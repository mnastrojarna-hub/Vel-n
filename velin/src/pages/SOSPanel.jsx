import { useState, useEffect, useRef } from 'react'
import { useLocation } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import SOSDetailPanel from './sos/SOSDetailPanel'

export const TYPE_LABELS = {
  theft: 'Krádež motorky',
  accident_minor: 'Lehká nehoda (pojízdná)',
  accident_major: 'Závažná nehoda (nepojízdná)',
  breakdown_minor: 'Lehká porucha (pojízdná)',
  breakdown_major: 'Těžká porucha (nepojízdná)',
  defect_question: 'Dotaz na závadu',
  location_share: 'Sdílení polohy',
  other: 'Jiný problém',
  // Zpětná kompatibilita
  accident: 'Nehoda',
  breakdown: 'Porucha',
}

// Kategorie pro výrazný badge v kartě
const TYPE_CATEGORY = {
  theft:           { label: 'KRÁDEŽ',  bg: '#7f1d1d', color: '#fff' },
  accident_minor:  { label: 'NEHODA',  bg: '#fee2e2', color: '#dc2626' },
  accident_major:  { label: 'NEHODA',  bg: '#dc2626', color: '#fff' },
  accident:        { label: 'NEHODA',  bg: '#dc2626', color: '#fff' },
  breakdown_minor: { label: 'PORUCHA', bg: '#fef3c7', color: '#b45309' },
  breakdown_major: { label: 'PORUCHA', bg: '#b45309', color: '#fff' },
  breakdown:       { label: 'PORUCHA', bg: '#b45309', color: '#fff' },
  defect_question: { label: 'ZÁVADA',  bg: '#f1faf7', color: '#1a2e22' },
  location_share:  { label: 'POLOHA',  bg: '#dbeafe', color: '#2563eb' },
  other:           { label: 'JINÉ',    bg: '#f3f4f6', color: '#1a2e22' },
}

export const TYPE_ICONS = {
  theft: '🔒',
  accident_minor: '⚠️',
  accident_major: '🚨',
  breakdown_minor: '🔧',
  breakdown_major: '🛑',
  defect_question: '❓',
  location_share: '📍',
  other: '📞',
  accident: '🚨',
  breakdown: '🔧',
}

export const SEVERITY_MAP = {
  critical: { label: 'Kritické', bg: '#7f1d1d', color: '#fff', border: '#dc2626' },
  high: { label: 'Vysoká', bg: '#fee2e2', color: '#dc2626', border: '#dc2626' },
  medium: { label: 'Střední', bg: '#fef3c7', color: '#b45309', border: '#f59e0b' },
  low: { label: 'Nízká', bg: '#f1faf7', color: '#1a2e22', border: '#d4e8e0' },
}

export const STATUS_COLORS = {
  reported: { bg: '#fee2e2', color: '#dc2626', label: 'Nový' },
  acknowledged: { bg: '#fef3c7', color: '#b45309', label: 'Potvrzeno' },
  in_progress: { bg: '#dbeafe', color: '#2563eb', label: 'Řeší se' },
  resolved: { bg: '#dcfce7', color: '#1a8a18', label: 'Vyřešeno' },
  closed: { bg: '#f3f4f6', color: '#1a2e22', label: 'Uzavřeno' },
}

const DECISION_LABELS = {
  replacement_moto: 'Chce náhradní motorku',
  end_ride: 'Ukončuje jízdu',
  continue: 'Pokračuje',
  waiting: 'Čeká na rozhodnutí',
}

// Lehké typy — automatické potvrzení velínem
const LIGHT_AUTO_ACK = ['breakdown_minor', 'defect_question', 'location_share', 'other']

