// Předávací protokol výpůjčky JEN výbavy (booking_kind 'gear') z Velína — kontroly, texty dokumentu
// v 8 jazycích (cs + en, de, es, fr, nl, pl, uk; dvojjazyčně „jazyk zákazníka / česky“ jako protocolI18n.js)
// a proměnné e-mailu `handover_protocol_gear_sent` (send-email při 404 padá na handover_protocol_sent).
// Bez motocyklu: žádný Motocykl/SPZ/VIN, km, motorkové kontroly ani doplňkové vybavení;
// identita = kód ŠATNY téže rezervace; aspoň jeden kus musí zůstat (jinak by zanikl kód šatny).
import { makeProtocolTr, protocolLang, esc } from './protocolI18n'
import { PROTO_A } from './protocolI18nA'
import { PROTO_B } from './protocolI18nB'
import { GEAR_LABELS, gearItems } from '../../lib/bookingKind'
import { effBranch } from '../../lib/bookingBranch'
import { rentalDays } from '../../lib/rentalDays'

export const GEAR_HANDOVER_CHECKS = [
  { key: 'gear_condition', label: 'Výbava předána čistá, kompletní a bez poškození' },
  { key: 'gear_fit', label: 'Velikosti vyzkoušeny a odpovídají' },
  { key: 'gear_return', label: 'Nájemce poučen o vrácení (termín, pobočka, šatna)' },
]

const CS = {
  gHeading: 'PŘEDÁVACÍ PROTOKOL — ZAPŮJČENÁ VÝBAVA', gParties: 'Smluvní strany a předmět nájmu', gSubject: 'Předmět nájmu',
  gSubjectVal: 'Motorkářská výbava (bez motocyklu)', gBranch: 'Pobočka', gIdentity: 'Ověření identity (kód šatny)',
  gPickedAt: 'Převzato', gAccTitle: 'Zapůjčená výbava', gDamageAt: 'Poškození výbavy při předání',
  chk_gear_condition: GEAR_HANDOVER_CHECKS[0].label, chk_gear_fit: GEAR_HANDOVER_CHECKS[1].label, chk_gear_return: GEAR_HANDOVER_CHECKS[2].label,
}
const FX = {
  en: { gHeading: 'HANDOVER PROTOCOL — RENTED GEAR', gParties: 'Contracting parties and subject of rental', gSubject: 'Subject of rental', gSubjectVal: 'Motorcycle gear (without motorcycle)', gBranch: 'Branch', gIdentity: 'Identity check (locker code)', gPickedAt: 'Picked up', gAccTitle: 'Rented gear', gDamageAt: 'Damage to the gear at handover', chk_gear_condition: 'Gear handed over clean, complete and undamaged', chk_gear_fit: 'Sizes tried on and fitting', chk_gear_return: 'Renter instructed on the return (date, branch, locker)' },
  de: { gHeading: 'ÜBERGABEPROTOKOLL — GELIEHENE AUSRÜSTUNG', gParties: 'Vertragsparteien und Mietgegenstand', gSubject: 'Mietgegenstand', gSubjectVal: 'Motorradausrüstung (ohne Motorrad)', gBranch: 'Filiale', gIdentity: 'Identitätsprüfung (Spind-Code)', gPickedAt: 'Übernommen', gAccTitle: 'Geliehene Ausrüstung', gDamageAt: 'Schäden an der Ausrüstung bei Übergabe', chk_gear_condition: 'Ausrüstung sauber, vollständig und unbeschädigt übergeben', chk_gear_fit: 'Größen anprobiert und passend', chk_gear_return: 'Mieter über die Rückgabe belehrt (Termin, Filiale, Spind)' },
  es: { gHeading: 'PROTOCOLO DE ENTREGA — EQUIPAMIENTO ALQUILADO', gParties: 'Partes contratantes y objeto del alquiler', gSubject: 'Objeto del alquiler', gSubjectVal: 'Equipamiento de motorista (sin moto)', gBranch: 'Sucursal', gIdentity: 'Verificación de identidad (código de la taquilla)', gPickedAt: 'Recogido', gAccTitle: 'Equipamiento alquilado', gDamageAt: 'Daños en el equipamiento en la entrega', chk_gear_condition: 'Equipamiento entregado limpio, completo y sin daños', chk_gear_fit: 'Tallas probadas y adecuadas', chk_gear_return: 'Arrendatario informado sobre la devolución (fecha, sucursal, taquilla)' },
  fr: { gHeading: 'PROCÈS-VERBAL DE REMISE — ÉQUIPEMENT LOUÉ', gParties: 'Parties contractantes et objet de la location', gSubject: 'Objet de la location', gSubjectVal: 'Équipement moto (sans moto)', gBranch: 'Agence', gIdentity: "Vérification d'identité (code du casier)", gPickedAt: 'Retiré', gAccTitle: 'Équipement loué', gDamageAt: "Dommages sur l'équipement lors de la remise", chk_gear_condition: 'Équipement remis propre, complet et sans dommage', chk_gear_fit: 'Tailles essayées et adaptées', chk_gear_return: 'Locataire informé du retour (date, agence, casier)' },
  nl: { gHeading: 'OVERDRACHTSPROTOCOL — GEHUURDE UITRUSTING', gParties: 'Contractpartijen en huurobject', gSubject: 'Huurobject', gSubjectVal: 'Motoruitrusting (zonder motor)', gBranch: 'Vestiging', gIdentity: 'Identiteitscontrole (kluiscode)', gPickedAt: 'Opgehaald', gAccTitle: 'Gehuurde uitrusting', gDamageAt: 'Schade aan de uitrusting bij overdracht', chk_gear_condition: 'Uitrusting schoon, compleet en onbeschadigd overgedragen', chk_gear_fit: 'Maten gepast en passend', chk_gear_return: 'Huurder geïnstrueerd over het terugbrengen (datum, vestiging, kluis)' },
  pl: { gHeading: 'PROTOKÓŁ PRZEKAZANIA — WYPOŻYCZONY SPRZĘT', gParties: 'Strony umowy i przedmiot najmu', gSubject: 'Przedmiot najmu', gSubjectVal: 'Odzież i sprzęt motocyklowy (bez motocykla)', gBranch: 'Oddział', gIdentity: 'Weryfikacja tożsamości (kod szafki)', gPickedAt: 'Odebrano', gAccTitle: 'Wypożyczony sprzęt', gDamageAt: 'Uszkodzenia sprzętu przy przekazaniu', chk_gear_condition: 'Sprzęt przekazany czysty, kompletny i nieuszkodzony', chk_gear_fit: 'Rozmiary przymierzone i pasują', chk_gear_return: 'Najemca poinformowany o zwrocie (termin, oddział, szafka)' },
  uk: { gHeading: 'ПРОТОКОЛ ПЕРЕДАННЯ — ОРЕНДОВАНЕ СПОРЯДЖЕННЯ', gParties: 'Сторони договору та предмет оренди', gSubject: 'Предмет оренди', gSubjectVal: 'Мотоекіпірування (без мотоцикла)', gBranch: 'Філія', gIdentity: 'Перевірка особи (код шафки)', gPickedAt: 'Отримано', gAccTitle: 'Орендоване спорядження', gDamageAt: 'Пошкодження спорядження під час передання', chk_gear_condition: 'Спорядження передано чистим, комплектним і без пошкоджень', chk_gear_fit: 'Розміри приміряно, підходять', chk_gear_return: 'Орендаря поінформовано про повернення (термін, філія, шафка)' },
}
const BASE_FX = { ...PROTO_A, ...PROTO_B }

