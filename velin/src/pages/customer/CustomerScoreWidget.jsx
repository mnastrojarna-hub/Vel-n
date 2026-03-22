import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'

/**
 * MotoGo24 Customer Score — komplexní scoring zákazníka
 *
 * POZITIVNÍ faktory (max ~100 bodů):
 *   1. Celkový obrat (total_price součet) — max 40 bodů
 *   2. Počet dokončených rezervací — max 20 bodů
 *   3. Průměrná délka půjčení (dny) — max 10 bodů
 *   4. Průměrná cena motorky za den — max 10 bodů
 *   5. Stálost (měsíce od první rezervace × frekvence) — max 10 bodů
 *   6. Hodnocení (průměr review rating) — max 10 bodů
 *
 * NEGATIVNÍ faktory (tvrdé srážky):
 *   7. SOS incidenty — -15 low, -30 medium, -50 high, -80 critical
 *   8. SOS s vinou zákazníka — TROJNÁSOBNÁ srážka (1 critical s vinou = -240!)
 *   9. Pozdní vrácení — progresivní: 1 den=-8, 2 dny=-18, 3 dny=-30 (strmě roste)
 *  10. Storna zákazníkem — eskalující: 1.=-5, 2.=-8, 3.=-11 (každé další horší)
 *  11. Reklamace — rejected -15, open -10, resolved -3
 *
 * NEGATIVNÍ faktory MAJÍ max limity (jako pozitivní):
 *   SOS incidenty — max 40 bodů srážky
 *   Pozdní vrácení — max 20 bodů
 *   Storna — max 15 bodů
 *   Reklamace — max 25 bodů
 *
 * Výsledné skóre: clamp(-100, 100)
 * Rank: S (90+), A (75+), B (55+), C (35+), D (20+), F (<20)
 */

const RANK_MAP = [
  { min: 90, rank: 'S', label: 'VIP', color: '#7c3aed', bg: '#ede9fe' },
  { min: 75, rank: 'A', label: 'Výborný', color: '#1a8a18', bg: '#dcfce7' },
  { min: 55, rank: 'B', label: 'Dobrý', color: '#2563eb', bg: '#dbeafe' },
  { min: 35, rank: 'C', label: 'Průměrný', color: '#b45309', bg: '#fef3c7' },
  { min: 20, rank: 'D', label: 'Problémový', color: '#dc2626', bg: '#fee2e2' },
  { min: 0, rank: 'F', label: 'Rizikový', color: '#fff', bg: '#7f1d1d' },
  { min: -100, rank: 'F', label: 'Rizikový', color: '#fff', bg: '#7f1d1d' },
]

export function getRank(total) {
  return RANK_MAP.find(r => total >= r.min) || RANK_MAP[RANK_MAP.length - 1]
}

export function getScoreColor(total) {
  const r = getRank(total)
  return { color: r.color, bg: r.bg }
}

