import { useState, useEffect, Component } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Card from '../components/ui/Card'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import SearchInput from '../components/ui/SearchInput'
import { StatCard, SmallBtn } from './BranchHelpers'
import TrasyModal, { computeGeometry } from './TrasyModal'
import TrasyReviewsModal from './TrasyReviewsModal'
import TrasyKatalogMist from './TrasyKatalogMist'

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
  const [poiCounts, setPoiCounts] = useState({})
  const [catalogCount, setCatalogCount] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [tab, setTab] = useState('routes')              // 'routes' | 'catalog'
  const [search, setSearch] = useState('')
  const [countryFilter, setCountryFilter] = useState('all')
  const [sortBy, setSortBy] = useState('default')       // řazení seznamu tras
  const [showModal, setShowModal] = useState(false)
  const [editing, setEditing] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [pendingPois, setPendingPois] = useState([])
  const [reviewStats, setReviewStats] = useState({})
  const [reviewsFor, setReviewsFor] = useState(null)
  const [selected, setSelected] = useState(new Set())          // hromadný výběr tras
  const [bulkDeleteConfirm, setBulkDeleteConfirm] = useState(false)
  const [bulkGeo, setBulkGeo] = useState(null)                 // {done,total} při dopočtu map

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      // Trasy stránkovaně — PostgREST vrací max 1000 řádků na dotaz, jediný
      // select bez range uřízl seznam i „Tras celkem" na 1000.
      const allRoutes = []
      for (let from = 0; ; from += 1000) {
        const routesRes = await supabase.from('routes').select('*')
          .order('sort_order').order('distance_km').range(from, from + 999)
        if (routesRes.error) {
          const e = routesRes.error
          throw new Error(
            `Načtení tras selhalo: ${e.message || 'neznámá chyba'}` +
            (e.code === '42P01' || (e.message || '').includes('does not exist')
              ? '\n\nTabulka "routes" zatím v databázi neexistuje — spusťte prosím SQL migraci tras.'
              : e.code === '42501' ? '\n\nChybí RLS politika pro tabulku "routes".' : '')
          )
        }
        allRoutes.push(...(routesRes.data || []))
        if (!routesRes.data || routesRes.data.length < 1000) break
      }
      setRoutes(allRoutes)

      // POI counts per route — stránkovaně: PostgREST vrací max 1000 řádků
      // na dotaz, takže jediný select bez range uřízl součet na 1000.
      try {
        const c = {}
        for (let from = 0; ; from += 1000) {
          const { data: pois, error: pe } = await supabase
            .from('route_pois').select('route_id').range(from, from + 999)
          if (pe) throw pe
          ;(pois || []).forEach(p => { c[p.route_id] = (c[p.route_id] || 0) + 1 })
          if (!pois || pois.length < 1000) break
        }
        setPoiCounts(c)
      } catch (e) { console.warn('[Trasy] POI counts failed:', e.message) }

      // Katalog samostatných zajímavých míst (points_of_interest) — jen počet
      try {
        const { count } = await supabase
          .from('points_of_interest').select('id', { count: 'exact', head: true })
        setCatalogCount(count ?? 0)
      } catch (e) { console.warn('[Trasy] catalog count failed:', e.message) }

      // Komunitní (uživatelské) body zájmu ke schválení
      try {
        const { data: up } = await supabase.from('user_pois').select('*').eq('status', 'pending').order('created_at', { ascending: false })
        setPendingPois(up || [])
      } catch (e) { console.warn('[Trasy] user_pois failed:', e.message) }

      // Agregace recenzí tras (počet + průměr, jen schválené) — stránkovaně
      try {
        const revs = []
        for (let from = 0; ; from += 1000) {
          const { data: page, error: re } = await supabase
            .from('route_reviews').select('route_id, rating, status').range(from, from + 999)
          if (re) throw re
          revs.push(...(page || []))
          if (!page || page.length < 1000) break
        }
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

  // ── Hromadná správa tras ──
  const toggleSel = (id) => setSelected(prev => {
    const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n
  })

  async function bulkSetActive(active) {
    const ids = [...selected]
    try {
      const { error: err } = await supabase.from('routes')
        .update({ is_active: active, updated_at: new Date().toISOString() }).in('id', ids)
      if (err) throw err
      await logAudit(active ? 'routes_bulk_published' : 'routes_bulk_hidden', { count: ids.length })
      setSelected(new Set())
      load()
    } catch (e) { setError(`Hromadná změna selhala: ${e.message}`) }
  }

  async function bulkDelete() {
    const ids = [...selected]
    try {
      await supabase.from('route_pois').delete().in('route_id', ids)
      const { error: err } = await supabase.from('routes').delete().in('id', ids)
      if (err) throw err
      await logAudit('routes_bulk_deleted', { count: ids.length })
      setBulkDeleteConfirm(false)
      setSelected(new Set())
      load()
    } catch (e) { setError(`Hromadné smazání selhalo: ${e.message}`); setBulkDeleteConfirm(false) }
  }

  /** Hromadný dopočet geometrie (mapy) přes Mapy.com pro vybrané trasy.
   *  Přeskakuje trasy, které už geometrii mají nebo nemají aspoň 2 waypointy.
   *  Ukládá i reálnou délku/čas z routingu (zpřesní odhady generátoru). */
  async function bulkComputeMaps() {
    const targets = routes.filter(r => selected.has(r.id)
      && !(r.geometry && r.geometry.coordinates)
      && Array.isArray(r.waypoints) && r.waypoints.length >= 2)
    if (targets.length === 0) { setError('Vybrané trasy už mapu mají (nebo nemají dost bodů).'); return }
    setBulkGeo({ done: 0, total: targets.length })
    let okCount = 0
    for (const r of targets) {
      try {
        const geo = await computeGeometry(null, r.waypoints, r.route_type)
        if (geo && geo.coordinates) {
          const patch = { geometry: { coordinates: geo.coordinates }, updated_at: new Date().toISOString() }
          if (geo.length_m) patch.distance_km = Math.round(geo.length_m / 1000)
          if (geo.duration_s) patch.duration_min = Math.round(geo.duration_s / 60)
          const { error: err } = await supabase.from('routes').update(patch).eq('id', r.id)
          if (!err) okCount++
        }
      } catch {}
      setBulkGeo(g => g ? { ...g, done: g.done + 1 } : g)
      await new Promise(res => setTimeout(res, 350)) // šetrně k Mapy API
    }
    await logAudit('routes_bulk_geometry', { requested: targets.length, ok: okCount })
    setBulkGeo(null)
    setSelected(new Set())
    load()
  }

  const pendingRoutes = routes.filter(r => r.status === 'pending')

  // Všechny státy napříč trasami (pro filtr „projíždí státem")
  const allCountries = Array.from(
    new Set(routes.flatMap(r => Array.isArray(r.countries) ? r.countries : []))
  ).sort((a, b) => a.localeCompare(b, 'cs'))

  const filtered = routes.filter(r => {
    if (countryFilter !== 'all' && !(Array.isArray(r.countries) && r.countries.includes(countryFilter))) return false
    if (!search) return true
    const s = search.toLowerCase()
    return (r.name || '').toLowerCase().includes(s) ||
      (r.description || '').toLowerCase().includes(s) ||
      (Array.isArray(r.countries) && r.countries.join(' ').toLowerCase().includes(s))
  })

  // Řazení nad už vyfiltrovaným seznamem (client-side). Hodnocení bere průměr
  // ze spočítaných reviewStats; trasy bez recenzí jdou na konec.
  const sorted = [...filtered].sort((a, b) => {
    switch (sortBy) {
      case 'name': return (a.name || '').localeCompare(b.name || '', 'cs')
      case 'distance': return (b.distance_km || 0) - (a.distance_km || 0)
      case 'duration': return (b.duration_min || 0) - (a.duration_min || 0)
      case 'rating': return (reviewStats[b.id]?.avg || 0) - (reviewStats[a.id]?.avg || 0)
      case 'newest': return new Date(b.created_at || 0) - new Date(a.created_at || 0)
      default: return 0
    }
  })

  const activeCount = routes.filter(r => r.is_active).length
  const loopCount = routes.filter(r => r.route_type === 'loop').length
  const totalPois = Object.values(poiCounts).reduce((s, v) => s + v, 0)

  return (
    <div>
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-5">
        <div onClick={() => setTab('routes')} className="cursor-pointer" title="Zobrazit trasy">
          <StatCard label="Tras celkem" value={routes.length} color="#0f1a14" />
        </div>
        <StatCard label="Publikované" value={activeCount} color="#1a8a18" />
        <StatCard label="Okruhy" value={loopCount} color="#2563eb" />
        <StatCard label="Body zájmu tras" value={totalPois} color="#8b5cf6" />
        <div onClick={() => setTab('catalog')} className="cursor-pointer" title="Otevřít katalog míst">
          <StatCard label="Katalog míst" value={catalogCount ?? '…'} color="#0d9488" />
        </div>
      </div>

      {/* Přepínač: seznam tras vs. katalog samostatných zajímavých míst */}
      <div className="flex gap-2 mb-5 flex-wrap">
        {[
          { id: 'routes', label: `🛣️ Trasy (${routes.length})` },
          { id: 'catalog', label: `📍 Katalog míst (${catalogCount ?? '…'})` },
        ].map(t => (
          <button key={t.id} onClick={() => setTab(t.id)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '8px 18px',
              background: tab === t.id ? '#74FB71' : '#f1faf7',
              color: '#1a2e22',
              border: 'none',
              boxShadow: tab === t.id ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}>
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'catalog' ? (
        <TrasyKatalogMist />
      ) : (
      <>
      <div className="flex items-center gap-3 mb-5 flex-wrap">
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat trasu…" />
        {allCountries.length > 0 && (
          <select
            value={countryFilter}
            onChange={e => setCountryFilter(e.target.value)}
            className="rounded-btn text-sm font-bold outline-none cursor-pointer"
            style={{ padding: '7px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            <option value="all">🌍 Všechny státy</option>
            {allCountries.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        )}
        <select
          value={sortBy}
          onChange={e => setSortBy(e.target.value)}
          title="Řadit dle"
          className="rounded-btn text-sm font-bold outline-none cursor-pointer"
          style={{ padding: '7px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="default">↕ Řadit dle…</option>
          <option value="name">Název (A–Z)</option>
          <option value="distance">Délka</option>
          <option value="duration">Čas</option>
          <option value="rating">Hodnocení</option>
          <option value="newest">Nejnovější</option>
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

      {selected.size > 0 && (
        <div className="mb-4 flex items-center gap-3 flex-wrap rounded-card"
          style={{ background: '#eef6ff', border: '1px solid #bfdbfe', padding: '10px 14px' }}>
          <span className="text-sm font-extrabold" style={{ color: '#1d4ed8' }}>
            Vybráno tras: {selected.size}
          </span>
          <SmallBtn color="#1a8a18" onClick={() => bulkSetActive(true)}>Publikovat vybrané</SmallBtn>
          <SmallBtn color="#b45309" onClick={() => bulkSetActive(false)}>Skrýt vybrané</SmallBtn>
          <SmallBtn color="#0d9488" onClick={bulkComputeMaps}>
            {bulkGeo ? `Dopočítávám mapy… ${bulkGeo.done}/${bulkGeo.total}` : 'Dopočítat mapy'}
          </SmallBtn>
          <SmallBtn color="#dc2626" onClick={() => setBulkDeleteConfirm(true)}>Smazat vybrané</SmallBtn>
          <button onClick={() => setSelected(new Set())} className="text-sm font-bold cursor-pointer"
            style={{ background: 'none', border: 'none', color: '#6b7280' }}>✕ Zrušit výběr</button>
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
              <TH>
                <input type="checkbox" title="Vybrat vše (dle filtru)"
                  checked={filtered.length > 0 && filtered.every(r => selected.has(r.id))}
                  onChange={e => setSelected(e.target.checked ? new Set(filtered.map(r => r.id)) : new Set())} />
              </TH>
              <TH>Náhled</TH><TH>Název</TH><TH>Typ</TH><TH>Délka</TH>
              <TH>Body zájmu</TH><TH>Recenze</TH><TH>Stav</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {sorted.map(r => (
              <tr key={r.id}
                className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                style={{ borderBottom: '1px solid #d4e8e0', opacity: r.is_active ? 1 : 0.5 }}
                onClick={() => { setEditing(r); setShowModal(true) }}>
                <TD>
                  <input type="checkbox" checked={selected.has(r.id)}
                    onClick={e => e.stopPropagation()}
                    onChange={() => toggleSel(r.id)} />
                </TD>
                <TD>
                  {r.cover_image ? (
                    <img src={r.cover_image} alt={r.name} loading="lazy"
                      style={{ width: 56, height: 38, objectFit: 'cover', borderRadius: 8, border: '1px solid #d4e8e0' }}
                      onError={e => { e.target.style.opacity = 0.3 }} />
                  ) : (
                    <div style={{ width: 56, height: 38, borderRadius: 8, background: '#e2f5ec', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18 }}>🛣️</div>
                  )}
                </TD>
                <TD bold>
                  {r.name}
                  {Array.isArray(r.countries) && r.countries.length > 0 && (
                    <div className="flex gap-1 flex-wrap mt-1">
                      {r.countries.map(c => (
                        <span key={c} className="inline-block rounded-btn text-[9px] font-bold"
                          style={{ padding: '1px 6px', background: '#eef2ff', color: '#4338ca' }}>{c}</span>
                      ))}
                    </div>
                  )}
                </TD>
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
      </>
      )}

      {showModal && (
        <TrasyModal
          existing={editing}
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

      {bulkDeleteConfirm && (
        <ConfirmDialog
          open title="Smazat vybrané trasy?"
          message={`Opravdu chcete NEVRATNĚ smazat ${selected.size} tras včetně jejich bodů zájmu?`}
          danger onConfirm={bulkDelete}
          onCancel={() => setBulkDeleteConfirm(false)}
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
