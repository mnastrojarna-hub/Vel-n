// ===== _tests/gear_documents_test.ts =====
// EDGE-B (2026-10-23) výpůjčka JEN výbavy: položky ZF/DP (generate-invoice/gear-lines.ts),
// dobropis + spodní mez zákaznické vratky (process-refund/gear.ts), smlouva gear_rental_contract
// a její {{proměnné}} (generate-document/gear-vars.ts).
import { gearDays, gearDaySource, gearInvoiceItems, gearSizesText, isGearBooking } from '../generate-invoice/gear-lines.ts'
import { gearPerDay, gearPriceFloorCzk, loadGearRefundRow, noMotoRefundSubject, refundSubject } from '../process-refund/gear.ts'
import { buildGearVars, GEAR_CONTRACT_SLUG, type PriceRow, resolveDocSlug } from '../generate-document/gear-vars.ts'
import { FakeDb } from './gear-fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }
type Row = Record<string, unknown>

const SET = { key: 'set_rider', kind: 'set', label: 'Komplet bez bot', includes: ['helmet', 'jacket', 'pants', 'gloves'],
  sizes: { helmet: 'M', jacket: 'L', pants: 'L', gloves: 'M' }, price_per_day: 490, total: 1470 }
const BOOTS = { key: 'boots', kind: 'item', label: 'Boty', includes: ['boots'], sizes: { boots: '43' }, price_per_day: 400, total: 1200 }
const gearBk = (o: Row = {}) => ({ id: 'g1', booking_kind: 'gear', moto_id: null, start_date: '2026-11-10T00:00:00+00:00',
  end_date: '2026-11-12T00:00:00+00:00', total_price: 2670, discount_amount: 0, gear_per_day: 890, gear_lines: [SET, BOOTS],
  helmet_size: 'M', jacket_size: 'L', pants_size: 'L', gloves_size: 'M', boots_size: '43', ...o })

Deno.test('ZF/DP gear: řádky „Půjčení výbavy: … (velikosti) — termín“, množství = dny vč. obou krajních, cena = Kč/den', () => {
  ok(isGearBooking(gearBk())); ok(!isGearBooking({ moto_id: null })); ok(!isGearBooking({ booking_kind: 'moto' }))
  eq(gearDays('2026-11-10T00:00:00+00:00', '2026-11-12T00:00:00+00:00'), 3)
  eq(gearDays('2026-11-10', '2026-11-10'), 1)
  eq(gearDays('2026-10-24T22:00:00+00:00', '2026-10-26T22:00:00+00:00'), 3, 'pražská půlnoc uložená v UTC — rozdíl stejný')
  eq(gearSizesText(SET), 'helma M, bunda L, kalhoty L, rukavice M')
  eq(gearSizesText(BOOTS), '43')
  const items = gearInvoiceItems(gearBk(), { startDate: '10. 11. 2026', endDate: '12. 11. 2026', expectedRental: 2670 })
  eq(items, [
    { description: 'Půjčení výbavy: Komplet bez bot (helma M, bunda L, kalhoty L, rukavice M) — 10. 11. 2026 – 12. 11. 2026', qty: 3, unit_price: 490 },
    { description: 'Půjčení výbavy: Boty (43) — 10. 11. 2026 – 12. 11. 2026', qty: 3, unit_price: 400 },
  ])
  ok(!items.some((i) => /motork|Přistavení/i.test(i.description)), 'bez motorky a přistavení')
})

Deno.test('ZF/DP gear: nesedí-li součet na cenu (ruční zásah) → korekce; bez řádků → jeden řádek', () => {
  const items = gearInvoiceItems(gearBk(), { startDate: 'a', endDate: 'b', expectedRental: 2500 })
  eq(items[items.length - 1], { description: 'Korekce ceny výpůjčky', qty: 1, unit_price: -170 })
  eq(items.reduce((s, i) => s + i.qty * i.unit_price, 0), 2500, 'součet = cena rezervace před slevami')
  const none = gearInvoiceItems(gearBk({ gear_lines: [] }), { startDate: 'a', endDate: 'b', expectedRental: 1000 })
  eq(none[0], { description: 'Půjčení výbavy — a – b', qty: 3, unit_price: 333.33 })
  eq(Math.round(none.reduce((s, i) => s + i.qty * i.unit_price, 0) * 100) / 100, 1000)
  eq(gearDaySource(gearBk()), { price_weekday: 890 })
  eq(gearDaySource(gearBk({ gear_per_day: null })), { price_weekday: 890 }, 'fallback ze řádků')
})

