import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../ui/Button'

export default function ReplacementMotoPicker({ branchId, excludeMotoId, onSelect, onCancel }) {
  const [motos, setMotos] = useState([])
  const [branches, setBranches] = useState([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState(null)
  const [filter, setFilter] = useState('all')

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const [mRes, bRes] = await Promise.all([
      supabase.from('motorcycles').select('id, model, spz, status, branch_id, category, branches(name, type)')
        .in('status', ['active', 'out_of_service', 'maintenance']).neq('id', excludeMotoId || ''),
      supabase.from('branches').select('id, name, type').eq('active', true),
    ])
    setMotos(mRes.data || [])
    setBranches(bRes.data || [])
    setLoading(false)
  }

  // Group: 1) deactivated/out_of_service motos, 2) from staffed branches with surplus, 3) without branch
  const grouped = {
    deactivated: motos.filter(m => m.status === 'out_of_service' || m.status === 'maintenance'),
    staffed: motos.filter(m => m.status === 'active' && m.branches?.type === 'obslužná' && m.branch_id !== branchId),
    noBranch: motos.filter(m => m.status === 'active' && !m.branch_id),
  }

  const filtered = filter === 'all' ? [...grouped.deactivated, ...grouped.staffed, ...grouped.noBranch]
    : filter === 'deactivated' ? grouped.deactivated
    : filter === 'staffed' ? grouped.staffed : grouped.noBranch

  const statusLabel = { active: 'Aktivní', out_of_service: 'Mimo provoz', maintenance: 'V servisu' }
  const statusColor = { active: '#1a8a18', out_of_service: '#7c3aed', maintenance: '#b45309' }

  if (loading) return <div className="py-4 text-center text-sm" style={{ color: '#6b7280' }}>Načítám dostupné motorky…</div>

  return (
    <div>
      <div className="flex gap-1 mb-3 flex-wrap">
        {[['all', 'Vše'], ['deactivated', `Mimo provoz (${grouped.deactivated.length})`], ['staffed', `Obslužné pob. (${grouped.staffed.length})`], ['noBranch', `Bez pobočky (${grouped.noBranch.length})`]].map(([k, l]) => (
          <button key={k} onClick={() => setFilter(k)} className="rounded-btn text-xs font-bold cursor-pointer"
            style={{ padding: '4px 10px', background: filter === k ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none' }}>{l}</button>
        ))}
      </div>
      <div style={{ maxHeight: 250, overflowY: 'auto' }} className="space-y-1">
        {filtered.map(m => (
          <div key={m.id} onClick={() => setSelected(m.id)} className="flex items-center gap-2 p-2 rounded cursor-pointer"
            style={{ background: selected === m.id ? '#dcfce7' : '#f9fafb', border: `1px solid ${selected === m.id ? '#1a8a18' : '#e5e7eb'}` }}>
            <input type="radio" checked={selected === m.id} readOnly style={{ accentColor: '#1a8a18' }} />
            <div className="flex-1">
              <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{m.model}</span>
              <span className="text-sm font-mono ml-2" style={{ color: '#6b7280' }}>{m.spz}</span>
            </div>
            <span className="text-xs font-bold" style={{ color: statusColor[m.status] || '#6b7280' }}>{statusLabel[m.status] || m.status}</span>
            <span className="text-xs" style={{ color: '#6b7280' }}>{m.branches?.name || 'Bez pobočky'}</span>
          </div>
        ))}
        {filtered.length === 0 && <div className="text-sm py-4 text-center" style={{ color: '#6b7280' }}>Žádné dostupné motorky</div>}
      </div>
      <div className="flex gap-2 mt-3 justify-end">
        <Button onClick={onCancel}>Zrušit</Button>
        <Button green onClick={() => selected && onSelect(motos.find(m => m.id === selected))} disabled={!selected}>Vybrat náhradu</Button>
      </div>
    </div>
  )
}
