import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Card from '../components/ui/Card'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import SearchInput from '../components/ui/SearchInput'
import { SmallBtn, Spinner, EmptyState } from './BranchHelpers'
import PoiReviewsModal from './PoiReviewsModal'
import PoiEditModal from './TrasyKatalogMistModal'
import { POI_CATS, POI_SOURCES, POI_COUNTRIES, catLabel, poiPhoto } from '../lib/poiCategories'

// Sekce „Zajímavá místa (katalog)" v záložce Trasy — správa tabulky
// points_of_interest (~40 tis. samostatných bodů zájmu pro appku: přehrady,
// hrady, rozhledny, vrcholy, studánky, památky, rezervace…).
// Server-side stránkování + filtry, edit včetně GPS, zakládání nových míst
// a HROMADNÉ akce (bez nich nešlo přetřídit tisíce řádků jinak než migrací).

const PAGE = 50
const SELECT_COLS = 'id, name, description, surroundings, category, country, lat, lng, image_url, images, source, is_active, created_at'

export default function TrasyKatalogMist() {
  const [rows, setRows] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(0)
  const [search, setSearch] = useState('')
  const [cat, setCat] = useState('all')
  const [country, setCountry] = useState('all')
  const [source, setSource] = useState('all')
  const [sortBy, setSortBy] = useState('default')     // default | name | newest | rating
  const [photo, setPhoto] = useState('all')           // all | with | without
  const [active, setActive] = useState('all')         // all | yes | no
  const [onlySurroundings, setOnlySurroundings] = useState(false)
  const [minRating, setMinRating] = useState('all')   // min. hodnocení (client-side nad stránkou)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [editing, setEditing] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [reviewsFor, setReviewsFor] = useState(null)
  const [stats, setStats] = useState({})
  const [selected, setSelected] = useState(() => new Set())
  const [bulk, setBulk] = useState(null)              // { kind, value, count }
  const [busy, setBusy] = useState(false)

  // Jeden filtr = jeden dotaz; používá ho i „vybrat vše dle filtru".
  const applyFilters = useCallback((q) => {
    if (cat !== 'all') q = q.eq('category', cat)
    if (country !== 'all') q = q.eq('country', country)
    if (source !== 'all') q = q.like('source', `${source}%`)
    // Hledá se i v popisu — jinak se duplicitní bod pod jiným názvem
    // („Rozhledna Pípalka na Křemešníku" vs „Pípalka") nedá dohledat.
    if (search) q = q.or(`name.ilike.%${search}%,description.ilike.%${search}%`)
    if (photo === 'with') q = q.not('image_url', 'is', null)
    else if (photo === 'without') q = q.is('image_url', null)
    if (active === 'yes') q = q.eq('is_active', true)
    else if (active === 'no') q = q.eq('is_active', false)
    if (onlySurroundings) q = q.not('surroundings', 'is', null)
    return q
  }, [cat, country, source, search, photo, active, onlySurroundings])

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      let q = applyFilters(
        supabase.from('points_of_interest').select(SELECT_COLS, { count: 'exact' }))
      if (sortBy === 'name') q = q.order('name')
      else if (sortBy === 'newest') q = q.order('created_at', { ascending: false })
      else q = q.order('sort_order').order('name')
      const { data, count, error: err } = await q.range(page * PAGE, page * PAGE + PAGE - 1)
      if (err) throw err
      setRows(data || [])
      setTotal(count ?? 0)
      loadStats(data || [])
    } catch (e) {
      setError(`Načtení katalogu selhalo: ${e.message}`)
    } finally {
      setLoading(false)
    }
  }, [applyFilters, page, sortBy])

  useEffect(() => { load() }, [load])
  // Změna filtru → zpět na první stránku a pryč s výběrem (týkal se jiných řádků)
  useEffect(() => { setPage(0); setSelected(new Set()) },
    [search, cat, country, source, photo, active, onlySurroundings, sortBy])

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

  // ── Hromadné akce ────────────────────────────────────────────────────────
  const allOnPage = rows.length > 0 && rows.every(r => selected.has(r.id))
  function toggleRow(id) {
    setSelected(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })
  }
  function togglePage() {
    setSelected(s => {
      const n = new Set(s)
      if (allOnPage) rows.forEach(r => n.delete(r.id))
      else rows.forEach(r => n.add(r.id))
      return n
    })
  }
  // Vybrat VŠE dle filtru, ne jen viditelných 50 — přetřídění tisíců řádků
  // je přesně to, kvůli čemu hromadné akce vznikly.
  async function selectAllFiltered() {
    setBusy(true)
    try {
      const ids = []
      for (let from = 0; ; from += 1000) {
        const { data, error: err } = await applyFilters(
          supabase.from('points_of_interest').select('id')).range(from, from + 999)
        if (err) throw err
        ids.push(...(data || []).map(r => r.id))
        if (!data || data.length < 1000) break
      }
      setSelected(new Set(ids))
    } catch (e) { setError(`Výběr dle filtru selhal: ${e.message}`) } finally { setBusy(false) }
  }

  async function runBulk() {
    if (!bulk) return
    setBusy(true)
    const ids = [...selected]
    try {
      const patch = { updated_at: new Date().toISOString() }
      if (bulk.kind === 'category') patch.category = bulk.value
      else if (bulk.kind === 'country') patch.country = bulk.value || null
      else if (bulk.kind === 'active') patch.is_active = bulk.value === 'yes'
      // PostgREST má limit na délku URL → po 500 id
      for (let i = 0; i < ids.length; i += 500) {
        const chunk = ids.slice(i, i + 500)
        const { error: err } = bulk.kind === 'delete'
          ? await supabase.from('points_of_interest').delete().in('id', chunk)
          : await supabase.from('points_of_interest').update(patch).in('id', chunk)
        if (err) throw err
      }
      await logAudit(`catalog_poi_bulk_${bulk.kind}`, { count: ids.length, value: bulk.value })
      setSelected(new Set()); setBulk(null); load()
    } catch (e) { setError(`Hromadná akce selhala: ${e.message}`); setBulk(null) } finally { setBusy(false) }
  }

  const pages = Math.max(1, Math.ceil(total / PAGE))
  const sel = { padding: '7px 10px', borderRadius: 8, border: '1px solid #d6ddd8', fontSize: 13, background: '#fff' }

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
        <SmallBtn color="#1a8a18" onClick={() => setEditing({
          _new: true, name: '', description: '', surroundings: '', category: 'lookout',
          country: 'CZ', lat: '', lng: '', image_url: '', is_active: true,
        })}>+ Nové místo</SmallBtn>
        <div className="flex-1" />
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat v názvu i popisu…" />
        <select style={sel} value={cat} onChange={e => setCat(e.target.value)}>
          <option value="all">Všechny kategorie</option>
          {Object.entries(POI_CATS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <select style={sel} value={country} onChange={e => setCountry(e.target.value)}>
          <option value="all">Všechny země</option>
          {POI_COUNTRIES.map(c => <option key={c} value={c}>{c}</option>)}
        </select>
        <select style={sel} value={source} onChange={e => setSource(e.target.value)}>
          {POI_SOURCES.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
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
        <select style={sel} value={photo} onChange={e => setPhoto(e.target.value)} title="Fotka">
          <option value="all">🖼 fotka: vše</option>
          <option value="with">🖼 s fotkou</option>
          <option value="without">🚫 bez fotky</option>
        </select>
        <select style={sel} value={active} onChange={e => setActive(e.target.value)} title="Stav">
          <option value="all">stav: vše</option>
          <option value="yes">jen aktivní</option>
          <option value="no">jen skryté</option>
        </select>
        <label className="flex items-center gap-1 text-sm font-semibold cursor-pointer" style={{ color: '#374151' }}>
          <input type="checkbox" checked={onlySurroundings} onChange={e => setOnlySurroundings(e.target.checked)} />
          🧭 s popisem okolí
        </label>
      </div>

      {selected.size > 0 && (
        <div className="flex flex-wrap items-center gap-2 p-3 mb-3 rounded-card" style={{ background: '#ecfdf5', border: '1px solid #bbf7d0' }}>
          <span className="text-sm font-bold">Vybráno {selected.size.toLocaleString('cs-CZ')} míst</span>
          <select style={sel} defaultValue="" disabled={busy}
            onChange={e => { if (e.target.value) { setBulk({ kind: 'category', value: e.target.value, count: selected.size }); e.target.value = '' } }}>
            <option value="">Změnit kategorii…</option>
            {Object.entries(POI_CATS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
          <select style={sel} defaultValue="" disabled={busy}
            onChange={e => { if (e.target.value) { setBulk({ kind: 'country', value: e.target.value, count: selected.size }); e.target.value = '' } }}>
            <option value="">Změnit zemi…</option>
            {POI_COUNTRIES.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
          <SmallBtn color="#1a8a18" onClick={() => setBulk({ kind: 'active', value: 'yes', count: selected.size })}>Aktivovat</SmallBtn>
          <SmallBtn color="#b45309" onClick={() => setBulk({ kind: 'active', value: 'no', count: selected.size })}>Skrýt</SmallBtn>
          <SmallBtn color="#dc2626" onClick={() => setBulk({ kind: 'delete', value: null, count: selected.size })}>Smazat</SmallBtn>
          <div className="flex-1" />
          <SmallBtn color="#374151" onClick={selectAllFiltered}>Vybrat vše dle filtru ({total.toLocaleString('cs-CZ')})</SmallBtn>
          <SmallBtn color="#6b7280" onClick={() => setSelected(new Set())}>Zrušit výběr</SmallBtn>
        </div>
      )}

      {error && (
        <div className="p-3 mb-3 rounded-card text-sm" style={{ background: '#fee2e2', color: '#dc2626', whiteSpace: 'pre-wrap' }}>{error}</div>
      )}

      {loading ? <Spinner /> : displayRows.length === 0 ? (
        <EmptyState text="Žádná místa neodpovídají filtru." />
      ) : (
        <>
          <Table>
            <TRow header>
              <TH><input type="checkbox" checked={allOnPage} onChange={togglePage} title="Vybrat stránku" /></TH>
              <TH>Foto</TH><TH>Název</TH><TH>Kategorie</TH><TH>Země</TH><TH>GPS</TH><TH>Zdroj</TH><TH>Stav</TH><TH>Akce</TH>
            </TRow>
            {displayRows.map(p => (
              <TRow key={p.id}>
                <TD><input type="checkbox" checked={selected.has(p.id)} onChange={() => toggleRow(p.id)} /></TD>
                <TD>
                  {poiPhoto(p)
                    ? <img src={poiPhoto(p)} alt="" loading="lazy" style={{ width: 46, height: 34, objectFit: 'cover', borderRadius: 6 }} />
                    : <span style={{ opacity: 0.4 }}>—</span>}
                </TD>
                <TD>
                  <div className="font-semibold">{p.name}</div>
                  {p.description && <div className="text-xs" style={{ color: '#6b7280', maxWidth: 380, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{p.description}</div>}
                </TD>
                <TD>{catLabel(p.category)}</TD>
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
            <div className="flex gap-2 items-center">
              <SmallBtn color="#374151" onClick={() => setPage(p => Math.max(0, p - 1))}>‹ Předchozí</SmallBtn>
              <input type="number" min={1} max={pages} value={page + 1} style={{ ...sel, width: 80 }}
                onChange={e => {
                  const n = Number(e.target.value)
                  if (n >= 1 && n <= pages) setPage(n - 1)
                }} title="Skočit na stránku" />
              <SmallBtn color="#374151" onClick={() => setPage(p => Math.min(pages - 1, p + 1))}>Další ›</SmallBtn>
            </div>
          </div>
        </>
      )}

      {editing && (
        <PoiEditModal
          poi={editing}
          onClose={() => setEditing(null)}
          onSaved={(action, name) => { logAudit(action, { name }); setEditing(null); load() }}
          onError={setError}
        />
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

      {bulk && (
        <ConfirmDialog
          open
          title={bulk.kind === 'delete' ? 'Smazat vybraná místa?' : 'Hromadná změna'}
          danger={bulk.kind === 'delete'}
          message={
            bulk.kind === 'delete'
              ? `Nenávratně smazat ${bulk.count.toLocaleString('cs-CZ')} míst z katalogu? Smažou se i jejich hodnocení.`
              : bulk.kind === 'category'
                ? `Přeřadit ${bulk.count.toLocaleString('cs-CZ')} míst do kategorie ${catLabel(bulk.value)}?`
                : bulk.kind === 'country'
                  ? `Nastavit ${bulk.count.toLocaleString('cs-CZ')} místům zemi ${bulk.value}?`
                  : `${bulk.value === 'yes' ? 'Aktivovat' : 'Skrýt'} ${bulk.count.toLocaleString('cs-CZ')} míst?`
          }
          onConfirm={runBulk}
          onCancel={() => setBulk(null)}
        />
      )}
    </Card>
  )
}