export default function SOSPanel() {
  const location = useLocation()
  const [incidents, setIncidents] = useState([])
  const [loading, setLoading] = useState(true)
  const [selectedIncident, setSelectedIncident] = useState(null)
  const [notifyEnabled, setNotifyEnabled] = useState(false)
  const [filter, setFilter] = useState(() => {
    try { const s = localStorage.getItem('velin_sos_filters'); if (s) { const p = JSON.parse(s); return p.filter || 'active' } } catch {} return 'active'
  })
  const [severityFilter, setSeverityFilter] = useState(() => {
    try { const s = localStorage.getItem('velin_sos_filters'); if (s) { const p = JSON.parse(s); return p.severityFilter || 'all_sev' } } catch {} return 'all_sev'
  })
  const [subFilter, setSubFilter] = useState(() => {
    try { const s = localStorage.getItem('velin_sos_filters'); if (s) { const p = JSON.parse(s); return p.subFilter || 'all' } } catch {} return 'all'
  })
  useEffect(() => { localStorage.setItem('velin_sos_filters', JSON.stringify({ filter, severityFilter, subFilter })) }, [filter, severityFilter, subFilter])
  const openIncidentHandled = useRef(null)

  // Auto-acknowledge light faults
  async function autoAcknowledge(incidentId, type) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('sos_incidents').update({ status: 'acknowledged' }).eq('id', incidentId)
      await supabase.from('sos_timeline').insert({
        incident_id: incidentId,
        action: `Automaticky potvrzeno (lehký incident: ${TYPE_LABELS[type] || type})`,
        performed_by: 'System (auto-ack)', admin_id: user?.id,
      })
    } catch (e) { console.error('[SOSPanel] autoAck failed:', e) }
  }

  useEffect(() => {
    load()
    const channel = supabase.channel('sos-realtime')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'sos_incidents' }, (payload) => {
        load()
        const n = payload.new
        // Auto-confirm light faults
        if (n && LIGHT_AUTO_ACK.includes(n.type) && n.status === 'reported') {
          autoAcknowledge(n.id, n.type)
        }
        if (notifyEnabled && 'Notification' in window && Notification.permission === 'granted') {
          const title = n?.title || TYPE_LABELS[n?.type] || 'Nový incident'
          const sev = SEVERITY_MAP[n?.severity]
          new Notification(`SOS: ${title}`, {
            body: `${sev?.label || ''} — ${n?.description?.slice(0, 80) || 'Bez popisu'}`,
            tag: 'sos-' + n?.id,
          })
        }
      })
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'sos_incidents' }, (payload) => {
        load()
        if (selectedIncident && payload.new?.id === selectedIncident.id) {
          setSelectedIncident(prev => ({ ...prev, ...payload.new }))
        }
      })
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [notifyEnabled, selectedIncident?.id])

  async function enableNotifications() {
    if (!('Notification' in window)) return
    const permission = await Notification.requestPermission()
    if (permission === 'granted') {
      setNotifyEnabled(true)
      new Notification('SOS notifikace zapnuty', { body: 'Budete informováni o nových incidentech.' })
    }
  }

  const SOS_SELECT = '*, profiles(full_name, phone, email), bookings(id, moto_id, start_date, end_date, status, motorcycles(model, spz, branch_id, branches(name)))'
  const SOS_SELECT_MOTO = '*, profiles(full_name, phone, email), motorcycles!sos_incidents_moto_id_fkey(model, spz, vin, branch_id, mileage, branches(name)), bookings(id, moto_id, start_date, end_date, status, motorcycles(model, spz, branch_id, branches(name)))'

  async function load() {
    setLoading(true)
    try {
      // Try with moto_id FK first, fallback without it if column doesn't exist
      let data = null, resolved = null
      try {
        const r1 = await supabase.from('sos_incidents').select(SOS_SELECT_MOTO)
          .in('status', ['reported', 'acknowledged', 'in_progress']).order('created_at', { ascending: false })
        const r2 = await supabase.from('sos_incidents').select(SOS_SELECT_MOTO)
          .in('status', ['resolved', 'closed']).order('created_at', { ascending: false }).limit(10)
        if (r1.error) throw r1.error
        data = r1.data
        resolved = r2.data
      } catch (fkErr) {
        console.warn('[SOSPanel] moto FK query failed, falling back:', fkErr?.message)
        const r1 = await supabase.from('sos_incidents').select(SOS_SELECT)
          .in('status', ['reported', 'acknowledged', 'in_progress']).order('created_at', { ascending: false })
        const r2 = await supabase.from('sos_incidents').select(SOS_SELECT)
          .in('status', ['resolved', 'closed']).order('created_at', { ascending: false }).limit(10)
        if (r1.error) console.error('[SOSPanel] fallback query ALSO failed:', r1.error)
        if (r2.error) console.error('[SOSPanel] fallback resolved query failed:', r2.error)
        data = r1.data
        resolved = r2.data
      }
      setIncidents([...(data || []), ...(resolved || [])])
    } catch (e) {
      console.error('[SOSPanel] load failed:', e)
    }
    setLoading(false)
  }

  // Auto-open incident from navigation state (e.g. from BookingDetail)
  useEffect(() => {
    const openId = location.state?.openIncidentId
    if (!openId || !incidents.length || openIncidentHandled.current === openId) return
    const found = incidents.find(i => i.id === openId)
    if (found) {
      setSelectedIncident(found)
      setFilter('all')
      openIncidentHandled.current = openId
    }
  }, [incidents, location.state])

  async function updateStatus(id, newStatus) {
    // SAFETY: Prevent closing incidents with pending replacements
    const inc = incidents.find(i => i.id === id)
    if (newStatus === 'resolved' && inc) {
      const pendingRepl = ['selecting', 'pending_payment', 'admin_review', 'approved', 'dispatched']
      if (pendingRepl.includes(inc.replacement_status)) {
        if (!window.confirm(`⚠️ POZOR: Tento incident má nedokončenou objednávku náhradní motorky!\n\nStav objednávky: ${inc.replacement_status}\n\nOpravdu chcete označit incident jako vyřešený?`)) {
          return
        }
      }
      if (!window.confirm('Označit incident jako VYŘEŠENÝ?\n\nZákazník nebude moci do incidentu dále přidávat informace.')) {
        return
      }
    }
    await debugAction('updateStatus', 'SOSPanel', async () => {
      const updates = { status: newStatus }
      if (newStatus === 'resolved') {
        const { data: { user } } = await supabase.auth.getUser()
        updates.resolved_at = new Date().toISOString()
        updates.resolved_by = user?.id

        // === SOS RESOLVE: finalize booking swap ===
        // 1. If replacement exists but swap wasn't done yet, do it now
        const rd = inc?.replacement_data || {}
        if (rd.replacement_moto_id && !rd.replacement_booking_id) {
          try {
            const swapResult = await supabase.rpc('sos_swap_bookings', {
              p_incident_id: id,
              p_replacement_moto_id: rd.replacement_moto_id,
              p_replacement_model: rd.replacement_model || null,
              p_delivery_fee: rd.delivery_fee || 0,
              p_daily_price: rd.daily_price || 0,
              p_is_free: !rd.customer_fault,
            })
            const sr = typeof swapResult.data === 'string' ? JSON.parse(swapResult.data) : swapResult.data
            if (sr?.success) {
              rd.replacement_booking_id = sr.replacement_booking_id
              rd.original_booking_id = sr.original_booking_id
              updates.replacement_data = { ...rd, approved_by_admin: true }
            }
          } catch (e) { console.error('[SOS] swap on resolve:', e) }
        }

        // 2. Mark original booking as completed (immediately, not date-based)
        const origBookingId = rd.original_booking_id || inc?.original_booking_id
        if (origBookingId) {
          await supabase.from('bookings').update({
            status: 'completed',
            ended_by_sos: true,
          }).eq('id', origBookingId)
        }

        // 3. Ensure replacement booking is active + paid
        const replBookingId = rd.replacement_booking_id || inc?.replacement_booking_id
        if (replBookingId) {
          await supabase.from('bookings').update({
            status: 'active',
            payment_status: 'paid',
          }).eq('id', replBookingId)
        }

        // 4. If no replacement but incident has a booking, complete it with SOS flag
        if (!replBookingId && inc?.booking_id) {
          await supabase.from('bookings').update({
            status: 'completed',
            ended_by_sos: true,
            sos_incident_id: id,
          }).eq('id', inc.booking_id)
        }

        // 5. Send confirmation message to customer
        if (inc?.user_id) {
          const replModel = rd.replacement_model
          const msgText = replModel
            ? `Váš SOS incident byl vyřešen. Náhradní motorka: ${replModel}. Původní rezervace ukončena, nová aktivní.`
            : 'Váš SOS incident byl vyřešen. Děkujeme za trpělivost.'
          await supabase.from('admin_messages').insert({
            user_id: inc.user_id,
            title: 'SOS vyřešeno',
            message: msgText,
            type: 'sos_response',
          })
        }
      }
      await supabase.from('sos_incidents').update(updates).eq('id', id)
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('sos_timeline').insert({
        incident_id: id,
        action: `Stav změněn na: ${STATUS_COLORS[newStatus]?.label || newStatus}`,
        performed_by: user?.email || 'Admin',
        admin_id: user?.id,
      })
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'sos_status_changed',
        details: { incident_id: id, new_status: newStatus },
      })
    }, { id, newStatus })
    load()
  }

  async function addTimelineEntry(id, action) {
    await debugAction('addTimelineEntry', 'SOSPanel', async () => {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('sos_timeline').insert({
        incident_id: id, action, performed_by: user?.email || 'Admin', admin_id: user?.id,
      })
    }, { id, action })
  }

  if (loading && incidents.length === 0) {
    return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  }

  const active = incidents.filter(i => !['resolved', 'closed'].includes(i.status))
  const resolved = incidents.filter(i => ['resolved', 'closed'].includes(i.status))
  const critical = active.filter(i => i.severity === 'critical' || i.severity === 'high')
  const pendingApproval = active.filter(i => i.replacement_status === 'admin_review')
  const pendingPayment = active.filter(i => i.replacement_status === 'pending_payment')

  const LIGHT_TYPES = ['breakdown_minor', 'defect_question', 'location_share', 'other']
  const HEAVY_TYPES = ['theft', 'accident_minor', 'accident_major', 'breakdown_major', 'accident', 'breakdown']

  const TYPE_FILTERS = [
    { key: 'all_type', label: 'Vše', icon: '' },
    { key: 'nehody', label: 'Nehody', icon: '💥', types: ['accident_minor','accident_major','accident'] },
    { key: 'poruchy', label: 'Poruchy', icon: '🔧', types: ['breakdown_minor','breakdown_major','breakdown'] },
    { key: 'kradeze', label: 'Krádeže', icon: '🔒', types: ['theft'] },
    { key: 'ostatni', label: 'Ostatní', icon: '📞', types: ['defect_question','location_share','other'] },
  ]

  // Sub-filtry pro nehody a poruchy
  const SUB_FILTERS = {
    nehody: [
      { key: 'all', label: 'Všechny nehody' },
      { key: 'lehke', label: 'Lehké', types: ['accident_minor'] },
      { key: 'tezke', label: 'Těžké', types: ['accident_major', 'accident'] },
      { key: 'zavinene', label: 'Zaviněné', filterFn: i => i.customer_fault === true },
      { key: 'nezavinene', label: 'Bez zavinění', filterFn: i => i.customer_fault === false },
    ],
    poruchy: [
      { key: 'all', label: 'Všechny poruchy' },
      { key: 'lehke', label: 'Lehké', types: ['breakdown_minor'] },
      { key: 'tezke', label: 'Těžké', types: ['breakdown_major', 'breakdown'] },
    ],
  }

  const filterByType = (list) => {
    if (severityFilter === 'all_type' || severityFilter === 'all_sev') return list
    const tf = TYPE_FILTERS.find(t => t.key === severityFilter)
    if (!tf?.types) return list
    let filtered = list.filter(i => tf.types.includes(i.type))
    // Apply sub-filter
    if (subFilter !== 'all') {
      const subs = SUB_FILTERS[severityFilter]
      if (subs) {
        const sf = subs.find(s => s.key === subFilter)
        if (sf?.types) filtered = filtered.filter(i => sf.types.includes(i.type))
        if (sf?.filterFn) filtered = filtered.filter(sf.filterFn)
      }
    }
    return filtered
  }

  // Priority sort: admin_review first, then pending_payment, then by severity, then by time
  const prioritySort = (a, b) => {
    const prio = (i) => {
      if (i.replacement_status === 'admin_review') return 0
      if (i.replacement_status === 'pending_payment') return 1
      if (i.severity === 'critical') return 2
      if (i.severity === 'high') return 3
      if (i.status === 'reported') return 4
      return 5
    }
    const pa = prio(a), pb = prio(b)
    if (pa !== pb) return pa - pb
    return new Date(b.created_at) - new Date(a.created_at)
  }

  const baseList = filter === 'active' ? active : filter === 'resolved' ? resolved : incidents
  const displayed = filterByType(baseList).sort(prioritySort)

  return (
    <>
    <div className="flex gap-5" style={{ minHeight: 'calc(100vh - 100px)' }}>
      {/* Left: incident list */}
      <div className={selectedIncident ? 'w-1/2' : 'w-full'} style={{ transition: 'width .2s' }}>

        {/* === DASHBOARD HEADER === */}
        <div className="mb-4">
          {/* Counters row */}
          <div className="flex items-center gap-3 mb-3 flex-wrap">
            <div className="flex items-center gap-2">
              <span className="text-2xl">🚨</span>
              <span className="text-xl font-black" style={{ color: active.length > 0 ? '#dc2626' : '#1a8a18' }}>
                {active.length}
              </span>
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>aktivních</span>
            </div>

            {critical.length > 0 && (
              <span className="text-sm font-extrabold uppercase tracking-wide px-3 py-1 rounded-btn animate-pulse"
                style={{ background: '#7f1d1d', color: '#fff' }}>
                {critical.length} kritických!
              </span>
            )}

            {pendingApproval.length > 0 && (
              <span className="text-sm font-extrabold uppercase tracking-wide px-3 py-1 rounded-btn animate-pulse"
                style={{ background: '#dc2626', color: '#fff' }}>
                {pendingApproval.length}x SCHVÁLIT MOTORKU
              </span>
            )}

            {pendingPayment.length > 0 && (
              <span className="text-sm font-extrabold uppercase tracking-wide px-3 py-1 rounded-btn"
                style={{ background: '#fef3c7', color: '#b45309' }}>
                {pendingPayment.length}x čeká na platbu
              </span>
            )}

            <div className="ml-auto">
              {!notifyEnabled ? (
                <Button onClick={enableNotifications} style={{ background: '#fef3c7', color: '#92400e', fontSize: 13 }}>
                  Zapnout notifikace
                </Button>
              ) : (
                <span className="text-sm font-bold px-3 py-1 rounded-btn" style={{ background: '#dcfce7', color: '#1a8a18' }}>
                  Notifikace ON
                </span>
              )}
            </div>
          </div>

          {/* Filters row */}
          <div className="flex items-center gap-1 flex-wrap">
            {/* Status filter */}
            {[
              { key: 'active', label: 'Aktivní', count: active.length },
              { key: 'resolved', label: 'Vyřešené', count: resolved.length },
              { key: 'all', label: 'Vše', count: incidents.length },
            ].map(f => (
              <button key={f.key} onClick={() => { setFilter(f.key); setSelectedIncident(null) }}
                className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
                style={{
                  padding: '5px 12px',
                  background: filter === f.key ? '#1a2e22' : '#f1faf7',
                  color: filter === f.key ? '#74FB71' : '#1a2e22',
                }}>
                {f.label} ({f.count})
              </button>
            ))}

            <span style={{ width: 1, height: 20, background: '#d4e8e0', margin: '0 4px' }} />

            {/* Type filter */}
            {TYPE_FILTERS.map(f => {
              const count = f.types
                ? baseList.filter(i => f.types.includes(i.type)).length
                : baseList.length
              return (
                <button key={f.key} onClick={() => { setSeverityFilter(f.key); setSubFilter('all') }}
                  className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none"
                  style={{
                    padding: '5px 10px',
                    background: severityFilter === f.key ? '#1a2e22' : '#f1faf7',
                    color: severityFilter === f.key ? '#74FB71' : '#1a2e22',
                  }}>
                  {f.icon} {f.label} {count > 0 ? `(${count})` : ''}
                </button>
              )
            })}
          </div>

          {/* Sub-filtry pro nehody/poruchy */}
          {SUB_FILTERS[severityFilter] && (
            <div className="flex items-center gap-1 mt-2 flex-wrap">
              <span className="text-[9px] font-bold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>Filtr:</span>
              {SUB_FILTERS[severityFilter].map(sf => {
                const sfCount = sf.types
                  ? baseList.filter(i => sf.types.includes(i.type)).length
                  : sf.filterFn
                    ? baseList.filter(i => TYPE_FILTERS.find(t => t.key === severityFilter)?.types?.includes(i.type)).filter(sf.filterFn).length
                    : baseList.filter(i => TYPE_FILTERS.find(t => t.key === severityFilter)?.types?.includes(i.type)).length
                return (
                  <button key={sf.key} onClick={() => setSubFilter(sf.key)}
                    className="rounded-btn text-[9px] font-extrabold uppercase tracking-wide cursor-pointer border-none"
                    style={{
                      padding: '3px 8px',
                      background: subFilter === sf.key ? '#1a2e22' : '#f8fcfa',
                      color: subFilter === sf.key ? '#fff' : '#1a2e22',
                      border: '1px solid #d4e8e0',
                    }}>
                    {sf.label} {sfCount > 0 ? `(${sfCount})` : ''}
                  </button>
                )
              })}
            </div>
          )}
        </div>

        {/* === SOS MAPA — zobrazí se ve filtru Ostatní nebo když jsou incidenty s GPS === */}
        {severityFilter === 'ostatni' && <SOSMap incidents={displayed} onSelect={setSelectedIncident} />}

        {/* === INCIDENT LIST === */}
        <div className="grid grid-cols-1 gap-3 mb-6">
          {displayed.map(inc => (
            <IncidentCard key={inc.id} incident={inc}
              selected={selectedIncident?.id === inc.id}
              onSelect={() => setSelectedIncident(inc)}
              onUpdateStatus={updateStatus}
              onAddTimeline={addTimelineEntry}
            />
          ))}
        </div>

        {displayed.length === 0 && (
          <Card>
            <div className="text-center py-8">
              <div className="text-3xl mb-2">{filter === 'active' ? '✅' : '📋'}</div>
              <div className="text-sm font-bold" style={{ color: '#1a8a18' }}>
                {filter === 'active' ? 'Žádné aktivní incidenty' : 'Žádné incidenty'}
              </div>
            </div>
          </Card>
        )}
      </div>

      {selectedIncident && (
        <div className="w-1/2 overflow-y-auto" style={{ maxHeight: 'calc(100vh - 100px)' }}>
          <SOSDetailPanel
            incident={selectedIncident}
            onClose={() => setSelectedIncident(null)}
            onRefresh={load}
          />
        </div>
      )}
    </div>
    </>
  )
}

