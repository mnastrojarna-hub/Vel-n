import Card from '../components/ui/Card'
import { TYPE_LABELS, TYPE_ICONS, SEVERITY_MAP, STATUS_COLORS } from './SOSConstants'

const DECISION_LABELS = {
  replacement_moto: 'Chce náhradní motorku',
  end_ride: 'Ukončuje jízdu',
  continue: 'Pokračuje',
  waiting: 'Čeká na rozhodnutí',
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

function IncidentCard({ incident: inc, selected, onSelect, onUpdateStatus, onAddTimeline }) {
  const sc = STATUS_COLORS[inc.status] || STATUS_COLORS.reported
  const sev = SEVERITY_MAP[inc.severity] || SEVERITY_MAP.medium
  const moto = inc.bookings?.motorcycles || inc.motorcycles
  const typeLabel = TYPE_LABELS[inc.type] || inc.type || 'Incident'
  const typeIcon = TYPE_ICONS[inc.type] || '⚠️'
  const typeCat = TYPE_CATEGORY[inc.type] || { label: 'SOS', bg: '#f3f4f6', color: '#1a2e22' }
  const isPhotoOnly = inc.type === 'other' && inc.description?.toLowerCase().includes('fotodokumentace')
  const displayTitle = isPhotoOnly ? '📷 Fotodokumentace' : (inc.title || typeLabel)
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

export { IncidentCard, SOSMap, formatTimeAgo }
