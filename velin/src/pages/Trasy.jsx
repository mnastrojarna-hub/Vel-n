import { useState, useEffect, Component } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Card from '../components/ui/Card'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import SearchInput from '../components/ui/SearchInput'
import { StatCard, SmallBtn } from './BranchHelpers'
import TrasyModal from './TrasyModal'
import TrasyReviewsModal from './TrasyReviewsModal'

// ─── Error boundary (stejný vzor jako Branches) ──────────────────────
class TrasyErrorBoundary extends Component {
  constructor(props) { super(props); this.state = { hasError: false, error: null } }
  static getDerivedStateFromError(error) { return { hasError: true, error } }
  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: 24 }}>
          <div className="p-4 rounded-card" style={{ background: '#fee2e2', color: '#dc2626' }}>
            <p className="font-bold mb-2">Chyba při zobrazení tras</p>
            <p className="text-sm mb-3">{this.state.error?.message || 'Neznámá chyba'}</p>
            <button onClick={() => { this.setState({ hasError: false, error: null }) }}
              className="rounded-btn text-sm font-bold cursor-pointer"
              style={{ padding: '6px 14px', background: '#dc2626', color: '#fff', border: 'none' }}>
              Zkusit znovu
            </button>
          </div>
        </div>
      )
    }
    return this.props.children
  }
}

export default function TrasyPage() {
  return (
    <TrasyErrorBoundary>
      <Trasy />
    </TrasyErrorBoundary>
  )
}

const TYPE_LABEL = { loop: 'Okruh', poi: 'Za body zájmu' }
const DIFF_LABEL = { easy: 'Lehká', medium: 'Střední', hard: 'Náročná' }

