// ===== _tests/gear_email_test.ts =====
// Výpůjčka JEN výbavy (bookings.booking_kind='gear', 2026-10-23) — proměnné e-mailových šablon
// (8 jazyků), blok kódů jen šatna + brána, přehled změn, volba gear šablony a fallback.
import { buildGearVars, gearCancellationReason, gearRenderType, gearSubjectVars, loadGearBooking, pragueDay, type GearBooking } from '../_shared/email-gear.ts'
import { daysLabel, renderGearDoorCodesBlock, type GearLine } from '../_shared/email-gear-blocks.ts'
import { EMAIL_SLUG_FALLBACKS, gearFallbackTemplate } from '../_shared/email-gear-fallback.ts'
import { prepareGearMail, releasedLockerCode } from '../send-booking-email/gear-booking.ts'
import { FakeDb } from './gear-fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg: string) { if (!c) throw new Error(msg) }
const LANGS = ['cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk'] as const
const BID = '5b0c8f2e-1111-4222-8333-0000a1b2c3d4'
const LABELS = { set_rider: { cs: 'Komplet bez bot', en: 'Full set without boots', de: 'Komplett ohne Stiefel', uk: 'Комплект без чобіт' },
  helmet: { cs: 'Helma', en: 'Helmet', de: 'Helm', pl: 'Kask', uk: 'Шолом' }, jacket: { cs: 'Bunda', en: 'Jacket', de: 'Jacke' },
  pants: { cs: 'Kalhoty', de: 'Hose' }, gloves: { cs: 'Rukavice', de: 'Handschuhe' }, boots: { cs: 'Boty', en: 'Boots', de: 'Stiefel' } }
const LINES: GearLine[] = [
  { key: 'set_rider', kind: 'set', label: 'Komplet bez bot', sizes: { helmet: 'M', jacket: 'L', pants: 'L', gloves: 'M' }, price_per_day: 490 },
  { key: 'boots', kind: 'item', label: 'Boty', sizes: { boots: '43' }, price_per_day: 400 },
]
function gb(o: Partial<GearBooking> = {}): GearBooking {
  return { id: BID, status: 'reserved', paymentStatus: 'paid', start: '2026-06-15', end: '2026-06-17', days: 3, pickupTime: '09:00',
    returnTime: '17:00', totalPrice: 2670, lines: LINES, sizes: { helmet: 'L', jacket: null, pants: null, gloves: null, boots: null },
    labels: LABELS, branch: { id: '22222222-2222-2222-2222-222222222222', name: 'Velké Němčice', address: 'Hlavní 1', city: 'Velké Němčice', type: 'samoobslužná' },
    customerName: 'Jana <Nováková>', ...o }
}

