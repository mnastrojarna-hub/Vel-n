import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'
import Button from '../ui/Button'
import PartsPanel from './PartsPanel'
import AddScheduleBtn from './AddScheduleBtn'
import ServiceBundleBox from './ServiceBundleBox'
import { DUE_STATE, BASELINE_LABELS, SOURCE_LABELS, fmtDate, fmtKm, intervalText, planServiceFromDue, setScheduleBaseline, applyServicePresets } from '../../lib/serviceBook'
import { groupDueByCatalogGroup } from '../../lib/serviceBundle'

const inp = { padding: '4px 8px', background: '#fff', border: '1px solid #d4e8e0', fontSize: 13 }
const th = { padding: '6px 8px', color: '#1a2e22', fontSize: 11, textAlign: 'left', whiteSpace: 'nowrap' }
const td = { padding: '6px 8px', fontSize: 13, verticalAlign: 'top' }

/**
 * Přehled servisních intervalů motorky — strukturovaná tabulka po skupinách (motor & olej, brzdy, …):
 * Stav · Úkon · Interval · Naposledy (datum · km · odkud) · Příští při km (zbývá) · Příští datum
 * (dle lhůty / odhad z Ø nájezdu). Nahoře doporučený společný servis. Akce na řádku: Naplánovat,
 * Zapsat provedení (baseline), Interval, Díly, Vyřadit. Stav počítá DB (get_service_due).
 */
