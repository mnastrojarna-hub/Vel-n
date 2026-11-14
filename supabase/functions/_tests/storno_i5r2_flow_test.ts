// ===== _tests/storno_i5r2_flow_test.ts =====
// Oprava fix:i5r2 (2026-11-07) po verify:refunds / verify:charges i5 — celé handlery nad falešným Stripe + DB
// (storno-harness.ts). Na stromu před opravou (03a2d1dc) testy PADAJÍ (STORNO_FN_DIR=<strom před opravou>), kromě kontroly R1c:
//  R1  selhaná vratka zkrácení „nahrazená“ NESOUVISEJÍCÍ novější vratkou (2. úprava o jinou částku) → rezervace se znovu
//      otevře a mail obsluze říká „Chybí vrátit 500 Kč“ (failed-refund.ts: nahrazuje jen opakování se stejným požadavkem);
//      R1c (kontrola) selhané dorovnání storna 50 % → 100 % starší vratka 50 % nenahrazuje,
//  R2  QR rezervace, dvě zkrácení + Velín „Vratka odeslána“ → ŽIVÁ rezervace zůstává 'partial_refund' (manualRefundState.js)
//      a storno pak vrátí zbytek; R2b mail storna nebere dobropisy dřívějších zkrácení jako vrácení storna (docsCheck),
//  R3  selhaná vratka zkrácení → obsluha vrátí v dashboardu (dle mailu) → webhook dobropis NEvystaví sám (jen mail „vystavte
//      ručně“); R3b dobropis k vratce z dashboardu u ŽIVÉ rezervace netvrdí „Storno rezervace“,
//  R8  opakování selhané vratky, výpis vratek uložené platby selže → nic se nevrací (chyba, mail obsluze); R8b výpis je
//      zastaralý (prázdný) → přehraná SELHANÁ vratka se pozná podle času vzniku a nevydává se za úspěch,
//  T3  potvrzení platby: kontrola stavu rezervace selže čtením → zrušená a vrácená rezervace se NEoživí, webhook 500
//      (Stripe doručí znovu); záložní zápis po chybě confirm_payment zrušenou rezervaci neoživí.
// Spouští storno_hotfix_test.ts (podproces s import mapou storno-flow-map.json).
// deno-lint-ignore-file no-explicit-any
import { BID, EMAIL, FN, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, mails, opsMails, rows, webhookStatuses, world } from './storno-harness.ts'
import { customerCancel } from './storno-dispatch.ts'
import { Db } from './storno-fake-db.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()
// Velín / webhook moduly z testovaného stromu (STORNO_FN_DIR = důkaz pádu na stromu před opravou)
const { manualRefundSentStatus } = MAPPED ? await import(new URL('../../velin/src/pages/booking/manualRefundState.js', FN).href) : { manualRefundSentStatus: null as any }

const pr = (amount?: number, as: 'service' | 'admin' | 'customer' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)
const ev = (type: string, r: any, id: string) => deliver([{ id, type, created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(r)) } }])
const fail = (r: any, id = 'evt_cru_' + r.id) => { r.status = 'failed'; return ev('charge.refund.updated', r, id) }
const liveKc = () => world().refunds.filter((r: any) => r.status === 'succeeded' || r.status === 'pending').reduce((s: number, r: any) => s + r.amount, 0) / 100
const text = (h: string) => h.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ')
const db = () => (globalThis as any).__STORNO_DB
/** Stripe API s upraveným refunds.list pro uloženou platbu (pi_orig) po dobu `fn` */
async function withList(fn: () => Promise<any>, list: (p: any, orig: (p: any) => Promise<any>) => Promise<any>) {
  const w = world(), api = w.api.bind(w)
  w.api = () => { const a = api(); const l = a.refunds.list; a.refunds.list = (p: any) => (p.payment_intent === 'pi_orig' ? list(p, l) : l(p)); return a }
  try { return await fn() } finally { w.api = api }
}

