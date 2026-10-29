// MotoGo24 — Velín → Dokumenty → E-mailové šablony: šablony pro VÝPŮJČKU VÝBAVY (bez motorky).
// Rezervace s bookings.booking_kind='gear' → edge send-booking-email vyrenderuje šablonu
// 'gear_' + <typ> (přednost má web_gear_<typ>), storno send-cancellation-email, protokol
// submit-handover-protocol → send-email (handover_protocol_gear_sent → fallback handover_protocol_sent).
// Seed: migrace 20261023d_gear_booking_templates.sql (CZ, tykání; ostatní jazyky překládá edge).
// Tady jen metadata karet (kategorie/spouštěč/popis) a ukázkové hodnoty pro náhled.

import { GEAR_PILL } from '../../lib/bookingKind'

// teal výbavy — stejné barvy jako štítek „JEN VÝBAVA“ v rezervacích (lib/bookingKind GEAR_PILL)
export const GEAR_CATEGORY = { value: 'gear', label: 'Půjčení výbavy', color: GEAR_PILL.color, bg: GEAR_PILL.bg }

const UNIVERSAL = 'Text musí sedět pro obslužnou pobočku (Mezná — převzetí s obsluhou, doklad se kontroluje na místě) '
  + 'i samoobslužnou (Velké Němčice — kódy, velikosti + podpis protokolu na displeji, potvrzení vrácení na displeji).'

const meta = (trigger, attachments, info) => ({ category: GEAR_CATEGORY.value, categoryLabel: GEAR_CATEGORY.label, trigger, attachments, info })

export const GEAR_TEMPLATE_META = {
  gear_booking_reserved: meta(
    'Po zaplacení výpůjčky výbavy, když je doklad totožnosti v pořádku (send-booking-email type=booking_reserved u rezervace výbavy)',
    'Smlouva (o nájmu výbavy), VOP',
    'Potvrzení výpůjčky výbavy bez motorky — místo booking_reserved. Příloha „Smlouva“ je u výbavy Smlouva o nájmu výbavy '
    + '(Smluvní texty → gear_rental_contract). Výbava {{gear_items_block}}, termín {{gear_period}} ({{gear_days}}), pobočka {{branch_name}}. '
    + 'Kódy vkládej jen přes {{door_codes_block}} (brána → šatna → postup; u obslužné pobočky a před uvolněním kódů prázdné). ' + UNIVERSAL,
  ),
  gear_invoice_payment_receipt: meta(
    'Po zaplacení výpůjčky výbavy, dokud chybí doklad totožnosti (Stripe webhook / potvrzení platby ve Velíně)',
    'ZF, DP',
    '„Platba přijata“ u výpůjčky výbavy — místo invoice_payment_receipt. Tlačítko „Nahrát doklad totožnosti“ ({{docs_url}} → '
    + '/pujceni-obleceni?resume=…&docs=1). U výbavy stačí občanka (obě strany) nebo pas a věk 18+, řidičák se nevyžaduje. '
    + 'Po doplnění dokladu následuje gear_booking_reserved.',
  ),
  gear_booking_missing_docs: meta(
    'Cron ~30 min po platbě, když u výpůjčky výbavy chybí doklad totožnosti (send_abandoned_booking_emails)',
    'Žádné',
    'Připomínka „zaplaceno, nahraj doklad totožnosti“ u výpůjčky výbavy — místo booking_missing_docs. Tlačítko {{docs_url}}. '
    + 'Bez ověřeného dokladu se kódy předem neposílají.',
  ),
  gear_booking_abandoned: meta(
    'Nedokončená platba výpůjčky výbavy (cron nedokončených rezervací)',
    'Žádné',
    'Výpůjčka výbavy čeká na zaplacení — místo booking_abandoned. Tlačítko „Dokončit platbu“ ({{pay_url}} / {{resume_link}} → '
    + '/pujceni-obleceni?resume=…).',
  ),
  gear_door_codes: meta(
    'Vydání / uvolnění kódu šatny (a brány) u výpůjčky výbavy na samoobslužné pobočce (DB send_door_codes_email → send-booking-email type=door_codes)',
    'Žádné',
    'Výpůjčka výbavy dostává JEN kód šatny (+ kód brány u pobočky s bránou), nikdy kód motorky. Kódy vkládej výhradně přes '
    + '{{door_codes_block}} — vykreslí bránu → šatnu č. X → postup (vezmi výbavu, zavři dveře, na displeji zkontroluj velikosti '
    + 'a podepiš protokol kódem šatny; při vrácení výbavu vrať do šatny, zavři a na displeji potvrď vrácení všeho).',
  ),
  gear_booking_modified: meta(
    'Změna výpůjčky výbavy — termín (posun / prodloužení / zkrácení), velikosti, odebraný kus (web, Velín)',
    'Žádné',
    'Úprava výpůjčky výbavy — místo booking_modified. Přehled změn vkládá {{changes_block}} (původní → nové). '
    + 'Aktuální výbava {{gear_items_block}}, termín {{gear_period}}, cena {{total_price}} Kč, správa rezervace {{manage_url}}.',
  ),
  gear_booking_cancelled: meta(
    'Storno výpůjčky výbavy (web, Velín) → send-cancellation-email',
    'Dobropis',
    'Potvrzení storna výpůjčky výbavy — místo booking_cancelled. Vratka {{refund_amount}} Kč ({{refund_percent}} %) dle storno '
    + 'podmínek, důvod {{cancellation_reason}}.',
  ),
  gear_booking_completed: meta(
    'Dokončení výpůjčky výbavy (potvrzení vrácení na displeji samoobslužné pobočky nebo převzetí zpět ve Velíně)',
    'KF (konečná faktura)',
    'Poděkování po vrácení výbavy + žádost o recenzi ({{google_review_url}}) — místo booking_completed. U výbavy se nevydává '
    + 'slevový kód na příští rezervaci ani věrnostní body.',
  ),
  handover_protocol_gear_sent: meta(
    'Podpis předávacího protokolu výbavy (displej samoobslužné pobočky / Velín) → submit-handover-protocol → send-email',
    'Předávací protokol (PDF/HTML v příloze)',
    'Kopie podepsaného předávacího protokolu výbavy (velikosti, stav, podpis) — samotný protokol jde v příloze. '
    + 'Když šablona chybí nebo je neaktivní, použije se handover_protocol_sent.',
  ),
}