Deno.test('gear vars: termín, dny, výbava a odkazy ve všech 8 jazycích', () => {
  const expPeriod: Record<string, string> = { cs: '15. 6. 2026 – 17. 6. 2026', de: '15.6.2026 – 17.6.2026', en: '15/06/2026 – 17/06/2026' }
  const expDays: Record<string, string> = { cs: '3 dny', en: '3 days', de: '3 Tage', nl: '3 dagen', es: '3 días', fr: '3 jours', pl: '3 dni', uk: '3 дні' }
  for (const l of LANGS) {
    const v = buildGearVars(gb(), l, { site: l === 'cs' ? 'https://www.motogo24.cz' : 'https://motogo24.com' })
    if (expPeriod[l]) eq(v.gear_period, expPeriod[l], `${l} period`)
    eq(v.gear_days, expDays[l], `${l} days`)
    eq(v.booking_number, 'A1B2C3D4', `${l} number`)
    eq(v.total_price, (2670).toLocaleString('cs-CZ'), `${l} total`)
    ok(v.gear_items_block.startsWith('<ul') && v.gear_items_block.includes('43'), `${l} items block`)
    const q = l === 'cs' ? '' : `&lang=${l}`
    eq(v.pay_url, `${l === 'cs' ? 'https://www.motogo24.cz' : 'https://motogo24.com'}/pujceni-obleceni?resume=${BID}${q}`, `${l} pay_url`)
    eq(v.resume_link, v.pay_url, `${l} resume`)
    ok(v.docs_url.includes(`resume=${BID}&docs=1`), `${l} docs_url`)
    ok(v.manage_url.endsWith('/upravit-rezervaci' + (l === 'cs' ? '' : `?lang=${l}`)), `${l} manage_url`)
    eq(v.branch_name, 'Velké Němčice', `${l} branch`)
    eq(v.branch_address, 'Hlavní 1, Velké Němčice', `${l} address`)
    eq(v.customer_name, 'Jana &lt;Nováková&gt;', `${l} escaped name`)
    ok(!/motork|motorcycle|Motorrad/i.test(JSON.stringify(v)), `${l} no motorcycle wording`)
  }
  const de = buildGearVars(gb(), 'de', { site: 'https://motogo24.com' })
  ok(de.gear_items_block.includes('Komplett ohne Stiefel') && de.gear_items_block.includes('Helm L, Jacke L'), 'de labels, nouns capitalised, size from column')
  const cs = buildGearVars(gb(), 'cs', { site: 'https://www.motogo24.cz' })
  ok(cs.gear_items_block.includes('helma L, bunda L, kalhoty L, rukavice M') && cs.gear_items_block.includes('490 Kč/den'), 'cs set sizes lowercase + per day')
  const uk = buildGearVars(gb(), 'uk', { site: 'https://motogo24.com' })
  ok(uk.gear_items_block.includes('Комплект без чобіт') && uk.gear_items_block.includes('/день'), 'uk labels')
  const pl = buildGearVars(gb(), 'pl', { site: 'https://motogo24.com' })
  ok(pl.gear_items_block.includes('Komplet bez bot'), 'pl falls back to cs label when no translation')
})

Deno.test('gear vars: skloňování dní (cs / pl / uk) a pražský den z timestamptz', () => {
  eq([1, 2, 4, 5, 21].map((n) => daysLabel('cs', n)), ['1 den', '2 dny', '4 dny', '5 dní', '21 dní'])
  eq([1, 2, 5, 22].map((n) => daysLabel('pl', n)), ['1 dzień', '2 dni', '5 dni', '22 dni'])
  eq([1, 3, 11, 12, 21, 22, 25].map((n) => daysLabel('uk', n)), ['1 день', '3 дні', '11 днів', '12 днів', '21 день', '22 дні', '25 днів'])
  eq([1, 2].map((n) => daysLabel('fr', n)), ['1 jour', '2 jours'])
  eq(pragueDay('2026-06-15T00:00:00+00:00'), '2026-06-15', 'web: UTC půlnoc')
  eq(pragueDay('2026-06-14T22:00:00+00:00'), '2026-06-15', 'Velín: pražská půlnoc (léto)')
  eq(pragueDay('2026-12-14T23:00:00+00:00'), '2026-12-15', 'pražská půlnoc (zima)')
  eq(pragueDay('2026-06-15'), '2026-06-15')
})

Deno.test('door_codes_block: samoobsluha = brána → šatna (dveře č.) → postup, nikdy kód motorky', () => {
  for (const l of LANGS) {
    const h = renderGearDoorCodesBlock(l, { code: '4821', gate: '0937', lockerDoor: 8, selfService: true, branchName: 'Velké Němčice', pageUrl: 'https://x.test/pobocky/velke-nemcice' })
    ok(h.includes('4821') && h.includes('0937') && h.includes('8'), `${l} codes + door`)
    ok(h.indexOf('0937') < h.indexOf('4821'), `${l} gate before locker`)
    ok((h.match(/<li /g) || []).length === 5, `${l} 5 steps (gate, locker, protocol, return, important)`)
    ok(!/motork|motorcycle|Motorrad|moto\b|мотоцикл/i.test(h), `${l} no motorcycle`)
    ok(h.includes('https://x.test/pobocky/velke-nemcice'), `${l} page link`)
  }
  const noGate = renderGearDoorCodesBlock('cs', { code: '4821', selfService: true, branchName: 'Test', lockerDoor: null })
  ok(!noGate.includes('schránky') && noGate.includes('Kód šatny:') && (noGate.match(/<li /g) || []).length === 3, 'samoobsluha bez brány: 3 kroky')
  const staffed = renderGearDoorCodesBlock('cs', { code: '4821', selfService: false, branchName: 'Mezná' })
  ok(staffed.includes('4821') && !staffed.includes('<ol') && !staffed.includes('displeji'), 'obslužná: jen box s kódem (bez postupu na displeji)')
  eq(renderGearDoorCodesBlock('cs', { code: '', gate: '0937', selfService: true, branchName: 'X' }), '', 'bez vydaného kódu nic (ani kód brány)')
  ok(renderGearDoorCodesBlock('cs', { code: '1<2', selfService: false, branchName: 'X' }).includes('1&lt;2'), 'escaped')
})

