// ===== _shared/bank-request.ts =====
// Požadavek na platbu převodem / QR pro to, co nežije na řádku rezervace: objednávka (DÁRKOVÝ POUKAZ)
// a DOPLATEK úpravy rezervace z webu, který čeká na peníze (tabulka bank_payment_requests, SQL 20261130b).
//   createBankRequest  RPC create_bank_payment_request (VS ze sdílené sekvence booking_vs_seq; opakované
//                      odeslání téže objednávky / změny vrátí TENTÝŽ požadavek → reused, bez nového mailu)
//                      + platební údaje (účet / IBAN / banka VŽDY z app_settings.company_info, QR řetězec SPD)
//   sendBankRequestMail e-mail zákazníkovi s QR a pokyny v jeho jazyce: šablona shop_qr_payment /
//                      booking_change_qr_payment (send-email ji přeloží), záložní HTML v 8 jazycích
// Bez nasazeného SQL (RPC / tabulka neexistuje) vrací { ok:false, code:'bank_unavailable' } — volající
// nabídne platbu kartou; nic se nezakládá. Potvrzení platby dělá fio-sync (dispatch.ts).
import { loadCompany } from './company.ts'
import { buildSpd, qrBankDetails } from '../qr-payment/spd.ts'
import { invoiceSuffix, QR_TEXTS, type QrLang, spdMessage } from '../qr-payment/texts.ts'
import { QR_FALLBACK } from '../qr-payment/fallback-texts.ts'
import { fmtAmount, row } from '../qr-payment/fallback-html.ts'
import { BANK_TEXTS, deadlineLabel } from './bank-request-texts.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
export type BankKind = 'shop_order' | 'booking_change'

export type BankDetails = {
  vs: string; amount: number; currency: 'czk'
  account: string; iban: string; bank: string
  spd: string; qr_url: string; expires_at: string | null
}

/** Chybí tabulka / funkce (SQL 20261130b ještě není nasazené)? */
export function bankSqlMissing(e: { code?: string | null; message?: string | null } | null | undefined): boolean {
  return !!e && /PGRST20[245]|42P01|42703|42883|could not find the (function|table)|does not exist/i.test(`${e.code || ''} ${e.message || ''}`)
}

/** Je registr požadavků nasazený? (levný dotaz PŘED založením objednávky — bez něj se nic nezakládá) */
export async function bankRequestsAvailable(sb: Sb): Promise<boolean> {
  try {
    const { error } = await sb.from('bank_payment_requests').select('id').limit(1)
    return !error
  } catch { return false }
}

/** Zpráva pro příjemce v QR (jen ASCII bez „*“). */
export function bankSpdMessage(kind: BankKind, lang: QrLang, number: string): string {
  if (kind === 'booking_change') return spdMessage(lang, true, number)
  return ('MotoGo24 ' + BANK_TEXTS[lang].spdOrder + ' ' + number).replace(/[^\x20-\x29\x2B-\x7E]/g, '')
}

/** Platební údaje k VS a částce — účet, IBAN i banka z TÉHOŽ nastavení provozovatele. */
export async function bankDetails(sb: Sb, a: { vs: string; amount: number; message: string; expiresAt?: string | null }): Promise<BankDetails> {
  const { iban, account, bank } = qrBankDetails(await loadCompany(sb))
  const amount = Math.round((Number(a.amount) || 0) * 100) / 100
  const spd = buildSpd(iban, amount, a.vs, a.message)
  return { vs: a.vs, amount, currency: 'czk', account, iban, bank, spd,
    qr_url: 'https://api.qrserver.com/v1/create-qr-code/?size=280x280&data=' + encodeURIComponent(spd), expires_at: a.expiresAt ?? null }
}

export const deadlineText = (kind: BankKind, lang: QrLang, expiresAt: string | null): string => {
  if (!expiresAt) return ''
  return kind === 'booking_change' ? BANK_TEXTS[lang].changeDeadline(deadlineLabel(lang, expiresAt, 'time'))
    : BANK_TEXTS[lang].orderDeadline(deadlineLabel(lang, expiresAt, 'date'))
}

export type CreateArgs = {
  kind: BankKind; amount: number; lang: QrLang; holdMinutes: number
  orderId?: string | null; bookingId?: string | null
  chg?: string | null; srv?: string | null; changeKind?: string | null; createdBy?: string | null
  /** číslo do zprávy pro příjemce: číslo objednávky / krátké číslo rezervace */
  number: string
}
export type CreateResult =
  | { ok: true; reused: boolean; requestId: string; details: BankDetails; deadlineText: string }
  | { ok: false; code: string; detail?: string }

