import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import SOSTimeline from './SOSTimeline'
import { DAMAGE_LABELS, InfoRow, TYPE_LABELS, TYPE_ICONS } from './SOSDetailConstants'

export function DamageCard({ incident, isAccident }) {
  if (!isAccident || !incident.damage_severity) return null
  return (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Poškození motorky</h4>
          <span className="inline-block rounded-btn text-sm font-extrabold" style={{
            padding: '5px 12px', background: '#1a2e22', color: '#74FB71',
          }}>
            {DAMAGE_LABELS[incident.damage_severity] || incident.damage_severity}
          </span>
          {incident.damage_description && (
            <div className="text-sm rounded-lg mt-2" style={{ padding: '6px 10px', background: '#f8fcfa', color: '#1a2e22' }}>
              {incident.damage_description}
            </div>
          )}
        </Card>
  )
}

export function NearestServiceCard({ incident, saveField }) {
  if (!['breakdown_minor', 'breakdown_major', 'defect_question'].includes(incident.type)) return null
  return (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Nejbližší servis</h4>
          <div className="grid grid-cols-1 gap-2">
            <input type="text" placeholder="Název servisu" defaultValue={incident.nearest_service_name || ''}
              onBlur={e => saveField('nearest_service_name', e.target.value)}
              className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            <input type="text" placeholder="Adresa servisu" defaultValue={incident.nearest_service_address || ''}
              onBlur={e => saveField('nearest_service_address', e.target.value)}
              className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            <input type="text" placeholder="Telefon servisu" defaultValue={incident.nearest_service_phone || ''}
              onBlur={e => saveField('nearest_service_phone', e.target.value)}
              className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          </div>
        </Card>
  )
}

export function CustomerCard({ customer, incident }) {
  return (
      <Card>
        <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Zákazník</h4>
        <div className="grid grid-cols-2 gap-2 text-sm">
          <InfoRow label="Jméno" value={customer?.full_name || incident.profiles?.full_name} />
          <InfoRow label="Telefon" value={customer?.phone || incident.profiles?.phone} />
          <InfoRow label="Email" value={customer?.email || incident.profiles?.email} />
          <InfoRow label="Město" value={customer?.city} />
        </div>
      </Card>
  )
}

export function MotoCard({ moto }) {
  if (!moto) return null
  return (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Motorka</h4>
          <div className="grid grid-cols-2 gap-2 text-sm">
            <InfoRow label="Model" value={moto.model} />
            <InfoRow label="SPZ" value={moto.spz} mono />
            <InfoRow label="VIN" value={moto.vin} mono />
            <InfoRow label="Pobočka" value={moto.branches?.name} />
            <InfoRow label="Km" value={moto.mileage?.toLocaleString('cs-CZ')} />
          </div>
        </Card>
  )
}

export function BookingCard({ booking }) {
  if (!booking) return null
  return (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Rezervace</h4>
          <div className="grid grid-cols-2 gap-2 text-sm">
            <InfoRow label="ID" value={booking.id?.slice(-8).toUpperCase()} mono />
            <InfoRow label="Stav" value={booking.status} />
            <InfoRow label="Od" value={booking.start_date} />
            <InfoRow label="Do" value={booking.end_date} />
            <InfoRow label="Částka" value={booking.total_price ? `${Number(booking.total_price).toLocaleString('cs-CZ')} Kč` : '—'} />
          </div>
        </Card>
  )
}

