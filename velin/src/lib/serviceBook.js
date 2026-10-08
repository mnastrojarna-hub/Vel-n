import { supabase } from './supabase'
import { TASK_BY_ID } from '../components/fleet/serviceCatalog'

// Sdílené helpery servisní knížky (Velín → Servis, detail motorky → Servis).
// Zdroj dat: maintenance_log (záznamy), maintenance_schedules + RPC get_service_due (plány / hlídání),
// maintenance_invoices (faktury). Žádná logika hlídání v JS — stav počítá DB (get_service_due).

export const SERVICE_TYPE_LABELS = { regular: 'Pravidelný servis', extraordinary: 'Mimořádný servis', repair: 'Oprava', inspection: 'Inspekce' }
export const LOG_TYPE_LABELS = {
  oil_change: 'Výměna oleje', tire_change: 'Výměna pneumatik', brake_check: 'Kontrola brzd',
  full_service: 'Kompletní servis', repair: 'Oprava', inspection: 'STK / Inspekce',
  stk: 'STK & Emise', winter_service: 'Velký zimní servis',
}

export const DUE_STATE = {
  overdue:  { label: 'Po termínu',  color: '#dc2626', bg: '#fee2e2', border: '#fca5a5', order: 0 },
  due_soon: { label: 'Blíží se',    color: '#b45309', bg: '#fef3c7', border: '#fde68a', order: 1 },
  ok:       { label: 'V pořádku',   color: '#1a8a18', bg: '#dcfce7', border: '#86efac', order: 2 },
  unknown:  { label: 'Neověřeno',   color: '#6b7280', bg: '#f3f4f6', border: '#e5e7eb', order: 3 },
}
export const BASELINE_LABELS = {
  log: 'z dokončeného servisu', acquisition: 'od pořízení motorky (neověřeno)', manual: 'zadáno ručně', unknown: 'neznámé — doplňte poslední provedení',
}
export const SOURCE_LABELS = { preset: 'dle výrobce', default: 'standard', manual: 'ručně' }

export const fmtDate = (d) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
export const fmtKm = (km, unit = 'km') => (km === null || km === undefined || km === '') ? '—' : `${Number(km).toLocaleString('cs-CZ')} ${unit}`
export const fmtMoney = (n) => (n === null || n === undefined || n === '' || Number(n) === 0) ? '—' : `${Number(n).toLocaleString('cs-CZ')} Kč`
export const unitLabel = (moto) => (moto?.tracking_unit === 'mh' ? 'MH' : 'km')
export const todayIso = () => new Date().toLocaleDateString('sv-SE')
export const isoDateOf = (d) => d ? String(d).slice(0, 10) : ''

export const isLogCompleted = (l) => l?.status === 'completed' || !!l?.completed_date
export const logStartDate = (l) => (l?.service_date || l?.created_at || '').slice(0, 10)
/** Stav záznamu pro UI: completed / in_service / planned */
export function logState(l) {
  if (isLogCompleted(l)) return 'completed'
  if (l?.service_date && String(l.service_date).slice(0, 10) > todayIso()) return 'planned'
  return l?.status === 'pending' ? 'planned' : 'in_service'
}
export const LOG_STATE = {
  completed: { label: 'Dokončeno', color: '#166534', bg: '#dcfce7' },
  in_service: { label: 'V servisu', color: '#b45309', bg: '#fef3c7' },
  planned: { label: 'Naplánováno', color: '#4f46e5', bg: '#eef2ff' },
}

