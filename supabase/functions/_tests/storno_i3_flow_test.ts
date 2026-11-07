// ===== _tests/storno_i3_flow_test.ts =====
// Oprava i3 (2026-11-07) po třetí adversariální verifikaci vratek (verify:refunds):
//  V1  QR / převod: zkrácení (ruční dobropis 500, cena 2500), pak storno 100 % → dobropisy celkem 3000 (dřív 2500:
//      dlužná částka total_price − dobropisy odečetla snížení ceny dvakrát); totéž u výbavy (gear_edit),
//  V1b karta 3000 + doplatek 1000 převodem, zkrácení 500 kartou, plné storno → převodem placená část celá (1000, dřív 500),
//  V36 karta 3000 + doplatek 500 převodem, vratka 500 v Stripe dashboardu bez dobropisu, plné storno z Velínu →
//      celkem ven nejvýš 3500 (dřív ruční dobropis 1000 → 4000),
//  V7  platba rezervace 3000 + přibalené zboží 500 (jedna platba): storno 100 % → 'refunded', jen 3000; další
//      vratka obsluhy (V7c) ani plné volání bez zůstatku (V7d) nevrátí peníze za zboží,
//  V2  zpožděný charge.refunded vratky zkrácení mezi commitem cancel_booking_tracked a jeho pg_net voláním → pojistný
//      storno mail webhooku claim nevezme (není to vratka tohoto storna), storno vratka proběhne,
//  V26 plná vratka doplatku v dashboardu rezervaci neruší (zůstatek v ceně > 0); externí vratka původní platby
//      (neuložené) se dohledá podle metadat platby,
//  V3  Velín storno rezervace 'partial_refund' (po vratce zkrácení): starší Velín bez volby vratky → jen mail (dřív
//      % z tabulky storna přes process-refund); nový Velín nabídne volbu (paidForRefund) a pošle ji vždy (i 0),
//  V8  pozdní platba zrušené rezervace s přibaleným zbožím (confirm_payment revive_failed) → vratka jen části za
//      rezervaci, objednávka e-shopu potvrzena (dřív vratka celé platby a zboží odešlo zdarma),
//  V10 mail úpravy s vratkou (send-booking-email booking_modified), ke které dobropis nevznikl → „vratku dokončuje
//      obsluha“ místo „dobropis v příloze, zpět na kartu“ + mail obsluze.
// Na kódu před opravou i3 testy PADAJÍ (STORNO_FN_DIR=<strom před opravou>). Spouští storno_hotfix_test.ts.
// deno-lint-ignore-file no-explicit-any
import { BID, EMAIL, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, loadFn, mails, opsMails, refundedKc, rows, world } from './storno-harness.ts'
import { customerCancel, rpcCancel, velinCancel, velinCancelLegacyUnpaid, velinConfirm } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()

const pr = (amount?: number, as: 'service' | 'admin' | 'customer' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)
const manualCnKc = () => creditNotes().filter((c) => c.stripe_refund_id == null).reduce((s, c) => s + Math.abs(Number(c.total) || 0), 0)
const QR = { payment_method: 'qr', pay_channel: 'qr', stripe_payment_intent_id: null }

Deno.test({ name: 'i3 V1: QR — zkrácení 500 (ruční dobropis), pak storno 100 % zákazníkem → dobropisy 3000 (motorka i výbava)', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [lab, gear, reason] of [['motorka', false, 'shortening'], ['výbava', true, 'gear_edit']] as Array<[string, boolean, string]>) {
    fresh(10, { gear, booking: { ...QR } })
    rows('fio_transactions').push({ fio_id: 1, booking_id: BID, amount: 3000, vs: '123', counter_account: '111', counter_bank: '0100' })
    bk().total_price = 2500
    const s = await pr(500, 'service', reason)
    if (!s?.manual || Number(s.amount) !== 500) bad.push(`${lab}: zkrácení ${JSON.stringify(s)}`)
    advance(20)
    const c = await customerCancel('none')
    if (c.amt !== 2500) bad.push(`${lab}: RPC částka ${c.amt}`)
    if (cnKc() !== 3000 || creditNotes().length !== 2) bad.push(`${lab}: dobropisy ${cnKc()} Kč / ${creditNotes().length} (čekáno 3000 / 2)`)
    if (rows('debug_log').some((d) => d.action === 'manual_refund_capped_docs')) bad.push(`${lab}: storno oříznuto (manual_refund_capped_docs)`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i3 V1b: karta 3000 + doplatek 1000 převodem, zkrácení 500 kartou, plné storno z Velínu → převodem placená část celá (1000), ven celkem 4000', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { total_price: 4000, mod_surcharge_vs: '2026002', mod_surcharge_paid_at: new Date().toISOString() } })
  rows('invoices').push({ id: crypto.randomUUID(), booking_id: BID, type: 'payment_receipt', status: 'issued', total: 1000, number: 'DP-2026-1501', issue_date: '2026-10-02', created_at: new Date().toISOString() })
  rows('fio_transactions').push({ fio_id: 8, booking_id: BID, amount: 1000, vs: '2026002', counter_account: '111', counter_bank: '0100' })
  bk().total_price = 3500
  await pr(500, 'service', 'shortening'); await deliver()
  bk().payment_status = 'paid'
  advance(20)
  await velinCancel('full'); await deliver()
  if (refundedKc() !== 3000 || manualCnKc() !== 1000) throw new Error(`Stripe ${refundedKc()} (čekáno 3000), ruční dobropisy ${manualCnKc()} (čekáno 1000)`)
} })

