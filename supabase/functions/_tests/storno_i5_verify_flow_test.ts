// ===== _tests/storno_i5_verify_flow_test.ts =====
// verify:refunds:i5 (2026-11-07) — adversariální REPRO testy regresí po opravách i3 + i4 (celé handlery nad falešným
// Stripe + DB, storno-harness.ts). Každý test tvrdí SPRÁVNÉ chování; na stromu a03f92eb PADAJÍ (repro). Spouštěč
// (storno_hotfix_test.ts FLOW_FILES) je zatím NEobsahuje — zaregistrovat po opravě. Ručně:
//   cd supabase/functions/_tests && deno test --allow-all --no-check --import-map=storno-flow-map.json storno_i5_verify_flow_test.ts
//  V1  hlavní storno vratka SELŽE, její zbytek z jiné platby uspěl → mail obsluze jmenuje dobropis celé vratky k ZRUŠENÍ,
//      opakování (Velín / služba) zbytek nevidí: vrátí ho podruhé a cancel_refunded_total / mail tvrdí jen novou částku,
//  V2  selže jen ZBYTEK (hlavní uspěla) → mail „zrušte dobropis“ (dobropis kryje i hlavní vratku); po pokynu dobropisy ≠ vráceno,
//  V3  stará událost „failed“ (doručená znovu / druhý typ události) PO úspěšném opakování znovu otevře rezervaci,
//  V4  refund.updated(hlavní succeeded) zatímco zbytek čeká → 'refunded' předčasně (i4 sémantika: refund_pending),
//  V5  (kontrola) zbytek pending → později succeeded → 'refunded',
//  V6  druhá pozdní platba zrušené + už vrácené rezervace → i4 revive guard ji tiše ponechá (žádná vratka ani mail),
//  V7  selhaná vratka duplicitní platby → pokyn „vraťte ručně ve Stripe dashboardu“ → živá zaplacená rezervace 'partial_refund',
//  V8  modifiedRefundCovered: historie web (s zónou) + appka 4.1.3 (bez zóny) → dobropis DŘÍVĚJŠÍ úpravy kryje novou,
//  V9  selhaná storno vratka + „Potvrdit vrácení“ bez ručního zrušení dobropisu → Velín vratku přeskočí (dobropis na tutéž
//      částku), nic se nevrátí a mail zákazníkovi tvrdí vrácení,
//  V10 (kontrola, prochází) dvě souběžná opakování po selhání → jedna nová vratka; V5 a V7 jsou také kontroly (procházejí).
// Po opravě: přidat do FLOW_FILES v storno_hotfix_test.ts a FLOW_MIN += 9.
// deno-lint-ignore-file no-explicit-any
import { BID, advance, bk, boot, call, cnKc, creditNotes, customerMails, deliver, fresh, mails, opsMails, refundedKc, rows, world } from './storno-harness.ts'
import { customerCancel, velinConfirm } from './storno-dispatch.ts'
import { coversModification, newestModificationMs } from '../send-booking-email/modified-refund.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
if (MAPPED) await boot()

const pr = (amount?: number, as: 'service' | 'admin' | 'customer' = 'admin', reason = 'cancellation') =>
  call('process-refund', { booking_id: BID, reason, ...(amount ? { amount } : {}) }, as)
const ev = (type: string, r: any, id: string) => deliver([{ id, type, created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(r)) } }])
const fail = (r: any, id = 'evt_cru_' + r.id) => { r.status = 'failed'; return ev('charge.refund.updated', r, id) }
const succeed = (r: any) => { r.status = 'succeeded'; return ev('charge.refund.updated', r, 'evt_ok_' + r.id) }
const liveKc = () => world().refunds.filter((r: any) => r.status === 'succeeded' || r.status === 'pending').reduce((s: number, r: any) => s + r.amount, 0) / 100

