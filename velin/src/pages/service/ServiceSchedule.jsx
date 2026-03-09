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
    try {
      debugLog('ServiceSchedule', 'load')
      const { data, error } = await debugAction('maintenance_schedules.list', 'ServiceSchedule', () =>
        supabase
          .from('maintenance_schedules')
          .select('*, motorcycles(model, spz)')
          .gte('next_date', new Date().toISOString().slice(0, 10))
          .order('next_date')
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
          <TH>Motorka</TH><TH>SPZ</TH><TH>Typ</TH>
          <TH>Plánované datum</TH><TH>Stav</TH>
        </TRow>
      </thead>
      <tbody>
        {schedules.map(s => (
          <TRow key={s.id}>
            <TD bold>{s.motorcycles?.model || '—'}</TD>
            <TD mono>{s.motorcycles?.spz || '—'}</TD>
            <TD>{TYPE_LABELS[s.type] || s.type || '—'}</TD>
            <TD>{s.next_date ? new Date(s.next_date).toLocaleDateString('cs-CZ') : '—'}</TD>
            <TD><StatusBadge status={s.status || 'pending'} /></TD>
          </TRow>
        ))}
        {schedules.length === 0 && <TRow><TD>Žádné plánované servisy</TD></TRow>}
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
