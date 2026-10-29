// ===== _tests/storno_hotfix_test.ts =====
// HOTFIX storno 2026-10-29: jednotkové testy send-cancellation-email/trigger-dispatch.ts
// a process-refund/cancel-once.ts + spouštěč flow testů celých handlerů (storno_hotfix_*_flow_test.ts)
// v PODPROCESU s import mapou storno-flow-map.json — pokryje je i běžné
//   deno test --allow-all --no-check supabase/functions/_tests/
import { hasSubMs, isTriggerDispatch, resolveTriggerDispatch, sameInstant } from '../send-cancellation-email/trigger-dispatch.ts'
import { acquireCancelLock, cancelToken, duplicateAdminRefunds, instantKey, priorCancellationRefunds, releaseCancelLock, type StripeRefundLike } from '../process-refund/cancel-once.ts'
import { Db } from './storno-fake-db.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
const BID = '11111111-2222-4333-8444-555555555555'
const RPC_TS = '2026-10-29T09:55:12.123456+00:00'

Deno.test('trigger-dispatch: tvar volání z DB triggeru (jediný bez e-mailu i vratky)', () => {
  eq(isTriggerDispatch({ booking_id: BID, cancellation_reason: 'x', cancelled_by_source: 'velin', source: 'app' }), true, 'trigger')
  eq(isTriggerDispatch({ booking_id: BID, source: 'app' }), true, 'mrtvý helper appky — bez peněz je to bezpečnější')
  eq(isTriggerDispatch({ booking_id: BID, customer_email: 'a@b.cz', refund_amount: 1500, refund_percent: 50 }), false, 'Velín / RPC / webhook')
  eq(isTriggerDispatch({ booking_id: BID, customer_email: 'a@b.cz' }), false, 'Velín storno „částečně vráceno“ (tabulka beze změny)')
  eq(isTriggerDispatch({ booking_id: BID, customer_email: 'a@b.cz', refund_amount: 0, refund_percent: 0 }), false, 'cron auto_cancel_expired_pending')
  eq(isTriggerDispatch({ booking_id: BID, refund_amount: 0, refund_percent: 0 }), false, 'volba 0 % bez e-mailu')
  eq(isTriggerDispatch({ booking_id: BID, skip_refund: true, force: true }), false, 'Velín Potvrdit vrácení')
})

Deno.test('trigger-dispatch: shoda okamžiku na mikrosekundy (RPC transakce) vs. čas z prohlížeče', () => {
  eq(sameInstant(RPC_TS, RPC_TS), true)
  eq(sameInstant('2026-10-29T09:55:12.1234+00:00', '2026-10-29T09:55:12.123400+00:00'), true, 'Postgres ořezává nuly')
  eq(sameInstant(RPC_TS, '2026-10-29T09:55:12.123457+00:00'), false)
  eq(sameInstant('2026-10-29T09:55:12.123Z', '2026-10-29T09:55:12.123+00:00'), true)
  eq([hasSubMs(RPC_TS), hasSubMs('2026-10-29T09:55:12.1234+00:00'), hasSubMs('2026-10-29T09:55:12.123+00:00'), hasSubMs('2026-10-29T09:55:12.123Z'), hasSubMs(null)],
    [true, true, false, false, false])
})

function dbWith(bk: Record<string, unknown>, rows: Array<Record<string, unknown>> = []) {
  return new Db({ bookings: [{ id: BID, ...bk }], booking_cancellations: rows.map((r) => ({ booking_id: BID, ...r })) })
}
Deno.test('trigger-dispatch: převezme jen rozhodnutí cancel_booking_tracked z téže transakce, jinak bez peněz', async () => {
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'paid', cancelled_at: RPC_TS }, [{ refund_amount: 1500, refund_percent: 50, created_at: RPC_TS }]), BID),
    { action: 'adopt', refund_amount: 1500, refund_percent: 50 }, 'RPC')
  const velinTs = '2026-10-29T09:55:12.120Z', ADM = 'adm-1', velin = { cancelled_by: ADM, cancelled_by_source: 'velin' }
  const skip = (staff: boolean, src: string | null) => ({ action: 'skip', why: 'paid_without_tracked_decision', staff, cancelled_by_source: src })
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'refund_pending', cancelled_at: velinTs, ...velin }, [{ refund_amount: 1500, refund_percent: 50, created_at: '2026-10-29T09:55:12.20431+00:00', cancelled_by: ADM }]), BID),
    skip(false, 'velin'), 'Velín (záznam zapsaný až po UPDATE)')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'paid', cancelled_at: velinTs, ...velin }, [{ refund_amount: 0, refund_percent: 0, created_at: velinTs, cancelled_by: 'jiny' }]), BID),
    skip(false, 'velin'), 'shoda jen na ms a jiný cancelled_by se nepřevezme')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'paid', cancelled_at: '2026-10-29T09:55:12.12+00:00', cancelled_by: 'u1' }, [{ refund_amount: 1500, refund_percent: 50, created_at: '2026-10-29T09:55:12.12+00:00', cancelled_by: 'u1' }]), BID),
    { action: 'adopt', refund_amount: 1500, refund_percent: 50 }, 'RPC s now() končícím …000 µs (týž cancelled_by)')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'refunded', cancelled_at: velinTs, cancelled_by_source: 'stripe_portal' }), BID), skip(false, 'stripe_portal'), 'Stripe portál')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'paid', cancelled_at: velinTs, cancelled_by_source: 'admin' }), BID), skip(true, 'admin'), 'hromadné „Zrušit“ → varování obsluze')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'paid', cancelled_at: velinTs }), BID), skip(true, null), 'AI copilot → varování obsluze')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'paid', cancelled_at: RPC_TS }, [{ refund_amount: 3000, refund_percent: 100, created_at: '2026-10-28T09:00:00.5551+00:00' }]), BID),
    skip(true, null), 'starý záznam z dřívějšího storna')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'unpaid', cancelled_at: velinTs }), BID), { action: 'mail_only' }, 'nezaplacená')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'unpaid', cancelled_at: RPC_TS }, [{ refund_amount: 3000, refund_percent: 100, created_at: RPC_TS }]), BID),
    { action: 'mail_only' }, 'nezaplacená přes cancel_booking_tracked → mail BEZ vratky (RPC zapisuje částku i bez platby)')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: null, cancelled_at: RPC_TS }, [{ refund_amount: 3000, refund_percent: 100, created_at: RPC_TS }]), BID), { action: 'mail_only' }, 'NULL')
  eq(await resolveTriggerDispatch(new Db({ bookings: [] }), BID), { action: 'skip', why: 'booking_unreadable' })
})

