// Výpůjčka JEN výbavy (bookings.booking_kind='gear', 2026-10-23) — HTML bloky proměnných
// e-mailových šablon (Velín email_templates gear_*): {{gear_items_block}}, {{door_codes_block}}
// (jen šatna + brána + postup na displeji; NIKDY „Kód motorky“) a {{changes_block}}.
// Bloky se skládají AŽ PO AI překladu šablony v jazyce zákazníka — kód brány se tak nikdy
// nedostane do podkladů pro překlad ani do předmětu. Všechny hodnoty se HTML-escapují.
import { GEAR_TEXTS_A } from './email-gear-texts-a.ts'
import { GEAR_TEXTS_B } from './email-gear-texts-b.ts'
import { gearStaffedTexts } from './email-gear-texts-staffed.ts'

export type GearLang = 'cs' | 'en' | 'de' | 'nl' | 'es' | 'fr' | 'pl' | 'uk'
export type GearTexts = {
  days: [string, string, string]; perDay: string
  codesTitle: string; gateLabel: string; gateHint: string; lockerLabel: string; lockerLabelDoor: string
  valid: string; procTitle: string; stepGate: string; stepLocker: string
  stepLockerDoor: string; stepProtocol: string; stepReturn: string; stepImportant: string; pageLink: string
  chTitle: string; chOld: string; chNew: string; chPeriod: string; chPickup: string; chReturn: string
  chItems: string; chTotal: string; chBranch: string; notSpecified: string; byCustomer: string
  /** Dovětek storna: vratka převodem na účet (bez platby kartou), tykání. */
  manualRefund: string
}
/** Naceněný řádek bookings.gear_lines (tvar _gear_rental_quote().lines). */
export type GearLine = { key: string; kind?: string; label?: string; sizes?: Record<string, string | null>; price_per_day?: number }
/** key → { cs: label, <lang>: label } z gear_rental_prices (label + translations). */
export type GearLabels = Record<string, Record<string, string>>

const TEXTS: Record<string, GearTexts> = { ...GEAR_TEXTS_A, ...GEAR_TEXTS_B }
export function gearTexts(lang: string): GearTexts { return Object.hasOwn(TEXTS, lang) ? TEXTS[lang] : TEXTS.cs }

const LOCALE: Record<string, string> = { cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', nl: 'nl-NL', es: 'es-ES', fr: 'fr-FR', pl: 'pl-PL', uk: 'uk-UA' }
export const esc = (s: unknown) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
export const kc = (n: number) => `${Math.round(Number(n) || 0).toLocaleString('cs-CZ')} Kč`

/** 'YYYY-MM-DD' → datum v jazyce zákazníka (cs „15. 6. 2026“). */
export function fmtDay(iso: string, lang: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '')
  if (!m) return ''
  try {
    return new Intl.DateTimeFormat(LOCALE[lang] || 'cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric', timeZone: 'UTC' })
      .format(new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], 12)))
  } catch { return iso.slice(0, 10) }
}

/** Počet dní s českým / polským / ukrajinským skloňováním („1 den“, „3 dny“, „5 dní“). */
export function daysLabel(lang: string, n: number): string {
  const f = gearTexts(lang).days
  let i = n === 1 ? 0 : 2
  if (lang === 'cs') i = n === 1 ? 0 : n >= 2 && n <= 4 ? 1 : 2
  else if (lang === 'pl') i = n === 1 ? 0 : 1
  else if (lang === 'uk') {
    const a = n % 10, b = n % 100
    i = a === 1 && b !== 11 ? 0 : a >= 2 && a <= 4 && (b < 12 || b > 14) ? 1 : 2
  }
  return f[i].split('{n}').join(String(n))
}

const labelOf = (labels: GearLabels, key: string, lang: string, fb = '') => labels[key]?.[lang] || labels[key]?.cs || fb || key
// Názvy kusů v kompletu malým písmenem („helma M“) — němčina má podstatná jména velkým.
const lower = (s: string, lang: string) => lang === 'de' ? s : s.toLocaleLowerCase(LOCALE[lang] || 'cs-CZ')

/** Velikosti řádku: komplet „helma M, bunda L“, kus jen „M“. `cur` = aktuální sloupce *_size rezervace. */
function lineSizes(l: GearLine, labels: GearLabels, lang: string, cur: Record<string, string | null>): string {
  return Object.entries(l.sizes || {}).map(([k, v]) => [k, cur[k] || v] as const).filter(([, v]) => v)
    .map(([k, v]) => l.kind === 'set' ? `${lower(labelOf(labels, k, lang), lang)} ${v}` : String(v)).join(', ')
}

/** {{gear_items_block}} — <ul> kusů/kompletů s velikostmi a cenou za den. */
export function renderGearItemsBlock(lines: GearLine[], labels: GearLabels, lang: string, cur: Record<string, string | null> = {}): string {
  const t = gearTexts(lang)
  if (!lines.length) return ''
  return '<ul style="margin:6px 0 0;padding-left:18px">' + lines.map((l) => {
    const sizes = lineSizes(l, labels, lang, cur)
    return `<li style="margin:2px 0"><strong>${esc(labelOf(labels, l.key, lang, l.label))}</strong>${sizes ? ` — ${esc(sizes)}` : ''}` +
      (l.price_per_day != null ? ` <span style="color:#6b7280">(${kc(Number(l.price_per_day))}${t.perDay})</span>` : '') + '</li>'
  }).join('') + '</ul>'
}

