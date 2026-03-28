import { useNavigate } from 'react-router-dom'
import Card from '../components/ui/Card'

// Season: April (3) – October (9), 7 months. Motos only ride during season.
const SEASON_MONTHS = 7
const SEASON_START = 3 // April (0-indexed)
const SEASON_END = 9   // October (0-indexed)

function isInSeason(date) {
  const m = date.getMonth()
  return m >= SEASON_START && m <= SEASON_END
}

// Count season days between two dates
function seasonDaysBetween(from, to) {
  let count = 0
  const d = new Date(from)
  d.setHours(0, 0, 0, 0)
  const end = new Date(to)
  end.setHours(0, 0, 0, 0)
  while (d <= end) {
    if (isInSeason(d)) count++
    d.setDate(d.getDate() + 1)
  }
  return count
}

// Estimate future date adding N season-only days from now
function addSeasonDays(from, seasonDays) {
  const d = new Date(from)
  d.setHours(0, 0, 0, 0)
  let added = 0
  while (added < seasonDays) {
    d.setDate(d.getDate() + 1)
    if (isInSeason(d)) added++
  }
  return d
}

// Winter service: find free weekday (Mon-Fri) in Jan-Feb for a given year
function findWinterServiceDate(year, bookings) {
  for (let month = 0; month <= 1; month++) {
    const d = new Date(year, month, 1)
    d.setHours(0, 0, 0, 0)
    while (d.getMonth() === month) {
      const day = d.getDay()
      if (day >= 1 && day <= 5) {
        const ds = d.toISOString().slice(0, 10)
        const busy = bookings.some(b => {
          const bs = (b.start_date || '').split('T')[0]
          const be = (b.end_date || '').split('T')[0]
          return ds >= bs && ds <= be
        })
        if (!busy) return new Date(d)
      }
      d.setDate(d.getDate() + 1)
    }
  }
  return new Date(year, 0, 15)
}

// Check if date falls in last 2 weeks of October (Oct 17-31)
function isLateOctober(date) {
  if (!date) return false
  return date.getMonth() === 9 && date.getDate() >= 17
}

// Find nearest Tue/Wed without an active booking for this moto
function findFreeTueWed(baseDate, bookings) {
  const d = new Date(baseDate)
  d.setHours(0, 0, 0, 0)
  for (let i = 0; i < 60; i++) {
    const day = d.getDay()
    if (day === 2 || day === 3) {
      const ds = d.toISOString().slice(0, 10)
      const busy = bookings.some(b => {
        const bs = (b.start_date || '').split('T')[0]
        const be = (b.end_date || '').split('T')[0]
        return ds >= bs && ds <= be
      })
      if (!busy) return new Date(d)
    }
    d.setDate(d.getDate() + 1)
  }
  return null
}

export { SEASON_MONTHS, SEASON_START, SEASON_END, isInSeason, seasonDaysBetween, addSeasonDays, findWinterServiceDate, isLateOctober, findFreeTueWed }

