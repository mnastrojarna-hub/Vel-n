// ===== _tests/gear_protocol_test.ts =====
// EDGE-B (2026-10-23) předávací protokol výpůjčky JEN výbavy (submit-handover-protocol/gear-only.ts,
// html-gear.ts, i18n-gear.ts): identita kódem šatny, číselník velikostí z ceníku ∩ samoobsluha,
// poslední kus zůstává, velikosti i do gear_lines, dokument bez motorky, e-mail s fallbackem šablony.
import {
  gearAllowedSizes, gearKioskChecks, gearMailVars, isGearBooking, keepLastGearItem, kioskIdentityCodeType,
  loadGearAllowedSizes, loadGearBranch, sendProtocolMail, syncGearLines,
} from '../submit-handover-protocol/gear-only.ts'
import { buildGearHtml } from '../submit-handover-protocol/html-gear.ts'
import { gearDaysLabel } from '../submit-handover-protocol/i18n-gear.ts'
import { buildHtml } from '../submit-handover-protocol/html.ts'
import { makeTr, PROTOCOL_LANGS } from '../submit-handover-protocol/i18n.ts'
import { normalizeAccessories, resolveGearUpdates } from '../submit-handover-protocol/gear.ts'
import { FakeDb } from './gear-fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }
type Row = Record<string, unknown>

