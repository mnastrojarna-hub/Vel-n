// ===== webhook-receiver/late-payment.ts =====
// Pozdní platba ZRUŠENÉ rezervace (oprava 2026-10-16): cron zrušil nezaplacenou
// rezervaci během placení a confirm_payment ji už nedokázal oživit (motorku mezitím
// zarezervoval někdo jiný). Peníze nesmí zůstat stržené za rezervaci, která neplatí →
// automatická vratka celé platby (jednou: Stripe idempotency klíč) + upozornění obsluhy.
// Oprava i3 (2026-11-07, verify:ux): platba s přibalenou e-shop objednávkou (web checkout, metadata.shop_order_id) —
// webhook objednávku dál potvrzuje (doklad, mail, expedice), takže se vrací JEN část za rezervaci (zboží + doprava
// + jejich podíl na dorovnání na 15 Kč zůstávají); dřív vratka celé platby a zboží odešlo zdarma. Vlastní
// idempotency klíč (…-booking), mail obsluze uvádí částku i ponechanou objednávku.
import type Stripe from 'https://esm.sh/stripe@14'

// deno-lint-ignore no-explicit-any
type Sb = any

const OPS_EMAIL = 'info@motogo24.cz'

/** Část platby za REZERVACI (haléře) u platby s přibalenou objednávkou: přijato − zboží (Σ položek s cenou > 0) − doprava
 *  − podíl zboží na dorovnání (metadata.card_rounding, poměrně k ceně před dorovnáním). null = nelze spočítat. */
export async function lateBookingPartHaleru(sb: Sb, stripe: Stripe, piId: string, shopOrderId: string): Promise<{ bookingH: number; shopH: number; orderNumber: string | null } | null> {
  try {
    const pi = await stripe.paymentIntents.retrieve(piId)
    const received = Number(pi?.amount_received || 0)
    const { data: so, error: e1 } = await sb.from('shop_orders').select('order_number, shipping_cost').eq('id', shopOrderId).maybeSingle()
    const { data: items, error: e2 } = await sb.from('shop_order_items').select('quantity, unit_price').eq('order_id', shopOrderId)
    if (e1 || e2 || !so || !(received > 0)) return null
    const goodsH = ((items || []) as Array<{ quantity?: unknown; unit_price?: unknown }>)
      .reduce((s, it) => s + (Number(it.unit_price) > 0 ? Math.round(Number(it.unit_price) * 100) * (Number(it.quantity) || 1) : 0), 0)
    const shopBaseH = goodsH + Math.max(0, Math.round((Number(so.shipping_cost) || 0) * 100))
    const roundH = Math.max(0, Math.round((Number((pi.metadata || {}).card_rounding) || 0) * 100))
    const dueH = received - roundH
    const shareH = roundH > 0 && dueH > 0 ? Math.round(roundH * Math.min(shopBaseH, dueH) / dueH) : 0
    const shopH = Math.min(received, shopBaseH + shareH)
    return { bookingH: Math.max(0, received - shopH), shopH, orderNumber: (so.order_number as string) || null }
  } catch { return null }
}

export async function refundLatePaymentOnCancelled(sb: Sb, stripe: Stripe, bookingId: string, piId: string,
  o: { shopOrderId?: string | null } = {}): Promise<boolean> {
  let refunded = false
  let errMsg: string | null = null
  const part = o.shopOrderId ? await lateBookingPartHaleru(sb, stripe, piId, o.shopOrderId) : null
  const bundled = !!o.shopOrderId
  const nothing = bundled && part != null && part.bookingH <= 0
  try {
    if (bundled && part == null) throw new Error('část platby za rezervaci nejde spočítat (objednávka e-shopu nečitelná)')
    if (!nothing) {
      await stripe.refunds.create(
        // mg_source: charge.refunded ji pozná jako NAŠI vratku (ne „storno přes Stripe portál") —
        // stav rezervace nemění, žádný dobropis (k platbě nevznikl doklad) ani storno mail.
        { payment_intent: piId, ...(bundled ? { amount: part!.bookingH } : {}),
          metadata: { mg_source: 'late_payment', booking_id: bookingId, reason: 'late_payment_cancelled_booking', ...(bundled ? { shop_order_id: String(o.shopOrderId) } : {}) } },
        { idempotencyKey: bundled ? `mg-late-cancelled-${piId}-booking` : `mg-late-cancelled-${piId}` },
      )
    }
    refunded = true
  } catch (e) { errMsg = (e as Error).message }
  try {
    await sb.from('debug_log').insert({
      source: 'webhook-receiver', action: refunded ? 'late_payment_refunded' : 'late_payment_refund_failed',
      component: 'stripe', status: refunded ? 'warning' : 'error', error_message: errMsg,
      request_data: { booking_id: bookingId, payment_intent_id: piId, shop_order_id: o.shopOrderId || null,
        refund_haleru: bundled ? (part?.bookingH ?? null) : 'full', shop_kept_haleru: part?.shopH ?? null },
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
          + `<p style="margin:0 0 8px">${!refunded
            ? `Automatická vratka platby ${piId} selhala (${errMsg || 'neznámá chyba'}) — vraťte ${bundled ? 'část za rezervaci (bez zboží e-shopu a dopravy)' : 'ji'} prosím ručně ve Stripe.`
            : !bundled ? `Platba ${piId} byla zákazníkovi automaticky vrácena v plné výši.`
            : nothing ? `Platba ${piId} byla jen za zboží e-shopu — za rezervaci se nic nevracelo.`
            : `Z platby ${piId} se zákazníkovi automaticky vrátila jen část za rezervaci: <strong>${part!.bookingH / 100} Kč</strong>.`}</p>`
          + (bundled ? `<p style="margin:0 0 8px">Přibalená objednávka e-shopu${part?.orderNumber ? ` ${part.orderNumber}` : ''} (${part ? `${part.shopH / 100} Kč vč. dopravy` : 'částka nezjištěna'}) zůstává zaplacená a vyřizuje se běžně (doklad, expedice). Pokud ji zákazník nechce, stornujte ji ve Velíně.</p>` : '')
          + `<p style="margin:0;color:#6b7280;font-size:12px">Detail: Velín → Debug log, akce late_payment_refunded.</p>`,
      }),
    })
  } catch { /* ignore */ }
  return refunded
}
