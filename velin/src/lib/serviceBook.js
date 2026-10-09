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
  no_interval: { label: 'Bez intervalu', color: '#9ca3af', bg: '#f9fafb', border: '#e5e7eb', order: 4 },
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
export const tomorrowIso = () => { const d = new Date(); d.setDate(d.getDate() + 1); return d.toLocaleDateString('sv-SE') }
/** Cena servisu: nahraná faktura má přednost před odhadem (cost). */
export const effectiveCost = (l) => Number(l?.invoiced_amount) > 0 ? Number(l.invoiced_amount) : (Number(l?.cost) || 0)

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

/** Poslední dokončený servis každé motorky (RPC, bez stahování celého logu). */
export async function fetchLastServicePerMoto() {
  const { data } = await supabase.rpc('get_last_service_per_moto')
  return Object.fromEntries((data || []).map(r => [r.moto_id, r]))
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

/**
 * Kontrola rezervací před naplánováním servisu (od `date` je motorka v servisu → nepůjde půjčit).
 * Probíhající pronájem = potvrdit, kolidující nadcházející rezervace = upozornit. Vrací false = zrušeno.
 */
export async function confirmServiceStart(motoId, date, label = 'servis') {
  const today = todayIso()
  const start = date || today
  if (start <= today) {
    const { data: active } = await supabase.from('bookings').select('id, end_date, profiles(full_name)').eq('moto_id', motoId).eq('status', 'active').gte('end_date', today)
    if (active?.length > 0 && !window.confirm(`Motorka má ${active.length} probíhající pronájem (${active.map(b => b.profiles?.full_name || '?').join(', ')}). ${label} ji vyřadí z půjčování. Pokračovat?`)) return false
  }
  const { data: future } = await supabase.from('bookings').select('id, start_date, end_date, profiles(full_name)').eq('moto_id', motoId).in('status', ['pending', 'reserved']).gte('end_date', start).order('start_date').limit(5)
  if (future?.length > 0) {
    const lines = future.map(b => `  ${b.profiles?.full_name || '?'}: ${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}`).join('\n')
    if (!window.confirm(`Upozornění — rezervace od ${new Date(start).toLocaleDateString('cs-CZ')} dál (${future.length}):\n${lines}\nMotorka musí být ze servisu zpět včas, nebo nabídněte náhradu. Naplánovat přesto?`)) return false
  }
  return true
}

/** Výchozí termín plánovaného servisu z řádku hlídání: ruční termín > odhad > zítra (nikdy tiše „dnes“ = vyřazení). */
export function suggestedServiceDate(d) {
  const t = tomorrowIso()
  const cand = d?.planned_date || (d?.state === 'overdue' ? t : (isoDateOf(d?.est_date) || isoDateOf(d?.next_date) || t))
  return cand < t ? t : cand
}

/** Vytvoří plánovaný servisní záznam z plánu (hlídání → „Naplánovat“). Vrací null, když obsluha zruší. */
export async function planServiceFromDue(d, { date, note } = {}) {
  const task = TASK_BY_ID[d.task_key]
  const items = [{ label: task?.label || d.label, done: false, note: '', key: d.task_key || undefined }]
  const service_date = date || suggestedServiceDate(d)
  if (!(await confirmServiceStart(d.moto_id, service_date, 'Plánovaný servis'))) return null
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

/**
 * „Provedeno“ z plánu údržby: založí DOKONČENÝ servisní záznam s tímto úkonem (datum + km) — DB trigger posune
 * plán, zvedne tachometr a technikem je přihlášený účet; s toLog=false se jen zapíše „naposledy provedeno“.
 * Výchozí = dnes + aktuální stav tachometru (zpětné provedení: jiné datum / km).
 */
export async function recordServiceDone(d, { km, date, toLog = true, note } = {}) {
  const day = date || todayIso()
  if (day > todayIso()) throw new Error('Datum provedení nemůže být v budoucnosti.')
  const kmNum = km === '' || km === null || km === undefined ? null : Number(km)
  if (kmNum !== null && (!Number.isFinite(kmNum) || kmNum < 0)) throw new Error('Neplatný stav tachometru.')
  if (!toLog) { await setScheduleBaseline(d.schedule_id, { km: kmNum, date: day }); return null }
  const task = TASK_BY_ID[d.task_key]
  const label = task?.label || d.label
  const payload = {
    moto_id: d.moto_id, service_type: 'regular', status: 'completed', service_date: day, completed_date: day,
    km_at_service: kmNum, items: [{ label, key: d.task_key || undefined, done: true, note: '' }],
    description: note || `Zapsáno z plánu údržby: ${label}`,
  }
  const { data, error } = await supabase.from('maintenance_log').insert(payload).select('id').single()
  if (error) throw error
  // plán bez klíče z katalogu trigger nepozná podle úkonu → baseline zapsat přímo
  if (!d.task_key) await setScheduleBaseline(d.schedule_id, { km: kmNum, date: day })
  await audit('service_done_from_due', { moto_id: d.moto_id, task_key: d.task_key, schedule_id: d.schedule_id, log_id: data?.id, km: kmNum, date: day })
  return data
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
