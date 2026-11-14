// ===== webhook-receiver/cancelled-payment.ts =====
// Oprava i5 (2026-11-07, verify:refunds V6 + verify:charges R1) — regrese i4: confirmBookingPayment u ZRUŠENÉ rezervace
// s platbou ve stavu refunded / partial_refund / refund_pending vrací 'skipped' (neoživovat — pozdní platba už vrácená,
// storno s vratkou) bez ohledu na to, KTERÁ platba událost nese. Druhá, skutečně NOVÁ platba (druhá záložka Checkoutu,
// karta u QR rezervace, která čeká na ruční vratku, nová platba po vrácené pozdní platbě) tak zůstala stržená bez vratky
// i bez mailu. Teď se platba události posoudí (stav ze Stripe, ne ze snímku události):
//  • 'handled' — už se vrací / vrátila (živá Stripe vratka platby, nebo záznam late_payment_refunded), nebo jde o
//    uloženou kartovou platbu rezervace zaplacenou PŘED stornem (znovu doručená událost — o ní rozhodlo storno),
//  • 'refund'  — zaplaceno PO stornu (čas charge > bookings.cancelled_at), nevráceno, bez duplicate_of → automatická
//    vratka jako pozdní platba (refundLatePaymentOnCancelled: klíč mg-late-cancelled-<pi> → jednou; mail obsluze),
//  • 'review'  — jinak (zaplaceno před stornem, ale rezervace o platbě neví / duplicita bez vratky) → mail obsluze
//    „zkontrolujte a vraťte“ (1× na platbu), nic automaticky.
// Chyba Stripe / DB → webhook odpoví 500 (Stripe událost doručí znovu).
import { refundLatePaymentOnCancelled } from './late-payment.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
// deno-lint-ignore no-explicit-any
type StripeLike = any
export type CancelledPaymentVerdict = 'handled' | 'refund' | 'review'

/** claim_email_send slug mailu obsluze (i6r1) — + id platby */
export const REVIEW_SLUG = 'ops_cancelled_payment_review:'
const MANUAL = ['bank_transfer', 'qr', 'cash', 'crypto', 'voucher', 'wire']
const live = (r: { status?: string | null }) => r.status === 'succeeded' || r.status === 'pending'

async function logged(sb: Sb, action: string, piId: string): Promise<boolean> {
  const { data, error } = await sb.from('debug_log').select('id').eq('source', 'webhook-receiver').eq('action', action)
    .eq('request_data->>payment_intent_id', piId).limit(1)
  if (error) throw new Error(`debug_log: ${error.message}`)
  return Array.isArray(data) && data.length > 0
}

/** Posouzení platby `piId` k zrušené rezervaci s vratkou (viz hlavička). Chyba čtení → výjimka. */
export async function cancelledPaymentVerdict(sb: Sb, stripe: StripeLike, bookingId: string, piId: string | null):
  Promise<{ verdict: CancelledPaymentVerdict; why: string; paidAtS?: number }> {
  if (!piId) return { verdict: 'handled', why: 'no_payment_intent' }
  if (await logged(sb, 'late_payment_refunded', piId)) return { verdict: 'handled', why: 'late_refund_logged' }
  const rl = await stripe.refunds.list({ payment_intent: piId, limit: 100 })
  if ((rl?.data || []).some(live)) return { verdict: 'handled', why: 'refunded' }
  const pi = await stripe.paymentIntents.retrieve(piId, { expand: ['latest_charge'] })
  let ch = pi?.latest_charge
  if (typeof ch === 'string' && stripe.charges?.retrieve) ch = await stripe.charges.retrieve(ch)
  const paidAtS = Number((ch && typeof ch === 'object' ? ch.created : null) || pi?.created || 0)
  const { data: bk, error } = await sb.from('bookings').select('cancelled_at, stripe_payment_intent_id, payment_method, pay_channel').eq('id', bookingId).maybeSingle()
  if (error) throw new Error(`bookings: ${error.message}`)
  const cancelledMs = Date.parse(String(bk?.cancelled_at || ''))
  if ((pi?.metadata || {}).duplicate_of) return { verdict: 'review', why: 'duplicate_unrefunded', paidAtS }
  if (Number.isFinite(cancelledMs) && paidAtS * 1000 > cancelledMs) return { verdict: 'refund', why: 'paid_after_cancel', paidAtS }
  const method = String(bk?.payment_method || '').toLowerCase().trim()
  const manual = MANUAL.includes(method) || (!method && bk?.pay_channel === 'qr')
  if (bk?.stripe_payment_intent_id === piId && !manual) return { verdict: 'handled', why: 'stored_card_payment', paidAtS }
  return { verdict: 'review', why: Number.isFinite(cancelledMs) ? 'paid_before_cancel_unknown' : 'cancel_time_unknown', paidAtS }
}

