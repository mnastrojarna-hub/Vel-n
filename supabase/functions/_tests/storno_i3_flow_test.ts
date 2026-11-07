// ===== _tests/storno_i3_flow_test.ts =====
// Oprava i3 (2026-11-07) po třetí adversariální verifikaci vratek (verify:refunds):
//  V1  QR / převod: zkrácení (ruční dobropis 500, cena 2500), pak storno 100 % → dobropisy celkem 3000 (dřív 2500:
//      dlužná částka total_price − dobropisy odečetla snížení ceny dvakrát); totéž u výbavy (gear_edit),
//  V1b karta 3000 + doplatek 1000 převodem, zkrácení 500 kartou, plné storno → převodem placená část celá (1000, dřív 500),
//  V36 karta 3000 + doplatek 500 převodem, vratka 500 v Stripe dashboardu bez dobropisu, plné storno z Velínu →
//      celkem ven nejvýš 3500 (dřív ruční dobropis 1000 → 4000),
//  V7  platba rezervace 3000 + přibalené zboží 500 (jedna platba): storno 100 % → 'refunded', jen 3000; další
//      vratka obsluhy (V7c) ani plné volání bez zůstatku (V7d) nevrátí peníze za zboží,
//  V3  Velín storno rezervace 'partial_refund' (po vratce zkrácení): starší Velín bez volby vratky → jen mail (dřív
//      % z tabulky storna přes process-refund); nový Velín nabídne volbu (paidForRefund) a pošle ji vždy (i 0).
//  Webhook + maily (V2, V26, V8, V10, refund-split) → storno_i3_mail_flow_test.ts.
// Na kódu před opravou i3 testy PADAJÍ (STORNO_FN_DIR=<strom před opravou>). Spouští storno_hotfix_test.ts.
// deno-lint-ignore-file no-explicit-any
import { BID, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, opsMails, refundedKc, rows, world } from './storno-harness.ts'
import { customerCancel, velinCancel, velinCancelLegacyUnpaid, velinConfirm } from './storno-dispatch.ts'

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