Deno.test('dobropis gear: „výpůjčka výbavy“ místo „motorky“; motorka beze změny', () => {
  eq(refundSubject({ booking_kind: 'gear', motorcycles: null }), 'výpůjčka výbavy')
  eq(refundSubject({ booking_kind: 'moto', motorcycles: { model: 'BMW R 1250 GS' } }), 'BMW R 1250 GS')
  eq(refundSubject({ motorcycles: null }), 'motorky')
  eq(refundSubject(null), 'motorky')
})

Deno.test('dobropis bez modelu motorky (index.ts `model || noMotoRefundSubject`): gear dohledá „výpůjčka výbavy“; jinak „motorky“; nenasazené SQL / chyba = „motorky“', async () => {
  const d = new FakeDb({ bookings: [{ id: 'g1', booking_kind: 'gear', gear_per_day: 490 }, { id: 'm1', booking_kind: 'moto', moto_id: null }] })
  eq(await noMotoRefundSubject(d, 'g1'), 'výpůjčka výbavy')
  eq(await noMotoRefundSubject(d, 'm1'), 'motorky', 'motorka se smazanou motorkou = dřívější fallback')
  eq(await noMotoRefundSubject(d, 'nope'), 'motorky')
  eq(await noMotoRefundSubject(d, null), 'motorky')
  eq((await loadGearRefundRow(d, 'g1'))?.gear_per_day, 490, 'celý řádek (select *) pro spodní mez')
  eq(await loadGearRefundRow(d, 'm1'), null)
  const old = new FakeDb({ bookings: [{ id: 'g1', booking_kind: 'gear' }] }); old.missingCols.add('booking_kind')
  eq(await noMotoRefundSubject(old, 'g1'), 'motorky', 'chybějící sloupec booking_kind (select * ho nevrátí) = motorka')
  const boom = { from: () => { throw new Error('db down') } }
  eq(await noMotoRefundSubject(boom, 'g1'), 'motorky', 'výjimka = motorka')
})

Deno.test('vratka gear: spodní mez = Kč/den × dny − slevy (dřív null = vždy obsluha); chyba = null', async () => {
  const d = new FakeDb({ booking_discounts: [{ booking_id: 'g1', amount: 500 }, { booking_id: 'x', amount: 9999 }] })
  eq(await gearPriceFloorCzk(d, gearBk(), 'g1'), 2170)
  eq(await gearPriceFloorCzk(new FakeDb({ booking_discounts: [] }), gearBk({ gear_per_day: 490, end_date: '2026-11-10' }), 'g1'), 490)
  eq(gearPerDay({ gear_per_day: null, gear_lines: [SET] }), 490)
  eq(gearPerDay({ gear_per_day: null, gear_lines: null }), null)
  eq(await gearPriceFloorCzk(new FakeDb({}), gearBk({ gear_per_day: null, gear_lines: null }), 'g1'), null)
  const bad = new FakeDb({ booking_discounts: [] }); bad.missingCols.add('amount')
  eq(await gearPriceFloorCzk(bad, gearBk(), 'g1'), null, 'chyba dotazu slev → obsluha')
  eq(await gearPriceFloorCzk(new FakeDb({ booking_discounts: [{ booking_id: 'g1', amount: 5000 }] }), gearBk(), 'g1'), 0, 'nikdy záporná')
})

Deno.test('smlouva: rental_contract u gear → gear_rental_contract; motorka / VOP / chybějící sloupec beze změny', async () => {
  const d = new FakeDb({ bookings: [{ id: 'g1', booking_kind: 'gear' }, { id: 'm1', booking_kind: 'moto' }] })
  eq(GEAR_CONTRACT_SLUG, 'gear_rental_contract')
  eq(await resolveDocSlug(d, 'rental_contract', 'g1'), 'gear_rental_contract')
  eq(await resolveDocSlug(d, 'rental_contract', 'm1'), 'rental_contract')
  eq(await resolveDocSlug(d, 'vop', 'g1'), 'vop')
  eq(await resolveDocSlug(d, 'handover_protocol', 'g1'), 'handover_protocol')
  d.missingCols.add('booking_kind')
  eq(await resolveDocSlug(d, 'rental_contract', 'g1'), 'rental_contract', 'SQL nenasazené → jako dřív')
})

