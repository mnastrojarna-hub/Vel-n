// ===== _tests/gear_email_staffed_test.ts =====
// FIX-R1: výpůjčka výbavy na OBSLUŽNÉ pobočce — {{door_codes_block}} = „Kód výpůjčky“ + věta, že ho
// zákazník při převzetí nahlásí obsluze (8 jazyků, tykání); samoobsluha beze změny („Kód šatny“).
import { esc, renderGearDoorCodesBlock } from '../_shared/email-gear-blocks.ts'
import { GEAR_STAFFED_TEXTS, gearStaffedTexts } from '../_shared/email-gear-texts-staffed.ts'
import { buildGearChanges, type GearBooking } from '../_shared/email-gear.ts'

function ok(c: unknown, msg: string) { if (!c) throw new Error(msg) }
const LANGS = ['cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk'] as const
// slova „šatna / locker room / displej“ v jazycích zákazníků — u obslužné pobočky NESMÍ být
const LOCKER = /šatn|locker|Umkleide|kleedruimte|vestuario|vestiaire|szatn|роздягальн|displej|display|Display|pantalla|écran|scherm|wyświetlacz|дисплей/i

Deno.test('staffed: všech 8 jazyků má titulek, štítek a větu s {branch}', () => {
  for (const l of LANGS) {
    const t = GEAR_STAFFED_TEXTS[l]
    ok(t && t.title && t.label && t.hint.includes('{branch}') && t.hintNoBranch && !t.hintNoBranch.includes('{branch}'), `${l} texts`)
  }
  ok(gearStaffedTexts('xx') === GEAR_STAFFED_TEXTS.cs && gearStaffedTexts('constructor') === GEAR_STAFFED_TEXTS.cs, 'fallback cs')
  ok(!/ Sie |Ihnen|vous |uw |Pan |Pani |вас|Ви /.test(LANGS.map((l) => GEAR_STAFFED_TEXTS[l].hint).join(' ')), 'tykání (žádné vykání)')
})

Deno.test('staffed: blok = Kód výpůjčky + nahlásit obsluze na pobočce, bez šatny / displeje / postupu', () => {
  for (const l of LANGS) {
    const h = renderGearDoorCodesBlock(l, { code: '613284', selfService: false, branchName: 'Mezná' })
    const t = GEAR_STAFFED_TEXTS[l]
    ok(h.includes(`${esc(t.label)}: <span`) && h.includes('613284'), `${l} label + code`)
    ok(h.includes(esc(t.hint.split('{branch}').join('Mezná'))), `${l} hint with branch`)
    ok(h.includes(esc(t.title)), `${l} title`)
    ok(!LOCKER.test(h), `${l} no locker/display wording: ${h}`)
    ok(!h.includes('<ol') && !h.includes('<li'), `${l} no procedure`)
  }
  const cs = renderGearDoorCodesBlock('cs', { code: '613284', selfService: false, branchName: 'Mezná' })
  ok(cs.includes('Kód výpůjčky: <span') && cs.includes('Při převzetí ho nahlásíš obsluze na pobočce Mezná.'), 'cs exact wording')
  const noBranch = renderGearDoorCodesBlock('cs', { code: '1', selfService: false, branchName: '' })
  ok(noBranch.includes('Při převzetí ho nahlásíš obsluze na pobočce.') && !noBranch.includes('{branch}'), 'bez názvu pobočky')
  ok(renderGearDoorCodesBlock('cs', { code: '1', selfService: false, branchName: 'A<b>' }).includes('A&lt;b&gt;'), 'branch escaped')
  ok(renderGearDoorCodesBlock('cs', { code: '', selfService: false, branchName: 'Mezná' }) === '', 'bez vydaného kódu nic')
})

Deno.test('samoobsluha beze změny: Kód šatny (dveře č.) + platnost + postup', () => {
  const h = renderGearDoorCodesBlock('cs', { code: '4821', gate: '0937', lockerDoor: 8, selfService: true, branchName: 'Velké Němčice' })
  ok(h.includes('Kód šatny (dveře č. 8): <span') && h.includes('Kód šatny platí po dobu výpůjčky') && h.includes('<ol'), 'self-service text')
  ok(!h.includes('Kód výpůjčky') && !h.includes('obsluze'), 'no staffed wording on self-service')
})

// FIX-R1: přesun pobočky z Velínu (admin_update_gear_booking → changes.branch) = řádek „Pobočka“ v přehledu změn
const G: GearBooking = {
  id: '00000000-0000-0000-0000-0000abcd1234', status: 'reserved', paymentStatus: 'paid', start: '2026-11-10', end: '2026-11-12', days: 3,
  pickupTime: '10:00', returnTime: '18:00', totalPrice: 1200, lines: [], sizes: {}, labels: {},
  branch: { id: 'b2', name: 'Velké Němčice', address: '', city: '', type: 'samoobslužná' }, customerName: 'Eva',
}
const BASE = { original_start_date: '2026-11-10', original_end_date: '2026-11-12', original_total_price: 1200 }

Deno.test('changes_block: přesun pobočky = řádek Pobočka (8 jazyků), bez změny ceny / termínu jen ten řádek', () => {
  const LBL: Record<string, string> = { cs: 'Pobočka', en: 'Branch', de: 'Filiale', nl: 'Vestiging', es: 'Sucursal', fr: 'Agence', pl: 'Oddział', uk: 'Філія' }
  for (const l of LANGS) {
    const h = buildGearChanges(G, l, { ...BASE, changes: { branch: { from_id: 'b1', to_id: 'b2', from: 'Mezná', to: 'Velké Němčice' } } })
    ok(h.includes(`>${LBL[l]}</td>`) && h.includes('>Mezná</td>') && h.includes('>Velké Němčice</td>'), `${l} branch row: ${h}`)
    ok((h.match(/<tr>/g) || []).length === 3, `${l} jen titulek + hlavička + pobočka`)
  }
  const both = buildGearChanges(G, 'cs', { ...BASE, changes: { gear: { from: { helmet: 'M' }, to: { helmet: 'L' } }, branch: { from: 'A<b>', to: 'Velké Němčice' } } })
  ok(both.includes('>Výbava</td>') && both.includes('>Pobočka</td>') && both.includes('A&lt;b&gt;'), 'výbava + pobočka, escapováno')
  ok(buildGearChanges(G, 'cs', { ...BASE, changes: { branch: { from: 'Mezná', to: '' } } }).includes('>Velké Němčice</td>'), 'cíl z rezervace')
  ok(buildGearChanges(G, 'cs', { ...BASE }) === '', 'bez změn prázdné')
})
