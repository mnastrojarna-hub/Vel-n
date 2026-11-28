// ===== _tests/fio_suggest_test.ts =====
// Návrhy spárování pro platbu bez / se špatným VS (zadání majitele 2026-11-27): jen čekající platby
// s PŘESNĚ stejnou částkou, pořadí podle podobnosti (jméno plátce × zákazník, zpráva, překlep ve VS,
// účet plátce), u každého návrhu důvody česky. Nic se nepotvrzuje. Běží i bez import mapy.
// deno-lint-ignore-file no-explicit-any
import { BankDb, BID, booking, eq, OID, ok, order, request, RID, txRow } from './bank-helpers.ts'
import { type Candidate, loadWaiting, nameMatch, norm, rankCandidates, suggestFor, vsNear } from '../fio-sync/suggest.ts'

const cand = (o: Partial<Candidate>): Candidate => ({ target_type: 'booking', target_id: 'b', kind: 'booking', label: 'Rezervace #AAAA1111', number: 'AAAA1111',
  booking_id: 'b', order_id: null, request_id: null, amount: 1500, vs: '10000123', customer_name: 'Jan Novák', customer_email: 'jan@example.com',
  state: 'waiting', created_at: '2026-12-01T08:00:00Z', expires_at: null, user_id: 'u1', ...o })
const mv = (o: any = {}) => ({ fio_id: 1, amount: 1500, vs: null, counter_name: null, counter_account: null, message: null, ...o })

Deno.test('normalizace a shoda jmen: diakritika, pořadí, tituly; shoda jen příjmení = částečná', () => {
  eq(norm('  Ing. Jiří ŠŤASTNÝ-Novák '), 'ing jiri stastny novak')
  eq(nameMatch('NOVAK JAN', 'Jan Novák').kind, 'full')
  eq(nameMatch('Ing. Jan Novák, Ph.D.', 'novák jan').kind, 'full')
  eq(nameMatch('NOVAKOVA JANA', 'Jan Novák').kind, null)
  eq(nameMatch('NOVAK PETR', 'Jan Novák'), { kind: 'partial', hit: ['novak'] })
  eq(nameMatch('JAN NOVAK', 'Jan Karel Novák').kind, 'full') // všechna slova plátce jsou ve jménu zákazníka
  eq(nameMatch('', 'Jan Novák').kind, null)
  eq(nameMatch('MOTO SERVIS SRO', 'Li Wu').kind, null) // dvoupísmenná shoda nestačí
})

Deno.test('překlep ve VS: jedna číslice, prohozené sousední, chybějící / přebývající; víc rozdílů ne', () => {
  ok(vsNear('10000128', '10000123')); ok(vsNear('10000132', '10000123')); ok(vsNear('1000123', '10000123')); ok(vsNear('100001233', '10000123'))
  ok(!vsNear('10000123', '10000123')); ok(!vsNear('10000199', '10000123')); ok(!vsNear('', '10000123')); ok(!vsNear('123', '10000123'))
})

Deno.test('pořadí návrhů: jméno + překlep VS > jméno > překlep VS > jen částka; jiná částka se nenabízí nikdy', () => {
  const all = [
    cand({ target_id: 'only-amount', customer_name: 'Eva Dvořáková', vs: '10000777', number: 'CCCC3333', user_id: 'u3' }),
    cand({ target_id: 'vs-typo', customer_name: 'Petr Svoboda', vs: '10000128', number: 'BBBB2222', user_id: 'u2' }),
    cand({ target_id: 'name', vs: '10000555' }),
    cand({ target_id: 'name+vs', vs: '10000129', number: 'DDDD4444' }),
    cand({ target_id: 'other-amount', amount: 1500.01 }),
    cand({ target_id: 'other-amount-2', amount: 1499 }),
  ]
  const r = rankCandidates(mv({ vs: '10000123', counter_name: 'NOVAK JAN' }), all)
  eq(r.map((c) => c.target_id), ['name+vs', 'name', 'vs-typo', 'only-amount'])
  eq(r.map((c) => c.confidence), ['high', 'high', 'medium', 'low'])
  eq(r[3].reasons, ['Stejná částka 1 500,00 Kč'])
  ok(r[0].reasons.some((x) => x.includes('„NOVAK JAN“ odpovídá zákazníkovi Jan Novák')) && r[0].reasons.some((x) => x.includes('10000123 × 10000129')), JSON.stringify(r[0].reasons))
  ok(!('user_id' in r[0]), 'interní user_id se nevrací')
})

