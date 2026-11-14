// ===== _tests/storno_i4_flow_test.ts =====
// Oprava i4 (2026-11-07) po čtvrté adversariální verifikaci (verify:refunds / verify:charges) — celé handlery nad
// falešným Stripe + DB (storno-harness.ts). Na kódu před opravou i4 testy PADAJÍ (STORNO_FN_DIR=<strom před opravou>):
//  S1a/S1b/S1c  SELHANÁ vratka se opakováním (Velín „Potvrdit vrácení“, služba, recovery zbytku) vrátí znovu — dřív
//               Stripe idempotency klíčem přehrál selhanou vratku (žádná nová, odpověď „success“),
//  S1d          zbytek z jiné platby „pending“ → 'refund_pending'; zbytek pak selže → rezervace 'refunded' se znovu otevře,
//  S5           selhaná automatická vratka MIMO cenu (duplicitní platba, metadata.booking_id) → mail obsluze,
//  S10          vratka zkrácení „pending“ + stejné volání znovu → jen jedna vratka (admin i služba),
//  S2 / S3      požadavek nad zaplacené (storno po stornu, nezaplacený doplatek v ceně) → bez mailu „vraťte ručně“, mail
//               zákazníkovi i stav dle skutečně vrácené částky,
//  S7           karta + doplatek převodem, plné storno: no_op „Potvrdit vrácení“ neuzavře „Čeká na vrácení“ s ručním dobropisem,
//  S6           druhé zkrácení se spadlou vratkou (služba) → mail obsluze + mail úpravy „dokončuje obsluha“,
//  AP           Stripe Adaptive Pricing (cena v CZK, strženo v EUR) → rezervace potvrzena, PaymentIntent tiše, vratka ručně.
// Spouští storno_hotfix_test.ts (podproces s import mapou storno-flow-map.json).
// deno-lint-ignore-file no-explicit-any
import { BID, EMAIL, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, loadFn, mails, opsMails, refundedKc, rows, world } from './storno-harness.ts'
import { customerCancel, velinCancel, velinConfirm } from './storno-dispatch.ts'
import { manualRefundOpen } from '../../../velin/src/pages/booking/manualRefundState.js'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) { await boot(); await loadFn('send-booking-email') }

const pr = (amount?: number, as: 'service' | 'admin' | 'customer' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)
const updated = (r: any, id = 'evt_ru_' + r.id) => deliver([{ id, type: 'charge.refund.updated', created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(r)) } }])
const fail = (r: any) => { r.status = 'failed'; return updated(r) }
const created = () => world().creates.filter((c: any) => String(c.result).startsWith('created:')).length

