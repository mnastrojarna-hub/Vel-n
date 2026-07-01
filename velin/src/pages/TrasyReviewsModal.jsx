import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Modal from '../components/ui/Modal'
import Button from '../components/ui/Button'
import { SmallBtn } from './BranchHelpers'

/** Moderace recenzí jedné trasy — admin může recenzi skrýt/zobrazit nebo smazat. */
export default function TrasyReviewsModal({ route, onClose, onChanged }) {
  const [reviews, setReviews] = useState([])
  const [names, setNames] = useState({})
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState(null)

  useEffect(() => { load() /* eslint-disable-next-line */ }, [])

  async function load() {
    setLoading(true); setErr(null)
    try {
      const { data, error } = await supabase.from('route_reviews')
        .select('*').eq('route_id', route.id).order('created_at', { ascending: false })
      if (error) throw error
      setReviews(data || [])
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
    if (error) { setErr(error.message); return }
    setReviews(rs => rs.filter(r => r.id !== rev.id))
    onChanged?.()
  }

  const stars = (n) => '★'.repeat(n) + '☆'.repeat(5 - n)

  return (
    <Modal open title={`Recenze trasy: ${route.name}`} onClose={onClose}>
      {err && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{err}</p>}
      {loading ? (
        <div className="flex justify-center py-10">
          <div className="animate-spin rounded-full h-7 w-7 border-t-2 border-brand-gd" />
        </div>
      ) : reviews.length === 0 ? (
        <p className="text-sm py-6 text-center" style={{ color: '#6b8f7b' }}>Zatím žádné recenze.</p>
      ) : (
        <div className="flex flex-col gap-3">
          {reviews.map(rev => (
            <div key={rev.id} className="rounded-card" style={{ background: rev.status === 'hidden' ? '#fef2f2' : '#f1faf7', border: '1px solid #d4e8e0', padding: 12 }}>
              <div className="flex items-center justify-between mb-1">
                <div className="flex items-center gap-2">
                  <span style={{ color: '#f59e0b', fontSize: 15, letterSpacing: 1 }}>{stars(rev.rating)}</span>
                  <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{names[rev.user_id] || 'Motorkář'}</span>
                  {rev.status === 'hidden' && <span className="text-[9px] font-extrabold uppercase rounded-btn" style={{ padding: '2px 6px', background: '#fee2e2', color: '#dc2626' }}>Skryto</span>}
                </div>
                <span className="text-xs" style={{ color: '#6b8f7b' }}>{new Date(rev.created_at).toLocaleDateString('cs-CZ')}</span>
              </div>
              {rev.review_text && <p className="text-sm mb-2" style={{ color: '#0f1a14', whiteSpace: 'pre-wrap' }}>{rev.review_text}</p>}
              {Array.isArray(rev.photos) && rev.photos.length > 0 && (
                <div className="flex gap-2 flex-wrap mb-2">
                  {rev.photos.map((url, i) => (
                    <a key={i} href={url} target="_blank" rel="noreferrer">
                      <img src={url} alt="" style={{ width: 64, height: 64, objectFit: 'cover', borderRadius: 8, border: '1px solid #d4e8e0' }} onError={e => { e.target.style.opacity = 0.3 }} />
                    </a>
                  ))}
                </div>
              )}
              <div className="flex gap-2">
                <SmallBtn color={rev.status === 'hidden' ? '#1a8a18' : '#b45309'} onClick={() => toggleHidden(rev)}>
                  {rev.status === 'hidden' ? 'Zobrazit' : 'Skrýt'}
                </SmallBtn>
                <SmallBtn color="#dc2626" onClick={() => remove(rev)}>Smazat</SmallBtn>
              </div>
            </div>
          ))}
        </div>
      )}
      <div className="flex justify-end mt-4">
        <Button onClick={onClose}>Zavřít</Button>
      </div>
    </Modal>
  )
}