Deno.test({ name: 'i5r2 R1: selhaná vratka zkrácení + nesouvisející novější vratka → znovu otevřena, „Chybí vrátit 500 Kč“; opakování (kontrola) ji nahradí', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const second of ['shortening', 'moto_swap'] as const) {
    fresh(10); world().refundStatus = () => 'pending'
    bk().total_price = 2500
    await pr(500, 'service', 'shortening'); await deliver() // 1. zkrácení: 500 Kč „pending“
    world().refundStatus = () => 'succeeded'
    advance(2)
    bk().total_price = 2200
    await pr(300, 'service', second); await deliver() // 2. úprava o JINOU částku — vratku 1. úpravy nenahrazuje
    opsMails.length = 0
    await fail(world().refunds[0])
    const m = opsMails.find((x) => /SELHALA/.test(x.subject))
    if (bk().payment_status !== 'refund_pending') bad.push(`${second}: stav ${bk().payment_status} (čekáno refund_pending)`)
    if (!m || !/Chybí vrátit <strong>500 Kč/.test(m.html) || /nahradila novější vratka/.test(m.html)) bad.push(`${second}: mail ${m ? text(m.html).slice(-260) : '—'}`)
    if (liveKc() !== 300 || cnKc() !== 300) bad.push(`${second}: vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč`)
    // kontrola: opakování TÉHOŽ požadavku (500 Kč) → stará událost „failed“ rezervaci znovu neotevře
    advance(5)
    await pr(500, 'service', 'shortening'); await deliver()
    const after = bk().payment_status
    await fail(world().refunds[0], 'evt_ru_again_' + second)
    if (liveKc() !== 800 || bk().payment_status !== after || after === 'refund_pending') bad.push(`${second}: po opakování ${after} → ${bk().payment_status}, vráceno ${liveKc()} Kč`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5r2 R1c: storno 50 % → „Potvrdit vrácení“ na 100 % (dorovnání) selže → starší vratka 50 % ho nenahrazuje, znovu otevřeno', ignore: !MAPPED, fn: async () => {
  fresh(10)
  await customerCancel('none', 50); await deliver() // 1500 Kč
  advance(5)
  world().refundStatus = () => 'pending'
  const { velinConfirm } = await import('./storno-dispatch.ts')
  await velinConfirm(3000); await deliver() // dorovnání +1500 Kč
  world().refundStatus = () => 'succeeded'
  const top = world().refunds.at(-1)
  opsMails.length = 0
  await fail(top)
  const m = opsMails.find((x) => /SELHALA/.test(x.subject))
  if (liveKc() !== 1500 || bk().payment_status !== 'refund_pending' || !m || !/Chybí vrátit <strong>1500 Kč/.test(m.html)) {
    throw new Error(`vráceno ${liveKc()} Kč (${world().refunds.length} vratek), stav ${bk().payment_status}, mail ${m ? text(m.html).slice(-240) : '—'}`)
  }
} })

const qrBooking = () => {
  fresh(10, { booking: { payment_method: 'bank_transfer', pay_channel: 'qr', stripe_payment_intent_id: null, payment_vs: '5550001' } })
  world().intents.delete('pi_orig')
  rows('fio_transactions').push({ fio_id: 1, amount: 3000, vs: '5550001', booking_id: BID, counter_account: '1', counter_bank: '0100', status: 'confirmed' })
}

Deno.test({ name: 'i5r2 R2: QR rezervace — „Vratka odeslána“ po dvou zkráceních nechá živou rezervaci částečně vrácenou; storno vrátí zbytek', ignore: !MAPPED, fn: async () => {
  qrBooking()
  const sent = () => { bk().payment_status = manualRefundSentStatus(bk(), creditNotes()) } // BookingDetail confirmManualRefundSent
  bk().total_price = 2000
  await pr(1000, 'service', 'shortening'); sent()
  advance(20)
  bk().total_price = 1400
  await pr(600, 'service', 'shortening'); sent()
  const afterSent = bk().payment_status
  mails.length = 0
  await customerCancel('none'); await deliver() // storno 100 % = 1400 Kč
  if (afterSent !== 'partial_refund' || cnKc() !== 3000) throw new Error(`po „Vratka odeslána“ ${afterSent}, dobropisy ${cnKc()} Kč (čekáno 3000), stav ${bk().payment_status}`)
  // zrušená: „Vratka odeslána“ porovnává se zaplacenými doklady (DP 3000), ne se sníženou cenou
  const cancelled = { status: 'cancelled', total_price: 1400 }
  if (manualRefundSentStatus(cancelled, [{ total: -1000 }, { total: -600 }], 3000) !== 'partial_refund'
    || manualRefundSentStatus(cancelled, [{ total: -1000 }, { total: -600 }, { total: -1400 }], 3000) !== 'refunded'
    || manualRefundSentStatus(cancelled, [{ total: -1400 }], null) !== 'refunded') throw new Error('zrušená rezervace: stav dle DP / ceny')
} })