function Trasy() {
  const [routes, setRoutes] = useState([])
  const [branches, setBranches] = useState([])
  const [poiCounts, setPoiCounts] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [search, setSearch] = useState('')
  const [branchFilter, setBranchFilter] = useState('all')
  const [showModal, setShowModal] = useState(false)
  const [editing, setEditing] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [pendingPois, setPendingPois] = useState([])
  const [reviewStats, setReviewStats] = useState({})
  const [reviewsFor, setReviewsFor] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const [routesRes, branchesRes] = await Promise.all([
        supabase.from('routes').select('*').order('sort_order').order('distance_km'),
        supabase.from('branches').select('id, name, city, gps_lat, gps_lng, active').order('name'),
      ])
      if (routesRes.error) {
        const e = routesRes.error
        throw new Error(
          `Načtení tras selhalo: ${e.message || 'neznámá chyba'}` +
          (e.code === '42P01' || (e.message || '').includes('does not exist')
            ? '\n\nTabulka "routes" zatím v databázi neexistuje — spusťte prosím SQL migraci tras.'
            : e.code === '42501' ? '\n\nChybí RLS politika pro tabulku "routes".' : '')
        )
      }
      setRoutes(routesRes.data || [])
      setBranches(branchesRes.data || [])

      // POI counts per route
      try {
        const { data: pois } = await supabase.from('route_pois').select('route_id')
        const c = {}
        ;(pois || []).forEach(p => { c[p.route_id] = (c[p.route_id] || 0) + 1 })
        setPoiCounts(c)
      } catch (e) { console.warn('[Trasy] POI counts failed:', e.message) }

      // Komunitní (uživatelské) body zájmu ke schválení
      try {
        const { data: up } = await supabase.from('user_pois').select('*').eq('status', 'pending').order('created_at', { ascending: false })
        setPendingPois(up || [])
      } catch (e) { console.warn('[Trasy] user_pois failed:', e.message) }

      // Agregace recenzí tras (počet + průměr, jen schválené)
      try {
        const { data: revs } = await supabase.from('route_reviews').select('route_id, rating, status')
        const agg = {}
        ;(revs || []).forEach(r => {
          if (r.status !== 'approved') return
          const a = agg[r.route_id] || { sum: 0, count: 0 }
          a.sum += r.rating; a.count += 1; agg[r.route_id] = a
        })
        const stats = {}
        Object.entries(agg).forEach(([id, a]) => { stats[id] = { avg: Math.round((a.sum / a.count) * 10) / 10, count: a.count } })
        setReviewStats(stats)
      } catch (e) { console.warn('[Trasy] route_reviews failed:', e.message) }
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  async function handleDelete(route) {
    try {
      // route_pois mají ON DELETE CASCADE, ale smažeme explicitně pro jistotu
      await supabase.from('route_pois').delete().eq('route_id', route.id)
      const result = await debugAction('routes.delete', 'Trasy', () =>
        supabase.from('routes').delete().eq('id', route.id)
      , { route_id: route.id, name: route.name })
      if (result?.error) {
        setError(`Smazání selhalo: ${result.error.message}`)
        setDeleteConfirm(null)
        return
      }
      await logAudit('route_deleted', { name: route.name })
      setDeleteConfirm(null)
      load()
    } catch (e) {
      setError(`Smazání selhalo: ${e.message}`)
      setDeleteConfirm(null)
    }
  }

  async function toggleActive(route) {
    const next = !route.is_active
    try {
      const { error: err } = await supabase
        .from('routes')
        .update({ is_active: next, updated_at: new Date().toISOString() })
        .eq('id', route.id)
      if (err) throw err
      await logAudit(next ? 'route_activated' : 'route_deactivated', { name: route.name })
      load()
    } catch (e) {
      setError(`Změna stavu selhala: ${e.message}`)
    }
  }

  async function setPoiStatus(poi, status) {
    try {
      const { error: err } = await supabase.from('user_pois')
        .update({ status, updated_at: new Date().toISOString() }).eq('id', poi.id)
      if (err) throw err
      setPendingPois(ps => ps.filter(p => p.id !== poi.id))
      await logAudit(status === 'approved' ? 'user_poi_approved' : 'user_poi_rejected', { name: poi.name })
    } catch (e) {
      setError(`Změna stavu bodu zájmu selhala: ${e.message}`)
    }
  }

  async function rejectRoute(route) {
    try {
      const { error: err } = await supabase.from('routes')
        .update({ status: 'rejected', is_active: false, updated_at: new Date().toISOString() }).eq('id', route.id)
      if (err) throw err
      await logAudit('route_rejected', { name: route.name })
      load()
    } catch (e) {
      setError(`Zamítnutí trasy selhalo: ${e.message}`)
    }
  }

  const branchName = (id) => branches.find(b => b.id === id)?.name || '—'

  const pendingRoutes = routes.filter(r => r.status === 'pending')

  const filtered = routes.filter(r => {
    if (branchFilter !== 'all' && r.branch_id !== branchFilter) return false
    if (!search) return true
    const s = search.toLowerCase()
    return (r.name || '').toLowerCase().includes(s) ||
      (r.description || '').toLowerCase().includes(s) ||
      branchName(r.branch_id).toLowerCase().includes(s)
  })

  const activeCount = routes.filter(r => r.is_active).length
  const loopCount = routes.filter(r => r.route_type === 'loop').length
  const totalPois = Object.values(poiCounts).reduce((s, v) => s + v, 0)

  return (
    <div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-5">
        <StatCard label="Tras celkem" value={routes.length} color="#0f1a14" />
        <StatCard label="Publikované" value={activeCount} color="#1a8a18" />
        <StatCard label="Okruhy" value={loopCount} color="#2563eb" />
        <StatCard label="Body zájmu" value={totalPois} color="#8b5cf6" />
      </div>

      <div className="flex items-center gap-3 mb-5 flex-wrap">
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat trasu, pobočku…" />
        <select
          value={branchFilter}
          onChange={e => setBranchFilter(e.target.value)}
          className="rounded-btn text-sm font-bold outline-none cursor-pointer"
          style={{ padding: '7px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="all">Všechny pobočky</option>
          {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
        </select>
        <div className="ml-auto">
          <Button green onClick={() => { setEditing(null); setShowModal(true) }}>+ Nová trasa</Button>
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13, whiteSpace: 'pre-wrap' }}>
          {error}
          <button onClick={() => { setError(null); load() }} className="ml-3 underline cursor-pointer font-bold"
            style={{ background: 'none', border: 'none', color: '#dc2626' }}>
            Zkusit znovu
          </button>
        </div>
      )}

      {(pendingRoutes.length > 0 || pendingPois.length > 0) && (
        <div className="mb-5 rounded-card" style={{ background: '#fff7ed', border: '1px solid #fdba74', padding: 14 }}>
          <div className="text-sm font-extrabold mb-3" style={{ color: '#b45309' }}>
            🔔 Komunitní návrhy ke schválení ({pendingRoutes.length + pendingPois.length})
          </div>

          {pendingRoutes.map(r => (
            <div key={r.id} className="flex items-center gap-3 mb-2 rounded-btn" style={{ background: '#fff', padding: '8px 10px', border: '1px solid #fed7aa' }}>
              <span className="text-xs font-bold" style={{ background: '#8b5cf6', color: '#fff', padding: '2px 7px', borderRadius: 6 }}>TRASA</span>
              <div className="flex-1 min-w-0">
                <div className="text-sm font-bold truncate" style={{ color: '#1a2e22' }}>{r.name}</div>
                {r.mapy_url && <a href={r.mapy_url} target="_blank" rel="noreferrer" className="text-xs underline truncate block" style={{ color: '#2563eb' }}>{r.mapy_url}</a>}
              </div>
              <Button small onClick={() => { setEditing(r); setShowModal(true) }}>Otevřít & doplnit</Button>
              <button onClick={() => rejectRoute(r)} className="text-xs font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#dc2626' }}>Zamítnout</button>
            </div>
          ))}

          {pendingPois.map(p => (
            <div key={p.id} className="flex items-center gap-3 mb-2 rounded-btn" style={{ background: '#fff', padding: '8px 10px', border: '1px solid #fed7aa' }}>
              {p.image_url
                ? <img src={p.image_url} alt={p.name} style={{ width: 44, height: 44, objectFit: 'cover', borderRadius: 8 }} onError={e => { e.target.style.opacity = 0.3 }} />
                : <div style={{ width: 44, height: 44, borderRadius: 8, background: '#e2f5ec', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>📍</div>}
              <span className="text-xs font-bold" style={{ background: '#1a8a18', color: '#fff', padding: '2px 7px', borderRadius: 6 }}>BOD</span>
              <div className="flex-1 min-w-0">
                <div className="text-sm font-bold truncate" style={{ color: '#1a2e22' }}>{p.name}</div>
                <div className="text-xs" style={{ color: '#6b8f7b' }}>
                  {p.description ? `${p.description.slice(0, 60)} · ` : ''}{Number(p.lat).toFixed(4)}, {Number(p.lng).toFixed(4)}
                </div>
              </div>
              <Button small green onClick={() => setPoiStatus(p, 'approved')}>Schválit</Button>
              <button onClick={() => setPoiStatus(p, 'rejected')} className="text-xs font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#dc2626' }}>Zamítnout</button>
            </div>
          ))}
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" />
        </div>
      ) : routes.length === 0 && !error ? (
        <Card>
          <div className="text-center py-12">
            <div className="text-4xl mb-3">🛣️</div>
            <div className="text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Žádné trasy</div>
            <div className="text-sm mb-4" style={{ color: '#1a2e22' }}>
              Zatím nemáte vytvořené žádné doporučené trasy. Vytvořte první trasu kliknutím na tlačítko výše.
            </div>
            <Button green onClick={() => { setEditing(null); setShowModal(true) }}>+ Vytvořit trasu</Button>
          </div>
        </Card>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Náhled</TH><TH>Název</TH><TH>Pobočka</TH><TH>Typ</TH><TH>Délka</TH>
              <TH>Body zájmu</TH><TH>Recenze</TH><TH>Stav</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {filtered.map(r => (
              <tr key={r.id}
                className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                style={{ borderBottom: '1px solid #d4e8e0', opacity: r.is_active ? 1 : 0.5 }}
                onClick={() => { setEditing(r); setShowModal(true) }}>
                <TD>
                  {r.cover_image ? (
                    <img src={r.cover_image} alt={r.name} loading="lazy"
                      style={{ width: 56, height: 38, objectFit: 'cover', borderRadius: 8, border: '1px solid #d4e8e0' }}
                      onError={e => { e.target.style.opacity = 0.3 }} />
                  ) : (
                    <div style={{ width: 56, height: 38, borderRadius: 8, background: '#e2f5ec', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18 }}>🛣️</div>
                  )}
                </TD>
                <TD bold>{r.name}</TD>
                <TD>{branchName(r.branch_id)}</TD>
                <TD>{TYPE_LABEL[r.route_type] || r.route_type || '—'}</TD>
                <TD bold>{r.distance_km ? `${r.distance_km} km` : '—'}</TD>
                <TD>
                  <span className="font-bold" style={{ color: poiCounts[r.id] > 0 ? '#8b5cf6' : '#1a2e22' }}>
                    {poiCounts[r.id] || 0}
                  </span>
                </TD>
                <TD>
                  <button onClick={e => { e.stopPropagation(); setReviewsFor(r) }}
                    className="cursor-pointer text-sm font-bold" style={{ background: 'none', border: 'none', color: reviewStats[r.id] ? '#f59e0b' : '#6b8f7b' }}
                    title="Zobrazit / moderovat recenze">
                    {reviewStats[r.id] ? `★ ${reviewStats[r.id].avg} (${reviewStats[r.id].count})` : '—'}
                  </button>
                </TD>
                <TD>
                  <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                    style={{ padding: '3px 8px', background: r.is_active ? '#dcfce7' : '#fee2e2', color: r.is_active ? '#1a8a18' : '#dc2626' }}>
                    {r.is_active ? 'Publikováno' : 'Skryto'}
                  </span>
                </TD>
                <TD>
                  <div className="flex gap-1" onClick={e => e.stopPropagation()}>
                    <SmallBtn color="#2563eb" onClick={() => { setEditing(r); setShowModal(true) }}>Upravit</SmallBtn>
                    <SmallBtn color={r.is_active ? '#b45309' : '#1a8a18'} onClick={() => toggleActive(r)}>
                      {r.is_active ? 'Skrýt' : 'Publikovat'}
                    </SmallBtn>
                    <SmallBtn color="#dc2626" onClick={() => setDeleteConfirm(r)}>Smazat</SmallBtn>
                  </div>
                </TD>
              </tr>
            ))}
            {filtered.length === 0 && routes.length > 0 && (
              <TRow><TD>Žádné trasy neodpovídají filtru</TD></TRow>
            )}
          </tbody>
        </Table>
      )}

      {showModal && (
        <TrasyModal
          existing={editing}
          branches={branches}
          onClose={() => { setShowModal(false); setEditing(null) }}
          onSaved={() => { setShowModal(false); setEditing(null); load() }}
        />
      )}

      {reviewsFor && (
        <TrasyReviewsModal
          route={reviewsFor}
          onClose={() => setReviewsFor(null)}
          onChanged={load}
        />
      )}

      {deleteConfirm && (
        <ConfirmDialog
          open title="Smazat trasu?"
          message={`Opravdu chcete smazat trasu "${deleteConfirm.name}"?${
            poiCounts[deleteConfirm.id] > 0 ? `\n\n⚠️ Smaže se i ${poiCounts[deleteConfirm.id]} bodů zájmu.` : ''
          }`}
          danger onConfirm={() => handleDelete(deleteConfirm)}
          onCancel={() => setDeleteConfirm(null)}
        />
      )}
    </div>
  )
}

export { TYPE_LABEL, DIFF_LABEL }