Deno.test({ name: 'i4 S1a/S1b: selhaná „pending“ storno vratka → „Potvrdit vrácení“ (Velín) i služba vrátí NOVOU vratkou', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const via of ['velin', 'service'] as const) {
    fresh(10); world().refundStatus = () => 'pending'
    const c = via === 'velin' ? (await velinCancel('full'), null) : await customerCancel('none')
    await deliver()
    world().refundStatus = () => 'succeeded'
    await fail(world().refunds[0])
    for (const x of creditNotes()) x.status = 'cancelled' // pokyn z mailu: „zrušte dobropis … a vratku zopakujte“
    advance(10)
    const r = via === 'velin' ? await velinConfirm(3000) : await pr(c!.amt, 'service')
    await deliver()
    if (refundedKc() !== 3000 || created() !== 2) bad.push(`${via}: vráceno ${refundedKc()} Kč, nových vratek ${created()} (${JSON.stringify(world().creates.map((x: any) => x.result))}) ${JSON.stringify(r)}`)
    if (world().creates.some((x: any) => String(x.result).startsWith('replayed:'))) bad.push(`${via}: Stripe přehrál selhanou vratku`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i4 S1c/S1d: zbytek storna z jiné platby „pending“ → refund_pending; selže → recovery ho vrátí znovu, „refunded“ se znovu otevře', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] }) // uložená pi_ext1 (500) + původní 3000
  let n = 0
  world().refundStatus = () => (++n === 2 ? 'pending' : 'succeeded') // 1. = hlavní z pi_ext1, 2. = zbytek z pi_orig
  await velinCancel('full'); await deliver()
  world().refundStatus = () => 'succeeded'
  if (bk().payment_status !== 'refund_pending') bad.push(`po stornu se zbytkem „pending“: ${bk().payment_status} (čekáno refund_pending)`)
  const rem = world().refunds.find((r: any) => r.metadata.mg_part === 'remainder')
  await fail(rem)
  advance(10)
  const ch = world().charges.get('ch_ext1')
  await deliver([{ id: 'evt_again', type: 'charge.refunded', created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(ch)) } }])
  await call('process-refund', { booking_id: BID, reason: 'cancellation_retry' }, 'service'); await deliver()
  if (refundedKc() !== 3500) bad.push(`po recovery vráceno ${refundedKc()} Kč (čekáno 3500): ${JSON.stringify(world().creates.map((x: any) => x.result))}`)
  // S1d: vratka, která uspěla, později selže → 'refunded' znovu otevřít, mail jmenuje dobropis
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] })
  await velinCancel('full'); await deliver()
  if (bk().payment_status !== 'refunded') bad.push(`S1d po stornu ${bk().payment_status}`)
  opsMails.length = 0
  const rem2 = world().refunds.find((r: any) => r.metadata.mg_part === 'remainder')
  await fail(rem2); await updated(rem2, 'evt_dup') // refund.updated i charge.refund.updated → jeden mail
  if (bk().payment_status !== 'refund_pending') bad.push(`S1d po selhání zbytku ${bk().payment_status} (čekáno refund_pending)`)
  const cn = creditNotes().find((c: any) => c.stripe_refund_id === rem2.metadata.mg_main_refund)
  if (opsMails.length !== 1 || !cn || !opsMails[0].html.includes(cn.number) || !/Čeká na vrácení/.test(opsMails[0].html)) {
    bad.push(`S1d mail: ${JSON.stringify(opsMails.map((m) => m.subject))} ${opsMails[0]?.html?.slice(0, 400)}`)
  }
  advance(10)
  for (const c of creditNotes()) c.status = 'cancelled'
  await velinConfirm(3500); await deliver()
  if (refundedKc() !== 3500) bad.push(`S1d po „Potvrdit vrácení“ vráceno ${refundedKc()} Kč (čekáno 3500)`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i4 S5: selhaná automatická vratka mimo cenu (duplicitní / pozdní platba, metadata.booking_id) → mail obsluze, stav beze změny', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  fresh(10)
  world().addPi('pi_dup', 3000, { booking_id: BID, type: 'booking', duplicate_of: 'pi_orig' })
  world().refundStatus = () => 'pending'
  const r = await world().api().refunds.create({ payment_intent: 'pi_dup', amount: 300000, metadata: { mg_source: 'duplicate_payment', booking_id: BID, kept: 'pi_orig' } }, { idempotencyKey: 'mg-dup-pi_dup' })
  world().refundStatus = () => 'succeeded'
  await deliver()
  const rr = world().refunds.find((x: any) => x.id === r.id)
  await fail(rr)
  if (!opsMails.some((m) => /SELHALA/.test(m.subject) && /Stripe dashboard/.test(m.html) && /duplicitní platba/.test(m.html))) bad.push(`duplicitní: ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  if (bk().payment_status !== 'paid') bad.push(`stav ${bk().payment_status}`)
  // pozdní platba bez dohledatelné rezervace (cizí booking_id) → mail i tak
  opsMails.length = 0
  world().addPi('pi_late', 2000, { booking_id: '99999999-2222-4333-8444-555555555555', type: 'booking' })
  const l = await world().api().refunds.create({ payment_intent: 'pi_late', metadata: { mg_source: 'late_payment', booking_id: '99999999-2222-4333-8444-555555555555' } }, { idempotencyKey: 'mg-late-cancelled-pi_late' })
  await deliver()
  await fail(world().refunds.find((x: any) => x.id === l.id))
  if (!opsMails.some((m) => /SELHALA/.test(m.subject) && /nepodařilo dohledat/.test(m.html))) bad.push(`bez rezervace: ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i4 S10: vratka zkrácení vrácená jako „pending“ + totéž volání znovu → jedna vratka (Velín i služba)', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const as of ['admin', 'service'] as const) {
    fresh(10); bk().total_price = 2500; world().refundStatus = () => 'pending'
    await call('process-refund', { booking_id: BID, reason: 'shortening', amount: 500 }, as); await deliver()
    advance(2)
    const b = await call('process-refund', { booking_id: BID, reason: 'shortening', amount: 500 }, as); await deliver()
    if (refundedKc() !== 500 || cnKc() !== 500 || b.already_refunded !== true) bad.push(`${as}: vráceno ${refundedKc()}, dobropisy ${cnKc()}, ${JSON.stringify(b)}`)
  }
  // druhé zkrácení o stejnou částku (cena znovu nižší) je po právu → vrátí se
  fresh(10); bk().total_price = 2500; world().refundStatus = () => 'pending'
  await pr(500, 'service', 'shortening'); await deliver(); advance(2)
  bk().total_price = 2000
  await pr(500, 'service', 'shortening'); await deliver()
  if (refundedKc() !== 1000) bad.push(`druhé zkrácení: vráceno ${refundedKc()} Kč (čekáno 1000)`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i4 S2/S3: požadavek nad zaplacené → bez mailu „vraťte ručně“, mail a stav dle skutečně vrácené částky', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  const shortMail = () => opsMails.some((x) => /nevrátila celá|zbývá|ručně/i.test(x.subject + x.html))
  // S2: storno 50 %, pak „Potvrdit vrácení“ 2000 (vrací rozdíl navíc — rozhodnutí o významu částky čeká na majitele)
  fresh(10); await velinCancel(1500); await deliver(); advance(40)
  mails.length = 0; opsMails.length = 0
  await velinConfirm(2000); await deliver()
  const m2 = customerMails().at(-1)
  if (m2?.amount !== refundedKc() || shortMail() || rows('booking_cancellations').at(-1)?.refund_amount !== refundedKc()) {
    bad.push(`S2: mail ${JSON.stringify(m2)}, vráceno ${refundedKc()}, záznam ${rows('booking_cancellations').at(-1)?.refund_amount}, ops ${JSON.stringify(opsMails.map((x) => x.subject))}`)
  }
  // S3: nezaplacený doplatek úpravy v ceně (3500, zaplaceno 3000) — storno zákazníkem 100 % i plné z Velínu
  for (const via of ['rpc', 'velin'] as const) {
    fresh(10, { booking: { total_price: 3500, mod_surcharge_due: 500, mod_surcharge_vs: '2026009', mod_surcharge_paid_at: null } })
    if (via === 'rpc') await customerCancel('none'); else await velinCancel('full')
    await deliver()
    const m = customerMails().at(-1)
    if (refundedKc() !== 3000 || m?.amount !== 3000 || shortMail() || bk().payment_status !== 'refunded') {
      bad.push(`S3 ${via}: vráceno ${refundedKc()}, mail ${JSON.stringify(m)}, stav ${bk().payment_status}, ops ${JSON.stringify(opsMails.map((x) => x.subject))}`)
    }
  }
  // regrese: karta 3000 + doplatek 500 převodem (DP), storno zákazníkem → zbytek 500 dál obsluze (dlužíme ho)
  fresh(10, { booking: { total_price: 3500, mod_surcharge_vs: '2026002', mod_surcharge_paid_at: new Date().toISOString() } })
  rows('invoices').push({ id: crypto.randomUUID(), booking_id: BID, type: 'payment_receipt', status: 'issued', total: 500, number: 'DP-2026-1501', issue_date: '2026-10-02', created_at: new Date().toISOString() })
  await customerCancel('none'); await deliver()
  if (!opsMails.some((x) => /zbývá <strong>500 Kč/.test(x.html))) bad.push(`převodem placená část: ops ${JSON.stringify(opsMails.map((x) => x.subject))}`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i4 S7: karta 3000 + převod 500, plné storno → Velín ukáže ruční část; „Potvrdit vrácení“ no_op stav „Čeká na vrácení“ nezavře', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { total_price: 3500, mod_surcharge_vs: '2026002', mod_surcharge_paid_at: new Date().toISOString() } })
  rows('invoices').push({ id: crypto.randomUUID(), booking_id: BID, type: 'payment_receipt', status: 'issued', total: 500, number: 'DP-2026-1501', issue_date: '2026-10-02', created_at: new Date().toISOString() })
  rows('fio_transactions').push({ fio_id: 8, booking_id: BID, amount: 500, vs: '2026002', counter_account: '111', counter_bank: '0100' })
  await velinCancel('full'); await deliver()
  const open = manualRefundOpen(bk(), creditNotes())
  if (!bk().stripe_refund_id || !open || Math.abs(Number(open.total)) !== 500) throw new Error(`ruční část ve Velínu: ${JSON.stringify(open)} (stripe_refund_id ${bk().stripe_refund_id})`)
  advance(10)
  await velinConfirm(3500); await deliver() // výchozí částka modalu u kartové vratky = celá cena
  if (bk().payment_status !== 'refund_pending' || refundedKc() !== 3000) throw new Error(`po „Potvrdit vrácení“: ${bk().payment_status}, vráceno ${refundedKc()}`)
} })