function IncidentCard({ incident: inc, selected, onSelect, onUpdateStatus, onAddTimeline }) {
  const sc = STATUS_COLORS[inc.status] || STATUS_COLORS.reported
  const sev = SEVERITY_MAP[inc.severity] || SEVERITY_MAP.medium
  const moto = inc.bookings?.motorcycles || inc.motorcycles
  const typeLabel = TYPE_LABELS[inc.type] || inc.type || 'Incident'
  const typeIcon = TYPE_ICONS[inc.type] || '⚠️'
  const typeCat = TYPE_CATEGORY[inc.type] || { label: 'SOS', bg: '#f3f4f6', color: '#1a2e22' }
  const displayTitle = inc.title || typeLabel
  const isActive = !['resolved', 'closed'].includes(inc.status)
  const isAccident = inc.type?.startsWith('accident')
  const isHeavy = ['theft', 'accident_major', 'breakdown_major'].includes(inc.type)

  return (
    <div onClick={onSelect} className="cursor-pointer" style={{
      border: selected ? '2px solid #74FB71' : `2px solid ${isActive ? (sev.border || '#d4e8e0') : 'transparent'}`,
      borderRadius: 16, transition: 'border-color .15s',
    }}>
      <Card>
        <div className="flex items-start gap-3">
          <div className="text-2xl">{typeIcon}</div>
          <div className="flex-1 min-w-0">
            {/* Nadpis + kategorie */}
            <div className="flex items-center gap-2 mb-1 flex-wrap">
              <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wider uppercase"
                style={{ padding: '3px 10px', background: typeCat.bg, color: typeCat.color, letterSpacing: '0.08em' }}>
                {typeCat.label}
              </span>
              <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>
                {displayTitle}
              </span>
              {isHeavy && (
                <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                  style={{ padding: '2px 7px', background: sev.bg, color: sev.color }}>
                  {sev.label}
                </span>
              )}
              <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                style={{ padding: '2px 7px', background: sc.bg, color: sc.color }}>
                {sc.label}
              </span>
            </div>

            {inc.title && (
              <div className="text-sm font-bold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                {typeLabel}
              </div>
            )}

            {/* Klíčové info: zavinění + pojízdnost — vždy viditelné u nehod/poruch */}
            {(isAccident || inc.type?.startsWith('breakdown') || inc.type === 'theft') && (
              <div className="flex flex-wrap gap-2 mb-2">
                {/* Zavinění */}
                <span className="inline-flex items-center gap-1 rounded-btn text-sm font-extrabold px-2 py-0.5" style={{
                  background: inc.customer_fault === true ? '#fee2e2' : inc.customer_fault === false ? '#dcfce7' : '#f3f4f6',
                  color: inc.customer_fault === true ? '#dc2626' : inc.customer_fault === false ? '#1a8a18' : '#9ca3af',
                }}>
                  {inc.customer_fault === true ? 'Zavinil zákazník' : inc.customer_fault === false ? 'Cizí zavinění' : 'Zavinění: nezjištěno'}
                </span>
                {/* Pojízdnost */}
                <span className="inline-flex items-center gap-1 rounded-btn text-sm font-extrabold px-2 py-0.5" style={{
                  background: inc.moto_rideable === true ? '#dcfce7' : inc.moto_rideable === false ? '#fee2e2' : '#f3f4f6',
                  color: inc.moto_rideable === true ? '#1a8a18' : inc.moto_rideable === false ? '#dc2626' : '#9ca3af',
                }}>
                  {inc.moto_rideable === true ? 'Pojízdná' : inc.moto_rideable === false ? 'NEPOJÍZDNÁ' : 'Pojízdnost: nezjištěno'}
                </span>
              </div>
            )}

            {/* Popis */}
            {inc.description && (
              <div className="text-sm mb-2 rounded-lg" style={{
                padding: '6px 10px', background: '#f8fcfa', color: '#1a2e22',
                borderLeft: `3px solid ${isHeavy ? '#dc2626' : '#d4e8e0'}`, lineHeight: 1.5,
              }}>
                {inc.description.length > 150 ? inc.description.slice(0, 150) + '…' : inc.description}
              </div>
            )}

            {/* Poznámky admina – viditelné na první pohled */}
            {inc.admin_notes && (
              <div className="text-sm mb-2 rounded-lg" style={{
                padding: '6px 10px', background: '#fffbeb', color: '#92400e',
                borderLeft: '3px solid #fbbf24', lineHeight: 1.5,
              }}>
                <span className="font-extrabold text-[9px] uppercase tracking-wide">Poznámka: </span>
                {inc.admin_notes.length > 100 ? inc.admin_notes.slice(0, 100) + '…' : inc.admin_notes}
              </div>
            )}

            {/* Rozhodnutí zákazníka */}
            {inc.customer_decision && (
              <div className="text-sm font-bold mb-2 rounded-lg" style={{
                padding: '4px 10px', display: 'inline-block',
                background: inc.customer_decision === 'replacement_moto' ? '#dbeafe' :
                  inc.customer_decision === 'end_ride' ? '#fee2e2' : '#fef3c7',
                color: inc.customer_decision === 'replacement_moto' ? '#2563eb' :
                  inc.customer_decision === 'end_ride' ? '#dc2626' : '#b45309',
              }}>
                {DECISION_LABELS[inc.customer_decision] || inc.customer_decision}
              </div>
            )}

            {/* Objednávka náhradní motorky – kompletní status */}
            {inc.replacement_status && (
              <div className="mb-2 rounded-lg" style={{
                padding: '6px 10px',
                background: inc.replacement_status === 'admin_review' ? '#fee2e2' :
                  inc.replacement_status === 'pending_payment' ? '#fef3c7' :
                  inc.replacement_status === 'approved' ? '#dcfce7' :
                  inc.replacement_status === 'dispatched' ? '#dbeafe' :
                  inc.replacement_status === 'delivered' ? '#f1faf7' :
                  inc.replacement_status === 'rejected' ? '#fee2e2' :
                  inc.replacement_status === 'paid' ? '#dbeafe' : '#f3f4f6',
                border: inc.replacement_status === 'admin_review' ? '2px solid #dc2626' :
                  inc.replacement_status === 'pending_payment' ? '2px solid #f59e0b' : 'none',
                animation: inc.replacement_status === 'admin_review' ? 'pulse 2s infinite' : 'none',
              }}>
                <div className="text-sm font-extrabold uppercase tracking-wide" style={{
                  color: inc.replacement_status === 'admin_review' ? '#dc2626' :
                    inc.replacement_status === 'pending_payment' ? '#b45309' :
                    inc.replacement_status === 'approved' ? '#1a8a18' :
                    inc.replacement_status === 'dispatched' ? '#2563eb' : '#1a2e22',
                }}>
                  {inc.replacement_status === 'admin_review' && '⚠️ ČEKÁ NA SCHVÁLENÍ'}
                  {inc.replacement_status === 'pending_payment' && '💳 ČEKÁ NA PLATBU ZÁKAZNÍKA'}
                  {inc.replacement_status === 'selecting' && '🏍️ Zákazník vybírá motorku'}
                  {inc.replacement_status === 'paid' && '💰 ZAPLACENO — čeká na schválení'}
                  {inc.replacement_status === 'approved' && '✅ Schváleno — připravit přistavení'}
                  {inc.replacement_status === 'dispatched' && '🚛 Motorka na cestě'}
                  {inc.replacement_status === 'delivered' && '📦 Doručeno'}
                  {inc.replacement_status === 'rejected' && '❌ Zamítnuto'}
                </div>
                {inc.replacement_data?.replacement_model && (
                  <div className="text-sm font-bold mt-1" style={{ color: '#1a2e22' }}>
                    {inc.replacement_data.replacement_model}
                    {inc.replacement_data.payment_amount > 0 && ` · ${Number(inc.replacement_data.payment_amount).toLocaleString('cs-CZ')} Kč`}
                    {inc.replacement_data.payment_status === 'free' && ' · zdarma'}
                    {inc.replacement_data.payment_status === 'paid' && ' · zaplaceno'}
                    {inc.replacement_data.payment_status === 'pending' && ' · nezaplaceno'}
                    {inc.replacement_data.delivery_city && ` · ${inc.replacement_data.delivery_city}`}
                  </div>
                )}
              </div>
            )}

            {/* Info grid */}
            <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm mt-1">
              <div>
                <span style={{ color: '#1a2e22' }}>Zákazník: </span>
                <b style={{ color: '#0f1a14' }}>{inc.profiles?.full_name || '—'}</b>
              </div>
              <div>
                <span style={{ color: '#1a2e22' }}>Telefon: </span>
                <b style={{ color: '#0f1a14' }}>{inc.contact_phone || inc.profiles?.phone || '—'}</b>
              </div>
              <div>
                <span style={{ color: '#1a2e22' }}>Motorka: </span>
                <b style={{ color: '#0f1a14' }}>{moto?.model || '—'} {moto?.spz ? `(${moto.spz})` : ''}</b>
              </div>
              <div>
                <span style={{ color: '#1a2e22' }}>Nahlášeno: </span>
                <b style={{ color: '#0f1a14' }}>{formatTimeAgo(inc.created_at)}</b>
              </div>
              {(inc.address || (inc.latitude && inc.longitude)) && (
                <div className="col-span-2">
                  <span style={{ color: '#1a2e22' }}>Poloha: </span>
                  <b style={{ color: '#1a8a18' }}>{inc.address || `${Number(inc.latitude).toFixed(4)}, ${Number(inc.longitude).toFixed(4)}`}</b>
                  {inc.latitude && inc.longitude && (
                    <a href={`https://www.google.com/maps?q=${inc.latitude},${inc.longitude}`}
                      target="_blank" rel="noopener noreferrer"
                      onClick={e => e.stopPropagation()}
                      className="inline-flex items-center gap-1 ml-2 text-sm font-bold px-2 py-0.5 rounded-btn"
                      style={{ background: '#dbeafe', color: '#2563eb', textDecoration: 'none' }}>
                      Otevřít mapu
                    </a>
                  )}
                </div>
              )}
              {inc.latitude && inc.longitude && !inc.address && (
                <div className="col-span-2">
                  <a href={`https://mapy.cz/zakladni?q=${inc.latitude},${inc.longitude}`}
                    target="_blank" rel="noopener noreferrer"
                    onClick={e => e.stopPropagation()}
                    className="inline-flex items-center gap-1 text-sm font-bold px-2 py-0.5 rounded-btn"
                    style={{ background: '#f1faf7', color: '#1a2e22', textDecoration: 'none' }}>
                    Mapy.cz
                  </a>
                </div>
              )}
            </div>

            {/* Fotky */}
            {inc.photos && inc.photos.length > 0 && (
              <div className="flex gap-1 mt-2">
                {inc.photos.slice(0, 3).map((photo, i) => (
                  <img key={i} src={photo} alt="" className="rounded object-cover" style={{ width: 36, height: 36 }} />
                ))}
                {inc.photos.length > 3 && (
                  <span className="flex items-center justify-center rounded text-sm font-bold"
                    style={{ width: 36, height: 36, background: '#f1faf7', color: '#1a2e22' }}>
                    +{inc.photos.length - 3}
                  </span>
                )}
              </div>
            )}

            {/* Akce podle typu incidentu */}
            {isActive && (
              <div className="flex flex-wrap gap-2 mt-3" onClick={e => e.stopPropagation()}>
                {inc.status === 'reported' && (
                  <ActionBtn label="Potvrdit příjem" color="#b45309" bg="#fef3c7" onClick={() => onUpdateStatus(inc.id, 'acknowledged')} />
                )}
                {(inc.status === 'reported' || inc.status === 'acknowledged') && (
                  <ActionBtn label="Začít řešit" color="#2563eb" bg="#dbeafe" onClick={() => onUpdateStatus(inc.id, 'in_progress')} />
                )}

                {/* Akce specifické dle typu — odkaz na detail pro workflow */}
                <ActionBtn label="Otevřít detail" color="#2563eb" bg="#dbeafe" onClick={() => onSelect()} />
                <ActionBtn label="Vyřešeno" color="#1a8a18" bg="#dcfce7" onClick={() => onUpdateStatus(inc.id, 'resolved')} />
              </div>
            )}
          </div>
        </div>
      </Card>
    </div>
  )
}

