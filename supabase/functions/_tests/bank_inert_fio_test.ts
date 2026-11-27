// ===== _tests/bank_inert_fio_test.ts =====
// DŮKAZ „nový kód + dnešní databáze = dnešní chování“ pro fio-sync. Dnešní databáze = bez SQL 20261130*
// (žádné RPC fio_sync_begin / fio_claim_transactions, žádné nové sloupce ani tabulky). Každý scénář se
// pustí dvakrát nad stejnými daty — zmrazenou kopií dnešního handleru (_tests/legacy/fio_sync_legacy.ts)
// a novým handlerem (fio-sync/handler.ts) — a porovná se VŠE pozorovatelné: odpověď, všechny zápisy do DB
// (tabulka, operace, data), volání RPC, dotazy na banku, volání ostatních edge funkcí (doklady, e-maily
// zákazníkovi i obsluze) a výsledné řádky tabulek. Jediné povolené rozdíly: (1) nový kód se na začátku
// běhu jednou zeptá na RPC fio_sync_begin (neexistuje → starý režim); nic dalšího nového nevolá ani
// nezapisuje; (2) výsledný stav pohybu se zapisuje až po záznamu do debug_log (dřív někde před ním) —
// množina zápisů i jejich obsah jsou totožné, proto se zápisy porovnávají bez ohledu na pořadí; pořadí
// volání RPC, banky a ostatních funkcí (doklady, e-maily) se porovnává přesně.
// Spuštění: deno test --allow-all --no-check --import-map=supabase/functions/_tests/storno-flow-map.json supabase/functions/_tests/bank_inert_fio_test.ts
// deno-lint-ignore-file no-explicit-any
import { BankDb, BID, booking, eq, fioTx, FN, loadHandler, MAPPED, net, OID, ok, order, post, request, type Row, statement, txRow, useDb } from './bank-helpers.ts'

if (MAPPED) Deno.env.set('FIO_API_TOKEN', 'tok')
const legacy = MAPPED ? await loadHandler(`${FN}_tests/legacy/fio_sync_legacy.ts`) : null
const fresh: any = MAPPED ? (await import(`${FN}fio-sync/handler.ts`)).handle : null
const T = (name: string, fn: () => Promise<void>) => Deno.test({ name, ignore: !MAPPED, sanitizeOps: false, sanitizeResources: false, fn })

type Scenario = { tables?: () => Record<string, Row[]>; fio: () => Response; setup?: (db: BankDb) => void }
const B2 = '22222222-2222-4333-8444-555555555555'
const TS = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const KNOWN = new Set([BID, B2, OID])
/** čas zápisu a náhodná id sjednotit, jinak beze změny (i pořadí klíčů se porovnává) */
const normalize = (v: unknown): unknown => JSON.parse(JSON.stringify(v, (_k, x) =>
  typeof x === 'string' ? (TS.test(x) ? '<ts>' : UUID.test(x) && !KNOWN.has(x) ? '<uuid>' : x) : x))

async function observe(handler: any, sc: Scenario) {
  const db = new BankDb({ fio_transactions: [], bookings: [], shop_orders: [], invoices: [], debug_log: [], admin_audit_log: [], message_threads: [], messages: [],
    app_settings: [], ...(sc.tables ? sc.tables() : {}) })
  // dnešní databáze: nové tabulky NEexistují
  db.failSelect = (t) => (['bank_payment_requests', 'fio_sync_state'].includes(t) ? { code: '42P01', message: `relation "public.${t}" does not exist` } : null)
  db.rpcs.confirm_payment = (a: Row) => {
    const b = db.rows('bookings').find((r) => r.id === a.p_booking_id) as Row
    if (b.payment_status === 'paid') return { data: { success: true, was_already_paid: true }, error: null }
    Object.assign(b, { payment_status: 'paid', payment_method: a.p_method, status: 'reserved' })
    return { data: { success: true, was_already_paid: false }, error: null }
  }
  db.rpcs.confirm_booking_surcharge = (a: Row) => { (db.rows('bookings').find((r) => r.id === a.p_booking_id) as Row).mod_surcharge_due = 0; return { data: { success: true }, error: null } }
  db.rpcs.check_booking_docs_status = () => ({ data: null, error: null })
  db.rpcs.check_booking_docs_status_for = () => ({ data: null, error: null })
  db.rpcs.detect_customer_language = () => ({ data: 'cs', error: null })
  sc.setup?.(db)
  useDb(db)
  const n = net()
  n.fio.push(sc.fio)
  try {
    const res = await post(handler, {})
    const writes = db.calls.filter((c) => c.op !== 'select' && c.op !== 'rpc').map((c) => ({ op: c.op, table: c.table, data: c.data }))
    const rpcs = db.calls.filter((c) => c.op === 'rpc').map((c) => ({ fn: c.fn, args: c.data }))
    return normalize({ status: res.status, body: res.json, writes, rpcs, http: n.calls.map((c) => ({ url: c.url, body: c.body })), tables: db.tables })
  } finally { n.restore() }
}

