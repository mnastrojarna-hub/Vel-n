import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'

import { Table, TRow, TH, TD } from '../../components/ui/Table'
import StatusBadge from '../../components/ui/StatusBadge'

const FILTERS = ['Vše', 'Nejbližší', 'Následující měsíc', 'Vlastní']

export default function ServiceSchedule() {
  const [schedules, setSchedules] = useState([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('Vše')
  const [customFrom, setCustomFrom] = useState('')
  const [customTo, setCustomTo] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      debugLog('ServiceSchedule', 'load')
      const { data, error } = await debugAction('maintenance_schedules.list', 'ServiceSchedule', () =>
        supabase
          .from('maintenance_schedules')
          .select('*, motorcycles(model, spz, mileage, purchase_mileage)')
          .eq('active', true)
          .order('next_due', { ascending: true, nullsFirst: false })
      )
      if (error) throw error
      setSchedules(data || [])
    } catch (e) {
      debugError('ServiceSchedule', 'load', e)
    }
    setLoading(false)
  }

  // Enrich schedules with computed remaining km and estimated date
  const enriched = useMemo(() => {
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

      // Estimated next date: from next_due, or from next_date, or null
      const estDate = s.next_due ? new Date(s.next_due) : s.next_date ? new Date(s.next_date) : null

      return { ...s, remaining, overdue, nextAt, estDate }
    })
  }, [schedules])

  // Apply filters
  const filtered = useMemo(() => {
    let items = enriched

    if (filter === 'Nejbližší') {
      // Per motorcycle: only keep the schedule with smallest remaining km (most urgent)
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
        // Include overdue (always urgent)
        if (s.overdue) return true
        // Include if estimated date is within next month
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

    // Sort: overdue first, then by remaining km ascending
    return items.sort((a, b) => {
      if (a.overdue !== b.overdue) return a.overdue ? -1 : 1
      return a.remaining - b.remaining
    })
  }, [enriched, filter, customFrom, customTo])

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
          {filtered.map(s => (
            <TRow key={s.id}>
              <TD bold>{s.motorcycles?.model || '—'}</TD>
              <TD mono>{s.motorcycles?.spz || '—'}</TD>
              <TD>{s.description || TYPE_LABELS[s.schedule_type] || s.schedule_type || '—'}</TD>
              <TD>{s.interval_km ? `${s.interval_km.toLocaleString('cs-CZ')} km` : ''}{s.interval_days ? ` / ${s.interval_days} dní` : ''}</TD>
              <TD style={s.overdue ? { color: '#dc2626', fontWeight: 700 } : undefined}>
                {s.interval_km ? (s.overdue ? `⚠ ${Math.abs(s.remaining).toLocaleString('cs-CZ')} km po` : `${s.remaining.toLocaleString('cs-CZ')} km`) : '—'}
                {!(Number(s.motorcycles?.mileage) || 0) && s.interval_km ? ' (km nenastaven)' : ''}
              </TD>
              <TD>{s.estDate ? s.estDate.toLocaleDateString('cs-CZ') : '—'}</TD>
            </TRow>
          ))}
          {filtered.length === 0 && <TRow><TD colSpan={6}>Žádné servisní plány pro zvolený filtr.</TD></TRow>}
        </tbody>
      </Table>
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
