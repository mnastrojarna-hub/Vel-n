// ===== _tests/storno_i2_flow_test.ts =====
// Oprava i2 (2026-11-05) po druhé adversariální verifikaci vratek (process-refund / webhook-receiver / send-cancellation-email):
//  B1 dvě zkrácení o stejnou částku do 15 min (appka edit_shortening, web shortening, ruční platba) → dvě vratky; duplicitní
//     dispatch (cena se nesnížila) → jedna,
//  B2 kartová rezervace + doplatek zaplacený převodem: plné storno z Velínu vrátí kartu, na převodem placenou část vystaví
//     ruční dobropis (refund_pending), mail obsluze; druhé volání (mail Velínu) nevrací podruhé a zákazníkovi neslibuje vrácení,
//  B3 ruční vratka (QR): „Potvrdit vrácení“ 100 % po dřívější ruční vratce 500 → dobropis i Fio příkaz jen na zbytek 2 500,
//  B4 souběžný dispatch téže vratky BEZ unikátního indexu → jeden dobropis, jeden účetní záznam,
//  B5 pád process-refund po refunds.create u DRUHÉ vratky → recovery z webhooku vystaví dobropis k druhé vratce,
//  B6 vratka „pending“ dokončená později → charge.refund.updated / další volání dorovná stav (refund_pending → refunded),
//  B7 pojistný storno mail webhooku po selhání zbytku: neslibuje celou částku (dokončuje obsluha).
// Na verzi před opravou i2 tyto testy PADAJÍ. Spouští storno_hotfix_test.ts v podprocesu s import mapou.
// deno-lint-ignore-file no-explicit-any
import { BID, EMAIL, advance, bk, boot, call, cnKc, creditNotes, deliver, fresh, insert, mails, opsMails, refundedKc, rows, world, type ExtraPi } from './storno-harness.ts'
import { velinCancel, velinConfirm } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()

const TWO: ExtraPi[] = [{ id: 'pi_ext1', czk: 115 }] // 3115 Kč, uložená platba pi_ext1
const db = () => (globalThis as any).__STORNO_DB
const dl = (action: string) => rows('debug_log').filter((d) => d.action === action)
function money(label: string, refunded: number, cn = refunded) {
  const r = refundedKc(), c = cnKc()
  if (r !== refunded || c !== cn) throw new Error(`${label}: vráceno ${r} (čekáno ${refunded}), dobropisy ${c} (čekáno ${cn}), stripe ${JSON.stringify(world().creates.map((x) => x.result))}`)
}
const pr = (amount?: number, as: 'service' | 'admin' | 'customer' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)
const sce = (amount: number) => call('send-cancellation-email', { booking_id: BID, customer_email: EMAIL, cancellation_reason: 'Storno (Velín)',
  cancelled_by_source: 'velin', source: 'app', refund_amount: amount, refund_percent: Math.round(amount / 31.15) }, 'admin')
const velinUpd = () => Object.assign(bk(), { status: 'cancelled', cancelled_at: new Date().toISOString(), payment_status: 'refund_pending',
  cancelled_by_source: 'velin', cancellation_reason: 'Storno (Velín)' })
/** ceník pro spodní mez zákaznické vratky (customerPriceFloorCzk: 0,8 × 2000 = 1600) */
const priceList = () => { db().rpcs._moto_dayprice_sum = () => ({ data: 2000, error: null }) }
function failOrig(on: boolean) { world().onBeforeCreate = on ? (p) => { if (p.payment_intent === 'pi_orig') throw new Error('Stripe: transient') } : null }
function killAfterRefund(n: number) {
  let k = 0; world().onRefundCreated = async () => { if (++k === n) { world().onRefundCreated = null; throw new Error('isolate killed') } }
}
const custMails = () => mails.filter((m) => m.to === EMAIL)
const deferredMail = (m: { html: string }) => /dokončuje obsluha/.test(m.html) && !/byl zpracován a vrácen/.test(m.html)

