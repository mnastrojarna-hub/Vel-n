import { useState, useEffect, useMemo, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'

import { Table, TRow, TH, TD } from '../../components/ui/Table'

const FILTERS = ['Vše', 'Nejbližší', 'Následující měsíc', 'Vlastní']

// Season: April (3) – October (9), 7 months. Motos only ride during season.
const SEASON_MONTHS = 7
const SEASON_START = 3
const SEASON_END = 9

// České státní svátky (měsíc 0-indexed, den)
function getCzechHolidays(year) {
  const fixed = [
    [0, 1],   // Nový rok
    [4, 1],   // Svátek práce
    [4, 8],   // Den vítězství
    [6, 5],   // Slovanští věrozvěstové
    [6, 6],   // Mistr Jan Hus
    [8, 28],  // Den české státnosti
    [9, 28],  // Vznik Československa
    [10, 17], // Den boje za svobodu
    [11, 24], // Štědrý den
    [11, 25], // 1. svátek vánoční
    [11, 26], // 2. svátek vánoční
  ]
  const holidays = new Set(fixed.map(([m, d]) => `${year}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`))
  // Velikonoční pondělí (pohyblivý svátek) — výpočet dle Gaussova algoritmu
  const a = year % 19, b = Math.floor(year / 100), c = year % 100
  const d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25)
  const g = Math.floor((b - f + 1) / 3), h = (19 * a + b - d - g + 15) % 30
  const i = Math.floor(c / 4), k = c % 4
  const l = (32 + 2 * e + 2 * i - h - k) % 7
  const m = Math.floor((a + 11 * h + 22 * l) / 451)
  const month = Math.floor((h + l - 7 * m + 114) / 31) - 1
  const day = ((h + l - 7 * m + 114) % 31) + 1
  // Velikonoční neděle
  const easter = new Date(year, month, day)
  // Velký pátek (Easter - 2)
  const goodFriday = new Date(easter); goodFriday.setDate(easter.getDate() - 2)
  holidays.add(isoDate(goodFriday))
  // Velikonoční pondělí (Easter + 1)
  const easterMonday = new Date(easter); easterMonday.setDate(easter.getDate() + 1)
  holidays.add(isoDate(easterMonday))
  return holidays
}

// Blokovaný den = svátek NEBO v období 20.12–7.1 (vánoční pauza)
function isBlockedDay(date) {
  const m = date.getMonth() // 0-indexed
  const d = date.getDate()
  const y = date.getFullYear()
  // Období 20.12–7.1 (přes roky)
  if (m === 11 && d >= 20) return true // 20.-31. prosinec
  if (m === 0 && d <= 7) return true   // 1.-7. leden
  // Český státní svátek
  const holidays = getCzechHolidays(y)
  return holidays.has(isoDate(date))
}

// Pracovní den vhodný pro servis = Po-Pá + není blokovaný
function isServiceDay(date) {
  const day = date.getDay()
  return day >= 1 && day <= 5 && !isBlockedDay(date)
}

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

