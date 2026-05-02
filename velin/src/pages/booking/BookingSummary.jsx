import { useNavigate } from 'react-router-dom'
import { getDisplayStatus } from '../../components/ui/StatusBadge'
import { SumRow } from './BookingUIHelpers'
import { STATUS_LABELS, CANCEL_SOURCE_LABELS, describeModification, fmtDT } from './bookingConstants'
import { mapyLinkUrl } from '../../lib/mapyCz'

// Spáruje booking_extras.name s velikostí z bookings.*_size (driver/passenger)
function matchExtraSize(name, b) {
  const n = (name || '').toLowerCase()
  const passenger = n.includes('spolujez') || n.includes('passenger')
  const pick = (driver, pas) => passenger ? (b[pas] || null) : (b[driver] || null)
  if (n.includes('boty') || n.includes('boots')) return pick('boots_size', 'passenger_boots_size')
  if (n.includes('helma') || n.includes('helmet')) return pick('helmet_size', 'passenger_helmet_size')
  if (n.includes('bunda') || n.includes('jacket')) return pick('jacket_size', 'passenger_jacket_size')
  if (n.includes('kalhoty') || n.includes('pants')) return pick('pants_size', 'passenger_pants_size')
  if (n.includes('rukavice') || n.includes('gloves')) return pick('gloves_size', 'passenger_gloves_size')
  if (n.includes('výbava') || n.includes('vybava') || n.includes('set')) {
    if (passenger) {
      const parts = [
        b.passenger_helmet_size && `helma ${b.passenger_helmet_size}`,
        b.passenger_jacket_size && `bunda/vesta ${b.passenger_jacket_size}`,
        b.passenger_pants_size && `kalhoty ${b.passenger_pants_size}`,
        b.passenger_boots_size && `boty ${b.passenger_boots_size}`,
        b.passenger_gloves_size && `rukavice ${b.passenger_gloves_size}`,
      ].filter(Boolean)
      return parts.length ? parts.join(', ') : null
    }
    const parts = [
      b.helmet_size && `helma ${b.helmet_size}`,
      b.jacket_size && `bunda ${b.jacket_size}`,
      b.pants_size && `kalhoty ${b.pants_size}`,
      b.boots_size && `boty ${b.boots_size}`,
      b.gloves_size && `rukavice ${b.gloves_size}`,
    ].filter(Boolean)
    return parts.length ? parts.join(', ') : null
  }
  return null
}