Deno.test({ name: 'i5r2 R2b: storno „už vráceno“ s dobropisy jen z dřívějších zkrácení → mail neslibuje vrácení storna', ignore: !MAPPED, fn: async () => {
  qrBooking()
  bk().total_price = 2000
  await pr(1000, 'service', 'shortening')
  advance(20)
  bk().total_price = 1400
  await pr(600, 'service', 'shortening')
  advance(20)
  bk().payment_status = 'refunded' // starší stav (Velín před opravou / ručně) — process-refund pak „už vráceno“
  mails.length = 0
  await customerCancel('none'); await deliver()
  const m = mails.filter((x) => x.to === EMAIL).at(-1)
  const cm = customerMails().at(-1)
  const html = m?.html || ''
  if (cm?.amount === 1400 && !/dokončuje obsluha/.test(html)) throw new Error(`mail tvrdí vrácení 1400 Kč: ${text(html).slice(0, 400)}`)
} })

Deno.test({ name: 'i5r2 R3: selhaná vratka zkrácení → vratka v dashboardu → webhook dobropis nevystaví sám, mail žádá ruční', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  bk().total_price = 2500
  await pr(500, 'service', 'shortening'); await deliver()
  world().refundStatus = () => 'succeeded'
  await fail(world().refunds[0])
  opsMails.length = 0
  await world().dashboardRefund('pi_orig', 50000); await deliver() // obsluha podle mailu
  const auto = creditNotes().filter((x: any) => x.stripe_refund_id === world().refunds[1].id)
  const asks = opsMails.filter((x) => /vystavte dobropis ručně/.test(text(x.html)))
  if (liveKc() !== 500 || auto.length || !asks.length || bk().status === 'cancelled') {
    throw new Error(`vráceno ${liveKc()} Kč, dobropisy ${JSON.stringify(creditNotes().map((x: any) => [x.total, x.notes]))}, mail obsluze: ${asks.length}, stav ${bk().status}`)
  }
} })

Deno.test({ name: 'i5r2 R3b: dobropis recovery k vratce z dashboardu u ŽIVÉ rezervace netvrdí „Storno rezervace“', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  bk().total_price = 2500
  await pr(500, 'service', 'shortening'); await deliver()
  world().refundStatus = () => 'succeeded'
  await fail(world().refunds[0])
  await world().dashboardRefund('pi_orig', 300000); await deliver() // obsluha vrátí celou platbu (rezervace zůstává živá)
  const cn = creditNotes().find((x: any) => x.stripe_refund_id === world().refunds[1].id)
  if (bk().status !== 'cancelled' && cn && /Storno/.test(String(cn.notes) + JSON.stringify(cn.items))) {
    throw new Error(`živá rezervace (${bk().status}), dobropis ${cn.total}: ${cn.notes} ${JSON.stringify(cn.items)}`)
  }
} })

Deno.test({ name: 'i5r2 R8: opakování selhané vratky, výpis vratek uložené platby selže → nic „úspěšně“ nepřehrát, chyba + mail obsluze', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  bk().total_price = 2500
  await pr(500, 'service', 'shortening'); await deliver()
  world().refundStatus = () => 'succeeded'
  await fail(world().refunds[0])
  advance(10)
  opsMails.length = 0
  let failNext = true
  const r = await withList(() => pr(500, 'service', 'shortening'),
    (p, l) => (failNext ? (failNext = false, Promise.reject(new Error('rate_limit'))) : l(p)))
  await deliver()
  const replayed = world().creates.filter((c: any) => String(c.result).startsWith('replayed:'))
  if (r?.success === true || replayed.length || !opsMails.length || bk().payment_status !== 'refund_pending') {
    throw new Error(`odpověď ${JSON.stringify(r)}, přehráno ${replayed.length}, maily ${opsMails.map((m) => m.subject).join(' | ')}, stav ${bk().payment_status}`)
  }
  // další pokus (Stripe odpovídá) → nová vratka
  const r2 = await pr(500, 'service', 'shortening'); await deliver()
  if (r2?.success !== true || liveKc() !== 500) throw new Error(`2. pokus ${JSON.stringify(r2)}, vráceno ${liveKc()} Kč`)
} })

Deno.test({ name: 'i5r2 R8b: zastaralý (prázdný) výpis vratek → přehraná SELHANÁ vratka se pozná podle času vzniku, ne úspěch', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  bk().total_price = 2500
  await pr(500, 'service', 'shortening'); await deliver()
  world().refundStatus = () => 'succeeded'
  await fail(world().refunds[0])
  advance(10)
  const r = await withList(() => pr(500, 'service', 'shortening'), () => Promise.resolve({ data: [] }))
  await deliver()
  const replayed = world().creates.filter((c: any) => String(c.result).startsWith('replayed:'))
  if (r?.success === true && liveKc() !== 500) {
    throw new Error(`vráceno ${liveKc()} Kč, odpověď ${JSON.stringify({ success: r?.success, refund_id: r?.refund_id, status: r?.status })}, přehráno ${replayed.length}, stav ${bk().payment_status}`)
  }
  if (!rows('debug_log').some((d: any) => d.action === 'stripe_refund_replayed_failed')) throw new Error('chybí debug_log stripe_refund_replayed_failed')
} })

