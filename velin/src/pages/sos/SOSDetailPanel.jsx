import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import SOSTimeline from './SOSTimeline'
import { TYPE_LABELS, TYPE_ICONS, SEVERITY_MAP, STATUS_COLORS } from '../SOSPanel'

const DECISION_LABELS = {
  replacement_moto: 'Chce náhradní motorku',
  end_ride: 'Ukončuje jízdu',
  continue: 'Pokračuje v jízdě',
  waiting: 'Čeká na rozhodnutí',
}

const DAMAGE_LABELS = {
  none: 'Žádné poškození',
  cosmetic: 'Kosmetické (škrábance, odřeniny)',
  functional: 'Funkční (ovlivňuje provoz)',
  totaled: 'Totální škoda',
}

export default function SOSDetailPanel({ incident, onClose, onRefresh }) {
  const [booking, setBooking] = useState(null)
  const [customer, setCustomer] = useState(null)
  const [moto, setMoto] = useState(null)
  const [admins, setAdmins] = useState([])
  const [message, setMessage] = useState('')
  const [adminNotes, setAdminNotes] = useState(incident?.admin_notes || '')
  const [resolution, setResolution] = useState(incident?.resolution || '')
  const [sending, setSending] = useState(false)
  const [msgSent, setMsgSent] = useState(false)

  useEffect(() => {
    if (!incident) return
    loadDetails()
    loadAdmins()
    setAdminNotes(incident.admin_notes || '')
    setResolution(incident.resolution || '')
  }, [incident?.id])

  async function loadDetails() {
    setCustomer(null)
    setMoto(null)
    setBooking(null)
    if (incident.booking_id || incident.bookings?.id) {
      const bookingId = incident.booking_id || incident.bookings?.id
      const { data: b } = await supabase.from('bookings')
        .select('*, motorcycles(*, branches(name)), profiles(*)')
        .eq('id', bookingId).single()
      if (b) {
        setBooking(b)
        setCustomer(b.profiles)
        setMoto(b.motorcycles)
        return
      }
    }
    if (incident.moto_id) {
      const { data: m } = await supabase.from('motorcycles').select('*, branches(name)').eq('id', incident.moto_id).single()
      if (m) setMoto(m)
    }
    if (incident.user_id) {
      const { data: p } = await supabase.from('profiles').select('*').eq('id', incident.user_id).single()
      if (p) setCustomer(p)
    }
  }

  async function loadAdmins() {
    const { data } = await supabase.from('admin_users').select('id, name').eq('active', true)
    setAdmins(data || [])
  }

  async function assignAdmin(adminId) {
    await debugAction('sos.assignAdmin', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({ assigned_to: adminId || null }).eq('id', incident.id)
    , { incident_id: incident.id, admin_id: adminId })
    const { data: { user } } = await supabase.auth.getUser()
    const adminName = admins.find(a => a.id === adminId)?.name || 'admin'
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: adminId ? `Přiřazeno: ${adminName}` : 'Přiřazení odebráno',
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }

  async function updateDecision(decision) {
    await debugAction('sos.updateDecision', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({ customer_decision: decision }).eq('id', incident.id)
    , { incident_id: incident.id, decision })
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: `Rozhodnutí zákazníka: ${DECISION_LABELS[decision] || decision}`,
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }

  async function updateFault(isFault) {
    await debugAction('sos.updateFault', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({ customer_fault: isFault }).eq('id', incident.id)
    , { incident_id: incident.id, customer_fault: isFault })
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: incident.id,
      action: isFault ? 'Zavinění: zákazník (platí náklady)' : 'Zavinění: cizí (bez nákladů pro zákazníka)',
      performed_by: user?.email || 'Admin', admin_id: user?.id,
    })
    onRefresh?.()
  }

  async function saveField(field, value) {
    await debugAction('sos.saveField', 'SOSDetailPanel', () =>
      supabase.from('sos_incidents').update({ [field]: value }).eq('id', incident.id)
    , { incident_id: incident.id, field, value })
  }

  async function sendMessage() {
    if (!message.trim() || !customer?.id) return
    setSending(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()

      let { data: thread } = await supabase.from('message_threads')
        .select('id').eq('customer_id', customer.id).eq('channel', 'web')
        .in('status', ['open']).order('created_at', { ascending: false }).limit(1).single()

      if (!thread) {
        const { data: newThread } = await supabase.from('message_threads').insert({
          customer_id: customer.id, channel: 'web', status: 'open',
          subject: `SOS: ${incident.title || TYPE_LABELS[incident.type] || 'Incident'}`,
          last_message_at: new Date().toISOString(),
        }).select().single()
        thread = newThread
      }

      if (thread) {
        const msgData = {
          thread_id: thread.id, direction: 'admin', sender_name: 'Admin (SOS)',
          content: message.trim(), read_at: new Date().toISOString(),
        }
        await debugAction('sos.sendMessage', 'SOSDetailPanel', () =>
          supabase.from('messages').insert(msgData)
        , { incident_id: incident.id, customer_id: customer.id, content: message.trim() })
        await supabase.from('message_threads').update({ last_message_at: new Date().toISOString() }).eq('id', thread.id)
      }

      await supabase.from('sos_timeline').insert({
        incident_id: incident.id,
        action: `Zpráva odeslána: "${message.slice(0, 50)}${message.length > 50 ? '...' : ''}"`,
        performed_by: user?.email || 'Admin', admin_id: user?.id,
      })
      setMessage('')
      setMsgSent(true)
      setTimeout(() => setMsgSent(false), 3000)
    } catch {}
    setSending(false)
  }

  if (!incident) return null

  const sev = SEVERITY_MAP[incident.severity] || SEVERITY_MAP.medium
  const sc = STATUS_COLORS[incident.status] || STATUS_COLORS.reported
  const displayTitle = incident.title || TYPE_LABELS[incident.type] || 'Incident'
  const isActive = !['resolved', 'closed'].includes(incident.status)
  const isAccident = incident.type?.startsWith('accident')
  const isMajor = incident.type === 'accident_major' || incident.type === 'breakdown_major'

  return (
    <div className="space-y-4">
      {/* Header */}
      <Card>
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <span className="text-2xl">{TYPE_ICONS[incident.type] || '⚠️'}</span>
            <div>
              <h3 className="font-extrabold text-base" style={{ color: '#0f1a14' }}>{displayTitle}</h3>
              {incident.title && (
                <span className="text-[10px] font-bold uppercase tracking-wide" style={{ color: '#8aab99' }}>
                  {TYPE_LABELS[incident.type] || incident.type}
                </span>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
              style={{ padding: '2px 7px', background: sev.bg, color: sev.color }}>{sev.label}</span>
            <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
              style={{ padding: '2px 7px', background: sc.bg, color: sc.color }}>{sc.label}</span>
            <button onClick={onClose} className="text-xs font-bold cursor-pointer"
              style={{ color: '#8aab99', background: 'none', border: 'none' }}>✕</button>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2 text-xs">
          <InfoRow label="ID" value={incident.id?.slice(0, 8)} mono />
          <InfoRow label="Nahlášeno" value={incident.created_at ? new Date(incident.created_at).toLocaleString('cs-CZ') : '—'} />
          <InfoRow label="Kontakt" value={incident.contact_phone || customer?.phone || incident.profiles?.phone} />
          {incident.moto_rideable !== null && incident.moto_rideable !== undefined && (
            <InfoRow label="Pojízdná" value={incident.moto_rideable ? 'Ano' : 'NE — nepojízdná'} />
          )}
        </div>

        {/* Popis od zákazníka */}
        {incident.description && (
          <div className="mt-3 rounded-lg text-xs" style={{
            padding: '10px 14px', background: '#f8fcfa', color: '#4a6357',
            borderLeft: '3px solid #d4e8e0', lineHeight: 1.6,
          }}>
            <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>
              Popis od zákazníka
            </div>
            {incident.description}
          </div>
        )}

        {/* Přiřadit */}
        <div className="mt-3 flex items-center gap-2">
          <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Přiřadit:</span>
          <select value={incident.assigned_to || ''} onChange={e => assignAdmin(e.target.value)}
            className="rounded-btn text-[11px] outline-none cursor-pointer"
            style={{ padding: '4px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
            <option value="">Nepřiřazeno</option>
            {admins.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </div>
      </Card>

      {/* Rozhodnutí zákazníka (u nepojízdných) */}
      {isActive && isMajor && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>
            Rozhodnutí zákazníka
          </h4>
          <div className="flex flex-wrap gap-2 mb-3">
            {Object.entries(DECISION_LABELS).map(([key, label]) => (
              <button key={key} onClick={() => updateDecision(key)}
                className="rounded-btn text-[10px] font-extrabold tracking-wide cursor-pointer border-none"
                style={{
                  padding: '6px 14px',
                  background: incident.customer_decision === key ? '#1a2e22' : '#f1faf7',
                  color: incident.customer_decision === key ? '#74FB71' : '#4a6357',
                }}>
                {label}
              </button>
            ))}
          </div>

          {/* Zavinění (u nehod) */}
          {isAccident && (
            <div className="mt-3">
              <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Zavinění: </span>
              <div className="flex gap-2 mt-1">
                <button onClick={() => updateFault(true)}
                  className="rounded-btn text-[10px] font-extrabold tracking-wide cursor-pointer border-none"
                  style={{
                    padding: '5px 12px',
                    background: incident.customer_fault === true ? '#dc2626' : '#f1faf7',
                    color: incident.customer_fault === true ? '#fff' : '#4a6357',
                  }}>
                  Zákazník (platí)
                </button>
                <button onClick={() => updateFault(false)}
                  className="rounded-btn text-[10px] font-extrabold tracking-wide cursor-pointer border-none"
                  style={{
                    padding: '5px 12px',
                    background: incident.customer_fault === false ? '#1a8a18' : '#f1faf7',
                    color: incident.customer_fault === false ? '#fff' : '#4a6357',
                  }}>
                  Cizí zavinění
                </button>
              </div>
            </div>
          )}
        </Card>
      )}

      {/* Poškození motorky */}
      {isAccident && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Poškození motorky</h4>
          <div className="flex flex-wrap gap-2 mb-3">
            {Object.entries(DAMAGE_LABELS).map(([key, label]) => (
              <button key={key} onClick={() => saveField('damage_severity', key)}
                className="rounded-btn text-[10px] font-extrabold tracking-wide cursor-pointer border-none"
                style={{
                  padding: '5px 12px',
                  background: incident.damage_severity === key ? '#1a2e22' : '#f1faf7',
                  color: incident.damage_severity === key ? '#74FB71' : '#4a6357',
                }}>
                {label}
              </button>
            ))}
          </div>
          {incident.damage_description && (
            <div className="text-xs rounded-lg" style={{ padding: '6px 10px', background: '#f8fcfa', color: '#4a6357' }}>
              {incident.damage_description}
            </div>
          )}
        </Card>
      )}

      {/* Nejbližší servis (pro poruchy a dotazy) */}
      {(incident.type === 'breakdown_minor' || incident.type === 'defect_question') && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Nejbližší servis</h4>
          <div className="grid grid-cols-1 gap-2">
            <input type="text" placeholder="Název servisu" defaultValue={incident.nearest_service_name || ''}
              onBlur={e => saveField('nearest_service_name', e.target.value)}
              className="rounded-btn text-xs outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            <input type="text" placeholder="Adresa servisu" defaultValue={incident.nearest_service_address || ''}
              onBlur={e => saveField('nearest_service_address', e.target.value)}
              className="rounded-btn text-xs outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            <input type="text" placeholder="Telefon servisu" defaultValue={incident.nearest_service_phone || ''}
              onBlur={e => saveField('nearest_service_phone', e.target.value)}
              className="rounded-btn text-xs outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          </div>
        </Card>
      )}

      {/* Zákazník */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Zákazník</h4>
        <div className="grid grid-cols-2 gap-2 text-xs">
          <InfoRow label="Jméno" value={customer?.full_name || incident.profiles?.full_name} />
          <InfoRow label="Telefon" value={customer?.phone || incident.profiles?.phone} />
          <InfoRow label="Email" value={customer?.email || incident.profiles?.email} />
          <InfoRow label="Město" value={customer?.city} />
        </div>
      </Card>

      {/* Motorka */}
      {moto && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Motorka</h4>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <InfoRow label="Model" value={moto.model} />
            <InfoRow label="SPZ" value={moto.spz} mono />
            <InfoRow label="VIN" value={moto.vin} mono />
            <InfoRow label="Pobočka" value={moto.branches?.name} />
            <InfoRow label="Km" value={moto.mileage?.toLocaleString('cs-CZ')} />
          </div>
        </Card>
      )}

      {/* Rezervace */}
      {booking && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Rezervace</h4>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <InfoRow label="ID" value={booking.id?.slice(0, 8)} mono />
            <InfoRow label="Stav" value={booking.status} />
            <InfoRow label="Od" value={booking.start_date} />
            <InfoRow label="Do" value={booking.end_date} />
            <InfoRow label="Částka" value={booking.total_price ? `${Number(booking.total_price).toLocaleString('cs-CZ')} Kč` : '—'} />
          </div>
        </Card>
      )}

      {/* Mapa */}
      {incident.latitude && incident.longitude && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Poloha zákazníka</h4>
          {incident.address && (
            <div className="text-xs font-bold mb-2" style={{ color: '#0f1a14' }}>{incident.address}</div>
          )}
          <div className="rounded-lg overflow-hidden" style={{ height: 200 }}>
            <iframe title="Poloha" width="100%" height="200" frameBorder="0" style={{ border: 0 }}
              src={`https://www.openstreetmap.org/export/embed.html?bbox=${incident.longitude - 0.01},${incident.latitude - 0.01},${incident.longitude + 0.01},${incident.latitude + 0.01}&layer=mapnik&marker=${incident.latitude},${incident.longitude}`}
            />
          </div>
          <div className="flex items-center gap-2 mt-2">
            <span className="text-[10px] font-mono" style={{ color: '#8aab99' }}>
              {Number(incident.latitude).toFixed(6)}, {Number(incident.longitude).toFixed(6)}
            </span>
            <a href={`https://www.google.com/maps?q=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-[10px] font-bold underline" style={{ color: '#1a8a18' }}>
              Google Maps
            </a>
            <a href={`https://mapy.cz/zakladni?q=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-[10px] font-bold underline" style={{ color: '#2563eb' }}>
              Mapy.cz
            </a>
            <a href={`https://www.google.com/maps/dir/?api=1&destination=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-[10px] font-bold underline" style={{ color: '#b45309' }}>
              Navigovat
            </a>
          </div>
        </Card>
      )}

      {/* Poznámky admina */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Poznámky admina</h4>
        <textarea value={adminNotes} onChange={e => setAdminNotes(e.target.value)}
          rows={3} placeholder="Interní poznámky (zákazník je nevidí)…"
          className="w-full rounded-btn text-sm outline-none"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
          onBlur={() => saveField('admin_notes', adminNotes)}
        />
      </Card>

      {/* Řešení */}
      {['resolved', 'closed'].includes(incident.status) && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Řešení incidentu</h4>
          <textarea value={resolution} onChange={e => setResolution(e.target.value)}
            rows={3} placeholder="Jak byl incident vyřešen…"
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
            onBlur={() => saveField('resolution', resolution)}
          />
          {incident.resolved_at && (
            <div className="text-[10px] mt-1" style={{ color: '#8aab99' }}>
              Vyřešeno: {new Date(incident.resolved_at).toLocaleString('cs-CZ')}
            </div>
          )}
        </Card>
      )}

      {/* Odeslat zprávu */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Odeslat zprávu zákazníkovi</h4>
        <textarea value={message} onChange={e => setMessage(e.target.value)}
          rows={3} placeholder="Napište zprávu zákazníkovi…"
          className="w-full rounded-btn text-sm outline-none mb-3"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
        />
        <div className="flex items-center gap-3">
          <Button green onClick={sendMessage} disabled={sending || !message.trim()}>
            {sending ? 'Odesílám…' : 'Odeslat'}
          </Button>
          {msgSent && <span className="text-xs font-bold" style={{ color: '#1a8a18' }}>Odesláno!</span>}
        </div>
      </Card>

      {/* Fotky */}
      {incident.photos && incident.photos.length > 0 && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Fotografie</h4>
          <div className="flex flex-wrap gap-2">
            {incident.photos.map((photo, i) => (
              <a key={i} href={photo} target="_blank" rel="noopener noreferrer">
                <img src={photo} alt={`Foto ${i + 1}`} className="rounded-lg object-cover" style={{ width: 100, height: 100 }} />
              </a>
            ))}
          </div>
        </Card>
      )}

      {/* Timeline */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Timeline</h4>
        <SOSTimeline incidentId={incident.id} />
      </Card>
    </div>
  )
}

function InfoRow({ label, value, mono }) {
  return (
    <div className="flex items-center gap-2 mb-1">
      <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99', minWidth: 55 }}>{label}</span>
      <span className={`text-sm font-medium ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value || '—'}</span>
    </div>
  )
}