export default function BookingSummary({ booking, sosIncidents, bookingExtras, cancellation, promoUsage, voucherUsed }) {
  const navigate = useNavigate()
  const b = booking
  const _sd = new Date(b.start_date); _sd.setHours(0,0,0,0)
  const _ed = new Date(b.end_date); _ed.setHours(0,0,0,0)
  const days = Math.max(1, Math.round((_ed - _sd) / 86400000) + 1)
  const branchName = b.motorcycles?.branches?.name || '—'

  const toLD = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
  const hasModification = b.original_start_date && b.original_end_date &&
    (toLD(b.start_date) !== toLD(b.original_start_date) || toLD(b.end_date) !== toLD(b.original_end_date))
  let mod
  if (hasModification) {
    mod = describeModification(b.original_start_date, b.original_end_date, b.start_date, b.end_date)
  }
  const history = Array.isArray(b.modification_history) ? b.modification_history : []

  return (
    <div className="space-y-1">
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Základní údaje</div>
      <SumRow label="Stav" value={STATUS_LABELS[getDisplayStatus(b)] || b.status} color={getDisplayStatus(b) === 'cancelled' ? '#dc2626' : getDisplayStatus(b) === 'active' ? '#1a8a18' : getDisplayStatus(b) === 'upcoming' ? '#7c3aed' : undefined} />
      <SumRow label="ID" value={`#${b.id?.slice(-8).toUpperCase()}`} />
      <SumRow label="Motorka" value={`${b.motorcycles?.model || '—'}${b.motorcycles?.spz ? ` (${b.motorcycles.spz})` : ''}`} />
      <SumRow label="Pobočka" value={branchName} />
      <SumRow label="Zákazník" value={`${b.profiles?.full_name || '—'} (${b.profiles?.email || '—'}, ${b.profiles?.phone || '—'})`} />
      <SumRow label="Zdroj" value={`${b.booking_source === 'web' ? 'Web (motogo24.cz)' : b.booking_source === 'app' ? 'Mobilní aplikace' : '—'}${b.created_via_ai ? ' 🤖 (přes AI asistenta)' : ''}`} color={b.booking_source === 'web' ? '#2563eb' : b.booking_source === 'app' ? '#16a34a' : undefined} />

      <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Termín</div>
      <SumRow label="Začátek" value={`${new Date(b.start_date).toLocaleDateString('cs-CZ')} v ${b.pickup_time || '9:00'}`} />
      <SumRow label="Konec" value={`${new Date(b.end_date).toLocaleDateString('cs-CZ')} v 9:00`} />
      <SumRow label="Délka" value={`${days} ${days === 1 ? 'den' : days < 5 ? 'dny' : 'dní'}`} />

      {hasModification && (
        <>
          <SumRow label="Původní termín" value={`${new Date(b.original_start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.original_end_date).toLocaleDateString('cs-CZ')} (${mod.origDays} dní)`} color="#b45309" />
          <SumRow label="Úprava rozsahu" value={`${mod.type} (${mod.detail}) → nový: ${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}`} color={mod.color} />
          {history.length > 0 && history.map((h, i) => {
            const hm = describeModification(h.from_start, h.from_end, h.to_start, h.to_end)
            return <SumRow key={i} label={`Úprava #${i + 1}`} value={`${new Date(h.at).toLocaleString('cs-CZ')} — ${hm.type} (${hm.detail}) · ${h.source === 'admin' ? 'admin' : 'zákazník'}`} color={hm.color} />
          })}
        </>
      )}

      <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Vyzvednutí a vrácení</div>
      <SumAddressRow label="Přistavení" method={b.pickup_method} address={b.pickup_address} branchName={branchName} lat={b.pickup_lat} lng={b.pickup_lng} />
      <SumAddressRow label="Vrácení" method={b.return_method} address={b.return_address} branchName={branchName} lat={b.return_lat} lng={b.return_lng} />
      <SumLocationShares sosIncidents={sosIncidents} />

      {(b.helmet_size || b.jacket_size || b.pants_size || b.boots_size || b.gloves_size ||
        b.passenger_helmet_size || b.passenger_jacket_size || b.passenger_pants_size || b.passenger_boots_size || b.passenger_gloves_size) && (
        <>
          {(b.helmet_size || b.jacket_size || b.pants_size || b.boots_size || b.gloves_size) && (
            <>
              <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Výbava — řidič</div>
              <SumRow label="Helma" value={b.helmet_size ? `vel. ${b.helmet_size}` : null} />
              <SumRow label="Bunda" value={b.jacket_size ? `vel. ${b.jacket_size}` : null} />
              <SumRow label="Kalhoty" value={b.pants_size ? `vel. ${b.pants_size}` : null} />
              <SumRow label="Boty" value={b.boots_size ? `vel. ${b.boots_size}` : null} />
              <SumRow label="Rukavice" value={b.gloves_size ? `vel. ${b.gloves_size}` : null} />
            </>
          )}
          {(b.passenger_helmet_size || b.passenger_jacket_size || b.passenger_pants_size || b.passenger_boots_size || b.passenger_gloves_size) && (
            <>
              <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Výbava — spolujezdec</div>
              <SumRow label="Helma" value={b.passenger_helmet_size ? `vel. ${b.passenger_helmet_size}` : null} />
              <SumRow label="Bunda" value={b.passenger_jacket_size ? `vel. ${b.passenger_jacket_size}` : null} />
              <SumRow label="Kalhoty" value={b.passenger_pants_size ? `vel. ${b.passenger_pants_size}` : null} />
              <SumRow label="Boty" value={b.passenger_boots_size ? `vel. ${b.passenger_boots_size}` : null} />
              <SumRow label="Rukavice" value={b.passenger_gloves_size ? `vel. ${b.passenger_gloves_size}` : null} />
            </>
          )}
        </>
      )}

      {b.insurance_type && <SumRow label="Pojištění" value={b.insurance_type} />}

      {bookingExtras.length > 0 && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Příslušenství</div>
          {bookingExtras.map((ex, i) => {
            const name = ex.name || ex.extras_catalog?.name || `Extra ${i + 1}`
            const size = matchExtraSize(name, b)
            const labeled = size ? `${name} (${size})` : name
            return <SumRow key={i} label={labeled} value={`${Number(ex.unit_price || ex.extras_catalog?.price_per_day || 0).toLocaleString('cs-CZ')} Kč${ex.quantity > 1 ? ` × ${ex.quantity}` : ''}`} />
          })}
        </>
      )}

      <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Platba</div>
      <SumRow label="Celkem" value={`${Number(b.total_price || 0).toLocaleString('cs-CZ')} Kč`} />
      {b.extras_price > 0 && <SumRow label="Příslušenství" value={`${b.extras_price.toLocaleString('cs-CZ')} Kč`} />}
      {bookingExtras.length > 0 && (
        <div className="pl-4" style={{ fontSize: 12, color: '#4a5a52' }}>
          {bookingExtras.map((ex, i) => {
            const name = ex.name || ex.extras_catalog?.name || `Extra ${i + 1}`
            const size = matchExtraSize(name, b)
            const qty = Number(ex.quantity || 1)
            const price = Number(ex.unit_price || ex.extras_catalog?.price_per_day || 0)
            return (
              <div key={i} className="py-[2px] flex justify-between" style={{ borderBottom: '1px dashed #e5e7eb' }}>
                <span>— {name}{size ? ` (${size})` : ''}{qty > 1 ? ` × ${qty}` : ''}</span>
                <span style={{ color: '#1a2e22', fontWeight: 600 }}>{(price * qty).toLocaleString('cs-CZ')} Kč</span>
              </div>
            )
          })}
        </div>
      )}
      {b.delivery_fee > 0 && <SumRow label="Doručení" value={`${b.delivery_fee.toLocaleString('cs-CZ')} Kč`} />}
      {b.discount_amount > 0 && <SumRow label="Sleva" value={`-${Number(b.discount_amount).toLocaleString('cs-CZ')} Kč${b.discount_code ? ` (${b.discount_code})` : ''}`} color="#1a8a18" />}
      <SumRow label="Stav platby" value={b.payment_status === 'paid' && b.status !== 'pending' ? 'Zaplaceno' : 'Nezaplaceno'} color={b.payment_status === 'paid' && b.status !== 'pending' ? '#1a8a18' : '#dc2626'} />
      {b.payment_method && <SumRow label="Způsob platby" value={b.payment_method} />}
      {b.deposit > 0 && <SumRow label="Kauce" value={`${Number(b.deposit).toLocaleString('cs-CZ')} Kč`} />}

      {promoUsage?.length > 0 && promoUsage.map((pu, i) => (
        <SumRow key={pu.id || i} label={`Promo kód ${i + 1}`} value={`${pu.promo_codes?.code || '—'} (${pu.promo_codes?.type === 'percent' ? pu.promo_codes.value + '%' : pu.promo_codes?.value + ' Kč'}) → sleva ${pu.promo_codes?.type === 'percent' ? pu.promo_codes.value + '%' : Number(pu.discount_applied || 0).toLocaleString('cs-CZ') + ' Kč'}`} />
      ))}
      {voucherUsed && <SumRow label="Dárkový poukaz" value={`${voucherUsed.code} — ${Number(voucherUsed.amount).toLocaleString('cs-CZ')} ${voucherUsed.currency}`} />}

      {(b.mileage_start || b.mileage_end) && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Nájezd</div>
          {b.mileage_start && <SumRow label="Při převzetí" value={`${b.mileage_start} km`} />}
          {b.mileage_end && <SumRow label="Při vrácení" value={`${b.mileage_end} km`} />}
          {b.mileage_start && b.mileage_end && <SumRow label="Najeto" value={`${b.mileage_end - b.mileage_start} km`} />}
        </>
      )}

      {b.damage_report && <SumRow label="Poškození" value={b.damage_report} color="#dc2626" />}

      {(b.sos_replacement || b.ended_by_sos || sosIncidents.length > 0) && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#dc2626' }}>SOS</div>
          {b.sos_replacement && (
            <div className="flex items-center gap-2 py-1" style={{ borderBottom: '1px solid #e5e7eb', fontSize: 13 }}>
              <span className="font-extrabold" style={{ color: '#1a2e22', minWidth: 130 }}>SOS náhrada</span>
              <span style={{ color: '#1a8a18' }}>Ano</span>
              {b.replacement_for_booking_id && (
                <button onClick={() => navigate(`/rezervace/${b.replacement_for_booking_id}`)}
                  className="font-bold cursor-pointer ml-1" style={{ color: '#2563eb', background: 'none', border: 'none', fontFamily: 'monospace', fontSize: 13 }}>
                  (za #{b.replacement_for_booking_id.slice(-8).toUpperCase()})
                </button>
              )}
            </div>
          )}
          {b.ended_by_sos && (
            <div className="flex items-center gap-2 py-1 flex-wrap" style={{ borderBottom: '1px solid #e5e7eb', fontSize: 13 }}>
              <span className="font-extrabold" style={{ color: '#1a2e22', minWidth: 130 }}>Ukončeno SOS</span>
              <span style={{ color: '#dc2626' }}>Ano</span>
              {b.sos_incident_id && (
                <button onClick={() => navigate('/sos', { state: { openIncidentId: b.sos_incident_id } })}
                  className="font-bold cursor-pointer ml-1" style={{ color: '#dc2626', background: 'none', border: 'none', fontFamily: 'monospace', fontSize: 13 }}>
                  (incident #{b.sos_incident_id.slice(-8).toUpperCase()})
                </button>
              )}
            </div>
          )}
          {sosIncidents.map(inc => (
            <div key={inc.id} className="py-1 flex items-center flex-wrap gap-x-2" style={{ borderBottom: '1px solid #fef2f2', fontSize: 13 }}>
              <button onClick={() => navigate('/sos', { state: { openIncidentId: inc.id } })}
                className="font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none', fontFamily: 'monospace', fontSize: 13, padding: 0 }}>
                #{inc.id.slice(-8).toUpperCase()}
              </button>
              <span>{inc.type} ({inc.severity}) — {inc.status}</span>
              {inc.title && <span>— {inc.title}</span>}
              <span style={{ color: '#1a2e22' }}>{fmtDT(inc.created_at)}</span>
              {inc.resolved_at && <span style={{ color: '#1a8a18' }}>→ vyřešeno {fmtDT(inc.resolved_at)}</span>}
            </div>
          ))}
        </>
      )}

      {b.status === 'cancelled' && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#dc2626' }}>Zrušení</div>
          <SumRow label="Zrušeno" value={fmtDT(b.cancelled_at)} color="#dc2626" />
          <SumRow label="Zdroj" value={CANCEL_SOURCE_LABELS[b.cancelled_by_source] || b.cancelled_by_source || '—'} />
          <SumRow label="Důvod" value={b.cancellation_reason || '—'} />
          {cancellation && <SumRow label="Vráceno" value={cancellation.refund_amount ? `${Number(cancellation.refund_amount).toLocaleString('cs-CZ')} Kč (${cancellation.refund_percent}%)` : 'Bez refundu'} />}
        </>
      )}

      <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Průběh</div>
      <SumRow label="Vytvořeno" value={fmtDT(b.created_at)} />
      <SumRow label="Potvrzeno" value={fmtDT(b.confirmed_at)} />
      <SumRow label="Vydáno" value={fmtDT(b.picked_up_at)} />
      <SumRow label="Vráceno" value={fmtDT(b.returned_at)} />
      {b.actual_return_date && <SumRow label="Skutečné vrácení" value={fmtDT(b.actual_return_date)} />}
      {b.rated_at && <SumRow label="Hodnoceno" value={`${fmtDT(b.rated_at)} (${b.rating}/5)`} />}

      {(() => {
        const cleanNotes = b.notes
          ? b.notes.replace(/Čas převzetí:\s*\d{1,2}:\d{2}\s*/gi, '').replace(/pickup_time[=:]\s*\S+\s*/gi, '').trim()
          : ''
        return cleanNotes ? (
          <>
            <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Poznámky</div>
            <p className="text-sm" style={{ color: '#1a2e22' }}>{cleanNotes}</p>
          </>
        ) : null
      })()}

      {b.contract_url && <SumRow label="Smlouva" value={b.signed_contract ? 'Podepsána' : 'Nepodepsána'} />}
      {b.complaint_status && <SumRow label="Reklamace" value={b.complaint_status} color="#b45309" />}
    </div>
  )
}

