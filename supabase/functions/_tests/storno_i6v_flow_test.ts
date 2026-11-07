// ===== _tests/storno_i6v_flow_test.ts =====
// verify:refunds:i6 (2026-11-07) — adversariální REPRO testy regresí po opravách i5 (failed-refund.ts zmenšení dobropisu /
// „nahrazená“ vratka, znovuotevření, Velín součty) a jejich souhry se starší logikou. Celé handlery nad falešným Stripe + DB
// (storno-harness.ts). Každý test tvrdí SPRÁVNÉ chování; na stromu ea441c6b PADAJÍ (repro), kromě kontrol označených
// „(kontrola)“. Spouštěč (storno_hotfix_test.ts FLOW_FILES) je zatím NEobsahuje — zaregistrovat po opravě. Ručně:
//   cd supabase/functions/_tests && deno test --allow-all --no-check --import-map=storno-flow-map.json storno_i6v_flow_test.ts
//  W1  selhaná vratka 1. zkrácení „nahrazená“ POZDĚJŠÍM LEGITIMNÍM zkrácením o STEJNOU částku (appka 4.1.3, další den) →
//      rezervace se neotevře, mail tvrdí „nahradila novější vratka“ (newer v failed-refund.ts nemá časovou kotvu selhání),
//  W2  (kontrola) storno ze dvou STEJNÝCH plateb, selže zbytek → dobropis zmenšen na 3000 = chybějící částka → Velín
//      „Potvrdit vrácení na 3000 Kč“ vratku přeskočí (dobropis na tutéž částku), zbytek ale dovrátí attach recovery mailu,
//  W2b dřívější zkrácení 500 (dobropis 500) + storno vratka 500 selže → Velín „Potvrdit vrácení na 500 Kč“ (přesně dle mailu
//      obsluze) vratku PŘESKOČÍ kvůli dobropisu ZKRÁCENÍ, storno mail zákazníkovi tvrdí „500 Kč vráceno“ s dobropisem zkrácení,
//  W3  karta + převod, plné storno; kartová vratka selže (dobropis zrušen, rezervace k vrácení) → „Vratka odeslána“ z
//      otevřeného detailu (seznam dobropisů z doby před selháním) zapíše 'refunded' bez kontroly → „Potvrdit vrácení“ pak
//      nevrátí nic (process-refund „už vráceno“),
//  W4  události mimo pořadí: „failed“ zpracována dřív než starší „succeeded“ téže vratky → onRefundUpdated věří snímku
//      události, znovuotevřenou rezervaci přepíše na 'partial_refund' (nic se nevrátilo),
//  W5  selhání doručené souběžně jako charge.refund.updated + refund.updated → obsluha dostane mail o selhání 2×,
//  W6  zkrácení z více plateb, selže HLAVNÍ vratka (zbytek odešel) → mail velí „vratku zopakujte (… stejná úprava)“ → totéž
//      volání vrátí celou úpravu znovu (přeplatek 1000 Kč) — osiřelý zbytek se mimo storno nepočítá.
// deno-lint-ignore-file no-explicit-any
import { BID, FN, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, opsMails, rows, world } from './storno-harness.ts'
import { velinCancel, velinConfirm } from './storno-dispatch.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()
const velin: any = MAPPED ? await import(new URL('../../velin/src/pages/booking/manualRefundState.js', FN).href) : {}

const pr = (amount?: number, as: 'service' | 'admin' | 'customer' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)
const ev = (type: string, r: any, id: string) => deliver([{ id, type, created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(r)) } }])
const fail = (r: any, id = 'evt_cru_' + r.id) => { r.status = 'failed'; return ev('charge.refund.updated', r, id) }
const liveKc = () => world().refunds.filter((r: any) => r.status === 'succeeded' || r.status === 'pending').reduce((s: number, r: any) => s + r.amount, 0) / 100
const text = (h: string) => h.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ')
const failMails = () => opsMails.filter((m) => /SELHALA/.test(m.subject))
const db = () => (globalThis as any).__STORNO_DB
const priceList = () => { db().rpcs._moto_dayprice_sum = () => ({ data: 2000, error: null }) }

