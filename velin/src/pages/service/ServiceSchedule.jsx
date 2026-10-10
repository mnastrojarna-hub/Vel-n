import { useState, useEffect, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import { debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import { fetchServiceDue, DUE_STATE, SOURCE_LABELS, BASELINE_LABELS, dueText, intervalText, fmtDate, fmtKm, planServiceFromDue, isoDateOf, acceptServiceState, todayIso } from '../../lib/serviceBook'
import { useAdminIdentity } from '../../hooks/useAdminIdentity'
import { technicianLocked } from './ServiceFormFields'

const FILTERS = [['attention', 'K řešení'], ['all', 'Vše'], ['planned', 'Naplánované'], ['stk', 'STK']]
const STATE_ORDER = { overdue: 0, due_soon: 1, unknown: 2, ok: 3 }

/**
 * Servis → Plánované: hlídání intervalů celé flotily (DB get_service_due) + STK. Ruční termín (next_due)
 * lze zapsat kliknutím na datum; „naplánovat“ založí servisní záznam s úkonem.
 */
export default function ServiceSchedule({ onRefresh }) {
  const navigate = useNavigate()
  const me = useAdminIdentity()
  const isSuper = !technicianLocked(me)   // hromadné „Vše v pořádku k dnešku“ = jen superadmin (podúčet ne)
  const [rows, setRows] = useState([])
  const [motos, setMotos] = useState([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('attention')
  const [q, setQ] = useState('')
  const [editing, setEditing] = useState(null)
  const [dateVal, setDateVal] = useState('')
  const [busy, setBusy] = useState(null)

  useEffect(() => { load() }, [])
  async function load() {
    setLoading(true)
    try {
      const [due, m] = await Promise.all([fetchServiceDue(null), supabase.from('motorcycles').select('id, model, spz, stk_valid_until, license_required, is_trailer, status').neq('status', 'retired').order('model')])
      setRows(due); setMotos((m.data || []).filter(x => !x.is_trailer))
    } catch (e) { debugError('ServiceSchedule', 'load', e) }
    setLoading(false)
  }

  const stkRows = useMemo(() => motos.filter(m => m.license_required !== 'N').map(m => {
    const days = m.stk_valid_until ? Math.ceil((new Date(m.stk_valid_until) - new Date()) / 86400000) : null
    return { schedule_id: `stk-${m.id}`, moto_id: m.id, model: m.model, spz: m.spz, label: 'STK & Emise', group_label: 'Státní správa', isStk: true,
      state: days === null ? 'unknown' : days <= 0 ? 'overdue' : days <= 60 ? 'due_soon' : 'ok', days_remaining: days, next_date: m.stk_valid_until, tracking_unit: 'km' }
  }), [motos])

  const list = useMemo(() => {
    const norm = s => (s || '').toLowerCase()
    let items = filter === 'stk' ? stkRows : filter === 'all' ? [...rows, ...stkRows] : rows
    if (filter === 'attention') items = [...rows.filter(r => !r.open_log_id && r.state !== 'ok'), ...stkRows.filter(r => r.state !== 'ok')]
    if (filter === 'planned') items = rows.filter(r => r.open_log_id || r.planned_date)
    if (q) items = items.filter(r => norm(r.model).includes(norm(q)) || norm(r.spz).includes(norm(q)) || norm(r.label).includes(norm(q)))
    return items.sort((a, b) => (STATE_ORDER[a.state] - STATE_ORDER[b.state]) || (a.model || '').localeCompare(b.model || '', 'cs') || (a.label || '').localeCompare(b.label || '', 'cs'))
  }, [rows, stkRows, filter, q])

  async function saveDate(r, val) {
    setBusy(r.schedule_id)
    try { const { error } = await supabase.from('maintenance_schedules').update({ next_due: val || null }).eq('id', r.schedule_id); if (error) throw error; setEditing(null); await load(); onRefresh?.() }
    catch (e) { debugError('ServiceSchedule', 'saveDate', e) }
    setBusy(null)
  }
  async function plan(r) { setBusy(r.schedule_id); try { const res = await planServiceFromDue(r, { date: r.planned_date || undefined }); if (res) { await load(); onRefresh?.() } } catch (e) { alert(e.message) } setBusy(null) }
  // „Vše v pořádku k dnešku“ pro celou flotilu — stav hlídaný jinde (papír); plány v pořádku se nemění
  async function acceptFleet() {
    const n = rows.filter(r => !r.open_log_id && ['overdue', 'due_soon', 'unknown'].includes(r.state) && !(r.state === 'due_soon' && r.baseline_source === 'log')).length
    if (!n) { alert('Žádný plán není po termínu, blížící se ani neověřený.'); return }
    if (!window.confirm(`Převzít stav z jiné evidence pro CELOU flotilu: ${n} plánů (po termínu / blíží se / neověřeno) dostane „naposledy provedeno“ = dnes při aktuálním stavu tachometru každé motorky. Plány v pořádku a plány blížící se podle skutečného servisního záznamu se nemění, budoucí ruční termíny zůstanou; dokončený servis (zimní prohlídka) odpočet znovu přepíše. Pokračovat?`)) return
    setBusy('accept')
    try { const r = await acceptServiceState(null, `stav převzat z evidence ${fmtDate(todayIso())}`); alert(`Převzato: ${r?.updated || 0} plánů u ${r?.motos || 0} motorek počítá od dneška.`); await load(); onRefresh?.() }
    catch (e) { alert(`Nepodařilo se: ${e.message}`) }
    setBusy(null)
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  const counts = rows.reduce((a, r) => { if (!r.open_log_id) a[r.state] = (a[r.state] || 0) + 1; return a }, {})

  return (
    <div>
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        {FILTERS.map(([k, label]) => (
          <button key={k} onClick={() => setFilter(k)} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer px-3.5 py-1.5 max-lg:py-2.5"
            style={{ background: filter === k ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none', boxShadow: filter === k ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>{label}</button>
        ))}
        <input value={q} onChange={e => setQ(e.target.value)} placeholder="Hledat motorku / úkon…" className="rounded-btn text-sm outline-none" style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', width: 220 }} />
        {isSuper && <button onClick={acceptFleet} disabled={busy === 'accept'} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer px-3.5 py-1.5 max-lg:py-2.5" style={{ background: '#e8fde8', color: '#1a8a18', border: 'none' }} title="Stav hlídaný jinde (papír): plány po termínu / blíží se / neověřené v celé flotile začnou počítat od dneška (jen superadmin)">Vše v pořádku k dnešku</button>}
        <span className="ml-auto text-xs flex gap-3 font-bold max-md:basis-full max-md:ml-0 max-md:flex-wrap max-md:gap-y-1">
          {['overdue', 'due_soon', 'unknown', 'ok'].map(k => counts[k] ? <span key={k} style={{ color: DUE_STATE[k].color }}>{DUE_STATE[k].label}: {counts[k]}</span> : null)}
          <span style={{ color: '#6b7280' }}>{list.length} řádků</span>
        </span>
      </div>

      <Table stack="tablet">
        <thead><TRow header><TH>Stav</TH><TH>Motorka</TH><TH>Úkon</TH><TH>Interval</TH><TH>Naposledy</TH><TH>Zbývá</TH><TH>Odhad / termín</TH><TH></TH></TRow></thead>
        <tbody>
          {list.map(r => {
            const st = r.open_log_id ? { label: 'Naplánováno', color: '#4f46e5', bg: '#eef2ff' } : DUE_STATE[r.state]
            const unit = r.tracking_unit === 'mh' ? 'MH' : 'km'
            const isEd = editing === r.schedule_id
            return (
              <tr key={r.schedule_id} className="md:max-lg:!grid md:max-lg:grid-cols-2 md:max-lg:gap-x-4" style={{ borderBottom: '1px solid #d4e8e0' }}>
                <TD><span className="text-xs font-extrabold rounded-full max-lg:whitespace-nowrap" style={{ padding: '2px 8px', background: st.bg, color: st.color }}>{st.label}</span></TD>
                <TD bold><span className="cursor-pointer" onClick={() => navigate(`/servis/motorka/${r.moto_id}`)} title="Servisní knížka">{r.model}</span><div className="text-xs font-mono font-normal" style={{ color: '#6b7280' }}>{r.spz}</div></TD>
                <TD>{r.label}{r.group_label && <div className="text-xs" style={{ color: '#9ca3af' }}>{r.group_label}{r.source ? ` · ${SOURCE_LABELS[r.source] || r.source}` : ''}</div>}</TD>
                <TD>{r.isStk ? '2 roky' : intervalText(r, unit)}</TD>
                <TD>{r.isStk ? '—' : <>{r.last_date ? fmtDate(r.last_date) : '—'}{r.last_km != null ? ` · ${fmtKm(r.last_km, unit)}` : ''}<div className="text-xs" style={{ color: '#9ca3af' }}>{BASELINE_LABELS[r.baseline_source] || ''}</div></>}</TD>
                <TD color={st.color} bold>{r.isStk ? (r.days_remaining === null ? 'STK nenastaveno' : r.days_remaining <= 0 ? `${-r.days_remaining} dní po` : `${r.days_remaining} dní`) : dueText(r, unit)}</TD>
                <TD>
                  {r.isStk ? fmtDate(r.next_date) : isEd ? (
                    <span className="flex items-center gap-1 max-lg:flex-wrap max-lg:justify-end">
                      <input type="date" value={dateVal} onChange={e => setDateVal(e.target.value)} className="rounded text-xs px-1 py-0.5" style={{ border: '1px solid #d1d5db' }} />
                      <button onClick={() => saveDate(r, dateVal)} disabled={busy === r.schedule_id} className="text-xs font-bold cursor-pointer max-lg:text-base max-lg:px-2 max-lg:py-1.5" style={{ color: '#1a8a18', background: 'none', border: 'none' }}>✓</button>
                      <button onClick={() => setEditing(null)} className="text-xs cursor-pointer max-lg:text-base max-lg:px-2 max-lg:py-1.5" style={{ color: '#6b7280', background: 'none', border: 'none' }}>✕</button>
                    </span>
                  ) : (
                    <span className="cursor-pointer" onClick={() => { setEditing(r.schedule_id); setDateVal(r.planned_date || isoDateOf(r.est_date) || '') }} title="Klikněte pro ruční termín">
                      {r.planned_date ? <b style={{ color: '#2563eb' }}>{fmtDate(r.planned_date)}</b> : r.est_date ? <>{fmtDate(r.est_date)} <span style={{ fontSize: 10, color: '#6b7280' }} title={`odhad z Ø ${r.avg_daily_km} ${unit}/den`}>~</span></> : '—'}
                      {r.planned_date && <button onClick={e => { e.stopPropagation(); saveDate(r, null) }} className="ml-1 text-xs cursor-pointer max-lg:text-base max-lg:px-2 max-lg:py-1" style={{ color: '#6b7280', background: 'none', border: 'none' }} title="Zrušit ruční termín">↺</button>}
                    </span>
                  )}
                </TD>
                <TD>{!r.isStk && !r.open_log_id && r.state !== 'unknown' && <button onClick={() => plan(r)} disabled={busy === r.schedule_id} className="text-xs font-bold cursor-pointer max-lg:py-2 max-lg:px-1" style={{ color: '#1a8a18', background: 'none', border: 'none' }}>Naplánovat</button>}
                    {r.open_log_id && <button onClick={() => navigate(`/servis/motorka/${r.moto_id}`)} className="text-xs font-bold cursor-pointer max-lg:py-2 max-lg:px-1" style={{ color: '#4f46e5', background: 'none', border: 'none' }}>otevřít</button>}</TD>
              </tr>
            )
          })}
          {list.length === 0 && <tr style={{ borderBottom: '1px solid #d4e8e0' }}><TD label="">{filter === 'attention' ? 'Nic k řešení — všechny intervaly v pořádku.' : 'Žádné plány pro zvolený filtr.'}</TD></tr>}
        </tbody>
      </Table>
      <div className="mt-3 text-xs" style={{ color: '#6b7280' }}>~ = odhad termínu z průměrného denního nájezdu od pořízení · klikněte na datum pro ruční termín · „Neověřeno“ = v servisní knížce motorky doplňte poslední provedení</div>
    </div>
  )
}
