// ===== _tests/fio_change_flow_test.ts =====
// Doplatek ÚPRAVY REZERVACE z webu zaplacený převodem (bank_payment_requests kind 'booking_change'):
// změna se zapíše až po připsání peněz STEJNOU rutinou jako po kartě (applyPaidExtension, payRef 'FIO …');
// když už zapsat nejde, rezervace zůstane beze změny, obsluha vrací peníze ručně (žádná vratka přes Stripe);
// platba po lhůtě / po zrušení jde obsluze a „Přesto provést“ (ruční spárování) spustí tutéž rutinu.
// Spuštění: deno test --allow-all --no-check --import-map=supabase/functions/_tests/storno-flow-map.json supabase/functions/_tests/fio_change_flow_test.ts
// deno-lint-ignore-file no-explicit-any
import { BID, booking, clock, eq, fioTx, FN, MAPPED, now, ok, opsSubjects, request, RID, type Row, SB, statement, SVC, tx, txRow } from './bank-helpers.ts'
import { world } from './bank-world.ts'

const run: any = MAPPED ? await import(`${FN}fio-sync/run.ts`) : null
const ext: any = MAPPED ? await import(`${FN}_shared/extension-apply.ts`) : null
const T = (name: string, fn: () => Promise<void>) => Deno.test({ name, ignore: !MAPPED, sanitizeOps: false, sanitizeResources: false, fn })

const paid = (o: Row = {}) => booking({ status: 'reserved', payment_status: 'paid', payment_method: 'card', payment_vs: null, pay_channel: null,
  start_date: '2026-12-20T00:00:00+00:00', end_date: '2026-12-22T00:00:00+00:00', pickup_time: '10:00:00', card_rounding: 0, delivery_fee: 0,
  pickup_method: 'branch', pickup_address: null, return_method: 'branch', return_address: null, late_pickup_discount_amount: 0,
  original_start_date: null, updated_at: '2026-12-01T09:00:00.000Z', ...o })
// prodloužení o den naceněné serverem: +1 500 Kč (cílová cena 4 500)
const chg = JSON.stringify({ p_new_end: '2026-12-23', _base: { s: '2026-12-20', e: '2026-12-22', t: '10:00', p: 3000 } })
const change = (o: Row = {}) => request({ kind: 'booking_change', vs: '10000400', amount: 1500, booking_id: BID, order_id: null, chg,
  srv: JSON.stringify({ t: 4500, f: ext.placeFingerprint(paid()) }), change_kind: 'edit', created_at: '2026-12-01T09:30:00Z', expires_at: '2026-12-01T10:30:00Z', ...o })
const sync = (db: any) => run.runSync(db, { token: 'tok', env: { url: SB, key: SVC, now } })
const give = (w: any, txs: unknown[]) => w.n.fio.push(() => new Response(statement(txs), { status: 200 }))
const bk = (w: any) => w.db.rows('bookings')[0]
const rq = (w: any) => w.db.rows('bank_payment_requests')[0]

T('doplatek úpravy zaplacen včas: změna zapsána jednou (payment_ref FIO …), požadavek paid, pohyb confirmed_change; opakování nic nezdvojí', async () => {
  const w = world({ bookings: [paid()], bank_payment_requests: [change()] })
  try {
    give(w, [fioTx(700, 1500, { vs: '10000400' })])
    const r = await sync(w.db)
    eq(r.body.changes, 1)
    eq([bk(w).end_date, bk(w).total_price, bk(w).status], ['2026-12-23', 4500, 'reserved'])
    const h = bk(w).modification_history
    eq([h.length, h[0].payment_ref, h[0].price_diff, h[0].to_end], [1, 'FIO 700', 1500, '2026-12-23'])
    eq([rq(w).status, rq(w).fio_id, rq(w).result.state], ['paid', 700, 'applied'])
    const t = tx(w.db, 700)
    eq([t.status, t.booking_id, t.request_id, t.target_type, t.expected_amount], ['confirmed_change', BID, RID, 'request', 1500])
    eq(w.db.rows('admin_audit_log').map((a: Row) => a.action), ['booking_change_paid_fio'])
    eq(w.n.calls.filter((c: any) => c.url.includes('stripe')).length, 0, 'žádné volání Stripe')
    // druhý pohyb se stejným VS = duplicita, změna se nezapíše podruhé
    clock.t += 60_000
    give(w, [fioTx(701, 1500, { vs: '10000400' })])
    await sync(w.db)
    eq([tx(w.db, 701).status, tx(w.db, 701).reason_code, bk(w).total_price, bk(w).modification_history.length], ['needs_review', 'duplicate', 4500, 1])
  } finally { w.n.restore() }
})

