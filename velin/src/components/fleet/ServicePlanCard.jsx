import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'
import Button from '../ui/Button'
import PartsPanel from './PartsPanel'
import AddScheduleBtn from './AddScheduleBtn'
import { DUE_STATE, BASELINE_LABELS, SOURCE_LABELS, fmtDate, fmtKm, dueText, intervalText, planServiceFromDue, setScheduleBaseline, applyServicePresets } from '../../lib/serviceBook'

const inp = { padding: '4px 8px', background: '#fff', border: '1px solid #d4e8e0', fontSize: 13 }

/**
 * Plán údržby motorky (hlídání intervalů): každý plán = úkon z katalogu / vlastní, stav z DB (get_service_due),
 * „naposledy provedeno“ (odkud), interval, odhad termínu. Akce: Naplánovat servis, Zapsat provedení,
 * Upravit interval, Díly, Vyřadit plán; „+ Nový plán“; „Doplnit standardní plány“.
 * Props: moto, due (řádky get_service_due této motorky), schedules (maintenance_schedules), parts, inventoryItems,
 *        unitLabel, onChanged, logAudit, partsApi { add, remove, updateQty }
 */
export default function ServicePlanCard({ moto, due, schedules, partsBySchedule = {}, inventoryItems = [], unitLabel = 'km', onChanged, logAudit, partsApi, onAddSchedule, saving }) {
  const [busy, setBusy] = useState(null)
  const [baseline, setBaseline] = useState(null)   // { id, km, date }
  const [editing, setEditing] = useState(null)     // { id, interval_km, interval_days, description }
  const [expandedParts, setExpandedParts] = useState(null)
  const [msg, setMsg] = useState(null)
  const byId = Object.fromEntries((schedules || []).map(s => [s.id, s]))
  const rows = (due || []).map(d => ({ ...d, sched: byId[d.schedule_id] }))
  const counts = rows.reduce((a, r) => { const k = r.open_log_id ? 'planned' : r.state; a[k] = (a[k] || 0) + 1; return a }, {})

  async function run(id, fn) { setBusy(id); setMsg(null); try { await fn(); onChanged?.() } catch (e) { setMsg(e.message) } finally { setBusy(null) } }
  const plan = (d) => run(d.schedule_id, async () => { await planServiceFromDue(d); setMsg(`Naplánováno: ${d.label}`) })
  const deactivate = (d) => { if (!window.confirm(`Vyřadit plán „${d.label}“? (přestane se hlídat)`)) return; run(d.schedule_id, async () => { await supabase.from('maintenance_schedules').update({ active: false }).eq('id', d.schedule_id); await logAudit?.('schedule_deleted', { schedule_id: d.schedule_id }) }) }
  const saveBaseline = () => run(baseline.id, async () => { await setScheduleBaseline(baseline.id, { km: baseline.km, date: baseline.date }); setBaseline(null) })
  const saveEdit = () => run(editing.id, async () => {
    const { error } = await supabase.from('maintenance_schedules').update({ description: editing.description, interval_km: Number(editing.interval_km) || null, interval_days: Number(editing.interval_days) || null, source: 'manual', schedule_type: editing.interval_km && editing.interval_days ? 'both' : editing.interval_km ? 'mileage' : 'time' }).eq('id', editing.id)
    if (error) throw error
    await logAudit?.('schedule_updated', { schedule_id: editing.id, moto_id: moto.id }); setEditing(null)
  })
  const applyStd = () => run('std', async () => { const r = await applyServicePresets(moto.id); setMsg(`Standardní plány: ${r?.created || 0} založeno, ${r?.updated || 0} aktualizováno`) })

  return (
    <Card>
      <div className="flex items-center justify-between mb-2 flex-wrap gap-2">
        <div>
          <h3 className="text-sm font-extrabold uppercase tracking-widest" style={{ color: '#1a2e22' }}>Plán údržby — hlídání intervalů</h3>
          <div className="flex gap-2 mt-1 flex-wrap text-xs font-bold">
            {['overdue', 'due_soon', 'ok', 'unknown'].map(k => counts[k] ? <span key={k} style={{ color: DUE_STATE[k].color }}>{DUE_STATE[k].label}: {counts[k]}</span> : null)}
            {counts.planned ? <span style={{ color: '#4f46e5' }}>Naplánováno: {counts.planned}</span> : null}
          </div>
        </div>
        <div className="flex gap-2 flex-wrap">
          <button onClick={applyStd} disabled={busy === 'std'} className="rounded-btn text-xs font-extrabold uppercase cursor-pointer" style={{ padding: '6px 12px', background: '#eef2ff', color: '#4f46e5', border: 'none' }} title="Založí chybějící plány základního standardu (olej, filtry, svíčky, brzdová kapalina, …) dle výrobce / katalogu">Doplnit standardní plány</button>
          <AddScheduleBtn onAdd={onAddSchedule} saving={saving} unitLabel={unitLabel} existingTypes={(schedules || []).map(s => s.description)} />
        </div>
      </div>
      {msg && <div className="text-xs mb-2 p-2 rounded" style={{ background: '#f1faf7', color: '#1a2e22' }}>{msg}</div>}
      {rows.length === 0 && <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné plány — klikněte na „Doplnit standardní plány“.</p>}
      <div className="space-y-1">
        {rows.map(d => {
          const st = d.open_log_id ? { label: 'Naplánováno', color: '#4f46e5', bg: '#eef2ff', border: '#c7d2fe' } : (DUE_STATE[d.state] || DUE_STATE.unknown)
          const parts = partsBySchedule[d.schedule_id] || []
          const isB = baseline?.id === d.schedule_id, isE = editing?.id === d.schedule_id
          return (
            <div key={d.schedule_id} className="rounded-lg" style={{ background: st.bg, border: `1px solid ${st.border}` }}>
              <div className="flex items-center gap-2 flex-wrap" style={{ padding: '6px 10px' }}>
                <span className="text-xs font-extrabold rounded-full" style={{ padding: '1px 8px', background: '#fff', color: st.color, border: `1px solid ${st.border}` }}>{st.label}</span>
                <span className="font-bold text-sm" style={{ color: '#0f1a14' }}>{d.label}</span>
                <span className="text-xs" style={{ color: '#6b7280' }}>každých {intervalText(d, unitLabel)} <span title={SOURCE_LABELS[d.source]}>({SOURCE_LABELS[d.source] || d.source})</span></span>
                <span className="text-sm font-bold ml-auto" style={{ color: st.color }}>{dueText(d, unitLabel)}</span>
                {d.est_date && !d.open_log_id && d.state !== 'overdue' && <span className="text-xs" style={{ color: '#6b7280' }} title="Odhad termínu z průměrného denního nájezdu">~{fmtDate(d.est_date)}</span>}
                {d.planned_date && <span className="text-xs font-bold" style={{ color: '#2563eb' }}>termín {fmtDate(d.planned_date)}</span>}
              </div>
              <div className="flex items-center gap-3 flex-wrap text-xs" style={{ padding: '0 10px 6px', color: '#1a2e22' }}>
                <span title={BASELINE_LABELS[d.baseline_source] || ''}>naposledy: <b>{d.last_date ? fmtDate(d.last_date) : '—'}</b>{d.last_km != null ? <b> · {fmtKm(d.last_km, unitLabel)}</b> : ''} <span style={{ color: '#9ca3af' }}>({BASELINE_LABELS[d.baseline_source] || 'neznámé'})</span></span>
                <span className="ml-auto flex gap-2 flex-wrap">
                  {!d.open_log_id && <button onClick={() => plan(d)} disabled={busy === d.schedule_id} className="font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#1a8a18' }}>Naplánovat servis</button>}
                  <button onClick={() => setBaseline(isB ? null : { id: d.schedule_id, km: d.last_km ?? '', date: d.last_date || '' })} className="font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#2563eb' }}>Zapsat provedení</button>
                  <button onClick={() => setEditing(isE ? null : { id: d.schedule_id, description: d.sched?.description || d.label, interval_km: d.interval_km || '', interval_days: d.interval_days || '' })} className="font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#1a2e22' }}>Interval</button>
                  <button onClick={() => setExpandedParts(expandedParts === d.schedule_id ? null : d.schedule_id)} className="font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#2563eb' }}>{parts.length ? `${parts.length} dílů` : 'Díly'}</button>
                  <button onClick={() => deactivate(d)} className="font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#dc2626' }} title="Vyřadit plán">×</button>
                </span>
              </div>
              {isB && (
                <div className="flex items-center gap-2 flex-wrap" style={{ padding: '0 10px 8px' }}>
                  <span className="text-xs font-bold" style={{ color: '#1a2e22' }}>Naposledy provedeno:</span>
                  <input type="number" value={baseline.km} onChange={e => setBaseline(b => ({ ...b, km: e.target.value }))} placeholder={unitLabel} className="rounded outline-none" style={{ ...inp, width: 110 }} />
                  <input type="date" value={baseline.date} onChange={e => setBaseline(b => ({ ...b, date: e.target.value }))} className="rounded outline-none" style={inp} />
                  <Button small green onClick={saveBaseline} disabled={busy === d.schedule_id}>Uložit</Button>
                  <Button small onClick={() => setBaseline(null)}>Zrušit</Button>
                </div>
              )}
              {isE && (
                <div className="flex items-center gap-2 flex-wrap" style={{ padding: '0 10px 8px' }}>
                  <input value={editing.description} onChange={e => setEditing(x => ({ ...x, description: e.target.value }))} placeholder="Popis" className="rounded outline-none" style={{ ...inp, width: 200 }} />
                  <input type="number" value={editing.interval_km} onChange={e => setEditing(x => ({ ...x, interval_km: e.target.value }))} placeholder={`Interval ${unitLabel}`} className="rounded outline-none" style={{ ...inp, width: 120 }} />
                  <input type="number" value={editing.interval_days} onChange={e => setEditing(x => ({ ...x, interval_days: e.target.value }))} placeholder="Interval dní" className="rounded outline-none" style={{ ...inp, width: 110 }} />
                  <Button small green onClick={saveEdit} disabled={busy === d.schedule_id}>Uložit</Button>
                  <Button small onClick={() => setEditing(null)}>Zrušit</Button>
                </div>
              )}
              {expandedParts === d.schedule_id && partsApi && (
                <PartsPanel parts={parts} inventoryItems={inventoryItems} scheduleId={d.schedule_id} onAdd={partsApi.add} onRemove={partsApi.remove} onUpdateQty={partsApi.updateQty} />
              )}
            </div>
          )
        })}
      </div>
    </Card>
  )
}
