import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Card from '../components/ui/Card'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import SearchInput from '../components/ui/SearchInput'
import { SmallBtn, Spinner, EmptyState } from './BranchHelpers'
import PoiReviewsModal from './PoiReviewsModal'

// Sekce „Zajímavá místa (katalog)" v záložce Trasy — správa tabulky
// points_of_interest (~20k samostatných bodů zájmu pro appku: přehrady,
// hrady, rozhledny, památky, rezervace…). Server-side stránkování +
// filtry (kategorie / země / zdroj / hledání), edit, aktivace, mazání.

const CAT = {
  food: '🍽️ Jídlo a pití', castle: '🏰 Hrady a zámky', lookout: '🗼 Rozhledny',
  water: '🌊 Voda', sights: '⛪ Památky', nature: '🌳 Příroda',
  military: '🪖 Vojenství', aviation: '✈️ Letectví', tech: '🏭 Technika',
  moto: '🏁 Motorismus', other: '📍 Ostatní',
}
const SOURCES = [
  ['all', 'Všechny zdroje'],
  ['curated-', 'Ruční (curated)'],
  ['wikidata-batch', 'Wikidata CZ/SK/PL/AT'],
  ['wikidata-eu-', 'Wikidata Evropa'],
  ['wikidata-cilovka-', 'Wikidata cílovka (military/aviation/tech/moto)'],
]
const COUNTRIES = ['CZ','SK','PL','AT','DE','FR','IT','ES','GB','NL','BE','CH','SI','HR','HU','RO','RS','GR','PT','IE','DK','SE','NO','FI']
const PAGE = 50