export const GEAR_SLUGS = Object.keys(GEAR_TEMPLATE_META)

/**
 * Šablona výpůjčky výbavy (gear_*, web_gear_*, handover_protocol_gear_sent). NE legacy gear_rental_*
 * (render typ e-shop objednávky půjčení výbavy, send-booking-email gear_rental_confirmed — patří k objednávkám).
 */
export function isGearSlug(slug) {
  const s = String(slug || '').replace(/^web_/, '')
  return (s.startsWith('gear_') && !s.startsWith('gear_rental_')) || s === 'handover_protocol_gear_sent'
}

/** Metadata gear šablony (i web_ varianty a neznámého gear_* slugu), jinak null. */
export function gearTemplateMeta(slug) {
  if (!isGearSlug(slug)) return null
  const base = String(slug).replace(/^web_/, '')
  const m = GEAR_TEMPLATE_META[base]
  if (!m) return meta('—', '—', 'Šablona pro výpůjčku výbavy (rezervace bez motorky).')
  if (base === slug) return m
  return { ...m, info: `Web varianta ${base} — u rezervací z webu má přednost; když neexistuje, použije se ${base}. ${m.info}` }
}

/** Typ mailu pro send-booking-email: bez web_ a gear_ prefixu (edge gear pozná sám podle rezervace). */
export function emailTypeForSlug(slug) {
  return String(slug || '').replace(/^web_/, '').replace(/^gear_/, '')
}

// Ukázkové hodnoty pro náhled gear šablon (přepisují obecné SAMPLE_VARS). Edge je plní živě
// v jazyce zákazníka; tady CZ ukázka — samoobslužná pobočka, 4 dny, komplet s botami.
const S = 'https://www.motogo24.cz'
export const GEAR_SAMPLE_VARS = {
  branch_name: 'Velké Němčice', branch_address: 'Boudky, 691 63 Velké Němčice',
  start_date: '15. 6. 2026', end_date: '18. 6. 2026', gear_period: '15. 6. 2026 – 18. 6. 2026', gear_days: '4 dny',
  pickup_time: '10:00', return_time: '18:00', total_price: '3 560',
  gear_items_block: '<ul style="margin:0 0 14px;padding-left:20px"><li><strong>Komplet s botami</strong> — helma L, bunda XL, '
    + 'kalhoty XL, rukavice M, boty 43 · 890 Kč/den</li></ul>',
  door_codes_block: '<div style="background:#eaf7ea;border:1px solid #74FB71;border-radius:12px;padding:16px;margin:16px 0">'
    + '<strong>Přístupové kódy</strong><br>Brána (horní schránka, jen pobočka s bránou): <strong>135</strong> · Šatna (dveře č. 8): '
    + '<strong>5678</strong><br><span style="font-size:13px">Postup: brána → šatna č. 8 → vezmi výbavu a zavři dveře → na displeji '
    + 'zkontroluj velikosti a podepiš protokol kódem šatny. Vrácení: výbavu vrať do šatny, zavři dveře a na displeji potvrď vrácení.</span></div>',
  docs_url: `${S}/pujceni-obleceni?resume=abc123&docs=1`,
  pay_url: `${S}/pujceni-obleceni?resume=abc123`, resume_link: `${S}/pujceni-obleceni?resume=abc123`,
  manage_url: `${S}/upravit-rezervaci`, refund_amount: '3 560', refund_percent: '100',
  changes_block: '<table style="width:100%;border-collapse:collapse;margin:0 0 14px;font-size:14px">'
    + '<tr><td style="padding:6px 0;color:#6b7280">Termín</td><td style="text-align:right">15. 6. – 18. 6. 2026 → <strong>15. 6. – 19. 6. 2026</strong></td></tr>'
    + '<tr><td style="padding:6px 0;color:#6b7280">Bunda</td><td style="text-align:right">XL → <strong>L</strong></td></tr></table>',
  rental_period: '15. 6. 2026 – 18. 6. 2026', doc_name: 'Předávací protokol',
}

/** Ukázkové proměnné pro náhled podle slugu (gear šablony dostanou gear hodnoty). */
export function sampleVarsFor(slug, base) {
  return isGearSlug(slug) ? { ...base, ...GEAR_SAMPLE_VARS } : base
}