const ref = (o: Partial<StripeRefundLike> & { md?: Record<string, string> }): StripeRefundLike => ({
  id: o.id || 're_x', amount: o.amount ?? 150000, status: o.status || 'succeeded', created: o.created ?? Date.parse('2026-10-29T10:00:00Z') / 1000,
  metadata: { mg_source: 'process-refund', mg_reason: 'cancellation', mg_booking_id: BID, ...(o.md || {}) },
})
Deno.test('cancel-once: vratka TOHOTO storna = naše storno vratka se značkou cancelled_at (starší verze: časem)', () => {
  const tok = cancelToken('2026-10-29T10:00:00.123+00:00')
  const ids = (rs: StripeRefundLike[]) => priorCancellationRefunds(rs, BID, tok).map((r) => r.id)
  eq(ids([ref({ id: 'a', md: { mg_cancel_at: tok } }), ref({ id: 'b', md: { mg_cancel_at: '2026-09-01T10:00:00+00:00' } })]), ['a'], 'jiné (dřívější) storno se nepočítá')
  eq(ids([ref({ id: 'p', status: 'pending', md: { mg_cancel_at: tok } }), ref({ id: 'f', status: 'failed', md: { mg_cancel_at: tok } })]), ['p'], 'pending ano, failed ne')
  eq(ids([ref({ id: 's', md: { mg_reason: 'edit_shortening', mg_cancel_at: tok } }), ref({ id: 'o', md: { mg_booking_id: 'jina', mg_cancel_at: tok } })]), [], 'zkrácení / jiná rezervace')
  eq(ids([ref({ id: 'd', md: { mg_source: '' } })]), [], 'ruční vratka v dashboardu')
  eq(ids([ref({ id: 'l1', created: Date.parse('2026-10-29T09:30:00Z') / 1000 }), ref({ id: 'l2', created: Date.parse('2026-10-29T08:00:00Z') / 1000 })]), ['l1'], 'bez značky: ±1 h')
  eq(priorCancellationRefunds([ref({ id: 'n' })], BID, '').map((r) => r.id), ['n'], 'bez cancelled_at: každá naše storno vratka')
  eq(priorCancellationRefunds([ref({ id: 'e', md: { mg_cancel_at: '' } }), ref({ id: 'x', md: { mg_cancel_at: tok } })], BID, '').map((r) => r.id), ['e'], 'bez cancelled_at: vratka bez cancelled_at')
  eq(cancelToken(null), '')
  // okamžik, ne text: 'Z' / '+00:00' / ořezané nuly / posun zóny (jiná verze PostgRESTu)
  const t6 = '2026-10-29T10:00:00.1234+00:00'
  for (const same of ['2026-10-29T10:00:00.123400+00:00', '2026-10-29T10:00:00.1234Z', '2026-10-29T11:00:00.1234+01:00']) {
    eq(priorCancellationRefunds([ref({ id: 's', md: { mg_cancel_at: same } })], BID, t6).map((r) => r.id), ['s'], same)
  }
  eq(priorCancellationRefunds([ref({ id: 'd', md: { mg_cancel_at: '2026-10-29T10:00:00.1235+00:00' } })], BID, t6).length, 0, 'jiná mikrosekunda')
  eq([instantKey('2026-10-29T10:00:00Z'), instantKey('2026-10-29T10:00:00.000000+00:00'), instantKey(''), instantKey('x')],
    [`${Date.parse('2026-10-29T10:00:00Z')}.000`, `${Date.parse('2026-10-29T10:00:00Z')}.000`, null, null])
})

