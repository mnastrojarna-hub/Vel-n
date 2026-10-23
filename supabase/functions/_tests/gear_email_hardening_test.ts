// ===== _tests/gear_email_hardening_test.ts =====
// Výpůjčka JEN výbavy (2026-10-23) — pojistky e-mailů po review EDGE-A: přechodná chyba DB nepřepne
// gear mail na motorku, fallback text de/fr/… = angličtina i v proměnných (odkazy v jazyce zákazníka),
// dovětek o vratce převodem (tykání, 8 jazyků), prototypové klíče, pásmo vratky storna (Praha).
import { gearRenderType, loadGearBooking } from '../_shared/email-gear.ts'
import { gearTexts } from '../_shared/email-gear-blocks.ts'
import { EMAIL_SLUG_FALLBACKS, gearFallbackLang, gearFallbackTemplate, gearFallbackVars } from '../_shared/email-gear-fallback.ts'
import { gearFallbackRender, prepareGearMail } from '../send-booking-email/gear-booking.ts'
import { pragueWallToMs, refundTierPercent, refundTierRef } from '../send-cancellation-email/refund-tier.ts'
import { FakeDb } from './gear-fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg: string) { if (!c) throw new Error(msg) }
const BID = '5b0c8f2e-1111-4222-8333-0000a1b2c3d4'
const LINES = [
  { key: 'set_rider', kind: 'set', label: 'Komplet bez bot', sizes: { helmet: 'M', jacket: 'L', pants: 'L', gloves: 'M' }, price_per_day: 490 },
  { key: 'boots', kind: 'item', label: 'Boty', sizes: { boots: '43' }, price_per_day: 400 },
]
const tables = () => ({
  bookings: [
    { id: BID, booking_kind: 'gear', status: 'reserved', payment_status: 'paid', user_id: 'u1', start_date: '2026-06-15T00:00:00+00:00',
      end_date: '2026-06-17T00:00:00+00:00', pickup_time: '09:00:00', return_time: null, total_price: 2670, gear_lines: LINES,
      branch_id: 'br-vn', helmet_size: 'M', jacket_size: 'L', pants_size: 'L', gloves_size: 'M', boots_size: '43' },
    { id: 'moto-1', booking_kind: 'moto', status: 'reserved', user_id: 'u1', start_date: '2026-06-15', end_date: '2026-06-16', total_price: 1 },
  ],
  branches: [{ id: 'br-vn', name: 'Velké Němčice', address: 'Hlavní 1', city: 'Velké Němčice', type: 'samoobslužná' }],
  gear_rental_prices: [{ key: 'set_rider', label: 'Komplet bez bot', translations: { en: { label: 'Full set without boots' }, de: { label: 'Komplett ohne Stiefel' } } }],
  profiles: [{ id: 'u1', full_name: 'Jana' }],
})

/** FakeDb, kde select z `bookings` selže (statement timeout), když `fail(cols, i)` vrátí true. */
function flaky(d: FakeDb, fail: (cols: string, i: number) => boolean) {
  let i = 0
  const err = { code: '57014', message: 'canceling statement due to statement timeout' }
  return new Proxy(d, {
    get(t, prop) {
      // deno-lint-ignore no-explicit-any
      const v = (t as any)[prop]
      if (prop !== 'from') return typeof v === 'function' ? v.bind(t) : v
      return (table: string) => table !== 'bookings' ? t.from(table) : {
        select: (cols: string) => fail(cols, i++)
          ? { eq: () => ({ maybeSingle: () => Promise.resolve({ data: null, error: err }) }) }
          : t.from(table).select(cols),
      }
    },
  })
}

Deno.test('loadGearBooking: přechodná chyba DB → opakování / sonda / kindHint, nikdy motorkový mail', async () => {
  const once = await loadGearBooking(flaky(new FakeDb(tables()), (_c, i) => i === 0), BID)
  eq([once?.days, once?.lines.length, once?.branch?.name], [3, 2, 'Velké Němčice'], 'retry succeeds')
  // Plný select padá pořád (např. vadný gear sloupec), základní sonda projde → gear bez detailů výbavy.
  const core = await loadGearBooking(flaky(new FakeDb(tables()), (c) => c.includes('gear_lines')), BID)
  eq([core?.start, core?.end, core?.days, core?.totalPrice, core?.lines.length, core?.branch?.id], ['2026-06-15', '2026-06-17', 3, 2670, 0, 'br-vn'], 'probe')
  const moto = await loadGearBooking(flaky(new FakeDb(tables()), (c) => c.includes('gear_lines')), 'moto-1')
  eq(moto, null, 'probe says moto')
  const down = flaky(new FakeDb(tables()), () => true)
  eq(await loadGearBooking(down, BID), null, 'no data and no hint → moto path (as before)')
  const hinted = await loadGearBooking(down, BID, 'gear')
  eq([hinted?.id, hinted?.days, hinted?.start, hinted?.branch], [BID, 1, '', null], 'hint gear → minimal gear booking')
  const d2 = new FakeDb(tables()); d2.missingCols.add('booking_kind')
  eq(await loadGearBooking(d2, BID, 'gear'), null, 'SQL not deployed (42703) → moto path')
  const gm = await prepareGearMail(down, { bookingId: BID, renderType: 'booking_reserved', site: 'https://motogo24.com', payload: { booking_kind: 'gear' }, doorCodeRows: [] })
  ok(gm && gm.renderType === 'gear_booking_reserved', 'prepareGearMail uses payload booking_kind')
  const fb = gearFallbackRender(gm!, 'cs', gm!.varsFor('cs'))
  ok(!/motork|motocykl|NaN|undefined/i.test(fb.subject + fb.body), 'minimal gear text is clean')
})

