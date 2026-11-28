// ===== _tests/fio_recovery_flow_test.ts =====
// Žádný ztracený pohyb: banka při NEPRÁZDNÉ odpovědi na „last“ posune zarážku — když odpověď není platný
// výpis nebo se řádek neuloží, příští „last“ už pohyb nevrátí. Běh se proto hlásí jako neúspěšný
// (recover) a další běh stáhne pohyby za období (periods, nezávislé na zarážce); duplicity přeskočí PK.
// + jednotkové testy čtení odpovědi Fio (běží i bez import mapy).
// deno-lint-ignore-file no-explicit-any
import { booking, clock, eq, fioCalls, fioTx, FN, MAPPED, now, ok, SB, statement, SVC, tx } from './bank-helpers.ts'
import { world } from './bank-world.ts'
import { mapTx, parseStatement, txDate } from '../fio-sync/fio-api.ts'

const run: any = MAPPED ? await import(`${FN}fio-sync/run.ts`) : null
const T = (name: string, fn: () => Promise<void>) => Deno.test({ name, ignore: !MAPPED, sanitizeOps: false, sanitizeResources: false, fn })
const sync = (db: any) => run.runSync(db, { token: 'tok', env: { url: SB, key: SVC, now } })

Deno.test('fio-api: neplatné tělo / chybějící accountStatement není „prázdný výpis“, ale chyba bad_response', () => {
  for (const body of ['<html>503</html>', '', '{}', '{"accountStatement":null}', '{"accountStatement":{"transactionList":{"transaction":"x"}}}']) {
    const r = parseStatement(body)
    eq([r.ok, (r as any).error], [false, 'bad_response'], body)
  }
  const empty = parseStatement(statement([]))
  eq([empty.ok, (empty as any).txs.length, (empty as any).iban, (empty as any).idLastDownload], [true, 0, 'CZ8320100000002303580494', 100])
  const nul = parseStatement(JSON.stringify({ accountStatement: { info: { iban: 'CZ83 2010 0000 0023 0358 0494' }, transactionList: null } }))
  eq([nul.ok, (nul as any).txs.length, (nul as any).iban], [true, 0, 'CZ8320100000002303580494'])
})

Deno.test('fio-api: řádek pohybu — příchozí new / odchozí outgoing, datum epoch i text, surový pohyb jen s novým SQL', () => {
  const t = fioTx(77, 1500.5, { vs: '10000123', msg: 'rezervace' }) as any
  const r = mapTx(t, true)
  eq([r.fio_id, r.amount, r.vs, r.status, r.tx_date, r.message, (r.raw as any).column22.value], [77, 1500.5, '10000123', 'new', '2026-12-01', 'rezervace', 77])
  eq('raw' in mapTx(t, false), false)
  eq(mapTx(fioTx(78, -10) as any, false).status, 'outgoing')
  eq(txDate({ column0: { value: Date.parse('2026-12-01T23:30:00Z') } } as any), '2026-12-02') // Praha
})

T('odpověď banky není JSON: běh selže (recover), nic se nepotvrdí; další běh stáhne období a pohyb dožene', async () => {
  const w = world({ bookings: [booking()] })
  try {
    w.n.fio.push(() => new Response('<html>Bad gateway</html>', { status: 200 }))
    const r = await sync(w.db)
    eq([r.body.success, r.body.error], [false, 'bad_response'])
    eq([w.st.ends[0].p_ok, w.st.ends[0].p_error, w.st.ends[0].p_info.recover], [false, 'bad_response', true])
    ok(w.st.reconcile_since, 'čeká dohledání')
    eq(w.db.rows('fio_transactions').length, 0)
    clock.t += 60_000
    // „last“ by pohyb 801 už nevrátil (zarážka posunutá) — periods ho vrátí
    w.n.fio.push(() => new Response(statement([fioTx(801, 3000, { vs: '10000123' })]), { status: 200 }))
    const r2 = await sync(w.db)
    ok(fioCalls(w.n)[1].url.includes('/periods/tok/2026-11-26/2026-12-01/transactions.json'), fioCalls(w.n)[1].url)
    eq([r2.body.success, r2.body.mode, r2.body.confirmed], [true, 'periods', 1])
    eq(tx(w.db, 801).status, 'confirmed_booking')
    eq(w.db.rows('debug_log').filter((d: any) => d.action === 'reconcile_recovered').map((d: any) => d.request_data.inserted), [1])
    eq([w.st.reconcile_since, w.st.ends[1].p_info.reconciled], [null, true])
    clock.t += 60_000
    await sync(w.db)
    ok(fioCalls(w.n)[2].url.endsWith('/last/tok/transactions.json'), 'pak zase last')
  } finally { w.n.restore() }
})

T('selhání zápisu: hromadný zápis se zopakuje po řádcích; neuložený pohyb = neúspěšný běh a dohledání obdobím, uložené se zpracují hned', async () => {
  const w = world({ bookings: [booking()] })
  try {
    // 1) hromadně to spadne, po jednom projde → běh je v pořádku
    w.db.failUpsert = (rows: any[]) => (rows.length > 1 ? { message: 'statement timeout' } : null)
    w.n.fio.push(() => new Response(statement([fioTx(810, 20), fioTx(811, 30)]), { status: 200 }))
    const r = await sync(w.db)
    eq([r.body.success, w.db.rows('fio_transactions').length, w.st.ends[0].p_ok], [true, 2, true])
    // 2) jeden řádek se neuloží vůbec
    clock.t += 60_000
    w.db.failUpsert = (rows: any[]) => (rows.length > 1 || rows[0].fio_id === 813 ? { message: 'value too long' } : null)
    w.n.fio.push(() => new Response(statement([fioTx(812, 3000, { vs: '10000123' }), fioTx(813, 500, { vs: '555' })]), { status: 200 }))
    const r2 = await sync(w.db)
    eq([r2.body.success, r2.body.error, r2.body.confirmed], [false, 'insert_failed', 1])
    eq([w.st.ends[1].p_ok, w.st.ends[1].p_error, w.st.ends[1].p_info.recover], [false, 'insert_failed', true])
    eq([tx(w.db, 812).status, tx(w.db, 813)], ['confirmed_booking', undefined])
    // 3) další běh: periods vrátí všechno znovu, uloží se jen chybějící 813
    clock.t += 60_000
    w.db.failUpsert = null
    w.n.fio.push(() => new Response(statement([fioTx(810, 20), fioTx(811, 30), fioTx(812, 3000, { vs: '10000123' }), fioTx(813, 500, { vs: '555' })]), { status: 200 }))
    const r3 = await sync(w.db)
    eq([r3.body.mode, r3.body.success, w.db.rows('fio_transactions').length, tx(w.db, 813).status], ['periods', true, 4, 'no_match'])
    eq(w.db.callsOf('rpc', 'confirm_payment').length, 1, 'už potvrzený pohyb se nepotvrzuje znovu')
  } finally { w.n.restore() }
})

T('denní kontrola období najde pohyb, který „last“ nikdy nedoručil', async () => {
  const w = world({ bookings: [booking()] }, { force_daily: true })
  try {
    w.n.fio.push(() => new Response(statement([fioTx(820, 3000, { vs: '10000123' })]), { status: 200 }))
    const r = await sync(w.db)
    eq([r.body.mode, tx(w.db, 820).status, w.st.last_reconcile_on], ['periods', 'confirmed_booking', '2026-12-01'])
    clock.t += 60_000
    eq((await sync(w.db)).body.mode, 'last')
  } finally { w.n.restore() }
})
