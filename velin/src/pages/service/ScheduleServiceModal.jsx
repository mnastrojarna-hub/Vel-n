import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import ServiceChecklistView from '../../components/fleet/ServiceChecklistView'
import { SCHEDULE_TYPES, INSPECTION_ITEMS } from './scheduleConstants'
import { RecurringForm, InspectionChecklist, MotoPicker } from './ScheduleServiceForms'

export default function ScheduleServiceModal({ open, onClose, onDone }) {
  const [type, setType] = useState(null)
  const [branches, setBranches] = useState([])
  const [allMotos, setAllMotos] = useState([])

  useEffect(() => {
    if (open) {
      setType(null)
      Promise.all([
        supabase.from('branches').select('id, name, type, active').order('name'),
        supabase.from('motorcycles').select('id, model, spz, status, branch_id, mileage, branches(name)').order('model'),
      ]).then(([b, m]) => { setBranches(b.data || []); setAllMotos(m.data || []) })
    }
  }, [open])

  if (!open) return null

  return (
    <Modal open={open} onClose={onClose} title="Naplánovat servis / kontrolu" wide>
      {!type ? (
        <div className="grid grid-cols-2 gap-3">
          {SCHEDULE_TYPES.map(t => (
            <button key={t.value} onClick={() => setType(t.value)} className="p-4 rounded-lg text-left cursor-pointer" style={{ background: '#f1faf7', border: '2px solid #d4e8e0' }}>
              <div className="text-lg mb-1">{t.icon}</div>
              <div className="text-sm font-extrabold mb-1" style={{ color: '#0f1a14' }}>{t.label}</div>
              <div className="text-xs" style={{ color: '#6b7280' }}>{t.desc}</div>
            </button>
          ))}
        </div>
      ) : type === 'single_service' ? (
        <SingleServiceForm motos={allMotos} onBack={() => setType(null)} onDone={onDone} />
      ) : type === 'inspection_moto' ? (
        <InspectionMotoForm motos={allMotos} onBack={() => setType(null)} onDone={onDone} />
      ) : type === 'inspection_branch' ? (
        <InspectionBranchForm branches={branches} motos={allMotos} onBack={() => setType(null)} onDone={onDone} />
      ) : type === 'recurring' ? (
        <RecurringForm motos={allMotos} branches={branches} onBack={() => setType(null)} onDone={onDone} />
      ) : null}
    </Modal>
  )
}

function SingleServiceForm({ motos, onBack, onDone }) {
  const [motoId, setMotoId] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [search, setSearch] = useState('')
  const filtered = motos.filter(m => !search || m.model?.toLowerCase().includes(search.toLowerCase()) || m.spz?.toLowerCase().includes(search.toLowerCase()))
  const selected = motos.find(m => m.id === motoId)

  async function handleConfirm({ selectedLabels, fullDescription, isUrgent, serviceDateFrom, serviceDateTo }) {
    if (!motoId) return
    setBusy(true); setError(null)
    try {
      const today = new Date().toISOString().slice(0, 10)
      const { data: active } = await supabase.from('bookings').select('id, status, profiles(full_name)').eq('moto_id', motoId).eq('status', 'active').gte('end_date', today)
      if (active?.length > 0) { const names = active.map(b => b.profiles?.full_name || '?').join(', '); if (!window.confirm(`Motorka má ${active.length} aktivní pronájem (${names}). Pokračovat?`)) { setBusy(false); return } }
      const { data: future } = await supabase.from('bookings').select('id, start_date, end_date, profiles(full_name)').eq('moto_id', motoId).in('status', ['pending', 'reserved']).gte('start_date', today).order('start_date').limit(5)
      if (future?.length > 0) { const lines = future.map(b => `  ${b.profiles?.full_name || '?'}: ${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}`).join('\n'); window.alert(`Upozornění — nadcházející rezervace (${future.length}):\n${lines}`) }
      const serviceStart = serviceDateFrom || today
      const isFuture = serviceStart > today
      if (!isFuture) await supabase.from('motorcycles').update({ status: 'maintenance' }).eq('id', motoId)
      const { data: newLog } = await supabase.from('maintenance_log').insert({ moto_id: motoId, description: fullDescription || 'Plánovaný servis', service_type: 'extraordinary', service_date: serviceStart, scheduled_date: serviceDateTo || null, status: isFuture ? 'pending' : 'in_service', km_at_service: Number(selected?.mileage) || null, is_urgent: isUrgent, items: selectedLabels.map(label => ({ label, done: false, note: '' })) }).select('id').single()
      await supabase.from('service_orders').insert({ moto_id: motoId, type: fullDescription || 'Mimořádný servis', notes: selectedLabels.join(', '), status: isFuture ? 'pending' : 'in_service', maintenance_log_id: newLog?.id })
      setBusy(false); onDone?.()
    } catch (e) { setError(e.message); setBusy(false) }
  }

  return (
    <div>
      {!motoId ? (
        <div>
          <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Vyberte motorku</h3>
          <MotoPicker motos={filtered} search={search} setSearch={setSearch} onSelect={setMotoId} />
          <div className="flex justify-end mt-3"><Button onClick={onBack}>Zpět</Button></div>
        </div>
      ) : (
        <div>
          <div className="flex items-center gap-2 mb-3 p-2 rounded" style={{ background: '#dcfce7', border: '1px solid #1a8a18' }}>
            <span className="font-bold text-sm">{selected?.model}</span><span className="font-mono text-sm">{selected?.spz}</span>
            <button onClick={() => setMotoId('')} className="ml-auto text-xs cursor-pointer" style={{ color: '#6b7280', background: 'none', border: 'none' }}>Změnit motorku</button>
          </div>
          <ServiceChecklistView moto={selected} onConfirm={handleConfirm} onBack={onBack} busy={busy} error={error} />
        </div>
      )}
    </div>
  )
}

