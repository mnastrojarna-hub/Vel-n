// ===== _tests/fio_sync_flow_test.ts =====
// Fio synchronizace s NASAZENÝM SQL 20261130a1/b (emulace RPC v bank-helpers.ts): rozcestník podle VS,
// každý druh platby jde svou potvrzovací rutinou právě jednou; nedoplatek / přeplatek / duplicita /
// špatný VS / pozdní platba / prošlý požadavek; zámek běhu, limit banky, chyby banky.
// Spuštění: deno test --allow-all --no-check --import-map=supabase/functions/_tests/storno-flow-map.json supabase/functions/_tests/fio_sync_flow_test.ts
// (funguje i s gear-flow-map.json; bez import mapy se přeskočí).
// deno-lint-ignore-file no-explicit-any
import { type BankDb, BID, booking, clock, edgeCalls, eq, fioCalls, fioTx, FN, MAPPED, now, OID, ok, opsSubjects, order, request, RID, type Row, SB, statement, SVC, tx, txRow } from './bank-helpers.ts'
import { world } from './bank-world.ts'

const run: any = MAPPED ? await import(`${FN}fio-sync/run.ts`) : null
const T = (name: string, fn: () => Promise<void>) => Deno.test({ name, ignore: !MAPPED, sanitizeOps: false, sanitizeResources: false, fn })

const sync = (db: BankDb, o: Row = {}) => run.runSync(db, { token: 'tok', env: { url: SB, key: SVC, now }, ...o })
const rpcs = (db: BankDb, fn: string) => db.callsOf('rpc', fn)
const give = (w: { n: any }, txs: unknown[]) => w.n.fio.push(() => new Response(statement(txs), { status: 200 }))

T('prázdný výpis: žádný řádek debug_log, žádný e-mail, běh zapsán jako úspěšný a zámek uvolněn', async () => {
  const w = world()
  try {
    const r = await sync(w.db)
    eq(r.body, { success: true, mode: 'last', fetched: 0, processed: 0, confirmed: 0, surcharge: 0, orders: 0, changes: 0, no_match: 0, mismatch: 0, review: 0, errors: 0 })
    eq(w.db.rows('debug_log').length, 0, 'debug_log')
    eq(w.n.mails.length, 0, 'mails')
    eq(w.st.ends.length, 1); eq(w.st.ends[0].p_ok, true); eq(w.st.ends[0].p_info.iban, 'CZ8320100000002303580494')
    eq(w.st.lease_until, null)
    ok(fioCalls(w.n)[0].url.endsWith('/last/tok/transactions.json'), 'last endpoint')
  } finally { w.n.restore() }
})

T('rezervace: VS sedí → confirm_payment(bank_transfer) právě jednou, ZF+DP, mail, zpráva, audit, pohyb confirmed_booking', async () => {
  const w = world({ bookings: [booking()] })
  try {
    give(w, [fioTx(501, 3000, { vs: '10000123' }), fioTx(502, -250, {})])
    const r = await sync(w.db)
    eq([r.body.fetched, r.body.confirmed, r.body.processed], [2, 1, 1])
    eq(rpcs(w.db, 'confirm_payment').map((c) => c.data), [{ p_booking_id: BID, p_method: 'bank_transfer' }])
    eq(edgeCalls(w.n, 'generate-invoice').map((c) => c.body?.type), ['advance', 'payment_receipt'])
    eq(edgeCalls(w.n, 'send-booking-email').map((c) => c.body?.type), ['booking_reserved'])
    const t = tx(w.db, 501)
    eq([t.status, t.booking_id, t.target_type, t.reason_code, t.expected_amount, t.followup, t.claimed_until], ['confirmed_booking', BID, 'booking', null, 3000, null, null])
    ok(t.raw?.column22?.value === 501, 'raw uložen')
    eq(tx(w.db, 502).status, 'outgoing')
    eq(w.db.rows('bookings')[0].payment_reference, 'FIO 501')
    eq(w.db.rows('messages').length, 1)
    eq(w.db.rows('admin_audit_log').map((a) => a.action), ['booking_payment_confirmed_fio'])
    ok(opsSubjects(w.n)[0].startsWith('✅ Fio: platba VS 10000123'), opsSubjects(w.n)[0])
  } finally { w.n.restore() }
})