/** confirmBookingPayment vrátil 'skipped' → vratka nové platby / mail obsluze. Vrací true = webhook má odpovědět 500. */
export async function handleCancelledPayment(sb: Sb, stripe: StripeLike, bookingId: string, piId: string | null,
  o: { shopOrderId?: string | null; czkReceivedH?: number | null } = {}): Promise<boolean> {
  let v: Awaited<ReturnType<typeof cancelledPaymentVerdict>>
  try { v = await cancelledPaymentVerdict(sb, stripe, bookingId, piId) } catch (e) {
    try {
      await sb.from('debug_log').insert({ source: 'webhook-receiver', action: 'cancelled_payment_check_failed', component: 'stripe', status: 'error',
        error_message: (e as Error).message, request_data: { booking_id: bookingId, payment_intent_id: piId } })
    } catch { /* ignore */ }
    return true
  }
  let logId: string | null = null
  try {
    const { data: lg } = await sb.from('debug_log').insert({ source: 'webhook-receiver', action: `cancelled_payment_${v.verdict}`, component: 'stripe',
      status: v.verdict === 'handled' ? 'info' : 'warning', request_data: { booking_id: bookingId, payment_intent_id: piId, why: v.why, paid_at_s: v.paidAtS ?? null } })
      .select('id').single()
    logId = (lg as { id?: string } | null)?.id ?? null
  } catch { /* ignore */ }
  if (v.verdict === 'refund' && piId) { await refundLatePaymentOnCancelled(sb, stripe, bookingId, piId, { shopOrderId: o.shopOrderId || null, afterRefund: true, czkReceivedH: o.czkReceivedH ?? null }); return false }
  if (v.verdict !== 'review' || !piId) return false
  // mail 1× na platbu. Oprava i6r1 (verify:charges T1): atomický claim (claim_email_send, okno 1 rok) místo „vložit záznam
  // a přeskočit, je-li jich víc“ — checkout.session.completed a payment_intent.succeeded (< 1 s od sebe) dřív oba vložily
  // dřív, než kdokoli četl, oba viděly 2 záznamy a mail neodešel vůbec. RPC chybí / chyba → první záznam vyhrává.
  const slug = `${REVIEW_SLUG}${piId}`
  let claimed: boolean | null = null
  try {
    const { data, error } = await sb.rpc('claim_email_send', { p_booking_id: bookingId, p_slug: slug, p_window_minutes: 525600 })
    if (!error) claimed = data !== false
  } catch { /* fallback */ }
  if (claimed === false) return false
  if (claimed == null && logId) {
    try {
      const { data } = await sb.from('debug_log').select('id').eq('source', 'webhook-receiver').eq('action', 'cancelled_payment_review')
        .eq('request_data->>payment_intent_id', piId).order('created_at', { ascending: true }).order('id', { ascending: true }).limit(1)
      if (Array.isArray(data) && data[0] && data[0].id !== logId) return false
    } catch { /* raději mail */ }
  }
  let sent = false
  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const num = bookingId.slice(-8).toUpperCase()
    const res = await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ to: 'info@motogo24.cz', booking_id: bookingId,
        subject: `⚠️ Platba k zrušené rezervaci #${num} (už vracené) — zkontrolujte a vraťte`,
        raw_html: `<p style="margin:0 0 8px">Stripe potvrdil platbu <code>${piId}</code> k rezervaci <strong>#${num}</strong>, která je zrušená a její platba se už vrací / vrátila.</p>`
          + `<p style="margin:0 0 8px">Platbu nešlo jednoznačně přiřadit (${v.why === 'duplicate_unrefunded' ? 'duplicitní platba bez vratky' : 'zaplaceno před stornem, rezervace ji neeviduje'}) — automaticky se NEvrátila ani nepotvrdila.</p>`
          + '<p style="margin:0">Zkontrolujte ji ve Stripe; pokud k rezervaci nepatří, vraťte ji ručně (platba → Refund). Detail: Velín → Debug log, akce cancelled_payment_review.</p>' }),
    })
    sent = res.ok
  } catch { /* níže */ }
  if (sent) return false
  // mail neodešel → uvolnit claim / vlastní záznam a nechat Stripe událost doručit znovu (dřív se mail ztratil napořád)
  try {
    if (claimed) await sb.from('email_send_locks').delete().eq('booking_id', bookingId).eq('template_slug', slug)
    else if (logId) await sb.from('debug_log').delete().eq('id', logId)
  } catch { /* vyprší / ruční kontrola */ }
  return true
}
