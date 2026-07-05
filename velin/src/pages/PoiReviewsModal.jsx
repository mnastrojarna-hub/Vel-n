import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Modal from '../components/ui/Modal'
import Button from '../components/ui/Button'
import { SmallBtn } from './BranchHelpers'

// Který sloupec v poi_ratings odpovídá danému typu bodu zájmu.
const COL = { route_poi: 'route_poi_id', user_poi: 'user_poi_id', catalog: 'poi_id' }

/** Moderace komentářů/recenzí jednoho bodu zájmu — admin může skrýt/zobrazit nebo smazat. */
export default function PoiReviewsModal({ poi, poiType = 'catalog', onClose, onChanged }) {
  const col = COL[poiType] || 'poi_id'
  const [ratings, setRatings] = useState([])
  const [names, setNames] = useState({})
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState(null)

  useEffect(() => { load() /* eslint-disable-next-line */ }, [])

  async function load() {
    setLoading(true); setErr(null)
    try {
      const { data, error } = await supabase.from('poi_ratings')
        .select('*').eq(col, poi.id).order('created_at', { ascending: false })
      if (error) throw error
      setRatings(data || [])
      const ids = [...new Set((data || []).map(r => r.user_id).filter(Boolean))]
      if (ids.length) {
        const { data: profs } = await supabase.from('profiles')
          .select('id, full_name, loyalty_nickname').in('id', ids)
        const map = {}
        ;(profs || []).forEach(p => { map[p.id] = p.loyalty_nickname?.trim() || p.full_name?.trim() || 'Motorkář' })
        setNames(map)
      }
    } catch (e) {
      setErr(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function toggleHidden(r) {
    const next = r.status === 'hidden' ? 'approved' : 'hidden'
    const { error } = await supabase.from('poi_ratings')
      .update({ status: next, updated_at: new Date().toISOString() }).eq('id', r.id)
    if (error) { setErr(error.message); return }
    setRatings(rs => rs.map(x => x.id === r.id ? { ...x, status: next } : x))
    onChanged?.()
  }

  async function remove(r) {
    const { error } = await supabase.from('poi_ratings').delete().eq('id', r.id)
    if (error) { setErr(error.message); return }
    setRatings(rs => rs.filter(x => x.id !== r.id))
    onChanged?.()
  }

  const stars = (n) => '★'.repeat(n) + '☆'.repeat(5 - Math.max(0, Math.min(5, n || 0)))
  // Komentáře (s textem) zvlášť od holých hodnocení (jen hvězdy) — komentáře jsou hlavní.
  const comments = ratings.filter(r => r.review_text?.trim())
  const bare = ratings.filter(r => !r.review_text?.trim())

  return (
    <Modal open title={`Komentáře: ${poi.name}`} onClose={onClose}>
      {err && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{err}</p>}
      {loading ? (
        <div className="flex justify-center py-10">
          <div className="animate-spin rounded-full h-7 w-7 border-t-2 border-brand-gd" />
        </div>
      ) : ratings.length === 0 ? (
        <p className="text-sm py-6 text-center" style={{ color: '#6b8f7b' }}>Zatím žádné komentáře ani hodnocení.</p>
      ) : (
        <div className="flex flex-col gap-3">
          {comments.map(r => (
            <div key={r.id} className="rounded-card" style={{ background: r.status === 'hidden' ? '#fef2f2' : '#f1faf7', border: '1px solid #d4e8e0', padding: 12 }}>
              <div className="flex items-center justify-between mb-1">
                <div className="flex items-center gap-2">
                  <span style={{ color: '#f59e0b', fontSize: 15, letterSpacing: 1 }}>{stars(r.rating)}</span>
                  <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{names[r.user_id] || 'Motorkář'}</span>
                  {r.status === 'hidden' && <span className="text-[9px] font-extrabold uppercase rounded-btn" style={{ padding: '2px 6px', background: '#fee2e2', color: '#dc2626' }}>Skryto</span>}
                </div>
                <span className="text-xs" style={{ color: '#6b8f7b' }}>{new Date(r.created_at).toLocaleDateString('cs-CZ')}</span>
              </div>
              <p className="text-sm mb-2" style={{ color: '#0f1a14', whiteSpace: 'pre-wrap' }}>{r.review_text}</p>
              {Array.isArray(r.photos) && r.photos.length > 0 && (
                <div className="flex gap-2 flex-wrap mb-2">
                  {r.photos.map((url, i) => (
                    <a key={i} href={url} target="_blank" rel="noreferrer">
                      <img src={url} alt="" style={{ width: 64, height: 64, objectFit: 'cover', borderRadius: 8, border: '1px solid #d4e8e0' }} onError={e => { e.target.style.opacity = 0.3 }} />
                    </a>
                  ))}
                </div>
              )}
              <div className="flex gap-2">
                <SmallBtn color={r.status === 'hidden' ? '#1a8a18' : '#b45309'} onClick={() => toggleHidden(r)}>
                  {r.status === 'hidden' ? 'Zobrazit' : 'Skrýt'}
                </SmallBtn>
                <SmallBtn color="#dc2626" onClick={() => remove(r)}>Smazat</SmallBtn>
              </div>
            </div>
          ))}

          {bare.length > 0 && (
            <div className="mt-2">
              <p className="text-xs font-bold mb-2" style={{ color: '#6b8f7b' }}>Hodnocení bez komentáře ({bare.length})</p>
              <div className="flex flex-col gap-1">
                {bare.map(r => (
                  <div key={r.id} className="flex items-center justify-between rounded-btn" style={{ background: r.status === 'hidden' ? '#fef2f2' : '#f7fbf9', border: '1px solid #e2efe8', padding: '6px 10px' }}>
                    <div className="flex items-center gap-2">
                      <span style={{ color: '#f59e0b', fontSize: 13, letterSpacing: 1 }}>{stars(r.rating)}</span>
                      <span className="text-xs" style={{ color: '#1a2e22' }}>{names[r.user_id] || 'Motorkář'}</span>
                      {r.status === 'hidden' && <span className="text-[9px] font-extrabold uppercase" style={{ color: '#dc2626' }}>Skryto</span>}
                    </div>
                    <div className="flex gap-2 items-center">
                      <span className="text-xs" style={{ color: '#6b8f7b' }}>{new Date(r.created_at).toLocaleDateString('cs-CZ')}</span>
                      <SmallBtn color={r.status === 'hidden' ? '#1a8a18' : '#b45309'} onClick={() => toggleHidden(r)}>
                        {r.status === 'hidden' ? 'Zobrazit' : 'Skrýt'}
                      </SmallBtn>
                      <SmallBtn color="#dc2626" onClick={() => remove(r)}>Smazat</SmallBtn>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
      <div className="flex justify-end mt-4">
        <Button onClick={onClose}>Zavřít</Button>
      </div>
    </Modal>
  )
}
