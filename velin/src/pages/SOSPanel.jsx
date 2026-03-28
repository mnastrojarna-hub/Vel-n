import { useState, useEffect, useRef } from 'react'
import { useLocation } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import SOSDetailPanel from './sos/SOSDetailPanel'
import { IncidentCard, SOSMap } from './SOSIncidentCard'
import { TYPE_LABELS, SEVERITY_MAP, STATUS_COLORS, LIGHT_AUTO_ACK, TYPE_FILTERS, SUB_FILTERS } from './SOSConstants'

// Re-export constants for backwards compatibility (SOSDetailPanel imports from here)
export { TYPE_LABELS, TYPE_ICONS, SEVERITY_MAP, STATUS_COLORS } from './SOSConstants'

export default function SOSPanel() {
  const location = useLocation()
  const [incidents, setIncidents] = useState([])
  const [loading, setLoading] = useState(true)
  const [selectedIncident, setSelectedIncident] = useState(null)
  const [notifyEnabled, setNotifyEnabled] = useState(false)
  const [filter, setFilter] = useState('active')
  const [severityFilter, setSeverityFilter] = useState('all_sev')
  const [subFilter, setSubFilter] = useState('all')
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