Deno.test('zpráva pro příjemce: číslo rezervace / objednávky, e-mail, jméno, VS; účet, ze kterého zákazník už platil; stav', () => {
  const all = [
    cand({ target_id: 'num' , customer_name: 'X Y', number: 'AB12CD34', vs: null }),
    cand({ target_id: 'mail', customer_name: 'Q W', customer_email: 'karel@firma.cz', vs: null, number: 'EEEE5555' }),
    cand({ target_id: 'acct', customer_name: 'R T', vs: null, number: 'FFFF6666', user_id: 'payer' }),
    cand({ target_id: 'late', customer_name: 'Z U', vs: '10000900', number: 'GGGG7777', state: 'cancelled' }),
    cand({ target_type: 'order', target_id: 'ord', kind: 'voucher', label: 'Dárkový poukaz MG-2026-0042', number: 'MG-2026-0042', customer_name: 'Petra Malá', vs: '10000200', booking_id: null, order_id: 'ord' }),
  ]
  const top = (m: any) => rankCandidates(m, all, new Set(['payer']))[0]
  eq(top(mv({ message: 'platba rezervace ab12cd34 dekuji' })).target_id, 'num')
  eq(top(mv({ message: 'Karel@Firma.cz moto' })).target_id, 'mail')
  eq(top(mv({ message: 'poukaz mg-2026-0042' })).target_id, 'ord')
  eq(top(mv({ message: 'VS10000900' })).target_id, 'late')
  ok(top(mv({ message: 'VS10000900' })).reasons.some((x) => x.startsWith('Pozor: rezervace byla mezitím automaticky zrušena')), 'upozornění na zrušení')
  eq(top(mv({ message: 'darek pro Petru', counter_name: 'MALA PETRA' })).target_id, 'ord')
  const acct = rankCandidates(mv({ counter_name: 'FIRMA SRO', counter_account: '111' }), all, new Set(['payer']))
  eq([acct[0].target_id, acct[0].confidence], ['acct', 'medium'])
  ok(acct[0].reasons.includes('Z tohoto účtu už zákazník dříve platil'))
  eq(rankCandidates(mv({ amount: 9999 }), all), [], 'žádná shoda částky = prázdný seznam')
})

Deno.test('načtení čekajících plateb a návrh z DB: rezervace, doplatek, úprava z webu, poukaz, objednávka dle ZF; nic se nemění', async () => {
  const B2 = '22222222-2222-4333-8444-555555555555', B3 = '33333333-2222-4333-8444-555555555555', O2 = '88888888-2222-4333-8444-555555555555'
  const db = new BankDb({
    bookings: [booking({ total_price: 1000 }),
      booking({ id: B2, status: 'reserved', payment_status: 'paid', payment_vs: null, mod_surcharge_due: 1000, mod_surcharge_vs: '10000300', profiles: { full_name: 'Karel Bílý', email: 'k@example.com' } }),
      booking({ id: B3, status: 'cancelled', cancelled_by_source: 'auto', cancelled_at: '2026-11-30T10:00:00Z', payment_vs: '10000124', total_price: 1000, profiles: { full_name: 'Late Payer', email: 'l@example.com' } })],
    shop_orders: [order(), order({ id: O2, order_number: 'MG-2026-0050', payment_method: 'stripe', notes: null, customer_name: 'Olga Tichá' })],
    bank_payment_requests: [request(), request({ id: 'rq-change', kind: 'booking_change', vs: '10000400', amount: 1000, booking_id: B2, order_id: null })],
    invoices: [{ order_id: O2, variable_symbol: '20260300', type: 'shop_proforma', status: 'issued' }],
    fio_transactions: [txRow(900, 1000, { status: 'no_match', counter_name: 'MALA PETRA', vs: '10000201' }), txRow(901, 1000, { status: 'confirmed_booking', booking_id: BID, counter_account: '555' })],
  })
  const now = Date.parse('2026-12-01T10:00:00Z')
  const narrow = await loadWaiting(db, { wide: false, now })
  eq(narrow.map((c) => [c.kind, c.target_type, c.state]).sort(), [['booking', 'booking', 'waiting'], ['booking_change', 'request', 'waiting'], ['surcharge', 'surcharge', 'waiting'], ['voucher', 'order', 'waiting']])
  const wide = await loadWaiting(db, { wide: true, now })
  eq(wide.filter((c) => c.state === 'cancelled').map((c) => c.target_id), [B3])
  eq(wide.filter((c) => c.kind === 'shop_order').map((c) => [c.target_id, c.vs, c.request_id]), [[O2, '20260300', null]])
  const before = JSON.stringify(db.tables)
  const s: any = await suggestFor(db, 900, 8, now)
  eq(s.success, true)
  eq([s.candidates[0].target_type, s.candidates[0].target_id, s.candidates[0].request_id, s.candidates[0].confidence], ['order', OID, RID, 'high'])
  eq(s.candidates.length, 6)
  eq(JSON.stringify(db.tables), before, 'návrh nic nezapisuje')
  eq(db.callsOf('rpc').length, 0, 'žádné potvrzovací RPC')
  eq(((await suggestFor(db, 12345)) as any).error, 'not_found')
  // z účtu 555 už zákazník platil rezervaci BID (pohyb 901) → jeho další čekající platby dostanou důvod navíc
  db.rows('fio_transactions').push(txRow(902, 1000, { status: 'no_match', counter_account: '555', counter_name: 'FIRMA SRO' }))
  const s2: any = await suggestFor(db, 902, 8, now)
  ok(s2.candidates.find((c: any) => c.target_id === B2).reasons.includes('Z tohoto účtu už zákazník dříve platil'), 'historie účtu')
  ok(!s2.candidates.find((c: any) => c.target_id === OID).reasons.includes('Z tohoto účtu už zákazník dříve platil'), 'jiný zákazník bez důvodu')
})