Deno.test({ name: 'i6v W1: selhaná vratka 1. zkrácení + pozdější legitimní zkrácení o stejnou částku → znovu otevřena, „Chybí vrátit 500 Kč“', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const [lab, as, reason] of [['appka 4.1.3', 'customer', 'edit_shortening'], ['web / RPC', 'service', 'shortening']] as Array<[string, 'customer' | 'service', string]>) {
    fresh(10); priceList(); world().refundStatus = () => 'pending' // nízký zůstatek účtu → vratka „pending“
    bk().total_price = 2500
    await pr(500, as, reason); await deliver() // 1. zkrácení o den: 500 Kč (pending)
    world().refundStatus = () => 'succeeded'
    advance(24 * 60) // další den
    bk().total_price = 2000
    await pr(500, as, reason); await deliver() // 2. zkrácení o DALŠÍ den: legitimní nová vratka 500 Kč (není to opakování 1.)
    opsMails.length = 0
    await fail(world().refunds[0]) // banka vrátí 1. vratku (o den později)
    const m = failMails()[0]
    if (bk().payment_status !== 'refund_pending') bad.push(`${lab}: stav ${bk().payment_status} (čekáno refund_pending — chybí vrátit 500 Kč)`)
    if (!m || !/Chybí vrátit <strong>500 Kč/.test(m.html) || /nahradila novější vratka/.test(m.html)) bad.push(`${lab}: mail ${m ? text(m.html).slice(-240) : '—'}`)
    if (liveKc() !== 500 || cnKc() !== 500) bad.push(`${lab}: vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč (dluh 1000 Kč)`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i6v W2 (kontrola): storno ze dvou stejných plateb, selže zbytek → „Potvrdit vrácení na 3000 Kč“ — dovrátí attach recovery storno mailu', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 3000 }] }) // původní 3000 + zapsaná změna 3000 (uložená) = 6000
  await velinCancel('full'); await deliver() // hlavní 3000 z pi_ext1 + zbytek 3000 z pi_orig
  opsMails.length = 0
  const rem = world().refunds.find((r: any) => r.metadata.mg_part === 'remainder')
  if (!rem) throw new Error(`zbytek nevznikl: ${JSON.stringify(world().refunds.map((r: any) => [r.payment_intent, r.amount]))}`)
  await fail(rem)
  const m = failMails()[0]
  const pre = { cn: cnKc(), st: bk().payment_status, mail: m ? text(m.html) : '—' }
  advance(10)
  const before = customerMails().length
  await velinConfirm(3000); await deliver() // obsluha přesně dle mailu: „Potvrdit vrácení“ na chybějících 3000 Kč
  const cm = customerMails().slice(before).at(-1)
  const bad: string[] = []
  if (!/Potvrdit vrácení[^.]*na 3000 Kč/.test(pre.mail)) bad.push(`mail obsluze (předpoklad testu): ${pre.mail.slice(-300)}`)
  if (pre.cn !== 3000 || pre.st !== 'refund_pending') bad.push(`po selhání dobropisy ${pre.cn} Kč, stav ${pre.st}`)
  if (liveKc() !== 6000) bad.push(`vráceno ${liveKc()} Kč (čekáno 6000) — Velín vratku přeskočil (dobropis ${pre.cn} Kč = zvolená částka)`)
  if (cnKc() !== liveKc()) bad.push(`dobropisy ${cnKc()} Kč ≠ vráceno ${liveKc()} Kč`)
  if (cm && cm.amount != null && cm.amount > liveKc()) bad.push(`mail zákazníkovi tvrdí ${cm.amount} Kč, vráceno ${liveKc()} Kč`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i6v W2b: dřívější zkrácení 500 (dobropis 500) + storno 500 selže → „Potvrdit vrácení na 500 Kč“ dle mailu opravdu vrátí', ignore: !MAPPED, fn: async () => {
  fresh(10); priceList()
  bk().total_price = 2500
  await pr(500, 'service', 'shortening'); await deliver() // zkrácení: vratka 500 + dobropis 500 (s PDF)
  advance(24 * 60)
  world().refundStatus = () => 'pending'
  await velinCancel(500); await deliver() // storno z Velínu s vratkou 500 Kč (pending)
  world().refundStatus = () => 'succeeded'
  opsMails.length = 0
  await fail(world().refunds[1])
  const m = failMails()[0]
  const pre = { cn: cnKc(), st: bk().payment_status, mail: m ? text(m.html) : '—' }
  advance(10)
  const before = customerMails().length
  await velinConfirm(500); await deliver() // obsluha přesně dle mailu
  const cm = customerMails().slice(before).at(-1)
  const bad: string[] = []
  if (!/Potvrdit vrácení[^.]*na 500 Kč/.test(pre.mail) || pre.cn !== 500 || pre.st !== 'refund_pending') bad.push(`předpoklad: dobropisy ${pre.cn}, stav ${pre.st}, mail ${pre.mail.slice(-260)}`)
  if (liveKc() !== 1000) bad.push(`vráceno ${liveKc()} Kč (čekáno 1000: zkrácení 500 + storno 500) — Velín vratku přeskočil kvůli dobropisu zkrácení na 500 Kč`)
  if (cnKc() !== liveKc()) bad.push(`dobropisy ${cnKc()} Kč ≠ vráceno ${liveKc()} Kč`)
  if (bk().payment_status !== 'partial_refund') bad.push(`stav ${bk().payment_status}`)
  if (cm?.amount === 500 && liveKc() < 1000) bad.push('mail zákazníkovi tvrdí vrácení 500 Kč')
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i6v W3: karta + převod, kartová vratka selže → „Vratka odeslána“ z otevřeného detailu neuzavře rezervaci jako vrácenou', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { total_price: 3500, mod_surcharge_vs: '2026002', mod_surcharge_paid_at: new Date().toISOString() } })
  rows('invoices').push({ id: crypto.randomUUID(), booking_id: BID, type: 'payment_receipt', status: 'issued', total: 500, number: 'DP-2026-1501', issue_date: '2026-10-02', created_at: new Date().toISOString() })
  rows('fio_transactions').push({ fio_id: 8, booking_id: BID, amount: 500, vs: '2026002', counter_account: '111', counter_bank: '0100' })
  world().refundStatus = () => 'pending'
  await velinCancel('full'); await deliver() // karta 3000 (pending) + ruční dobropis 500 (převod posílá obsluha)
  world().refundStatus = () => 'succeeded'
  const pageCns = creditNotes().map((c: any) => ({ ...c })) // obsluha má detail rezervace otevřený
  const pageBk = { ...bk() }
  await fail(world().refunds[0]) // kartová vratka selže → dobropis 3000 zrušen, „Čeká na vrácení“, mail obsluze
  const afterFail = { cn: cnKc(), st: bk().payment_status }
  // obsluha odešle převod 500 Kč a klikne „Vratka odeslána“ (BookingDetail.confirmManualRefundSent)
  let st: string
  if (typeof velin.manualRefundSentLive === 'function') st = await velin.manualRefundSentLive(db(), pageBk) // po opravě: dobropisy + CAS z DB
  else {
    const paidDocs = pageBk.status === 'cancelled' ? await velin.livePaidDocsCzk(db(), BID) : null
    st = velin.manualRefundSentStatus(pageBk, pageCns, paidDocs)
    bk().payment_status = st // dnešní BookingDetail: update({ payment_status }).eq('id') bez kontroly stavu
  }
  advance(10)
  const nMail = customerMails().length
  await velinConfirm(3000); await deliver() // pak dle mailu o selhání: „Potvrdit vrácení“ na 3000 Kč
  const cm = customerMails().slice(nMail).at(-1)
  const bad: string[] = []
  if (liveKc() < 3000 && (cm?.amount ?? 0) >= 3000) bad.push(`mail zákazníkovi tvrdí vrácení ${cm?.amount} Kč, kartou vráceno ${liveKc()} Kč`)
  if (afterFail.cn !== 500 || afterFail.st !== 'refund_pending') bad.push(`po selhání karty dobropisy ${afterFail.cn} Kč, stav ${afterFail.st} (předpoklad)`)
  if (st === 'refunded') bad.push(`„Vratka odeslána“ zapsala 'refunded', ačkoli kartových 3000 Kč neodešlo (seznam dobropisů z otevřené stránky)`)
  if (liveKc() !== 3000) bad.push(`„Potvrdit vrácení“ po té nevrátilo kartou nic: vráceno kartou ${liveKc()} Kč`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i6v W4: „failed“ zpracovaná dřív než starší „succeeded“ téže vratky → rezervace zůstává k vrácení (stav ze Stripe, ne ze snímku)', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  await velinCancel('full'); await deliver() // storno 3000 „pending“
  const r = world().refunds[0]
  const okSnap = JSON.parse(JSON.stringify({ ...r, status: 'succeeded' })) // pending → succeeded (událost zdržená)
  await fail(r) // … pak succeeded → failed; „failed“ dorazí první
  const mid = bk().payment_status
  await deliver([{ id: 'evt_ru_ok_' + r.id, type: 'refund.updated', created: okSnap.created, data: { object: okSnap } }])
  if (mid !== 'refund_pending' || bk().payment_status !== 'refund_pending' || liveKc() !== 0) {
    throw new Error(`po „failed“ ${mid}, po zdržené „succeeded“ ${bk().payment_status}, vráceno ${liveKc()} Kč (nic neodešlo)`)
  }
} })

Deno.test({ name: 'i6v W5: selhání doručené souběžně dvěma typy události → jeden mail obsluze, dobropis zmenšen jednou', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] })
  await velinCancel('full'); await deliver()
  opsMails.length = 0
  const rem = world().refunds.find((r: any) => r.metadata.mg_part === 'remainder')
  rem.status = 'failed'
  const obj = () => JSON.parse(JSON.stringify(rem))
  await Promise.all([
    deliver([{ id: 'evt_cru_' + rem.id, type: 'charge.refund.updated', created: Math.floor(Date.now() / 1000), data: { object: obj() } }]),
    deliver([{ id: 'evt_ru_' + rem.id, type: 'refund.updated', created: Math.floor(Date.now() / 1000), data: { object: obj() } }]),
  ])
  const n = failMails().length
  const acc = rows('accounting_entries').filter((a: any) => a.category === 'refund').map((a: any) => a.amount)
  if (n !== 1 || cnKc() !== 500) throw new Error(`mailů o selhání ${n}, dobropisy ${cnKc()} Kč, účetní záznamy ${JSON.stringify(acc)}`)
} })

