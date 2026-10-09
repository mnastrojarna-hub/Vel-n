import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'
import Button from '../ui/Button'
import PartsPanel from './PartsPanel'
import AddScheduleBtn from './AddScheduleBtn'
import ServiceBundleBox from './ServiceBundleBox'
import { DUE_STATE, BASELINE_LABELS, SOURCE_LABELS, fmtDate, fmtKm, intervalText, planServiceFromDue, recordServiceDone, applyServicePresets, todayIso } from '../../lib/serviceBook'
import { groupDueByCatalogGroup } from '../../lib/serviceBundle'

const inp = { padding: '4px 8px', background: '#fff', border: '1px solid #d4e8e0', fontSize: 13 }
const th = { padding: '6px 8px', color: '#1a2e22', fontSize: 11, textAlign: 'left', whiteSpace: 'nowrap' }
const td = { padding: '6px 8px', fontSize: 13, verticalAlign: 'top' }
// Mimo komponentu: definice uvnitř by při každém renderu tlačítka odpojila a znovu připojila (ztráta kliknutí).
const Note = ({ m }) => <div className="text-xs font-bold p-2 rounded" style={{ background: m.error ? '#fef2f2' : '#f1faf7', color: m.error ? '#dc2626' : '#1a8a18' }}>{m.text}</div>
const Btn = ({ onClick, color, children, title, disabled }) => <button type="button" onClick={onClick} disabled={disabled} title={title} className="font-bold cursor-pointer" style={{ background: 'none', border: 'none', color, fontSize: 12, padding: '0 3px' }}>{children}</button>

/**
 * Přehled servisních intervalů motorky — strukturovaná tabulka po skupinách (motor & olej, brzdy, …):
 * Stav · Úkon · Interval · Naposledy (datum · km · odkud) · Příští při km (zbývá) · Příští datum
 * (dle lhůty / odhad z Ø nájezdu). Nahoře doporučený společný servis. Akce na řádku: Naplánovat,
 * Provedeno (dnes + aktuální km → dokončený servisní záznam, plán se posune), Interval, Díly, Vyřadit.
 * Stav počítá DB (get_service_due). Výsledek / chyba akce se zobrazí přímo pod řádkem.
 */