Deno.test('cancel-once: obsluha — duplicita téhož požadavku (stejná částka ≤ 3 min / vratka vzniklá při čekání na zámek)', () => {
  const now = Date.parse('2026-10-29T10:00:00Z') / 1000
  const ids = (rs: StripeRefundLike[], amountHaleru: number | null, lock: { held: boolean; waited: boolean; sinceS: number | null } | null) =>
    duplicateAdminRefunds(rs, BID, { amountHaleru, nowS: now, lock }).map((r) => r.id)
  const r1 = ref({ id: 'r1', amount: 150000, created: now - 30 })
  eq(ids([r1], 150000, null), ['r1'], 'dvojité odeslání (i čekající „pending“)')
  eq(ids([r1], 200000, null), [], '„Potvrdit vrácení“ jiné částky = vědomá další vratka')
  eq(ids([ref({ id: 'old', amount: 150000, created: now - 600 })], 150000, null), [], 'stejná částka po 10 min = vědomá')
  eq(ids([ref({ id: 'mine', amount: 150000, created: now - 400 })], 150000, { held: true, waited: true, sinceS: now - 500 }), ['mine'], 'čekal na zámek od dřívějška')
  eq(ids([r1], null, null), [], 'plná vratka bez čekání: dorovná zbytek jako dřív')
  eq(ids([r1], null, { held: true, waited: true, sinceS: now - 60 }), ['r1'], 'plná vratka, souběžné volání vratku mezitím provedlo')
  eq(ids([ref({ id: 'b4', amount: 150000, created: now - 90 })], null, { held: true, waited: true, sinceS: now - 60 }), [], 'vratka před začátkem čekání')
  eq(ids([ref({ id: 'sh', amount: 150000, created: now - 5, md: { mg_reason: 'edit_shortening' } })], 150000, null), [], 'jen storno vratky')
})

Deno.test('cancel-once: zámek storno vratky přes claim_email_send(refund_cancellation) se po doběhnutí uvolní', async () => {
  const db = new Db({ email_send_locks: [] })
  db.rpcs.claim_email_send = (a) => {
    const rows = db.rows('email_send_locks')
    if (rows.some((x) => x.booking_id === a.p_booking_id && x.template_slug === a.p_slug)) return { data: false, error: null }
    rows.push({ booking_id: a.p_booking_id, template_slug: a.p_slug }); return { data: true, error: null }
  }
  eq(await acquireCancelLock(db, BID), { held: true, waited: false, sinceS: null })
  eq(db.rows('email_send_locks').map((x) => x.template_slug), ['refund_cancellation'])
  await releaseCancelLock(db, BID)
  eq(db.rows('email_send_locks').length, 0)
  eq(await acquireCancelLock(new Db({}), BID), { held: false, waited: false, sinceS: null }, 'RPC chybí → bez zámku (rozhodne kontrola Stripe vratek)')
  // drženo jiným voláním → čeká (polling), pak dostane zámek; sinceS = od kdy ho drží ono
  const lockedAt = '2026-10-29T10:00:00.5+00:00'
  db.rows('email_send_locks').push({ booking_id: BID, template_slug: 'refund_cancellation', locked_at: lockedAt })
  setTimeout(() => void releaseCancelLock(db, BID), 300)
  eq(await acquireCancelLock(db, BID), { held: true, waited: true, sinceS: Date.parse(lockedAt) / 1000 - 2 - 0.5 })
})

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
const CAN_RUN = (() => { try { return Deno.permissions.querySync({ name: 'run' }).state === 'granted' } catch { return false } })()
const FLOW_FILES = ['./storno_hotfix_trigger_flow_test.ts', './storno_hotfix_once_flow_test.ts', './storno_hotfix_r1_flow_test.ts']
const FLOW_MIN = 7 + 10 + 7 // počet flow testů (ubyl-li by některý, spouštěč selže)

Deno.test({ name: 'storno hotfix: flow testy celých handlerů (podproces s import mapou storno-flow-map.json)', ignore: MAPPED || !CAN_RUN, fn: async () => {
  const p = (f: string) => new URL(f, import.meta.url).pathname
  const out = await new Deno.Command(Deno.execPath(), { // env (i STORNO_FN_DIR) se dědí
    args: ['test', '--allow-all', '--no-check', `--import-map=${p('./storno-flow-map.json')}`, ...FLOW_FILES.map(p)],
    env: { NO_COLOR: '1' }, stdout: 'piped', stderr: 'piped',
  }).output()
  const txt = new TextDecoder().decode(out.stdout) + '\n' + new TextDecoder().decode(out.stderr)
  const m = /(\d+) passed \| (\d+) failed(?: \| (\d+) ignored)?/.exec(txt)
  if (!out.success || !m || Number(m[1]) < FLOW_MIN || m[2] !== '0' || Number(m[3] || 0) > 0) {
    throw new Error(`storno flow testy neprošly (exit ${out.code}):\n${txt.slice(-8000)}`)
  }
} })