T('výpůjčka jen výbavy: stejná rutina, zpráva v jazyce zákazníka', async () => {
  const w = world({ bookings: [booking({ moto_id: null, booking_kind: 'gear', motorcycles: null, language: 'en' })] })
  try {
    give(w, [fioTx(503, 3000, { vs: '0010000123' })]) // banka doplnila VS nulami
    await sync(w.db)
    eq(tx(w.db, 503).status, 'confirmed_booking')
    ok(String(w.db.rows('messages')[0].content).startsWith('Your gear rental #'), w.db.rows('messages')[0].content)
  } finally { w.n.restore() }
})

T('doplatek z Velínu a VS zálohové faktury rezervace: confirm_booking_surcharge / confirm_payment právě jednou', async () => {
  const B2 = '22222222-2222-4333-8444-555555555555'
  const w = world({ bookings: [booking({ status: 'reserved', payment_status: 'paid', payment_method: 'card', mod_surcharge_due: 400, mod_surcharge_vs: '10000300' }),
    booking({ id: B2, payment_vs: null, pay_channel: null })], invoices: [{ id: 'i1', booking_id: B2, order_id: null, type: 'proforma', status: 'issued', variable_symbol: '20260204' }] })
  try {
    give(w, [fioTx(510, 400, { vs: '10000300' }), fioTx(511, 3000, { vs: '20260204' })])
    const r = await sync(w.db)
    eq([r.body.surcharge, r.body.confirmed], [1, 1])
    eq(rpcs(w.db, 'confirm_booking_surcharge').length, 1)
    eq(rpcs(w.db, 'confirm_booking_surcharge')[0].data, { p_booking_id: BID, p_method: 'bank_transfer', p_vs: '10000300', p_paid_date: '2026-12-01', p_transaction_ref: 'FIO 510' })
    eq([tx(w.db, 510).status, tx(w.db, 510).target_type], ['confirmed_surcharge', 'surcharge'])
    eq([tx(w.db, 511).status, tx(w.db, 511).booking_id], ['confirmed_booking', B2])
  } finally { w.n.restore() }
})

T('dárkový poukaz (požadavek na platbu): confirm_shop_payment(bank_transfer) jednou, požadavek zaplacen, poukaz e-mailem až teď', async () => {
  const w = world({ shop_orders: [order()], bank_payment_requests: [request()] })
  try {
    eq(w.db.rows('vouchers').length, 0, 'před platbou žádný poukaz')
    give(w, [fioTx(520, 1000, { vs: '10000200', name: 'MALA PETRA' })])
    const r = await sync(w.db)
    eq(r.body.orders, 1)
    eq(rpcs(w.db, 'confirm_shop_payment').map((c) => c.data), [{ p_order_id: OID, p_method: 'bank_transfer' }])
    const t = tx(w.db, 520)
    eq([t.status, t.order_id, t.request_id, t.target_type], ['confirmed_order', OID, RID, 'order'])
    const rq = w.db.rows('bank_payment_requests')[0]
    eq([rq.status, rq.fio_id], ['paid', 520])
    eq(edgeCalls(w.n, 'send-booking-email').map((c) => [c.body?.type, c.body?.voucher_code]), [['voucher_purchased', 'MG-TEST-1 (1000 Kč)']])
    ok(opsSubjects(w.n)[0].includes('MG-2026-0042'), opsSubjects(w.n)[0])
  } finally { w.n.restore() }
})

T('objednávka e-shopu zaplacená převodem na VS zálohové faktury (bez požadavku) se spáruje', async () => {
  const w = world({ shop_orders: [order({ payment_method: 'stripe', notes: null })], invoices: [{ id: 'i2', booking_id: null, order_id: OID, type: 'shop_proforma', status: 'issued', variable_symbol: '20260300' }] })
  try {
    give(w, [fioTx(521, 1000, { vs: '20260300' })])
    await sync(w.db)
    eq([tx(w.db, 521).status, tx(w.db, 521).order_id, tx(w.db, 521).request_id], ['confirmed_order', OID, null])
    eq(w.db.rows('shop_orders')[0].payment_method, 'bank_transfer')
  } finally { w.n.restore() }
})

T('prošlá objednávka poukazu (7 dní) zaplacená později se přesto potvrdí', async () => {
  const w = world({ shop_orders: [order()], bank_payment_requests: [request({ status: 'expired', expires_at: '2026-11-20T08:00:00Z' })] })
  try {
    give(w, [fioTx(522, 1000, { vs: '10000200' })])
    await sync(w.db)
    eq(tx(w.db, 522).status, 'confirmed_order')
    eq(w.db.rows('bank_payment_requests')[0].status, 'paid')
  } finally { w.n.restore() }
})

