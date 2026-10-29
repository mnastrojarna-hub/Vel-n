// ===== _tests/storno_hotfix_test.ts =====
// HOTFIX storno 2026-10-29: jednotkové testy send-cancellation-email/trigger-dispatch.ts
// a process-refund/cancel-once.ts + spouštěč flow testů celých handlerů (storno_hotfix_*_flow_test.ts)
// v PODPROCESU s import mapou storno-flow-map.json — pokryje je i běžné
//   deno test --allow-all --no-check supabase/functions/_tests/
import { hasSubMs, isTriggerDispatch, resolveTriggerDispatch, sameInstant } from '../send-cancellation-email/trigger-dispatch.ts'
import { acquireCancelLock, cancelToken, priorCancellationRefunds, releaseCancelLock, type StripeRefundLike } from '../process-refund/cancel-once.ts'
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
  const velinTs = '2026-10-29T09:55:12.120Z'
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'refund_pending', cancelled_at: velinTs }, [{ refund_amount: 1500, refund_percent: 50, created_at: '2026-10-29T09:55:12.20431+00:00' }]), BID),
    { action: 'skip', why: 'paid_without_tracked_decision' }, 'Velín')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'paid', cancelled_at: velinTs }, [{ refund_amount: 0, refund_percent: 0, created_at: velinTs }]), BID),
    { action: 'skip', why: 'paid_without_tracked_decision' }, 'Velín 0 %, shoda na ms se nepřevezme')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'refunded', cancelled_at: velinTs }), BID), { action: 'skip', why: 'paid_without_tracked_decision' }, 'Stripe portál')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'paid', cancelled_at: RPC_TS }, [{ refund_amount: 3000, refund_percent: 100, created_at: '2026-10-28T09:00:00.5551+00:00' }]), BID),
    { action: 'skip', why: 'paid_without_tracked_decision' }, 'starý záznam z dřívějšího storna')
  eq(await resolveTriggerDispatch(dbWith({ payment_status: 'unpaid', cancelled_at: velinTs }), BID), { action: 'mail_only' }, 'nezaplacená')
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
  eq(cancelToken(null), '')
})

Deno.test('cancel-once: zámek storno vratky přes claim_email_send(refund_cancellation) se po doběhnutí uvolní', async () => {
  const db = new Db({ email_send_locks: [] })
  db.rpcs.claim_email_send = (a) => {
    const rows = db.rows('email_send_locks')
    if (rows.some((x) => x.booking_id === a.p_booking_id && x.template_slug === a.p_slug)) return { data: false, error: null }
    rows.push({ booking_id: a.p_booking_id, template_slug: a.p_slug }); return { data: true, error: null }
  }
  eq(await acquireCancelLock(db, BID), true)
  eq(db.rows('email_send_locks').map((x) => x.template_slug), ['refund_cancellation'])
  await releaseCancelLock(db, BID)
  eq(db.rows('email_send_locks').length, 0)
  eq(await acquireCancelLock(new Db({}), BID), false, 'RPC chybí → bez zámku (rozhodne kontrola Stripe vratek)')
})

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
const CAN_RUN = (() => { try { return Deno.permissions.querySync({ name: 'run' }).state === 'granted' } catch { return false } })()
const FLOW_FILES = ['./storno_hotfix_trigger_flow_test.ts', './storno_hotfix_once_flow_test.ts']
const FLOW_MIN = 7 + 10 // počet flow testů (ubyl-li by některý, spouštěč selže)

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
