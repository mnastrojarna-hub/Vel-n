import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import { useAdminIdentity } from '../../hooks/useAdminIdentity'
import { fetchServiceDue, groupDueByMoto, DUE_STATE, dueText, fmtDate, fmtKm, logState, LOG_STATE, planServiceFromDue } from '../../lib/serviceBook'
import { computeBundle, planServiceBundle } from '../../lib/serviceBundle'

/**
 * Servis → Přehled: co je potřeba řešit (hlídání intervalů z DB — po termínu / blíží se / neověřeno),
 * moje otevřené servisy (technik = přihlášený účet), nadcházející naplánované servisy.
 */
export default function ServiceOverview({ onOpenMoto }) {
  const me = useAdminIdentity()
  const navigate = useNavigate()
  const [due, setDue] = useState([])
  const [open, setOpen] = useState([])
  const [loading, setLoading] = useState(true)
  const [onlyMine, setOnlyMine] = useState(false)
  const [busy, setBusy] = useState(null)
  const [msg, setMsg] = useState(null)

  useEffect(() => { load() }, [])
  async function load() {
    setLoading(true)
    const [d, o] = await Promise.all([
      fetchServiceDue(null).catch(() => []),
      supabase.from('maintenance_log').select('id, moto_id, service_date, scheduled_date, status, description, is_urgent, items, performed_by, technician_admin_id, created_by, motorcycles!moto_id(model, spz, mileage, tracking_unit, branches(name))').is('completed_date', null).not('is_test', 'is', true).order('service_date'),
    ])
    setDue(d); setOpen(o.data || []); setLoading(false)
  }

  const groups = groupDueByMoto(due).filter(g => g.overdue + g.due_soon + g.unknown > 0)
  const totals = due.reduce((a, r) => { if (r.open_log_id) a.planned++; else a[r.state] = (a[r.state] || 0) + 1; return a }, { overdue: 0, due_soon: 0, unknown: 0, ok: 0, planned: 0 })
  const mine = open.filter(l => l.technician_admin_id === me?.id || l.created_by === me?.id)
  const shownOpen = onlyMine ? mine : open
  const goMoto = (id) => onOpenMoto ? onOpenMoto(id) : navigate(`/servis/motorka/${id}`)

  async function plan(d) {
    setBusy(d.schedule_id); setMsg(null)
    try { const r = await planServiceFromDue(d); if (r) { setMsg(`Naplánováno: ${d.model} — ${d.label}`); load() } } catch (e) { setMsg(e.message) } finally { setBusy(null) }
  }
  // Sdružený servis motorky: po termínu + blížící se + co dozraje do 2 000 km / 60 dní → jeden záznam
  async function planBundle(g) {
    const b = computeBundle(g.rows); if (!b) return
    if (!window.confirm(`${g.model}: naplánovat jeden společný servis (${b.items.length} úkonů) na ${fmtDate(b.date)}?\n${b.items.map(r => '• ' + r.label).join('\n')}`)) return
    setBusy(g.moto_id); setMsg(null)
    try { const r = await planServiceBundle(g.moto_id, b.items, { date: b.date }); if (r) { setMsg(`Naplánován společný servis: ${g.model} (${b.items.length} úkonů) na ${fmtDate(b.date)}`); load() } } catch (e) { setMsg(e.message) } finally { setBusy(null) }
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  const Tile = ({ k, label, value, color }) => (
    <div className="p-3 rounded-lg" style={{ background: DUE_STATE[k]?.bg || '#eef2ff', border: `1px solid ${DUE_STATE[k]?.border || '#c7d2fe'}` }}>
      <div className="text-xs font-extrabold uppercase" style={{ color: color || DUE_STATE[k]?.color }}>{label}</div>
      <div className="text-xl font-extrabold" style={{ color: '#0f1a14' }}>{value}</div>
    </div>
  )

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        <Tile k="overdue" label="Po termínu" value={totals.overdue} />
        <Tile k="due_soon" label="Blíží se" value={totals.due_soon} />
        <Tile k="unknown" label="Neověřeno" value={totals.unknown} />
        <Tile k="ok" label="V pořádku" value={totals.ok} />
        <Tile k="planned" label="Naplánováno" value={totals.planned} color="#4f46e5" />
      </div>
      {msg && <div className="text-sm p-2 rounded" style={{ background: '#dcfce7', color: '#1a8a18' }}>{msg}</div>}

      <Card>
        <div className="flex items-center justify-between mb-3 flex-wrap gap-2">
          <h3 className="text-sm font-extrabold uppercase tracking-widest" style={{ color: '#1a2e22' }}>Otevřené servisy ({shownOpen.length})</h3>
          <label className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: '#1a2e22' }}>
            <input type="checkbox" checked={onlyMine} onChange={e => setOnlyMine(e.target.checked)} style={{ accentColor: '#16a34a' }} /> jen moje ({mine.length})
          </label>
        </div>
        {shownOpen.length === 0 ? <p className="text-sm" style={{ color: '#6b7280' }}>Žádné otevřené servisy.</p> : (
          <div className="space-y-1">
            {shownOpen.map(l => {
              const st = LOG_STATE[logState(l)]; const m = l.motorcycles
              const items = (l.items || []).filter(i => i?.label)
              return (
                <div key={l.id} onClick={() => goMoto(l.moto_id)} className="flex items-center gap-3 flex-wrap p-2 rounded-lg cursor-pointer hover:bg-[#f1faf7]" style={{ border: '1px solid #e5efe9' }}>
                  <span className="text-xs font-extrabold rounded-full" style={{ padding: '1px 8px', background: st.bg, color: st.color }}>{st.label}</span>
                  {l.is_urgent && <span className="text-xs font-bold px-1.5 rounded" style={{ background: '#dc2626', color: '#fff' }}>URGENT</span>}
                  <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{m?.model}</span>
                  <span className="font-mono text-xs" style={{ color: '#1a2e22' }}>{m?.spz}</span>
                  <span className="text-xs" style={{ color: '#6b7280' }}>{m?.branches?.name || ''}</span>
                  <span className="text-xs" style={{ color: '#1a2e22' }}>od {fmtDate(l.service_date)}{l.scheduled_date ? ` → ${fmtDate(l.scheduled_date)}` : ''}</span>
                  <span className="text-xs flex-1 truncate max-md:basis-full" style={{ color: '#1a2e22' }}>{items.length > 0 ? `${items.filter(i => i.done).length}/${items.length} úkonů: ${items.slice(0, 4).map(i => i.label).join(', ')}${items.length > 4 ? '…' : ''}` : (l.description || '')}</span>
                  <span className="text-xs font-bold" style={{ color: '#1a2e22' }}>{l.performed_by || '—'}</span>
                </div>
              )
            })}
          </div>
        )}
      </Card>

      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-widest mb-1" style={{ color: '#1a2e22' }}>Hlídání intervalů — co motorkám chybí</h3>
        <p className="text-xs mb-3" style={{ color: '#6b7280' }}>Z plánů údržby (výrobce / standard) a dokončených servisů. „Neověřeno“ = chybí záznam o posledním provedení — doplňte v servisní knížce motorky.</p>
        {groups.length === 0 ? <p className="text-sm" style={{ color: '#1a8a18' }}>Vše v pořádku — žádný interval po termínu ani blížící se.</p> : (
          <div className="space-y-2">
            {groups.map(g => (
              <div key={g.moto_id} className="rounded-lg" style={{ border: '1px solid #d4e8e0' }}>
                <div className="flex items-center gap-3 flex-wrap p-2 cursor-pointer" style={{ background: g.overdue ? '#fee2e2' : g.due_soon ? '#fef3c7' : '#f3f4f6' }} onClick={() => goMoto(g.moto_id)}>
                  <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{g.model}</span>
                  <span className="font-mono text-xs" style={{ color: '#1a2e22' }}>{g.spz}</span>
                  <span className="text-xs" style={{ color: '#1a2e22' }}>{fmtKm(g.rows[0]?.current_km, g.tracking_unit === 'mh' ? 'MH' : 'km')}</span>
                  <span className="ml-auto flex gap-2 text-xs font-bold max-md:ml-0 max-md:w-full max-md:flex-wrap max-md:items-center max-md:gap-x-3 max-md:gap-y-1">
                    {g.overdue > 0 && <span style={{ color: DUE_STATE.overdue.color }}>{g.overdue} po termínu</span>}
                    {g.due_soon > 0 && <span style={{ color: DUE_STATE.due_soon.color }}>{g.due_soon} blíží se</span>}
                    {g.unknown > 0 && <span style={{ color: DUE_STATE.unknown.color }}>{g.unknown} neověřeno</span>}
                    {computeBundle(g.rows) && <button onClick={e => { e.stopPropagation(); planBundle(g) }} disabled={busy === g.moto_id} className="rounded-btn font-extrabold uppercase cursor-pointer px-[10px] py-[2px] max-lg:py-2" style={{ background: '#74FB71', color: '#1a2e22', border: 'none', fontSize: 11 }} title="Založí jeden servisní záznam se všemi úkony po termínu / blížícími se">Naplánovat společně</button>}
                    <span style={{ color: '#2563eb' }}>servisní knížka →</span>
                  </span>
                </div>
                <div className="p-2 grid grid-cols-1 md:grid-cols-2 gap-1">
                  {g.rows.filter(r => !r.open_log_id && r.state !== 'ok').map(r => (
                    <div key={r.schedule_id} className="flex items-center gap-2 text-sm rounded max-md:flex-wrap" style={{ padding: '3px 6px', background: '#fff', border: `1px solid ${DUE_STATE[r.state].border}` }}>
                      <span style={{ color: DUE_STATE[r.state].color, fontSize: 10 }}>●</span>
                      <span className="font-bold flex-1 max-md:basis-[calc(100%-24px)]" style={{ color: '#0f1a14' }}>{r.label}</span>
                      <span className="text-xs max-md:flex-1 max-md:pl-4" style={{ color: DUE_STATE[r.state].color }}>{r.state === 'unknown' ? 'doplnit poslední provedení' : dueText(r, g.tracking_unit === 'mh' ? 'MH' : 'km')}</span>
                      {r.state !== 'unknown' && <button onClick={e => { e.stopPropagation(); plan(r) }} disabled={busy === r.schedule_id} className="text-xs font-bold cursor-pointer max-lg:px-2 max-lg:py-2" style={{ background: 'none', border: 'none', color: '#1a8a18' }}>naplánovat</button>}
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  )
}
