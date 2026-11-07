// ===== _tests/storno_i5v_flow_test.ts =====
// verify:refunds:i5 (2026-11-07, po opravě fix:i5r1) — adversariální REPRO testy regresí oprav i3 / i4 / i5 (celé handlery
// nad falešným Stripe + DB, storno-harness.ts). Každý test tvrdí SPRÁVNÉ chování a na stromu 03a2d1dc PADÁ (repro).
// Spouštěč (storno_hotfix_test.ts FLOW_FILES) je zatím NEobsahuje — zaregistrovat až po opravě (FLOW_MIN += 8). Ručně:
//   cd supabase/functions/_tests && deno test --allow-all --no-check --import-map=storno-flow-map.json storno_i5v_flow_test.ts
//  R1  selhaná vratka zkrácení „nahrazená“ NESOUVISEJÍCÍ novější vratkou (druhá úprava o jinou částku) → rezervace se
//      neotevře a mail obsluze místo „Chybí vrátit 500 Kč“ tvrdí „nahradila novější vratka“ (failed-refund.ts superseded),
//  R2  QR rezervace, dvě zkrácení s ruční vratkou + Velín „Vratka odeslána“ → ŽIVÁ rezervace 'refunded' (součet dobropisů
//      ≥ snížená cena, manualRefundState.js); následné storno 100 % nevrátí nic a mail zákazníkovi tvrdí vrácení,
//  R3  selhaná vratka zkrácení → obsluha podle mailu vrátí v Stripe dashboardu → webhook dobropis vystaví SÁM (text „Storno“)
//      a mail obsluze zároveň velí „vystavte dobropis ručně“ (dva dobropisy k jedné vratce),
//  R4  process-refund nevystavil dobropis (pád zápisu), vratka pak selhala a charge.refunded dorazil až potom → recovery
//      vystaví dobropis k SELHANÉ vratce (dobropis 3000, vráceno 0; „Potvrdit vrácení“ ve Velíně pak vratku přeskočí),
//  R5  refund.updated „succeeded“ jedné vratky, zatímco jiná naše vratka rezervace ještě čeká → stav předčasně
//      'partial_refund' / 'refunded' (i4 sémantika: 'refund_pending' do dokončení všech) — dvě zkrácení i storno se zbytkem,
//  R6  plná vratka ze Stripe dashboardu (storno portálem) později SELŽE → rezervace zůstane 'refunded' a dobropis 3000 živý,
//  R7  modifiedRefundCovered: web úprava (at se zónou) a pak appka 4.1.3 (at bez zóny) → dobropis DŘÍVĚJŠÍ úpravy na
//      STEJNOU částku kryje novou úpravu se spadlou vratkou (mail tvrdí dobropis v příloze i vratku na kartu),
//  R8  opakování selhané vratky, výpis vratek uložené platby přechodně selže („non-fatal“) → bez přípony :f1 tentýž klíč →
//      Stripe přehraje SELHANOU vratku a process-refund hlásí úspěch (0 Kč vráceno, rezervace 'refund_pending', bez mailu).
// deno-lint-ignore-file no-explicit-any
import { BID, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, mails, opsMails, rows, world } from './storno-harness.ts'
import { customerCancel, portalFullRefund, velinCancel } from './storno-dispatch.ts'
import { coversModification, newestModificationMs } from '../send-booking-email/modified-refund.ts'
import { manualRefundSentStatus } from '../../../velin/src/pages/booking/manualRefundState.js'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()

const pr = (amount?: number, as: 'service' | 'admin' | 'customer' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)
const ev = (type: string, r: any, id: string) => deliver([{ id, type, created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(r)) } }])
const fail = (r: any, id = 'evt_cru_' + r.id) => { r.status = 'failed'; return ev('charge.refund.updated', r, id) }
const succeed = (r: any) => { r.status = 'succeeded'; return ev('charge.refund.updated', r, 'evt_ok_' + r.id) }
const liveKc = () => world().refunds.filter((r: any) => r.status === 'succeeded' || r.status === 'pending').reduce((s: number, r: any) => s + r.amount, 0) / 100
const text = (h: string) => h.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ')
const db = () => (globalThis as any).__STORNO_DB