async function parity(name: string, sc: Scenario) {
  const a: any = await observe(legacy, sc)
  const b: any = await observe(fresh, sc)
  const probes = b.rpcs.filter((r: Row) => r.fn === 'fio_sync_begin')
  eq(probes.length, 1, `${name}: právě jeden dotaz na fio_sync_begin`)
  b.rpcs = b.rpcs.filter((r: Row) => r.fn !== 'fio_sync_begin')
  const bag = (w: Row[]) => w.map((x) => JSON.stringify(x)).sort()
  a.writes = bag(a.writes); b.writes = bag(b.writes)
  // debug_log: stejné řádky (pořadí vůči ostatním zápisům viz hlavička)
  for (const k of ['status', 'body', 'rpcs', 'http', 'writes', 'tables']) {
    if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) throw new Error(`${name}: rozdíl v „${k}“\n dnes: ${JSON.stringify(a[k])}\n nově: ${JSON.stringify(b[k])}`)
  }
  return b
}
const st = (txs: unknown[]) => () => new Response(statement(txs), { status: 200 })

T('parita: prázdný výpis, limit banky 409, chyba banky 500, neplatná odpověď, výpadek spojení', async () => {
  const e = await parity('prázdný', { fio: st([]) })
  eq([e.body, e.writes, e.http.length], [{ success: true, fetched: 0, confirmed: 0, surcharge: 0, no_match: 0, mismatch: 0, review: 0, errors: 0 }, [], 1])
  const r = await parity('409', { tables: () => ({ fio_transactions: [txRow(1, 3000, { vs: '10000123' })], bookings: [booking()] }), fio: () => new Response('', { status: 409 }) })
  eq([r.body, r.writes], [{ success: true, skipped: 'rate_limited' }, []])
  const f = await parity('500', { fio: () => new Response('Internal Server Error', { status: 500 }) })
  eq([f.body, f.tables.debug_log.map((d: Row) => d.action)], [{ success: false, error: 'fio_http_500' }, ['fio_fetch_failed']])
  await parity('ne-JSON', { tables: () => ({ fio_transactions: [txRow(2, 20)] }), fio: () => new Response('<html>oops</html>', { status: 200 }) })
  const x = await parity('výpadek', { fio: () => { throw new Error('connection refused') } })
  eq([x.status, x.tables.debug_log.map((d: Row) => d.action)], [500, ['sync_failed']])
})

T('parita: rezervace zaplacená převodem (motorka, výbava, doklady chybí, přeplatek, VS zálohové faktury)', async () => {
  const p = await parity('motorka', { tables: () => ({ bookings: [booking()] }), fio: st([fioTx(10, 3000, { vs: '10000123' }), fioTx(11, -99)]) })
  eq(p.tables.fio_transactions.map((t: Row) => [t.fio_id, t.status, Object.keys(t).sort().join(',')]), [
    [10, 'confirmed_booking', 'amount,booking_id,counter_account,counter_bank,counter_name,currency,fio_id,id,message,note,processed_at,status,tx_date,tx_type,vs'],
    [11, 'outgoing', 'amount,counter_account,counter_bank,counter_name,currency,fio_id,id,message,status,tx_date,tx_type,vs']], 'jen dnešní sloupce')
  ok(p.http.some((h: Row) => h.url.endsWith('/send-booking-email')) && p.http.filter((h: Row) => h.url.endsWith('/generate-invoice')).length === 2, 'doklady + mail')
  await parity('výbava', { tables: () => ({ bookings: [booking({ moto_id: null, booking_kind: 'gear', motorcycles: null, language: 'de' })] }), fio: st([fioTx(12, 3000, { vs: '10000123' })]) })
  await parity('doklady chybí', { tables: () => ({ bookings: [booking({ docs_completed_at: null })] }), fio: st([fioTx(13, 3000, { vs: '10000123' })]),
    setup: (db) => { db.rpcs.check_booking_docs_status = () => ({ data: 'missing_license', error: null }) } })
  const o = await parity('přeplatek', { tables: () => ({ bookings: [booking()] }), fio: st([fioTx(14, 3100.5, { vs: '10000123' })]) })
  eq(o.tables.fio_transactions[0].note, 'přeplatek: přišlo 3100.50, cena 3000.00 Kč')
  await parity('VS faktury', { tables: () => ({ bookings: [booking({ payment_vs: null })], invoices: [{ booking_id: BID, order_id: null, type: 'proforma', status: 'issued', variable_symbol: '20260204' }] }),
    fio: st([fioTx(15, 3000, { vs: '20260204' })]) })
})

T('parita: doplatek z Velínu (zaplacen, přeplatek, nedoplatek, už potvrzen, ke zrušené rezervaci)', async () => {
  const sur = (o: Row = {}) => booking({ status: 'reserved', payment_status: 'paid', payment_method: 'card', payment_vs: '10000001', mod_surcharge_due: 400, mod_surcharge_vs: '10000300', ...o })
  for (const [name, b, amount] of [['zaplacen', sur(), 400], ['přeplatek', sur(), 450], ['nedoplatek', sur(), 399], ['už potvrzen', sur({ mod_surcharge_due: 0 }), 400], ['zrušená', sur({ status: 'cancelled' }), 400]] as Array<[string, Row, number]>) {
    await parity('doplatek ' + name, { tables: () => ({ bookings: [{ ...b }] }), fio: st([fioTx(20, amount, { vs: '10000300' })]) })
  }
})