export function MapCard({ incident }) {
  if (!incident.latitude || !incident.longitude) return null
  return (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Poloha zákazníka</h4>
          {incident.address && (
            <div className="text-sm font-bold mb-2" style={{ color: '#0f1a14' }}>{incident.address}</div>
          )}
          <div className="rounded-lg overflow-hidden" style={{ height: 200 }}>
            <iframe title="Poloha" width="100%" height="200" frameBorder="0" style={{ border: 0 }}
              src={`https://www.openstreetmap.org/export/embed.html?bbox=${incident.longitude - 0.01},${incident.latitude - 0.01},${incident.longitude + 0.01},${incident.latitude + 0.01}&layer=mapnik&marker=${incident.latitude},${incident.longitude}`}
            />
          </div>
          <div className="flex items-center gap-2 mt-2">
            <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>
              {Number(incident.latitude).toFixed(6)}, {Number(incident.longitude).toFixed(6)}
            </span>
            <a href={`https://www.google.com/maps?q=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-sm font-bold underline" style={{ color: '#1a8a18' }}>
              Google Maps
            </a>
            <a href={`https://mapy.cz/zakladni?q=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-sm font-bold underline" style={{ color: '#2563eb' }}>
              Mapy.cz
            </a>
            <a href={`https://www.google.com/maps/dir/?api=1&destination=${incident.latitude},${incident.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="text-sm font-bold underline" style={{ color: '#b45309' }}>
              Navigovat
            </a>
          </div>
        </Card>
  )
}

export function AdminNotesCard({ adminNotes, setAdminNotes, saveField }) {
  return (
      <Card>
        <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Poznámky admina</h4>
        <textarea value={adminNotes} onChange={e => setAdminNotes(e.target.value)}
          rows={3} placeholder="Interní poznámky (zákazník je nevidí)…"
          className="w-full rounded-btn text-sm outline-none"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
          onBlur={() => saveField('admin_notes', adminNotes)}
        />
      </Card>
  )
}

export function ResolutionCard({ incident, resolution, setResolution, saveField }) {
  if (!['resolved', 'closed'].includes(incident.status)) return null
  return (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Řešení incidentu</h4>
          <textarea value={resolution} onChange={e => setResolution(e.target.value)}
            rows={3} placeholder="Jak byl incident vyřešen…"
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
            onBlur={() => saveField('resolution', resolution)}
          />
          {incident.resolved_at && (
            <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>
              Vyřešeno: {new Date(incident.resolved_at).toLocaleString('cs-CZ')}
            </div>
          )}
        </Card>
  )
}

export function MessageCard({ incident, message, setMessage, sending, msgSent, sendMessage }) {
  return (
      <Card>
        <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Odeslat zprávu zákazníkovi</h4>
        {['accident_minor', 'breakdown_minor', 'defect_question', 'location_share', 'other'].includes(incident.type) && (
          <div className="rounded-lg text-sm font-semibold mb-3" style={{ padding: '8px 12px', background: '#f0fdf4', color: '#1a8a18', border: '1px solid #86efac' }}>
            Automatická zpráva odeslána: &quot;Děkujeme za nahlášení, šťastnou cestu!&quot; — další zprávu odesílejte jen pokud je potřeba.
          </div>
        )}
        <textarea value={message} onChange={e => setMessage(e.target.value)}
          rows={3} placeholder="Napište zprávu zákazníkovi…"
          className="w-full rounded-btn text-sm outline-none mb-3"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
        />
        <div className="flex items-center gap-3">
          <Button green onClick={sendMessage} disabled={sending || !message.trim()}>
            {sending ? 'Odesílám…' : 'Odeslat'}
          </Button>
          {msgSent && <span className="text-sm font-bold" style={{ color: '#1a8a18' }}>Odesláno!</span>}
        </div>
      </Card>
  )
}

export function PhotosCard({ incident, isPhotoOnly, relatedIncidents, showLinkPhotos, setShowLinkPhotos, linkingPhotos, linkPhotosToIncident }) {
  if (!incident.photos || incident.photos.length === 0) return null
  return (
        <Card>
          <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>
            Fotografie ({incident.photos.length})
          </h4>
          {isPhotoOnly && (
            <div className="rounded-lg text-sm font-bold mb-3" style={{
              padding: '8px 12px', background: '#eff6ff', color: '#2563eb', border: '1px solid #93c5fd',
            }}>
              📷 Informativní fotodokumentace — zákazník odeslal fotky bez nahlášení konkrétního incidentu.
              {incident.booking_id && ' Můžete je přiřadit k jinému incidentu u této rezervace.'}
            </div>
          )}
          <div className="flex flex-wrap gap-2">
            {incident.photos.map((photo, i) => (
              <a key={i} href={photo} target="_blank" rel="noopener noreferrer">
                <img src={photo} alt={`Foto ${i + 1}`} className="rounded-lg object-cover" style={{ width: 100, height: 100 }} />
              </a>
            ))}
          </div>
          {/* Přiřadit fotky k jinému incidentu */}
          {isPhotoOnly && incident.booking_id && relatedIncidents.length > 0 && (
            <div className="mt-3">
              {!showLinkPhotos ? (
                <button onClick={() => setShowLinkPhotos(true)}
                  className="rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none"
                  style={{ padding: '8px 16px', background: '#2563eb', color: '#fff' }}>
                  Přiřadit fotky k incidentu u této rezervace
                </button>
              ) : (
                <div>
                  <div className="text-sm font-extrabold mb-2" style={{ color: '#1a2e22' }}>
                    Vyberte incident ({relatedIncidents.length}):
                  </div>
                  <div className="space-y-2" style={{ maxHeight: 200, overflowY: 'auto' }}>
                    {relatedIncidents.map(ri => (
                      <div key={ri.id} className="flex items-center justify-between rounded-lg cursor-pointer"
                        style={{ padding: '8px 12px', background: '#f8fcfa', border: '1px solid #d4e8e0' }}
                        onClick={() => !linkingPhotos && linkPhotosToIncident(ri.id)}>
                        <div>
                          <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>
                            {TYPE_ICONS[ri.type] || '⚠️'} {ri.title || TYPE_LABELS[ri.type] || ri.type}
                          </div>
                          <div className="text-sm" style={{ color: '#1a2e22' }}>
                            #{ri.id?.slice(0, 8)} · {ri.status} · {ri.created_at ? new Date(ri.created_at).toLocaleString('cs-CZ') : ''}
                            {ri.photos?.length ? ` · ${ri.photos.length} fotek` : ''}
                          </div>
                        </div>
                        <span className="text-sm font-extrabold" style={{ color: '#2563eb' }}>
                          {linkingPhotos ? '⏳' : 'Přiřadit →'}
                        </span>
                      </div>
                    ))}
                  </div>
                  <button onClick={() => setShowLinkPhotos(false)}
                    className="mt-2 rounded-btn text-sm font-extrabold cursor-pointer border-none"
                    style={{ padding: '6px 12px', background: '#f1faf7', color: '#1a2e22' }}>
                    Zrušit
                  </button>
                </div>
              )}
            </div>
          )}
        </Card>
  )
}

export function TimelineCard({ incident }) {
  return (
    <Card>
      <h4 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Timeline</h4>
      <SOSTimeline incidentId={incident.id} />
    </Card>
  )
}
