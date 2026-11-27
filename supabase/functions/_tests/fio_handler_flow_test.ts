// ===== _tests/fio_handler_flow_test.ts =====
// Vstup fio-sync (handler.ts): kdo smí volat a akce pro Velín — pair (RPC jménem admina + okamžité
// potvrzení stejnou rutinou), process, suggest (nic nepotvrzuje), waiting, set_marker (jen superadmin).
// Spuštění: deno test --allow-all --no-check --import-map=supabase/functions/_tests/storno-flow-map.json supabase/functions/_tests/fio_handler_flow_test.ts
// deno-lint-ignore-file no-explicit-any
import { BID, booking, eq, fioCalls, FN, MAPPED, ok, order, post, request, type Row, tx, txRow } from './bank-helpers.ts'
import { world } from './bank-world.ts'

if (MAPPED) Deno.env.set('FIO_API_TOKEN', 'tok')
const handle: any = MAPPED ? (await import(`${FN}fio-sync/handler.ts`)).handle : null
const T = (name: string, fn: () => Promise<void>) => Deno.test({ name, ignore: !MAPPED, sanitizeOps: false, sanitizeResources: false, fn })
const ADMIN = 'adm.jwt.token', CUST = 'cus.jwt.token'
const g = globalThis as any

function setup(tables: Record<string, Row[]> = {}, role = 'admin') {
  const w = world({ admin_users: [{ id: 'adm1', role, active: true }], ...tables })
  let token = ''
  const origRpc = w.db.rpc.bind(w.db)
  // is_admin() a RPC s auditem běží pod JWT volajícího — emulace podle tokenu posledního požadavku
  w.db.rpcs.is_admin = () => ({ data: token === ADMIN, error: null })
  w.db.rpcs.admin_fio_pair_transaction = (a: Row) => {
    if (token !== ADMIN) return { data: { success: false, error: 'forbidden' }, error: null }
    const t = tx(w.db, Number(a.p_fio_id))
    if (!t) return { data: { success: false, error: 'not_found' }, error: null }
    if (!['no_match', 'amount_mismatch', 'needs_review', 'error', 'ignored'].includes(t.status)) return { data: { success: false, error: 'wrong_status', status: t.status }, error: null }
    Object.assign(t, { status: 'new', manual_target_type: a.p_target_type, manual_target_id: a.p_target_id, manual_accept_amount: a.p_accept_amount, resolution_note: a.p_note, resolved_by: 'adm1' })
    return { data: { success: true }, error: null }
  }
  g.__gearAuthUser = { id: 'adm1' }
  const call = (body: Row, t = ADMIN) => { token = t; return post(handle, body, t) }
  return { ...w, call, origRpc }
}

T('volat smí jen server a admin; zákazník ani anonym ne (403) — žádný dotaz na banku', async () => {
  const w = setup()
  try {
    eq((await w.call({}, CUST)).status, 403)
    eq((await w.call({ action: 'suggest', fio_id: 1 }, '')).status, 403)
    eq(fioCalls(w.n).length, 0)
    eq((await w.call({}, ADMIN)).json.success, true) // „Synchronizovat teď“
    eq((await post(handle, {})).json.success, true) // service klíč (cron fio_sync_tick)
    eq(fioCalls(w.n).length, 2)
  } finally { w.n.restore() }
})