Deno.test({ name: 'i5v R1: selhaná vratka zkrácení + nesouvisející novější vratka → rezervace znovu otevřena, mail „Chybí vrátit 500 Kč“', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const second of ['shortening', 'moto_swap'] as const) {
    fresh(10); world().refundStatus = () => 'pending'
    bk().total_price = 2500
    await pr(500, 'service', 'shortening'); await deliver() // 1. zkrácení: 500 Kč „pending“
    world().refundStatus = () => 'succeeded'
    advance(2)
    bk().total_price = 2200
    await pr(300, 'service', second); await deliver() // 2. úprava o JINOU částku (300 Kč) — vratku 1. úpravy nenahrazuje
    opsMails.length = 0
    await fail(world().refunds[0]) // 1. vratka selže
    const m = opsMails.find((x) => /SELHALA/.test(x.subject))
    if (bk().payment_status !== 'refund_pending') bad.push(`${second}: stav ${bk().payment_status} (čekáno refund_pending — 500 Kč nevráceno)`)
    if (!m || !/Chybí vrátit <strong>500 Kč/.test(m.html) || /nahradila novější vratka/.test(m.html)) bad.push(`${second}: mail ${m ? text(m.html).slice(-260) : '—'}`)
    if (liveKc() !== 300 || cnKc() !== 300) bad.push(`${second}: vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5v R2: QR rezervace — „Vratka odeslána“ po dvou zkráceních nechá živou rezervaci zaplacenou; storno pak vrátí zbytek', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { payment_method: 'bank_transfer', pay_channel: 'qr', stripe_payment_intent_id: null, payment_vs: '5550001' } })
  world().intents.delete('pi_orig')
  rows('fio_transactions').push({ fio_id: 1, amount: 3000, vs: '5550001', booking_id: BID, counter_account: '1', counter_bank: '0100', status: 'confirmed' })
  const sent = () => { bk().payment_status = manualRefundSentStatus(bk(), creditNotes()) } // BookingDetail confirmManualRefundSent
  bk().total_price = 2000
  await pr(1000, 'service', 'shortening'); sent()
  advance(20)
  bk().total_price = 1400
  await pr(600, 'service', 'shortening'); sent() // Σ dobropisů 1600 ≥ cena 1400 → dnes 'refunded' u ŽIVÉ rezervace
  const afterSent = bk().payment_status
  mails.length = 0
  const c = await customerCancel('none'); await deliver() // storno 100 % = 1400 Kč
  const m = customerMails().at(-1)
  if (afterSent !== 'partial_refund' || cnKc() !== 3000) {
    throw new Error(`po „Vratka odeslána“ ${afterSent} (čekáno partial_refund), storno ${c.amt} Kč → dobropisy ${cnKc()} Kč (čekáno 3000), stav ${bk().payment_status}, mail zákazníkovi ${JSON.stringify(m)}`)
  }
} })

Deno.test({ name: 'i5v R3: selhaná vratka zkrácení → vratka v Stripe dashboardu dle mailu → jeden dobropis = vráceno, mail neříká „vystavte ručně“, když už je', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  bk().total_price = 2500
  await pr(500, 'service', 'shortening'); await deliver()
  world().refundStatus = () => 'succeeded'
  await fail(world().refunds[0]) // mail: „… nebo ji vraťte ve Stripe dashboardu“
  opsMails.length = 0
  await world().dashboardRefund('pi_orig', 50000); await deliver() // obsluha podle mailu
  const auto = creditNotes().filter((x: any) => x.stripe_refund_id === world().refunds[1].id)
  const asks = opsMails.filter((x) => /vystavte dobropis ručně/.test(text(x.html)))
  // buď dobropis vystaví webhook (pak mail nesmí velet vystavit další a text nesmí tvrdit „Storno“ u živé rezervace),
  // nebo ho nevystaví a mail ho žádá — nikdy obojí
  if (liveKc() !== 500 || cnKc() > 500 || (auto.length && asks.length) || auto.some((x: any) => /Storno/.test(String(x.notes)))) {
    throw new Error(`vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč (${JSON.stringify(creditNotes().map((x: any) => [x.total, x.notes]))}), mail obsluze: ${asks.map((x) => x.subject).join(' | ')}`)
  }
} })

Deno.test({ name: 'i5v R4: dobropis nevznikl, vratka selhala, charge.refunded dorazí pozdě → recovery nevystaví dobropis k selhané vratce', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  Object.assign(bk(), { status: 'cancelled', cancelled_at: new Date().toISOString(), payment_status: 'refund_pending' })
  const orig = db().beforeInsert; let once = true // zápis dobropisu v process-refund spadne (isolate / DB)
  db().beforeInsert = (t: string, r: any) => { if (t === 'invoices' && r.type === 'credit_note' && once) { once = false; return { code: 'XX000', message: 'boom' } } return orig(t, r) }
  await pr(3000, 'service')
  const held = world().takeEvents() // charge.refunded zdržen (Stripe doručuje znovu po 500 / bez pořadí)
  world().refundStatus = () => 'succeeded'
  await fail(world().refunds[0])
  await deliver(held)
  if (cnKc() !== liveKc()) throw new Error(`vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč (${JSON.stringify(creditNotes().map((x: any) => [x.total, x.stripe_refund_id]))})`)
} })

Deno.test({ name: 'i5v R5: refund.updated „succeeded“, zatímco jiná naše vratka rezervace čeká → zůstává refund_pending', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  // a) dvě zkrácení „pending“, první se dokončí
  fresh(10); world().refundStatus = () => 'pending'
  bk().total_price = 2500
  await pr(500, 'service', 'shortening'); await deliver()
  advance(2)
  bk().total_price = 2200
  await pr(300, 'service', 'shortening'); await deliver()
  await succeed(world().refunds[0])
  if (bk().payment_status !== 'refund_pending') bad.push(`a) po dokončení 1. vratky ${bk().payment_status} (2. vratka 300 Kč čeká)`)
  await succeed(world().refunds[1])
  if (bk().payment_status !== 'partial_refund') bad.push(`a) po dokončení obou ${bk().payment_status}`)
  // b) storno z více plateb: hlavní i zbytek „pending“, hlavní se dokončí dřív
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] }); world().refundStatus = () => 'pending'
  await velinCancel('full'); await deliver()
  const main = world().refunds.find((r: any) => r.metadata.mg_part !== 'remainder')
  const rem = world().refunds.find((r: any) => r.metadata.mg_part === 'remainder')
  await succeed(main)
  if (bk().payment_status !== 'refund_pending') bad.push(`b) hlavní hotová, zbytek ${rem?.amount / 100} Kč čeká → ${bk().payment_status}`)
  await succeed(rem)
  if (bk().payment_status !== 'refunded') bad.push(`b) obě hotové → ${bk().payment_status}`)
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5v R6: plná vratka ze Stripe dashboardu (storno portálem) selže → dobropis zrušen / rezervace k vrácení', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  await portalFullRefund(false)
  world().refundStatus = () => 'succeeded'
  const before = [bk().status, bk().payment_status, cnKc()]
  await fail(world().refunds[0])
  if (cnKc() !== liveKc() || bk().payment_status === 'refunded') {
    throw new Error(`po stornu portálem ${JSON.stringify(before)}; po selhání vratky: vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč, stav ${bk().payment_status}`)
  }
} })

Deno.test({ name: 'i5v R7: modifiedRefundCovered — web (at se zónou) + appka 4.1.3 (at bez zóny), stejná částka: dobropis 1. úpravy nekryje 2.', ignore: !MAPPED, fn: () => {
  const t0 = Date.parse('2026-11-07T08:00:00Z')
  // 1. úprava z webu (RPC, timestamptz), 2. úprava z appky 4.1.3 (místní čas Prahy bez zóny = 09:30Z), obě s vratkou 500 Kč
  const history = [{ type: 'edit', at: '2026-11-07T08:00:00.123456+00:00', price_diff: -500 }, { type: 'edit', at: '2026-11-07T10:30:00.000', price_diff: -500 }]
  const since = newestModificationMs(history)
  const cnOfFirst = { total: -500, created_at: new Date(t0 + 60_000).toISOString() } // dobropis 1. úpravy (08:01Z)
  const now = Date.parse('2026-11-07T09:31:00Z') // mail 2. úpravy (vratka appky se neprovedla)
  if (coversModification(cnOfFirst, 500, since, now)) throw new Error(`dobropis 1. úpravy kryje 2. (sinceMs ${since && new Date(since).toISOString()})`)
} })

Deno.test({ name: 'i5v R8: opakování selhané vratky, výpis vratek platby přechodně selže → Stripe přehraje SELHANOU vratku jako úspěch', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  bk().total_price = 2500
  await pr(500, 'service', 'shortening'); await deliver()
  world().refundStatus = () => 'succeeded'
  await fail(world().refunds[0])
  advance(10)
  const w = world(), api = w.api.bind(w)
  let failNext = true // refunds.list uložené platby jednou spadne (limit / výpadek Stripe) — process-refund to bere jako „non-fatal“
  w.api = () => { const a = api(); const l = a.refunds.list; a.refunds.list = (p: any) => (failNext && p.payment_intent === 'pi_orig' ? (failNext = false, Promise.reject(new Error('rate_limit'))) : l(p)); return a }
  const r = await pr(500, 'service', 'shortening'); await deliver()
  w.api = api
  const replayed = world().creates.filter((c: any) => String(c.result).startsWith('replayed:'))
  // správně: nová vratka 500 Kč, nebo chyba (zkusit znovu) — nikdy „success“ s přehranou SELHANOU vratkou a bez peněz
  if (r?.success === true && liveKc() !== 500) {
    throw new Error(`vráceno ${liveKc()} Kč, odpověď ${JSON.stringify({ success: r?.success, refund_id: r?.refund_id, status: r?.status })}, přehráno ${JSON.stringify(replayed.map((c: any) => c.result))}, stav ${bk().payment_status}`)
  }
} })