Deno.test({ name: 'i4 S6: druhé zkrácení do 6 h se spadlou vratkou (služba) → mail obsluze + mail úpravy „dokončuje obsluha“', ignore: !MAPPED, fn: async () => {
  fresh(10)
  const send = (pd: number) => call('send-booking-email', { type: 'booking_modified', booking_id: BID, customer_email: EMAIL, customer_name: 'Test Zákazník',
    price_difference: pd, language: 'cs', source: 'app' })
  bk().total_price = 2500
  bk().modification_history = [{ type: 'edit', at: new Date().toISOString() }]
  await pr(500, 'service', 'shortening'); await deliver(); await send(-500)
  advance(30)
  bk().total_price = 2200
  bk().modification_history = [...bk().modification_history, { type: 'edit', at: new Date().toISOString() }]
  world().onBeforeCreate = () => { throw new Error('Stripe: api_connection_error') }
  const opsBefore = opsMails.length
  await pr(300, 'service', 'shortening')
  world().onBeforeCreate = null
  mails.length = 0
  await send(-300)
  const html = mails.filter((m) => m.to === EMAIL).at(-1)?.html || ''
  const subj = opsMails.slice(opsBefore).map((m) => m.subject)
  if (!/dokončuje obsluha/.test(html) || !subj.some((s) => /selhala/.test(s))) throw new Error(`mail úpravy deferred=${/dokončuje obsluha/.test(html)}, ops ${JSON.stringify(subj)}`)
} })

