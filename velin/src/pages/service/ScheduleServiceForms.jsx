import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'
import { RECURRING_INTERVALS, WEEKDAYS } from './scheduleConstants'

/* ═══ Pravidelný servis / kontrola ═══ */
export function RecurringForm({ motos, branches = [], onBack, onDone }) {
  const [selectedIds, setSelectedIds] = useState(new Set())
  const [intervalType, setIntervalType] = useState('days')
  const [intervalValue, setIntervalValue] = useState('')
  const [startDate, setStartDate] = useState(new Date().toISOString().slice(0, 10))
  const [desc, setDesc] = useState('')
  const [preferredDays, setPreferredDays] = useState(new Set([1, 2]))
  const [busy, setBusy] = useState(false)
  const [search, setSearch] = useState('')
  const [branchFilter, setBranchFilter] = useState('')

  const filtered = motos.filter(m => {
    if (branchFilter && m.branch_id !== branchFilter) return false
    if (search && !m.model?.toLowerCase().includes(search.toLowerCase()) && !m.spz?.toLowerCase().includes(search.toLowerCase())) return false
    return true
  })
  const toggle = id => setSelectedIds(prev => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n })
  function selectBranch(bId) {
    setBranchFilter(bId)
    if (bId) { const branchMotoIds = motos.filter(m => m.branch_id === bId).map(m => m.id); setSelectedIds(new Set(branchMotoIds)) }
  }
  const toggleDay = d => setPreferredDays(prev => { const n = new Set(prev); n.has(d) ? n.delete(d) : n.add(d); return n })
  const interval = RECURRING_INTERVALS.find(i => i.value === intervalType)

  async function submit() {
    if (selectedIds.size === 0 || !intervalValue) return
    setBusy(true)
    const val = Number(intervalValue)
    for (const motoId of selectedIds) {
      const payload = { moto_id: motoId, active: true, description: desc || `Pravidelný: ${interval?.label.replace('X', intervalValue)}`, schedule_type: intervalType === 'km' ? 'km_interval' : intervalType === 'reservations' ? 'reservation_interval' : 'time_interval', preferred_days: Array.from(preferredDays) }
      if (intervalType === 'days') { payload.interval_days = val; payload.next_due = startDate }
      else if (intervalType === 'km') { payload.interval_km = val; payload.next_due = startDate }
      else if (intervalType === 'monthly') { payload.interval_days = 30; payload.next_due = startDate }
      else if (intervalType === 'reservations') { payload.interval_days = null; payload.interval_km = null; payload.interval_reservations = val; payload.next_due = startDate }
      await supabase.from('maintenance_schedules').insert(payload)
    }
    setBusy(false); onDone?.()
  }

  return (
    <div>
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Pravidelný servis / kontrola</h3>
      <div className="text-xs mb-3" style={{ color: '#6b7280' }}>Opakovaný plán — systém automaticky naplánuje servisy dle zvoleného intervalu.</div>
      <div className="mb-2">
        <label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Pobočka (vybrat = označí všechny motorky na pobočce)</label>
        <select value={branchFilter} onChange={e => selectBranch(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">— Všechny pobočky —</option>
          {branches.map(b => <option key={b.id} value={b.id}>{b.name} ({b.type}){!b.active ? ' — neaktivní' : ''}</option>)}
        </select>
      </div>
      <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Hledat model / SPZ…" className="w-full rounded-btn text-sm outline-none mb-2" style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
      <div style={{ maxHeight: 150, overflowY: 'auto' }} className="space-y-1 mb-3">
        {filtered.map(m => (
          <label key={m.id} className="flex items-center gap-2 p-2 rounded cursor-pointer" style={{ background: selectedIds.has(m.id) ? '#dcfce7' : '#f9fafb', border: `1px solid ${selectedIds.has(m.id) ? '#1a8a18' : '#e5e7eb'}` }}>
            <input type="checkbox" checked={selectedIds.has(m.id)} onChange={() => toggle(m.id)} className="accent-[#1a8a18]" style={{ width: 16, height: 16 }} />
            <span className="font-bold text-sm">{m.model}</span><span className="font-mono text-xs" style={{ color: '#6b7280' }}>{m.spz}</span>
            <span className="text-xs ml-auto" style={{ color: '#6b7280' }}>{m.branches?.name || '—'}</span>
          </label>
        ))}
      </div>
      <div className="text-xs font-bold mb-3" style={{ color: '#1a2e22' }}>Vybráno: {selectedIds.size} motorek</div>
      <div className="mb-3">
        <label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Typ opakování</label>
        <div className="flex flex-wrap gap-2">
          {RECURRING_INTERVALS.map(i => (
            <button key={i.value} onClick={() => setIntervalType(i.value)} className="rounded-btn text-xs font-bold cursor-pointer" style={{ padding: '6px 12px', border: 'none', background: intervalType === i.value ? '#7c3aed' : '#f1faf7', color: intervalType === i.value ? '#fff' : '#1a2e22' }}>{i.label.replace('X', '…')}</button>
          ))}
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3 mb-3">
        <div><label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>{intervalType === 'days' ? 'Každých (dní)' : intervalType === 'km' ? 'Po (km)' : intervalType === 'reservations' ? 'Po (rezervacích)' : 'Den v měsíci'}</label><input type="number" min="1" value={intervalValue} onChange={e => setIntervalValue(e.target.value)} placeholder={interval?.placeholder} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} /></div>
        <div><label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Start od</label><input type="date" value={startDate} onChange={e => setStartDate(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} /></div>
      </div>
      <div className="mb-3">
        <label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Preferované dny (servis se naplánuje na nejbližší volný)</label>
        <div className="flex gap-1">
          {WEEKDAYS.map((d, i) => <button key={i} onClick={() => toggleDay(i)} className="rounded text-xs font-bold cursor-pointer" style={{ width: 36, height: 30, border: 'none', background: preferredDays.has(i) ? '#1a8a18' : '#f1faf7', color: preferredDays.has(i) ? '#fff' : '#1a2e22' }}>{d}</button>)}
        </div>
      </div>
      <div className="mb-4"><label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Popis</label><input value={desc} onChange={e => setDesc(e.target.value)} placeholder="Typ servisu / kontroly…" className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} /></div>
      <div className="flex gap-2 justify-end">
        <Button onClick={onBack}>Zpět</Button>
        <Button green onClick={submit} disabled={busy || selectedIds.size === 0 || !intervalValue}>{busy ? 'Ukládám…' : `Vytvořit plán (${selectedIds.size} motorek)`}</Button>
      </div>
    </div>
  )
}

