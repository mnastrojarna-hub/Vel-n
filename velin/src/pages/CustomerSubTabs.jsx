import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import StatusBadge, { getDisplayStatus } from '../components/ui/StatusBadge'

function LoadingSpinner() {
  return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
}

function EmptyState({ text }) {
  return <p style={{ color: '#1a2e22', fontSize: 13 }}>{text}</p>
}

export function CustomerBookings({ userId }) {
  const navigate = useNavigate()
  const [bookings, setBookings] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('bookings').select('*, motorcycles(id, model, spz)').eq('user_id', userId).order('start_date', { ascending: false })
      .then(({ data }) => { setBookings(data || []); setLoading(false) })
      .catch(() => { setBookings([]); setLoading(false) })
  }, [userId])

  if (loading) return <LoadingSpinner />

  return (
    <Card>
      {bookings.length === 0 ? <EmptyState text="Zadne rezervace" /> : (
        <div className="space-y-3">
          {bookings.map(b => (
            <div key={b.id} className="flex items-center gap-4 p-3 rounded-lg cursor-pointer hover:bg-[#e8f5e9]"
              style={{ background: '#f1faf7' }} onClick={() => navigate(`/rezervace/${b.id}`)}>
              <div className="flex-1">
                <span className="font-bold text-sm">{b.motorcycles?.model || '\u2014'}</span>
                <span className="text-sm font-mono ml-2" style={{ color: '#1a2e22' }}>{b.motorcycles?.spz}</span>
                <span className="text-sm ml-3" style={{ color: '#1a2e22' }}>{b.start_date} {'\u2192'} {b.end_date}</span>
              </div>
              <StatusBadge status={getDisplayStatus(b)} />
              <span className="text-sm font-bold">{b.total_price?.toLocaleString('cs-CZ')} Kc</span>
              {b.motorcycles?.id && (
                <button onClick={e => { e.stopPropagation(); navigate(`/flotila/${b.motorcycles.id}`) }}
                  className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>
                  {'\u2192'} Motorka
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </Card>
  )
}

export function CustomerReviews({ userId }) {
  const [reviews, setReviews] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('reviews').select('*').eq('user_id', userId).order('created_at', { ascending: false })
      .then(({ data }) => { setReviews(data || []); setLoading(false) })
      .catch(() => { setReviews([]); setLoading(false) })
  }, [userId])

  if (loading) return <LoadingSpinner />

  return (
    <Card>
      {reviews.length === 0 ? <EmptyState text="Zadna hodnoceni" /> : (
        <div className="space-y-3">
          {reviews.map(r => (
            <div key={r.id} className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
              <div className="flex items-center gap-2 mb-1">
                <span className="font-bold text-sm">{'\u2605'.repeat(r.rating || 0)}{'\u2606'.repeat(5 - (r.rating || 0))}</span>
                <span className="text-sm" style={{ color: '#1a2e22' }}>{r.created_at?.slice(0, 10)}</span>
              </div>
              <p className="text-sm" style={{ color: '#1a2e22' }}>{r.comment || '\u2014'}</p>
            </div>
          ))}
        </div>
      )}
    </Card>
  )
}
