// ===== process-payment/bank-shop.ts =====
// WEB: nákup DÁRKOVÉHO POUKAZU placený QR kódem / převodem (`pay_method:'bank'` u type 'shop', source 'web').
// Volá se z handleWebShopCheckout po ocenění (RPC quote_web_voucher_order — slevové kódy se počítají
// stejně jako u karty a platí cena z okamžiku objednávky). Objednávka se založí STEJNĚ jako u karty
// (voucher-order.ts, payment_method 'bank_transfer'), místo Stripe session vznikne požadavek na platbu
// (bank_payment_requests, lhůta 7 dní) + zálohová faktura s jeho VS + e-mail s QR a pokyny.
// POUKAZ NEVZNIKÁ — vystaví ho až potvrzení platby (fio-sync → confirmShopPayment, jako po kartě).
// Po 7 dnech požadavek vyprší (objednávka zůstává nezaplacená); pozdější platba se přesto uzná.
// Bez nasazeného SQL → 503 bank_unavailable PŘED založením objednávky (nic nevznikne).
import { normalizeQrLang } from '../qr-payment/texts.ts'
import { bankRequestsAvailable, createBankRequest, sendBankRequestMail } from '../_shared/bank-request.ts'
import { resolveReturnOrigin, resolveSiteLang, withLangParam } from './stripe-customer.ts'
import { respond } from './refusals.ts'
import { insertVoucherOrder, type VoucherOrderInput } from './voucher-order.ts'

// deno-lint-ignore no-explicit-any
type Sb = any

export const BANK_ORDER_HOLD_DAYS = 7
const UNAVAILABLE = 'Platba převodem teď není dostupná – zvolte prosím platbu kartou. Objednávka nevznikla.'

export async function bankVoucherCheckout(sb: Sb, v: Omit<VoucherOrderInput, 'paymentMethod'> & { origin: string | null | undefined }): Promise<Response> {
  if (!(await bankRequestsAvailable(sb))) return respond(503, { success: false, code: 'bank_unavailable', error: UNAVAILABLE })

  const ins = await insertVoucherOrder(sb, { ...v, paymentMethod: 'bank_transfer' })
  if (ins.error) return respond(500, { error: 'Order creation failed', details: ins.error })

  const lang = normalizeQrLang(resolveSiteLang(v.locale)) ?? 'cs'
  let orderNumber = v.orderId.slice(-8).toUpperCase()
  try {
    const { data } = await sb.from('shop_orders').select('order_number').eq('id', v.orderId).maybeSingle()
    if (data?.order_number) orderNumber = String(data.order_number)
  } catch { /* číslo objednávky doplní trigger; bez něj krátké id */ }

  const req = await createBankRequest(sb, { kind: 'shop_order', orderId: v.orderId, amount: v.amountCzk, holdMinutes: BANK_ORDER_HOLD_DAYS * 24 * 60, lang, number: orderNumber })
  if (!req.ok) {
    // požadavek nevznikl → objednávku nenechat viset jako „čeká na platbu“
    try { await sb.from('shop_orders').update({ status: 'cancelled', cancelled_at: new Date().toISOString(), notes: 'Platba převodem nedostupná — objednávka zrušena' }).eq('id', v.orderId).eq('payment_status', 'pending') } catch { /* ignore */ }
    return respond(503, { success: false, code: 'bank_unavailable', error: UNAVAILABLE })
  }

  // Zálohová faktura s VS požadavku (účetní doklad + příloha e-mailu); selhání platbu neblokuje.
  let invoice: { number: string | null; path: string | null } | null = null
  try {
    const url = Deno.env.get('SUPABASE_URL') ?? '', key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const gi = await fetch(`${url}/functions/v1/generate-invoice`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ type: 'shop_proforma', order_id: v.orderId, send_email: false, language: lang,
        variable_symbol: req.details.vs, due_note: `do ${BANK_ORDER_HOLD_DAYS} dnů od vystavení` }),
    })
    const gj = await gi.json().catch(() => ({}))
    if (gj?.success) invoice = { number: gj.number ?? null, path: gj.pdf_path ?? null }
    else console.warn('[bank-shop] generate-invoice:', JSON.stringify(gj))
  } catch (e) { console.warn('[bank-shop] ZF generation failed:', (e as Error).message) }

  if (!req.reused) {
    await sendBankRequestMail({ kind: 'shop_order', lang, details: req.details, deadline: req.deadlineText, email: v.customerEmail, name: v.customerName,
      number: orderNumber, orderId: v.orderId, invoice })
  }
  try {
    await sb.from('debug_log').insert({ source: 'process-payment', action: 'bank_order_request_created', component: 'voucher_checkout', status: 'ok',
      request_data: { order_id: v.orderId, request_id: req.requestId, amount: req.details.amount, vs: req.details.vs } })
  } catch { /* ignore */ }

  const origin = resolveReturnOrigin(v.origin, v.locale)
  return respond(200, {
    success: true, pay_method: 'bank', status: 'pending', order_id: v.orderId, order_number: orderNumber,
    request_id: req.requestId, hold_days: BANK_ORDER_HOLD_DAYS, ...req.details,
    invoice_number: invoice?.number ?? null, deadline_text: req.deadlineText,
    confirm_url: withLangParam(`${origin}/potvrzeni?order_id=${v.orderId}&flow=qr`, v.locale),
  })
}