/** Popis zbývající lhůty plánu (z řádku get_service_due). */
export function dueText(d, unit = 'km') {
  const parts = []
  if (d.km_remaining !== null && d.km_remaining !== undefined) {
    parts.push(d.km_remaining <= 0 ? `${Math.abs(d.km_remaining).toLocaleString('cs-CZ')} ${unit} po termínu` : `za ${Number(d.km_remaining).toLocaleString('cs-CZ')} ${unit}`)
  }
  if (d.days_remaining !== null && d.days_remaining !== undefined) {
    parts.push(d.days_remaining <= 0 ? `${Math.abs(d.days_remaining)} dní po termínu` : `za ${d.days_remaining} dní`)
  }
  if (parts.length === 0) return 'bez základu — doplňte poslední provedení'
  return parts.join(' · ')
}
export function intervalText(d, unit = 'km') {
  const parts = []
  if (d.interval_km) parts.push(`${Number(d.interval_km).toLocaleString('cs-CZ')} ${unit}`)
  if (d.interval_days) parts.push(d.interval_days % 30 === 0 || Math.abs(d.interval_days / 30.44 - Math.round(d.interval_days / 30.44)) < 0.05 ? `${Math.round(d.interval_days / 30.44)} měs.` : `${d.interval_days} dní`)
  return parts.join(' / ') || '—'
}

/** Hlídání intervalů (DB). p_moto_id null = celá flotila. */
export async function fetchServiceDue(motoId = null) {
  const { data, error } = await supabase.rpc('get_service_due', { p_moto_id: motoId })
  if (error) throw error
  return data || []
}
export async function fetchServiceDueCount() {
  const { data } = await supabase.rpc('get_service_due_count')
  return data || { overdue: 0, due_soon: 0, unknown: 0, planned: 0 }
}
/** Založí / doplní plány základního standardu (po přidání motorky, ručně z knížky). */
export async function applyServicePresets(motoId = null) {
  const { data, error } = await supabase.rpc('service_plan_apply_presets', { p_moto_id: motoId, p_reset: false })
  if (error) throw error
  return data
}

/** Vytvoří plánovaný servisní záznam z plánu (hlídání → „Naplánovat“). */
export async function planServiceFromDue(d, { date, note } = {}) {
  const task = TASK_BY_ID[d.task_key]
  const items = [{ label: task?.label || d.label, done: false, note: '', key: d.task_key || undefined }]
  const service_date = date || todayIso()
  const future = service_date > todayIso()
  const payload = {
    moto_id: d.moto_id, service_type: 'regular', status: future ? 'pending' : 'in_service',
    service_date, scheduled_date: service_date, items,
    description: note || `Plánovaný servis: ${task?.label || d.label}`,
  }
  const { data, error } = await supabase.from('maintenance_log').insert(payload).select('id').single()
  if (error) throw error
  await audit('service_planned_from_due', { moto_id: d.moto_id, task_key: d.task_key, log_id: data?.id })
  return data
}

/** Ruční baseline plánu („naposledy provedeno“) — km + datum. */
export async function setScheduleBaseline(scheduleId, { km, date }) {
  const { error } = await supabase.from('maintenance_schedules').update({
    last_service_km: km === '' || km === null || km === undefined ? null : Number(km),
    last_service_date: date || null, last_performed: date || null, baseline_source: 'manual', next_due: null,
  }).eq('id', scheduleId)
  if (error) throw error
  await audit('service_schedule_baseline_set', { schedule_id: scheduleId, km, date })
}

export async function audit(action, details) {
  try {
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, new_data: details })
  } catch { /* audit nesmí shodit akci */ }
}

/** Seskupení řádků get_service_due podle motorky s počty stavů. */
export function groupDueByMoto(rows) {
  const map = {}
  for (const r of rows) {
    if (!map[r.moto_id]) map[r.moto_id] = { moto_id: r.moto_id, model: r.model, spz: r.spz, branch_id: r.branch_id, moto_status: r.moto_status, tracking_unit: r.tracking_unit, rows: [], overdue: 0, due_soon: 0, unknown: 0, planned: 0 }
    const g = map[r.moto_id]
    g.rows.push(r)
    if (r.open_log_id) g.planned++
    else if (r.state === 'overdue') g.overdue++
    else if (r.state === 'due_soon') g.due_soon++
    else if (r.state === 'unknown') g.unknown++
  }
  return Object.values(map).sort((a, b) => (b.overdue - a.overdue) || (b.due_soon - a.due_soon) || a.model.localeCompare(b.model, 'cs'))
}