const PRICES: PriceRow[] = [
  { key: 'set_rider', label: 'Komplet bez bot', translations: { en: { label: 'Full set without boots' }, de: { label: 'Komplett ohne Stiefel' } } },
  { key: 'helmet', label: 'Helma', translations: { en: { label: 'Helmet' } } },
  { key: 'jacket', label: 'Bunda', translations: { en: { label: 'Jacket' } } },
  { key: 'pants', label: 'Kalhoty', translations: { en: { label: 'Trousers' } } },
  { key: 'gloves', label: 'Rukavice', translations: { en: { label: 'Gloves' } } },
  { key: 'boots', label: 'Boty', translations: { en: { label: 'Boots' } } },
]
Deno.test('smlouva gear: {{gear_items_table}} / {{gear_period}} / {{gear_days}} česky a v jazyce dokumentu', () => {
  const cs = buildGearVars(gearBk(), 'cs', PRICES)
  ok(cs.gear_items_table.startsWith('<table'), 'tabulka')
  ok(cs.gear_items_table.includes('Komplet bez bot') && cs.gear_items_table.includes('Helma M, Bunda L, Kalhoty L, Rukavice M'))
  ok(cs.gear_items_table.includes('Cena za den') && cs.gear_items_table.includes('890,00 Kč') && /2\s670,00 Kč/u.test(cs.gear_items_table), 'ceny')
  eq(cs.gear_period, '10. 11. 2026 – 12. 11. 2026')
  eq(cs.gear_days, '3 dny')
  eq(cs.gear_items, 'Komplet bez bot (Helma M, Bunda L, Kalhoty L, Rukavice M), Boty (43)')
  eq(cs.accessories, cs.gear_items); eq(cs.accessories_block, cs.gear_items_table)
  ok(!/řidič/.test(cs.gear_items_table), 'bez „(řidič)“')
  const en = buildGearVars(gearBk(), 'en', PRICES)
  ok(en.gear_items_table.includes('Full set without boots') && en.gear_items_table.includes('Helmet M') && en.gear_items_table.includes('Price per day'))
  eq(en.gear_days, '3 days')
  eq(buildGearVars(gearBk({ end_date: '2026-11-10T00:00:00+00:00' }), 'pl', []).gear_days, '1 dzień')
  eq(buildGearVars(gearBk({ end_date: '2026-11-14T00:00:00+00:00' }), 'uk', []).gear_days, '5 днів')
  const de = buildGearVars(gearBk(), 'de', [])
  ok(de.gear_items_table.includes('Helm M'), 'bez ceníku → obecné názvy z labels.ts')
  const xss = buildGearVars(gearBk({ gear_lines: [{ ...BOOTS, label: '<b>x</b>' }] }), 'cs', [])
  ok(!xss.gear_items_table.includes('<b>x</b>') && xss.gear_items_table.includes('&lt;b&gt;x&lt;/b&gt;'), 'HTML escapované')
})

Deno.test('ZF/DP + smlouva gear: kus nepřevzatý při předání (`not_taken`) → „nepřevzato“, cena řádku beze změny', () => {
  const setNt = { ...SET, sizes: { helmet: 'M', jacket: 'L', pants: 'L' }, not_taken: ['gloves'] }
  const bootsNt = { ...BOOTS, sizes: {}, not_taken: ['boots'] }
  eq(gearSizesText(setNt), 'helma M, bunda L, kalhoty L, rukavice nepřevzato')
  eq(gearSizesText(bootsNt), 'nepřevzato')
  eq(gearSizesText({ key: 'boots', kind: 'item', sizes: {}, not_taken: ['boots'] }), 'nepřevzato', 'řádek bez includes')
  const items = gearInvoiceItems(gearBk({ gear_lines: [setNt, bootsNt], gloves_size: null, boots_size: null }),
    { startDate: 'a', endDate: 'b', expectedRental: 2670 })
  eq(items.map((i) => [i.description, i.qty, i.unit_price]), [
    ['Půjčení výbavy: Komplet bez bot (helma M, bunda L, kalhoty L, rukavice nepřevzato) — a – b', 3, 490],
    ['Půjčení výbavy: Boty (nepřevzato) — a – b', 3, 400],
  ], 'bez korekce — zaplacená cena zůstává')
  const cs = buildGearVars(gearBk({ gear_lines: [setNt, bootsNt] }), 'cs', PRICES)
  eq(cs.gear_items, 'Komplet bez bot (Helma M, Bunda L, Kalhoty L, Rukavice nepřevzato), Boty (nepřevzato)')
  const en = buildGearVars(gearBk({ gear_lines: [bootsNt] }), 'en', PRICES)
  eq(en.gear_items, 'Boots (not taken)')
})
