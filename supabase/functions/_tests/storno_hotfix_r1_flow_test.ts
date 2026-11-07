// ===== _tests/storno_hotfix_r1_flow_test.ts =====
// HOTFIX storno 2026-10-29 — oprava r1 po adversariální verifikaci (flow testy celých handlerů):
//  • duplicita téhož požadavku obsluhy (dvojité odeslání storna, dvojklik „Potvrdit vrácení“) → jedna vratka,
//  • webhook charge.refunded nikdy nevrací (ruční vratka v dashboardu po stornu 0 %, replay po novém cancelled_at),
//  • „Potvrdit částečné vrácení“ 100 % vrátí zbytek, dorovnání stavu po pádu, zámek po zabitém isolatu, cancelled_at NULL.
// Na předchozí verzi hotfixu (i na main) tyto testy PADAJÍ. Spouští storno_hotfix_test.ts v podprocesu s import mapou.
// deno-lint-ignore-file no-explicit-any
import { BID, EMAIL, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, refundedKc, rows, world } from './storno-harness.ts'
import { customerCancel, velinCancel, velinConfirm } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()

function money(label: string, refunded: number, cn = refunded) {
  const r = refundedKc(), c = cnKc()
  if (r !== refunded || c !== cn) throw new Error(`${label}: vráceno ${r} (čekáno ${refunded}), dobropisy ${c} (čekáno ${cn}), stripe ${JSON.stringify(world().creates.map((x) => x.result))}`)
}
function mailsSay(label: string, amount: number | null, count?: number) {
  const ms = customerMails()
  if ((count != null && ms.length !== count) || !ms.length || ms.some((m) => m.amount !== amount)) throw new Error(`${label}: maily ${JSON.stringify(ms)}, čekáno ${amount}`)
}
const velinUpd = () => Object.assign(bk(), { status: 'cancelled', cancelled_at: new Date().toISOString(), payment_status: 'refund_pending',
  cancelled_by_source: 'velin', cancellation_reason: 'Storno (Velín)' })
const sce = (amount: number) => call('send-cancellation-email', { booking_id: BID, customer_email: EMAIL, cancellation_reason: 'Storno (Velín)',
  cancelled_by_source: 'velin', source: 'app', refund_amount: amount, refund_percent: Math.round(amount / 30) }, 'admin')
const pr = (amount?: number) => call('process-refund', { booking_id: BID, reason: 'cancellation', ...(amount ? { amount } : {}) }, 'admin')

Deno.test({ name: 'obsluha: dvojité odeslání storna / dvojklik „Potvrdit vrácení“ (souběžně i po sobě s „pending“) → jedna vratka', ignore: !MAPPED, fn: async () => {
  fresh(10); velinUpd(); await Promise.all([pr(1500), pr(1500)]); await sce(1500); await deliver()
  money('souběžné storno 50 %', 1500); mailsSay('souběžné storno 50 %', 1500, 1)
  fresh(10); velinUpd(); await Promise.all([pr(), pr()]); await sce(3000); await deliver()
  money('souběžné storno 100 %', 3000)
  fresh(10); world().refundStatus = () => 'pending'; velinUpd(); await pr(1500); await pr(1500); await sce(1500); await deliver()
  money('po sobě, vratka čeká „pending“', 1500)
  fresh(10); await velinCancel(0); await deliver(); advance(40)
  await Promise.all([pr(1000), pr(1000)]); await deliver()
  money('dvojklik Potvrdit vrácení 1000', 1000)
} })

Deno.test({ name: 'storno bez vratky (Velín 0 %, zákazník < 48 h, výbava) + o 40 min ruční vratka 500 Kč v dashboardu → vráceno jen 500', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [label, run] of [
    ['Velín 0 %', async () => { fresh(10); await velinCancel(0) }],
    ['zákazník +1 d', async () => { fresh(1); await customerCancel('none') }],
    ['zákazník +1 d výbava', async () => { fresh(1, { gear: true }); await customerCancel('none') }],
  ] as Array<[string, () => Promise<void>]>) {
    await run(); await deliver(); advance(40); await world().dashboardRefund('pi_orig', 50000); await deliver()
    try { money(label, 500) } catch (e) { bad.push((e as Error).message) }
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'charge.refunded znovu po 40 min, když hromadné „Zrušit“ / AI copilot přepsal cancelled_at → bez další vratky i mailu', ignore: !MAPPED, fn: async () => {
  fresh(10); await velinCancel(1500); const ev = world().takeEvents(); await deliver(ev)
  advance(40); bk().cancelled_at = new Date().toISOString(); await deliver(ev)
  money('replay po novém cancelled_at', 1500); mailsSay('replay po novém cancelled_at', 1500, 1)
} })

