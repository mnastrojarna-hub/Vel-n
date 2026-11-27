// ===== fio-sync/confirm-order.ts =====
// Objednávka e-shopu / DÁRKOVÝ POUKAZ zaplacený bankovním převodem. Potvrzení dělá STEJNÁ rutina jako
// po platbě kartou (Stripe webhook): webhook-receiver/payment-confirmers.ts → confirmShopPayment
// (RPC confirm_shop_payment → DB triggery vystaví poukaz a zapíší použití slevového kódu → doklad →
// e-mail voucher_purchased). Tady se jen rozhodne, JESTLI se smí potvrdit (částka, duplicita, stav).
// Poukaz tak vznikne až po připsání peněz. Objednávka po 7 dnech nevyprší — pozdější platba se uzná
// (nic se nedrží); požadavek na platbu (bank_payment_requests) se jen označí jako zaplacený.
import { confirmShopPayment } from '../webhook-receiver/payment-confirmers.ts'
import { audit, type Ctx, debugLog, fmtAmount, type Outcome, RetryError, type Row, short, type Tx } from './util.ts'
import { notifyDone, notifyReview, notifyUnderpaid } from './ops-mail.ts'
import { confirmedByOther, priorPartial } from './partials.ts'
import type { PairOpts } from './confirm-booking.ts'

export const ORDER_SELECT = 'id, order_number, status, payment_status, payment_method, total, customer_name, customer_email'

export async function handleOrder(ctx: Ctx, p: Tx, order: Row, request: Row | null, o: PairOpts): Promise<Outcome> {
  const { sb, caps, env } = ctx
  const oId = String(order.id)
  const label = 'objednávka ' + (order.order_number || '#' + short(oId))
  // QR nesl částku požadavku (cena při objednání, včetně slevového kódu); bez požadavku cena objednávky.
  const expected = Number(request?.amount ?? order.total) || 0
  const base = { orderId: oId, requestId: request ? String(request.id) : null, targetType: 'order' as const, expected }

  if (order.payment_status === 'paid') {
    const other = await confirmedByOther(ctx, p, 'order', oId, 'confirmed_order')
    if (other != null || String(order.payment_method || '') !== 'bank_transfer') {
      await notifyReview(env, p, 'duplicitní platba', `${cap(label)} už je zaplacená (${other != null ? 'pohybem FIO ' + other : 'jiným způsobem: ' + (order.payment_method || '—')}). Tato platba je navíc — vraťte ji zákazníkovi převodem.`)
      return { ...base, status: 'needs_review', reason: 'duplicate', note: 'duplicitní platba — objednávka už je zaplacená, vraťte' }
    }
    return { ...base, status: 'already_paid', note: 'objednávka už zaplacená' }
  }
  const st = String(order.status || '')
  if (['cancelled', 'refunded', 'returned'].includes(st)) {
    await notifyReview(env, p, 'platba ke zrušené objednávce', `${cap(label)} je ve stavu „${st}“ — platba se nepotvrdila. Vraťte ji zákazníkovi, nebo rozhodněte ručně.`)
    return { ...base, status: 'needs_review', reason: 'target_closed', note: `objednávka ve stavu ${st}` }
  }

  const part = await priorPartial(ctx, p, 'order', oId)
  const received = p.amount + part.sum
  if (received + 0.01 < expected && !o.accept) {
    await notifyUnderpaid(env, p, label, expected, received)
    return { ...base, status: 'amount_mismatch', reason: 'underpaid', note: `přišlo ${part.ids.length ? 'celkem ' : ''}${fmtAmount(received)}, cena ${fmtAmount(expected)} Kč` }
  }

  // ── Potvrzení: stejná rutina jako po kartě (jen způsob platby 'bank_transfer') ──
  await confirmShopPayment(sb, oId, 'FIO ' + p.fio_id, null, 'bank_transfer')
  const { data: post, error: postErr } = await sb.from('shop_orders').select('payment_status').eq('id', oId).maybeSingle()
  if (postErr || (post as { payment_status?: string } | null)?.payment_status !== 'paid') {
    // confirmShopPayment chyby jen loguje → ověřit výsledek; nepotvrzeno = zkusit znovu při dalším běhu
    throw new RetryError('confirm_shop_payment: objednávka se nepotvrdila' + (postErr ? ' (' + postErr.message + ')' : ''))
  }

  if (caps.requests) {
    try {
      let q = sb.from('bank_payment_requests')
        .update({ status: 'paid', paid_at: new Date().toISOString(), fio_id: p.fio_id, result: { state: 'paid' } })
      q = request ? q.eq('id', request.id) : q.eq('order_id', oId)
      await q.in('status', ['pending', 'expired', 'cancelled'])
    } catch { /* ignore — požadavek jen přestane „čekat“ */ }
  }
  await audit(sb, 'shop_order_payment_confirmed_fio', 'shop_order', oId,
    { fio_id: p.fio_id, amount: p.amount, vs: o.vs, paid_date: p.tx_date, method: 'bank_transfer' })
  await debugLog(sb, 'order_confirmed', 'ok', { fio_id: p.fio_id, order_id: oId, amount: p.amount, vs: o.vs })

  const overpay = received > expected + 0.01
  const under = received + 0.01 < expected
  await notifyDone(env, p, `Platba za ${label} potvrzena automaticky`,
    `Příchozí platba byla spárována s objednávkou <strong>${order.order_number || '#' + short(oId)}</strong> a potvrzena stejně jako platba kartou (doklad a e-mail zákazníkovi — u dárkového poukazu i samotný poukaz — odešly automaticky).`,
    expected, overpay)
  return { ...base, status: 'confirmed_order', absorbed: part.ids,
    reason: overpay ? 'overpaid' : under ? 'accepted_lower' : o.manual ? 'manual' : null,
    followup: overpay ? 'overpaid' : null,
    note: overpay ? `přeplatek: přišlo ${fmtAmount(received)}, cena ${fmtAmount(expected)} Kč`
      : under ? `obsluha přijala nižší částku: ${fmtAmount(received)} z ${fmtAmount(expected)} Kč`
      : o.manual ? 'spárováno ručně' : null }
}

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)