Deno.test({ name: 'i5 V1: hlavní storno vratka selže, zbytek uspěl → opakování nevrátí zbytek podruhé, dobropis = vráceno', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const via of ['service', 'velin'] as const) {
    // uložená pi_ext1 (500) + původní 3000; storno zákazníkem 50 % = 1750: hlavní 500 z pi_ext1 (pending → selže), zbytek 1250 z pi_orig
    fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] })
    let n = 0
    world().refundStatus = () => (++n === 1 ? 'pending' : 'succeeded')
    const c = await customerCancel('none', 50); await deliver()
    world().refundStatus = () => 'succeeded'
    if (c.amt !== 1750 || liveKc() !== 1750) bad.push(`${via}: storno ${c.amt}, vráceno ${liveKc()} (čekáno 1750)`)
    opsMails.length = 0
    const main = world().refunds.find((r: any) => r.metadata.mg_part !== 'remainder')
    await fail(main)
    const failMail = opsMails.find((m) => /SELHALA/.test(m.subject))
    const cn = creditNotes()[0]
    // pokyn mailu: dobropis k vratce zrušit — ale dobropis kryje i 1250 Kč zbytku, které ODEŠLY
    if (failMail && cn && failMail.html.includes(String(cn.number)) && /Zrušte dobropis/.test(failMail.html) && Math.abs(Number(cn.total)) > main.amount / 100) {
      bad.push(`${via}: mail obsluze velí zrušit dobropis ${cn.number} na ${Math.abs(Number(cn.total))} Kč, selhalo jen ${main.amount / 100} Kč`)
    }
    advance(10)
    mails.length = 0
    let res: any
    if (via === 'service') res = await pr(1750, 'service')
    else { for (const x of creditNotes()) x.status = 'cancelled'; res = await velinConfirm(1750) }
    await deliver()
    if (liveKc() !== 1750) bad.push(`${via}: po opakování vráceno ${liveKc()} Kč (čekáno 1750) — ${JSON.stringify(world().creates.map((x: any) => x.result))}`)
    if (cnKc() !== liveKc()) bad.push(`${via}: dobropisy ${cnKc()} Kč ≠ vráceno ${liveKc()} Kč`)
    const m = customerMails().at(-1)
    if (via === 'velin' && m && m.amount !== liveKc()) bad.push(`${via}: mail zákazníkovi ${m.amount} Kč, vráceno ${liveKc()} Kč (${JSON.stringify(res)})`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5 V2: selže jen zbytek z jiné platby → mail nevelí zrušit dobropis celé vratky; po dovrácení dobropisy = vráceno', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const how of ['recovery', 'velin'] as const) {
    fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] })
    const { velinCancel } = await import('./storno-dispatch.ts')
    await velinCancel('full'); await deliver()
    opsMails.length = 0
    const rem = world().refunds.find((r: any) => r.metadata.mg_part === 'remainder')
    await fail(rem)
    const m = opsMails.find((x) => /SELHALA/.test(x.subject))
    // obsluha dělá, co mail říká: „Zrušte dobropis …“ a vratku zopakujte
    if (m && /Zrušte dobropis/.test(m.html)) for (const x of creditNotes()) if (m.html.includes(String(x.number))) x.status = 'cancelled'
    advance(10)
    if (how === 'recovery') {
      const ch = world().charges.get('ch_ext1')
      await deliver([{ id: 'evt_again', type: 'charge.refunded', created: Math.floor(Date.now() / 1000), data: { object: JSON.parse(JSON.stringify(ch)) } }])
      await call('process-refund', { booking_id: BID, reason: 'cancellation_retry' }, 'service'); await deliver()
    } else { await velinConfirm(3500); await deliver() }
    if (liveKc() !== 3500 || cnKc() !== liveKc()) bad.push(`${how}: vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč (${creditNotes().map((x: any) => x.total).join(', ')}); mail: ${m?.html.slice(0, 300)}`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5 V3: událost „failed“ staré vratky doručená PO úspěšném opakování neotevře rezervaci znovu', ignore: !MAPPED, fn: async () => {
  fresh(10); bk().total_price = 2500; world().refundStatus = () => 'pending'
  await pr(500, 'service', 'shortening'); await deliver()
  world().refundStatus = () => 'succeeded'
  const r1 = world().refunds[0]
  await fail(r1) // charge.refund.updated
  advance(5)
  await pr(500, 'service', 'shortening'); await deliver() // opakování (nový klíč :f1) — uspěje
  const after = bk().payment_status
  await fail(r1, 'evt_ru_' + r1.id) // týž stav, druhý typ události (refund.updated) / Stripe retry doručení
  if (after !== 'partial_refund' || bk().payment_status !== 'partial_refund' || liveKc() !== 500) {
    throw new Error(`po opakování ${after}, po staré události ${bk().payment_status}, vráceno ${liveKc()} Kč`)
  }
} })

