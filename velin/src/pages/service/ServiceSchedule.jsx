import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'

import { Table, TRow, TH, TD } from '../../components/ui/Table'
import StatusBadge from '../../components/ui/StatusBadge'

export default function ServiceSchedule() {
  const [schedules, setSchedules] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    // Show all active schedules (with or without next_due)
    try {
      debugLog('ServiceSchedule', 'load')
      const { data, error } = await debugAction('maintenance_schedules.list', 'ServiceSchedule', () =>
        supabase
          .from('maintenance_schedules')
          .select('*, motorcycles(model, spz, mileage)')
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

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <Table>
      <thead>
        <TRow header>
          <TH>Motorka</TH><TH>SPZ</TH><TH>Popis</TH>
          <TH>Interval</TH><TH>Zbývá km</TH><TH>Plánované datum</TH>
        </TRow>
      </thead>
      <tbody>
        {schedules.map(s => {
          const currentKm = Number(s.motorcycles?.mileage) || 0
          const nextAt = (s.last_service_km || 0) + (s.interval_km || 0)
          const remaining = nextAt - currentKm
          const overdue = s.interval_km && remaining <= 0
          return (
            <TRow key={s.id}>
              <TD bold>{s.motorcycles?.model || '—'}</TD>
              <TD mono>{s.motorcycles?.spz || '—'}</TD>
              <TD>{s.description || TYPE_LABELS[s.schedule_type] || s.schedule_type || '—'}</TD>
              <TD>{s.interval_km ? `${s.interval_km.toLocaleString('cs-CZ')} km` : ''}{s.interval_days ? ` / ${s.interval_days} dní` : ''}</TD>
              <TD style={overdue ? { color: '#dc2626', fontWeight: 700 } : undefined}>
                {s.interval_km ? (overdue ? `⚠ ${Math.abs(remaining).toLocaleString('cs-CZ')} km po` : `${remaining.toLocaleString('cs-CZ')} km`) : '—'}
                {!currentKm && s.interval_km ? ' (km nenastaven)' : ''}
              </TD>
              <TD>{s.next_due ? new Date(s.next_due).toLocaleDateString('cs-CZ') : '—'}</TD>
            </TRow>
          )
        })}
        {schedules.length === 0 && <TRow><TD>Žádné servisní plány. Nastavte intervaly v detailu motorky.</TD></TRow>}
      </tbody>
    </Table>
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