Deno.test({ name: '„Potvrdit částečné vrácení“ 100 % po stornu 50 % → vrátí zbytek (3000); ruční platba (QR) beze změny', ignore: !MAPPED, fn: async () => {
  fresh(10); await velinCancel(1500); await deliver(); advance(40); await velinConfirm(3000); await deliver()
  money('zbytek kartou', 3000)
  if (bk().payment_status !== 'refunded' || customerMails().at(-1)?.amount !== 3000) throw new Error(`stav ${bk().payment_status}, maily ${JSON.stringify(customerMails())}`)
  fresh(10, { booking: { payment_method: 'qr', pay_channel: 'qr', stripe_payment_intent_id: null } })
  await velinCancel(1500); bk().payment_status = 'partial_refund'; advance(40); await velinConfirm(3000)
  money('QR beze změny (žádný další ruční dobropis)', 0, 1500)
} })

Deno.test({ name: 'pád process-refund po refunds.create u rezervace s dřívější vratkou úpravy → další volání ze serveru dorovná stav (před webhookem)', ignore: !MAPPED, fn: async () => {
  fresh(10)
  await call('process-refund', { booking_id: BID, amount: 500, reason: 'edit_shortening' }); await deliver()
  Object.assign(bk(), { total_price: 2500, card_brand: null, card_last4: null })
  const shortening = bk().stripe_refund_id
  const db = (globalThis as any).__STORNO_DB
  let killed = false
  db.beforeUpdate = (t: string, patch: any) => { if (!killed && t === 'bookings' && patch.stripe_refund_id) { killed = true; throw new Error('isolate killed') } }
  const c = await customerCancel('none'); db.beforeUpdate = null
  const cancelRefund = world().refunds.at(-1)!.id
  if (bk().stripe_refund_id !== shortening) throw new Error('pád se nenasimuloval')
  await call('process-refund', { booking_id: BID, amount: c.amt, reason: 'cancellation' }) // další volání ze serveru (trigger / retry)
  const b = bk()
  if (b.stripe_refund_id !== cancelRefund || b.payment_status !== 'refunded' || b.card_last4 !== '4242') {
    throw new Error(`stav ${b.payment_status}, refund ${b.stripe_refund_id} (čekáno ${cancelRefund}), karta ${b.card_brand}/${b.card_last4}`)
  }
  await deliver(); money('pád + dorovnání', 3000)
} })

Deno.test({ name: 'zámek po zabitém isolatu (řádek email_send_locks zůstal) → druhé volání po 8 s čekání bez druhé vratky i dobropisu', ignore: !MAPPED, fn: async () => {
  fresh(10); velinUpd()
  // zabitý process-refund z Velínu: vratka vznikla, stav ani dobropis ne, zámek zůstal (finally neproběhl)
  await world().api().refunds.create({ payment_intent: 'pi_orig', amount: 150000, reason: 'requested_by_customer', metadata: {
    mg_source: 'process-refund', mg_reason: 'cancellation', mg_booking_id: BID, mg_order_id: '', mg_cancel_at: bk().cancelled_at } },
    { idempotencyKey: `refund:${BID}:150000:300000` })
  const ev = world().takeEvents()
  rows('email_send_locks').push({ booking_id: BID, template_slug: 'refund_cancellation', locked_at: Date.now() })
  const orig = Date.now; let off = 0; Date.now = () => orig() + off
  try { const p = sce(1500); setTimeout(() => { off = 9000 }, 300); await p } finally { Date.now = orig }
  if (!rows('debug_log').some((d) => d.action === 'cancellation_lock_busy' && d.request_data?.waited)) throw new Error('nečekalo na zámek')
  await deliver(ev)
  money('zabitý isolate', 1500)
  if (creditNotes().length !== 1) throw new Error(`dobropisů ${creditNotes().length}`)
  mailsSay('zabitý isolate', 1500, 1)
} })

Deno.test({ name: 'storno bez cancelled_at (NULL): druhé volání ze serveru vratku nezopakuje', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending' // stav zůstane refund_pending → rozhoduje kontrola cancel-once (token '')
  velinUpd(); bk().cancelled_at = null
  await pr(1500); await sce(1500); await deliver()
  money('cancelled_at NULL', 1500); mailsSay('cancelled_at NULL', 1500, 1)
} })
