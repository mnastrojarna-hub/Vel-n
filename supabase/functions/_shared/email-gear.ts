// Výpůjčka JEN výbavy jako rezervace (bookings.booking_kind='gear', 2026-10-23) — e-maily.
// send-booking-email / send-cancellation-email: když je rezervace gear, tělo + předmět jdou
// z Velín šablony `gear_<typ>` (renderType; web_ varianta má přednost), NIKDY z motorkové
// šablony / textu. Logovaný slug zůstává dle `type` (dedup cronů/triggerů). Proměnné níže =
// kontrakt DESIGN-GEAR §3.3 (seed šablon 20261023d), v jazyce zákazníka, HTML-escapované.
import {
  daysLabel, esc, fmtDay, gearItemsText, gearTexts, kc, renderGearChangesBlock, renderGearItemsBlock,
  type GearLabels, type GearLine,
} from './email-gear-blocks.ts'

// deno-lint-ignore no-explicit-any
type Db = any

/** Typ mailu → gear šablona. Zbytek 'gear_' + typ (bez šablony → gear fallback, ne motorka). */
export const GEAR_RENDER_TYPES: Record<string, string> = {
  booking_reserved: 'gear_booking_reserved',
  invoice_payment_receipt: 'gear_invoice_payment_receipt',
  booking_missing_docs: 'gear_booking_missing_docs',
  booking_abandoned: 'gear_booking_abandoned',
  booking_abandoned_full: 'gear_booking_abandoned', // u výbavy chybí jen doklad totožnosti
  door_codes: 'gear_door_codes',
  booking_modified: 'gear_booking_modified',
  booking_cancelled: 'gear_booking_cancelled',
  booking_completed: 'gear_booking_completed',
}
export function gearRenderType(t: string): string {
  return GEAR_RENDER_TYPES[t] || (t.startsWith('gear_') ? t : 'gear_' + t)
}
/** Přílohy, když gear šablona ve Velínu chybí (= výchozí hodnoty seedu 20261023d). */
export const GEAR_DEFAULT_ATTACHMENTS: Record<string, string[]> = {
  gear_booking_reserved: ['Smlouva', 'VOP'],
  gear_invoice_payment_receipt: ['ZF', 'DP'],
  gear_booking_cancelled: ['Dobropis'],
  gear_booking_completed: ['KF'],
}

const SIZE_KEYS = ['helmet', 'jacket', 'pants', 'gloves', 'boots'] as const
export interface GearBooking {
  id: string; status: string; paymentStatus: string
  start: string; end: string; days: number // Praha, 'YYYY-MM-DD', včetně obou krajních dnů
  pickupTime: string; returnTime: string; totalPrice: number
  lines: GearLine[]; sizes: Record<string, string | null>; labels: GearLabels
  branch: { id: string; name: string; address: string; city: string; type: string } | null
  customerName: string
}

/** Datum (timestamptz i 'YYYY-MM-DD') → den v Praze 'YYYY-MM-DD' (web ukládá UTC půlnoc, Velín pražskou). */
export function pragueDay(v: unknown): string {
  const s = String(v || '')
  if (!s) return ''
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s
  const d = new Date(s)
  if (Number.isNaN(d.getTime())) return s.slice(0, 10)
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Prague', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d)
}
const hhmm = (v: unknown) => { const m = /^(\d{1,2}):(\d{2})/.exec(String(v || '')); return m ? `${m[1].padStart(2, '0')}:${m[2]}` : '' }
const dayDiff = (a: string, b: string) => Math.round((Date.parse(b + 'T00:00:00Z') - Date.parse(a + 'T00:00:00Z')) / 86400000)

/** Načte gear rezervaci; null = není gear (nebo DB bez sloupců booking_kind → motorkový mail beze změny). */
export async function loadGearBooking(supabase: Db, bookingId: string): Promise<GearBooking | null> {
  if (!bookingId) return null
  try {
    const { data: b, error } = await supabase.from('bookings')
      .select('id, booking_kind, status, payment_status, user_id, start_date, end_date, pickup_time, return_time, total_price, gear_lines, branch_id, helmet_size, jacket_size, pants_size, gloves_size, boots_size')
      .eq('id', bookingId).maybeSingle()
    if (error || !b || b.booking_kind !== 'gear') return null
    const g: GearBooking = {
      id: String(b.id), status: String(b.status || ''), paymentStatus: String(b.payment_status || ''),
      start: pragueDay(b.start_date), end: pragueDay(b.end_date), days: 1,
      pickupTime: hhmm(b.pickup_time), returnTime: hhmm(b.return_time), totalPrice: Number(b.total_price) || 0,
      lines: Array.isArray(b.gear_lines) ? b.gear_lines as GearLine[] : [],
      sizes: Object.fromEntries(SIZE_KEYS.map((k) => [k, b[`${k}_size`] ? String(b[`${k}_size`]) : null])),
      labels: {}, branch: null, customerName: '',
    }
    g.days = Math.max(1, dayDiff(g.start, g.end) + 1)
    // Gear už je jisté — dílčí výpadek níže mail nepřepne na motorku, jen chybí údaj.
    try {
      const { data: br } = await supabase.from('branches').select('id, name, address, city, type').eq('id', b.branch_id).maybeSingle()
      if (br) g.branch = { id: String(br.id), name: String(br.name || ''), address: String(br.address || ''), city: String(br.city || ''), type: String(br.type || '') }
    } catch { /* bez pobočky */ }
    try {
      const { data: pr } = await supabase.from('gear_rental_prices').select('key, label, translations')
      for (const p of (pr || []) as Array<{ key: string; label: string; translations?: Record<string, { label?: string }> }>) {
        g.labels[p.key] = { cs: p.label }
        for (const [l, v] of Object.entries(p.translations || {})) if (v?.label) g.labels[p.key][l] = v.label
      }
    } catch { /* label z řádku gear_lines */ }
    if (b.user_id) {
      try {
        const { data: pf } = await supabase.from('profiles').select('full_name').eq('id', b.user_id).maybeSingle()
        g.customerName = String(pf?.full_name || '')
      } catch { /* jméno z payloadu */ }
    }
    return g
  } catch {
    return null
  }
}