function SumAddressRow({ label, method, address, branchName, lat, lng }) {
  const isDelivery = method === 'delivery'
  const displayAddr = address || branchName || '—'
  const methodLabel = isDelivery ? (label === 'Přistavení' ? 'Přistavení na adresu' : 'Svoz z adresy') : 'Na pobočce'
  const mapLink = isDelivery && (lat && lng)
    ? mapyLinkUrl(lat, lng)
    : isDelivery && address ? `https://mapy.cz/zakladni?q=${encodeURIComponent(address)}` : null

  return (
    <div className="py-[3px]" style={{ borderBottom: '1px solid #f1faf7', fontSize: 12 }}>
      <div className="flex gap-2">
        <span className="font-bold" style={{ color: '#1a2e22', minWidth: 160, flexShrink: 0 }}>{label}</span>
        <span className="font-medium" style={{ color: '#0f1a14' }}>{methodLabel} — {displayAddr}</span>
      </div>
      {isDelivery && (lat && lng) && (
        <div className="ml-[168px]" style={{ fontSize: 11, color: '#6b7280' }}>GPS: {Number(lat).toFixed(6)}, {Number(lng).toFixed(6)}</div>
      )}
      {mapLink && (
        <div className="ml-[168px]">
          <a href={mapLink} target="_blank" rel="noopener noreferrer" style={{ fontSize: 11, color: '#2563eb', textDecoration: 'none', fontWeight: 700 }}>
            📍 Zobrazit na mapě ↗
          </a>
        </div>
      )}
    </div>
  )
}

