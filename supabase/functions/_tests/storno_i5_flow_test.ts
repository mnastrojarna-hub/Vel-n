// ===== _tests/storno_i5_flow_test.ts =====
// Oprava i5 (2026-11-07, fix:i5r1) po páté adversariální verifikaci (verify:refunds / verify:charges) — celé handlery nad
// falešným Stripe + DB (storno-harness.ts). Na kódu před opravou i5 testy PADAJÍ (STORNO_FN_DIR=<strom před opravou>),
// kromě kontrol označených „(kontrola)“:
//  B1  selhaná storno vratka → dobropis se sám zruší; „Potvrdit vrácení“ bez ručního zrušení dobropisu vratku zopakuje,
//  B2  selže jen ZBYTEK z jiné platby → dobropis zmenšen na hlavní vratku, mail nevelí „zrušte“; recovery / Velín
//      dovrátí a dobropisy = vráceno,
//  B3  selže HLAVNÍ vratka, zbytek z jiné platby odešel (osiřelý zbytek) → služba vrátí jen chybějící část, Velín
//      (rozdíl navíc, P2) hlásí správný součet; dobropisy = vráceno,
//  B4  stará událost „failed“ po úspěšném opakování rezervaci znovu neotevře,
//  C1  nová platba zrušené a už vrácené rezervace → vratka (zaplaceno po stornu) / mail obsluze (nejasné), znovu doručená
//      událost nic nezopakuje; uložená kartová platba během storna (kontrola) zůstává bez vratky i mailu,
//  F1  Fio doplatek úpravy ke ZRUŠENÉ rezervaci → nepotvrzen, obsluha (živá rezervace — kontrola — potvrzen),
//  A1  Adaptive Pricing: pozdní platba v EUR s přibalenou objednávkou → nic automaticky, mail s částkou v Kč,
//  A2  Adaptive Pricing: nezapsaná placená změna v HUF → vratka CELÉ platby (ne haléře CZK jako forinty).
// Spouští storno_hotfix_test.ts (podproces s import mapou storno-flow-map.json).
// deno-lint-ignore-file no-explicit-any
import { BID, FN, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, loadFn, mails, opsMails, rows, webhookStatuses, world } from './storno-harness.ts'
import { customerCancel, velinCancel, velinConfirm } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) {
  await boot()
  Deno.env.set('FIO_API_TOKEN', 'fio-test-token') // fio-sync ho čte při načtení modulu
  try { await loadFn('fio-sync') } finally { Deno.env.delete('FIO_API_TOKEN') }
}

const pr = (amount?: number, as: 'service' | 'admin' | 'customer' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)
const ev = (type: string, r: any, id: string) => deliver([{ id, type, created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(r)) } }])
const fail = (r: any, id = 'evt_cru_' + r.id) => { r.status = 'failed'; return ev('charge.refund.updated', r, id) }
const liveKc = () => world().refunds.filter((r: any) => r.status === 'succeeded' || r.status === 'pending').reduce((s: number, r: any) => s + r.amount, 0) / 100
const failMail = () => opsMails.find((m) => /SELHALA/.test(m.subject))
const db = () => (globalThis as any).__STORNO_DB
const now = () => Math.floor(Date.now() / 1000)

Deno.test({ name: 'i5 B1: selhaná storno vratka → dobropis zrušen sám; „Potvrdit vrácení“ bez ručního zrušení vrátí znovu, mail nelže', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  await velinCancel('full'); await deliver()
  world().refundStatus = () => 'succeeded'
  opsMails.length = 0
  await fail(world().refunds[0])
  const m = failMail()
  if (!m || /Zrušte dobropis/.test(m.html) || !/automaticky zrušen/.test(m.html) || !/Chybí vrátit <strong>3000 Kč/.test(m.html)) throw new Error(`mail obsluze: ${m?.html}`)
  if (cnKc() !== 0 || bk().payment_status !== 'refund_pending') throw new Error(`po selhání dobropisy ${cnKc()} Kč, stav ${bk().payment_status}`)
  advance(10); mails.length = 0
  await velinConfirm(3000); await deliver() // obsluha klikne „Potvrdit vrácení“ (nic ručně nerušila)
  const cm = customerMails().at(-1)
  if (liveKc() !== 3000 || cnKc() !== 3000 || cm?.amount !== 3000 || bk().payment_status !== 'refunded') {
    throw new Error(`vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč, mail zákazníkovi ${JSON.stringify(cm)}, stav ${bk().payment_status}`)
  }
} })