export default function ServicePlanCard({ moto, due, schedules, partsBySchedule = {}, inventoryItems = [], unitLabel = 'km', onChanged, logAudit, partsApi, onAddSchedule, saving, existingTaskKeys = [] }) {
  const [busy, setBusy] = useState(null)
  const [done, setDone] = useState(null)        // { id, km, date, toLog } — editor „Provedeno“
  const [editing, setEditing] = useState(null)
  const [expandedParts, setExpandedParts] = useState(null)
  const [msg, setMsg] = useState(null)          // { text, error, rowId }
  const byId = Object.fromEntries((schedules || []).map(s => [s.id, s]))
  const rows = (due || []).map(d => ({ ...d, sched: byId[d.schedule_id] }))
  const counts = rows.reduce((a, r) => { const k = r.open_log_id ? 'planned' : r.state; a[k] = (a[k] || 0) + 1; return a }, {})
  const avg = rows[0]?.avg_daily_km

  async function run(id, fn, rowId = null) {
    setBusy(id); setMsg(null)
    try { const text = await fn(); if (text) setMsg({ text, rowId }); onChanged?.() }
    catch (e) { setMsg({ text: `Nepodařilo se uložit: ${e.message || e}`, error: true, rowId }) }
    finally { setBusy(null) }
  }
  const plan = (d) => run(d.schedule_id, async () => { const r = await planServiceFromDue(d); return r ? `Naplánováno: ${d.label}` : null }, d.schedule_id)
  const deactivate = (d) => { if (!window.confirm(`Vyřadit plán „${d.label}“? (přestane se hlídat)`)) return; run(d.schedule_id, async () => { const { error } = await supabase.from('maintenance_schedules').update({ active: false }).eq('id', d.schedule_id); if (error) throw error; await logAudit?.('schedule_deleted', { schedule_id: d.schedule_id }) }) }
  const openDone = (d) => setDone(done?.id === d.schedule_id ? null : { id: d.schedule_id, km: moto?.mileage ?? '', date: todayIso(), toLog: true })
  const saveDone = (d) => run(d.schedule_id, async () => {
    const r = await recordServiceDone(d, done)
    setDone(null)
    return `${d.label}: provedeno ${fmtDate(done.date)}${done.km !== '' ? ` při ${fmtKm(done.km, unitLabel)}` : ''} — ${r ? `zapsáno do servisní knihy${r.removedFromOpen ? ' a odebráno z naplánovaného servisu' : ''}` : 'zapsáno jako poslední provedení'}`
  }, d.schedule_id)
  const saveEdit = () => run(editing.id, async () => {
    const { error } = await supabase.from('maintenance_schedules').update({ description: editing.description, interval_km: Number(editing.interval_km) || null, interval_days: Number(editing.interval_days) || null, source: 'manual', schedule_type: editing.interval_km && editing.interval_days ? 'both' : editing.interval_km ? 'mileage' : 'time' }).eq('id', editing.id)
    if (error) throw error
    await logAudit?.('schedule_updated', { schedule_id: editing.id, moto_id: moto.id }); setEditing(null)
    return 'Interval uložen'
  }, editing.id)
  const applyStd = () => run('std', async () => { const r = await applyServicePresets(moto.id); return `Standardní plány: ${r?.created || 0} založeno, ${r?.updated || 0} aktualizováno${r?.deactivated ? `, ${r.deactivated} vyřazeno (netýká se)` : ''}` })

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
      {msg && !msg.rowId && <div className="mb-2"><Note m={msg} /></div>}
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
                  const isD = done?.id === d.schedule_id, isE = editing?.id === d.schedule_id
                  const kmRem = d.km_remaining, dRem = d.days_remaining
                  const rowMsg = msg?.rowId === d.schedule_id ? msg : null
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
                        <Btn onClick={() => openDone(d)} color="#2563eb" title="Zapsat provedení: dnes při aktuálním stavu tachometru (lze upravit) → dokončený servisní záznam, plán se posune">Provedeno</Btn>
                        {d.open_log_id && <span className="text-xs" style={{ color: '#4f46e5' }} title="Úkon je v naplánovaném / otevřeném servisu (karta výše). „Provedeno“ ho zapíše samostatně a z checklistu toho servisu odebere.">naplánováno</span>}
                        <Btn onClick={() => setEditing(isE ? null : { id: d.schedule_id, description: d.sched?.description || d.label, interval_km: d.interval_km || '', interval_days: d.interval_days || '' })} color="#1a2e22">Interval</Btn>
                        <Btn onClick={() => setExpandedParts(expandedParts === d.schedule_id ? null : d.schedule_id)} color="#2563eb">{parts.length ? `${parts.length} dílů` : 'Díly'}</Btn>
                        <Btn onClick={() => deactivate(d)} color="#dc2626" title="Vyřadit plán">×</Btn>
                      </td>
                    </tr>,
                    (isD || isE || rowMsg || expandedParts === d.schedule_id) && (
                      <tr key={`${d.schedule_id}-x`}><td colSpan={7} style={{ padding: '0 8px 8px' }}>
                        {rowMsg && <div className="mb-1"><Note m={rowMsg} /></div>}
                        {isD && <div className="flex items-center gap-2 flex-wrap p-2 rounded" style={{ background: '#eff6ff', border: '1px solid #bfdbfe' }}>
                          <span className="text-xs font-extrabold" style={{ color: '#1e3a8a' }}>{d.label} — provedeno dne</span>
                          <input type="date" value={done.date} max={todayIso()} onChange={e => setDone(b => ({ ...b, date: e.target.value }))} className="rounded outline-none" style={inp} />
                          <span className="text-xs font-bold" style={{ color: '#1e3a8a' }}>při</span>
                          <input type="number" min="0" value={done.km} onChange={e => setDone(b => ({ ...b, km: e.target.value }))} placeholder={unitLabel} className="rounded outline-none" style={{ ...inp, width: 110 }} />
                          <span className="text-xs" style={{ color: '#1e3a8a' }}>{unitLabel}</span>
                          <label className="text-xs flex items-center gap-1 cursor-pointer" style={{ color: '#1e3a8a' }}><input type="checkbox" checked={done.toLog} onChange={e => setDone(b => ({ ...b, toLog: e.target.checked }))} /> zapsat do servisní knihy (dokončený servis s tímto úkonem)</label>
                          <Button small green onClick={() => saveDone(d)} disabled={busy === d.schedule_id || !done.date || (done.toLog && !!d.interval_km && done.km === '')}>{busy === d.schedule_id ? 'Ukládám…' : 'Uložit'}</Button><Button small onClick={() => setDone(null)}>Zrušit</Button>
                          <div className="text-xs w-full" style={{ color: '#6b7280' }}>Předvyplněno dnes a aktuální stav tachometru ({fmtKm(moto?.mileage, unitLabel)}). Dřívější provedení: upravte datum a km — plán se počítá od nich (novější provedení už zapsané v servisní knize má přednost).{d.interval_km && done.toLog ? ` U plánu podle ${unitLabel} je stav tachometru povinný.` : ''}{!done.toLog ? ' Bez zápisu do knihy se jen nastaví „naposledy provedeno“ (bez záznamu v historii).' : ''}</div>
                        </div>}
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