function computeScore(bookings, sosIncidents, reviews, complaints) {
  const completed = bookings.filter(b => ['completed', 'returned'].includes(b.status) || b.returned_at)
  const cancelled = bookings.filter(b => b.status === 'cancelled' && b.cancelled_by_source === 'customer')

  // 1. Celkový obrat — max 40 bodů (logaritmická škála, 50k = max)
  const totalRevenue = completed.reduce((s, b) => s + (b.total_price || 0), 0)
  const revenueScore = Math.min(40, (Math.log10(Math.max(1, totalRevenue)) / Math.log10(50000)) * 40)

  // 2. Počet dokončených rezervací — max 20 bodů (10+ = max)
  const countScore = Math.min(20, (completed.length / 10) * 20)

  // 3. Průměrná délka půjčení — max 10 bodů (7+ dní = max)
  const avgDays = completed.length > 0
    ? completed.reduce((s, b) => {
        const start = new Date(b.start_date)
        const end = new Date(b.actual_return_date || b.end_date)
        return s + Math.max(1, (end - start) / 86400000)
      }, 0) / completed.length
    : 0
  const durationScore = Math.min(10, (avgDays / 7) * 10)

  // 4. Průměrná denní cena — max 10 bodů (2000 Kč/den = max)
  const totalDays = completed.reduce((s, b) => {
    const start = new Date(b.start_date)
    const end = new Date(b.actual_return_date || b.end_date)
    return s + Math.max(1, (end - start) / 86400000)
  }, 0)
  const avgDailyPrice = totalDays > 0 ? totalRevenue / totalDays : 0
  const priceScore = Math.min(10, (avgDailyPrice / 2000) * 10)

  // 5. Stálost — max 10 bodů
  let loyaltyScore = 0
  if (completed.length > 0) {
    const dates = completed.map(b => new Date(b.start_date)).sort((a, b) => a - b)
    const firstBooking = dates[0]
    const monthsSinceFirst = (Date.now() - firstBooking) / (30 * 86400000)
    const frequency = monthsSinceFirst > 0 ? completed.length / monthsSinceFirst : 0
    // Freq 0.5+/měsíc + 12+ měsíců = max
    const freqPart = Math.min(5, (frequency / 0.5) * 5)
    const tenurePart = Math.min(5, (monthsSinceFirst / 12) * 5)
    loyaltyScore = freqPart + tenurePart
  }

  // 6. Hodnocení — max 10 bodů
  const avgRating = reviews.length > 0 ? reviews.reduce((s, r) => s + (r.rating || 0), 0) / reviews.length : 0
  const ratingScore = reviews.length > 0 ? (avgRating / 5) * 10 : 5 // Neutrální pokud bez recenzí

  // === SRÁŽKY (každá s max limitem) ===

  // 7+8. SOS incidenty — max 40 bodů srážky
  const sevPenalty = { low: 15, medium: 30, high: 50, critical: 80 }
  let sosPenaltyRaw = 0
  sosIncidents.forEach(inc => {
    const base = sevPenalty[inc.severity] || 30
    sosPenaltyRaw += inc.is_customer_fault ? base * 3 : base
  })
  const sosPenalty = Math.min(40, sosPenaltyRaw)

  // 9. Pozdní vrácení — max 20 bodů
  let latePenaltyRaw = 0
  completed.forEach(b => {
    if (b.actual_return_date && b.end_date) {
      const lateDays = Math.ceil((new Date(b.actual_return_date) - new Date(b.end_date)) / 86400000)
      if (lateDays > 0) {
        for (let d = 1; d <= lateDays; d++) latePenaltyRaw += 5 + d * 3
      }
    }
  })
  const latePenalty = Math.min(20, latePenaltyRaw)

  // 10. Storna — max 15 bodů
  let cancelPenaltyRaw = 0
  for (let i = 0; i < cancelled.length; i++) cancelPenaltyRaw += 5 + i * 3
  const cancelPenalty = Math.min(15, cancelPenaltyRaw)

  // 11. Reklamace — max 25 bodů
  let complaintPenaltyRaw = 0
  complaints.forEach(c => {
    if (c.status === 'rejected') complaintPenaltyRaw += 15
    else if (c.status === 'open' || c.status === 'in_progress') complaintPenaltyRaw += 10
    else if (c.status === 'resolved') complaintPenaltyRaw += 3
  })
  const complaintPenalty = Math.min(25, complaintPenaltyRaw)

  const totalPositive = revenueScore + countScore + durationScore + priceScore + loyaltyScore + ratingScore
  const totalNegative = sosPenalty + latePenalty + cancelPenalty + complaintPenalty
  const total = Math.max(-100, Math.min(100, Math.round(totalPositive - totalNegative)))

  return {
    total,
    rank: getRank(total),
    breakdown: {
      revenue: { score: Math.round(revenueScore * 10) / 10, max: 40, value: totalRevenue },
      bookings: { score: Math.round(countScore * 10) / 10, max: 20, value: completed.length },
      duration: { score: Math.round(durationScore * 10) / 10, max: 10, value: Math.round(avgDays * 10) / 10 },
      dailyPrice: { score: Math.round(priceScore * 10) / 10, max: 10, value: Math.round(avgDailyPrice) },
      loyalty: { score: Math.round(loyaltyScore * 10) / 10, max: 10 },
      rating: { score: Math.round(ratingScore * 10) / 10, max: 10, value: Math.round(avgRating * 10) / 10 },
    },
    penalties: {
      sos: { count: sosIncidents.length, penalty: Math.round(sosPenalty), max: 40 },
      late: { penalty: Math.round(latePenalty), max: 20 },
      cancellations: { count: cancelled.length, penalty: cancelPenalty, max: 15 },
      complaints: { count: complaints.length, penalty: complaintPenalty, max: 25 },
    },
    totalPositive: Math.round(totalPositive * 10) / 10,
    totalNegative: Math.round(totalNegative),
  }
}