/** Překladač: base = makeProtocolTr (sdílené popisky), g(key) = gear popisky, item(key) = název kusu bez „(řidič)“. */
export function makeGearTr(rawLang) {
  const base = makeProtocolTr(protocolLang(rawLang))
  const fx = base.bilingual ? FX[base.lang] : null
  const fxBase = base.bilingual ? BASE_FX[base.lang] : null
  const both = (f, cz, block) => (!fx ? cz : block ? `${f}<br><span lang="cs" style="color:#666">${cz}</span>` : `${f}<span lang="cs" style="color:#666"> / ${cz}</span>`)
  return {
    base,
    g: (key, block = false) => both(esc(fx?.[key] ?? CS[key]), esc(CS[key]), block),
    gplain: (key) => (fx ? `${fx[key] ?? CS[key]} / ${CS[key]}` : CS[key]),
    item: (key, czLabel) => both(esc(fxBase?.['g_' + key] ?? czLabel), esc(czLabel), false),
  }
}

// ── E-mail handover_protocol_gear_sent: proměnné z DESIGN §3.3 (hodnoty escapované, send-email je vkládá syrově)
const SITE = 'https://motogo24.cz'
function daysText(n, lang) {
  const l = protocolLang(lang)
  if (l === 'cs') return `${n} ${n === 1 ? 'den' : n >= 2 && n <= 4 ? 'dny' : 'dní'}`
  if (l === 'pl') return `${n} ${n === 1 ? 'dzień' : 'dni'}`
  if (l === 'uk') { const d = n % 10, h = n % 100; return `${n} ${d === 1 && h !== 11 ? 'день' : d >= 2 && d <= 4 && (h < 12 || h > 14) ? 'дні' : 'днів'}` }
  const W = { en: ['day', 'days'], de: ['Tag', 'Tage'], es: ['día', 'días'], fr: ['jour', 'jours'], nl: ['dag', 'dagen'] }[l] || ['day', 'days']
  return `${n} ${n === 1 ? W[0] : W[1]}`
}
function fmtD(d) {
  const s = String(d || '').slice(0, 10)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return ''
  const [y, m, day] = s.split('-')
  return `${Number(day)}. ${Number(m)}. ${y}`
}

/** Proměnné šablony protokolu výbavy pro send-email (jazyk = bookings.language). */
export function gearProtocolEmailVars(booking, rawLang) {
  const lang = protocolLang(rawLang)
  const fxBase = lang !== 'cs' ? BASE_FX[lang] : null
  const br = effBranch(booking) || {}
  const days = rentalDays(booking?.start_date, booking?.end_date) || 1
  const items = gearItems(booking)
  const li = items.map(i => `<li>${esc(fxBase?.['g_' + i.key] || GEAR_LABELS[i.key])} — ${esc(i.size)}</li>`).join('')
  return {
    branch_name: esc(br.name || ''),
    branch_address: esc([br.address, [br.zip, br.city].filter(Boolean).join(' ')].filter(Boolean).join(', ')),
    gear_period: `${fmtD(booking?.start_date)} – ${fmtD(booking?.end_date)}`,
    gear_days: esc(daysText(days, lang)),
    start_date: fmtD(booking?.start_date), end_date: fmtD(booking?.end_date),
    pickup_time: esc(String(booking?.pickup_time || '').slice(0, 5)), return_time: esc(String(booking?.return_time || '').slice(0, 5)),
    gear_items_block: li ? `<ul style="margin:6px 0;padding-left:20px">${li}</ul>` : '',
    total_price: (Number(booking?.total_price) || 0).toLocaleString('cs-CZ'),
    site_url: SITE, manage_url: `${SITE}/upravit-rezervaci`,
  }
}