/** Čitelný text výbavy pro přehled změn — řádky gear_lines, [{key,size}] nebo {key: size}. */
export function gearItemsText(x: unknown, labels: GearLabels, lang: string): string {
  if (typeof x === 'string') return x
  if (Array.isArray(x)) {
    return x.map((it) => {
      const o = (it || {}) as GearLine & { size?: string | null }
      if (o.sizes && typeof o.sizes === 'object') {
        const s = lineSizes(o, labels, lang, {})
        const name = labelOf(labels, o.key, lang, o.label)
        return o.kind === 'set' ? (s ? `${name} (${s})` : name) : (s ? `${name} ${s}` : name)
      }
      return [labelOf(labels, String(o.key || ''), lang, o.label), o.size || ''].filter(Boolean).join(' ')
    }).filter(Boolean).join(', ')
  }
  if (x && typeof x === 'object') {
    return Object.entries(x as Record<string, unknown>).filter(([, v]) => v)
      .map(([k, v]) => `${labelOf(labels, k, lang)} ${v}`).join(', ')
  }
  return ''
}

export interface GearCodesOpts { code: string; gate?: string; lockerDoor?: number | null; selfService: boolean; branchName: string; pageUrl?: string }

/** {{door_codes_block}} výpůjčky výbavy: brána → šatna (+ postup na displeji). '' bez vydaného kódu.
 *  Obslužná pobočka (selfService=false, FIX-R1): „Kód výpůjčky“ + věta, že ho zákazník nahlásí obsluze. */
export function renderGearDoorCodesBlock(lang: string, o: GearCodesOpts): string {
  if (!o.code) return ''
  const t = gearTexts(lang)
  const st = o.selfService ? null : gearStaffedTexts(lang)
  const line = (label: string, code: string) =>
    `<p style="margin:4px 0;font-size:14px;font-weight:700;font-family:'Courier New',monospace;color:#0c4a6e">${esc(label)}: <span style="font-size:18px;letter-spacing:3px;color:#0369a1">${esc(code)}</span></p>`
  const door = o.lockerDoor != null && Number.isFinite(Number(o.lockerDoor)) ? String(o.lockerDoor) : ''
  const codeLabel = st ? st.label : door ? t.lockerLabelDoor.split('{n}').join(door) : t.lockerLabel
  const note = st ? (o.branchName ? st.hint.split('{branch}').join(o.branchName) : st.hintNoBranch) : t.valid
  const box = `
<div style="background:#e0f2fe;border-radius:12px;padding:16px 20px;margin:20px 0;border:1px solid #7dd3fc">
  <h3 style="margin:0 0 12px 0;color:#0c4a6e;font-size:15px">${esc(st ? st.title : t.codesTitle)}</h3>${o.gate ? `
  ${line(t.gateLabel, o.gate)}
  <p style="margin:0 0 8px 0;font-size:12px;color:#075985">${esc(t.gateHint)}</p>` : ''}
  ${line(codeLabel, o.code)}
  <p style="margin:8px 0 0 0;font-size:12px;color:#075985">${esc(note)}</p>
</div>`
  if (!o.selfService) return box
  const gateHtml = `<strong style="font-family:'Courier New',monospace;font-size:15px;letter-spacing:2px;color:#0369a1">${esc(o.gate || '')}</strong>`
  const steps: string[] = []
  if (o.gate) steps.push(esc(t.stepGate).split('{gate}').join(gateHtml))
  steps.push(door ? esc(t.stepLockerDoor).split('{n}').join(door) : esc(t.stepLocker))
  steps.push(esc(t.stepProtocol), esc(t.stepReturn))
  const important = o.gate
    ? `\n    <li style="margin:4px 0 0 0;padding:10px 12px;background:#fff7ed;border:1px solid #fdba74;border-left:4px solid #ea580c;border-radius:8px;color:#7c2d12;font-weight:700">${esc(t.stepImportant)}</li>`
    : ''
  return box + `
<div style="background:#f0faf5;border:1px solid #d4e8e0;border-left:4px solid #74fb71;border-radius:12px;padding:16px 20px;margin:20px 0">
  <h3 style="margin:0 0 10px 0;color:#1a2e22;font-size:15px">${esc(t.procTitle.split('{branch}').join(o.branchName))}</h3>
  <ol style="margin:0;padding:0 0 0 20px;font-size:13px;line-height:1.55;color:#1a2e22">
${steps.map((s) => `    <li style="margin:0 0 8px 0">${s}</li>`).join('\n')}${important}
  </ol>${o.pageUrl ? `
  <p style="margin:12px 0 0 0;font-size:13px"><a href="${esc(o.pageUrl)}" style="color:#2563eb;font-weight:700">${esc(t.pageLink)}</a></p>` : ''}
</div>`
}

/** {{changes_block}} — tabulka „Původně / Nově“ jen se změněnými řádky ('' bez změn). */
export function renderGearChangesBlock(lang: string, rows: Array<[string, string, string]>): string {
  const t = gearTexts(lang)
  const changed = rows.filter(([, a, b]) => (a || b) && a !== b)
  if (!changed.length) return ''
  const td = 'padding:8px 12px;border-bottom:1px solid #e5e7eb;font-size:13px'
  return `
<table style="width:100%;border-collapse:collapse;margin:16px 0;background:#f9fafb;border-radius:8px">
  <tr><th colspan="3" style="text-align:left;padding:10px 12px;font-size:14px;color:#0f1a14">${esc(t.chTitle)}</th></tr>
  <tr><td style="${td};color:#6b7280"></td><td style="${td};color:#6b7280">${esc(t.chOld)}</td><td style="${td};color:#6b7280">${esc(t.chNew)}</td></tr>
${changed.map(([l, a, b]) => `  <tr><td style="${td};color:#6b7280">${esc(l)}</td><td style="${td};color:#9ca3af;text-decoration:line-through">${esc(a || '—')}</td><td style="${td};color:#16a34a;font-weight:700">${esc(b || '—')}</td></tr>`).join('\n')}
</table>`
}