Deno.test({ name: 'i2 B1: dvě zkrácení o stejnou částku do 15 min (appka / web / QR) → dvě vratky; duplicitní dispatch → jedna', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [lab, as, reason] of [['appka', 'customer', 'edit_shortening'], ['web', 'service', 'shortening']] as Array<[string, 'customer' | 'service', string]>) {
    fresh(10); priceList()
    bk().total_price = 2500
    const a = await pr(500, as, reason)
    bk().total_price = 2000
    const b = await pr(500, as, reason)
    try { money(`B1 ${lab} dvě zkrácení`, 1000) } catch (e) { bad.push((e as Error).message) }
    if (!a?.success || !b?.success || b.already_refunded) bad.push(`B1 ${lab}: odpovědi ${JSON.stringify([a, b])}`)
    if (creditNotes().length !== 2) bad.push(`B1 ${lab}: dobropisů ${creditNotes().length}`)
    // duplicitní dispatch téže vratky (cena se nesnížila) → žádná další vratka
    const c = await pr(500, as, reason)
    try { money(`B1 ${lab} duplicita`, 1000) } catch (e) { bad.push((e as Error).message) }
    if (!c?.success || !c.already_refunded) bad.push(`B1 ${lab} duplicita: ${JSON.stringify(c)}`)
  }
  // ruční platba (QR): dvě odebrané položky výbavy za stejnou cenu (RPC → service, gear_edit)
  fresh(10, { booking: { payment_method: 'qr', pay_channel: 'qr', stripe_payment_intent_id: null } })
  rows('fio_transactions').push({ fio_id: 1, booking_id: BID, amount: 3000, vs: '123', counter_account: '111', counter_bank: '0100' })
  bk().total_price = 2500; const m1 = await pr(500, 'service', 'gear_edit')
  bk().total_price = 2000; const m2 = await pr(500, 'service', 'gear_edit')
  if (!m1?.manual || !m2?.manual || m1.credit_note_id === m2.credit_note_id || cnKc() !== 1000) bad.push(`B1 QR: ${JSON.stringify([m1, m2])}, dobropisy ${cnKc()}`)
  const m3 = await pr(500, 'service', 'gear_edit')
  if (m3?.credit_note_id !== m2.credit_note_id || cnKc() !== 1000) bad.push(`B1 QR duplicita: ${JSON.stringify(m3)}, dobropisy ${cnKc()}`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i2 B2: karta 3000 + doplatek 500 převodem, plné storno z Velínu → karta 3000, ruční dobropis 500 (refund_pending), mail obsluze, zákazník bez slibu', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { total_price: 3500, mod_surcharge_vs: '2026001', mod_surcharge_paid_at: new Date().toISOString() } })
  rows('invoices').push({ id: crypto.randomUUID(), booking_id: BID, type: 'payment_receipt', status: 'issued', total: 500, number: 'DP-2026-1500', issue_date: '2026-10-02', created_at: new Date().toISOString() })
  rows('fio_transactions').push({ fio_id: 7, booking_id: BID, amount: 500, vs: '2026001', counter_account: '111', counter_bank: '0100' })
  await velinCancel('full'); await deliver()
  money('B2', 3000, 3500)
  const cns = creditNotes()
  if (cns.length !== 2 || !cns.some((c) => c.stripe_refund_id == null && Math.abs(Number(c.total)) === 500)) throw new Error(`dobropisy ${JSON.stringify(cns.map((c) => [c.total, c.stripe_refund_id]))}`)
  if (bk().payment_status !== 'refund_pending') throw new Error(`stav ${bk().payment_status} (čekáno refund_pending — převodem placená část čeká na obsluhu)`)
  if (!opsMails.some((m) => /zaplaceno převodem/.test(m.subject))) throw new Error(`mail obsluze ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  const cm = custMails()
  if (cm.length !== 1 || !deferredMail(cm[0])) throw new Error(`mail zákazníkovi ${cm.map((m) => m.html.slice(0, 500))}`)
  // další volání ze serveru / obsluhy (mail, retry) nic nevrací podruhé a stav nechá obsluze
  await pr(3500, 'service'); await pr(3500, 'admin'); await deliver()
  money('B2 opakování', 3000, 3500)
  if (bk().payment_status !== 'refund_pending') throw new Error(`stav po opakování ${bk().payment_status}`)
} })

Deno.test({ name: 'i2 B3: QR rezervace, ruční vratka 500 a pak „Potvrdit vrácení“ 100 % → druhý dobropis i částka pro Fio / odpověď jen 2 500', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { payment_method: 'qr', pay_channel: 'qr', stripe_payment_intent_id: null } })
  rows('fio_transactions').push({ fio_id: 1, booking_id: BID, amount: 3000, vs: '123', counter_account: '111', counter_bank: '0100' })
  const first = await pr(500, 'admin', 'booking_modified')
  if (!first?.manual || Number(first.amount) !== 500) throw new Error(`první ruční vratka ${JSON.stringify(first)}`)
  Object.assign(bk(), { status: 'cancelled', cancelled_at: new Date().toISOString(), cancelled_by_source: 'velin', cancellation_reason: 'Storno (Velín)', payment_status: 'refund_pending' })
  advance(20)
  // BookingDetail „Potvrdit vrácení“ 100 % = process-refund bez částky (částka pro Fio příkaz, odpověď i mail = manAmount)
  const second = await pr(undefined, 'admin')
  if (!second?.manual || Number(second.amount) !== 2500 || !second.credit_note_id) throw new Error(`druhá ruční vratka ${JSON.stringify(second)} (čekáno amount 2500)`)
  if (cnKc() !== 3000 || creditNotes().length !== 2) throw new Error(`dobropisy ${cnKc()} / ${creditNotes().length}`)
  const last = dl('manual_refund_pending').at(-1)
  if (!last || Number(last.request_data?.amount) !== 2500) throw new Error(`částka druhé vratky ${JSON.stringify(last?.request_data)}`)
  // ještě jednou 100 % → nic (zbytek dle dokladů 0)
  const again = await pr(undefined, 'admin')
  if (!again?.success || again.code !== 'manual_refund_noop_zero' || cnKc() !== 3000) throw new Error(`třetí volání ${JSON.stringify(again)}, dobropisy ${cnKc()}`)
  const r = await velinConfirm(3000)
  if (r.failed || cnKc() !== 3000) throw new Error(`Velín ${JSON.stringify(r)}, dobropisy ${cnKc()}`)
} })

Deno.test({ name: 'i2 B4: souběžný dispatch téže vratky BEZ unikátního indexu → jedna vratka, jeden živý dobropis, jeden účetní záznam', ignore: !MAPPED, fn: async () => {
  fresh(10); bk().total_price = 2500
  const [a, b] = await Promise.all([pr(500, 'service', 'edit_shortening'), pr(500, 'service', 'edit_shortening')])
  money('B4', 500)
  if (creditNotes().length !== 1) throw new Error(`živých dobropisů ${creditNotes().length}`)
  if (!a?.success || !b?.success || !a.credit_note_id || a.credit_note_id !== b.credit_note_id) throw new Error(`odpovědi ${JSON.stringify([a, b])}`)
  const acc = rows('accounting_entries')
  if (acc.length !== 1) throw new Error(`účetních záznamů ${acc.length}`)
  const cancelled = rows('invoices').filter((x) => x.type === 'credit_note' && x.status === 'cancelled')
  if (cancelled.length && !dl('credit_note_duplicate_cancelled').length) throw new Error('zrušený duplicitní dobropis bez záznamu')
} })

Deno.test({ name: 'i2 B5: pád po refunds.create u DRUHÉ vratky → recovery z webhooku vystaví dobropis k druhé vratce (ne jen k první)', ignore: !MAPPED, fn: async () => {
  fresh(10); bk().total_price = 2500
  await pr(500, 'service', 'edit_shortening'); await deliver()
  if (creditNotes().length !== 1 || bk().stripe_refund_id !== 're_1') throw new Error(`po první vratce ${creditNotes().length} / ${bk().stripe_refund_id}`)
  bk().total_price = 2200; killAfterRefund(1)
  const crashed = await pr(300, 'service', 'edit_shortening')
  if (crashed?.success) throw new Error('pád se nenasimuloval')
  await deliver() // charge.refunded druhé vratky → recovery s refund_id re_2
  money('B5', 800)
  if (creditNotes().length !== 2 || !creditNotes().some((c) => c.stripe_refund_id === 're_2' && Math.abs(Number(c.total)) === 300)) {
    throw new Error(`dobropisy ${JSON.stringify(creditNotes().map((c) => [c.total, c.stripe_refund_id]))}`)
  }
  if (bk().stripe_refund_id !== 're_2') throw new Error(`uložená vratka ${bk().stripe_refund_id} (čekáno re_2)`)
  if (bk().payment_status !== 'partial_refund') throw new Error(`stav ${bk().payment_status}`)
} })

Deno.test({ name: 'i2 B6: vratka „pending“ (nízký zůstatek) později dokončena → charge.refund.updated / další volání dorovná refund_pending → refunded; selhání → mail obsluze', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const via of ['event', 'call', 'failed'] as const) {
    fresh(10); world().refundStatus = () => 'pending'
    await velinCancel('full'); await deliver()
    if (bk().payment_status !== 'refund_pending' || refundedKc() !== 3000) { bad.push(`${via}: po stornu ${bk().payment_status} / ${refundedKc()}`); continue }
    const r = world().refunds[0]
    if (via === 'failed') {
      r.status = 'failed'
      await deliver([{ id: 'evt_ru_f', type: 'charge.refund.updated', created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(r)) } }])
      if (bk().payment_status !== 'refund_pending') bad.push(`failed: stav ${bk().payment_status}`)
      if (!opsMails.some((m) => /SELHALA/.test(m.subject)) || !dl('refund_updated_failed').length) bad.push(`failed: mail ${JSON.stringify(opsMails.map((m) => m.subject))}`)
      continue
    }
    r.status = 'succeeded'; advance(5)
    if (via === 'event') await deliver([{ id: 'evt_ru_1', type: 'charge.refund.updated', created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(r)) } }])
    else await pr(3000, 'service')
    if (bk().payment_status !== 'refunded') bad.push(`${via}: stav ${bk().payment_status} (čekáno refunded)`)
    try { money(`B6 ${via}`, 3000) } catch (e) { bad.push((e as Error).message) }
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i2 B7: zbytek z ostatních plateb selhal a webhook předběhne mail z Velínu → pojistný mail neslibuje 1 558 (dokončuje obsluha); retry dovrátí', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: TWO }); velinUpd(); failOrig(true)
  const a = await pr(1558) // hlavní 115 z pi_ext1, zbytek 1443 selhává → partial_refund
  if (!a?.success || refundedKc() !== 115) throw new Error(`storno ${JSON.stringify(a)}, vráceno ${refundedKc()}`)
  await deliver() // charge.refunded uložené platby DŘÍV než mail z Velínu: recovery zbytek znovu selže → pojistný mail
  const after = await sce(1558) // mail z Velínu: claim drží webhook
  const cm = custMails()
  if (cm.length !== 1) throw new Error(`mailů zákazníkovi ${cm.length}: ${cm.map((m) => m.html.slice(0, 300))}`)
  if (!deferredMail(cm[0])) throw new Error(`pojistný mail slibuje vrácení: ${cm[0].html.slice(0, 600)}`)
  if (!/1[\s ]558/.test(cm[0].html)) throw new Error(`mail neuvádí požadovanou částku storna: ${cm[0].html.slice(0, 600)}`)
  if (after?.skipped !== 'claim_held' && after?.skipped !== 'already_sent') throw new Error(`mail Velínu ${JSON.stringify(after)}`)
  failOrig(false); advance(5)
  await pr(1558, 'service'); await deliver()
  money('B7 dovrácení', 1558)
  if (bk().payment_status !== 'partial_refund') throw new Error(`stav ${bk().payment_status}`)
} })

Deno.test({ name: 'i2 B8: selhaná zákaznická vratka z appky (výjimka) → mail obsluze s rezervací', ignore: !MAPPED, fn: async () => {
  fresh(10); priceList(); bk().total_price = 2500
  world().onBeforeCreate = () => { throw new Error('Stripe: boom') }
  const r = await pr(500, 'customer', 'edit_shortening')
  world().onBeforeCreate = null
  if (r?.success) throw new Error('měla selhat')
  if (!opsMails.some((m) => /selhala/.test(m.subject) && /vratka/i.test(m.subject))) throw new Error(`mail obsluze ${JSON.stringify(opsMails.map((m) => m.subject))}`)
  const err = rows('debug_log').find((d) => d.action === 'stripe_refund_error')
  if (!err || err.request_data?.booking_id !== BID) throw new Error(`debug_log bez rezervace: ${JSON.stringify(err)}`)
  void insert
} })
