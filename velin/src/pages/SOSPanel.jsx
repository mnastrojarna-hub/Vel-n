import { useState, useEffect } from 'react'
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
  other: 'Jiný problém',
  // Zpětná kompatibilita
  accident: 'Nehoda',
  breakdown: 'Porucha',
}

export const TYPE_ICONS = {
  theft: '🔒',
  accident_minor: '⚠️',
  accident_major: '🚨',
  breakdown_minor: '🔧',
  breakdown_major: '🛑',
  defect_question: '❓',
  other: '📞',
  accident: '🚨',
  breakdown: '🔧',
}

export const SEVERITY_MAP = {
  critical: { label: 'Kritické', bg: '#7f1d1d', color: '#fff', border: '#dc2626' },
  high: { label: 'Vysoká', bg: '#fee2e2', color: '#dc2626', border: '#dc2626' },
  medium: { label: 'Střední', bg: '#fef3c7', color: '#b45309', border: '#f59e0b' },
  low: { label: 'Nízká', bg: '#f1faf7', color: '#4a6357', border: '#d4e8e0' },
}

export const STATUS_COLORS = {
  reported: { bg: '#fee2e2', color: '#dc2626', label: 'Nový' },
  acknowledged: { bg: '#fef3c7', color: '#b45309', label: 'Potvrzeno' },
  in_progress: { bg: '#dbeafe', color: '#2563eb', label: 'Řeší se' },
  resolved: { bg: '#dcfce7', color: '#1a8a18', label: 'Vyřešeno' },
  closed: { bg: '#f3f4f6', color: '#6b7280', label: 'Uzavřeno' },
}

const DECISION_LABELS = {
  replacement_moto: 'Chce náhradní motorku',
  end_ride: 'Ukončuje jízdu',
  continue: 'Pokračuje',
  waiting: 'Čeká na rozhodnutí',
}