/* ═══ Inspection checklist (shared) ═══ */
export function InspectionChecklist({ checks, setChecks }) {
  // Import INSPECTION_ITEMS inline to avoid circular deps
  const { INSPECTION_ITEMS } = require('./scheduleConstants')
  return (
    <div>
      <div className="text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Co zkontrolovat</div>
      <div className="grid grid-cols-2 gap-1" style={{ maxHeight: 160, overflowY: 'auto' }}>
        {INSPECTION_ITEMS.map(item => (
          <label key={item.id} className="flex items-center gap-2 p-1.5 rounded cursor-pointer" style={{ background: checks[item.id] ? '#dcfce7' : '#f9fafb', border: `1px solid ${checks[item.id] ? '#1a8a18' : '#e5e7eb'}` }}>
            <input type="checkbox" checked={!!checks[item.id]} onChange={e => setChecks(c => ({ ...c, [item.id]: e.target.checked }))} className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
            <span className="text-xs" style={{ fontWeight: checks[item.id] ? 700 : 400 }}>{item.label}</span>
          </label>
        ))}
      </div>
    </div>
  )
}

/* ═══ Moto picker (shared) ═══ */
export function MotoPicker({ motos, search, setSearch, onSelect }) {
  const statusColor = { active: '#1a8a18', maintenance: '#b45309', unavailable: '#7c3aed', retired: '#6b7280' }
  const statusLabel = { active: 'Aktivní', maintenance: 'V servisu', unavailable: 'Dočasně vyřazena', retired: 'Trvale vyřazena' }
  return (
    <div>
      <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Hledat model / SPZ…" className="w-full rounded-btn text-sm outline-none mb-2" style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
      <div style={{ maxHeight: 280, overflowY: 'auto' }} className="space-y-1">
        {motos.map(m => (
          <div key={m.id} onClick={() => onSelect(m.id)} className="flex items-center gap-2 p-2 rounded cursor-pointer" style={{ background: '#f9fafb', border: '1px solid #e5e7eb' }}>
            <span className="font-bold text-sm">{m.model}</span><span className="font-mono text-xs" style={{ color: '#6b7280' }}>{m.spz}</span>
            <span className="text-xs font-bold" style={{ color: statusColor[m.status] || '#6b7280' }}>{statusLabel[m.status] || m.status}</span>
            <span className="text-xs ml-auto" style={{ color: '#6b7280' }}>{m.branches?.name || '—'}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