const PRICES = [
  { key: 'helmet', kind: 'item', sizes: ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL'], is_active: true },
  { key: 'jacket', kind: 'item', sizes: ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL', '6XL'], is_active: true },
  { key: 'pants', kind: 'item', sizes: ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL', '6XL'], is_active: true },
  { key: 'gloves', kind: 'item', sizes: ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL'], is_active: false },
  { key: 'boots', kind: 'item', sizes: ['39', '40', '41', '42', '43', '44', '45', '46', '47', '48'], is_active: true },
  { key: 'set_rider', kind: 'set', sizes: [], is_active: true },
]
const bk = (o: Row = {}): Row => ({ id: 'g1', booking_kind: 'gear', moto_id: null, branch_id: 'br-vn', status: 'reserved',
  start_date: '2026-11-10T00:00:00+00:00', end_date: '2026-11-12T00:00:00+00:00', pickup_time: '12:00:00', return_time: null,
  helmet_size: 'M', jacket_size: 'L', pants_size: null, gloves_size: null, boots_size: null,
  gear_lines: [{ key: 'set_x', kind: 'set', label: 'Helma + bunda', includes: ['helmet', 'jacket'], sizes: { helmet: 'M', jacket: 'L' }, price_per_day: 350 }],
  ...o })

Deno.test('gear protokol: identita = kód šatny, motorka = kód motorky; rozpoznání jen booking_kind', () => {
  eq(kioskIdentityCodeType(true), 'accessories'); eq(kioskIdentityCodeType(false), 'motorcycle')
  ok(isGearBooking(bk())); ok(!isGearBooking({ moto_id: null, booking_kind: 'moto' })); ok(!isGearBooking(null))
})

Deno.test('gear protokol: typ pobočky z bookings.branch_id (samostatný dotaz); chyba / chybí → null', async () => {
  const d = new FakeDb({ branches: [{ id: 'br-vn', type: 'samoobslužná', name: 'MotoGo24 Velké Němčice', address: 'Hlavní 1', city: 'Velké Němčice' },
    { id: 'br-mz', type: 'obslužná', name: 'MotoGo24 Mezná', address: 'Mezná 9', city: 'Pelhřimov' }] })
  eq((await loadGearBranch(d, 'br-vn'))?.type, 'samoobslužná')
  eq((await loadGearBranch(d, 'br-mz'))?.type, 'obslužná')
  eq(await loadGearBranch(d, null), null)
  eq(await loadGearBranch(d, 'missing'), null)
  d.missingCols.add('type')
  let thrown = false
  try { await loadGearBranch(d, 'br-vn') } catch { thrown = true }
  ok(thrown, 'chyba DB → výjimka → 500 (kiosk podpis zopakuje), ne trvalé not_self_service')
})

Deno.test('gear protokol: číselník = aktivní kusy ceníku ∩ samoobsluha (helma S–3XL, ostatní ≤ 4XL, boty vše)', async () => {
  const m = gearAllowedSizes(PRICES)
  eq([...m.get('helmet')!], ['S', 'M', 'L', 'XL', '2XL', '3XL'])
  eq([...m.get('jacket')!], ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL'])
  eq(m.has('gloves'), false, 'neaktivní kus')
  eq(m.get('boots')!.size, 10)
  eq(m.has('set_rider'), false, 'komplet nemá vlastní velikosti')
  const d = new FakeDb({ gear_rental_prices: PRICES })
  eq([...(await loadGearAllowedSizes(d)).get('pants')!].pop(), '4XL')
  d.missingCols.add('sizes')
  eq((await loadGearAllowedSizes(d)).size, 0, 'chyba = prázdný číselník (velikost se nezapíše)')
})

Deno.test('gear protokol: změna velikosti z číselníku se propíše (i do gear_lines), 5XL ne; kus navíc se nepřidá', async () => {
  const b = bk()
  const items = normalizeAccessories([
    { field: 'helmet_size', size: 'L', checked: true },
    { field: 'jacket_size', size: '5XL', checked: true },
    { field: 'boots_size', size: '43', checked: true },
  ], true)
  const res = await resolveGearUpdates(null, b, items, true, false, true, gearAllowedSizes(PRICES))
  eq(res.updates, { helmet_size: 'L' })
  eq(res.changes, { helmet: { from: 'M', to: 'L' } })
  ok(items.find((a) => a.field === 'boots_size')?.extra, 'v dokumentu „(navíc)“, do rezervace ne')
  eq(syncGearLines(b.gear_lines, res.updates), [{ key: 'set_x', kind: 'set', label: 'Helma + bunda', includes: ['helmet', 'jacket'], sizes: { helmet: 'L', jacket: 'L' }, price_per_day: 350 }])
  eq(syncGearLines(b.gear_lines, {}), null)
  eq(syncGearLines(b.gear_lines, { jacket_size: null }), [{ key: 'set_x', kind: 'set', label: 'Helma + bunda', includes: ['helmet', 'jacket'],
    sizes: { helmet: 'M' }, price_per_day: 350, not_taken: ['jacket'] }], 'nepřevzatý kus: ze sizes pryč + not_taken, cena beze změny')
  eq(syncGearLines(null, { helmet_size: 'L' }), null)
})

Deno.test('gear protokol: nepřevzatý kus → gear_lines souhlasí se sloupci (sizes bez kusu, not_taken), cena řádku zůstává', () => {
  const lines = [
    { key: 'helmet', kind: 'item', label: 'Helma', includes: ['helmet'], sizes: { helmet: 'M' }, price_per_day: 200, total: 600 },
    { key: 'jacket', kind: 'item', label: 'Bunda', includes: ['jacket'], sizes: { jacket: 'L' }, price_per_day: 200, total: 600 },
  ]
  const out = syncGearLines(lines, { helmet_size: null, jacket_size: 'XL' }) as Row[]
  eq(out[0], { key: 'helmet', kind: 'item', label: 'Helma', includes: ['helmet'], sizes: {}, price_per_day: 200, total: 600, not_taken: ['helmet'] })
  eq(out[1], { key: 'jacket', kind: 'item', label: 'Bunda', includes: ['jacket'], sizes: { jacket: 'XL' }, price_per_day: 200, total: 600 })
  eq(syncGearLines(out, { helmet_size: null }), null, 'opakované odebrání = beze změny')
  // řádek bez includes / sizes (starší tvar): kus, který řádek nenese, se nedotkne
  eq(syncGearLines([{ key: 'boots', kind: 'item', sizes: { boots: '43' }, price_per_day: 100 }], { helmet_size: null }), null)
  // velikost kusu, který byl dřív nepřevzatý (nový podpis), not_taken zase zruší
  eq(syncGearLines(out, { helmet_size: 'L' }) as Row[], [{ ...out[0], sizes: { helmet: 'L' }, not_taken: undefined }, out[1]].map((l) => JSON.parse(JSON.stringify(l))))
})

Deno.test('gear protokol: odebrat jeden ze dvou kusů jde; poslední kus zůstává (odebrání se vrátí)', async () => {
  const b = bk()
  const two = normalizeAccessories([{ field: 'helmet_size', size: 'M', checked: false }, { field: 'jacket_size', size: 'L', checked: true }], true)
  const r1 = await resolveGearUpdates(null, b, two, true, false, false, gearAllowedSizes(PRICES))
  eq(keepLastGearItem(b, r1, two), [])
  eq(r1.updates, { helmet_size: null }); ok(two[0].removed)
  const none = normalizeAccessories([{ field: 'helmet_size', size: 'M', checked: false }, { field: 'jacket_size', size: 'L', checked: false }], true)
  const r2 = await resolveGearUpdates(null, b, none, true, false, false, gearAllowedSizes(PRICES))
  eq(Object.keys(r2.updates).sort(), ['helmet_size', 'jacket_size'])
  eq(keepLastGearItem(b, r2, none).sort(), ['helmet_size', 'jacket_size'])
  eq(r2.updates, {}); eq(r2.changes, {})
  ok(!none.some((a) => a.removed), 'bez poznámky o odebrání')
  // poslední kus + změna velikosti druhého → odebrání se vrátí, změna velikosti zůstane
  const mix = normalizeAccessories([{ field: 'helmet_size', size: 'L', checked: true }, { field: 'jacket_size', size: 'L', checked: false }], true)
  const one = bk({ helmet_size: null, jacket_size: 'L' })
  const r3 = await resolveGearUpdates(null, one, mix, true, false, false, gearAllowedSizes(PRICES))
  eq(keepLastGearItem(one, r3, mix), ['jacket_size'])
  eq(r3.updates, {})
})

Deno.test('gear protokol: kontroly výpůjčky předvyplněné na kiosku, poslané hodnoty mají přednost', () => {
  eq(gearKioskChecks(undefined), { gear_condition: true, gear_fit: true, gear_return: true })
  eq(gearKioskChecks({ gear_fit: false }), { gear_condition: true, gear_fit: false, gear_return: true })
})

const SIG = 'data:image/png;base64,iVBORw0KGgo='
const VARS = { booking_number: '66667777', today: '10. 11. 2026', company_name: 'Bc. Petra Semorádová, MotoGo24', customer_name: 'Jana <Nováková>',
  moto_model: '—', moto_spz: '', moto_vin: '', rental_period: '10. 11. 2026 — 12. 11. 2026', pickup_time: '10. 11. 2026 12:00' }
const FORM = () => ({ checks: gearKioskChecks(undefined), damage: { checked: false, desc: '' }, notes: '',
  accessories: normalizeAccessories([{ field: 'helmet_size', size: 'M', checked: true }, { field: 'jacket_size', size: 'L', checked: true }], true) })

Deno.test('gear dokument: bez motocyklu / VIN / km / výbavy motorky; předmět nájmu, pobočka, ověření kódem šatny', () => {
  const h = buildGearHtml(VARS, FORM(), SIG, { by: 'kiosk', deviceId: 'dev-1', signedAt: new Date('2026-11-10T11:05:00Z') }, 'cs', { branch: 'MotoGo24 Velké Němčice, Hlavní 1' })
  for (const bad of ['Motocykl', 'VIN', 'Stav km', 'Výbava motorky', 'Klíče a zabezpečení', 'OTP', 'řidič']) ok(!h.includes(bad), `bez „${bad}“`)
  for (const good of ['PŘEDÁVACÍ PROTOKOL — ZAPŮJČENÁ VÝBAVA', 'Motorkářská výbava (bez motocyklu)', 'MotoGo24 Velké Němčice, Hlavní 1',
    'kód šatny této rezervace', 'Výbava předána čistá, kompletní a bez poškození', 'Velikosti vyzkoušeny a odpovídají',
    'Nájemce poučen o vrácení (termín, pobočka, šatna)', 'Poškození výbavy při předání', '☑ Výbava', 'Helma', 'Bunda', 'zařízení dev-1']) ok(h.includes(good), `obsahuje „${good}“`)
  ok(h.includes('Jana &lt;Nováková&gt;') && !h.includes('Jana <Nováková>'), 'escapované jméno')
  const app = buildGearHtml(VARS, { ...FORM(), checks: {} }, SIG, { by: 'app', signedAt: new Date() }, 'cs', { branch: 'X' })
  ok(app.includes('přihlášení do aplikace MotoGo24') && app.includes('☐ Výbava předána'), 'appka: nezaškrtnuté kontroly zůstávají ☐')
  // motorkový dokument beze změny (regrese)
  const moto = buildHtml(VARS, { ...FORM(), checks: { clean: true } }, SIG, { by: 'kiosk', deviceId: 'd', signedAt: new Date() }, 'cs')
  ok(moto.includes('Motocykl') && moto.includes('VIN') && !moto.includes('ZAPŮJČENÁ VÝBAVA'))
})

Deno.test('gear dokument: všech 8 jazyků má texty gr_* (dvojjazyčně s češtinou)', () => {
  eq(PROTOCOL_LANGS.length, 8)
  for (const l of PROTOCOL_LANGS) {
    const tr = makeTr(l)
    for (const k of ['gr_title', 'gr_heading', 'gr_subject_val', 'gr_identity_kiosk', 'gr_chk_gear_condition', 'gr_chk_gear_fit', 'gr_chk_gear_return', 'gr_damageAt']) {
      const v = tr.plain(k)
      ok(v && v !== k, `${l}.${k}`)
      if (l !== 'cs') ok(v !== makeTr('cs').plain(k), `${l}.${k} přeloženo`)
    }
    const h = buildGearHtml(VARS, FORM(), SIG, { by: 'kiosk', deviceId: 'd', signedAt: new Date() }, l, { branch: 'B' })
    ok(h.includes(`lang="${l}"`), l)
    if (l !== 'cs') ok(h.includes('Motorkářská výbava (bez motocyklu)') && h.includes(tr.plain('gr_subject_val')), `${l}: dvojjazyčně`)
  }
})

Deno.test('gear e-mail: proměnné escapované, výbava, pobočka, dny v 8 jazycích', () => {
  const v = gearMailVars(bk(), FORM().accessories, { id: 'br-vn', type: 'samoobslužná', name: 'MotoGo24 Velké Němčice', address: 'Hlavní 1', city: 'Velké Němčice' },
    'cs', { customer_name: 'Jana <Nováková>', booking_number: '66667777', doc_name: 'Předávací protokol — výbava' })
  eq(v.customer_name, 'Jana &lt;Nováková&gt;')
  eq(v.branch_address, 'Hlavní 1, Velké Němčice')
  eq(v.gear_period, '10. 11. 2026 – 12. 11. 2026'); eq(v.gear_days, '3 dny'); eq(v.pickup_time, '12:00'); eq(v.return_time, '')
  eq(v.gear_items_block, '<ul style="margin:6px 0 6px 18px;padding:0"><li>Helma: <strong>M</strong></li><li>Bunda: <strong>L</strong></li></ul>')
  eq(v.moto, 'Motorkářská výbava (bez motocyklu)', 'fallback šablona „Motocykl: {{moto}}“')
  eq(v.site_url, 'https://www.motogo24.cz')
  const en = gearMailVars(bk(), FORM().accessories, null, 'en', { customer_name: 'J', booking_number: '1', doc_name: 'd' })
  ok(en.gear_items_block.includes('Helmet') && en.site_url === 'https://motogo24.com' && en.gear_days === '3 days')
  // SITE_URL (staging / náhled) platí pro češtinu jako jinde v edge (send-invoice-email); env se vrátí
  const prev = Deno.env.get('SITE_URL')
  Deno.env.set('SITE_URL', 'https://staging.motogo24.test')
  try {
    eq(gearMailVars(bk(), [], null, 'cs', { customer_name: '', booking_number: '', doc_name: '' }).site_url, 'https://staging.motogo24.test')
    eq(gearMailVars(bk(), [], null, 'de', { customer_name: '', booking_number: '', doc_name: '' }).site_url, 'https://motogo24.com')
  } finally { if (prev === undefined) Deno.env.delete('SITE_URL'); else Deno.env.set('SITE_URL', prev) }
  const want: Record<string, [string, string, string]> = {
    cs: ['1 den', '3 dny', '5 dní'], en: ['1 day', '3 days', '5 days'], de: ['1 Tag', '3 Tage', '5 Tage'], es: ['1 día', '3 días', '5 días'],
    fr: ['1 jour', '3 jours', '5 jours'], nl: ['1 dag', '3 dagen', '5 dagen'], pl: ['1 dzień', '3 dni', '5 dni'], uk: ['1 день', '3 дні', '5 днів'],
  }
  for (const [l, [a, b, c]] of Object.entries(want)) eq([gearDaysLabel(1, l), gearDaysLabel(3, l), gearDaysLabel(5, l)], [a, b, c], l)
})

Deno.test('gear e-mail: chybí gear šablona (404) → základní šablona protokolu; jinak jedno volání; motorka bez fallbacku', async () => {
  const seen: string[] = []
  const mk = (status: Record<string, number>) => ((_u: string | URL | Request, init?: RequestInit) => {
    const slug = JSON.parse(String(init?.body)).template_slug as string
    seen.push(slug)
    const st = status[slug] ?? 200
    return Promise.resolve(new Response(JSON.stringify(st === 200 ? { success: true } : { success: false }), { status: st }))
  }) as typeof fetch
  eq(await sendProtocolMail('u', 'k', { template_slug: 'handover_protocol_gear_sent' }, 'handover_protocol_sent', mk({ handover_protocol_gear_sent: 404 })), true)
  eq(seen, ['handover_protocol_gear_sent', 'handover_protocol_sent'])
  seen.length = 0
  eq(await sendProtocolMail('u', 'k', { template_slug: 'handover_protocol_gear_sent' }, 'handover_protocol_sent', mk({})), true)
  eq(seen, ['handover_protocol_gear_sent'])
  seen.length = 0
  eq(await sendProtocolMail('u', 'k', { template_slug: 'handover_protocol_gear_sent' }, 'handover_protocol_sent', mk({ handover_protocol_gear_sent: 500 })), false)
  eq(seen, ['handover_protocol_gear_sent'], '5xx = žádný fallback (best-effort)')
  seen.length = 0
  eq(await sendProtocolMail('u', 'k', { template_slug: 'handover_protocol_sent' }, null, mk({ handover_protocol_sent: 404 })), false)
  eq(seen, ['handover_protocol_sent'])
})
