// ===== send-cancellation-email/refund-split.ts =====
// Oprava i3 (2026-11-07, verify:ux) — storno rezervace placené částečně kartou a částečně převodem (doplatek úpravy
// převodem / QR): process-refund vrátí kartu Stripem a na převodem placenou část vystaví ruční dobropis (refund_pending,
// Fio příkaz). Mail dřív říkal jen „Vratku 3 500 Kč dokončuje obsluha – potvrzení pošleme zvlášť“ (ani slovo o 3 000
// na kartě, přiložen jen nejnovější dobropis, žádné „zvlášť“ neexistuje), po odeslání přes Fio zase „celých 3 500 na
// kartu“. Teď se odstavec o vratce skládá z živých dobropisů TOHOTO storna: kartové (stripe_refund_id) → „vráceno na
// kartu“, ruční → „pošleme převodem do 14 dnů“ / „odeslali jsme převodem“ (fio_payment_orders 'submitted').
// deno-lint-ignore no-explicit-any
type Sb = any

export type RefundSplit = { cardCzk: number; bankCzk: number; bankSent: boolean; cnIds: string[] }
const fmt = (n: number) => n.toLocaleString('cs-CZ')
/** Dobropis patří k tomuto stornu, vznikl-li nejdřív CLOCK_SLACK před bookings.cancelled_at (Velín: čas prohlížeče). */
const CLOCK_SLACK_MS = 120_000

const SPLIT: Record<string, (c: string, b: string, sent: boolean) => string> = {
  cs: (c, b, s) => `Vratka: <strong>${c} Kč</strong> jsme vrátili na vaši platební kartu (peníze obvykle dorazí do 5–10 pracovních dnů) a <strong>${b} Kč</strong> ${s ? 'jsme vám odeslali převodem na bankovní účet' : 'vám pošleme převodem na bankovní účet do 14 dnů'}. Dobropisy najdete v příloze.`,
  en: (c, b, s) => `Refund: <strong>${c} CZK</strong> has been returned to your payment card (funds typically arrive within 5–10 business days) and <strong>${b} CZK</strong> ${s ? 'has been sent to your bank account by transfer' : 'will be sent to your bank account by transfer within 14 days'}. The credit notes are attached.`,
  de: (c, b, s) => `Rückerstattung: <strong>${c} CZK</strong> wurden auf Ihre Zahlungskarte zurückerstattet (der Betrag erscheint in der Regel innerhalb von 5–10 Werktagen) und <strong>${b} CZK</strong> ${s ? 'haben wir Ihnen per Überweisung auf Ihr Bankkonto gesendet' : 'senden wir Ihnen innerhalb von 14 Tagen per Überweisung auf Ihr Bankkonto'}. Die Gutschriften finden Sie im Anhang.`,
  nl: (c, b, s) => `Terugbetaling: <strong>${c} CZK</strong> is teruggeboekt op je betaalkaart (het bedrag verschijnt doorgaans binnen 5–10 werkdagen) en <strong>${b} CZK</strong> ${s ? 'hebben we per overschrijving naar je bankrekening gestuurd' : 'sturen we binnen 14 dagen per overschrijving naar je bankrekening'}. De creditnota's vind je in de bijlage.`,
  es: (c, b, s) => `Reembolso: <strong>${c} CZK</strong> se han devuelto a tu tarjeta (el importe suele llegar en 5–10 días hábiles) y <strong>${b} CZK</strong> ${s ? 'te los hemos enviado por transferencia a tu cuenta bancaria' : 'te los enviaremos por transferencia a tu cuenta bancaria en un plazo de 14 días'}. Las notas de crédito están adjuntas.`,
  fr: (c, b, s) => `Remboursement : <strong>${c} CZK</strong> ont été remboursés sur votre carte (la somme arrive généralement sous 5 à 10 jours ouvrés) et <strong>${b} CZK</strong> ${s ? 'vous ont été envoyés par virement sur votre compte bancaire' : 'vous seront envoyés par virement sur votre compte bancaire sous 14 jours'}. Les avoirs sont joints.`,
  pl: (c, b, s) => `Zwrot: <strong>${c} CZK</strong> zwróciliśmy na Twoją kartę płatniczą (środki zwykle pojawiają się w ciągu 5–10 dni roboczych), a <strong>${b} CZK</strong> ${s ? 'wysłaliśmy przelewem na Twoje konto bankowe' : 'wyślemy przelewem na Twoje konto bankowe w ciągu 14 dni'}. Noty kredytowe znajdziesz w załączniku.`,
  uk: (c, b, s) => `Повернення: <strong>${c} CZK</strong> повернуто на вашу платіжну картку (кошти зазвичай надходять протягом 5–10 робочих днів), а <strong>${b} CZK</strong> ${s ? 'ми надіслали банківським переказом на ваш рахунок' : 'надішлемо банківським переказом на ваш рахунок протягом 14 днів'}. Кредит-ноти знайдете у вкладенні.`,
}

/** Odstavec o vratce rozdělené na kartu a převod; `informal` = tykání (výpůjčka výbavy, jen cs). */
export function refundSplitNote(lang: string, s: RefundSplit, o: { informal?: boolean } = {}): string {
  const c = fmt(s.cardCzk), b = fmt(s.bankCzk)
  if (o.informal && (lang === 'cs' || !(lang in SPLIT))) {
    return `Vratka: <strong>${c} Kč</strong> jsme vrátili na tvou platební kartu (peníze obvykle dorazí do 5–10 pracovních dnů) a <strong>${b} Kč</strong> ${s.bankSent ? 'jsme ti odeslali převodem na bankovní účet' : 'ti pošleme převodem na bankovní účet do 14 dnů'}. Dobropisy najdeš v příloze.`
  }
  return (SPLIT[lang] || SPLIT.cs)(c, b, s.bankSent)
}

/** Živé dobropisy TOHOTO storna (vznikly od bookings.cancelled_at − 2 min): kartové vs. ruční + stav Fio příkazu. null = nečitelné. */
export async function loadRefundSplit(sb: Sb, bookingId: string): Promise<RefundSplit | null> {
  try {
    const { data: bk } = await sb.from('bookings').select('cancelled_at').eq('id', bookingId).maybeSingle()
    const since = Date.parse(String(bk?.cancelled_at || ''))
    if (!Number.isFinite(since)) return null
    const { data: cns, error } = await sb.from('invoices').select('id, total, stripe_refund_id, created_at')
      .eq('booking_id', bookingId).eq('type', 'credit_note').neq('status', 'cancelled')
      .gte('created_at', new Date(since - CLOCK_SLACK_MS).toISOString())
    if (error) return null
    let card = 0, bank = 0
    const manualIds: string[] = [], ids: string[] = []
    for (const c of (cns || []) as Array<{ id: string; total: unknown; stripe_refund_id: unknown }>) {
      const a = Math.abs(Number(c.total) || 0)
      ids.push(c.id)
      if (c.stripe_refund_id) card += a
      else { bank += a; manualIds.push(c.id) }
    }
    let bankSent = false
    if (manualIds.length) {
      const { data: fo } = await sb.from('fio_payment_orders').select('credit_note_id, status').in('credit_note_id', manualIds)
      const sent = new Set(((fo || []) as Array<{ credit_note_id: string; status: string }>).filter((x) => x.status === 'submitted').map((x) => x.credit_note_id))
      bankSent = manualIds.every((id) => sent.has(id))
    }
    return { cardCzk: Math.round(card * 100) / 100, bankCzk: Math.round(bank * 100) / 100, bankSent, cnIds: ids }
  } catch { return null }
}