T('nedoplatek: nepotvrdí se + e-mail; druhá platba se stejným VS se přičte a potvrdí obě', async () => {
  const w = world({ bookings: [booking()] })
  try {
    give(w, [fioTx(530, 2000, { vs: '10000123' })])
    await sync(w.db)
    eq([tx(w.db, 530).status, tx(w.db, 530).reason_code, tx(w.db, 530).expected_amount], ['amount_mismatch', 'underpaid', 3000])
    eq(rpcs(w.db, 'confirm_payment').length, 0)
    ok(opsSubjects(w.n)[0].includes('NIŽŠÍ'), opsSubjects(w.n)[0])
    clock.t += 60_000
    give(w, [fioTx(531, 1000, { vs: '10000123' })])
    await sync(w.db)
    eq(rpcs(w.db, 'confirm_payment').length, 1)
    eq([tx(w.db, 531).status, tx(w.db, 531).reason_code], ['confirmed_booking', null])
    eq([tx(w.db, 530).status, tx(w.db, 530).reason_code], ['confirmed_booking', 'partial_sum'])
  } finally { w.n.restore() }
})

T('přeplatek: potvrdí se, úkol „vrátit přeplatek“ zůstává otevřený (followup) a obsluha dostane e-mail', async () => {
  const w = world({ bookings: [booking()] })
  try {
    give(w, [fioTx(532, 3500, { vs: '10000123' })])
    await sync(w.db)
    const t = tx(w.db, 532)
    eq([t.status, t.reason_code, t.followup, t.expected_amount], ['confirmed_booking', 'overpaid', 'overpaid', 3000])
    ok(String(w.n.mails[w.n.mails.length - 1].raw_html).includes('přeplatek vraťte'), 'mail o přeplatku')
  } finally { w.n.restore() }
})

T('duplicita: druhá platba téhož VS jde obsluze s e-mailem; ručně potvrzená rezervace zůstává already_paid bez e-mailu', async () => {
  const w = world({ bookings: [booking()] })
  try {
    give(w, [fioTx(540, 3000, { vs: '10000123' })])
    await sync(w.db)
    const before = w.n.mails.length
    clock.t += 60_000
    give(w, [fioTx(541, 3000, { vs: '10000123' })])
    await sync(w.db)
    eq([tx(w.db, 541).status, tx(w.db, 541).reason_code], ['needs_review', 'duplicate'])
    eq(rpcs(w.db, 'confirm_payment').length, 1, 'žádné druhé potvrzení')
    ok(opsSubjects(w.n).slice(before).some((s) => s.includes('duplicitní platba')), 'e-mail o duplicitě')
  } finally { w.n.restore() }
  const w2 = world({ bookings: [booking({ status: 'reserved', payment_status: 'paid', payment_method: 'bank_transfer' })] })
  try {
    give(w2, [fioTx(542, 3000, { vs: '10000123' })])
    await sync(w2.db)
    eq([tx(w2.db, 542).status, w2.n.mails.length], ['already_paid', 0])
  } finally { w2.n.restore() }
  // zaplaceno KARTOU a pak ještě převodem = duplicita
  const w3 = world({ bookings: [booking({ status: 'reserved', payment_status: 'paid', payment_method: 'card' })] })
  try {
    give(w3, [fioTx(543, 3000, { vs: '10000123' })])
    await sync(w3.db)
    eq([tx(w3.db, 543).status, tx(w3.db, 543).reason_code], ['needs_review', 'duplicate'])
  } finally { w3.n.restore() }
})

T('bez VS / špatný VS / cizí měna: NIKDY se nepotvrdí — no_match s důvodem; drobná částka bez VS bez e-mailu', async () => {
  const w = world({ bookings: [booking()] })
  try {
    give(w, [fioTx(550, 3000, {}), fioTx(551, 3000, { vs: '10000999' }), fioTx(552, 12.5, {}), fioTx(553, 120, { vs: '10000123', currency: 'EUR' })])
    const r = await sync(w.db)
    eq(r.body.no_match, 4)
    eq([550, 551, 552, 553].map((i) => [tx(w.db, i).status, tx(w.db, i).reason_code]), [['no_match', 'no_vs'], ['no_match', 'vs_not_found'], ['no_match', 'no_vs'], ['no_match', 'foreign_currency']])
    eq(rpcs(w.db, 'confirm_payment').length, 0)
    eq(w.db.rows('bookings')[0].payment_status, 'unpaid')
    eq(w.n.mails.length, 3, 'e-mail za 550, 551, 553 — ne za 12,50 Kč bez VS')
  } finally { w.n.restore() }
})

