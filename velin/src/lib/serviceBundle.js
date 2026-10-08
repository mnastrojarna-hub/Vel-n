import { supabase } from './supabase'
import { TASK_BY_ID } from '../components/fleet/serviceCatalog'
import { todayIso, audit } from './serviceBook'

// Sdružování servisních úkonů (zadání majitele: „servisy sdružovat, dělat najednou, ne po drobkách“).
// Z hlídání intervalů (get_service_due) sestaví doporučený SPOLEČNÝ servis: vše po termínu + blížící se
// + úkony, které dozrají krátce po nich (okno km / dní), s navrženým termínem a km.
export const BUNDLE_KM_WINDOW = 2000      // úkony dozrávající do 2 000 km od nejbližšího se vezmou s sebou
export const BUNDLE_DAYS_WINDOW = 60      // … nebo do 60 dní

const cmpNum = (a, b) => (a ?? Infinity) - (b ?? Infinity)

/**
 * rows = řádky get_service_due jedné motorky. Vrací null, nebo
 * { items: [rows], date (ISO navržený termín), km (navržený stav), reason, extra: [rows „vezmi s sebou“] }
 */
export function computeBundle(rows, { kmWindow = BUNDLE_KM_WINDOW, daysWindow = BUNDLE_DAYS_WINDOW } = {}) {
  const open = (rows || []).filter(r => !r.open_log_id && r.state !== 'unknown')
  const urgent = open.filter(r => r.state === 'overdue' || r.state === 'due_soon')
  if (urgent.length === 0) return null
  const anchor = [...urgent].sort((a, b) => cmpNum(a.km_remaining, b.km_remaining) || cmpNum(a.days_remaining, b.days_remaining))[0]
  const aKm = anchor.km_remaining ?? null, aDays = anchor.days_remaining ?? null
  const extra = open.filter(r => r.state === 'ok' && (
    (r.km_remaining !== null && r.km_remaining !== undefined && r.km_remaining <= Math.max(aKm ?? 0, 0) + kmWindow) ||
    (r.days_remaining !== null && r.days_remaining !== undefined && r.days_remaining <= Math.max(aDays ?? 0, 0) + daysWindow)))
  const items = [...urgent, ...extra]
  const overdue = urgent.some(r => r.state === 'overdue')
  const dates = urgent.map(r => r.est_date || r.next_date).filter(Boolean).sort()
  const date = overdue ? todayIso() : (dates[0] || todayIso())
  const cur = anchor.current_km ?? 0
  const km = overdue ? cur : Math.max(cur, Math.min(...urgent.map(r => r.next_km ?? Infinity).filter(Number.isFinite), cur + Math.max(aKm ?? 0, 0)))
  return { items, extra, date: date < todayIso() ? todayIso() : date, km: Number.isFinite(km) ? km : cur, overdue, anchor }
}

/** Založí JEDEN plánovaný servisní záznam se všemi úkony sdruženého servisu. */
export async function planServiceBundle(motoId, rows, { date, note } = {}) {
  const items = rows.map(r => ({ label: TASK_BY_ID[r.task_key]?.label || r.label, done: false, note: '', key: r.task_key || undefined }))
  const service_date = date || todayIso()
  const future = service_date > todayIso()
  const { data, error } = await supabase.from('maintenance_log').insert({
    moto_id: motoId, service_type: 'regular', status: future ? 'pending' : 'in_service',
    service_date, scheduled_date: service_date, items,
    description: note || `Společný plánovaný servis (${items.length} úkonů): ${items.map(i => i.label).join(', ')}`,
  }).select('id').single()
  if (error) throw error
  await audit('service_bundle_planned', { moto_id: motoId, log_id: data?.id, tasks: rows.map(r => r.task_key) })
  return data
}

/** Řádky get_service_due seskupené podle skupiny katalogu (pořadí katalogu), pro přehledovou tabulku. */
export function groupDueByCatalogGroup(rows) {
  const order = {}
  let i = 0
  for (const t of Object.values(TASK_BY_ID)) if (!(t.group in order)) order[t.group] = { key: t.group, label: t.groupLabel, idx: i++ }
  const map = {}
  for (const r of rows || []) {
    const t = TASK_BY_ID[r.task_key]
    const g = t ? order[t.group] : { key: 'custom', label: 'Vlastní plány', idx: 999 }
    if (!map[g.key]) map[g.key] = { ...g, rows: [] }
    map[g.key].rows.push(r)
  }
  return Object.values(map).sort((a, b) => a.idx - b.idx)
}