export default function CustomerScoreWidget({ userId }) {
  const [score, setScore] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => { if (userId) load() }, [userId])

  async function load() {
    setLoading(true)
    try {
      const [bRes, sRes, rRes, cRes] = await Promise.all([
        supabase.from('bookings').select('id, status, total_price, start_date, end_date, actual_return_date, returned_at, cancelled_by_source').eq('user_id', userId),
        supabase.from('sos_incidents').select('id, severity, is_customer_fault, user_id').eq('user_id', userId),
        supabase.from('reviews').select('id, rating').eq('user_id', userId),
        supabase.from('booking_complaints').select('id, status').eq('customer_id', userId),
      ])
      const result = computeScore(bRes.data || [], sRes.data || [], rRes.data || [], cRes.data || [])
      setScore(result)

      // Persist score to profile for list views
      await supabase.from('profiles').update({
        reliability_score: { total: result.total, rank: result.rank.rank, computed_at: new Date().toISOString() }
      }).eq('id', userId)
    } catch { /* silent */ }
    setLoading(false)
  }

  if (loading) return <ScorePlaceholder />
  if (!score) return null

  const { total, rank, breakdown, penalties, totalPositive, totalNegative } = score

  return (
    <div className="space-y-3">
      {/* Hlavní score */}
      <Card>
        <div className="flex items-center gap-4">
          <div className="flex items-center justify-center rounded-full font-extrabold text-2xl" style={{ width: 64, height: 64, background: rank.bg, color: rank.color, border: `3px solid ${rank.color}` }}>
            {rank.rank}
          </div>
          <div>
            <div className="text-2xl font-extrabold" style={{ color: '#0f1a14' }}>{total} <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>(-100 az 100)</span></div>
            <div className="text-sm font-bold" style={{ color: rank.color }}>{rank.label} zakaznik</div>
          </div>
          <div className="flex-1" />
          <div className="text-right">
            <div className="text-sm" style={{ color: '#1a8a18' }}>+{totalPositive}</div>
            <div className="text-sm" style={{ color: '#dc2626' }}>-{totalNegative}</div>
          </div>
        </div>
        {/* Progress bar — centered at 0, range -100 to 100 */}
        <div className="mt-3 rounded-full overflow-hidden relative" style={{ height: 8, background: '#e5e7eb' }}>
          {total >= 0 ? (
            <div className="absolute rounded-r-full h-full transition-all" style={{ left: '50%', width: `${(total / 100) * 50}%`, background: rank.color }} />
          ) : (
            <div className="absolute rounded-l-full h-full transition-all" style={{ right: '50%', width: `${(Math.abs(total) / 100) * 50}%`, background: '#dc2626' }} />
          )}
          <div className="absolute h-full" style={{ left: '50%', width: 2, background: '#9ca3af' }} />
        </div>
      </Card>

      {/* Pozitivní faktory */}
      <Card>
        <div className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a8a18' }}>Pozitivni faktory</div>
        <div className="space-y-2">
          <ScoreRow label="Celkovy obrat" detail={`${Math.round(breakdown.revenue.value).toLocaleString('cs-CZ')} Kc`} score={breakdown.revenue.score} max={breakdown.revenue.max} color="#1a8a18" />
          <ScoreRow label="Dokoncene rezervace" detail={`${breakdown.bookings.value}x`} score={breakdown.bookings.score} max={breakdown.bookings.max} color="#1a8a18" />
          <ScoreRow label="Prumerna delka pujceni" detail={`${breakdown.duration.value} dni`} score={breakdown.duration.score} max={breakdown.duration.max} color="#1a8a18" />
          <ScoreRow label="Prumerna cena/den" detail={`${breakdown.dailyPrice.value} Kc`} score={breakdown.dailyPrice.score} max={breakdown.dailyPrice.max} color="#1a8a18" />
          <ScoreRow label="Vernost" detail="" score={breakdown.loyalty.score} max={breakdown.loyalty.max} color="#1a8a18" />
          <ScoreRow label="Hodnoceni" detail={breakdown.rating.value > 0 ? `${breakdown.rating.value}/5` : 'Zatim bez hodnoceni'} score={breakdown.rating.score} max={breakdown.rating.max} color="#1a8a18" />
        </div>
      </Card>

      {/* Negativní faktory */}
      <Card>
        <div className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#dc2626' }}>Srazky</div>
        <div className="space-y-2">
          <PenaltyRow label="SOS incidenty" count={penalties.sos.count} penalty={penalties.sos.penalty} max={penalties.sos.max} />
          <PenaltyRow label="Pozdni vraceni" penalty={penalties.late.penalty} max={penalties.late.max} />
          <PenaltyRow label="Storna zakaznikem" count={penalties.cancellations.count} penalty={penalties.cancellations.penalty} max={penalties.cancellations.max} />
          <PenaltyRow label="Reklamace" count={penalties.complaints.count} penalty={penalties.complaints.penalty} max={penalties.complaints.max} />
        </div>
        {totalNegative === 0 && <p className="text-sm mt-2" style={{ color: '#1a8a18' }}>Zadne srazky — cisty zaznam</p>}
      </Card>
    </div>
  )
}

