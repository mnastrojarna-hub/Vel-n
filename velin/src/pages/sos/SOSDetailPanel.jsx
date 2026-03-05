import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import SOSTimeline from './SOSTimeline'

const TYPE_LABELS = { accident: 'Nehoda', theft: 'Krádež', breakdown: 'Porucha' }

export default function SOSDetailPanel({ incident, onClose, onRefresh }) {
  const [booking, setBooking] = useState(null)
  const [customer, setCustomer] = useState(null)
  const [moto, setMoto] = useState(null)
  const [message, setMessage] = useState('')
  const [sending, setSending] = useState(false)
  const [msgSent, setMsgSent] = useState(false)

  useEffect(() => {
    if (!incident) return
    loadDetails()
  }, [incident?.id])

  async function loadDetails() {
    if (incident.booking_id || incident.bookings?.id) {
      const bookingId = incident.booking_id || incident.bookings?.id
      const { data: b } = await supabase.from('bookings')
        .select('*, motorcycles(*, branches(name)), profiles(*)')
        .eq('id', bookingId).single()
      if (b) {
        setBooking(b)
        setCustomer(b.profiles)
        setMoto(b.motorcycles)
      }
    }
    if (incident.user_id && !customer) {
      const { data: p } = await supabase.from('profiles').select('*').eq('id', incident.user_id).single()
      if (p) setCustomer(p)
    }
  }

  async function sendMessage() {
    if (!message.trim() || !customer?.id) return
    setSending(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('messages').insert({
        sender_id: user?.id,
        recipient_id: customer.id,
        content: message,
        type: 'sos_response',
        metadata: { incident_id: incident.id },
      })
      await supabase.from('sos_timeline').insert({
        incident_id: incident.id,
        action: `Zpráva odeslána zákazníkovi: "${message.slice(0, 50)}${message.length > 50 ? '...' : ''}"`,
        performed_by: user?.email || 'Admin',
      })
      setMessage('')
      setMsgSent(true)
      setTimeout(() => setMsgSent(false), 3000)
    } catch {}
    setSending(false)
  }

  if (!incident) return null

  return (
    <div className="space-y-4">
      {/* Incident header */}
      <Card>
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <span className="text-2xl">{incident.type === 'accident' ? '🚨' : incident.type === 'theft' ? '🔒' : '🔧'}</span>
            <h3 className="font-extrabold text-base" style={{ color: '#0f1a14' }}>
              {TYPE_LABELS[incident.type] || 'Incident'}
            </h3>
          </div>
          <button onClick={onClose} className="text-xs font-bold cursor-pointer"
            style={{ color: '#8aab99', background: 'none', border: 'none' }}>✕ Zavřít</button>
        </div>
        <div className="grid grid-cols-2 gap-2 text-xs">
          <InfoRow label="ID" value={incident.id?.slice(0, 8)} mono />
          <InfoRow label="Nahlášeno" value={incident.created_at ? new Date(incident.created_at).toLocaleString('cs-CZ') : '—'} />
          {incident.description && <div className="col-span-2"><InfoRow label="Popis" value={incident.description} /></div>}
        </div>
      </Card>

      {/* Customer detail */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Zákazník</h4>
        <div className="grid grid-cols-2 gap-2 text-xs">
          <InfoRow label="Jméno" value={customer?.full_name || incident.profiles?.full_name} />
          <InfoRow label="Telefon" value={customer?.phone || incident.profiles?.phone} />
          <InfoRow label="Email" value={customer?.email} />
          <InfoRow label="Město" value={customer?.city} />
          {customer?.driving_license && <InfoRow label="ŘP" value={customer.driving_license} />}
          {customer?.preferred_language && <InfoRow label="Jazyk" value={customer.preferred_language} />}
        </div>
      </Card>

      {/* Motorcycle detail */}
      {moto && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Motorka</h4>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <InfoRow label="Model" value={moto.model} />
            <InfoRow label="SPZ" value={moto.spz} mono />
            <InfoRow label="VIN" value={moto.vin} mono />
            <InfoRow label="Pobočka" value={moto.branches?.name} />
            <InfoRow label="Kategorie" value={moto.category} />
            <InfoRow label="Km" value={moto.mileage?.toLocaleString('cs-CZ')} />
          </div>
        </Card>
      )}

      {/* Booking detail */}
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

      {/* Location map */}
      {incident.latitude && incident.longitude && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Poloha zákazníka</h4>
          <div className="rounded-lg overflow-hidden" style={{ height: 200 }}>
            <iframe
              title="Poloha"
              width="100%" height="200" frameBorder="0" style={{ border: 0 }}
              src={`https://www.openstreetmap.org/export/embed.html?bbox=${incident.longitude - 0.01},${incident.latitude - 0.01},${incident.longitude + 0.01},${incident.latitude + 0.01}&layer=mapnik&marker=${incident.latitude},${incident.longitude}`}
            />
          </div>
          <div className="flex items-center gap-2 mt-2">
            <span className="text-[10px] font-mono" style={{ color: '#8aab99' }}>
              {incident.latitude.toFixed(6)}, {incident.longitude.toFixed(6)}
            </span>
            <a href={`https://www.google.com/maps?q=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-[10px] font-bold underline" style={{ color: '#1a8a18' }}>
              Google Maps ↗
            </a>
          </div>
        </Card>
      )}

      {/* Send message */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Odeslat zprávu zákazníkovi</h4>
        <textarea
          value={message} onChange={e => setMessage(e.target.value)}
          rows={3} placeholder="Napište zprávu zákazníkovi..."
          className="w-full rounded-btn text-sm outline-none mb-3"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
        />
        <div className="flex items-center gap-3">
          <Button green onClick={sendMessage} disabled={sending || !message.trim()}>
            {sending ? 'Odesílám...' : 'Odeslat zprávu'}
          </Button>
          {msgSent && <span className="text-xs font-bold" style={{ color: '#1a8a18' }}>Zpráva odeslána!</span>}
        </div>
      </Card>

      {/* Incident photos */}
      {incident.photos && incident.photos.length > 0 && (
        <Card>
          <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Fotografie</h4>
          <div className="flex flex-wrap gap-2">
            {incident.photos.map((photo, i) => (
              <a key={i} href={photo} target="_blank" rel="noopener noreferrer">
                <img src={photo} alt={`SOS foto ${i + 1}`} className="rounded-lg object-cover" style={{ width: 100, height: 100 }} />
              </a>
            ))}
          </div>
        </Card>
      )}

      {/* Timeline */}
      <Card>
        <h4 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Timeline incidentu</h4>
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