Deno.test({ name: 'i5 B2: selže jen zbytek z jiné platby → dobropis = hlavní vratka (ne „zrušte“); recovery i Velín dovrátí, dobropisy = vráceno', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const how of ['recovery', 'velin'] as const) {
    fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] })
    await velinCancel('full'); await deliver()
    opsMails.length = 0
    const rem = world().refunds.find((r: any) => r.metadata.mg_part === 'remainder')
    await fail(rem)
    const m = failMail()
    if (!m || /Zrušte dobropis/.test(m.html) || !/upraven z 3500 Kč na <strong>500 Kč/.test(m.html)) bad.push(`${how}: mail ${m?.html.slice(0, 600)}`)
    if (cnKc() !== 500 || bk().payment_status !== 'refund_pending') bad.push(`${how}: po selhání dobropisy ${cnKc()} Kč, stav ${bk().payment_status}`)
    advance(10)
    if (how === 'recovery') {
      const ch = world().charges.get('ch_ext1')
      await deliver([{ id: 'evt_again', type: 'charge.refunded', created: now(), data: { object: JSON.parse(JSON.stringify(ch)) } }])
      await call('process-refund', { booking_id: BID, reason: 'cancellation_retry' }, 'service'); await deliver()
    } else { await velinConfirm(3500); await deliver() }
    if (liveKc() !== 3500 || cnKc() !== 3500) bad.push(`${how}: vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč (${creditNotes().map((x: any) => x.total).join(', ')})`)
    const st = bk().payment_status
    await fail(rem, 'evt_ru_' + rem.id) // stará událost selhaného zbytku (druhý typ / opakované doručení) po dovrácení
    if (st !== 'refunded' || bk().payment_status !== 'refunded' || cnKc() !== 3500) bad.push(`${how}: po dovrácení ${st}, po staré události ${bk().payment_status}, dobropisy ${cnKc()} Kč`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5 B3: hlavní storno vratka selže, zbytek odešel → služba vrátí jen chybějící část, Velín správný součet; dobropisy = vráceno', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const via of ['service', 'velin', 'covered'] as const) {
    // uložená pi_ext1 (500) + původní 3000; storno zákazníkem 50 % = 1750: hlavní 500 z pi_ext1 (pending → selže), zbytek 1250 z pi_orig
    fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] })
    let n = 0
    world().refundStatus = () => (++n === 1 ? 'pending' : 'succeeded')
    await customerCancel('none', 50); await deliver()
    world().refundStatus = () => 'succeeded'
    opsMails.length = 0
    const main = world().refunds.find((r: any) => r.metadata.mg_part !== 'remainder')
    await fail(main)
    const m = failMail()
    if (!m || /Zrušte dobropis/.test(m.html) || !/na <strong>1250 Kč/.test(m.html) || !/Chybí vrátit <strong>500 Kč/.test(m.html)) bad.push(`${via}: mail ${m?.html.slice(0, 700)}`)
    if (cnKc() !== 1250) bad.push(`${via}: dobropis po selhání ${cnKc()} Kč (čekáno 1250)`)
    advance(10); mails.length = 0
    if (via === 'service') {
      const r = await pr(1750, 'service'); await deliver()
      if (r?.cancel_refunded_total !== 1750 || r?.amount_refunded !== 1750) bad.push(`service: odpověď ${JSON.stringify(r)}`)
    } else if (via === 'velin') {
      await velinConfirm(1750); await deliver() // P2 (majitel 2026-11-08): obsluha zadá CELKOVOU vratku storna 1750 → odejde chybějících 500
      const cm = customerMails().at(-1), last = rows('booking_cancellations').at(-1)
      if (cm?.amount !== 1750 || Number(last?.refund_amount) !== 1750) bad.push(`velin: mail ${JSON.stringify(cm)}, booking_cancellations ${last?.refund_amount}`)
    } else {
      // požadavek služby celý pokrytý osiřelým zbytkem → žádná nová vratka, stav dorovnán
      const r = await pr(1250, 'service'); await deliver()
      if (!r?.already_refunded || r?.cancel_refunded_total !== 1250 || world().refunds.length !== 2 || bk().payment_status !== 'partial_refund') {
        bad.push(`covered: ${JSON.stringify(r)}, vratek ${world().refunds.length}, stav ${bk().payment_status}`)
      }
      continue
    }
    if (liveKc() !== 1750 || cnKc() !== 1750) bad.push(`${via}: vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč — ${JSON.stringify(world().creates.map((x: any) => x.result))}`)
    if (bk().payment_status !== 'partial_refund') bad.push(`${via}: stav ${bk().payment_status}`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5 B3u: osiřelé zbytky storna (cancel-once) — počítají se do vráceného k tomuto stornu, ne k jinému', ignore: !MAPPED, fn: async () => {
  const co = await import(`${FN}process-refund/cancel-once.ts`)
  const tok = '2026-11-07T10:00:00.123456+00:00'
  const md = (x: Record<string, string>) => ({ mg_source: 'process-refund', mg_reason: 'cancellation', mg_booking_id: BID, mg_cancel_at: tok, ...x })
  const refunds = [
    { id: 're_m', amount: 50000, status: 'failed', created: 1, metadata: md({ mg_target: '175000' }) },
    { id: 're_r', amount: 125000, status: 'succeeded', created: 2, metadata: md({ mg_part: 'remainder', mg_main_refund: 're_m' }) },
    { id: 're_o', amount: 30000, status: 'succeeded', created: 3, metadata: md({ mg_part: 'remainder', mg_main_refund: 're_x', mg_cancel_at: '2026-10-01T10:00:00+00:00' }) },
  ]
  if (typeof co.orphanCancelRemainders !== 'function') throw new Error('orphanCancelRemainders chybí')
  const o = co.orphanCancelRemainders(refunds, BID, tok).map((r: any) => r.id)
  if (JSON.stringify(o) !== '["re_r"]' || co.cancellationRefundedHaleru(refunds, BID, tok) !== 125000) throw new Error(`osiřelé ${o}, vráceno ${co.cancellationRefundedHaleru(refunds, BID, tok)}`)
  refunds[0].status = 'succeeded' // hlavní živá → zbytek patří k ní, ne osiřelý
  if (co.orphanCancelRemainders(refunds, BID, tok).length || co.cancellationRefundedHaleru(refunds, BID, tok) !== 175000) throw new Error('živá hlavní vratka')
} })