/** Odkazy výpůjčky (web /pujceni-obleceni); cizí jazyk = ?lang (web lokalizuje slug sám, 301 se zachovaným dotazem). */
export function gearLinks(g: GearBooking, lang: string, site: string) {
  const base = site.replace(/\/+$/, '')
  const q = lang === 'cs' ? '' : `&lang=${lang}`
  const pay = `${base}/pujceni-obleceni?resume=${g.id}${q}`
  return { pay, docs: `${base}/pujceni-obleceni?resume=${g.id}&docs=1${q}`, manage: `${base}/upravit-rezervaci${lang === 'cs' ? '' : `?lang=${lang}`}`, base }
}

type Payload = Record<string, unknown>
const fmtPrice = (n: number) => (Number(n) || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 0 })

/** {{changes_block}} z payloadu triggeru úpravy (original_* vs. nový stav) + `changes.gear.{from,to}` z RPC. */
export function buildGearChanges(g: GearBooking, lang: string, p: Payload): string {
  const t = gearTexts(lang)
  const rows: Array<[string, string, string]> = []
  const os = pragueDay(p.original_start_date), oe = pragueDay(p.original_end_date)
  if (os && oe) rows.push([t.chPeriod, `${fmtDay(os, lang)} – ${fmtDay(oe, lang)}`, `${fmtDay(g.start, lang)} – ${fmtDay(g.end, lang)}`])
  if (p.original_pickup_time !== undefined) rows.push([t.chPickup, hhmm(p.original_pickup_time), hhmm(p.pickup_time) || g.pickupTime])
  if (p.original_return_time !== undefined) rows.push([t.chReturn, hhmm(p.original_return_time), hhmm(p.return_time) || g.returnTime])
  const ch = (p.changes && typeof p.changes === 'object' ? (p.changes as Payload).gear : null) as Payload | null
  if (ch && (ch.from !== undefined || ch.to !== undefined)) {
    rows.push([t.chItems, gearItemsText(ch.from, g.labels, lang), gearItemsText(ch.to, g.labels, lang)])
  }
  if (p.original_total_price != null && p.original_total_price !== '') {
    rows.push([t.chTotal, kc(Number(p.original_total_price)), kc(g.totalPrice)])
  }
  return renderGearChangesBlock(lang, rows)
}

export interface GearVarsOpts { site: string; customerName?: string; payload?: Payload }

/** Proměnné gear šablon (bez {{door_codes_block}} — ten skládá send-booking-email/gear-booking.ts). */
export function buildGearVars(g: GearBooking, lang: string, o: GearVarsOpts): Record<string, string> {
  const l = gearLinks(g, lang, o.site)
  const br = g.branch
  return {
    customer_name: esc(o.customerName || g.customerName),
    booking_number: g.id.slice(-8).toUpperCase(),
    branch_name: esc(br?.name || ''),
    branch_address: esc([br?.address, br?.city].filter(Boolean).join(', ')),
    gear_period: `${fmtDay(g.start, lang)} – ${fmtDay(g.end, lang)}`,
    gear_days: daysLabel(lang, g.days),
    start_date: fmtDay(g.start, lang),
    end_date: fmtDay(g.end, lang),
    pickup_time: g.pickupTime,
    return_time: g.returnTime,
    gear_items_block: renderGearItemsBlock(g.lines, g.labels, lang, g.sizes),
    total_price: fmtPrice(g.totalPrice),
    docs_url: l.docs,
    pay_url: l.pay,
    resume_link: l.pay,
    manage_url: l.manage,
    site_url: l.base,
    changes_block: o.payload ? buildGearChanges(g, lang, o.payload) : '',
  }
}

/** Předmět = čistý text: bez HTML bloků (kód brány nikdy do předmětu), jména bez escapování. */
export function gearSubjectVars(v: Record<string, string>, g: GearBooking, customerName?: string): Record<string, string> {
  return {
    ...v, door_codes_block: '', gate_codes_block: '', gear_items_block: '', changes_block: '',
    customer_name: customerName || g.customerName, branch_name: g.branch?.name || '',
    branch_address: [g.branch?.address, g.branch?.city].filter(Boolean).join(', '),
  }
}

/** Důvod storna pro šablonu (escapovaný). Prázdný / systémové české texty → v jazyce zákazníka. */
export function gearCancellationReason(reason: unknown, lang: string): string {
  const r = String(reason || '').trim()
  const t = gearTexts(lang)
  if (!r || r === 'Neuvedeno') return esc(t.notSpecified)
  if (r === 'Stornováno zákazníkem') return esc(t.byCustomer)
  return esc(r)
}