export default function ServicePlanCard({ moto, due, schedules, partsBySchedule = {}, inventoryItems = [], unitLabel = 'km', onChanged, logAudit, partsApi, onAddSchedule, saving, existingTaskKeys = [] }) {
  const [busy, setBusy] = useState(null)
  const [baseline, setBaseline] = useState(null)
  const [editing, setEditing] = useState(null)
  const [expandedParts, setExpandedParts] = useState(null)
  const [msg, setMsg] = useState(null)
  const byId = Object.fromEntries((schedules || []).map(s => [s.id, s]))
  const rows = (due || []).map(d => ({ ...d, sched: byId[d.schedule_id] }))
  const counts = rows.reduce((a, r) => { const k = r.open_log_id ? 'planned' : r.state; a[k] = (a[k] || 0) + 1; return a }, {})
  const avg = rows[0]?.avg_daily_km

  async function run(id, fn) { setBusy(id); setMsg(null); try { await fn(); onChanged?.() } catch (e) { setMsg(e.message) } finally { setBusy(null) } }
  const plan = (d) => run(d.schedule_id, async () => { const r = await planServiceFromDue(d); if (r) setMsg(`Naplánováno: ${d.label}`) })
  const deactivate = (d) => { if (!window.confirm(`Vyřadit plán „${d.label}“? (přestane se hlídat)`)) return; run(d.schedule_id, async () => { await supabase.from('maintenance_schedules').update({ active: false }).eq('id', d.schedule_id); await logAudit?.('schedule_deleted', { schedule_id: d.schedule_id }) }) }
  const saveBaseline = () => run(baseline.id, async () => { await setScheduleBaseline(baseline.id, { km: baseline.km, date: baseline.date }); setBaseline(null) })
  const saveEdit = () => run(editing.id, async () => {
    const { error } = await supabase.from('maintenance_schedules').update({ description: editing.description, interval_km: Number(editing.interval_km) || null, interval_days: Number(editing.interval_days) || null, source: 'manual', schedule_type: editing.interval_km && editing.interval_days ? 'both' : editing.interval_km ? 'mileage' : 'time' }).eq('id', editing.id)
    if (error) throw error
    await logAudit?.('schedule_updated', { schedule_id: editing.id, moto_id: moto.id }); setEditing(null)
  })
  const applyStd = () => run('std', async () => { const r = await applyServicePresets(moto.id); setMsg(`Standardní plány: ${r?.created || 0} založeno, ${r?.updated || 0} aktualizováno`) })

  const Btn = ({ onClick, color, children, title, disabled }) => <button onClick={onClick} disabled={disabled} title={title} className="font-bold cursor-pointer" style={{ background: 'none', border: 'none', color, fontSize: 12, padding: '0 3px' }}>{children}</button>

  return (
    <Card>
      <div className="flex items-center justify-between mb-2 flex-wrap gap-2">
        <div>
          <h3 className="text-sm font-extrabold uppercase tracking-widest" style={{ color: '#1a2e22' }}>Servisní intervaly — kdy byl a kdy bude</h3>
          <div className="flex gap-3 mt-1 flex-wrap text-xs font-bold">
            {['overdue', 'due_soon', 'ok', 'unknown'].map(k => counts[k] ? <span key={k} style={{ color: DUE_STATE[k].color }}>{DUE_STATE[k].label}: {counts[k]}</span> : null)}
            {counts.planned ? <span style={{ color: '#4f46e5' }}>Naplánováno: {counts.planned}</span> : null}
            {avg ? <span style={{ color: '#6b7280' }}>Ø nájezd {avg} {unitLabel}/den (od pořízení)</span> : null}
          </div>
        </div>
        <div className="flex gap-2 flex-wrap">
          <button onClick={applyStd} disabled={busy === 'std'} className="rounded-btn text-xs font-extrabold uppercase cursor-pointer" style={{ padding: '6px 12px', background: '#eef2ff', color: '#4f46e5', border: 'none' }} title="Založí chybějící plány základního standardu dle výrobce / katalogu">Doplnit standardní plány</button>
          <AddScheduleBtn onAdd={onAddSchedule} saving={saving} unitLabel={unitLabel} existingTypes={(schedules || []).map(s => s.description)} existingTaskKeys={existingTaskKeys} />
        </div>
      </div>
      {msg && <div className="text-xs mb-2 p-2 rounded" style={{ background: '#f1faf7', color: '#1a2e22' }}>{msg}</div>}
      <ServiceBundleBox moto={moto} due={rows} onPlanned={onChanged} unitLabel={unitLabel} />
      {rows.length === 0 && <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné plány — klikněte na „Doplnit standardní plány“.</p>}
      {rows.length > 0 && (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse">
            <thead><tr style={{ background: '#f1faf7', borderBottom: '1px solid #d4e8e0' }}>
              {['Stav', 'Úkon', 'Interval', 'Naposledy', `Příští při ${unitLabel}`, 'Příští datum', ''].map((h, i) => <th key={i} className="font-extrabold uppercase tracking-wide" style={th}>{h}</th>)}
            </tr></thead>
            <tbody>
              {groupDueByCatalogGroup(rows).map(g => [
                <tr key={`g-${g.key}`}><td colSpan={7} className="text-xs font-extrabold uppercase tracking-wide" style={{ padding: '8px 8px 2px', color: '#1a8a18' }}>{g.label}</td></tr>,
                ...g.rows.map(d => {
                  const st = d.open_log_id ? { label: 'Naplánováno', color: '#4f46e5', bg: '#eef2ff', border: '#c7d2fe' } : (DUE_STATE[d.state] || DUE_STATE.unknown)
                  const parts = partsBySchedule[d.schedule_id] || []
                  const isB = baseline?.id === d.schedule_id, isE = editing?.id === d.schedule_id
                  const kmRem = d.km_remaining, dRem = d.days_remaining
                  return [
                    <tr key={d.schedule_id} style={{ borderTop: '1px solid #e5efe9', background: d.state === 'overdue' && !d.open_log_id ? '#fff5f5' : 'transparent' }}>
                      <td style={td}><span className="text-xs font-extrabold rounded-full" style={{ padding: '1px 7px', background: st.bg, color: st.color, border: `1px solid ${st.border}`, whiteSpace: 'nowrap' }}>{st.label}</span></td>
                      <td style={{ ...td, fontWeight: 700, color: '#0f1a14' }}>{d.label}<div className="text-xs font-normal" style={{ color: '#9ca3af' }}>{SOURCE_LABELS[d.source] || d.source}{d.sched?.notes ? ` · ${d.sched.notes}` : ''}</div></td>
                      <td style={{ ...td, whiteSpace: 'nowrap', color: '#1a2e22' }}>{intervalText(d, unitLabel)}</td>
                      <td style={{ ...td, whiteSpace: 'nowrap', color: '#1a2e22' }} title={BASELINE_LABELS[d.baseline_source] || ''}>{d.last_date ? fmtDate(d.last_date) : '—'}{d.last_km != null ? ` · ${d.km_estimated ? '~' : ''}${fmtKm(d.last_km, '')}` : ''}<div className="text-xs" style={{ color: '#9ca3af' }}>{d.baseline_source === 'log' ? 'servisní záznam' : d.baseline_source === 'acquisition' ? 'od pořízení (neověřeno)' : d.baseline_source === 'manual' ? 'zadáno ručně' : 'doplňte provedení'}</div></td>
                      <td style={{ ...td, whiteSpace: 'nowrap', fontWeight: 700, color: kmRem != null && kmRem <= 0 ? '#dc2626' : '#0f1a14' }}>{d.next_km != null ? <>{d.km_estimated ? '~' : ''}{fmtKm(d.next_km, '')}<div className="text-xs font-normal" style={{ color: kmRem <= 0 ? '#dc2626' : '#6b7280' }}>{kmRem <= 0 ? `${fmtKm(-kmRem, '')} po termínu` : `zbývá ${fmtKm(kmRem, '')}`}{d.km_estimated ? ' · km odhad z data' : ''}</div></> : <span style={{ color: '#9ca3af' }}>—</span>}</td>
                      <td style={{ ...td, whiteSpace: 'nowrap', color: '#0f1a14' }}>
                        {d.planned_date && <div className="font-bold" style={{ color: '#2563eb' }}>termín {fmtDate(d.planned_date)}</div>}
                        {d.next_date && <div style={{ fontWeight: 700, color: dRem != null && dRem <= 0 ? '#dc2626' : '#0f1a14' }}>{fmtDate(d.next_date)} <span className="text-xs font-normal" style={{ color: '#6b7280' }}>dle lhůty{dRem != null ? ` (${dRem <= 0 ? `${-dRem} dní po` : `za ${dRem} dní`})` : ''}</span></div>}
                        {d.est_date && d.next_km != null && <div className="text-xs" style={{ color: '#6b7280' }}>~{fmtDate(d.est_date)} odhad dle nájezdu</div>}
                        {!d.next_date && !d.est_date && !d.planned_date && <span style={{ color: '#9ca3af' }}>—</span>}
                      </td>
                      <td style={{ ...td, whiteSpace: 'nowrap' }}>
                        {!d.open_log_id && d.state !== 'unknown' && <Btn onClick={() => plan(d)} color="#1a8a18" disabled={busy === d.schedule_id}>Naplánovat</Btn>}
                        <Btn onClick={() => setBaseline(isB ? null : { id: d.schedule_id, km: d.last_km ?? '', date: d.last_date || '' })} color="#2563eb">Provedeno</Btn>
                        <Btn onClick={() => setEditing(isE ? null : { id: d.schedule_id, description: d.sched?.description || d.label, interval_km: d.interval_km || '', interval_days: d.interval_days || '' })} color="#1a2e22">Interval</Btn>
                        <Btn onClick={() => setExpandedParts(expandedParts === d.schedule_id ? null : d.schedule_id)} color="#2563eb">{parts.length ? `${parts.length} dílů` : 'Díly'}</Btn>
                        <Btn onClick={() => deactivate(d)} color="#dc2626" title="Vyřadit plán">×</Btn>
                      </td>
                    </tr>,
                    (isB || isE || expandedParts === d.schedule_id) && (
                      <tr key={`${d.schedule_id}-x`}><td colSpan={7} style={{ padding: '0 8px 8px' }}>
                        {isB && <div className="flex items-center gap-2 flex-wrap"><span className="text-xs font-bold" style={{ color: '#1a2e22' }}>Naposledy provedeno:</span>
                          <input type="number" value={baseline.km} onChange={e => setBaseline(b => ({ ...b, km: e.target.value }))} placeholder={unitLabel} className="rounded outline-none" style={{ ...inp, width: 110 }} />
                          <input type="date" value={baseline.date} onChange={e => setBaseline(b => ({ ...b, date: e.target.value }))} className="rounded outline-none" style={inp} />
                          <Button small green onClick={saveBaseline} disabled={busy === d.schedule_id}>Uložit</Button><Button small onClick={() => setBaseline(null)}>Zrušit</Button></div>}
                        {isE && <div className="flex items-center gap-2 flex-wrap">
                          <input value={editing.description} onChange={e => setEditing(x => ({ ...x, description: e.target.value }))} placeholder="Popis" className="rounded outline-none" style={{ ...inp, width: 200 }} />
                          <input type="number" value={editing.interval_km} onChange={e => setEditing(x => ({ ...x, interval_km: e.target.value }))} placeholder={`Interval ${unitLabel}`} className="rounded outline-none" style={{ ...inp, width: 120 }} />
                          <input type="number" value={editing.interval_days} onChange={e => setEditing(x => ({ ...x, interval_days: e.target.value }))} placeholder="Interval dní" className="rounded outline-none" style={{ ...inp, width: 110 }} />
                          <Button small green onClick={saveEdit} disabled={busy === d.schedule_id}>Uložit</Button><Button small onClick={() => setEditing(null)}>Zrušit</Button></div>}
                        {expandedParts === d.schedule_id && partsApi && <PartsPanel parts={parts} inventoryItems={inventoryItems} scheduleId={d.schedule_id} onAdd={partsApi.add} onRemove={partsApi.remove} onUpdateQty={partsApi.updateQty} />}
                      </td></tr>
                    ),
                  ]
                }),
              ])}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  )
}
