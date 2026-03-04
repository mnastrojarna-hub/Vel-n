import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import SOSTimeline from './sos/SOSTimeline'

const TYPE_LABELS = { accident: 'Nehoda', theft: 'Krádež', breakdown: 'Porucha' }
const TYPE_ICONS = { accident: '🚨', theft: '🔒', breakdown: '🔧' }
const STATUS_COLORS = {
  reported: { bg: '#fee2e2', color: '#dc2626', label: 'Nový' },
  acknowledged: { bg: '#fef3c7', color: '#b45309', label: 'Potvrzeno' },
  resolved: { bg: '#dcfce7', color: '#1a8a18', label: 'Vyřešeno' },
}

export default function SOSPanel() {
  const [incidents, setIncidents] = useState([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState(null)

  useEffect(() => {
    load()
    // Real-time subscription
    const channel = supabase.channel('sos-realtime')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'sos_incidents',
      }, () => {
        load()
      })
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'sos_incidents',
      }, () => {
        load()
      })
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [])

  async function load() {
    setLoading(true)
    const { data } = await supabase
      .from('sos_incidents')
      .select('*, profiles(full_name, phone), bookings(id, moto_id, motorcycles(model, spz))')
      .in('status', ['reported', 'acknowledged'])
      .order('created_at', { ascending: false })

    // Also load resolved recent ones
    const { data: resolved } = await supabase
      .from('sos_incidents')
      .select('*, profiles(full_name, phone), bookings(id, moto_id, motorcycles(model, spz))')
      .eq('status', 'resolved')
      .order('created_at', { ascending: false })
      .limit(5)

    setIncidents([...(data || []), ...(resolved || [])])
    setLoading(false)
  }

  async function updateStatus(id, newStatus) {
    await supabase.from('sos_incidents').update({ status: newStatus }).eq('id', id)
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: id,
      action: `Stav změněn na: ${STATUS_COLORS[newStatus]?.label || newStatus}`,
      performed_by: user?.email || 'Admin',
    })
    await supabase.from('admin_audit_log').insert({
      admin_id: user?.id,
      action: 'sos_status_changed',
      details: { incident_id: id, new_status: newStatus },
    })
    load()
  }

  async function addTimelineEntry(id, action) {
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: id,
      action,
      performed_by: user?.email || 'Admin',
    })
  }

  if (loading && incidents.length === 0) {
    return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  }

  const active = incidents.filter(i => i.status !== 'resolved')
  const resolved = incidents.filter(i => i.status === 'resolved')

  return (
    <div>
      {/* Active count */}
      <div className="flex items-center gap-3 mb-5">
        <div className="flex items-center gap-2">
          <span className="text-2xl">🚨</span>
          <span className="text-xl font-black" style={{ color: active.length > 0 ? '#dc2626' : '#1a8a18' }}>
            {active.length}
          </span>
          <span className="text-sm font-bold" style={{ color: '#4a6357' }}>
            aktivních incidentů
          </span>
        </div>
      </div>

      {/* Active incidents */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
        {active.map(inc => (
          <IncidentCard
            key={inc.id}
            incident={inc}
            expanded={expanded === inc.id}
            onToggle={() => setExpanded(expanded === inc.id ? null : inc.id)}
            onUpdateStatus={updateStatus}
            onAddTimeline={addTimelineEntry}
          />
        ))}
      </div>

      {active.length === 0 && (
        <Card>
          <div className="text-center py-8">
            <div className="text-3xl mb-2">✅</div>
            <div className="text-sm font-bold" style={{ color: '#1a8a18' }}>Žádné aktivní incidenty</div>
          </div>
        </Card>
      )}

      {/* Resolved */}
      {resolved.length > 0 && (
        <>
          <div className="text-[10px] font-extrabold uppercase tracking-wide mb-3 mt-4" style={{ color: '#8aab99' }}>
            Nedávno vyřešené
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {resolved.map(inc => (
              <IncidentCard
                key={inc.id}
                incident={inc}
                expanded={expanded === inc.id}
                onToggle={() => setExpanded(expanded === inc.id ? null : inc.id)}
                onUpdateStatus={updateStatus}
                onAddTimeline={addTimelineEntry}
              />
            ))}
          </div>
        </>
      )}
    </div>
  )
}

