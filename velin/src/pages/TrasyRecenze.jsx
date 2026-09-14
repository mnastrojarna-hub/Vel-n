import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../lib/supabase'
import SearchInput from '../components/ui/SearchInput'
import { SmallBtn } from './BranchHelpers'

const FILTERS = [
  { id: 'all', label: 'Vše' },
  { id: 'text', label: '💬 S komentářem' },
  { id: 'photos', label: '📷 S fotkami' },
  { id: 'hidden', label: '🙈 Skryté' },
  { id: 'low', label: '★ ≤ 2' },
]

/** Přehled VŠECH recenzí/komentářů tras napříč trasami — čtení + moderace
 *  (skrýt / zobrazit / smazat). Doplňuje modal recenzí jedné trasy. */
export default function TrasyRecenze({ routes, onOpenRoute, onChanged }) {
  const [reviews, setReviews] = useState([])
  const [names, setNames] = useState({})
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState(null)
  const [filter, setFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [confirm, setConfirm] = useState(null) // recenze čekající na potvrzení smazání

  const routeById = useMemo(() => {
    const m = {}
    ;(routes || []).forEach(r => { m[r.id] = r })
    return m
  }, [routes])

  useEffect(() => { load() /* eslint-disable-next-line */ }, [])

  async function load() {
    setLoading(true); setErr(null)
    try {
      const all = []
      for (let from = 0; ; from += 1000) {
        const { data, error } = await supabase.from('route_reviews')
          .select('*').order('created_at', { ascending: false }).range(from, from + 999)
        if (error) throw error
        all.push(...(data || []))
        if (!data || data.length < 1000) break
      }
      setReviews(all)
      const ids = [...new Set(all.map(r => r.user_id).filter(Boolean))]
      const map = {}
      for (let i = 0; i < ids.length; i += 200) {
        const { data: profs } = await supabase.from('profiles')
          .select('id, full_name, loyalty_nickname').in('id', ids.slice(i, i + 200))
        ;(profs || []).forEach(p => { map[p.id] = p.loyalty_nickname?.trim() || p.full_name?.trim() || 'Motorkář' })
      }
      setNames(map)
    } catch (e) {
      setErr(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function toggleHidden(rev) {
    const next = rev.status === 'hidden' ? 'approved' : 'hidden'
    const { error } = await supabase.from('route_reviews')
      .update({ status: next, updated_at: new Date().toISOString() }).eq('id', rev.id)
    if (error) { setErr(error.message); return }
    setReviews(rs => rs.map(r => r.id === rev.id ? { ...r, status: next } : r))
    onChanged?.()
  }

  async function remove(rev) {
    const { error } = await supabase.from('route_reviews').delete().eq('id', rev.id)
    setConfirm(null)
    if (error) { setErr(error.message); return }
    setReviews(rs => rs.filter(r => r.id !== rev.id))
    onChanged?.()
  }

  const stars = (n) => '★'.repeat(n) + '☆'.repeat(5 - Math.max(0, Math.min(5, n || 0)))

  const filtered = reviews.filter(r => {
    if (filter === 'text' && !r.review_text?.trim()) return false
    if (filter === 'photos' && !(Array.isArray(r.photos) && r.photos.length)) return false
    if (filter === 'hidden' && r.status !== 'hidden') return false
    if (filter === 'low' && r.rating > 2) return false
    if (!search) return true
    const s = search.toLowerCase()
    return (routeById[r.route_id]?.name || '').toLowerCase().includes(s) ||
      (r.review_text || '').toLowerCase().includes(s) ||
      (names[r.user_id] || '').toLowerCase().includes(s)
  })

  const withText = reviews.filter(r => r.review_text?.trim()).length
  const hidden = reviews.filter(r => r.status === 'hidden').length
  const avg = reviews.length
    ? Math.round(reviews.filter(r => r.status === 'approved').reduce((s, r) => s + r.rating, 0) /
        Math.max(1, reviews.filter(r => r.status === 'approved').length) * 10) / 10
    : null

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat trasu, autora, text…" />
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
          {reviews.length} recenzí · {withText} s komentářem · {hidden} skrytých{avg != null ? ` · průměr ★ ${avg}` : ''}
        </span>
      </div>

      {err && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{err}</p>}

      {loading ? (
        <div className="flex justify-center py-12">
          <div className="animate-spin rounded-full h-7 w-7 border-t-2 border-brand-gd" />
        </div>
      ) : filtered.length === 0 ? (
        <p className="text-sm py-8 text-center" style={{ color: '#6b8f7b' }}>
          {reviews.length === 0 ? 'Zatím žádné recenze tras.' : 'Žádná recenze neodpovídá filtru.'}
        </p>
      ) : (
        <div className="flex flex-col gap-3">
          {filtered.map(rev => {
            const route = routeById[rev.route_id]
            const isHidden = rev.status === 'hidden'
            return (
              <div key={rev.id} className="rounded-card"
                style={{ background: isHidden ? '#fef2f2' : '#fff', border: `1px solid ${isHidden ? '#fecaca' : '#d4e8e0'}`, padding: '12px 14px' }}>
                <div className="flex items-center justify-between gap-3 mb-1 flex-wrap">
                  <div className="flex items-center gap-2 min-w-0 flex-wrap">
                    <button onClick={() => route && onOpenRoute?.(route)}
                      className="text-sm font-extrabold cursor-pointer truncate"
                      title="Otevřít trasu"
                      style={{ background: 'none', border: 'none', color: '#1a8a18', padding: 0, maxWidth: 360 }}>
                      🛣️ {route?.name || 'Smazaná trasa'}
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
                        <img src={url} alt="" style={{ width: 64, height: 64, objectFit: 'cover', borderRadius: 8, border: '1px solid #d4e8e0' }}
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
      )}
    </div>
  )
}
