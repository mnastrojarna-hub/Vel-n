import { useState, useEffect, useMemo, useCallback, useRef } from 'react'
import { supabase } from '../lib/supabase'
import SearchInput from '../components/ui/SearchInput'
import Button from '../components/ui/Button'
import { SmallBtn } from './BranchHelpers'

const FILTERS = [
  { id: 'all', label: 'Vše' },
  { id: 'text', label: '💬 S komentářem' },
  { id: 'photos', label: '📷 S fotkami' },
  { id: 'hidden', label: '🙈 Skryté' },
  { id: 'low', label: '★ ≤ 2' },
]

const PAGE = 50          // recenzí na jedno načtení
const MAX_ROUTE_IDS = 80 // strop id tras v hledání (delší URL PostgREST neunese)

/** Přehled VŠECH recenzí/komentářů tras napříč trasami — čtení + moderace
 *  (skrýt / zobrazit / smazat).
 *
 *  Načítá se PO STRÁNKÁCH ze serveru (filtry, hledání i řazení dělá databáze),
 *  nikdy celá tabulka najednou; jména autorů se dotahují jen pro právě
 *  zobrazené řádky. Souhrnná čísla jdou přes `head` počty (bez přenosu dat). */
export default function TrasyRecenze({ routes, onOpenRoute, onChanged }) {
  const [reviews, setReviews] = useState([])
  const [names, setNames] = useState({})
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [hasMore, setHasMore] = useState(false)
  const [err, setErr] = useState(null)
  const [filter, setFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [dSearch, setDSearch] = useState('')            // odloženo (debounce)
  const [totals, setTotals] = useState(null)            // {count, comments, hidden, avg}
  const [confirm, setConfirm] = useState(null)          // recenze čekající na potvrzení smazání
  const reqId = useRef(0)                               // zahození odpovědí staršího dotazu

  const routeById = useMemo(() => {
    const m = {}
    ;(routes || []).forEach(r => { m[r.id] = r })
    return m
  }, [routes])

  // Hledání se na server posílá až po dopsání (šetří dotazy i čekání).
  useEffect(() => {
    const id = setTimeout(() => setDSearch(search.trim()), 350)
    return () => clearTimeout(id)
  }, [search])

  /** Hledání (text recenze + názvy tras) — společné pro obě varianty dotazu. */
  const applySearch = useCallback((q) => {
    if (!dSearch) return q
    const esc = dSearch.replace(/[,()*]/g, ' ')
    const ids = (routes || [])
      .filter(r => (r.name || '').toLowerCase().includes(dSearch.toLowerCase()))
      .slice(0, MAX_ROUTE_IDS).map(r => r.id)
    return ids.length
      ? q.or(`review_text.ilike.*${esc}*,route_id.in.(${ids.join(',')})`)
      : q.ilike('review_text', `%${esc}%`)
  }, [dSearch, routes])

  /** Fallback pro filtr „s fotkami" — bez serverové podmínky na pole. */
  const buildQueryWithoutPhotos = useCallback((q) => applySearch(q), [applySearch])

  /** Dotaz na recenze s filtry aplikovanými SERVEREM. */
  const buildQuery = useCallback((q) => {
    if (filter === 'text') q = q.not('review_text', 'is', null).neq('review_text', '')
    else if (filter === 'photos') q = q.neq('photos', '{}')
    else if (filter === 'hidden') q = q.eq('status', 'hidden')
    else if (filter === 'low') q = q.lte('rating', 2)
    return applySearch(q)
  }, [filter, applySearch])

  /** Jména autorů pro právě načtené řádky (už známá se znovu netahají). */
  const knownUsers = useRef(new Set())
  const loadNames = useCallback(async (rows) => {
    const need = [...new Set(rows.map(r => r.user_id).filter(Boolean))]
      .filter(id => !knownUsers.current.has(id))
      .slice(0, 200)
    if (need.length === 0) return
    need.forEach(id => knownUsers.current.add(id))
    const { data } = await supabase.from('profiles')
      .select('id, full_name, loyalty_nickname').in('id', need)
    const add = {}
    ;(data || []).forEach(p => { add[p.id] = p.loyalty_nickname?.trim() || p.full_name?.trim() || 'Motorkář' })
    need.forEach(id => { if (!(id in add)) add[id] = 'Motorkář' })
    setNames(cur => ({ ...cur, ...add }))
  }, [])

  /** Načte stránku recenzí. `append` = tlačítko „Načíst další". */
  const load = useCallback(async (append = false) => {
    const my = ++reqId.current
    append ? setLoadingMore(true) : setLoading(true)
    setErr(null)
    const offset = append ? reviews.length : 0
    try {
      let { data, error } = await buildQuery(supabase.from('route_reviews').select('*'))
        .order('created_at', { ascending: false })
        .range(offset, offset + PAGE - 1)
      let clientPhotoFilter = false
      if (error && filter === 'photos') {
        // Porovnání text[] s '{}' server nevzal — stáhni stránku bez něj a
        // profiltruj ji klientsky (raději o pár řádků méně než chyba).
        clientPhotoFilter = true
        ;({ data, error } = await buildQueryWithoutPhotos(supabase.from('route_reviews').select('*'))
          .order('created_at', { ascending: false })
          .range(offset, offset + PAGE - 1))
      }
      if (error) throw error
      if (my !== reqId.current) return // mezitím přišel novější dotaz
      let rows = data || []
      if (clientPhotoFilter) rows = rows.filter(r => Array.isArray(r.photos) && r.photos.length > 0)
      setReviews(prev => append ? [...prev, ...rows] : rows)
      setHasMore(rows.length === PAGE)
      loadNames(rows)
    } catch (e) {
      if (my === reqId.current) setErr(e.message)
    } finally {
      if (my === reqId.current) { setLoading(false); setLoadingMore(false) }
    }
  }, [buildQuery, buildQueryWithoutPhotos, filter, loadNames, reviews.length])

  // Změna filtru / hledání → nová první stránka.
  useEffect(() => { load(false) /* eslint-disable-next-line */ }, [filter, dSearch])

  // Souhrnná čísla — jen počty, bez stahování řádků.
  const loadTotals = useCallback(async () => {
    try {
      const head = (tweak = q => q) =>
        tweak(supabase.from('route_reviews').select('id', { count: 'exact', head: true }))
      const [all, comments, hidden, approved] = await Promise.all([
        head(),
        head(q => q.not('review_text', 'is', null).neq('review_text', '')),
        head(q => q.eq('status', 'hidden')),
        supabase.from('route_reviews').select('rating').eq('status', 'approved').limit(1001),
      ])
      const rs = approved.data || []
      setTotals({
        count: all.count ?? 0,
        comments: comments.count ?? 0,
        hidden: hidden.count ?? 0,
        avg: rs.length ? Math.round(rs.reduce((s, r) => s + r.rating, 0) / rs.length * 10) / 10 : null,
        avgPartial: rs.length > 1000, // nad 1000 recenzí je průměr ze vzorku
      })
    } catch { /* souhrn je jen doplněk, chyba nesmí zabít seznam */ }
  }, [])

  useEffect(() => { loadTotals() }, [loadTotals])

  async function toggleHidden(rev) {
    const next = rev.status === 'hidden' ? 'approved' : 'hidden'
    const { error } = await supabase.from('route_reviews')
      .update({ status: next, updated_at: new Date().toISOString() }).eq('id', rev.id)
    if (error) { setErr(error.message); return }
    setReviews(rs => rs.map(r => r.id === rev.id ? { ...r, status: next } : r))
    loadTotals()
    onChanged?.()
  }

  async function remove(rev) {
    const { error } = await supabase.from('route_reviews').delete().eq('id', rev.id)
    setConfirm(null)
    if (error) { setErr(error.message); return }
    setReviews(rs => rs.filter(r => r.id !== rev.id))
    loadTotals()
    onChanged?.()
  }

  const stars = (n) => '★'.repeat(n) + '☆'.repeat(5 - Math.max(0, Math.min(5, n || 0)))
  const routesReady = (routes || []).length > 0

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat trasu nebo text recenze…" />
        <div className="flex gap-1 flex-wrap">
          {FILTERS.map(f => (
            <button key={f.id} onClick={() => setFilter(f.id)}
              className="rounded-btn text-xs font-extrabold cursor-pointer"
              style={{
                padding: '6px 12px', border: 'none',
                background: filter === f.id ? '#74FB71' : '#f1faf7', color: '#1a2e22',
              }}>
              {f.label}
            </button>
          ))}
        </div>
        <span className="ml-auto text-xs font-bold" style={{ color: '#6b8f7b' }}>
          {totals
            ? `${totals.count} recenzí · ${totals.comments} s komentářem · ${totals.hidden} skrytých${totals.avg != null ? ` · průměr ★ ${totals.avgPartial ? '~' : ''}${totals.avg}` : ''}`
            : 'počítám souhrn…'}
        </span>
      </div>

      {err && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{err}</p>}

      {loading ? (
        <div className="flex justify-center py-12">
          <div className="animate-spin rounded-full h-7 w-7 border-t-2 border-brand-gd" />
        </div>
      ) : reviews.length === 0 ? (
        <p className="text-sm py-8 text-center" style={{ color: '#6b8f7b' }}>
          {filter === 'all' && !dSearch ? 'Zatím žádné recenze tras.' : 'Žádná recenze neodpovídá filtru.'}
        </p>
      ) : (
        <>
          <div className="flex flex-col gap-3">
            {reviews.map(rev => {
              const route = routeById[rev.route_id]
              const isHidden = rev.status === 'hidden'
              return (
                <div key={rev.id} className="rounded-card"
                  style={{ background: isHidden ? '#fef2f2' : '#fff', border: `1px solid ${isHidden ? '#fecaca' : '#d4e8e0'}`, padding: '12px 14px' }}>
                  <div className="flex items-center justify-between gap-3 mb-1 flex-wrap">
                    <div className="flex items-center gap-2 min-w-0 flex-wrap">
                      <button onClick={() => route && onOpenRoute?.(route)}
                        disabled={!route}
                        className="text-sm font-extrabold truncate"
                        title={route ? 'Otevřít trasu' : undefined}
                        style={{
                          background: 'none', border: 'none', padding: 0, maxWidth: 360,
                          color: route ? '#1a8a18' : '#8aab99',
                          cursor: route ? 'pointer' : 'default',
                        }}>
                        🛣️ {route?.name || (routesReady ? 'Smazaná trasa' : '…')}
                      </button>
                      <span style={{ color: '#f59e0b', fontSize: 15, letterSpacing: 1 }}>{stars(rev.rating)}</span>
                      <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{names[rev.user_id] || 'Motorkář'}</span>
                      {isHidden && (
                        <span className="text-[9px] font-extrabold uppercase rounded-btn"
                          style={{ padding: '2px 6px', background: '#fee2e2', color: '#dc2626' }}>Skryto</span>
                      )}
                    </div>
                    <span className="text-xs" style={{ color: '#6b8f7b' }}>
                      {new Date(rev.created_at).toLocaleString('cs-CZ', { dateStyle: 'medium', timeStyle: 'short' })}
                    </span>
                  </div>
                  {rev.review_text?.trim()
                    ? <p className="text-sm mb-2" style={{ color: '#0f1a14', whiteSpace: 'pre-wrap' }}>{rev.review_text}</p>
                    : <p className="text-xs italic mb-2" style={{ color: '#8aab99' }}>Bez komentáře (jen hvězdičky)</p>}
                  {Array.isArray(rev.photos) && rev.photos.length > 0 && (
                    <div className="flex gap-2 flex-wrap mb-2">
                      {rev.photos.map((url, i) => (
                        <a key={i} href={url} target="_blank" rel="noreferrer">
                          <img src={url} alt="" loading="lazy"
                            style={{ width: 64, height: 64, objectFit: 'cover', borderRadius: 8, border: '1px solid #d4e8e0' }}
                            onError={e => { e.target.style.opacity = 0.3 }} />
                        </a>
                      ))}
                    </div>
                  )}
                  <div className="flex gap-2 items-center">
                    <SmallBtn color={isHidden ? '#1a8a18' : '#b45309'} onClick={() => toggleHidden(rev)}>
                      {isHidden ? 'Zobrazit' : 'Skrýt'}
                    </SmallBtn>
                    {confirm === rev.id ? (
                      <>
                        <span className="text-xs font-bold" style={{ color: '#dc2626' }}>Opravdu smazat?</span>
                        <SmallBtn color="#dc2626" onClick={() => remove(rev)}>Ano, smazat</SmallBtn>
                        <SmallBtn color="#6b7280" onClick={() => setConfirm(null)}>Zrušit</SmallBtn>
                      </>
                    ) : (
                      <SmallBtn color="#dc2626" onClick={() => setConfirm(rev.id)}>Smazat</SmallBtn>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
          {hasMore && (
            <div className="flex justify-center mt-4">
              <Button onClick={() => load(true)} disabled={loadingMore}>
                {loadingMore ? 'Načítám…' : 'Načíst další'}
              </Button>
            </div>
          )}
        </>
      )}
    </div>
  )
}