Deno.test({ name: 'i6v W6: zkrácení z více plateb, selže HLAVNÍ vratka (zbytek odešel) → „vratku zopakujte (stejná úprava)“ nevrátí víc, než chybí', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] }) // 3000 + uložený doplatek 500 = 3500
  let n = 0
  world().refundStatus = () => (++n === 1 ? 'pending' : 'succeeded') // hlavní z pi_ext1 „pending“, zbytek z pi_orig odešel
  bk().total_price = 2000
  await pr(1500, 'service', 'shortening'); await deliver() // zkrácení o 1500: hlavní 500 (pi_ext1) + zbytek 1000 (pi_orig)
  world().refundStatus = () => 'succeeded'
  opsMails.length = 0
  await fail(world().refunds.find((r: any) => r.metadata.mg_part !== 'remainder'))
  const m = failMails()[0]
  const pre = { cn: cnKc(), mail: m ? text(m.html) : '—' }
  advance(30)
  await pr(1500, 'service', 'shortening'); await deliver() // obsluha / dispatch zopakuje TOTÉŽ zkrácení (dle mailu „stejná úprava“)
  const bad: string[] = []
  if (pre.cn !== 1000 || !/Chybí vrátit 500 Kč[^.]*zopakujte/.test(pre.mail)) bad.push(`předpoklad: dobropisy ${pre.cn} Kč, mail ${pre.mail.slice(-260)}`)
  if (liveKc() > 1500) bad.push(`vráceno ${liveKc()} Kč, dlužno 1500 Kč (přeplatek ${liveKc() - 1500} Kč)`)
  if (cnKc() !== liveKc()) bad.push(`dobropisy ${cnKc()} Kč ≠ vráceno ${liveKc()} Kč`)
  if (bad.length) throw new Error(bad.join('\n'))
} })