function ActionBtn({ label, color, bg, onClick }) {
  return (
    <button onClick={onClick} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
      style={{ padding: '5px 12px', background: bg, color, border: 'none' }}>
      {label}
    </button>
  )
}

function SOSMap({ incidents, onSelect }) {
  const withGps = incidents.filter(i => i.latitude && i.longitude)
  if (withGps.length === 0) return null

  // Calculate bounding box for all markers
  const lats = withGps.map(i => Number(i.latitude))
  const lngs = withGps.map(i => Number(i.longitude))
  const minLat = Math.min(...lats), maxLat = Math.max(...lats)
  const minLng = Math.min(...lngs), maxLng = Math.max(...lngs)
  const padLat = Math.max((maxLat - minLat) * 0.3, 0.005)
  const padLng = Math.max((maxLng - minLng) * 0.3, 0.005)
  const centerLat = (minLat + maxLat) / 2
  const centerLng = (minLng + maxLng) / 2

  const mapUrl = `https://www.openstreetmap.org/export/embed.html?bbox=${minLng - padLng},${minLat - padLat},${maxLng + padLng},${maxLat + padLat}&layer=mapnik&marker=${centerLat},${centerLng}`

  return (
    <Card>
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-extrabold uppercase tracking-widest" style={{ color: '#1a2e22' }}>
          Mapa SOS incidentu
        </h3>
        <span className="text-sm font-bold px-2 py-0.5 rounded-btn" style={{ background: '#dbeafe', color: '#2563eb' }}>
          {withGps.length} s GPS
        </span>
      </div>
      <div className="rounded-lg overflow-hidden relative" style={{ height: 280, background: '#e8f5e9' }}>
        <iframe title="SOS Mapa" width="100%" height="100%" style={{ border: 'none' }} src={mapUrl} />
      </div>
      <div className="flex flex-wrap gap-2 mt-3">
        {withGps.map(inc => {
          const typeIcon = TYPE_ICONS[inc.type] || '📍'
          const sc = STATUS_COLORS[inc.status] || STATUS_COLORS.reported
          return (
            <button key={inc.id} onClick={() => onSelect(inc)}
              className="rounded-btn text-sm font-bold cursor-pointer flex items-center gap-1"
              style={{ padding: '4px 10px', background: sc.bg, color: sc.color, border: 'none' }}>
              {typeIcon} {inc.profiles?.full_name || 'Zákazník'} · {Number(inc.latitude).toFixed(4)}, {Number(inc.longitude).toFixed(4)}
            </button>
          )
        })}
      </div>
    </Card>
  )
}

function formatTimeAgo(dateStr) {
  if (!dateStr) return '—'
  const diff = Date.now() - new Date(dateStr).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'právě teď'
  if (mins < 60) return `před ${mins} min`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `před ${hours} h`
  const days = Math.floor(hours / 24)
  return `před ${days} d`
}