T('pozdní platba po automatickém zrušení: termín volný → rezervace obnovena a potvrzena; obsazený → obsluha, nic se nepotvrdí', async () => {
  const cancelled = { status: 'cancelled', cancelled_by_source: 'auto' }
  const w = world({ bookings: [booking(cancelled)] })
  try {
    give(w, [fioTx(560, 3000, { vs: '10000123' })])
    await sync(w.db)
    eq([tx(w.db, 560).status, tx(w.db, 560).reason_code], ['confirmed_booking', 'late_revived'])
    eq([w.db.rows('bookings')[0].status, w.db.rows('bookings')[0].payment_status], ['reserved', 'paid'])
    eq(edgeCalls(w.n, 'send-booking-email').length, 1)
  } finally { w.n.restore() }
  const w2 = world({ bookings: [booking(cancelled)] })
  try {
    w2.flags.taken = true
    give(w2, [fioTx(561, 3000, { vs: '10000123' })])
    await sync(w2.db)
    eq([tx(w2.db, 561).status, tx(w2.db, 561).reason_code], ['needs_review', 'late_cancelled'])
    eq([w2.db.rows('bookings')[0].status, w2.db.rows('bookings')[0].payment_status], ['cancelled', 'unpaid'])
    eq(edgeCalls(w2.n, 'send-booking-email').length + edgeCalls(w2.n, 'generate-invoice').length, 0, 'žádné doklady ani mail zákazníkovi')
    ok(opsSubjects(w2.n)[0].includes('termín už není volný'), opsSubjects(w2.n)[0])
  } finally { w2.n.restore() }
  // zrušil ji zákazník / obsluha → neobnovovat automaticky
  const w3 = world({ bookings: [booking({ status: 'cancelled', cancelled_by_source: 'customer' })] })
  try {
    give(w3, [fioTx(562, 3000, { vs: '10000123' })])
    await sync(w3.db)
    eq([tx(w3.db, 562).status, tx(w3.db, 562).reason_code, rpcs(w3.db, 'confirm_payment').length], ['needs_review', 'target_closed', 0])
  } finally { w3.n.restore() }
})

T('zámek běhu: druhý běh během prvního se na banku vůbec neptá (skipped busy)', async () => {
  const w = world({ bookings: [booking()] })
  try {
    w.st.lease_until = new Date(now() + 120_000).toISOString()
    const r = await sync(w.db)
    eq(r.body, { success: true, skipped: 'busy' })
    eq(fioCalls(w.n).length, 0)
    clock.t += 121_000 // zámek po pádu běhu sám vyprší
    eq((await sync(w.db)).body.success, true)
    eq(fioCalls(w.n).length, 1)
  } finally { w.n.restore() }
})

T('limit banky 409: není to chyba (rate_limited), fronta se přesto zpracuje; HTTP 500: chyba běhu se stavem pro upozornění', async () => {
  const w = world({ bookings: [booking()], fio_transactions: [txRow(570, 3000, { vs: '10000123' })] })
  try {
    w.n.fio.push(() => new Response('', { status: 409 }))
    const r = await sync(w.db)
    eq([r.body.success, r.body.skipped, r.body.confirmed], [true, 'rate_limited', 1])
    eq([w.st.ends[0].p_ok, w.st.ends[0].p_error, w.st.ends[0].p_http], [null, 'rate_limited', 409])
    eq(w.st.consecutive_failures, 0)
    clock.t += 60_000
    w.n.fio.push(() => new Response('Internal Server Error', { status: 500 }))
    const r2 = await sync(w.db)
    eq([r2.body.success, r2.body.error], [false, 'fio_http_500'])
    eq([w.st.ends[1].p_ok, w.st.ends[1].p_error, w.st.ends[1].p_http, w.st.consecutive_failures], [false, 'fio_http_500', 500, 1])
    eq(w.db.rows('debug_log').filter((d) => d.action === 'fio_fetch_failed').length, 0, 'selhání neloguje edge funkce každým během (stav hlídá SQL)')
  } finally { w.n.restore() }
})