Deno.test({ name: 'i5 B4: událost „failed“ staré vratky doručená PO úspěšném opakování neotevře rezervaci znovu', ignore: !MAPPED, fn: async () => {
  fresh(10); bk().total_price = 2500; world().refundStatus = () => 'pending'
  await pr(500, 'service', 'shortening'); await deliver()
  world().refundStatus = () => 'succeeded'
  const r1 = world().refunds[0]
  await fail(r1)
  advance(5)
  await pr(500, 'service', 'shortening'); await deliver() // opakování (klíč :f1) — uspěje
  const after = bk().payment_status
  await fail(r1, 'evt_ru_' + r1.id) // týž stav znovu (druhý typ události / Stripe opakuje doručení)
  const sup = rows('debug_log').some((d: any) => d.action === 'refund_updated_failed_superseded')
  if (after !== 'partial_refund' || bk().payment_status !== 'partial_refund' || liveKc() !== 500 || cnKc() !== 500 || !sup) {
    throw new Error(`po opakování ${after}, po staré události ${bk().payment_status}, vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč, superseded ${sup}`)
  }
} })

const payPi = (pi: string, czk: number, md: Record<string, string>, offsetS: number) => {
  world().addPi(pi, czk, md, offsetS)
  const o = world().intents.get(pi)!
  return deliver([{ id: 'evt_' + pi + '_' + Math.random().toString(36).slice(2, 7), type: 'payment_intent.succeeded', created: now(),
    data: { object: { id: pi, object: 'payment_intent', currency: 'czk', amount: o.amount, amount_received: o.amount_received, status: 'succeeded',
      metadata: o.metadata, customer: null, created: o.created, latest_charge: o.latest_charge } } }])
}
const redeliver = (pi: string) => {
  const o = world().intents.get(pi)!
  return deliver([{ id: 'evt_re_' + pi, type: 'payment_intent.succeeded', created: now(), data: { object: { id: pi, object: 'payment_intent', currency: 'czk',
    amount: o.amount, amount_received: o.amount_received, status: 'succeeded', metadata: o.metadata, customer: null, created: o.created, latest_charge: o.latest_charge } } }])
}
const refundedOf = (pi: string) => world().refunds.filter((r: any) => r.payment_intent === pi && r.status !== 'failed').reduce((s: number, r: any) => s + r.amount, 0) / 100