Deno.test('changes_block: termín, časy, výbava (RPC changes.gear) a cena; beze změn prázdné', () => {
  const p = { original_start_date: '2026-06-14T00:00:00+00:00', original_end_date: '2026-06-16T00:00:00+00:00', original_total_price: 2000,
    original_pickup_time: '09:00:00', pickup_time: '10:30:00', original_return_time: '17:00', return_time: '17:00',
    changes: { gear: { from: { helmet: 'M', boots: '42' }, to: { helmet: 'L', boots: '43' } } } }
  const v = buildGearVars(gb(), 'cs', { site: 'https://www.motogo24.cz', payload: p })
  ok(v.changes_block.includes('14. 6. 2026 – 16. 6. 2026') && v.changes_block.includes('15. 6. 2026 – 17. 6. 2026'), 'period row')
  ok(v.changes_block.includes('10:30') && !v.changes_block.includes('Čas vrácení'), 'pickup changed, return unchanged → hidden')
  ok(v.changes_block.includes('Helma M, Boty 42') && v.changes_block.includes('Helma L, Boty 43'), 'items row')
  ok(v.changes_block.includes(`${(2000).toLocaleString('cs-CZ')} Kč`) && v.changes_block.includes(`${(2670).toLocaleString('cs-CZ')} Kč`), 'total row')
  const lines = buildGearVars(gb(), 'en', { site: 'https://motogo24.com', payload: { changes: { gear: { from: LINES, to: [LINES[0]] } } } })
  ok(lines.changes_block.includes('Full set without boots (helmet M') && lines.changes_block.includes('Boots 43'), 'lines shape')
  const same = buildGearVars(gb(), 'cs', { site: 'https://www.motogo24.cz', payload: { original_start_date: '2026-06-15', original_end_date: '2026-06-17', original_total_price: 2670, original_pickup_time: '09:00:00', pickup_time: '09:00:00' } })
  eq(same.changes_block, '', 'no changes')
})

Deno.test('volba šablony: typ → gear_<typ>, fallback CZ/EN bez motorky, send-email náhradní slug', () => {
  eq(gearRenderType('booking_reserved'), 'gear_booking_reserved')
  eq(gearRenderType('invoice_payment_receipt'), 'gear_invoice_payment_receipt')
  eq(gearRenderType('booking_abandoned_full'), 'gear_booking_abandoned')
  eq(gearRenderType('door_codes'), 'gear_door_codes')
  eq(gearRenderType('booking_modified'), 'gear_booking_modified')
  eq(gearRenderType('gear_booking_completed'), 'gear_booking_completed', 'Velín přeposlání gear slugu')
  eq(gearRenderType('sos_incident'), 'gear_sos_incident')
  for (const t of ['gear_booking_reserved', 'gear_invoice_payment_receipt', 'gear_booking_missing_docs', 'gear_booking_abandoned', 'gear_door_codes', 'gear_booking_modified', 'gear_booking_cancelled', 'gear_booking_completed', 'gear_unknown']) {
    for (const l of ['cs', 'en', 'de']) {
      const f = gearFallbackTemplate(t, l, { refund_amount: '100', manage_url: 'x', docs_url: 'x', pay_url: 'x', google_review_url: 'x' })
      ok(f.subject.includes('{{booking_number}}') && f.body.includes('{{gear_items_block}}'), `${t}/${l} placeholders`)
      ok(!/motork|motocykl|motorcycle/i.test(f.subject + f.body), `${t}/${l} no motorcycle`)
    }
  }
  ok(gearFallbackTemplate('gear_booking_reserved', 'de').subject.startsWith('Gear rental'), 'other languages → EN')
  ok(!gearFallbackTemplate('gear_booking_cancelled', 'cs', { refund_amount: '' }).body.includes('Vrácená částka'), 'storno bez vratky bez řádku částky')
  eq(EMAIL_SLUG_FALLBACKS.handover_protocol_gear_sent, 'handover_protocol_sent')
  eq(gearCancellationReason('', 'de'), 'Nicht angegeben')
  eq(gearCancellationReason('Stornováno zákazníkem', 'en'), 'Cancelled by the customer')
  eq(gearCancellationReason('a<b', 'cs'), 'a&lt;b')
  const sv = gearSubjectVars({ door_codes_block: '<div>0937</div>', gear_items_block: '<ul>', customer_name: 'x' }, gb(), '')
  eq([sv.door_codes_block, sv.gear_items_block, sv.customer_name], ['', '', 'Jana <Nováková>'], 'subject = plain text, no codes')
})