T('změnu už nejde zapsat (termín mezitím obsazen): rezervace beze změny, požadavek failed s důvodem, obsluha má vrátit převodem — žádná automatická vratka', async () => {
  const w = world({ bookings: [paid()], bank_payment_requests: [change()] })
  try {
    w.db.failUpdate = (t: string, p: Row) => (t === 'bookings' && 'end_date' in p ? { code: 'P0001', message: 'Překrývající se rezervace pro moto_id m1' } : null)
    give(w, [fioTx(710, 1500, { vs: '10000400', account: '987654321' })])
    await sync(w.db)
    eq([bk(w).end_date, bk(w).total_price, bk(w).modification_history.length], ['2026-12-22T00:00:00+00:00', 3000, 0])
    eq([rq(w).status, rq(w).result.reason, rq(w).fio_id], ['failed', 'moto_unavailable', 710])
    const t = tx(w.db, 710)
    eq([t.status, t.reason_code, t.booking_id, t.request_id], ['needs_review', 'change_failed', BID, RID])
    const log = w.db.rows('debug_log').find((d: Row) => d.action === 'paid_change_failed')
    eq([log.request_data.payment_ref, log.request_data.expect_refund, log.response_data.refund], ['FIO 710', 'staff', 'staff'])
    const mail = w.n.mails.find((m: Row) => String(m.subject).includes('nešlo zapsat') || String(m.subject).includes('obsazená'))
    ok(mail && String(mail.raw_html).includes('převodem zpět') && String(mail.raw_html).includes('987654321/0800') && !String(mail.raw_html).includes('Stripe'), JSON.stringify(mail))
    eq(w.n.calls.filter((c: any) => c.url.includes('stripe') || c.url.includes('process-refund')).length, 0, 'žádná automatická vratka')
  } finally { w.n.restore() }
})

T('doplatek po lhůtě 60 min: nic se nezapíše, jde obsluze; „Přesto provést“ (ruční spárování s požadavkem) spustí stejnou rutinu', async () => {
  const w = world({ bookings: [paid()], bank_payment_requests: [change({ status: 'pending', expires_at: '2026-12-01T09:50:00Z' })] })
  try {
    give(w, [fioTx(720, 1500, { vs: '10000400' })])
    await sync(w.db)
    eq([tx(w.db, 720).status, tx(w.db, 720).reason_code, bk(w).total_price], ['needs_review', 'request_expired', 3000])
    ok(opsSubjects(w.n)[0].includes('po lhůtě'), opsSubjects(w.n)[0])
    // obsluha: admin_fio_pair_transaction(720, 'request', RID) → pohyb zpět do fronty s ručním cílem
    Object.assign(tx(w.db, 720), { status: 'new', manual_target_type: 'request', manual_target_id: RID, claimed_until: null })
    const r = await run.processOne(w.db, { url: SB, key: SVC, now }, 720)
    eq([r.result.status, r.result.reason_code], ['confirmed_change', 'manual'])
    eq([bk(w).end_date, bk(w).total_price, rq(w).status], ['2026-12-23', 4500, 'paid'])
  } finally { w.n.restore() }
})

T('zákazník požadavek zrušil a přesto zaplatil; rezervace mezitím stornovaná; nedoplatek', async () => {
  const w = world({ bookings: [paid()], bank_payment_requests: [change({ status: 'cancelled' })] })
  try {
    give(w, [fioTx(730, 1500, { vs: '10000400' })])
    await sync(w.db)
    eq([tx(w.db, 730).status, tx(w.db, 730).reason_code, bk(w).total_price], ['needs_review', 'request_cancelled', 3000])
  } finally { w.n.restore() }
  const w2 = world({ bookings: [paid({ status: 'cancelled' })], bank_payment_requests: [change()] })
  try {
    give(w2, [fioTx(731, 1500, { vs: '10000400' })])
    await sync(w2.db)
    eq([tx(w2.db, 731).status, tx(w2.db, 731).reason_code, rq(w2).status, rq(w2).result.reason], ['needs_review', 'change_failed', 'failed', 'booking_cancelled'])
  } finally { w2.n.restore() }
  const w3 = world({ bookings: [paid()], bank_payment_requests: [change()] })
  try {
    give(w3, [fioTx(732, 1000, { vs: '10000400' })])
    await sync(w3.db)
    eq([tx(w3.db, 732).status, rq(w3).status, bk(w3).total_price], ['amount_mismatch', 'pending', 3000])
  } finally { w3.n.restore() }
})

T('přechodná chyba zápisu: pohyb i požadavek zůstávají čekat a další běh změnu dokončí', async () => {
  const w = world({ bookings: [paid()], bank_payment_requests: [change({ expires_at: '2026-12-01T12:00:00Z' })], fio_transactions: [txRow(740, 1500, { vs: '10000400' })] })
  try {
    let fail = true
    w.db.failUpdate = (t: string, p: Row) => (fail && t === 'bookings' && 'end_date' in p ? { code: '08006', message: 'connection failure' } : null)
    await sync(w.db)
    eq([tx(w.db, 740).status, tx(w.db, 740).attempts, rq(w).status, bk(w).total_price], ['new', 1, 'pending', 3000])
    fail = false
    clock.t += 60_000
    await sync(w.db)
    eq([tx(w.db, 740).status, rq(w).status, bk(w).total_price, bk(w).modification_history.length], ['confirmed_change', 'paid', 4500, 1])
  } finally { w.n.restore() }
})