export async function createBankRequest(sb: Sb, a: CreateArgs): Promise<CreateResult> {
  let data: Record<string, unknown> | null = null
  try {
    const res = await sb.rpc('create_bank_payment_request', {
      p_kind: a.kind, p_amount: a.amount, p_booking_id: a.bookingId ?? null, p_order_id: a.orderId ?? null,
      p_hold_minutes: a.holdMinutes, p_chg: a.chg ?? null, p_srv: a.srv ?? null, p_change_kind: a.changeKind ?? null,
      p_language: a.lang, p_created_by: a.createdBy ?? null,
    })
    if (res.error) return { ok: false, code: 'bank_unavailable', detail: bankSqlMissing(res.error) ? 'sql_missing' : res.error.message }
    data = (res.data || null) as Record<string, unknown> | null
  } catch (e) { return { ok: false, code: 'bank_unavailable', detail: (e as Error).message } }
  if (!data || data.success !== true || !data.vs || !data.request_id) {
    return { ok: false, code: String(data?.error || 'bank_unavailable') }
  }
  const expiresAt = (data.expires_at as string) || null
  const details = await bankDetails(sb, { vs: String(data.vs), amount: Number(data.amount ?? a.amount), message: bankSpdMessage(a.kind, a.lang, a.number), expiresAt })
  return { ok: true, reused: data.reused === true, requestId: String(data.request_id), details, deadlineText: deadlineText(a.kind, a.lang, expiresAt) }
}

export type MailArgs = {
  kind: BankKind; lang: QrLang; details: BankDetails; deadline: string
  email: string; name: string; number: string
  bookingId?: string | null; orderId?: string | null
  invoice?: { number: string | null; path: string | null } | null
  env?: { url: string; key: string }
}

/** Záložní HTML (stejný vzhled jako šablony; použije se, když mail ze šablony neodešel). */
export function bankRequestFallbackHtml(a: MailArgs): string {
  const f = QR_FALLBACK[a.lang], t = BANK_TEXTS[a.lang], q = QR_TEXTS[a.lang], d = a.details
  const order = a.kind === 'shop_order'
  const intro = order ? q.thanks(a.name) + t.orderIntro(`<strong>${a.number}</strong>`)
    : q.surchargeLead(a.name) + f.surchargeIntro(`<strong>#${a.number}</strong>`) + ' <strong>' + t.changeNote + '</strong>'
  return `
  <h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">${order ? f.title : f.surchargeTitle}</h2>
  <p style="margin:0 0 16px;color:#374151;font-size:14px">${intro}</p>
  <div style="text-align:center;margin:0 0 16px"><img src="${d.qr_url}" alt="${f.qrAlt}" style="width:240px;height:240px;border:1px solid #e5e7eb;border-radius:12px"></div>
  <table style="width:100%;border-collapse:collapse;margin:0 0 14px">
    ${row(f.amount, fmtAmount(d.amount) + ' Kč', true)}
    ${row(f.account, d.account)}
    ${row('IBAN', d.iban.replace(/(.{4})/g, '$1 ').trim())}
    ${row(f.bank, d.bank)}
    ${row(f.vs, d.vs)}
  </table>
  <p style="margin:0 0 10px;padding:12px 14px;background:#fef2f2;border-radius:10px;color:#b91c1c;font-weight:700;font-size:14px">⏱ ${a.deadline}</p>
  <p style="margin:0;color:#374151;font-size:13px">${order ? t.orderAfter + invoiceSuffix(a.lang, a.invoice?.number ?? null) : t.changeAfter}</p>
  `
}

/** E-mail zákazníkovi: šablona (přeloží send-email), při neúspěchu záložní HTML. Nikdy nevyhodí. */
export async function sendBankRequestMail(a: MailArgs): Promise<boolean> {
  const url = a.env?.url ?? (Deno.env.get('SUPABASE_URL') || '')
  const key = a.env?.key ?? (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '')
  if (!a.email) return false
  const order = a.kind === 'shop_order'
  const d = a.details
  const attachment_paths = a.invoice?.path ? [{ filename: (a.invoice.number || 'zalohova-faktura') + '.pdf', path: a.invoice.path }] : []
  const ref = order ? { order_id: a.orderId ?? undefined } : { booking_id: a.bookingId ?? undefined }
  const post = (payload: Record<string, unknown>) => fetch(url + '/functions/v1/send-email', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + key, apikey: key },
    body: JSON.stringify(payload),
  })
  try {
    const r = await post({
      to: a.email, template_slug: order ? 'shop_qr_payment' : 'booking_change_qr_payment', language: a.lang, ...ref, attachment_paths,
      template_vars: {
        lead: order ? QR_TEXTS[a.lang].thanks(a.name) : QR_TEXTS[a.lang].surchargeLead(a.name),
        ...(order ? { order_number: a.number } : { booking_number: a.number }),
        qr_url: d.qr_url, amount: fmtAmount(d.amount) + ' Kč', account: d.account,
        iban: d.iban.replace(/(.{4})/g, '$1 ').trim(), bank: d.bank, vs: d.vs, deadline: a.deadline,
        invoice_suffix: invoiceSuffix(a.lang, a.invoice?.number ?? null),
      },
    })
    const rj = await r.json().catch(() => ({}))
    if ((rj as { success?: boolean })?.success) return true
    console.warn('[bank-request] template mail not sent:', JSON.stringify(rj))
  } catch (e) { console.warn('[bank-request] template mail error:', (e as Error).message) }
  try {
    const r = await post({
      to: a.email, ...ref, attachment_paths,
      subject: order ? BANK_TEXTS[a.lang].orderSubject(a.number) : QR_TEXTS[a.lang].subjectSurcharge(a.number),
      raw_html: bankRequestFallbackHtml(a),
    })
    return r.ok
  } catch (e) { console.warn('[bank-request] fallback mail failed:', (e as Error).message); return false }
}