Deno.test({ name: 'i3 V36: karta 3000 + 500 převodem, vratka 500 v dashboardu bez dobropisu, plné storno z Velínu → ven celkem 3500, ne víc', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { total_price: 3500, mod_surcharge_vs: '2026001', mod_surcharge_paid_at: new Date().toISOString() } })
  rows('invoices').push({ id: crypto.randomUUID(), booking_id: BID, type: 'payment_receipt', status: 'issued', total: 500, number: 'DP-2026-1500', issue_date: '2026-10-02', created_at: new Date().toISOString() })
  rows('fio_transactions').push({ fio_id: 7, booking_id: BID, amount: 500, vs: '2026001', counter_account: '111', counter_bank: '0100' })
  await world().dashboardRefund('pi_orig', 50000); await deliver()
  advance(5)
  await velinCancel('full'); await deliver()
  const r = await velinConfirm(3500); await deliver()
  const out = refundedKc() + manualCnKc()
  if (out !== 3500) throw new Error(`ven celkem ${out} Kč (Stripe ${refundedKc()}, ruční dobropisy ${manualCnKc()}) — čekáno 3500; Velín ${JSON.stringify(r)}`)
  if (manualCnKc() !== 500) throw new Error(`ruční dobropis ${manualCnKc()} (čekáno 500)`)
} })

Deno.test({ name: 'i3 V36b: doplatek označený zaplaceným BEZ platby převodem (hotově / ručně) → žádný automatický ruční dobropis, mail obsluze', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { total_price: 3500, mod_surcharge_vs: '2026001', mod_surcharge_paid_at: new Date().toISOString() } })
  rows('invoices').push({ id: crypto.randomUUID(), booking_id: BID, type: 'payment_receipt', status: 'issued', total: 500, number: 'DP-2026-1500', issue_date: '2026-10-02', created_at: new Date().toISOString() })
  await velinCancel('full'); await deliver()
  if (refundedKc() !== 3000 || manualCnKc() !== 0) throw new Error(`Stripe ${refundedKc()}, ruční dobropisy ${manualCnKc()} (čekáno 3000 / 0)`)
  if (!opsMails.some((m) => /nejde vrátit automaticky/.test(m.subject))) throw new Error(`mail obsluze ${JSON.stringify(opsMails.map((m) => m.subject))}`)
} })

function bundled() {
  fresh(10)
  world().addPi('pi_orig', 3500, { booking_id: BID, type: 'booking', shop_order_id: 'so-1' })
  rows('shop_orders').push({ id: 'so-1', total: 500, payment_status: 'paid', stripe_payment_intent_id: 'pi_orig' })
}

Deno.test({ name: 'i3 V7/V7c: platba 3000 + přibalené zboží 500 — storno 100 % → refunded, další vratka obsluhy nevrátí peníze za zboží', ignore: !MAPPED, fn: async () => {
  bundled()
  await customerCancel('none'); await deliver()
  if (refundedKc() !== 3000) throw new Error(`vráceno ${refundedKc()} (čekáno 3000)`)
  if (bk().payment_status !== 'refunded') throw new Error(`stav ${bk().payment_status} (čekáno refunded)`)
  advance(10)
  await pr(1000, 'admin'); await deliver()
  if (refundedKc() !== 3000 || cnKc() !== 3000) throw new Error(`V7c: vráceno ${refundedKc()}, dobropisy ${cnKc()} (čekáno 3000 / 3000)`)
} })