Deno.test('prepareGearMail: jen gear rezervace; motorka / chybějící sloupec → null (motorkový mail beze změny)', async () => {
  const tables = () => ({
    bookings: [
      { id: BID, booking_kind: 'gear', status: 'reserved', payment_status: 'paid', user_id: 'u1', start_date: '2026-06-15T00:00:00+00:00',
        end_date: '2026-06-17T00:00:00+00:00', pickup_time: '09:00:00', return_time: null, total_price: 2670, gear_lines: LINES,
        branch_id: 'br-vn', helmet_size: 'M', jacket_size: 'L', pants_size: 'L', gloves_size: 'M', boots_size: '43' },
      { id: 'moto-1', booking_kind: 'moto', status: 'reserved', user_id: 'u1', start_date: '2026-06-15', end_date: '2026-06-16' },
    ],
    branches: [{ id: 'br-vn', name: 'Velké Němčice', address: 'Hlavní 1', city: 'Velké Němčice', type: 'samoobslužná' }],
    gear_rental_prices: [{ key: 'set_rider', label: 'Komplet bez bot', translations: { en: { label: 'Full set without boots' } } }],
    profiles: [{ id: 'u1', full_name: 'Jana' }],
  })
  const d = new FakeDb(tables())
  d.rpcs._branch_gate_code = () => ({ data: '0937', error: null })
  d.rpcs._branch_locker_door_no = () => ({ data: 8, error: null })
  const rows = [{ code_type: 'accessories', door_code: '4821', sent_to_customer: true, withheld_reason: null }]
  eq(releasedLockerCode([{ code_type: 'accessories', door_code: '1', sent_to_customer: true, withheld_reason: 'Chybí doklad' }]), '', 'withheld')
  const gm = await prepareGearMail(d, { bookingId: BID, renderType: 'booking_reserved', site: 'https://motogo24.com', payload: {}, doorCodeRows: rows })
  ok(gm, 'gear detected')
  eq(gm!.renderType, 'gear_booking_reserved')
  const en = gm!.varsFor('en'), cs = gm!.varsFor('cs')
  ok(en.door_codes_block.includes('Locker room code (door no. 8)') && en.door_codes_block.includes('0937'), 'en block with gate + door')
  ok(cs.door_codes_block.includes('Kód šatny (dveře č. 8)') && cs.gear_days === '3 dny', 'cs admin copy vars')
  eq([en.customer_name, en.door_code_moto, en.motorcycle], ['Jana', '', ''])
  eq(await prepareGearMail(d, { bookingId: 'moto-1', renderType: 'booking_reserved', site: 's', payload: {}, doorCodeRows: [] }), null, 'moto')
  const noCodes = await prepareGearMail(d, { bookingId: BID, renderType: 'door_codes', site: 's', payload: {}, doorCodeRows: [] })
  eq(noCodes!.varsFor('cs').door_codes_block, '', 'no released code → empty block')
  const d2 = new FakeDb(tables()); d2.missingCols.add('booking_kind')
  eq(await loadGearBooking(d2, BID), null, 'SQL not deployed yet → moto path')
})
