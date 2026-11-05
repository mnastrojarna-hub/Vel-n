// ===== webhook-receiver/refund-updated.ts =====
// Oprava i2 (2026-11-05): Stripe vratka vytvořená jako „pending“ (nízký zůstatek účtu) — process-refund zapíše
// 'refund_pending'; charge.refunded dorazí ještě s pending vratkou (syncRefundBooking mění stav jen z 'paid') a
// když vratka později uspěje, Stripe pošle `charge.refund.updated` / `refund.updated`, které se dřív nezpracovávaly
// → rezervace zůstala v „Čeká na vrácení“ napořád (Velín sváděl k další vratce). Teď:
//  • status 'succeeded' → rezervace s touto vratkou (bookings.stripe_refund_id = refund.id, nebo metadata
//    mg_booking_id) ve stavu 'refund_pending' → compare-and-set na 'refunded' (na platbách V CENĚ rezervace nic
//    nezbývá — staffFullBalanceHaleru jako process-refund) / 'partial_refund' (něco zbývá, nebo nelze zjistit).
//    Živý RUČNÍ dobropis (část ceny placená převodem — obsluha ji teprve posílá) → stav nechat, jen záznam.
//  • status 'failed' / 'canceled' → peníze NEodešly: debug_log error + mail obsluze (dobropis je třeba zrušit,
//    vratku zopakovat); stav rezervace se nemění (zůstává „Čeká na vrácení“).
// Stripe endpoint musí události `charge.refund.updated` (případně `refund.updated`) odesílat — STATE_5.
import { staffFullBalanceHaleru, type OtherIntentsStripe } from '../process-refund/other-intents.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
type RefundObj = { id: string; status?: string | null; amount?: number | null; payment_intent?: unknown; metadata?: Record<string, string> | null }
const OPS_EMAIL = 'info@motogo24.cz'

async function log(sb: Sb, action: string, status: string, data: Record<string, unknown>, err?: string) {
  try {
    await sb.from('debug_log').insert({ source: 'webhook-receiver', action, component: 'stripe', status, request_data: data, ...(err ? { error_message: err } : {}) })
  } catch { /* ignore */ }
}

async function opsMail(subject: string, html: string) {
  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ to: OPS_EMAIL, subject, raw_html: html }),
    })
  } catch { /* ignore */ }
}

/** Rezervace, ke které vratka patří (uložená vratka, nebo metadata naší vratky). */
async function bookingOfRefund(sb: Sb, r: RefundObj): Promise<Record<string, any> | null> {
  const cols = 'id, payment_status, stripe_refund_id, stripe_payment_intent_id'
  const { data: byId } = await sb.from('bookings').select(cols).eq('stripe_refund_id', r.id).maybeSingle()
  if (byId) return byId
  const bid = (r.metadata || {}).mg_booking_id
  if (bid) {
    const { data: byMd } = await sb.from('bookings').select(cols).eq('id', bid).maybeSingle()
    if (byMd) return byMd
  }
  return null
}

export async function onRefundUpdated(sb: Sb, stripe: OtherIntentsStripe, r: RefundObj): Promise<void> {
  const status = String(r.status || '')
  const bk = await bookingOfRefund(sb, r)
  if (!bk) { await log(sb, 'refund_updated_no_booking', 'info', { refund_id: r.id, status }); return }
  const num = String(bk.id).slice(-8).toUpperCase()
  if (status === 'failed' || status === 'canceled') {
    await log(sb, 'refund_updated_failed', 'error', { booking_id: bk.id, refund_id: r.id, status, amount: r.amount ?? null, payment_status: bk.payment_status },
      `Stripe vratka ${r.id} skončila '${status}' — peníze zákazníkovi NEODEŠLY.`)
    await opsMail(`⚠️ Vratka ${Number(r.amount || 0) / 100} Kč k rezervaci #${num} ve Stripe SELHALA (${status})`,
      `<p>Stripe vratka <code>${r.id}</code> (${Number(r.amount || 0) / 100} Kč) k rezervaci <strong>#${num}</strong> (${bk.id}) skončila stavem <strong>${status}</strong> — peníze zákazníkovi neodešly.</p>`
      + '<p>Rezervace zůstává ve stavu „Čeká na vrácení“. Zrušte dobropis k této vratce ve Velíně a vratku zopakujte (Stripe / převodem).</p>')
    return
  }
  if (status !== 'succeeded') { await log(sb, 'refund_updated_ignored', 'info', { booking_id: bk.id, refund_id: r.id, status }); return }
  if (bk.payment_status !== 'refund_pending') {
    await log(sb, 'refund_updated_no_change', 'info', { booking_id: bk.id, refund_id: r.id, payment_status: bk.payment_status }); return
  }
  // Ruční část (převodem) teprve posílá obsluha → „Čeká na vrácení“ je správně.
  try {
    const { data: man } = await sb.from('invoices').select('id').eq('booking_id', bk.id).eq('type', 'credit_note')
      .neq('status', 'cancelled').is('stripe_refund_id', null).limit(1)
    if (man?.length) { await log(sb, 'refund_updated_manual_pending', 'info', { booking_id: bk.id, refund_id: r.id, manual_credit_note_id: man[0].id }); return }
  } catch { /* bez údaje → dorovnat */ }
  let left: number | null = null
  try {
    const storedPi = bk.stripe_payment_intent_id && stripe.paymentIntents.retrieve ? await stripe.paymentIntents.retrieve(bk.stripe_payment_intent_id) : null
    left = await staffFullBalanceHaleru(stripe, sb, { bookingId: bk.id, storedPi, storedRefunds: null })
  } catch (e) { console.warn('[webhook] refund.updated balance failed:', (e as Error).message) }
  const next = left === 0 ? 'refunded' : 'partial_refund'
  const { data: upd, error } = await sb.from('bookings').update({ payment_status: next }).eq('id', bk.id).eq('payment_status', 'refund_pending').select('id')
  const written = !error && Array.isArray(upd) && upd.length > 0
  await log(sb, 'refund_updated_status_synced', written ? 'ok' : 'info', { booking_id: bk.id, refund_id: r.id, left_haleru: left, payment_status: next, written })
}