Deno.test({ name: 'i3 V7d: přibalené zboží — plné storno z Velínu vrátí 3000, další plné volání bez zůstatku nevrátí nic (no_op)', ignore: !MAPPED, fn: async () => {
  bundled()
  await velinCancel('full'); await deliver()
  if (refundedKc() !== 3000 || bk().payment_status !== 'refunded') throw new Error(`vráceno ${refundedKc()}, stav ${bk().payment_status}`)
  bk().payment_status = 'refund_pending' // např. Velín storno znovu / ruční změna stavu
  advance(10)
  const r = await pr(undefined, 'admin'); await deliver()
  if (refundedKc() !== 3000) throw new Error(`vráceno ${refundedKc()} (čekáno 3000 — zbylých 500 jsou peníze za zboží); odpověď ${JSON.stringify(r)}`)
  if (bk().payment_status !== 'refunded') throw new Error(`stav ${bk().payment_status}`)
} })

Deno.test({ name: 'i3 V2: zpožděný webhook vratky zkrácení dorazí mezi commitem storna a voláním RPC → storno vratka i mail proběhnou (3000 celkem, mail 2500)', ignore: !MAPPED, fn: async () => {
  fresh(10); bk().total_price = 2500
  const s = await pr(500, 'service', 'shortening')
  if (!s?.success || refundedKc() !== 500) throw new Error(`zkrácení ${JSON.stringify(s)}`)
  const held = world().takeEvents() // charge.refunded zkrácení se zpozdí
  advance(5)
  const c = rpcCancel()
  await deliver(held) // dorazí po commitu cancel_booking_tracked, před jeho pg_net voláním
  await c.R(); await deliver()
  if (refundedKc() !== 3000) throw new Error(`vráceno ${refundedKc()} (čekáno 3000)`)
  const cm = customerMails()
  if (cm.length !== 1 || cm[0].amount !== 2500) throw new Error(`maily zákazníkovi ${JSON.stringify(cm)} (čekán jeden s 2500)`)
} })

Deno.test({ name: 'i3 V26/V26b: plná vratka DOPLATKU 115 v dashboardu (3000 + 115) rezervaci neruší; pozdější storno vrátí i 3000', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 115 }] })
  await world().dashboardRefund('pi_ext1'); await deliver()
  if (bk().status === 'cancelled' || bk().payment_status !== 'partial_refund') throw new Error(`stav ${bk().status} / ${bk().payment_status} (čekáno živá, partial_refund)`)
  if (customerMails().length) throw new Error(`storno mail zákazníkovi ${JSON.stringify(customerMails())}`)
  if (!opsMails.some((m) => /NEzrušena/.test(m.subject))) throw new Error(`mail obsluze ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  advance(5)
  await customerCancel('none'); await deliver()
  if (refundedKc() !== 3115) throw new Error(`V26b: vráceno ${refundedKc()} (čekáno 3115 = 115 dashboard + 3000 storno)`)
} })

Deno.test({ name: 'i3 V26d: doplatek s dřívější NAŠÍ vratkou (úprava 50), zbytek doplatku vrácen v dashboardu → partial_refund (ne refunded), mail obsluze', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 115 }] })
  await pr(50, 'service', 'booking_modified'); await deliver()
  if (bk().payment_status !== 'partial_refund') throw new Error(`po vratce úpravy ${bk().payment_status}`)
  await world().dashboardRefund('pi_ext1'); await deliver()
  if (bk().status === 'cancelled' || bk().payment_status !== 'partial_refund') throw new Error(`stav ${bk().status} / ${bk().payment_status} (čekáno živá, partial_refund — na původní platbě zbývá 3000)`)
  if (!opsMails.some((m) => /NEzrušena/.test(m.subject))) throw new Error(`mail obsluze ${JSON.stringify(opsMails.map((m) => m.subject))}`)
} })

Deno.test({ name: 'i3 V26c: externí vratka PŮVODNÍ platby (uložený je doplatek) → rezervace dohledána podle metadat, partial_refund + mail obsluze', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 115 }] })
  await world().dashboardRefund('pi_orig'); await deliver()
  if (bk().status === 'cancelled' || bk().payment_status !== 'partial_refund') throw new Error(`stav ${bk().status} / ${bk().payment_status} (čekáno živá, partial_refund)`)
  if (!opsMails.some((m) => /NEzrušena/.test(m.subject))) throw new Error(`mail obsluze ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  // a plná vratka i doplatku → nic nezbývá → storno přes Stripe portál jako dřív
  await world().dashboardRefund('pi_ext1'); await deliver()
  if (bk().status !== 'cancelled' || bk().payment_status !== 'refunded' || bk().cancelled_by_source !== 'stripe_portal') throw new Error(`po 2. vratce ${bk().status} / ${bk().payment_status} / ${bk().cancelled_by_source}`)
} })