Deno.test('fallback de/fr/…: text i proměnné výbavy anglicky, odkazy v jazyce zákazníka, blok kódů jednou', async () => {
  const d = new FakeDb(tables())
  d.rpcs._branch_gate_code = () => ({ data: '0937', error: null })
  d.rpcs._branch_locker_door_no = () => ({ data: 8, error: null })
  const rows = [{ code_type: 'accessories', door_code: '4821', sent_to_customer: true, withheld_reason: null }]
  const gm = (await prepareGearMail(d, { bookingId: BID, renderType: 'booking_reserved', site: 'https://motogo24.com', payload: {}, doorCodeRows: rows }))!
  const de = gm.varsFor('de')
  const fb = gearFallbackRender(gm, 'de', de)
  eq(fb.lang, 'en')
  ok(fb.body.includes('3 days') && fb.body.includes('Full set without boots') && fb.body.includes('Locker room code (door no. 8)'), 'en vars')
  ok(!/Tage|Komplett|Umkleideraum/.test(fb.body), 'no German variables in the English text')
  ok(fb.body.includes('upravit-rezervaci?lang=de') && fb.vars.docs_url.endsWith('&docs=1&lang=de'), 'links stay in de')
  eq(fb.vars.door_codes_block, gm.varsFor('en').door_codes_block, 'vars returned = what the body was filled with')
  eq(gearFallbackRender(gm, 'cs', gm.varsFor('cs')).vars.gear_days, '3 dny', 'cs unchanged')
  eq([gearFallbackLang('cs'), gearFallbackLang('en'), gearFallbackLang('uk')], ['cs', 'en', 'en'])
  const v = { gear_days: '3 Tage', pay_url: 'P', x: 'keep' }
  eq(gearFallbackVars('de', v, () => ({ gear_days: '3 days', pay_url: 'EN' })), { gear_days: '3 days', pay_url: 'P', x: 'keep' })
  eq(gearFallbackVars('en', v, () => ({ gear_days: 'zz' })), v, 'en customer → same vars')
})

Deno.test('dovětek o vratce převodem: tykání ve všech 8 jazycích (žádný fallback na češtinu)', () => {
  const cs = gearTexts('cs').manualRefund
  ok(cs.includes('ti vrátíme') && cs.includes('14 dnů') && !/vám|váš/.test(cs), 'cs tykání')
  for (const l of ['en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']) {
    const t = gearTexts(l).manualRefund
    ok(t && t !== cs && t.includes('14'), `${l} note`)
  }
  ok(!/Ihr Konto|votre compte|uw rekening|ваш рахунок/.test(['de', 'fr', 'nl', 'uk'].map((l) => gearTexts(l).manualRefund).join(' ')), 'no formal forms')
})

Deno.test('prototypové klíče: constructor / toString nikdy nevrátí funkci', () => {
  eq([gearRenderType('constructor'), gearRenderType('toString'), gearRenderType('__proto__')], ['gear_constructor', 'gear_toString', 'gear___proto__'])
  eq(gearFallbackTemplate('constructor', 'cs').subject, gearFallbackTemplate('gear_unknown', 'cs').subject, 'generic text')
  eq(gearTexts('constructor'), gearTexts('cs'))
  ok(!Object.hasOwn(EMAIL_SLUG_FALLBACKS, 'constructor'), 'send-email: no substitute for prototype keys')
})

Deno.test('pásmo vratky storna = DB _refund_tier_pct: pražský čas vyzvednutí, ≥168 h / ≥48 h', () => {
  // Léto (CEST): web ukládá UTC půlnoc → pražský den 15. 6., vyzvednutí 09:00 = 07:00 UTC.
  const ref = refundTierRef('2026-06-15T00:00:00+00:00', '09:00:00')
  eq(new Date(ref).toISOString(), '2026-06-15T07:00:00.000Z')
  // Velín ukládá pražskou půlnoc (22:00 UTC předchozího dne) → stejný den.
  eq(refundTierRef('2026-06-14T22:00:00+00:00', '09:00'), ref, 'Prague midnight')
  eq(new Date(refundTierRef('2026-01-10', null)).toISOString(), '2026-01-10T08:00:00.000Z', 'winter, default 09:00')
  eq(new Date(pragueWallToMs('2026-03-29', '14:30')).toISOString(), '2026-03-29T12:30:00.000Z', 'DST day')
  const H = 3600000
  eq(refundTierPercent('2026-06-15T00:00:00+00:00', '09:00', ref - 168 * H), 100, 'exactly 168 h → 100 (≥)')
  eq(refundTierPercent('2026-06-15T00:00:00+00:00', '09:00', ref - 168 * H + 1), 50)
  eq(refundTierPercent('2026-06-15T00:00:00+00:00', '09:00', ref - 48 * H), 50, 'exactly 48 h → 50 (≥)')
  eq(refundTierPercent('2026-06-15T00:00:00+00:00', '09:00', ref - 48 * H + 1), 0)
  // Dřív (UTC půlnoc, >): 7 dní a 3 h před vyzvednutím v 09:00 vycházelo jen 50 %.
  eq(refundTierPercent('2026-06-15T00:00:00+00:00', '09:00', ref - (168 + 3) * H), 100)
  eq(refundTierPercent('nesmysl', '09:00'), 0, 'invalid date → 0 (as before)')
})