const errQ: any = new Proxy({}, { get: (_t, k) => k === 'then'
  ? (res: any) => res({ data: null, error: { message: 'canceling statement due to statement timeout' } }) : () => errQ })
/** select('status, payment_status') rezervace (kontrola v confirmBookingPayment) jednou selže čtením */
function failPrecheckOnce(d: any) {
  const from = d.from.bind(d); let left = 1
  d.from = (t: string) => {
    const q = from(t)
    if (t === 'bookings') { const sel = q.select.bind(q); q.select = (c: string, ...o: any[]) => (left > 0 && c === 'status, payment_status' ? (left--, errQ) : sel(c, ...o)) }
    return q
  }
}
const piEvent = (id: string) => {
  const o = world().intents.get('pi_orig')!
  return { id, type: 'payment_intent.succeeded', created: Math.floor(Date.now() / 1000), data: { object: { id: 'pi_orig', object: 'payment_intent', currency: 'czk',
    amount: o.amount, amount_received: o.amount_received, status: 'succeeded', metadata: o.metadata, customer: null, created: o.created, latest_charge: o.latest_charge } } }
}

Deno.test({ name: 'i5r2 T3: kontrola stavu nečitelná → zrušená a vrácená rezervace se neoživí, webhook 500; záložní zápis neoživí', ignore: !MAPPED, fn: async () => {
  fresh(10)
  await pr(undefined, 'admin') // plné storno vratka
  Object.assign(bk(), { status: 'cancelled', cancelled_at: new Date().toISOString(), cancelled_by_source: 'velin' })
  await deliver()
  const ps = bk().payment_status
  let rpcCalls = 0
  db().rpcs.confirm_payment = () => { // živé RPC: oživí každou zrušenou s payment_status <> 'paid'
    rpcCalls++
    if (bk().payment_status === 'paid') return { data: { success: true, was_already_paid: true }, error: null }
    Object.assign(bk(), { status: 'reserved', payment_status: 'paid' }); return { data: { success: true, was_already_paid: false }, error: null }
  }
  failPrecheckOnce(db())
  webhookStatuses.length = 0
  await deliver([piEvent('evt_t3_1')])
  const bad: string[] = []
  if (bk().status !== 'cancelled' || bk().payment_status !== ps || rpcCalls) bad.push(`po nečitelné kontrole ${bk().status}/${bk().payment_status} (RPC ${rpcCalls}×)`)
  if (webhookStatuses.at(-1) !== 500) bad.push(`webhook ${webhookStatuses.at(-1)} (čekáno 500 — Stripe doručí znovu)`)
  await deliver([piEvent('evt_t3_1')]) // znovu doručeno, kontrola čitelná → 'skipped'
  if (bk().status !== 'cancelled' || rpcCalls) bad.push(`po znovudoručení ${bk().status}/${bk().payment_status} (RPC ${rpcCalls}×)`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5r2 T3b: confirm_payment spadne → záložní zápis zrušenou (pozdní) platbu neoživí', ignore: !MAPPED, fn: async () => {
  const { confirmBookingPayment } = await import(new URL('webhook-receiver/payment-confirmers.ts', FN).href)
  const d = new Db({ bookings: [{ id: BID, status: 'cancelled', payment_status: 'unpaid', start_date: '2026-12-01' }], debug_log: [] })
  d.rpcs.confirm_payment = () => ({ data: null, error: { message: 'connection reset' } })
  const res = await confirmBookingPayment(d as never, BID, 'cs_x', null, true)
  const b = d.rows('bookings')[0]
  if (b.status !== 'cancelled' || b.payment_status !== 'unpaid') throw new Error(`výsledek ${res}, rezervace ${b.status}/${b.payment_status}`)
  // nečitelná kontrola stavu → 'retry' bez volání RPC
  const d2 = new Db({ bookings: [{ id: BID, status: 'cancelled', payment_status: 'refunded' }], debug_log: [] })
  let rpc = 0
  d2.rpcs.confirm_payment = () => { rpc++; return { data: { success: true }, error: null } }
  failPrecheckOnce(d2)
  const r2 = await confirmBookingPayment(d2 as never, BID, 'cs_y', null, true)
  if (r2 !== 'retry' || rpc) throw new Error(`nečitelná kontrola: ${r2}, RPC ${rpc}×`)
} })