T('parita: co se dnes NEpotvrzuje, se nepotvrdí ani nově (nedoplatky se nesčítají, zrušená se neobnovuje, duplicita tiše, objednávky se nepárují)', async () => {
  const two = await parity('2× nedoplatek', { tables: () => ({ bookings: [booking()] }), fio: st([fioTx(30, 1500, { vs: '10000123' }), fioTx(31, 1500, { vs: '10000123' })]) })
  eq([two.tables.fio_transactions.map((t: Row) => t.status), two.rpcs.filter((r: Row) => r.fn === 'confirm_payment').length], [['amount_mismatch', 'amount_mismatch'], 0])
  const late = await parity('po auto-zrušení', { tables: () => ({ bookings: [booking({ status: 'cancelled', cancelled_by_source: 'auto' })] }), fio: st([fioTx(32, 3000, { vs: '10000123' })]) })
  eq([late.tables.fio_transactions[0].status, late.rpcs.length, late.tables.bookings[0].status], ['needs_review', 0, 'cancelled'])
  const dup = await parity('už zaplacená kartou', { tables: () => ({ bookings: [booking({ status: 'reserved', payment_status: 'paid', payment_method: 'card' })] }), fio: st([fioTx(33, 3000, { vs: '10000123' })]) })
  eq([dup.tables.fio_transactions[0].status, dup.http.length], ['already_paid', 1], 'jen dotaz na banku, žádný e-mail')
  const shop = await parity('objednávka dle VS faktury / požadavku', { tables: () => ({ shop_orders: [order()], bank_payment_requests: [request()],
    invoices: [{ booking_id: null, order_id: OID, type: 'shop_proforma', status: 'issued', variable_symbol: '20260300' }] }),
    fio: st([fioTx(34, 1000, { vs: '20260300' }), fioTx(35, 1000, { vs: '10000200' })]) })
  eq([shop.tables.fio_transactions.map((t: Row) => t.status), shop.tables.shop_orders[0].payment_status, shop.rpcs], [['no_match', 'no_match'], 'pending', []])
  await parity('bez VS / špatný VS / cizí měna / VS s nulami', { tables: () => ({ bookings: [booking()] }),
    fio: st([fioTx(36, 3000), fioTx(37, 12), fioTx(38, 3000, { vs: '99' }), fioTx(39, 100, { vs: '10000123', currency: 'EUR' }), fioTx(40, 3000, { vs: '0010000123' })]) })
})

T('parita: chyby potvrzení (RPC chyba, success:false, souběh, výjimka), selhání zápisu pohybů, dávka 50 starších pohybů', async () => {
  const one = (setup: (db: BankDb) => void) => ({ tables: () => ({ bookings: [booking()] }), fio: st([fioTx(50, 3000, { vs: '10000123' })]), setup })
  const e1 = await parity('RPC chyba', one((db) => { db.rpcs.confirm_payment = () => ({ data: null, error: { message: 'timeout' } }) }))
  eq([e1.tables.fio_transactions[0].status, e1.tables.fio_transactions[0].note, e1.body.errors], ['error', 'confirm_payment: timeout', 1])
  await parity('success:false', one((db) => { db.rpcs.confirm_payment = () => ({ data: { success: false, error: 'forbidden' }, error: null }) }))
  await parity('souběh', one((db) => { db.rpcs.confirm_payment = () => ({ data: { success: true, was_already_paid: true }, error: null }) }))
  const e4 = await parity('výjimka', one((db) => { db.rpcs.confirm_payment = () => { throw new Error('boom') } }))
  eq([e4.tables.fio_transactions[0].status, e4.tables.fio_transactions[0].note], ['error', 'boom'])
  await parity('doplatek RPC chyba', { tables: () => ({ bookings: [booking({ status: 'reserved', payment_status: 'paid', mod_surcharge_due: 400, mod_surcharge_vs: '10000300' })] }),
    fio: st([fioTx(51, 400, { vs: '10000300' })]), setup: (db) => { db.rpcs.confirm_booking_surcharge = () => ({ data: { success: false, error: 'no_surcharge_pending' }, error: null }) } })
  const ins = await parity('zápis pohybů selže', { fio: st([fioTx(52, 100)]), setup: (db) => { db.failUpsert = () => ({ message: 'disk full' }) } })
  eq([ins.body, ins.tables.debug_log.map((d: Row) => d.action)], [{ success: false, error: 'insert_failed' }, ['fio_tx_insert_failed']])
  const many = await parity('55 starších pohybů', { tables: () => ({ fio_transactions: Array.from({ length: 55 }, (_, i) => txRow(100 + i, 10)) }), fio: st([]) })
  eq([many.body.no_match, many.tables.fio_transactions.filter((t: Row) => t.status === 'new').length], [50, 5])
})