function IncidentCard({ incident: inc, expanded, onToggle, onUpdateStatus, onAddTimeline }) {
  const sc = STATUS_COLORS[inc.status] || STATUS_COLORS.reported
  const moto = inc.bookings?.motorcycles

  return (
    <Card>
      <div className="flex items-start gap-3">
        <div className="text-2xl">{TYPE_ICONS[inc.type] || '⚠️'}</div>
        <div className="flex-1">
          <div className="flex items-center gap-2 mb-1">
            <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>
              {TYPE_LABELS[inc.type] || inc.type || 'Incident'}
            </span>
            <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
              style={{ padding: '3px 8px', background: sc.bg, color: sc.color }}>
              {sc.label}
            </span>
          </div>

          <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs mt-2">
            <div>
              <span style={{ color: '#8aab99' }}>Zákazník: </span>
              <b style={{ color: '#0f1a14' }}>{inc.profiles?.full_name || '—'}</b>
            </div>
            <div>
              <span style={{ color: '#8aab99' }}>Telefon: </span>
              <b style={{ color: '#0f1a14' }}>{inc.profiles?.phone || '—'}</b>
            </div>
            <div>
              <span style={{ color: '#8aab99' }}>Motorka: </span>
              <b style={{ color: '#0f1a14' }}>{moto?.model || '—'}</b>
            </div>
            <div>
              <span style={{ color: '#8aab99' }}>SPZ: </span>
              <b className="font-mono" style={{ color: '#0f1a14' }}>{moto?.spz || '—'}</b>
            </div>
            {inc.latitude && inc.longitude && (
              <div className="col-span-2">
                <span style={{ color: '#8aab99' }}>Poloha: </span>
                <a href={`https://www.google.com/maps?q=${inc.latitude},${inc.longitude}`}
                  target="_blank" rel="noopener noreferrer"
                  className="font-bold underline" style={{ color: '#1a8a18' }}>
                  Zobrazit na mapě ↗
                </a>
              </div>
            )}
            <div className="col-span-2">
              <span style={{ color: '#8aab99' }}>Nahlášeno: </span>
              <b style={{ color: '#0f1a14' }}>
                {inc.created_at ? new Date(inc.created_at).toLocaleString('cs-CZ') : '—'}
              </b>
            </div>
            {inc.description && (
              <div className="col-span-2 mt-1">
                <span style={{ color: '#8aab99' }}>Popis: </span>
                <span style={{ color: '#0f1a14' }}>{inc.description}</span>
              </div>
            )}
          </div>

          {/* Photos */}
          {inc.photos && inc.photos.length > 0 && (
            <div className="flex gap-2 mt-2">
              {inc.photos.map((photo, i) => (
                <a key={i} href={photo} target="_blank" rel="noopener noreferrer">
                  <img src={photo} alt={`SOS foto ${i + 1}`} className="rounded-lg object-cover"
                    style={{ width: 60, height: 60 }} />
                </a>
              ))}
            </div>
          )}

          {/* Actions */}
          {inc.status !== 'resolved' && (
            <div className="flex flex-wrap gap-2 mt-3">
              {inc.status === 'reported' && (
                <ActionBtn label="Potvrdit" color="#b45309" bg="#fef3c7"
                  onClick={() => onUpdateStatus(inc.id, 'acknowledged')} />
              )}
              <ActionBtn label="Odeslat odtah" color="#4a6357" bg="#f1faf7"
                onClick={() => onAddTimeline(inc.id, 'Odtahová služba odeslána')} />
              <ActionBtn label="Odeslat náhradu" color="#4a6357" bg="#f1faf7"
                onClick={() => onAddTimeline(inc.id, 'Náhradní motorka odeslána')} />
              <ActionBtn label="Uzavřít" color="#1a8a18" bg="#dcfce7"
                onClick={() => onUpdateStatus(inc.id, 'resolved')} />
            </div>
          )}

          {/* Expandable timeline */}
          <button onClick={onToggle}
            className="mt-2 text-[10px] font-bold cursor-pointer bg-transparent border-none uppercase tracking-wide"
            style={{ color: '#8aab99' }}>
            {expanded ? '▲ Skrýt timeline' : '▼ Zobrazit timeline'}
          </button>
          {expanded && <SOSTimeline incidentId={inc.id} />}
        </div>
      </div>
    </Card>
  )
}

function ActionBtn({ label, color, bg, onClick }) {
  return (
    <button onClick={onClick}
      className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer"
      style={{ padding: '5px 12px', background: bg, color, border: 'none' }}>
      {label}
    </button>
  )
}