Deno.test({ name: 'i5 V4/V5: hlavní vratka hotová, zbytek z jiné platby čeká → zůstává refund_pending; zbytek uspěje → refunded', ignore: !MAPPED, fn: async () => {
  fresh(10, { extra: [{ id: 'pi_ext1', czk: 500 }] })
  world().refundStatus = () => 'pending'
  const { velinCancel } = await import('./storno-dispatch.ts')
  await velinCancel('full'); await deliver()
  world().refundStatus = () => 'succeeded'
  const main = world().refunds.find((r: any) => r.metadata.mg_part !== 'remainder')
  const rem = world().refunds.find((r: any) => r.metadata.mg_part === 'remainder')
  const s0 = bk().payment_status
  await succeed(main)
  const s1 = bk().payment_status
  await succeed(rem)
  const s2 = bk().payment_status
  if (s0 !== 'refund_pending' || s1 !== 'refund_pending' || s2 !== 'refunded') throw new Error(`stavy: po stornu ${s0}, hlavní hotová ${s1} (čekáno refund_pending — zbytek 3000 Kč čeká), zbytek hotový ${s2}`)
} })

Deno.test({ name: 'i5 V6: druhá pozdní platba zrušené a už vrácené rezervace → vrátí se (nebo mail obsluze), ne tiché ponechání', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { status: 'cancelled', payment_status: 'unpaid', booking_source: 'web', stripe_payment_intent_id: null, cancelled_at: new Date().toISOString() } })
  world().intents.delete('pi_orig')
  const db = (globalThis as any).__STORNO_DB
  db.rpcs.confirm_payment = () => ({ data: { success: false, error: 'moto_unavailable' }, error: null }) // motorka mezitím obsazená
  const pay = async (pi: string) => {
    world().addPi(pi, 3000, { booking_id: BID, type: 'booking' }, -60)
    const o = world().intents.get(pi)!
    await deliver([{ id: 'evt_' + pi, type: 'payment_intent.succeeded', created: Math.floor(Date.now() / 1000),
      data: { object: { id: pi, object: 'payment_intent', currency: 'czk', amount: o.amount, amount_received: o.amount_received, status: 'succeeded', metadata: o.metadata, customer: null, created: o.created, latest_charge: o.latest_charge } } }])
  }
  await pay('pi_late1')
  const s1 = bk().payment_status, back1 = liveKc()
  opsMails.length = 0
  await pay('pi_late2') // druhá záložka / starší Checkout Session zaplacená později
  const late2 = world().refunds.filter((r: any) => r.payment_intent === 'pi_late2' && r.status !== 'failed').reduce((s: number, r: any) => s + r.amount, 0) / 100
  const told = opsMails.some((m) => /pi_late2/.test(m.html))
  if (s1 !== 'refunded' || back1 !== 3000 || (late2 !== 3000 && !told)) {
    throw new Error(`1. platba: ${s1}, vráceno ${back1}; 2. platba vrácena ${late2} Kč, mail obsluze ${told} — ${JSON.stringify(rows('debug_log').map((d: any) => d.action).slice(-5))}`)
  }
} })