function InspectionMotoForm({ motos, onBack, onDone }) {
  const [selectedIds, setSelectedIds] = useState(new Set())
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10))
  const [checks, setChecks] = useState({})
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [search, setSearch] = useState('')
  const filtered = motos.filter(m => !search || m.model?.toLowerCase().includes(search.toLowerCase()) || m.spz?.toLowerCase().includes(search.toLowerCase()))
  const toggle = id => setSelectedIds(prev => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n })

  async function submit() {
    if (selectedIds.size === 0 || !date) return
    setBusy(true)
    const items = INSPECTION_ITEMS.filter(i => checks[i.id]).map(i => ({ label: i.label, done: false, note: '' }))
    for (const motoId of selectedIds) { await supabase.from('maintenance_log').insert({ moto_id: motoId, description: note || 'Zevrubná inspekce', service_type: 'inspection', service_date: date, scheduled_date: date, status: 'pending', items: items.length > 0 ? items : null }) }
    setBusy(false); onDone?.()
  }

  return (
    <div>
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Inspekce motorek</h3>
      <div className="text-xs mb-3" style={{ color: '#1a8a18' }}>Neblokuje rezervace — motorky zůstanou aktivní.</div>
      <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Hledat model / SPZ…" className="w-full rounded-btn text-sm outline-none mb-2" style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
      <div style={{ maxHeight: 180, overflowY: 'auto' }} className="space-y-1 mb-3">
        {filtered.map(m => (
          <label key={m.id} className="flex items-center gap-2 p-2 rounded cursor-pointer" style={{ background: selectedIds.has(m.id) ? '#dcfce7' : '#f9fafb', border: `1px solid ${selectedIds.has(m.id) ? '#1a8a18' : '#e5e7eb'}` }}>
            <input type="checkbox" checked={selectedIds.has(m.id)} onChange={() => toggle(m.id)} className="accent-[#1a8a18]" style={{ width: 16, height: 16 }} />
            <span className="font-bold text-sm">{m.model}</span><span className="font-mono text-xs" style={{ color: '#6b7280' }}>{m.spz}</span>
            <span className="text-xs ml-auto" style={{ color: '#6b7280' }}>{m.branches?.name || '—'}</span>
          </label>
        ))}
      </div>
      <div className="text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Vybráno: {selectedIds.size} motorek</div>
      <InspectionChecklist checks={checks} setChecks={setChecks} />
      <div className="grid grid-cols-2 gap-3 mb-3 mt-3">
        <div><label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Datum inspekce</label><input type="date" value={date} onChange={e => setDate(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} /></div>
        <div><label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Poznámka</label><input value={note} onChange={e => setNote(e.target.value)} placeholder="Důvod inspekce…" className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} /></div>
      </div>
      <div className="flex gap-2 justify-end"><Button onClick={onBack}>Zpět</Button><Button green onClick={submit} disabled={busy || selectedIds.size === 0}>{busy ? 'Ukládám…' : `Naplánovat (${selectedIds.size})`}</Button></div>
    </div>
  )
}