/** Kompaktní badge pro hlavičku */
export function ScoreBadge({ userId }) {
  const [data, setData] = useState(null)

  useEffect(() => {
    if (!userId) return
    supabase.from('profiles').select('reliability_score').eq('id', userId).single()
      .then(({ data: p }) => {
        if (p?.reliability_score?.total != null) setData(p.reliability_score)
      })
  }, [userId])

  if (!data) return null
  const r = getRank(data.total)
  return (
    <span className="rounded-btn text-sm font-extrabold uppercase tracking-wide inline-flex items-center gap-1" style={{ padding: '4px 12px', background: r.bg, color: r.color }}>
      {r.rank} · {data.total}
    </span>
  )
}

function ScoreRow({ label, detail, score, max, color }) {
  const pct = max > 0 ? (score / max) * 100 : 0
  return (
    <div className="flex items-center gap-3">
      <div className="flex-1 min-w-0">
        <div className="flex justify-between text-sm">
          <span style={{ color: '#0f1a14' }}>{label}</span>
          <span style={{ color: '#1a2e22' }}>{detail}</span>
        </div>
        <div className="rounded-full overflow-hidden mt-1" style={{ height: 4, background: '#e5e7eb' }}>
          <div className="rounded-full h-full" style={{ width: `${pct}%`, background: color }} />
        </div>
      </div>
      <span className="text-sm font-bold" style={{ color, minWidth: 50, textAlign: 'right' }}>{score}/{max}</span>
    </div>
  )
}

function PenaltyRow({ label, count, penalty, max }) {
  const pct = max > 0 ? (penalty / max) * 100 : 0
  return (
    <div className="flex items-center gap-3">
      <div className="flex-1 min-w-0">
        <div className="flex justify-between text-sm">
          <span style={{ color: '#0f1a14' }}>{label}{count != null ? ` (${count}x)` : ''}</span>
        </div>
        <div className="rounded-full overflow-hidden mt-1" style={{ height: 4, background: '#e5e7eb' }}>
          <div className="rounded-full h-full" style={{ width: `${pct}%`, background: '#dc2626' }} />
        </div>
      </div>
      <span className="text-sm font-bold" style={{ color: penalty > 0 ? '#dc2626' : '#1a8a18', minWidth: 50, textAlign: 'right' }}>-{penalty}/{max}</span>
    </div>
  )
}

function ScorePlaceholder() {
  return <div className="py-4 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
}