export function ServiceScheduleCard({ moto, schedules, avgKm, unitLabel, unit, motoBookings }) {
  const navigate = useNavigate()
  const currentKm = Number(moto.mileage) || 0
  const baseMileage = Number(moto.purchase_mileage) || 0

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>Nájezd a servis</h3>
      <div className="flex gap-6 mb-3">
        <div className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
          <div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Měsíční průměr</div>
          <div className="text-lg font-extrabold">{avgKm != null ? `${avgKm.toLocaleString('cs-CZ')} ${unitLabel}` : '—'}</div>
        </div>
        <div className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
          <div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Celkem</div>
          <div className="text-lg font-extrabold">{moto.mileage ? `${Number(moto.mileage).toLocaleString('cs-CZ')} ${unitLabel}` : '—'}</div>
        </div>
      </div>
        {schedules.map(s => {
          const currentKm = Number(moto.mileage) || 0
          const baseMileage = Number(moto.purchase_mileage) || 0
          const hasBeenServiced = !!s.last_service_km
          let nextAt
          if (!hasBeenServiced && s.first_service_km) {
            nextAt = baseMileage + Number(s.first_service_km)
          } else if (hasBeenServiced) {
            nextAt = s.last_service_km + (s.interval_km || 0)
          } else {
            nextAt = baseMileage + (s.interval_km || 0)
          }
          const rem = nextAt - currentKm
          const overdue = rem <= 0

          // Estimate planned service date (Tue/Wed without booking)
          let planDate = null
          let mergedWithWinter = false
          const dbDate = s.next_due || s.next_date
          const now = new Date()
          const winterYear = now.getMonth() >= 2 ? now.getFullYear() + 1 : now.getFullYear()

          if (dbDate) {
            planDate = new Date(dbDate)
          } else if (s.interval_km || s.interval_days) {
            if (overdue) {
              planDate = findFreeTueWed(now, motoBookings)
            } else if (avgKm > 0 && rem > 0) {
              const dailyKm = avgKm / 30
              const seasonDaysUntil = Math.ceil(rem / dailyKm)
              const est = addSeasonDays(now, seasonDaysUntil)

              // October merge: last 2 weeks of Oct + 25% tolerance
              if (isLateOctober(est) && s.interval_km) {
                const extendedRemaining = rem - (s.interval_km * 0.25)
                if (extendedRemaining > 0) {
                  planDate = findWinterServiceDate(winterYear, motoBookings)
                  mergedWithWinter = true
                } else {
                  planDate = findFreeTueWed(est, motoBookings)
                }
              } else {
                planDate = findFreeTueWed(est, motoBookings)
              }
            }
          }

          return (
            <div key={s.id} className="flex flex-col gap-1 p-2 rounded-lg mb-1" style={{ background: overdue ? '#fee2e2' : mergedWithWinter ? '#dbeafe' : '#f1faf7', fontSize: 12 }}>
              <div className="flex items-center gap-3">
                <span className="font-bold">{s.description}</span>
                <span style={{ color: '#1a2e22' }}>každých {s.interval_km?.toLocaleString('cs-CZ')} {unitLabel}</span>
                <span className="ml-auto font-bold" style={{ color: overdue ? '#dc2626' : mergedWithWinter ? '#2563eb' : '#1a8a18' }}>
                  {overdue ? `PO TERMÍNU ${Math.abs(rem).toLocaleString('cs-CZ')} ${unitLabel}` : `za ${rem.toLocaleString('cs-CZ')} ${unitLabel}`}
                  {mergedWithWinter && ' → zimní servis'}
                  {!overdue && !mergedWithWinter && avgKm > 0 ? ` (~${Math.round((rem / avgKm) * 30)} dní ${unit === 'mh' ? 'provozu' : 'jízdy'})` : ''}
                </span>
              </div>
              {planDate && (
                <div className="flex items-center gap-1" style={{ color: '#6b7280', fontSize: 11 }}>
                  <span>{mergedWithWinter ? 'Sloučeno se zimním servisem:' : 'Plánovaný servis:'}</span>
                  <span className="font-bold" style={{ color: overdue ? '#dc2626' : mergedWithWinter ? '#2563eb' : '#1a2e22' }}>
                    {planDate.toLocaleDateString('cs-CZ', { weekday: 'short', day: 'numeric', month: 'numeric', year: 'numeric' })}
                  </span>
                  {!dbDate && !mergedWithWinter && <span title="Automatický odhad (Út/St bez rezervace)">~</span>}
                </div>
              )}
            </div>
          )
        })}

        {/* Winter service entry */}
        {(() => {
          const now = new Date()
          const winterYear = now.getMonth() >= 2 ? now.getFullYear() + 1 : now.getFullYear()
          const winterDate = findWinterServiceDate(winterYear, motoBookings)
          return (
            <div className="flex flex-col gap-1 p-2 rounded-lg mb-1" style={{ background: '#dbeafe', fontSize: 12 }}>
              <div className="flex items-center gap-3">
                <span className="font-bold" style={{ color: '#2563eb' }}>Velký zimní servis</span>
                <span style={{ color: '#1a2e22' }}>leden–únor {winterYear}</span>
                <span className="ml-auto font-bold" style={{ color: '#2563eb' }}>bez ohledu na {unitLabel}</span>
              </div>
              <div className="flex items-center gap-1" style={{ color: '#6b7280', fontSize: 11 }}>
                <span>Plánovaný servis:</span>
                <span className="font-bold" style={{ color: '#2563eb' }}>
                  {winterDate.toLocaleDateString('cs-CZ', { weekday: 'short', day: 'numeric', month: 'numeric', year: 'numeric' })}
                </span>
                <span title="Automatický odhad (Po–Pá bez rezervace)">~</span>
              </div>
            </div>
          )
        })()}

        {schedules.length === 0 && <p style={{ color: '#1a2e22', fontSize: 12 }}>Žádné plány — přidejte v záložce Servis</p>}

      {schedules.length === 0 && <p style={{ color: '#1a2e22', fontSize: 12 }}>Žádné plány — přidejte v záložce Servis</p>}
    </Card>
  )
}

export function SOSIncidentsCard({ sosIncidents, motoId }) {
  const navigate = useNavigate()
  if (sosIncidents.length === 0) return null

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#dc2626' }}>🆘 SOS Incidenty ({sosIncidents.length})</h3>
      <div className="space-y-2">
        {sosIncidents.map(inc => {
          const typeLabels = { theft: '🔒 Krádež', accident_minor: '💥 Lehká nehoda', accident_major: '💥 Závažná nehoda', breakdown_minor: '🔧 Drobná závada', breakdown_major: '🔧 Velká porucha', defect_question: '❓ Dotaz', location_share: '📍 Poloha', other: '📋 Jiné' }
          const statusColors = { reported: '#fee2e2', acknowledged: '#fef3c7', in_progress: '#dbeafe', resolved: '#dcfce7', closed: '#f3f4f6' }
          return (
            <div key={inc.id} className="flex items-center gap-3 p-2 rounded-lg cursor-pointer" style={{ background: statusColors[inc.status] || '#f3f4f6', fontSize: 12 }}
              onClick={() => navigate('/sos', { state: { openIncidentId: inc.id } })}>
              <span className="font-extrabold">{typeLabels[inc.type] || inc.type}</span>
              <span style={{ color: '#1a2e22' }}>{inc.status}</span>
              {inc.severity && <span className="font-bold" style={{ color: inc.severity === 'critical' ? '#dc2626' : inc.severity === 'high' ? '#b91c1c' : '#1a2e22' }}>{inc.severity}</span>}
              <span className="ml-auto" style={{ color: '#1a2e22' }}>{new Date(inc.created_at).toLocaleDateString('cs-CZ')}</span>
              {inc.booking_id && <span className="font-mono text-[10px]" style={{ color: '#1a2e22' }}>#{inc.booking_id.slice(-8).toUpperCase()}</span>}
            </div>
          )
        })}
      </div>
    </Card>
  )
}
