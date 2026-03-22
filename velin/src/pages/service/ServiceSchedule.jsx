import { useState, useEffect, useMemo, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'

import { Table, TRow, TH, TD } from '../../components/ui/Table'

const FILTERS = ['Vše', 'Nejbližší', 'Následující měsíc', 'Vlastní']

// Season: April (3) – October (9), 7 months. Motos only ride during season.
const SEASON_MONTHS = 7
const SEASON_START = 3
const SEASON_END = 9

function isInSeason(date) {
  const m = date.getMonth()
  return m >= SEASON_START && m <= SEASON_END
}

function seasonDaysBetween(from, to) {
  let count = 0
  const d = new Date(from); d.setHours(0, 0, 0, 0)
  const end = new Date(to); end.setHours(0, 0, 0, 0)
  while (d <= end) { if (isInSeason(d)) count++; d.setDate(d.getDate() + 1) }
  return count
}

function addSeasonDays(from, seasonDays) {
  const d = new Date(from); d.setHours(0, 0, 0, 0)
  let added = 0
  while (added < seasonDays) { d.setDate(d.getDate() + 1); if (isInSeason(d)) added++ }
  return d
}

function isoDate(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

// Find the nearest Tuesday (2) or Wednesday (3) on or after a given date
function nearestTueWed(date) {
  const d = new Date(date)
  d.setHours(0, 0, 0, 0)
  for (let i = 0; i < 14; i++) {
    const day = d.getDay()
    if (day === 2 || day === 3) return new Date(d)
    d.setDate(d.getDate() + 1)
  }
  return new Date(date) // fallback
}

// Find the nearest Tue/Wed that doesn't overlap with any booking for a moto
function findFreeServiceDate(baseDate, bookings) {
  const d = new Date(baseDate)
  d.setHours(0, 0, 0, 0)
  // Search up to 60 days ahead
  for (let i = 0; i < 60; i++) {
    const day = d.getDay()
    if (day === 2 || day === 3) {
      const ds = isoDate(d)
      const hasBooking = bookings.some(b => {
        const bs = (b.start_date || '').split('T')[0]
        const be = (b.end_date || '').split('T')[0]
        return ds >= bs && ds <= be
      })
      if (!hasBooking) return new Date(d)
    }
    d.setDate(d.getDate() + 1)
  }
  // Fallback: nearest Tue/Wed regardless of bookings
  return nearestTueWed(baseDate)
}

export default function ServiceSchedule() {
  const [schedules, setSchedules] = useState([])
  const [bookings, setBookings] = useState([])  // all active bookings
  const [avgKmPerDay, setAvgKmPerDay] = useState({}) // moto_id -> km/day
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('Vše')
  const [customFrom, setCustomFrom] = useState('')
  const [customTo, setCustomTo] = useState('')
  const [manualDates, setManualDates] = useState({}) // schedule_id -> date string
  const [editingDate, setEditingDate] = useState(null) // schedule_id being edited
  const [savingDate, setSavingDate] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      debugLog('ServiceSchedule', 'load')
      const [schedRes, bookRes, logRes] = await Promise.all([
        debugAction('maintenance_schedules.list', 'ServiceSchedule', () =>
          supabase
            .from('maintenance_schedules')
            .select('*, motorcycles(id, model, spz, mileage, purchase_mileage, year)')
            .eq('active', true)
            .order('next_due', { ascending: true, nullsFirst: false })
        ),
        // Fetch active bookings (next 6 months) for availability checking
        supabase.from('bookings')
          .select('moto_id, start_date, end_date')
          .in('status', ['pending', 'reserved', 'active'])
          .gte('end_date', isoDate(new Date())),
        // Fetch maintenance logs for avg km/day calculation
        supabase.from('maintenance_log')
          .select('moto_id, mileage_at_service, created_at')
          .order('created_at', { ascending: true }),
      ])

      if (schedRes.error) throw schedRes.error
      setSchedules(schedRes.data || [])
      setBookings(bookRes.data || [])

      // Calculate avg km/day per motorcycle
      const logs = logRes.data || []
      const byMoto = {}
      for (const l of logs) {
        if (!l.moto_id || !l.mileage_at_service) continue
        if (!byMoto[l.moto_id]) byMoto[l.moto_id] = []
        byMoto[l.moto_id].push(l)
      }

      const avgMap = {}
      for (const [motoId, entries] of Object.entries(byMoto)) {
        if (entries.length >= 2) {
          const first = entries[0], last = entries[entries.length - 1]
          const kmDiff = (last.mileage_at_service || 0) - (first.mileage_at_service || 0)
          const sDays = seasonDaysBetween(new Date(first.created_at), new Date(last.created_at))
          if (sDays > 0 && kmDiff > 0) {
            avgMap[motoId] = kmDiff / sDays // km per season-day
          }
        }
      }

      // Fallback: use mileage / season-months since purchase year
      for (const s of (schedRes.data || [])) {
        const moto = s.motorcycles
        if (moto && !avgMap[moto.id] && moto.mileage && moto.year) {
          const seasonMonths = Math.max(1, (new Date().getFullYear() - moto.year) * SEASON_MONTHS)
          avgMap[moto.id] = moto.mileage / (seasonMonths * 30) // km per season-day
        }
      }

      setAvgKmPerDay(avgMap)
    } catch (e) {
      debugError('ServiceSchedule', 'load', e)
    }
    setLoading(false)
  }

  // Enrich schedules with computed remaining km and auto-estimated date
  const enriched = useMemo(() => {
    const now = new Date()
    return schedules.map(s => {
      const currentKm = Number(s.motorcycles?.mileage) || 0
      const baseMileage = Number(s.motorcycles?.purchase_mileage) || 0
      const hasBeenServiced = !!s.last_service_km

      let nextAt
      if (!hasBeenServiced && s.first_service_km) {
        nextAt = baseMileage + Number(s.first_service_km)
      } else if (hasBeenServiced) {
        nextAt = s.last_service_km + (s.interval_km || 0)
      } else {
        nextAt = baseMileage + (s.interval_km || 0)
      }

      const remaining = nextAt - currentKm
      const overdue = s.interval_km ? remaining <= 0 : false

      // Manual override from DB
      const dbDate = s.next_due || s.next_date || null

      // Auto-estimate date only for regular planned services (with interval)
      let autoDate = null
      const motoId = s.motorcycles?.id || s.moto_id
      const dailyKm = avgKmPerDay[motoId]
      const isRegularService = !!(s.interval_km || s.interval_days)

      if (isRegularService && overdue) {
        // Already overdue — plan ASAP (nearest Tue/Wed)
        const motoBookings = bookings.filter(b => b.moto_id === motoId)
        autoDate = findFreeServiceDate(now, motoBookings)
      } else if (isRegularService && dailyKm > 0 && remaining > 0) {
        // dailyKm is per season-day, so estimate season-days until service
        const seasonDaysUntil = Math.ceil(remaining / dailyKm)
        const estReachDate = addSeasonDays(now, seasonDaysUntil)
        // Find free Tue/Wed near that date
        const motoBookings = bookings.filter(b => b.moto_id === motoId)
        autoDate = findFreeServiceDate(estReachDate, motoBookings)
      }

      // Priority: manual override (from DB next_due) > auto-estimated
      const estDate = dbDate ? new Date(dbDate) : autoDate
      const isAutoEstimated = !dbDate && !!autoDate

      return { ...s, remaining, overdue, nextAt, estDate, autoDate, isAutoEstimated, dailyKm: dailyKm || 0 }
    })
  }, [schedules, avgKmPerDay, bookings])

  // Apply filters
  const filtered = useMemo(() => {
    let items = enriched

    if (filter === 'Nejbližší') {
      const byMoto = {}
      for (const s of items) {
        const motoId = s.moto_id
        if (!byMoto[motoId] || s.remaining < byMoto[motoId].remaining) {
          byMoto[motoId] = s
        }
      }
      items = Object.values(byMoto)
    } else if (filter === 'Následující měsíc') {
      const now = new Date()
      const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, now.getDate())
      items = items.filter(s => {
        if (s.overdue) return true
        if (s.estDate && s.estDate <= nextMonth) return true
        return false
      })
    } else if (filter === 'Vlastní') {
      const from = customFrom ? new Date(customFrom) : null
      const to = customTo ? new Date(customTo + 'T23:59:59') : null
      if (from || to) {
        items = items.filter(s => {
          if (!s.estDate) return false
          if (from && s.estDate < from) return false
          if (to && s.estDate > to) return false
          return true
        })
      }
    }

    return items.sort((a, b) => {
      if (a.overdue !== b.overdue) return a.overdue ? -1 : 1
      return a.remaining - b.remaining
    })
  }, [enriched, filter, customFrom, customTo])

  // Save manual date override to DB
  async function saveDate(scheduleId, dateStr) {
    setSavingDate(scheduleId)
    try {
      const { error } = await supabase.from('maintenance_schedules')
        .update({ next_due: dateStr || null })
        .eq('id', scheduleId)
      if (error) throw error
      // Update local state
      setSchedules(prev => prev.map(s => s.id === scheduleId ? { ...s, next_due: dateStr || null } : s))
      setEditingDate(null)
      setManualDates(prev => { const n = { ...prev }; delete n[scheduleId]; return n })
    } catch (e) {
      debugError('ServiceSchedule', 'saveDate', e)
    }
    setSavingDate(null)
  }

  // Reset to auto-estimated date (clear manual override)
  async function resetDate(scheduleId) {
    await saveDate(scheduleId, null)
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <div>
      {/* Filter bar */}
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        {FILTERS.map(f => (
          <button key={f} onClick={() => setFilter(f)}
            className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '6px 14px',
              background: filter === f ? '#74FB71' : '#f1faf7',
              color: '#1a2e22',
              border: 'none',
              boxShadow: filter === f ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}>
            {f}
          </button>
        ))}
        {filter === 'Vlastní' && (
          <div className="flex items-center gap-2 ml-2">
            <input type="date" value={customFrom} onChange={e => setCustomFrom(e.target.value)}
              className="rounded-lg text-xs px-2 py-1" style={{ border: '1px solid #d1d5db', background: '#fff' }} />
            <span className="text-xs" style={{ color: '#1a2e22' }}>—</span>
            <input type="date" value={customTo} onChange={e => setCustomTo(e.target.value)}
              className="rounded-lg text-xs px-2 py-1" style={{ border: '1px solid #d1d5db', background: '#fff' }} />
          </div>
        )}
        <span className="ml-auto text-xs" style={{ color: '#6b7280' }}>{filtered.length} záznamů</span>
      </div>

      <Table>
        <thead>
          <TRow header>
            <TH>Motorka</TH><TH>SPZ</TH><TH>Popis</TH>
            <TH>Interval</TH><TH>Zbývá km</TH><TH>Plánované datum</TH>
          </TRow>
        </thead>
        <tbody>
          {filtered.map(s => {
            const isEditing = editingDate === s.id
            const dateVal = manualDates[s.id] ?? (s.estDate ? isoDate(s.estDate) : '')
            const hasManualOverride = !!(s.next_due || s.next_date)

            return (
              <TRow key={s.id}>
                <TD bold>{s.motorcycles?.model || '—'}</TD>
                <TD mono>{s.motorcycles?.spz || '—'}</TD>
                <TD>{s.description || TYPE_LABELS[s.schedule_type] || s.schedule_type || '—'}</TD>
                <TD>{s.interval_km ? `${s.interval_km.toLocaleString('cs-CZ')} km` : ''}{s.interval_days ? ` / ${s.interval_days} dní` : ''}</TD>
                <TD style={s.overdue ? { color: '#dc2626', fontWeight: 700 } : undefined}>
                  {s.interval_km ? (s.overdue ? `⚠ ${Math.abs(s.remaining).toLocaleString('cs-CZ')} km po` : `${s.remaining.toLocaleString('cs-CZ')} km`) : '—'}
                  {!(Number(s.motorcycles?.mileage) || 0) && s.interval_km ? ' (km nenastaven)' : ''}
                </TD>
                <TD>
                  {isEditing ? (
                    <div className="flex items-center gap-1">
                      <input type="date" value={dateVal}
                        onChange={e => setManualDates(prev => ({ ...prev, [s.id]: e.target.value }))}
                        className="rounded text-xs px-1 py-0.5" style={{ border: '1px solid #d1d5db', width: 130 }} />
                      <button onClick={() => saveDate(s.id, manualDates[s.id] || dateVal)}
                        disabled={savingDate === s.id}
                        className="text-xs font-bold cursor-pointer" style={{ color: '#1a8a18', background: 'none', border: 'none' }}>
                        {savingDate === s.id ? '…' : '✓'}
                      </button>
                      <button onClick={() => { setEditingDate(null); setManualDates(prev => { const n = { ...prev }; delete n[s.id]; return n }) }}
                        className="text-xs cursor-pointer" style={{ color: '#6b7280', background: 'none', border: 'none' }}>✕</button>
                    </div>
                  ) : (
                    <div className="flex items-center gap-1">
                      <span className="cursor-pointer" onClick={() => setEditingDate(s.id)}
                        title={s.isAutoEstimated ? `Odhad (~${Math.round(s.dailyKm)} km/den). Klikni pro ruční úpravu.` : 'Klikni pro úpravu'}>
                        {s.estDate ? (
                          <>
                            {s.estDate.toLocaleDateString('cs-CZ')}
                            {s.isAutoEstimated && <span className="ml-1" style={{ color: '#6b7280', fontSize: 10 }} title="Automatický odhad">~</span>}
                          </>
                        ) : '—'}
                      </span>
                      {hasManualOverride && (
                        <button onClick={() => resetDate(s.id)}
                          className="text-xs cursor-pointer ml-1" style={{ color: '#6b7280', background: 'none', border: 'none', fontSize: 10 }}
                          title="Obnovit automatický odhad">↺</button>
                      )}
                    </div>
                  )}
                </TD>
              </TRow>
            )
          })}
          {filtered.length === 0 && <TRow><TD colSpan={6}>Žádné servisní plány pro zvolený filtr.</TD></TRow>}
        </tbody>
      </Table>

      <div className="mt-3 text-xs" style={{ color: '#6b7280' }}>
        <span style={{ fontSize: 10 }}>~</span> = automatický odhad (Út/St bez rezervace, dle průměrného nájezdu) · Klikněte na datum pro ruční úpravu
      </div>
    </div>
  )
}

export const TYPE_LABELS = {
  oil_change: 'Výměna oleje',
  tire_change: 'Výměna pneumatik',
  brake_check: 'Kontrola brzd',
  full_service: 'Kompletní servis',
  repair: 'Oprava',
  inspection: 'STK / Inspekce',
}