T('pair: RPC jménem admina (audit) + okamžité potvrzení; špatný stav / nenalezeno vrací chybu RPC; neznámá akce 400', async () => {
  const w = setup({ bookings: [booking()], fio_transactions: [txRow(950, 3000, { status: 'no_match', note: 'platba bez VS' }), txRow(951, 3000, { status: 'confirmed_booking' })] })
  try {
    const r = await w.call({ action: 'pair', fio_id: 950, target_type: 'booking', target_id: BID, note: 'zákazník zapomněl VS' })
    eq([r.status, r.json.success, r.json.result.status, r.json.result.reason_code, r.json.result.booking_id], [200, true, 'confirmed_booking', 'manual', BID])
    eq(w.db.callsOf('rpc', 'admin_fio_pair_transaction')[0].data, { p_fio_id: 950, p_target_type: 'booking', p_target_id: BID, p_accept_amount: false, p_note: 'zákazník zapomněl VS' })
    eq(w.db.callsOf('rpc', 'confirm_payment').length, 1)
    eq([tx(w.db, 950).resolved_by, tx(w.db, 950).manual_target_type, w.db.rows('bookings')[0].payment_status], ['adm1', 'booking', 'paid'])
    eq((await w.call({ action: 'pair', fio_id: 951, target_type: 'booking', target_id: BID })).json, { success: false, error: 'wrong_status', status: 'confirmed_booking' })
    eq((await w.call({ action: 'pair', fio_id: 5, target_type: 'booking', target_id: BID })).json.error, 'not_found')
    eq((await w.call({ action: 'pair', target_type: 'booking', target_id: BID })).status, 400)
    eq((await w.call({ action: 'nonsense' })).status, 400)
    eq(w.db.callsOf('rpc', 'confirm_payment').length, 1, 'nic dalšího se nepotvrdilo')
  } finally { w.n.restore() }
})

T('pair / process bez nasazeného SQL: bank_unavailable, nic se nezmění', async () => {
  const w = setup({ bookings: [booking()], fio_transactions: [txRow(960, 3000, { status: 'no_match' })] })
  try {
    delete w.db.rpcs.admin_fio_pair_transaction
    delete w.db.rpcs.fio_claim_transactions
    eq((await w.call({ action: 'pair', fio_id: 960, target_type: 'booking', target_id: BID })).json, { success: false, error: 'bank_unavailable' })
    eq((await w.call({ action: 'process', fio_id: 960 })).json, { success: false, error: 'bank_unavailable' })
    eq([tx(w.db, 960).status, w.db.rows('bookings')[0].payment_status], ['no_match', 'unpaid'])
  } finally { w.n.restore() }
})

T('suggest a waiting: návrh nejpravděpodobnějšího cíle, bez jakéhokoli potvrzení', async () => {
  const w = setup({ bookings: [booking({ total_price: 1000 })], shop_orders: [order()], bank_payment_requests: [request()],
    fio_transactions: [txRow(970, 1000, { status: 'no_match', counter_name: 'NOVAK JAN', vs: '10000128' })] })
  try {
    const s = (await w.call({ action: 'suggest', fio_id: 970 })).json
    eq([s.success, s.candidates.length, s.candidates[0].target_type, s.candidates[0].target_id, s.candidates[0].confidence], [true, 2, 'booking', BID, 'high'])
    ok(s.candidates[0].reasons.length >= 3 && s.candidates[1].confidence === 'low', JSON.stringify(s.candidates.map((c: Row) => c.reasons)))
    const wt = (await w.call({ action: 'waiting' })).json
    eq(wt.items.map((i: Row) => [i.kind, i.vs, i.amount]).sort(), [['booking', '10000123', 1000], ['voucher', '10000200', 1000]])
    ok(!('user_id' in wt.items[0]) && !('score' in wt.items[0]))
    eq([w.db.callsOf('rpc', 'confirm_payment').length, w.db.callsOf('rpc', 'confirm_shop_payment').length, tx(w.db, 970).status], [0, 0, 'no_match'])
  } finally { w.n.restore() }
})

T('set_marker: jen superadmin (nebo server); volá set-last-date / set-last-id banky', async () => {
  const w = setup({}, 'admin')
  try {
    eq((await w.call({ action: 'set_marker', date: '2026-12-01' })).status, 403)
    eq(fioCalls(w.n).length, 0)
  } finally { w.n.restore() }
  const s = setup({}, 'superadmin')
  try {
    eq((await s.call({ action: 'set_marker', date: '2026-12-01' })).json, { success: true })
    eq((await s.call({ action: 'set_marker', id: 1147608196 })).json, { success: true })
    eq((await s.call({ action: 'set_marker', date: '1.12.2026' })).status, 400)
    eq(fioCalls(s.n).map((c) => c.url.split('/rest/')[1]), ['set-last-date/tok/2026-12-01/', 'set-last-id/tok/1147608196/'])
    eq(s.db.rows('admin_audit_log').map((a: Row) => a.action), ['fio_marker_set', 'fio_marker_set'])
  } finally { s.n.restore() }
})