Deno.test({ name: 'i5 C1: nová platba zrušené a už vrácené rezervace → vratka / mail obsluze; znovu doručená událost nic nezopakuje', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  // a) zaplaceno PO stornu (druhá záložka / nová platba) → automatická vratka obou plateb, mail 1× na platbu
  fresh(10, { booking: { status: 'cancelled', payment_status: 'unpaid', booking_source: 'web', stripe_payment_intent_id: null, cancelled_at: new Date(Date.now() - 600_000).toISOString() } })
  world().intents.delete('pi_orig')
  db().rpcs.confirm_payment = () => ({ data: { success: false, error: 'moto_unavailable' }, error: null })
  await payPi('pi_late1', 3000, { booking_id: BID, type: 'booking' }, -120)
  await payPi('pi_late2', 3000, { booking_id: BID, type: 'booking' }, -10)
  await redeliver('pi_late2'); await redeliver('pi_late1')
  const auto = opsMails.filter((m) => /automaticky vrácena/.test(m.subject))
  if (refundedOf('pi_late1') !== 3000 || refundedOf('pi_late2') !== 3000 || world().refunds.length !== 2 || auto.length !== 2 || bk().status !== 'cancelled') {
    bad.push(`a) vráceno ${refundedOf('pi_late1')} + ${refundedOf('pi_late2')} Kč (${world().refunds.length} vratek), maily ${auto.length}, stav ${bk().status}`)
  }
  // b) zaplaceno před stornem a rezervace platbu neeviduje → nic automaticky, mail obsluze 1× (i po znovudoručení)
  fresh(10, { booking: { status: 'cancelled', payment_status: 'unpaid', booking_source: 'web', stripe_payment_intent_id: null, cancelled_at: new Date().toISOString() } })
  world().intents.delete('pi_orig')
  db().rpcs.confirm_payment = () => ({ data: { success: false, error: 'moto_unavailable' }, error: null })
  await payPi('pi_late1', 3000, { booking_id: BID, type: 'booking' }, 0) // stejný okamžik jako storno → pozdní platba (cancelled + unpaid)
  opsMails.length = 0
  await payPi('pi_late2', 3000, { booking_id: BID, type: 'booking' }, -60)
  await redeliver('pi_late2')
  const told = opsMails.filter((m) => /pi_late2/.test(m.html) && /zkontrolujte/i.test(m.subject))
  if (refundedOf('pi_late2') !== 0 || told.length !== 1) bad.push(`b) vráceno ${refundedOf('pi_late2')} Kč, maily obsluze ${told.length}`)
  // c) (kontrola) storno ve Velíně právě běží (refund_pending, vratka ještě nevznikla) a Stripe znovu doručí uloženou platbu → nic
  fresh(10)
  Object.assign(bk(), { status: 'cancelled', payment_status: 'refund_pending', cancelled_at: new Date().toISOString() })
  opsMails.length = 0
  await redeliver('pi_orig')
  if (world().refunds.length || opsMails.length || bk().status !== 'cancelled') bad.push(`c) vratek ${world().refunds.length}, maily ${opsMails.map((m) => m.subject)}`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5 F1: Fio doplatek úpravy ke ZRUŠENÉ rezervaci → nepotvrzen, obsluha; (kontrola) živá rezervace → potvrzen', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const status of ['cancelled', 'reserved'] as const) {
    fresh(10, { booking: { status, mod_surcharge_due: 500, mod_surcharge_vs: '7777001', payment_vs: '5555001' } })
    const calls: any[] = []
    db().rpcs.confirm_booking_surcharge = (a: any) => { calls.push(a); return { data: { success: true }, error: null } }
    rows('fio_transactions').push({ fio_id: 9001, tx_date: '2026-11-07', amount: 500, currency: 'CZK', vs: '7777001', counter_account: '123', counter_bank: '0100',
      counter_name: 'Zákazník', message: 'doplatek', tx_type: 'Příjem', status: 'new' })
    opsMails.length = 0
    await call('fio-sync', {}, 'service')
    const tx = rows('fio_transactions')[0]
    if (status === 'cancelled' && (calls.length || tx.status !== 'needs_review' || !opsMails.some((m) => /ZRUŠENÉ/.test(m.html)) || opsMails.some((m) => /potvrzen automaticky/i.test(m.html)))) {
      bad.push(`zrušená: RPC ${calls.length}×, stav ${tx.status}, maily ${opsMails.map((m) => m.subject).join(' | ')}`)
    }
    if (status === 'reserved' && (calls.length !== 1 || tx.status !== 'confirmed_surcharge')) bad.push(`živá: RPC ${calls.length}×, stav ${tx.status}`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5 A1: Adaptive Pricing — pozdní platba v EUR s přibalenou objednávkou → nic automaticky, mail „vraťte“ s částkou v Kč', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { status: 'cancelled', payment_status: 'unpaid', cancelled_at: new Date().toISOString(), stripe_payment_intent_id: null } })
  const md = { booking_id: BID, type: 'booking', source: 'web', shop_order_id: 'so-9' }
  world().addPi('pi_eur', 140, md, -60) // 14 000 eurocentů = 140 € (≈ 3 500 Kč)
  ;(world().intents.get('pi_eur') as any).currency = 'eur'
  rows('shop_orders').push({ id: 'so-9', order_number: 'OBJ-2026-0009', total: 500, shipping_cost: 100, payment_status: 'pending' })
  rows('shop_order_items').push({ id: 'it-9', order_id: 'so-9', product_name: 'Tričko', quantity: 2, unit_price: 200 })
  db().rpcs.confirm_payment = () => ({ data: { success: false, error: 'overlap' }, error: null })
  db().rpcs.confirm_shop_payment = () => { const so = rows('shop_orders')[0]; const was = so.payment_status === 'paid'; so.payment_status = 'paid'; return { data: { success: true, was_already_paid: was }, error: null } }
  const sess = { id: 'cs_ap_9', object: 'checkout.session', mode: 'payment', payment_status: 'paid', status: 'complete', currency: 'eur', amount_total: 14000,
    currency_conversion: { source_currency: 'czk', amount_total: 350000, amount_subtotal: 350000, fx_rate: '0.04' }, payment_intent: 'pi_eur',
    metadata: md, client_reference_id: BID, customer: null, created: now() }
  await deliver([{ id: 'evt_cs_ap9', type: 'checkout.session.completed', created: sess.created, data: { object: sess } }])
  const m = opsMails.find((x) => /Platba zrušené rezervace/.test(x.subject))
  if (world().refunds.length || !m || !/VRAŤTE RUČNĚ/.test(m.subject) || !/3000 Kč<\/strong> z ceny v CZK/.test(m.html) || !/500 Kč vč\. dopravy/.test(m.html)) {
    throw new Error(`vratek ${world().refunds.length}, mail ${m?.subject}: ${m?.html.replace(/<[^>]+>/g, ' ').slice(0, 500)}`)
  }
} })

Deno.test({ name: 'i5 A2: Adaptive Pricing — nezapsaná placená změna v HUF → vratka CELÉ platby (ne haléře CZK jako forinty)', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { status: 'cancelled', payment_status: 'refunded', cancelled_at: new Date().toISOString() } })
  const md = { booking_id: BID, type: 'extension', attempt_id: 'att-0003-cccc' }
  world().addPi('pi_huf', 31000, md, -60) // 3 100 000 nejmenších jednotek = 31 000 HUF ≈ 2 000 Kč
  ;(world().intents.get('pi_huf') as any).currency = 'huf'
  const sess = { id: 'cs_ap_huf', object: 'checkout.session', mode: 'payment', payment_status: 'paid', status: 'complete', currency: 'huf', amount_total: 3100000,
    currency_conversion: { source_currency: 'czk', amount_total: 200000, amount_subtotal: 200000, fx_rate: '15.5' }, payment_intent: 'pi_huf',
    metadata: md, client_reference_id: BID, customer: null, created: now() }
  await deliver([{ id: 'evt_cs_huf', type: 'checkout.session.completed', created: sess.created, data: { object: sess } }])
  const re = world().refunds.filter((r: any) => r.payment_intent === 'pi_huf')
  const pcf = rows('debug_log').find((d: any) => d.action === 'paid_change_failed')
  const m = opsMails.find((x) => /nešlo zapsat/.test(x.subject))
  if (re.length !== 1 || re[0].amount !== 3100000 || pcf?.response_data?.refund !== 'auto' || !m || !/2[\s ]?000 Kč/.test(m.html) || webhookStatuses.at(-1) !== 200) {
    throw new Error(`vratky ${JSON.stringify(re.map((r: any) => r.amount))}, režim ${pcf?.response_data?.refund}, mail ${m?.html.slice(0, 300)}`)
  }
} })