Deno.test({ name: 'i4 AP: Stripe Adaptive Pricing (cena v CZK, strženo v EUR) → rezervace potvrzena, PaymentIntent tiše, vratka jen ručně', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  fresh(10, { booking: { status: 'pending', payment_status: 'unpaid', booking_source: 'web', stripe_session_id: 'cs_ap_1', stripe_payment_intent_id: null } })
  const db = (globalThis as any).__STORNO_DB
  const confirmed: string[] = []
  db.rpcs.confirm_payment = (a: any) => { confirmed.push(a.p_booking_id); Object.assign(bk(), { status: 'reserved', payment_status: 'paid' }); return { data: { success: true, was_already_paid: false }, error: null } }
  const sess = { id: 'cs_ap_1', object: 'checkout.session', mode: 'payment', payment_status: 'paid', status: 'complete', currency: 'eur', amount_total: 12000,
    currency_conversion: { source_currency: 'czk', amount_total: 300000, amount_subtotal: 300000, fx_rate: '0.04' }, payment_intent: 'pi_ap_1',
    metadata: { type: 'booking', booking_id: BID }, client_reference_id: BID, customer: null, created: Math.floor(Date.now() / 1000) }
  const w = world(), api0 = w.api.bind(w)
  w.api = () => { const a: any = api0(); a.checkout.sessions.list = (p: any) => Promise.resolve({ data: p?.payment_intent === 'pi_ap_1' ? [sess] : [] }); return a }
  await deliver([{ id: 'evt_cs_ap', type: 'checkout.session.completed', created: sess.created, data: { object: sess } }])
  if (!confirmed.length || rows('debug_log').some((d: any) => d.action === 'non_czk_payment_ignored')) bad.push(`session: potvrzeno ${confirmed.length}, ${JSON.stringify(rows('debug_log').map((d: any) => d.action).slice(-6))}`)
  opsMails.length = 0
  await deliver([{ id: 'evt_pi_ap', type: 'payment_intent.succeeded', created: sess.created, data: { object: { id: 'pi_ap_1', object: 'payment_intent', currency: 'eur', amount: 12000, amount_received: 12000, status: 'succeeded', metadata: { type: 'booking', booking_id: BID } } } }])
  if (opsMails.some((m) => /cizí měně/.test(m.subject))) bad.push(`PaymentIntent: mail ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  // vratka z platby v EUR → ručně (žádná automatická)
  w.addPi('pi_ap_1', 120, { booking_id: BID, type: 'booking' })
  ;(w.intents.get('pi_ap_1') as any).currency = 'eur'
  Object.assign(bk(), { stripe_payment_intent_id: 'pi_ap_1' })
  const r = await pr(1500, 'admin')
  if (r.code !== 'foreign_currency_payment' || w.refunds.length || !opsMails.some((m) => /cizí měně/.test(m.subject))) bad.push(`vratka: ${JSON.stringify(r)}, vratek ${w.refunds.length}`)
  if (bad.length) throw new Error(bad.join('\n'))
} })