export default function SOSPanel() {
  const [incidents, setIncidents] = useState([])
  const [loading, setLoading] = useState(true)
  const [selectedIncident, setSelectedIncident] = useState(null)
  const [notifyEnabled, setNotifyEnabled] = useState(false)
  const [filter, setFilter] = useState('active')
  const [severityFilter, setSeverityFilter] = useState('all_sev')

  useEffect(() => {
    load()
    const channel = supabase.channel('sos-realtime')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'sos_incidents' }, (payload) => {
        load()
        if (notifyEnabled && 'Notification' in window && Notification.permission === 'granted') {
          const n = payload.new
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
        // Aktualizuj selected incident pokud se změnil
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

  async function load() {
    setLoading(true)
    try {
      const { data } = await debugAction('load_active_incidents', 'SOSPanel', () =>
        supabase
          .from('sos_incidents')
          .select('*, profiles(full_name, phone, email), bookings(id, moto_id, start_date, end_date, status, motorcycles(model, spz, branch_id, branches(name)))')
          .in('status', ['reported', 'acknowledged', 'in_progress'])
          .order('created_at', { ascending: false })
      )
      const { data: resolved } = await debugAction('load_resolved_incidents', 'SOSPanel', () =>
        supabase
          .from('sos_incidents')
          .select('*, profiles(full_name, phone, email), bookings(id, moto_id, start_date, end_date, status, motorcycles(model, spz, branch_id, branches(name)))')
          .in('status', ['resolved', 'closed'])
          .order('created_at', { ascending: false })
          .limit(10)
      )
      setIncidents([...(data || []), ...(resolved || [])])
    } catch {}
    setLoading(false)
  }

  async function updateStatus(id, newStatus) {
    await debugAction('updateStatus', 'SOSPanel', async () => {
      const updates = { status: newStatus }
      if (newStatus === 'resolved') {
        const { data: { user } } = await supabase.auth.getUser()
        updates.resolved_at = new Date().toISOString()
        updates.resolved_by = user?.id
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

  const LIGHT_TYPES = ['breakdown_minor', 'defect_question', 'other']
  const HEAVY_TYPES = ['theft', 'accident_minor', 'accident_major', 'breakdown_major', 'accident', 'breakdown']

  const filterBySeverity = (list) => {
    if (severityFilter === 'light') return list.filter(i => LIGHT_TYPES.includes(i.type))
    if (severityFilter === 'heavy') return list.filter(i => HEAVY_TYPES.includes(i.type))
    return list
  }

  const baseList = filter === 'active' ? active : filter === 'resolved' ? resolved : incidents
  const displayed = filterBySeverity(baseList)

  return (
    <div className="flex gap-5" style={{ minHeight: 'calc(100vh - 100px)' }}>
      {/* Left: incident list */}
      <div className={selectedIncident ? 'w-1/2' : 'w-full'} style={{ transition: 'width .2s' }}>
        <div className="flex items-center gap-3 mb-4 flex-wrap">
          <div className="flex items-center gap-2">
            <span className="text-2xl">🚨</span>
            <span className="text-xl font-black" style={{ color: active.length > 0 ? '#dc2626' : '#1a8a18' }}>
              {active.length}
            </span>
            <span className="text-sm font-bold" style={{ color: '#4a6357' }}>aktivních</span>
          </div>

          {critical.length > 0 && (
            <span className="text-[10px] font-extrabold uppercase tracking-wide px-3 py-1 rounded-btn animate-pulse"
              style={{ background: '#7f1d1d', color: '#fff' }}>
              {critical.length} kritických!
            </span>
          )}

          <div className="flex items-center gap-1">
            {[
              { key: 'light', label: 'Lehké závady' },
              { key: 'heavy', label: 'Těžké závady' },
              { key: 'all_sev', label: 'Vše' },
            ].map(f => (
              <button key={f.key} onClick={() => setSeverityFilter(f.key)}
                className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer border-none"
                style={{
                  padding: '5px 12px',
                  background: severityFilter === f.key ? (f.key === 'heavy' ? '#7f1d1d' : '#1a2e22') : '#f1faf7',
                  color: severityFilter === f.key ? (f.key === 'heavy' ? '#fff' : '#74FB71') : '#4a6357',
                }}>
                {f.label}
              </button>
            ))}
          </div>

          <div className="flex items-center gap-1 ml-auto">
            {[
              { key: 'active', label: 'Aktivní' },
              { key: 'resolved', label: 'Vyřešené' },
              { key: 'all', label: 'Vše' },
            ].map(f => (
              <button key={f.key} onClick={() => setFilter(f.key)}
                className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer border-none"
                style={{
                  padding: '5px 12px',
                  background: filter === f.key ? '#1a2e22' : '#f1faf7',
                  color: filter === f.key ? '#74FB71' : '#4a6357',
                }}>
                {f.label}
              </button>
            ))}
          </div>

          <div>
            {!notifyEnabled ? (
              <Button onClick={enableNotifications} style={{ background: '#fef3c7', color: '#92400e', fontSize: 11 }}>
                Zapnout notifikace
              </Button>
            ) : (
              <span className="text-[10px] font-bold px-3 py-1 rounded-btn" style={{ background: '#dcfce7', color: '#1a8a18' }}>
                Notifikace aktivní
              </span>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 gap-4 mb-6">
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
  )
}

function IncidentCard({ incident: inc, selected, onSelect, onUpdateStatus, onAddTimeline }) {
  const sc = STATUS_COLORS[inc.status] || STATUS_COLORS.reported
  const sev = SEVERITY_MAP[inc.severity] || SEVERITY_MAP.medium
  const moto = inc.bookings?.motorcycles
  const typeLabel = TYPE_LABELS[inc.type] || inc.type || 'Incident'
  const typeIcon = TYPE_ICONS[inc.type] || '⚠️'
  const displayTitle = inc.title || typeLabel
  const isActive = !['resolved', 'closed'].includes(inc.status)

  return (
    <div onClick={onSelect} className="cursor-pointer" style={{
      border: selected ? '2px solid #74FB71' : `2px solid ${isActive ? (sev.border || '#d4e8e0') : 'transparent'}`,
      borderRadius: 16, transition: 'border-color .15s',
    }}>
      <Card>
        <div className="flex items-start gap-3">
          <div className="text-2xl">{typeIcon}</div>
          <div className="flex-1 min-w-0">
            {/* Nadpis */}
            <div className="flex items-center gap-2 mb-1 flex-wrap">
              <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>
                {displayTitle}
              </span>
              <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                style={{ padding: '2px 7px', background: sev.bg, color: sev.color }}>
                {sev.label}
              </span>
              <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                style={{ padding: '2px 7px', background: sc.bg, color: sc.color }}>
                {sc.label}
              </span>
            </div>

            {inc.title && (
              <div className="text-[10px] font-bold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>
                {typeLabel}
              </div>
            )}

            {/* Popis */}
            {inc.description && (
              <div className="text-xs mb-2 rounded-lg" style={{
                padding: '6px 10px', background: '#f8fcfa', color: '#4a6357',
                borderLeft: '3px solid #d4e8e0', lineHeight: 1.5,
              }}>
                {inc.description.length > 150 ? inc.description.slice(0, 150) + '…' : inc.description}
              </div>
            )}

            {/* Rozhodnutí zákazníka */}
            {inc.customer_decision && (
              <div className="text-xs font-bold mb-2 rounded-lg" style={{
                padding: '4px 10px', display: 'inline-block',
                background: inc.customer_decision === 'replacement_moto' ? '#dbeafe' :
                  inc.customer_decision === 'end_ride' ? '#fee2e2' : '#fef3c7',
                color: inc.customer_decision === 'replacement_moto' ? '#2563eb' :
                  inc.customer_decision === 'end_ride' ? '#dc2626' : '#b45309',
              }}>
                {DECISION_LABELS[inc.customer_decision] || inc.customer_decision}
                {inc.customer_fault === true && ' (zavinil zákazník — platí)'}
                {inc.customer_fault === false && ' (cizí zavinění)'}
              </div>
            )}

            {/* Pojízdnost */}
            {inc.moto_rideable !== null && inc.moto_rideable !== undefined && (
              <div className="text-[10px] font-bold mb-1" style={{
                color: inc.moto_rideable ? '#1a8a18' : '#dc2626',
              }}>
                Motorka: {inc.moto_rideable ? 'pojízdná' : 'NEPOJÍZDNÁ'}
              </div>
            )}

            {/* Info grid */}
            <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs mt-1">
              <div>
                <span style={{ color: '#8aab99' }}>Zákazník: </span>
                <b style={{ color: '#0f1a14' }}>{inc.profiles?.full_name || '—'}</b>
              </div>
              <div>
                <span style={{ color: '#8aab99' }}>Telefon: </span>
                <b style={{ color: '#0f1a14' }}>{inc.contact_phone || inc.profiles?.phone || '—'}</b>
              </div>
              <div>
                <span style={{ color: '#8aab99' }}>Motorka: </span>
                <b style={{ color: '#0f1a14' }}>{moto?.model || '—'} {moto?.spz ? `(${moto.spz})` : ''}</b>
              </div>
              <div>
                <span style={{ color: '#8aab99' }}>Nahlášeno: </span>
                <b style={{ color: '#0f1a14' }}>{formatTimeAgo(inc.created_at)}</b>
              </div>
              {(inc.address || (inc.latitude && inc.longitude)) && (
                <div className="col-span-2">
                  <span style={{ color: '#8aab99' }}>Poloha: </span>
                  <b style={{ color: '#1a8a18' }}>{inc.address || `${Number(inc.latitude).toFixed(4)}, ${Number(inc.longitude).toFixed(4)}`}</b>
                  {inc.latitude && inc.longitude && (
                    <a href={`https://www.google.com/maps?q=${inc.latitude},${inc.longitude}`}
                      target="_blank" rel="noopener noreferrer"
                      onClick={e => e.stopPropagation()}
                      className="inline-flex items-center gap-1 ml-2 text-[10px] font-bold px-2 py-0.5 rounded-btn"
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
                    className="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-btn"
                    style={{ background: '#f1faf7', color: '#4a6357', textDecoration: 'none' }}>
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
                  <span className="flex items-center justify-center rounded text-[10px] font-bold"
                    style={{ width: 36, height: 36, background: '#f1faf7', color: '#8aab99' }}>
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

                {/* Akce specifické dle typu */}
                {(inc.type === 'accident_major' || inc.type === 'breakdown_major') && (
                  <>
                    <ActionBtn label="Odeslat odtah" color="#4a6357" bg="#f1faf7" onClick={() => onAddTimeline(inc.id, 'Odtahová služba kontaktována a odeslána na místo')} />
                    <ActionBtn label="Přistavit náhr. moto" color="#2563eb" bg="#dbeafe" onClick={() => onAddTimeline(inc.id, 'Náhradní motorka připravena k přistavení')} />
                  </>
                )}
                {(inc.type === 'breakdown_minor' || inc.type === 'defect_question') && (
                  <ActionBtn label="Navigovat na servis" color="#4a6357" bg="#f1faf7" onClick={() => onAddTimeline(inc.id, 'Zákazník navigován na nejbližší servis')} />
                )}
                {inc.type === 'theft' && (
                  <ActionBtn label="Policie kontaktována" color="#dc2626" bg="#fee2e2" onClick={() => onAddTimeline(inc.id, 'Policie ČR kontaktována, číslo případu zaznamenáno')} />
                )}
                {(inc.type === 'accident_major' || inc.type === 'accident_minor') && (
                  <ActionBtn label="Kontaktovat pojišťovnu" color="#4a6357" bg="#f1faf7" onClick={() => onAddTimeline(inc.id, 'Pojišťovna kontaktována, hlášena škodná událost')} />
                )}

                <ActionBtn label="Zákazník kontaktován" color="#4a6357" bg="#f1faf7" onClick={() => onAddTimeline(inc.id, 'Zákazník telefonicky kontaktován')} />
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
    <button onClick={onClick} className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer"
      style={{ padding: '5px 12px', background: bg, color, border: 'none' }}>
      {label}
    </button>
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