// Winter service: find free service day (Mon-Fri, no holidays, no 20.12-7.1) in Jan-Feb
function findWinterServiceDate(year, bookings) {
  for (let month = 0; month <= 1; month++) {
    const d = new Date(year, month, 1)
    d.setHours(0, 0, 0, 0)
    while (d.getMonth() === month) {
      if (isServiceDay(d)) {
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
  }
  return new Date(year, 0, 15)
}

// STK scheduling: distribute motorcycles across Dec-Feb service days, max 2 per day
// Vynechává 20.12–7.1 (Vánoce) a české státní svátky
function scheduleStkDates(motos, bookings, year) {
  // Collect all available service days (Mon-Fri, no holidays, no Christmas break) in Dec-Feb
  const availableDays = []
  // December of previous year
  for (let d = new Date(year - 1, 11, 1); d.getMonth() === 11; d.setDate(d.getDate() + 1)) {
    if (isServiceDay(d)) availableDays.push(new Date(d))
  }
  // January
  for (let d = new Date(year, 0, 1); d.getMonth() === 0; d.setDate(d.getDate() + 1)) {
    if (isServiceDay(d)) availableDays.push(new Date(d))
  }
  // February
  for (let d = new Date(year, 1, 1); d.getMonth() === 1; d.setDate(d.getDate() + 1)) {
    if (isServiceDay(d)) availableDays.push(new Date(d))
  }

  // Assign motos to days: max 2 per day, evenly distributed
  const assignments = {} // motoId -> Date
  const dayUsage = {} // isoDate -> count
  let dayIdx = 0

  for (const moto of motos) {
    const motoBookings = bookings.filter(b => b.moto_id === moto.id)
    let assigned = false
    // Try from current dayIdx onwards, wrap around
    for (let attempt = 0; attempt < availableDays.length; attempt++) {
      const idx = (dayIdx + attempt) % availableDays.length
      const candidate = availableDays[idx]
      const ds = isoDate(candidate)
      const usage = dayUsage[ds] || 0
      if (usage >= 2) continue
      // Check no booking conflict
      const hasBooking = motoBookings.some(b => {
        const bs = (b.start_date || '').split('T')[0]
        const be = (b.end_date || '').split('T')[0]
        return ds >= bs && ds <= be
      })
      if (hasBooking) continue
      assignments[moto.id] = new Date(candidate)
      dayUsage[ds] = usage + 1
      dayIdx = (idx + 1) % availableDays.length
      assigned = true
      break
    }
    if (!assigned) {
      // Fallback: Jan 15
      assignments[moto.id] = new Date(year, 0, 15)
    }
  }
  return assignments
}

// Check if date falls in last 2 weeks of October (Oct 17-31)
function isLateOctober(date) {
  if (!date) return false
  return date.getMonth() === 9 && date.getDate() >= 17
}

function isoDate(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

// Find the nearest Tuesday (2) or Wednesday (3) on or after a given date, skipping blocked days
function nearestTueWed(date) {
  const d = new Date(date)
  d.setHours(0, 0, 0, 0)
  for (let i = 0; i < 30; i++) {
    const day = d.getDay()
    if ((day === 2 || day === 3) && !isBlockedDay(d)) return new Date(d)
    d.setDate(d.getDate() + 1)
  }
  return new Date(date) // fallback
}

// Find the nearest Tue/Wed that doesn't overlap with any booking and isn't blocked
function findFreeServiceDate(baseDate, bookings) {
  const d = new Date(baseDate)
  d.setHours(0, 0, 0, 0)
  // Search up to 90 days ahead
  for (let i = 0; i < 90; i++) {
    const day = d.getDay()
    if ((day === 2 || day === 3) && !isBlockedDay(d)) {
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
  const [allMotos, setAllMotos] = useState([]) // all motorcycles for STK
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
      const [schedRes, bookRes, logRes, motosRes] = await Promise.all([
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
        // Fetch all motorcycles for STK scheduling
        supabase.from('motorcycles')
          .select('id, model, spz, stk_valid_until')
          .order('model'),
      ])

      if (schedRes.error) throw schedRes.error
      setSchedules(schedRes.data || [])
      setBookings(bookRes.data || [])
      setAllMotos(motosRes.data || [])

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
    // Determine next winter service year (Jan-Feb)
    const winterYear = now.getMonth() >= 2 ? now.getFullYear() + 1 : now.getFullYear()

    const results = schedules.map(s => {
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
      let mergedWithWinter = false

      if (isRegularService && overdue) {
        const motoBookings = bookings.filter(b => b.moto_id === motoId)
        autoDate = findFreeServiceDate(now, motoBookings)
      } else if (isRegularService && dailyKm > 0 && remaining > 0) {
        const seasonDaysUntil = Math.ceil(remaining / dailyKm)
        const estReachDate = addSeasonDays(now, seasonDaysUntil)
        const motoBookings = bookings.filter(b => b.moto_id === motoId)

        // October merge: if service falls in last 2 weeks of Oct and
        // remaining km allows +25% tolerance, merge with winter service
        if (isLateOctober(estReachDate) && s.interval_km) {
          const extendedRemaining = remaining - (s.interval_km * 0.25)
          if (extendedRemaining > 0) {
            // Can safely extend — merge with winter service
            autoDate = findWinterServiceDate(winterYear, motoBookings)
            mergedWithWinter = true
          } else {
            // Too many km remaining even with tolerance — do service now
            autoDate = findFreeServiceDate(estReachDate, motoBookings)
          }
        } else {
          autoDate = findFreeServiceDate(estReachDate, motoBookings)
        }
      }

      const estDate = dbDate ? new Date(dbDate) : autoDate
      const isAutoEstimated = !dbDate && !!autoDate

      return { ...s, remaining, overdue, nextAt, estDate, autoDate, isAutoEstimated, dailyKm: dailyKm || 0, mergedWithWinter }
    })

    // Add virtual winter service entries for each unique moto
    const motoIds = new Set()
    for (const s of schedules) {
      const motoId = s.motorcycles?.id || s.moto_id
      if (motoId) motoIds.add(motoId)
    }
    for (const motoId of motoIds) {
      const motoSched = schedules.find(s => (s.motorcycles?.id || s.moto_id) === motoId)
      const moto = motoSched?.motorcycles
      const motoBookings = bookings.filter(b => b.moto_id === motoId)
      const winterDate = findWinterServiceDate(winterYear, motoBookings)
      results.push({
        id: `winter-${motoId}`,
        moto_id: motoId,
        motorcycles: moto || { id: motoId, model: '—', spz: '—' },
        description: 'Velký zimní servis',
        schedule_type: 'winter_service',
        interval_km: null,
        interval_days: null,
        remaining: null,
        overdue: false,
        nextAt: null,
        estDate: winterDate,
        autoDate: winterDate,
        isAutoEstimated: true,
        dailyKm: 0,
        mergedWithWinter: false,
        isWinterService: true,
      })
    }

    // Add virtual STK entries for ALL motorcycles (Dec-Feb, Mon-Fri, max 2/day)
    const stkYear = now.getMonth() >= 2 ? now.getFullYear() + 1 : now.getFullYear() // next winter
    const stkAssignments = scheduleStkDates(allMotos, bookings, stkYear)
    for (const moto of allMotos) {
      const stkDate = stkAssignments[moto.id]
      const stkValid = moto.stk_valid_until ? new Date(moto.stk_valid_until) : null
      // Find moto data from schedules if available, else use basic info
      const motoSched = schedules.find(s => (s.motorcycles?.id || s.moto_id) === moto.id)
      const motoData = motoSched?.motorcycles || { id: moto.id, model: moto.model, spz: moto.spz }
      results.push({
        id: `stk-${moto.id}`,
        moto_id: moto.id,
        motorcycles: motoData,
        description: 'STK & Emise',
        schedule_type: 'stk',
        interval_km: null,
        interval_days: null,
        remaining: null,
        overdue: stkValid ? stkValid < now : false,
        nextAt: null,
        estDate: stkDate,
        autoDate: stkDate,
        isAutoEstimated: true,
        dailyKm: 0,
        mergedWithWinter: false,
        isStkService: true,
        stkValidUntil: stkValid,
      })
    }

    return results
  }, [schedules, avgKmPerDay, bookings, allMotos])

  // Apply filters
  const filtered = useMemo(() => {
    let items = enriched

    if (filter === 'Nejbližší') {
      // 1) Nearest service per motorcycle
      const byMoto = {}
      for (const s of items) {
        const motoId = s.moto_id
        if (!byMoto[motoId] || (s.remaining != null && (byMoto[motoId].remaining == null || s.remaining < byMoto[motoId].remaining))) {
          byMoto[motoId] = s
        }
      }
      const motoIds = new Set(Object.values(byMoto).map(s => s.id))
      // 2) Nearest service per schedule_type (service interval)
      const byType = {}
      for (const s of items) {
        const type = s.schedule_type
        if (!type || s.isWinterService || s.isStkService) continue
        if (!byType[type] || (s.remaining != null && (byType[type].remaining == null || s.remaining < byType[type].remaining))) {
          byType[type] = s
        }
      }
      const typeIds = new Set(Object.values(byType).map(s => s.id))
      // Merge both sets (deduplicate by id), tag each item
      const merged = new Map()
      for (const s of Object.values(byMoto)) merged.set(s.id, { ...s, _nearestMoto: true, _nearestType: typeIds.has(s.id) })
      for (const s of Object.values(byType)) {
        if (merged.has(s.id)) {
          merged.get(s.id)._nearestType = true
        } else {
          merged.set(s.id, { ...s, _nearestMoto: false, _nearestType: true })
        }
      }
      items = Array.from(merged.values())
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
      // Sort by estimated date, then by remaining km
      if (a.estDate && b.estDate) return a.estDate - b.estDate
      if (a.estDate) return -1
      if (b.estDate) return 1
      return (a.remaining ?? Infinity) - (b.remaining ?? Infinity)
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
              <TRow key={s.id} style={s.isStkService ? { background: '#fef3c7' } : s.isWinterService ? { background: '#eff6ff' } : s.mergedWithWinter ? { background: '#eff6ff' } : undefined}>
                <TD bold>{s.motorcycles?.model || '—'}</TD>
                <TD mono>{s.motorcycles?.spz || '—'}</TD>
                <TD>
                  {s.isStkService ? <span style={{ color: '#b45309', fontWeight: 700 }}>STK & Emise</span> : s.isWinterService ? <span style={{ color: '#2563eb', fontWeight: 700 }}>Velký zimní servis</span> : (s.description || TYPE_LABELS[s.schedule_type] || s.schedule_type || '—')}
                  {filter === 'Nejbližší' && s._nearestMoto && <span className="ml-1" style={{ fontSize: 9, background: '#dcfce7', color: '#166534', borderRadius: 4, padding: '1px 4px', fontWeight: 600 }}>motorka</span>}
                  {filter === 'Nejbližší' && s._nearestType && <span className="ml-1" style={{ fontSize: 9, background: '#dbeafe', color: '#1e40af', borderRadius: 4, padding: '1px 4px', fontWeight: 600 }}>{TYPE_LABELS[s.schedule_type] || s.schedule_type}</span>}
                </TD>
                <TD>
                  {s.isStkService ? 'prosinec–únor' : s.isWinterService ? 'leden–únor' : ''}
                  {!s.isStkService && s.interval_km ? `${s.interval_km.toLocaleString('cs-CZ')} km` : ''}{!s.isStkService && s.interval_days ? ` / ${s.interval_days} dní` : ''}
                </TD>
                <TD style={s.overdue ? { color: '#dc2626', fontWeight: 700 } : s.mergedWithWinter ? { color: '#2563eb', fontWeight: 600 } : undefined}>
                  {s.isStkService ? (
                    s.stkValidUntil ? (() => {
                      const stkDays = Math.ceil((s.stkValidUntil - new Date()) / 86400000)
                      const color = stkDays < 0 ? '#dc2626' : stkDays < 30 ? '#dc2626' : stkDays < 90 ? '#b45309' : '#1a8a18'
                      return <span style={{ color, fontWeight: 700 }}>
                        {stkDays < 0 ? `⚠ ${Math.abs(stkDays)} dní po` : `${stkDays} dní`}
                        <span style={{ fontWeight: 400, color: '#6b7280', marginLeft: 6, fontSize: 11 }}>
                          (do {s.stkValidUntil.toLocaleDateString('cs-CZ')})
                        </span>
                      </span>
                    })() : <span style={{ color: '#6b7280' }}>STK nenastaveno</span>
                  ) : s.isWinterService ? 'bez ohledu na km' : s.interval_km ? (s.overdue ? `⚠ ${Math.abs(s.remaining).toLocaleString('cs-CZ')} km po` : `${s.remaining.toLocaleString('cs-CZ')} km`) : '—'}
                  {s.mergedWithWinter && ' → zimní servis'}
                  {!s.isStkService && !(Number(s.motorcycles?.mileage) || 0) && s.interval_km ? ' (km nenastaven)' : ''}
                </TD>
                <TD>
                  {s.isStkService ? (
                    <span style={{ color: '#b45309', fontWeight: 600 }}>
                      {s.estDate ? s.estDate.toLocaleDateString('cs-CZ') : '—'}
                      <span className="ml-1" style={{ fontSize: 10 }} title="Automaticky (Po–Pá, max 2/den, prosinec–únor)">~</span>
                    </span>
                  ) : s.isWinterService ? (
                    <span style={{ color: '#2563eb', fontWeight: 600 }}>
                      {s.estDate ? s.estDate.toLocaleDateString('cs-CZ') : '—'}
                      <span className="ml-1" style={{ fontSize: 10 }} title="Automaticky (Po–Pá bez rezervace)">~</span>
                    </span>
                  ) : isEditing ? (
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
                            {s.mergedWithWinter && <span className="ml-1" style={{ color: '#2563eb', fontSize: 10 }}>→ zimní</span>}
                            {s.isAutoEstimated && !s.mergedWithWinter && <span className="ml-1" style={{ color: '#6b7280', fontSize: 10 }} title="Automatický odhad">~</span>}
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
        <span style={{ fontSize: 10 }}>~</span> = automatický odhad (Út/St bez rezervace, dle sezónního nájezdu) · <span style={{ color: '#2563eb' }}>→ zimní servis</span> = sloučeno se zimním servisem (říjen +25% tolerance) · <span style={{ color: '#b45309' }}>STK</span> = naplánováno prosinec–únor (Po–Pá, max 2/den) · Klikněte na datum pro ruční úpravu
        {filter === 'Nejbližší' && <><br /><span style={{ background: '#dcfce7', color: '#166534', borderRadius: 4, padding: '1px 4px', fontSize: 9, fontWeight: 600 }}>motorka</span> = nejbližší servis dané motorky · <span style={{ background: '#dbeafe', color: '#1e40af', borderRadius: 4, padding: '1px 4px', fontSize: 9, fontWeight: 600 }}>typ</span> = nejbližší servis daného intervalu</>}
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
  stk: 'STK & Emise',
  winter_service: 'Velký zimní servis',
}
