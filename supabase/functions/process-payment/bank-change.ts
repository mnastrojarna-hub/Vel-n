// ===== process-payment/bank-change.ts =====
// WEB: doplatek ÚPRAVY rezervace placený QR kódem / převodem (`pay_method:'bank'`, type 'extension',
// mode 'checkout'). Volá se z index.ts AŽ PO všech stávajících kontrolách (vlastník, zastaralý základ,
// serverový dry-run, vozík, částka) — místo založení Stripe Checkout Session se naceněná změna uloží jako
// čekající požadavek (bank_payment_requests, lhůta 60 minut) a zákazník dostane QR + pokyny (odpověď i
// e-mail v jeho jazyce). Rezervace se NEMĚNÍ a nový termín se neblokuje; změnu zapíše fio-sync po
// připsání platby stejnou rutinou jako po kartě (applyPaidExtension). Bez minima karty: 1–15 Kč se platí
// přesně; do 1 Kč se odpouští jako dnes (řeší index.ts ještě před voláním).
// Bez nasazeného SQL → 503 bank_unavailable (web nabídne kartu), nic se nezakládá.
import { loadBookingLanguage, pickQrLang } from '../qr-payment/texts.ts'
import { bankSqlMissing, createBankRequest, sendBankRequestMail } from '../_shared/bank-request.ts'
import { refuse, respond } from './refusals.ts'

// deno-lint-ignore no-explicit-any
type Sb = any

export const BANK_CHANGE_HOLD_MIN = 60
const TXT = {
  bank_unavailable: 'Platba převodem teď není dostupná – zaplať prosím kartou. Nic jsme nezměnili.',
  bank_not_allowed: 'Platbu převodem lze zvolit jen při úpravě rezervace na webu. Nic jsme nezměnili.',
  wrong_status: 'Rezervaci v tomto stavu už nelze upravit (stornovaná nebo ukončená). Nic jsme nezměnili.',
}

/** `pay_method:'bank'` mimo webový checkout doplatku / objednávky. */
export const bankNotAllowed = () => refuse(400, 'bank_not_allowed', {}, TXT.bank_not_allowed)

/** Druh změny pro zobrazení (Velín, web): výměna / výbava / jiná motorka / úprava. */
export function bankChangeKind(change: Record<string, unknown>): 'swap' | 'gear' | 'moto' | 'edit' {
  if (change._swap && typeof change._swap === 'object') return 'swap'
  if (change._gear && typeof change._gear === 'object') return 'gear'
  return change.p_new_moto_id || (typeof change.moto_id === 'string' && change.moto_id) ? 'moto' : 'edit'
}

export async function bankChangeFlow(sb: Sb, a: {
  bookingId: string; userId: string | null; change: Record<string, unknown>
  /** výsledek serverového dry-runu (totéž, co jde u karty do metadata.srv) */
  srv: string | null
  /** přesný doplatek v Kč (server) */
  due: number
  locale: unknown
}): Promise<Response> {
  const number = a.bookingId.slice(-8).toUpperCase()
  const lang = pickQrLang(a.locale, await loadBookingLanguage(sb, a.bookingId))
  const res = await createBankRequest(sb, {
    kind: 'booking_change', bookingId: a.bookingId, amount: a.due, holdMinutes: BANK_CHANGE_HOLD_MIN,
    chg: JSON.stringify(a.change), srv: a.srv, changeKind: bankChangeKind(a.change), lang, createdBy: a.userId, number,
  })
  if (!res.ok) {
    if (res.code === 'wrong_status' || res.code === 'not_found') return refuse(409, 'wrong_status', {}, TXT.wrong_status)
    if (res.code === 'invalid_amount') return refuse(400, 'invalid_amount')
    return refuse(503, 'bank_unavailable', {}, TXT.bank_unavailable)
  }
  if (!res.reused) {
    let email = '', name = ''
    try {
      const { data } = await sb.from('bookings').select('id, profiles(full_name, email)').eq('id', a.bookingId).maybeSingle()
      const p = (Array.isArray(data?.profiles) ? data.profiles[0] : data?.profiles) as { full_name?: string; email?: string } | null
      email = p?.email || ''; name = p?.full_name || ''
    } catch { /* bez e-mailu — údaje má zákazník na stránce */ }
    await sendBankRequestMail({ kind: 'booking_change', lang, details: res.details, deadline: res.deadlineText, email, name, number, bookingId: a.bookingId })
    try {
      await sb.from('debug_log').insert({ source: 'process-payment', action: 'bank_change_request_created', component: 'extension', status: 'ok',
        request_data: { booking_id: a.bookingId, request_id: res.requestId, amount: res.details.amount, vs: res.details.vs } })
    } catch { /* ignore */ }
  }
  return respond(200, {
    success: true, pay_method: 'bank', status: 'pending', reused: res.reused,
    request_id: res.requestId, booking_id: a.bookingId, booking_number: number, hold_minutes: BANK_CHANGE_HOLD_MIN,
    ...res.details, deadline_text: res.deadlineText,
  })
}

/** Zákazník začal platit TUTÉŽ rezervaci kartou → čekající požadavek na převod zrušit (pozdější převod
 *  pak jde obsluze, nezapíše se druhá změna). Bez SQL / bez požadavku nic nedělá; nikdy nevyhodí. */
export async function cancelPendingBankChange(sb: Sb, bookingId: string): Promise<void> {
  try {
    const { data, error } = await sb.from('bank_payment_requests').select('id').eq('booking_id', bookingId).eq('status', 'pending').limit(1)
    if (error || !Array.isArray(data) || !data.length) { if (error && !bankSqlMissing(error)) console.warn('[bank-change] lookup:', error.message); return }
    await sb.rpc('cancel_bank_payment_request', { p_request_id: (data[0] as { id: string }).id, p_note: 'zákazník zvolil platbu kartou' })
  } catch { /* ignore */ }
}