Deno.test({ name: 'i3 V3: storno z Velínu po vratce zkrácení (partial_refund) — bez volby obsluhy nic nevrací; s volbou vrátí zvolené (i 0)', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  const shortened = async () => {
    fresh(10); bk().total_price = 2500
    await pr(500, 'service', 'shortening'); await deliver()
    if (bk().payment_status !== 'partial_refund') bad.push(`po zkrácení stav ${bk().payment_status}`)
    advance(20)
  }
  // a) starší Velín (během nasazení): bez refund_amount / refund_percent → jen mail, žádná vratka z tabulky storna
  await shortened(); await velinCancelLegacyUnpaid(); await deliver()
  if (refundedKc() !== 500) bad.push(`a) bez volby vráceno ${refundedKc()} (čekáno jen 500 zkrácení)`)
  if (customerMails().length !== 1) bad.push(`a) maily ${JSON.stringify(customerMails())}`)
  // b) nový Velín: volba 1250 → vrátí 1250, booking_cancellations zapsán, mail 1250
  await shortened(); await velinCancel(1250); await deliver()
  if (refundedKc() !== 1750) bad.push(`b) vráceno ${refundedKc()} (čekáno 500 + 1250)`)
  if (Number(rows('booking_cancellations').at(-1)?.refund_amount) !== 1250) bad.push(`b) booking_cancellations ${JSON.stringify(rows('booking_cancellations'))}`)
  if (customerMails().at(-1)?.amount !== 1250) bad.push(`b) mail ${JSON.stringify(customerMails())}`)
  // c) nový Velín „bez vratky“ → nic dalšího
  await shortened(); await velinCancel(0); await deliver()
  if (refundedKc() !== 500) bad.push(`c) bez vratky vráceno ${refundedKc()}`)
  // d) nový Velín plné storno → zbytek 2500
  await shortened(); await velinCancel('full'); await deliver()
  if (refundedKc() !== 3000) bad.push(`d) plné storno vráceno ${refundedKc()} (čekáno 3000)`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i3 V8: pozdní platba zrušené rezervace s přibaleným zbožím (revive_failed) → vrátí se jen část za rezervaci, objednávka potvrzena jednou', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { status: 'cancelled', payment_status: 'unpaid', cancelled_at: new Date().toISOString(), stripe_payment_intent_id: null } })
  const db = (globalThis as any).__STORNO_DB
  const md = { booking_id: BID, type: 'booking', source: 'web', shop_order_id: 'so-8' }
  world().addPi('pi_late', 3500, md, -60)
  rows('shop_orders').push({ id: 'so-8', order_number: 'OBJ-2026-0008', total: 500, shipping_cost: 100, payment_status: 'pending' })
  rows('shop_order_items').push({ id: 'it-1', order_id: 'so-8', product_name: 'Tričko', quantity: 2, unit_price: 200 })
  db.rpcs.confirm_payment = () => ({ data: { success: false, error: 'overlap' }, error: null })
  let shopConfirms = 0
  db.rpcs.confirm_shop_payment = () => { shopConfirms++; const so = rows('shop_orders')[0]; const was = so.payment_status === 'paid'; so.payment_status = 'paid'
    return { data: { success: true, was_already_paid: was }, error: null } }
  const ev = (id: string) => ({ id, type: 'payment_intent.succeeded', created: Math.floor(Date.now() / 1000), data: { object: { id: 'pi_late', object: 'payment_intent',
    amount: 350000, amount_received: 350000, currency: 'czk', status: 'succeeded', metadata: md, customer: 'cus_1', created: Math.floor(Date.now() / 1000), latest_charge: 'ch_late' } } })
  await deliver([ev('evt_l1')]); await deliver([ev('evt_l2')]) // Stripe doručí i znovu
  world().takeEvents()
  if (refundedKc() !== 3000) throw new Error(`vráceno ${refundedKc()} (čekáno 3000 = platba 3500 − zboží 400 − doprava 100)`)
  if (rows('shop_orders')[0].payment_status !== 'paid' || shopConfirms < 1) throw new Error(`objednávka ${rows('shop_orders')[0].payment_status}, potvrzení ${shopConfirms}`)
  if (bk().status !== 'cancelled') throw new Error(`rezervace ${bk().status}`)
  const m = opsMails.find((x) => /Platba zrušené rezervace/.test(x.subject))
  if (!m || !/jen část za rezervaci/.test(m.html) || !/OBJ-2026-0008/.test(m.html)) throw new Error(`mail obsluze ${JSON.stringify(opsMails.map((x) => x.subject))} ${m?.html.slice(0, 400)}`)
} })