function SumLocationShares({ sosIncidents }) {
  const withLocation = (sosIncidents || []).filter(i => i.type === 'location_share' || (i.latitude && i.longitude))
  if (withLocation.length === 0) return null

  return withLocation.map(inc => {
    const hasGps = inc.latitude && inc.longitude
    const isLocShare = inc.type === 'location_share'
    const link = hasGps
      ? mapyLinkUrl(inc.latitude, inc.longitude)
      : inc.address ? `https://mapy.cz/zakladni?q=${encodeURIComponent(inc.address)}` : null

    return (
      <div key={inc.id} className="py-[3px]" style={{ borderBottom: '1px solid #dbeafe', fontSize: 12 }}>
        <div className="flex gap-2">
          <span className="font-bold" style={{ color: '#2563eb', minWidth: 160, flexShrink: 0 }}>{isLocShare ? '📍 Sdílení polohy' : '📍 Poloha při SOS'}</span>
          <span className="font-medium" style={{ color: '#0f1a14' }}>
            {new Date(inc.created_at).toLocaleString('cs-CZ')}
            {inc.address ? ` — ${inc.address}` : ''}
          </span>
        </div>
        {hasGps && <div className="ml-[168px]" style={{ fontSize: 11, color: '#6b7280' }}>GPS: {Number(inc.latitude).toFixed(6)}, {Number(inc.longitude).toFixed(6)}</div>}
        {link && (
          <div className="ml-[168px]">
            <a href={link} target="_blank" rel="noopener noreferrer" style={{ fontSize: 11, color: '#2563eb', textDecoration: 'none', fontWeight: 700 }}>
              📍 Zobrazit na mapě ↗
            </a>
          </div>
        )}
      </div>
    )
  })
}