export default function TrasyKatalogMist() {
  const [rows, setRows] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(0)
  const [search, setSearch] = useState('')
  const [cat, setCat] = useState('all')
  const [country, setCountry] = useState('all')
  const [source, setSource] = useState('all')
  const [sortBy, setSortBy] = useState('default')     // default | name | newest | rating
  const [onlyPhoto, setOnlyPhoto] = useState(false)   // jen s fotkou (server-side)
  const [onlySurroundings, setOnlySurroundings] = useState(false) // jen s popisem okolí (server-side)
  const [minRating, setMinRating] = useState('all')   // min. hodnocení (client-side nad stránkou)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [editing, setEditing] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [reviewsFor, setReviewsFor] = useState(null)
  const [stats, setStats] = useState({})

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      let q = supabase.from('points_of_interest')
        .select('id, name, description, surroundings, category, country, lat, lng, image_url, source, is_active, created_at', { count: 'exact' })
      if (cat !== 'all') q = q.eq('category', cat)
      if (country !== 'all') q = q.eq('country', country)
      if (source !== 'all') q = q.like('source', `${source}%`)
      if (search) q = q.ilike('name', `%${search}%`)
      if (onlyPhoto) q = q.not('image_url', 'is', null)
      if (onlySurroundings) q = q.not('surroundings', 'is', null)
      // Server-side řazení. „Hodnocení" (rating) se řadí client-side nad
      // aktuální stránkou v derivaci `displayRows` (poi_ratings se počítají
      // až po načtení), takže na serveru zůstává výchozí pořadí.
      if (sortBy === 'name') q = q.order('name')
      else if (sortBy === 'newest') q = q.order('created_at', { ascending: false })
      else q = q.order('sort_order').order('name')
      const { data, count, error: err } = await q
        .range(page * PAGE, page * PAGE + PAGE - 1)
      if (err) throw err
      setRows(data || [])
      setTotal(count ?? 0)
      loadStats(data || [])
    } catch (e) {
      setError(`Načtení katalogu selhalo: ${e.message}`)
    } finally {
      setLoading(false)
    }
  }, [page, search, cat, country, source, onlyPhoto, onlySurroundings, sortBy])

  useEffect(() => { load() }, [load])
  // Změna filtru → zpět na první stránku
  useEffect(() => { setPage(0) }, [search, cat, country, source, onlyPhoto, onlySurroundings, sortBy])

  // Spočítá průměr a počet hodnocení (poi_ratings) pro aktuálně zobrazené body.
  async function loadStats(list) {
    const ids = list.map(p => p.id)
    if (!ids.length) { setStats({}); return }
    try {
      const { data } = await supabase.from('poi_ratings').select('poi_id, rating').in('poi_id', ids)
      const acc = {}
      ;(data || []).forEach(r => {
        if (r.poi_id == null) return
        const s = acc[r.poi_id] || (acc[r.poi_id] = { sum: 0, count: 0 })
        s.sum += Number(r.rating) || 0; s.count += 1
      })
      const map = {}
      Object.entries(acc).forEach(([id, s]) => { map[id] = { avg: (s.sum / s.count).toFixed(1), count: s.count } })
      setStats(map)
    } catch { /* stats jsou nepovinné */ }
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  async function toggleActive(p) {
    try {
      const { error: err } = await supabase.from('points_of_interest')
        .update({ is_active: !p.is_active, updated_at: new Date().toISOString() }).eq('id', p.id)
      if (err) throw err
      await logAudit(p.is_active ? 'catalog_poi_deactivated' : 'catalog_poi_activated', { name: p.name })
      load()
    } catch (e) { setError(`Změna stavu selhala: ${e.message}`) }
  }

  async function handleDelete(p) {
    try {
      const { error: err } = await supabase.from('points_of_interest').delete().eq('id', p.id)
      if (err) throw err
      await logAudit('catalog_poi_deleted', { name: p.name })
      setDeleteConfirm(null)
      load()
    } catch (e) { setError(`Smazání selhalo: ${e.message}`); setDeleteConfirm(null) }
  }

  async function saveEdit() {
    try {
      const { id, name, description, surroundings, category, country: ctry, image_url, is_active } = editing
      const { error: err } = await supabase.from('points_of_interest')
        .update({ name, description, surroundings: surroundings || null, category, country: ctry, image_url: image_url || null, is_active, updated_at: new Date().toISOString() })
        .eq('id', id)
      if (err) throw err
      await logAudit('catalog_poi_updated', { name })
      setEditing(null)
      load()
    } catch (e) { setError(`Uložení selhalo: ${e.message}`) }
  }

  const pages = Math.max(1, Math.ceil(total / PAGE))
  const sel = { padding: '7px 10px', borderRadius: 8, border: '1px solid #d6ddd8', fontSize: 13, background: '#fff' }

  // Řazení dle hodnocení a filtr min. hodnocení běží client-side JEN nad
  // aktuální stránkou (poi_ratings se agregují až po načtení řádků).
  let displayRows = rows
  if (minRating !== 'all') {
    displayRows = displayRows.filter(p => Number(stats[p.id]?.avg || 0) >= Number(minRating))
  }
  if (sortBy === 'rating') {
    displayRows = [...displayRows].sort((a, b) => Number(stats[b.id]?.avg || 0) - Number(stats[a.id]?.avg || 0))
  }

  return (
    <Card className="mt-6">
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <h2 className="font-bold" style={{ fontSize: 16 }}>📍 Zajímavá místa (katalog) — {total.toLocaleString('cs-CZ')}</h2>
        <div className="flex-1" />
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat místo…" />
        <select style={sel} value={cat} onChange={e => setCat(e.target.value)}>
          <option value="all">Všechny kategorie</option>
          {Object.entries(CAT).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <select style={sel} value={country} onChange={e => setCountry(e.target.value)}>
          <option value="all">Všechny země</option>
          {COUNTRIES.map(c => <option key={c} value={c}>{c}</option>)}
        </select>
        <select style={sel} value={source} onChange={e => setSource(e.target.value)}>
          {SOURCES.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <select style={sel} value={sortBy} onChange={e => setSortBy(e.target.value)} title="Řadit dle">
          <option value="default">↕ Řadit dle…</option>
          <option value="name">Název (A–Z)</option>
          <option value="rating">Hodnocení (stránka)</option>
          <option value="newest">Nejnovější</option>
        </select>
        <select style={sel} value={minRating} onChange={e => setMinRating(e.target.value)} title="Min. hodnocení (aktuální stránka)">
          <option value="all">★ min (vše)</option>
          <option value="3">★ 3+</option>
          <option value="4">★ 4+</option>
          <option value="4.5">★ 4,5+</option>
        </select>
        <label className="flex items-center gap-1 text-sm font-semibold cursor-pointer" style={{ color: '#374151' }}>
          <input type="checkbox" checked={onlyPhoto} onChange={e => setOnlyPhoto(e.target.checked)} />
          🖼 s fotkou
        </label>
        <label className="flex items-center gap-1 text-sm font-semibold cursor-pointer" style={{ color: '#374151' }}>
          <input type="checkbox" checked={onlySurroundings} onChange={e => setOnlySurroundings(e.target.checked)} />
          🧭 s popisem okolí
        </label>
      </div>

      {error && (
        <div className="p-3 mb-3 rounded-card text-sm" style={{ background: '#fee2e2', color: '#dc2626', whiteSpace: 'pre-wrap' }}>{error}</div>
      )}

      {loading ? <Spinner /> : displayRows.length === 0 ? (
        <EmptyState text="Žádná místa neodpovídají filtru." />
      ) : (
        <>
          <Table>
            <TRow header>
              <TH>Foto</TH><TH>Název</TH><TH>Kategorie</TH><TH>Země</TH><TH>GPS</TH><TH>Zdroj</TH><TH>Stav</TH><TH>Akce</TH>
            </TRow>
            {displayRows.map(p => (
              <TRow key={p.id}>
                <TD>
                  {p.image_url
                    ? <img src={p.image_url} alt="" loading="lazy" style={{ width: 46, height: 34, objectFit: 'cover', borderRadius: 6 }} />
                    : <span style={{ opacity: 0.4 }}>—</span>}
                </TD>
                <TD>
                  <div className="font-semibold">{p.name}</div>
                  {p.description && <div className="text-xs" style={{ color: '#6b7280', maxWidth: 380, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{p.description}</div>}
                </TD>
                <TD>{CAT[p.category] || p.category}</TD>
                <TD>{p.country || '—'}</TD>
                <TD className="text-xs" style={{ whiteSpace: 'nowrap' }}>{p.lat?.toFixed(4)}, {p.lng?.toFixed(4)}</TD>
                <TD className="text-xs">{p.source || '—'}</TD>
                <TD>
                  <span className="text-xs font-bold px-2 py-1 rounded-full"
                    style={p.is_active ? { background: '#dcfce7', color: '#166534' } : { background: '#f3f4f6', color: '#6b7280' }}>
                    {p.is_active ? 'Aktivní' : 'Skrytý'}
                  </span>
                </TD>
                <TD>
                  <div className="flex gap-1 flex-wrap">
                    <SmallBtn color="#2563eb" onClick={() => setEditing({ ...p })}>Upravit</SmallBtn>
                    <SmallBtn color={stats[p.id] ? '#f59e0b' : '#6b7280'} onClick={() => setReviewsFor(p)}>
                      {stats[p.id] ? `★ ${stats[p.id].avg} (${stats[p.id].count})` : '💬 Komentáře'}
                    </SmallBtn>
                    <SmallBtn color={p.is_active ? '#b45309' : '#1a8a18'} onClick={() => toggleActive(p)}>
                      {p.is_active ? 'Skrýt' : 'Aktivovat'}
                    </SmallBtn>
                    <SmallBtn color="#dc2626" onClick={() => setDeleteConfirm(p)}>Smazat</SmallBtn>
                  </div>
                </TD>
              </TRow>
            ))}
          </Table>

          <div className="flex items-center justify-between mt-3 text-sm">
            <span style={{ color: '#6b7280' }}>Stránka {page + 1} / {pages} ({total.toLocaleString('cs-CZ')} míst)</span>
            <div className="flex gap-2">
              <SmallBtn color="#374151" onClick={() => setPage(p => Math.max(0, p - 1))}>‹ Předchozí</SmallBtn>
              <SmallBtn color="#374151" onClick={() => setPage(p => Math.min(pages - 1, p + 1))}>Další ›</SmallBtn>
            </div>
          </div>
        </>
      )}

      {editing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.45)' }} onClick={() => setEditing(null)}>
          <div className="bg-white rounded-card p-5" style={{ width: 520, maxWidth: '92vw', maxHeight: '88vh', overflowY: 'auto' }} onClick={e => e.stopPropagation()}>
            <h3 className="font-bold mb-3" style={{ fontSize: 15 }}>Upravit místo</h3>
            <label className="block text-xs font-bold mb-1">Název</label>
            <input style={{ ...sel, width: '100%', marginBottom: 10 }} value={editing.name || ''}
              onChange={e => setEditing(s => ({ ...s, name: e.target.value }))} />
            <label className="block text-xs font-bold mb-1">Popis (česky)</label>
            <textarea style={{ ...sel, width: '100%', minHeight: 90, marginBottom: 10 }} value={editing.description || ''}
              onChange={e => setEditing(s => ({ ...s, description: e.target.value }))} />
            <label className="block text-xs font-bold mb-1">Popis okolí (česky)</label>
            <textarea style={{ ...sel, width: '100%', minHeight: 70, marginBottom: 10 }} value={editing.surroundings || ''}
              placeholder="Co je v okolí — tipy na zastávky, občerstvení, výhledy…"
              onChange={e => setEditing(s => ({ ...s, surroundings: e.target.value }))} />
            <div className="flex gap-3 mb-3">
              <div style={{ flex: 1 }}>
                <label className="block text-xs font-bold mb-1">Kategorie</label>
                <select style={{ ...sel, width: '100%' }} value={editing.category}
                  onChange={e => setEditing(s => ({ ...s, category: e.target.value }))}>
                  {Object.entries(CAT).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </div>
              <div style={{ width: 110 }}>
                <label className="block text-xs font-bold mb-1">Země</label>
                <select style={{ ...sel, width: '100%' }} value={editing.country || ''}
                  onChange={e => setEditing(s => ({ ...s, country: e.target.value }))}>
                  <option value="">—</option>
                  {COUNTRIES.map(c => <option key={c} value={c}>{c}</option>)}
                </select>
              </div>
            </div>
            <label className="block text-xs font-bold mb-1">URL titulní fotky</label>
            <input style={{ ...sel, width: '100%', marginBottom: 10 }} value={editing.image_url || ''}
              onChange={e => setEditing(s => ({ ...s, image_url: e.target.value }))} />
            <label className="flex items-center gap-2 text-sm mb-4">
              <input type="checkbox" checked={!!editing.is_active}
                onChange={e => setEditing(s => ({ ...s, is_active: e.target.checked }))} />
              Aktivní (zobrazuje se v appce)
            </label>
            <div className="flex justify-end gap-2">
              <SmallBtn color="#6b7280" onClick={() => setEditing(null)}>Zrušit</SmallBtn>
              <SmallBtn color="#1a8a18" onClick={saveEdit}>Uložit</SmallBtn>
            </div>
          </div>
        </div>
      )}

      {reviewsFor && (
        <PoiReviewsModal
          poi={reviewsFor}
          poiType="catalog"
          onClose={() => setReviewsFor(null)}
          onChanged={() => loadStats(rows)}
        />
      )}

      {deleteConfirm && (
        <ConfirmDialog
          open title="Smazat místo?"
          message={`Opravdu chcete smazat "${deleteConfirm.name}" z katalogu?`}
          danger onConfirm={() => handleDelete(deleteConfirm)}
          onCancel={() => setDeleteConfirm(null)}
        />
      )}
    </Card>
  )
}
