// MotoGo24 — Velín → Flotila → Půjčení oblečení: sdílené konstanty a výpočty.
// Ceník = `gear_rental_prices` (Kč/den), nastavení = `app_settings.gear_rental` (migrace
// 20261022_gear_rental.sql) + `gear_stock_check` (20261023a, viz gearSettingsApi.js).
// Výpůjčky jsou od 20261023a rezervace (bookings.booking_kind='gear'); `gear_rentals` +
// `shop_orders` (RENTAL_STATUS/PAYMENT níže) už jen pro starší e-shopové objednávky.
import { supabase } from '../../lib/supabase'

export const KEY_RE = /^[a-z][a-z0-9_]{1,39}$/
export const SETTINGS_KEY = 'gear_rental'
export const DEFAULT_SETTINGS = { enabled: true, max_days: 30, max_ahead_days: 400 }
export const LANGS = ['en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']

export const RENTAL_STATUS = {
  reserved: { label: 'Rezervováno', color: '#7c3aed', bg: '#ede9fe' },
  picked_up: { label: 'Vydáno', color: '#2563eb', bg: '#dbeafe' },
  returned: { label: 'Vráceno', color: '#1a8a18', bg: '#dcfce7' },
  cancelled: { label: 'Zrušeno', color: '#dc2626', bg: '#fee2e2' },
}

export const PAYMENT = {
  pending: { label: 'Nezaplaceno', color: '#dc2626', bg: '#fee2e2' },
  paid: { label: 'Zaplaceno', color: '#1a8a18', bg: '#dcfce7' },
  refunded: { label: 'Vráceno', color: '#1a2e22', bg: '#f3f4f6' },
  failed: { label: 'Selhalo', color: '#dc2626', bg: '#fee2e2' },
}

export const INPUT = {
  padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0',
  color: '#0f1a14', borderRadius: 8, fontSize: 14, outline: 'none',
}

export function czk(n) {
  const v = Number(n) || 0
  return `${v.toLocaleString('cs-CZ', { maximumFractionDigits: 2 })} Kč`
}

export function daysLabel(n) {
  return n === 1 ? 'den' : n >= 2 && n <= 4 ? 'dny' : 'dní'
}

export function fmtDate(d) {
  if (!d) return '—'
  const [y, m, day] = String(d).slice(0, 10).split('-')
  return `${Number(day)}. ${Number(m)}. ${y}`
}

// Dnešek v Praze (stejně jako server: now() AT TIME ZONE 'Europe/Prague').
export function pragueToday() {
  return new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Prague' })
}

// "M, L ,xl,, L" → ['M','L','xl'] (bez prázdných a duplicit, pořadí zachováno)
export function parseSizes(text) {
  const out = []
  String(text || '').split(',').map(s => s.trim()).filter(Boolean).forEach(s => { if (!out.includes(s)) out.push(s) })
  return out
}

// Stejné pravidlo jako DB `_gear_rental_quote`: komplet se účtuje, když jsou
// vybrané VŠECHNY jeho kusy a je levnější než součet těchto kusů; jinak po kusech.
export function quote(prices, itemKeys) {
  const items = prices.filter(p => p.kind === 'item')
  const priceOf = k => Number(items.find(i => i.key === k)?.price_per_day) || 0
  let left = [...itemKeys]
  const lines = []
  const sets = prices.filter(p => p.kind === 'set' && p.is_active)
    .sort((a, b) => (b.includes?.length || 0) - (a.includes?.length || 0)
      || Number(a.price_per_day) - Number(b.price_per_day) || a.key.localeCompare(b.key))
  for (const s of sets) {
    const inc = s.includes || []
    if (!inc.every(k => left.includes(k))) continue
    const sum = inc.reduce((acc, k) => acc + priceOf(k), 0)
    if (Number(s.price_per_day) >= sum) continue
    lines.push({ key: s.key, kind: 'set', label: s.label, price_per_day: Number(s.price_per_day) })
    left = left.filter(k => !inc.includes(k))
  }
  items.filter(i => left.includes(i.key))
    .sort((a, b) => (a.sort_order || 0) - (b.sort_order || 0) || a.key.localeCompare(b.key))
    .forEach(i => lines.push({ key: i.key, kind: 'item', label: i.label, price_per_day: Number(i.price_per_day) }))
  const perDay = lines.reduce((acc, l) => acc + l.price_per_day, 0)
  return { lines, perDay }
}

// Součet Kč/den kusů kompletu (porovnání „vyplatí se komplet?“)
export function itemsSum(prices, keys) {
  return (keys || []).reduce((acc, k) => acc + (Number(prices.find(p => p.kind === 'item' && p.key === k)?.price_per_day) || 0), 0)
}

// admin_audit_log: JEN sloupce admin_id, action, entity_type, entity_id (uuid), old_data, new_data
// (žádný `details`). Klíč ceníku je text → jde do new_data/old_data, entity_id jen u uuid.
export async function audit(action, entityType, entityId, oldData, newData) {
  try {
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('admin_audit_log').insert({
      admin_id: user?.id, action, entity_type: entityType, entity_id: entityId || null,
      old_data: oldData || null, new_data: newData || null,
    })
  } catch { /* audit nesmí shodit akci */ }
}

export function Pill({ label, color, bg }) {
  return (
    <span className="inline-block rounded-btn text-xs font-extrabold tracking-wide uppercase whitespace-nowrap"
      style={{ padding: '3px 8px', color, background: bg }}>
      {label}
    </span>
  )
}
