// ===== webhook-receiver/late-payment.ts =====
// Pozdní platba ZRUŠENÉ rezervace (oprava 2026-10-16): cron zrušil nezaplacenou
// rezervaci během placení a confirm_payment ji už nedokázal oživit (motorku mezitím
// zarezervoval někdo jiný). Peníze nesmí zůstat stržené za rezervaci, která neplatí →
// automatická vratka celé platby (jednou: Stripe idempotency klíč) + upozornění obsluhy.
import type Stripe from 'https://esm.sh/stripe@14'

// deno-lint-ignore no-explicit-any
type Sb = any

const OPS_EMAIL = 'info@motogo24.cz'

export async function refundLatePaymentOnCancelled(sb: Sb, stripe: Stripe, bookingId: string, piId: string): Promise<boolean> {
  let refunded = false
  let errMsg: string | null = null
  try {
    await stripe.refunds.create(
      { payment_intent: piId, metadata: { booking_id: bookingId, reason: 'late_payment_cancelled_booking' } },
      { idempotencyKey: `mg-late-cancelled-${piId}` },
    )
    refunded = true
  } catch (e) { errMsg = (e as Error).message }
  try {
    await sb.from('debug_log').insert({
      source: 'webhook-receiver', action: refunded ? 'late_payment_refunded' : 'late_payment_refund_failed',
      component: 'stripe', status: refunded ? 'warning' : 'error', error_message: errMsg,
      request_data: { booking_id: bookingId, payment_intent_id: piId },
    })
  } catch { /* ignore */ }
  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const num = bookingId.slice(-8).toUpperCase()
    await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({
        to: OPS_EMAIL,
        subject: `⚠️ Platba zrušené rezervace #${num} — ${refunded ? 'automaticky vrácena' : 'VRAŤTE RUČNĚ'}`,
        raw_html: `<h2 style="margin:0 0 8px;font-size:18px">Platba dorazila k už zrušené rezervaci #${num}</h2>`
          + `<p style="margin:0 0 8px">Rezervaci zrušil automat (nezaplaceno včas) a motorku si mezitím zarezervoval někdo jiný, takže ji nešlo obnovit.</p>`
          + `<p style="margin:0 0 8px">${refunded ? `Platba ${piId} byla zákazníkovi automaticky vrácena v plné výši.` : `Automatická vratka platby ${piId} selhala (${errMsg || 'neznámá chyba'}) — vraťte ji prosím ručně ve Stripe.`}</p>`
          + `<p style="margin:0;color:#6b7280;font-size:12px">Detail: Velín → Debug log, akce late_payment_refunded.</p>`,
      }),
    })
  } catch { /* ignore */ }
  return refunded
}