Deno.test({ name: 'i5 V7: selhaná vratka duplicitní platby → vratka ručně v dashboardu (dle mailu) nemění stav živé zaplacené rezervace', ignore: !MAPPED, fn: async () => {
  fresh(10)
  world().addPi('pi_dup', 3000, { booking_id: BID, type: 'booking', duplicate_of: 'pi_orig' })
  world().refundStatus = () => 'pending'
  const r = await world().api().refunds.create({ payment_intent: 'pi_dup', amount: 300000, metadata: { mg_source: 'duplicate_payment', booking_id: BID, kept: 'pi_orig' } }, { idempotencyKey: 'mg-dup-pi_dup' })
  world().refundStatus = () => 'succeeded'
  await deliver()
  opsMails.length = 0
  await fail(world().refunds.find((x: any) => x.id === r.id))
  if (!opsMails.some((m) => /Stripe dashboard/.test(m.html))) throw new Error('chybí mail „vraťte ručně ve Stripe dashboardu“')
  await world().dashboardRefund('pi_dup'); await deliver() // obsluha podle mailu
  if (bk().payment_status !== 'paid' || bk().stripe_refund_id) throw new Error(`rezervace po ruční vratce duplicity: ${bk().payment_status}, stripe_refund_id ${bk().stripe_refund_id}`)
} })

Deno.test({ name: 'i5 V9: selhaná storno vratka a „Potvrdit vrácení“ bez ručního zrušení dobropisu → vratka se zopakuje, mail nelže', ignore: !MAPPED, fn: async () => {
  fresh(10); world().refundStatus = () => 'pending'
  const { velinCancel } = await import('./storno-dispatch.ts')
  await velinCancel('full'); await deliver()
  world().refundStatus = () => 'succeeded'
  await fail(world().refunds[0])
  advance(10); mails.length = 0
  await velinConfirm(3000); await deliver() // obsluha klikne „Potvrdit vrácení“ (dobropis selhané vratky ještě živý)
  const m = customerMails().at(-1)
  if (liveKc() !== 3000 || cnKc() !== liveKc() || (m && m.amount !== liveKc())) {
    throw new Error(`vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč, mail zákazníkovi ${JSON.stringify(m)}, stav ${bk().payment_status}`)
  }
} })

Deno.test({ name: 'i5 V10 (kontrola): po selhání dvě souběžná opakování (dvojklik / služba) → jedna nová vratka', ignore: !MAPPED, fn: async () => {
  const bad: string[] = []
  for (const as of ['admin', 'service'] as const) {
    fresh(10); world().refundStatus = () => 'pending'
    const c = await customerCancel('none'); await deliver()
    world().refundStatus = () => 'succeeded'
    await fail(world().refunds[0])
    for (const x of creditNotes()) x.status = 'cancelled'
    advance(10)
    await Promise.all([pr(as === 'admin' ? undefined : c.amt, as), pr(as === 'admin' ? undefined : c.amt, as)]); await deliver()
    if (liveKc() !== 3000 || cnKc() !== 3000) bad.push(`${as}: vráceno ${liveKc()} Kč, dobropisy ${cnKc()} Kč — ${JSON.stringify(world().creates.map((x: any) => x.result))}`)
  }
  if (bad.length) throw new Error(bad.join('\n'))
} })

Deno.test({ name: 'i5 V8: modifiedRefundCovered — web úprava (at se zónou) + pak appka 4.1.3 (at bez zóny): dobropis dřívější úpravy nekryje novou', ignore: !MAPPED, fn: () => {
  const t0 = Date.parse('2026-11-07T08:00:00Z')
  const history = [{ type: 'edit', at: '2026-11-07T08:00:00+00:00' }, { type: 'edit', at: '2026-11-07T10:30:00.123456' }] // druhá = appka (místní čas)
  const since = newestModificationMs(history)
  const cnOfFirst = { total: -500, created_at: new Date(t0 + 60_000).toISOString() } // vratka 1. úpravy (500 Kč)
  // 2. úprava (appka) s vratkou 300 Kč se neprovedla → mail nesmí tvrdit dobropis v příloze
  if (coversModification(cnOfFirst, 300, since, t0 + 2.6 * 3600_000)) throw new Error(`dobropis 1. úpravy kryje 2. (sinceMs ${since && new Date(since).toISOString()})`)
} })