function InspectionBranchForm({ branches, motos, onBack, onDone }) {
  const [branchId, setBranchId] = useState('')
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10))
  const [checks, setChecks] = useState({})
  const [note, setNote] = useState('')
  const [includeMotos, setIncludeMotos] = useState(true)
  const [busy, setBusy] = useState(false)
  const branchMotos = motos.filter(m => m.branch_id === branchId)
  const branch = branches.find(b => b.id === branchId)

  async function submit() {
    if (!branchId || !date) return
    setBusy(true)
    const items = INSPECTION_ITEMS.filter(i => checks[i.id]).map(i => ({ label: i.label, done: false, note: '' }))
    if (includeMotos && branchMotos.length > 0) {
      for (const m of branchMotos) { await supabase.from('maintenance_log').insert({ moto_id: m.id, description: `Kontrola pobočky ${branch?.name || '—'}: ${note || 'zevrubná inspekce'}`, service_type: 'inspection', service_date: date, scheduled_date: date, status: 'pending', items: items.length > 0 ? items : null }) }
    } else {
      const firstMoto = branchMotos[0]
      if (firstMoto) { await supabase.from('maintenance_log').insert({ moto_id: firstMoto.id, description: `Kontrola pobočky ${branch?.name || '—'}: ${note || 'pouze stanoviště'}`, service_type: 'inspection', service_date: date, scheduled_date: date, status: 'pending', items: items.length > 0 ? items : null }) }
    }
    setBusy(false); onDone?.()
  }

  return (
    <div>
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Kontrola pobočky</h3>
      <div className="text-xs mb-3" style={{ color: '#1a8a18' }}>Autonomní kontrola — neblokuje rezervace.</div>
      <div className="mb-3">
        <label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Pobočka</label>
        <select value={branchId} onChange={e => setBranchId(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">— Vyberte pobočku —</option>
          {branches.map(b => <option key={b.id} value={b.id}>{b.name} ({b.type}){!b.active ? ' — neaktivní' : ''}</option>)}
        </select>
      </div>
      {branchId && (<>
        <div className="mb-3 p-2 rounded" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Motorky na pobočce: {branchMotos.length}</div>
          <div className="flex flex-wrap gap-1">{branchMotos.map(m => <span key={m.id} className="text-xs px-2 py-0.5 rounded" style={{ background: '#e5e7eb' }}>{m.model}</span>)}</div>
          <label className="flex items-center gap-2 mt-2 cursor-pointer"><input type="checkbox" checked={includeMotos} onChange={e => setIncludeMotos(e.target.checked)} className="accent-[#1a8a18]" /><span className="text-xs font-bold" style={{ color: '#1a2e22' }}>Zahrnout inspekci všech motorek na pobočce</span></label>
        </div>
        <InspectionChecklist checks={checks} setChecks={setChecks} />
        <div className="grid grid-cols-2 gap-3 mb-3 mt-3">
          <div><label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Datum kontroly</label><input type="date" value={date} onChange={e => setDate(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} /></div>
          <div><label className="block text-xs font-bold mb-1" style={{ color: '#1a2e22' }}>Poznámka</label><input value={note} onChange={e => setNote(e.target.value)} placeholder="Specifický důvod kontroly…" className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} /></div>
        </div>
      </>)}
      <div className="flex gap-2 justify-end"><Button onClick={onBack}>Zpět</Button><Button green onClick={submit} disabled={busy || !branchId}>{busy ? 'Ukládám…' : 'Naplánovat kontrolu'}</Button></div>
    </div>
  )
}