Deno.test({ name: 'i3 V10: mail úpravy s vratkou, ke které dobropis NEVZNIKL → „dokončuje obsluha“ (bez dobropisu v příloze / karty), mail obsluze; s dobropisem beze změny', ignore: !MAPPED, fn: async () => {
  await loadFn('send-booking-email')
  const send = () => call('send-booking-email', { type: 'booking_modified', booking_id: BID, customer_email: EMAIL, customer_name: 'Test Zákazník',
    price_difference: -500, language: 'cs', source: 'app' })
  const last = () => mails.filter((m) => m.to === EMAIL).at(-1)?.html || ''
  // a) vratka se k serveru nedostala (appka zapsala cenu, process-refund nedoběhl) → žádný dobropis
  fresh(10); bk().total_price = 2500
  await send()
  const a = last()
  if (!/vratku dokončuje obsluha/.test(a) || /formou dobropisu|původní platební kartu/.test(a)) throw new Error(`a) mail ${a.slice(a.indexOf('upravena'), a.indexOf('upravena') + 1500)}`)
  if (!opsMails.some((m) => /vratka \/ dobropis chybí/.test(m.subject))) throw new Error(`a) mail obsluze ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  // b) vratka proběhla (dobropis 500) → dosavadní text s dobropisem v příloze, bez mailu obsluze
  fresh(10); bk().total_price = 2500
  await pr(500, 'service', 'shortening')
  await send()
  const b = last()
  if (!/formou dobropisu/.test(b) || /dokončuje obsluha/.test(b)) throw new Error(`b) mail ${b.slice(b.indexOf('upravena'), b.indexOf('upravena') + 1500)}`)
  if (opsMails.some((m) => /dobropis chybí/.test(m.subject))) throw new Error(`b) zbytečný mail obsluze`)
} })

Deno.test('i3 refund-split: dobropisy jen tohoto storna, karta + převod (Fio odesláno / čeká), text ve všech 8 jazycích', async () => {
  const { Db } = await import('./storno-fake-db.ts')
  const { loadRefundSplit, refundSplitNote } = await import('../send-cancellation-email/refund-split.ts')
  const at = '2026-11-07T10:00:00.000Z'
  const cn = (id: string, total: number, re: string | null, created: string) => ({ id, booking_id: BID, type: 'credit_note', status: 'issued', total, stripe_refund_id: re, created_at: created })
  const mk = (fio: string) => new Db({ bookings: [{ id: BID, cancelled_at: at }], invoices: [
    cn('c0', -500, 're_old', '2026-11-06T10:00:00.000Z'), // dřívější zkrácení — do storna nepatří
    cn('c1', -3000, 're_1', '2026-11-07T10:00:05.000Z'), cn('c2', -500, null, '2026-11-07T10:00:06.000Z')],
    fio_payment_orders: [{ credit_note_id: 'c2', status: fio }] })
  const sent = await loadRefundSplit(mk('submitted'), BID), pending = await loadRefundSplit(mk('failed'), BID)
  const J = JSON.stringify
  if (J(sent) !== J({ cardCzk: 3000, bankCzk: 500, bankSent: true, cnIds: ['c1', 'c2'] })) throw new Error(`odesláno ${J(sent)}`)
  if (pending?.bankSent !== false) throw new Error(`čeká ${J(pending)}`)
  const nb = (s: string) => s.replace(/[  ]/g, ' ')
  if (!/jsme vám odeslali převodem/.test(refundSplitNote('cs', sent!)) || !/vám pošleme převodem na bankovní účet do 14 dnů/.test(refundSplitNote('cs', pending!))) throw new Error('cs text')
  if (!/ti pošleme převodem/.test(refundSplitNote('cs', pending!, { informal: true }))) throw new Error('cs tykání')
  for (const l of ['cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk']) {
    const t = nb(refundSplitNote(l, pending!))
    if (!t.includes('3 000') || !t.includes('>500 ')) throw new Error(`${l}: ${t}`)
  }
})
