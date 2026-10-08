import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import StatusBadge from '../../components/ui/StatusBadge'
import SearchInput from '../../components/ui/SearchInput'
import { fetchServiceDue, groupDueByMoto, DUE_STATE, fmtDate, fmtKm } from '../../lib/serviceBook'

/** Servis → Servisní knížka: všechny motorky, stav hlídání, poslední servis, otevřené servisy → detail knížky. */
export default function ServiceBookIndex() {
  const navigate = useNavigate()
  const [motos, setMotos] = useState([])
  const [dueByMoto, setDueByMoto] = useState({})
  const [lastByMoto, setLastByMoto] = useState({})
  const [openByMoto, setOpenByMoto] = useState({})
  const [q, setQ] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])
  async function load() {
    const [mRes, due, logs] = await Promise.all([
      supabase.from('motorcycles').select('id, model, spz, status, mileage, tracking_unit, stk_valid_until, is_trailer, branches(name)').neq('status', 'retired').order('model'),
      fetchServiceDue(null).catch(() => []),
      supabase.from('maintenance_log').select('id, moto_id, completed_date, service_date, status, performed_by, km_at_service').not('is_test', 'is', true).order('completed_date', { ascending: false, nullsFirst: false }),
    ])
    setMotos((mRes.data || []).filter(m => !m.is_trailer))
    setDueByMoto(Object.fromEntries(groupDueByMoto(due).map(g => [g.moto_id, g])))
    const last = {}, open = {}
    for (const l of (logs.data || [])) {
      if (l.completed_date) { if (!last[l.moto_id] || last[l.moto_id].completed_date < l.completed_date) last[l.moto_id] = l }
      else open[l.moto_id] = (open[l.moto_id] || 0) + 1
    }
    setLastByMoto(last); setOpenByMoto(open); setLoading(false)
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  const norm = s => (s || '').toLowerCase()
  const list = motos.filter(m => !q || norm(m.model).includes(norm(q)) || norm(m.spz).includes(norm(q)))
    .sort((a, b) => ((dueByMoto[b.id]?.overdue || 0) - (dueByMoto[a.id]?.overdue || 0)) || a.model.localeCompare(b.model, 'cs'))

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <SearchInput value={q} onChange={setQ} placeholder="Hledat motorku / SPZ…" />
        <span className="text-xs" style={{ color: '#6b7280' }}>{list.length} motorek · klikněte pro servisní knížku (plán údržby, historie, faktury)</span>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {list.map(m => {
          const g = dueByMoto[m.id]
          const last = lastByMoto[m.id]
          const open = openByMoto[m.id] || 0
          const unit = m.tracking_unit === 'mh' ? 'MH' : 'km'
          const stkDays = m.stk_valid_until ? Math.ceil((new Date(m.stk_valid_until) - new Date()) / 86400000) : null
          const border = g?.overdue ? DUE_STATE.overdue.border : g?.due_soon ? DUE_STATE.due_soon.border : '#d4e8e0'
          return (
            <Card key={m.id} style={{ padding: 14, border: `2px solid ${border}`, cursor: 'pointer' }}>
              <div onClick={() => navigate(`/servis/motorka/${m.id}`)}>
                <div className="flex items-center gap-2 flex-wrap mb-1">
                  <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{m.model}</span>
                  <span className="font-mono text-xs" style={{ color: '#1a2e22' }}>{m.spz}</span>
                  <span className="ml-auto"><StatusBadge status={m.status} /></span>
                </div>
                <div className="text-xs mb-2" style={{ color: '#6b7280' }}>{m.branches?.name || 'bez pobočky'} · {fmtKm(m.mileage, unit)}{stkDays !== null ? ` · STK ${stkDays < 0 ? `${-stkDays} dní po` : `${stkDays} dní`}` : ''}</div>
                <div className="flex gap-2 flex-wrap text-xs font-bold mb-2">
                  {g?.overdue > 0 && <span className="rounded-full px-2" style={{ background: DUE_STATE.overdue.bg, color: DUE_STATE.overdue.color }}>{g.overdue} po termínu</span>}
                  {g?.due_soon > 0 && <span className="rounded-full px-2" style={{ background: DUE_STATE.due_soon.bg, color: DUE_STATE.due_soon.color }}>{g.due_soon} blíží se</span>}
                  {g?.unknown > 0 && <span className="rounded-full px-2" style={{ background: DUE_STATE.unknown.bg, color: DUE_STATE.unknown.color }}>{g.unknown} neověřeno</span>}
                  {open > 0 && <span className="rounded-full px-2" style={{ background: '#eef2ff', color: '#4f46e5' }}>{open} otevřený servis</span>}
                  {!g && <span className="rounded-full px-2" style={{ background: '#f3f4f6', color: '#6b7280' }}>bez plánu údržby</span>}
                  {g && !g.overdue && !g.due_soon && !g.unknown && !open && <span className="rounded-full px-2" style={{ background: DUE_STATE.ok.bg, color: DUE_STATE.ok.color }}>v pořádku</span>}
                </div>
                <div className="text-xs" style={{ color: '#1a2e22' }}>
                  Poslední servis: <b>{last ? `${fmtDate(last.completed_date)} · ${fmtKm(last.km_at_service, unit)}${last.performed_by ? ` · ${last.performed_by}` : ''}` : 'žádný zapsaný'}</b>
                </div>
              </div>
            </Card>
          )
        })}
      </div>
    </div>
  )
}
