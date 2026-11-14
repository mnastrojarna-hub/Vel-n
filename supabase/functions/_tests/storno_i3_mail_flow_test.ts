// ===== _tests/storno_i3_mail_flow_test.ts =====
// Oprava i3 (2026-11-07), část webhook + maily (rozděleno ze storno_i3_flow_test.ts kvůli velikosti souboru):
//  V2  zpožděný charge.refunded vratky zkrácení mezi commitem cancel_booking_tracked a jeho pg_net voláním → pojistný
//      storno mail webhooku claim nevezme (není to vratka tohoto storna), storno vratka proběhne,
//  V26 plná vratka doplatku v dashboardu rezervaci neruší (zůstatek v ceně > 0); V26d totéž po dřívější naší vratce
//      z doplatku; V26c externí vratka původní (neuložené) platby se dohledá podle metadat platby,
//  V8  pozdní platba zrušené rezervace s přibaleným zbožím (confirm_payment revive_failed) → vratka jen části za
//      rezervaci, objednávka e-shopu potvrzena (dřív vratka celé platby a zboží odešlo zdarma),
//  V10 mail úpravy s vratkou (send-booking-email booking_modified), ke které dobropis nevznikl → „vratku dokončuje
//      obsluha“ místo „dobropis v příloze, zpět na kartu“ + mail obsluze,
//  refund-split: odstavec storna karta + převod (send-cancellation-email/refund-split.ts) v 8 jazycích.
// Na kódu před opravou i3 testy PADAJÍ (STORNO_FN_DIR=<strom před opravou>). Spouští storno_hotfix_test.ts.
// deno-lint-ignore-file no-explicit-any
import { BID, EMAIL, advance, bk, boot, call, customerMails, deliver, fresh, loadFn, mails, opsMails, refundedKc, rows, world } from './storno-harness.ts'
import { customerCancel, rpcCancel } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()

const pr = (amount?: number, as: 'service' | 'admin' | 'customer' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)

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