T('chybějící token: ručně spárované pohyby se zpracují, selhání jde do stavu (ne do debug_log každým během)', async () => {
  const w = world({ bookings: [booking()], fio_transactions: [txRow(571, 3000, { manual_target_type: 'booking', manual_target_id: BID })] })
  try {
    const r = await sync(w.db, { token: '' })
    eq([r.body.success, r.body.error, r.body.confirmed], [false, 'missing_fio_token', 1])
    eq(fioCalls(w.n).length, 0)
    eq(w.st.ends[0].p_error, 'missing_fio_token')
    eq(w.db.rows('debug_log').filter((d) => d.action === 'missing_fio_token').length, 0)
    eq([tx(w.db, 571).status, tx(w.db, 571).reason_code], ['confirmed_booking', 'manual'])
  } finally { w.n.restore() }
})

T('omezená dávka: 13 čekajících pohybů → 10 v tomto běhu, zbytek v dalším', async () => {
  const w = world({ fio_transactions: Array.from({ length: 13 }, (_, i) => txRow(600 + i, 20, {})) })
  try {
    eq((await sync(w.db)).body.processed, 10)
    eq(w.db.rows('fio_transactions').filter((t) => t.status === 'new').length, 3)
    clock.t += 60_000
    eq((await sync(w.db)).body.processed, 3)
  } finally { w.n.restore() }
})

T('chyba zpracování: pohyb zůstane ve frontě a zkouší se znovu; po 30 minutách jde obsluze s e-mailem; starý řádek „error“ se zkusí znovu', async () => {
  const w = world({ bookings: [booking()], fio_transactions: [txRow(580, 3000, { vs: '10000123', status: 'error', note: 'stará chyba' })] })
  try {
    w.flags.confirmFails = true
    await sync(w.db)
    let t = tx(w.db, 580)
    eq([t.status, t.attempts, !!t.first_error_at, Date.parse(t.claimed_until) > now()], ['new', 1, true, true])
    eq(w.db.rows('debug_log').filter((d) => d.action === 'tx_processing_failed').length, 1)
    for (let i = 0; i < 3; i++) { clock.t += 60_000; await sync(w.db) }
    eq(tx(w.db, 580).attempts, 4)
    eq(w.db.rows('debug_log').filter((d) => d.action === 'tx_processing_failed').length, 1, 'log jen při první chybě')
    eq(w.n.mails.length, 0)
    clock.t += 31 * 60_000
    await sync(w.db)
    t = tx(w.db, 580)
    eq([t.status, t.reason_code], ['needs_review', 'processing_error'])
    ok(opsSubjects(w.n)[0].includes('opakovaně selhalo'), opsSubjects(w.n)[0])
    // po opravě: vrácení ke zpracování (admin_fio_reopen_transaction) → potvrdí se
    w.flags.confirmFails = false
    Object.assign(t, { status: 'new', attempts: 0, first_error_at: null, claimed_until: null })
    clock.t += 60_000
    await sync(w.db)
    eq(tx(w.db, 580).status, 'confirmed_booking')
  } finally { w.n.restore() }
})

T('ruční spárování: nižší částku potvrdí jen s výslovným přijetím; běží stejná rutina jako automatika', async () => {
  const w = world({ bookings: [booking()], fio_transactions: [txRow(590, 2900, { manual_target_type: 'booking', manual_target_id: BID })] })
  try {
    eq((await run.processOne(w.db, { url: SB, key: SVC, now }, 590)).result.status, 'amount_mismatch')
    eq(rpcs(w.db, 'confirm_payment').length, 0)
    Object.assign(tx(w.db, 590), { status: 'new', manual_accept_amount: true, claimed_until: null })
    const r = await run.processOne(w.db, { url: SB, key: SVC, now }, 590)
    eq([r.result.status, r.result.reason_code], ['confirmed_booking', 'accepted_lower'])
    eq(rpcs(w.db, 'confirm_payment').length, 1)
    eq(edgeCalls(w.n, 'send-booking-email').length, 1)
    eq((await run.processOne(w.db, { url: SB, key: SVC, now }, 590)).error, 'not_pending')
    eq((await run.processOne(w.db, { url: SB, key: SVC, now }, 999)).error, 'not_found')
  } finally { w.n.restore() }
})
