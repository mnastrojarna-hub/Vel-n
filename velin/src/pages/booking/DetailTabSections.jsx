import Card from '../../components/ui/Card'
import { InfoRow } from './BookingUIHelpers'
import { CANCEL_REASONS, describeModification, paymentMethodInfo, stripePaymentIntentUrl } from './bookingConstants'
import Button from '../../components/ui/Button'
import { mapyLinkUrl, mapyNavigateUrl } from '../../lib/mapyCz'

export function SOSSection({ booking, sosIncidents, navigate }) {
  if (!booking.sos_replacement && !booking.ended_by_sos && sosIncidents.length === 0) return null
  const SOS_TYPE_LABELS = { theft: 'Krádež', accident_minor: 'Lehká nehoda', accident_major: 'Těžká nehoda', breakdown_minor: 'Lehká porucha', breakdown_major: 'Těžká porucha', defect_question: 'Dotaz na závadu', location_share: 'Sdílení polohy', other: 'Jiné' }
  const SOS_STATUS_LABELS = { reported: 'Nahlášeno', acknowledged: 'Přijato', in_progress: 'Řeší se', resolved: 'Vyřešeno', closed: 'Uzavřeno' }
  const SOS_SEVERITY_COLORS = { critical: { bg: '#dc2626', color: '#fff' }, high: { bg: '#f97316', color: '#fff' }, medium: { bg: '#f59e0b', color: '#fff' }, low: { bg: '#6b7280', color: '#fff' } }
  const SOS_DECISION_LABELS = { replacement_moto: 'Náhradní motorka', end_ride: 'Ukončení jízdy + odtah', continue: 'Pokračuje v jízdě', waiting: 'Čeká na rozhodnutí' }
  const inc = sosIncidents[0]
  const rd = inc?.replacement_data || {}
  const isReplacement = booking.sos_replacement
  const isEnded = booking.ended_by_sos

  return (
    <Card className="col-span-2">
      <div className="p-4 rounded-lg" style={{ background: isReplacement ? '#dcfce7' : '#fee2e2', border: `2px solid ${isReplacement ? '#86efac' : '#fca5a5'}` }}>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-extrabold" style={{ color: isReplacement ? '#1a8a18' : '#b91c1c' }}>
            {isReplacement ? '🏍️ Náhradní motorka (SOS)' : '🆘 Ukončeno kvůli SOS incidentu'}
          </h3>
          {(booking.sos_incident_id || inc?.id) && (
            <button onClick={() => navigate('/sos', { state: { openIncidentId: booking.sos_incident_id || inc?.id } })}
              className="text-sm font-extrabold cursor-pointer rounded-btn" style={{ padding: '4px 12px', background: '#b91c1c', color: '#fff', border: 'none' }}>
              🆘 Otevřít SOS incident →
            </button>
          )}
        </div>
        {inc && (
          <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm mb-3" style={{ padding: '10px 12px', background: 'rgba(255,255,255,.6)', borderRadius: 8 }}>
            <InfoRow label="Typ incidentu" value={<span style={{ fontWeight: 800 }}>{SOS_TYPE_LABELS[inc.type] || inc.type}</span>} />
            <InfoRow label="Stav incidentu" value={
              <span className="inline-block rounded-full text-xs font-extrabold" style={{ padding: '2px 10px', ...(inc.status === 'resolved' || inc.status === 'closed' ? { background: '#dcfce7', color: '#1a8a18' } : { background: '#fee2e2', color: '#dc2626' }) }}>
                {SOS_STATUS_LABELS[inc.status] || inc.status}
              </span>
            } />
            {inc.severity && <InfoRow label="Závažnost" value={<span className="inline-block rounded-full text-xs font-extrabold" style={{ padding: '2px 10px', ...(SOS_SEVERITY_COLORS[inc.severity] || { bg: '#6b7280', color: '#fff' }) }}>{inc.severity.toUpperCase()}</span>} />}
            {inc.customer_decision && <InfoRow label="Rozhodnutí zákazníka" value={SOS_DECISION_LABELS[inc.customer_decision] || inc.customer_decision} />}
            <InfoRow label="Zavinění" value={inc.customer_fault === true ? '⚠️ Zákazník' : inc.customer_fault === false ? '✅ Nezaviněno' : '—'} />
            <InfoRow label="Nahlášeno" value={inc.created_at ? new Date(inc.created_at).toLocaleString('cs-CZ') : '—'} />
            {inc.resolved_at && <InfoRow label="Vyřešeno" value={new Date(inc.resolved_at).toLocaleString('cs-CZ')} />}
            {inc.damage_severity && <InfoRow label="Poškození" value={{ none: 'Žádné', cosmetic: 'Kosmetické', functional: 'Funkční', totaled: 'Totální škoda' }[inc.damage_severity] || inc.damage_severity} />}
            {inc.description && <div className="col-span-2"><InfoRow label="Popis" value={inc.description} /></div>}
            {inc.latitude && inc.longitude && (
              <div className="col-span-2">
                <InfoRow label="Poloha zákazníka" value={
                  <span className="inline-flex items-center flex-wrap gap-2">
                    <span className="text-xs font-mono" style={{ color: '#6b7280' }}>GPS: {Number(inc.latitude).toFixed(6)}, {Number(inc.longitude).toFixed(6)}</span>
                    <a href={mapyLinkUrl(inc.latitude, inc.longitude)} target="_blank" rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded-btn" style={{ background: '#dbeafe', color: '#2563eb', textDecoration: 'none' }}>
                      📍 Mapy.cz ↗
                    </a>
                    <a href={mapyNavigateUrl(inc.latitude, inc.longitude)} target="_blank" rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded-btn" style={{ background: '#dcfce7', color: '#1a8a18', textDecoration: 'none' }}>
                      Navigovat ↗
                    </a>
                  </span>
                } />
              </div>
            )}
          </div>
        )}
        {(rd.replacement_model || rd.payment_amount) && (
          <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm mb-3" style={{ padding: '10px 12px', background: 'rgba(255,255,255,.6)', borderRadius: 8 }}>
            <div className="col-span-2 text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Náhradní motorka</div>
            {rd.replacement_model && <InfoRow label="Model" value={rd.replacement_model} />}
            {rd.daily_price > 0 && <InfoRow label="Denní cena" value={`${Number(rd.daily_price).toLocaleString('cs-CZ')} Kč`} />}
            {(rd.original_end_date || rd.remaining_days) && (() => {
              const endDate = rd.original_end_date ? new Date(rd.original_end_date + (rd.original_end_date.includes('T') ? '' : 'T23:59:59')) : null
              if (endDate && !isNaN(endDate)) {
                const now = new Date()
                const remainMs = endDate - now
                if (remainMs <= 0) return <InfoRow label="Zbývající čas" value="Vypršelo" />
                const remainH = Math.floor(remainMs / 3600000)
                if (remainH < 24) return <InfoRow label="Zbývající čas" value={`${remainH} h ${Math.floor((remainMs % 3600000) / 60000)} min`} />
                const d = Math.ceil(remainMs / 86400000)
                return <InfoRow label="Zbývající dny" value={`${d} ${d === 1 ? 'den' : d < 5 ? 'dny' : 'dní'}`} />
              }
              const d = rd.remaining_days
              return d ? <InfoRow label="Zbývající dny" value={`${d} ${d === 1 ? 'den' : d < 5 ? 'dny' : 'dní'}`} /> : null
            })()}
            {rd.payment_amount > 0 && <InfoRow label="Zaplaceno celkem" value={<span style={{ fontWeight: 800, color: '#1a8a18' }}>{Number(rd.payment_amount).toLocaleString('cs-CZ')} Kč</span>} />}
          </div>
        )}
        <div className="flex flex-wrap gap-3 text-sm">
          {booking.replacement_for_booking_id && (
            <button onClick={() => navigate(`/rezervace/${booking.replacement_for_booking_id}`)} className="text-sm font-extrabold cursor-pointer rounded-btn" style={{ padding: '4px 12px', background: '#2563eb', color: '#fff', border: 'none' }}>
              📋 Původní rezervace #{booking.replacement_for_booking_id.slice(-8).toUpperCase()}
            </button>
          )}
          {isEnded && inc?.replacement_booking_id && (
            <button onClick={() => navigate(`/rezervace/${inc.replacement_booking_id}`)} className="text-sm font-extrabold cursor-pointer rounded-btn" style={{ padding: '4px 12px', background: '#1a8a18', color: '#fff', border: 'none' }}>
              🏍️ Náhradní rezervace #{inc.replacement_booking_id.slice(-8).toUpperCase()}
            </button>
          )}
        </div>
      </div>
    </Card>
  )
}

function mapUrl(address, lat, lng) {
  if (lat && lng) return mapyLinkUrl(lat, lng)
  if (address) return `https://mapy.cz/zakladni?q=${encodeURIComponent(address)}`
  return null
}

export function AddressBlock({ label, method, address, branchName, lat, lng, fee, time }) {
  // „Přistavení/svoz" vyhodnocujeme primárně podle method. Fee > 0 je další
  // jasný signál (admin občas nastaví adresu k pobočce bez method=delivery).
  // Mapový odkaz ukazujeme VŽDY, když máme adresu nebo GPS — i pro pobočku
  // (admin se rád proklikne na mapu, aby ji našel).
  const hasGps = !!(lat && lng)
  const isDelivery = method === 'delivery' || (fee > 0)
  const displayAddr = address || branchName || '—'
  const mapLink = hasGps ? mapyLinkUrl(lat, lng) : (address ? `https://mapy.cz/zakladni?q=${encodeURIComponent(address)}` : null)
  const navLink = hasGps ? mapyNavigateUrl(lat, lng) : null

  return (
    <div className="rounded-lg p-3" style={{ background: '#fff', border: `1px solid ${isDelivery ? '#bfdbfe' : '#d4e8e0'}` }}>
      <div className="flex items-center justify-between mb-1.5">
        <div className="text-xs font-extrabold uppercase tracking-wider" style={{ color: '#4a5a52' }}>{label}</div>
        {time && (
          <span className="text-xs font-extrabold rounded-btn" style={{ padding: '2px 8px', background: '#f1faf7', color: '#1a2e22' }}>
            {time}
          </span>
        )}
      </div>
      <div className="text-sm font-extrabold mb-1" style={{ color: isDelivery ? '#1d4ed8' : '#1a8a18' }}>
        {isDelivery ? '🚚 Přistavení / svoz na adresu' : '🏍️ Na pobočce'}
      </div>
      <div className="text-sm font-semibold leading-snug" style={{ color: '#0f1a14' }}>{displayAddr}</div>
      {hasGps && <div className="text-xs mt-1" style={{ color: '#6b7280', fontFamily: 'monospace' }}>GPS: {Number(lat).toFixed(6)}, {Number(lng).toFixed(6)}</div>}
      {fee > 0 && (
        <div className="mt-2 text-xs font-extrabold inline-block rounded-btn" style={{ padding: '2px 8px', background: '#fffbeb', color: '#92400e', border: '1px solid #fde68a' }}>
          Poplatek: {Number(fee).toLocaleString('cs-CZ')} Kč
        </div>
      )}
      {(mapLink || navLink) && (
        <div className="flex flex-wrap gap-2 mt-2">
          {mapLink && (
            <a href={mapLink} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs font-extrabold rounded-btn" style={{ padding: '4px 10px', background: '#dbeafe', color: '#1d4ed8', textDecoration: 'none', border: '1px solid #bfdbfe' }}>
              📍 Mapy.cz ↗
            </a>
          )}
          {navLink && (
            <a href={navLink} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs font-extrabold rounded-btn" style={{ padding: '4px 10px', background: '#dcfce7', color: '#166534', textDecoration: 'none', border: '1px solid #bbf7d0' }}>
              🧭 Navigovat ↗
            </a>
          )}
        </div>
      )}
    </div>
  )
}

export function DoorCodesSection({ doorCodes }) {
  const motoCode = doorCodes.find(c => c.code_type === 'motorcycle')
  const gearCode = doorCodes.find(c => c.code_type === 'accessories')
  const allSent = doorCodes.every(c => c.sent_to_customer)
  const anyWithheld = doorCodes.some(c => c.withheld_reason)

  return (
    <Card className="col-span-2">
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Pristupove kody k pobocce</h3>
      <div className="p-4 rounded-lg" style={{ background: allSent ? '#dcfce7' : anyWithheld ? '#fef3c7' : '#f1faf7', border: `1px solid ${allSent ? '#86efac' : anyWithheld ? '#fcd34d' : '#d4e8e0'}` }}>
        <div className="grid grid-cols-2 gap-4 mb-3">
          <div><div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Kod k motorce</div><div className="text-lg font-black tracking-widest" style={{ color: '#0f1a14', fontFamily: 'monospace' }}>{motoCode?.door_code || '—'}</div></div>
          <div><div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Kod k prislusenstvi</div><div className="text-lg font-black tracking-widest" style={{ color: '#0f1a14', fontFamily: 'monospace' }}>{gearCode?.door_code || '—'}</div></div>
        </div>
        <div className="flex items-center gap-3">
          <span className="inline-block rounded-btn text-xs font-bold" style={{ padding: '3px 10px', background: allSent ? '#dcfce7' : '#fee2e2', color: allSent ? '#1a8a18' : '#dc2626' }}>{allSent ? 'Odeslano zakaznikovi' : 'Neodeslano'}</span>
          {motoCode?.is_active && <span className="inline-block rounded-btn text-xs font-bold" style={{ padding: '3px 10px', background: '#dbeafe', color: '#2563eb' }}>Aktivni</span>}
          {motoCode && !motoCode.is_active && <span className="inline-block rounded-btn text-xs font-bold" style={{ padding: '3px 10px', background: '#f3f4f6', color: '#6b7280' }}>Neaktivni</span>}
          {anyWithheld && <span className="inline-block rounded-btn text-xs font-bold" style={{ padding: '3px 10px', background: '#fef3c7', color: '#b45309' }}>Zadrzeno: {motoCode?.withheld_reason || gearCode?.withheld_reason}</span>}
        </div>
      </div>
    </Card>
  )
}

export function LocationShareRow({ sosIncidents }) {
  const withLocation = (sosIncidents || []).filter(i => i.type === 'location_share' || (i.latitude && i.longitude))
  if (withLocation.length === 0) return null

  return (
    <div className="mt-3 pt-3" style={{ borderTop: '1px solid #d4e8e0' }}>
      {withLocation.map(inc => {
        const hasGps = inc.latitude && inc.longitude
        const isLocShare = inc.type === 'location_share'
        const link = hasGps ? mapyLinkUrl(inc.latitude, inc.longitude) : inc.address ? `https://mapy.cz/zakladni?q=${encodeURIComponent(inc.address)}` : null

        return (
          <div key={inc.id} className="flex items-center flex-wrap gap-2 py-1" style={{ fontSize: 13 }}>
            <span className="font-extrabold" style={{ color: '#2563eb' }}>{isLocShare ? '📍 Zákazník sdílí polohu' : '📍 Poloha při SOS'}</span>
            <span className="text-sm">{new Date(inc.created_at).toLocaleString('cs-CZ')}</span>
            {inc.address && <span className="text-sm font-medium">— {inc.address}</span>}
            {hasGps && <span className="text-xs" style={{ color: '#6b7280' }}>GPS: {Number(inc.latitude).toFixed(6)}, {Number(inc.longitude).toFixed(6)}</span>}
            {link && <a href={link} target="_blank" rel="noopener noreferrer" className="text-xs font-bold" style={{ color: '#2563eb', textDecoration: 'none' }}>Mapa ↗</a>}
          </div>
        )
      })}
    </div>
  )
}

// Heuristika: vytáhne z booking_extras položku, která vypadá jako poplatek za
// přistavení nebo vrácení (admin si je v různých rezervacích pojmenoval různě).
function findFeeExtra(extras, kind) {
  const re = kind === 'pickup'
    ? /(p[rř]istav|delivery|dovoz)/i
    : /(vr[aá]cen[ií]|return|svoz)/i
  return (extras || []).find(e => re.test(e?.name || e?.extras_catalog?.name || ''))
}

function feeAmount(extra) {
  if (!extra) return 0
  const unit = Number(extra.unit_price || extra.extras_catalog?.price_per_day || 0)
  const qty = Number(extra.quantity || 1)
  return unit * qty
}

export function DatesAndPaymentSection({ booking, bookingExtras, sosIncidents, onModify, error, actions, onAction }) {
  const _ld = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
  const hasModification = booking.original_start_date && booking.original_end_date &&
    (_ld(booking.start_date) !== _ld(booking.original_start_date) || _ld(booking.end_date) !== _ld(booking.original_end_date))

  const branchName = booking.motorcycles?.branches?.name
  const pickupExtra = findFeeExtra(bookingExtras, 'pickup')
  const returnExtra = findFeeExtra(bookingExtras, 'return')
  const pickupFee = feeAmount(pickupExtra)
  const returnFee = feeAmount(returnExtra)

  const pmInfo = paymentMethodInfo(booking.payment_method)
  const isPaid = booking.payment_status === 'paid' && booking.status !== 'pending'
  const isRefunded = booking.payment_status === 'refunded'
  const stripeUrl = stripePaymentIntentUrl(booking.stripe_payment_intent_id)

  return (
    <Card className="col-span-2">
      <div className="flex items-center justify-between mb-4 flex-wrap gap-2">
        <div className="flex items-center gap-3 flex-wrap">
          <h3 className="text-base font-extrabold uppercase tracking-wider" style={{ color: '#0f1a14' }}>Termín a platba</h3>
          {booking.booking_source && (
            <span className="inline-flex items-center gap-1 rounded-btn text-xs font-extrabold uppercase tracking-wide"
              style={{ padding: '3px 10px', background: booking.booking_source === 'web' ? '#dbeafe' : '#dcfce7', color: booking.booking_source === 'web' ? '#1d4ed8' : '#166534', border: `1px solid ${booking.booking_source === 'web' ? '#bfdbfe' : '#bbf7d0'}` }}>
              {booking.booking_source === 'web' ? 'Rezervace z webu' : 'Rezervace z aplikace'}
              {booking.created_via_ai && (
                <span title="Vytvořeno přes AI asistenta" style={{ background: '#fef3c7', color: '#92400e', padding: '0 5px', borderRadius: 6, fontSize: 10 }}>🤖 AI</span>
              )}
            </span>
          )}
        </div>
        {!['cancelled', 'completed'].includes(booking.status) && (
          <button onClick={onModify} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '6px 16px', background: '#2563eb', color: '#fff', border: 'none', boxShadow: '0 2px 8px rgba(37,99,235,.25)' }}>Upravit rezervaci</button>
        )}
      </div>
      {hasModification && (() => {
        const mod = describeModification(booking.original_start_date, booking.original_end_date, booking.start_date, booking.end_date)
        const history = Array.isArray(booking.modification_history) ? booking.modification_history : []
        return (
          <div className="mb-3 space-y-1">
            <div className="p-2.5 rounded-lg flex items-center gap-3 flex-wrap" style={{ background: mod.bg, fontSize: 13, border: `1px solid ${mod.color}33` }}>
              <span className="font-extrabold uppercase tracking-wide text-xs rounded-btn" style={{ color: '#fff', background: mod.color, padding: '2px 8px' }}>{mod.type}</span>
              <span style={{ color: '#1a2e22' }}>
                {mod.detail} · Původní: {new Date(booking.original_start_date).toLocaleDateString('cs-CZ')} – {new Date(booking.original_end_date).toLocaleDateString('cs-CZ')} ({mod.origDays}d)
              </span>
            </div>
            {history.length > 0 && (
              <div className="text-sm px-2 py-1 rounded" style={{ background: '#f1faf7', color: '#1a2e22' }}>
                <span className="font-extrabold">Historie úprav ({history.length}×):</span>
                {history.map((h, i) => {
                  const m = describeModification(h.from_start, h.from_end, h.to_start, h.to_end)
                  return <div key={i} className="ml-2">{i + 1}. {new Date(h.at).toLocaleString('cs-CZ')} — <span className="font-bold" style={{ color: m.color }}>{m.type}</span> ({m.detail})</div>
                })}
              </div>
            )}
          </div>
        )
      })()}

      {/* Termín — výrazné rámečky */}
      <div className="grid grid-cols-4 gap-3 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <KeyValueTile label="Od" value={booking.start_date ? new Date(booking.start_date + 'T00:00:00').toLocaleDateString('cs-CZ') : '—'} sub={booking.pickup_time ? `v ${booking.pickup_time}` : null} />
        <KeyValueTile label="Do" value={booking.end_date ? new Date(booking.end_date + 'T00:00:00').toLocaleDateString('cs-CZ') : '—'} sub={booking.return_time ? `v ${booking.return_time}` : null} />
        <KeyValueTile label="Celkem k úhradě" value={`${Number(booking.total_price || 0).toLocaleString('cs-CZ')} Kč`} accent="#1a8a18" big />
        <KeyValueTile label="Dní" value={(() => { const d = Math.max(1, Math.round((new Date(booking.end_date) - new Date(booking.start_date)) / 86400000) + 1); return `${d} ${d === 1 ? 'den' : d < 5 ? 'dny' : 'dní'}` })()} />
      </div>

      {/* Místo + pojištění */}
      <div className="mt-3 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <div className="grid grid-cols-3 gap-3">
          <AddressBlock label="Přistavení" method={booking.pickup_method} address={booking.pickup_address} branchName={branchName} lat={booking.pickup_lat} lng={booking.pickup_lng} fee={pickupFee} time={booking.pickup_time} />
          <AddressBlock label="Vrácení" method={booking.return_method} address={booking.return_address} branchName={branchName} lat={booking.return_lat} lng={booking.return_lng} fee={returnFee} time={booking.return_time} />
          <div className="rounded-lg p-3" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
            <div className="text-xs font-extrabold uppercase tracking-wider mb-1.5" style={{ color: '#4a5a52' }}>Pojištění</div>
            <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>
              {booking.insurance_type ? insuranceLabel(booking.insurance_type) : '—'}
            </div>
          </div>
        </div>
        <LocationShareRow sosIncidents={sosIncidents} />
      </div>

      {/* Platba — silně zvýrazněný blok */}
      <div className="mt-3 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <div className="text-xs font-extrabold uppercase tracking-wider mb-2" style={{ color: '#4a5a52' }}>Platba</div>
        <div className="grid grid-cols-4 gap-3">
          <div className="rounded-lg p-2.5" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
            <div className="text-[11px] font-extrabold uppercase tracking-wider mb-1" style={{ color: '#4a5a52' }}>Stav platby</div>
            <div className="text-sm font-extrabold" style={{ color: isPaid ? '#1a8a18' : isRefunded ? '#dc2626' : '#dc2626' }}>
              {isPaid ? '✅ Zaplaceno' : isRefunded ? '↩️ Refundováno' : '⚠️ Nezaplaceno'}
            </div>
          </div>
          <div className="rounded-lg p-2.5" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
            <div className="text-[11px] font-extrabold uppercase tracking-wider mb-1" style={{ color: '#4a5a52' }}>Způsob platby</div>
            <div className="text-sm font-extrabold flex items-center gap-1.5" style={{ color: pmInfo.tone }}>
              <span>{pmInfo.icon}</span>
              <span>{pmInfo.label}</span>
            </div>
            {stripeUrl && (
              <a href={stripeUrl} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 mt-1 text-[11px] font-extrabold rounded-btn"
                style={{ padding: '2px 6px', background: '#ede9fe', color: '#6d28d9', textDecoration: 'none', border: '1px solid #ddd6fe' }}>
                Stripe ↗
              </a>
            )}
          </div>
          <div className="rounded-lg p-2.5" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
            <div className="text-[11px] font-extrabold uppercase tracking-wider mb-1" style={{ color: '#4a5a52' }}>Sleva</div>
            <div className="text-sm font-extrabold" style={{ color: booking.discount_amount > 0 ? '#1a8a18' : '#0f1a14' }}>
              {booking.discount_amount > 0 ? `-${Number(booking.discount_amount).toLocaleString('cs-CZ')} Kč` : '—'}
            </div>
            {booking.discount_code && <div className="text-[11px] font-bold mt-0.5" style={{ color: '#4a5a52' }}>{booking.discount_code}</div>}
          </div>
          <div className="rounded-lg p-2.5" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
            <div className="text-[11px] font-extrabold uppercase tracking-wider mb-1" style={{ color: '#4a5a52' }}>Kauce</div>
            <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>
              {booking.deposit > 0 ? `${Number(booking.deposit).toLocaleString('cs-CZ')} Kč` : '—'}
            </div>
          </div>
        </div>
      </div>

      {/* Příslušenství — přehledná tabulka */}
      {(bookingExtras?.length > 0 || booking.extras_price > 0) && (
        <div className="mt-3 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="flex items-center justify-between mb-2">
            <div className="text-xs font-extrabold uppercase tracking-wider" style={{ color: '#4a5a52' }}>Příslušenství a poplatky</div>
            <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{Number(booking.extras_price || 0).toLocaleString('cs-CZ')} Kč</div>
          </div>
          {bookingExtras?.length > 0 && (
            <div className="rounded-lg" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
              {bookingExtras.map((ex, i) => {
                const name = ex.name || ex.extras_catalog?.name || `Extra ${i + 1}`
                const unit = Number(ex.unit_price || ex.extras_catalog?.price_per_day || 0)
                const qty = Number(ex.quantity || 1)
                return (
                  <div key={i} className="flex items-center justify-between px-3 py-1.5" style={{ borderTop: i === 0 ? 'none' : '1px solid #eef4f0', fontSize: 13 }}>
                    <span className="font-semibold" style={{ color: '#0f1a14' }}>{name}{qty > 1 ? ` × ${qty}` : ''}</span>
                    <span className="font-extrabold" style={{ color: '#1a2e22' }}>{(unit * qty).toLocaleString('cs-CZ')} Kč</span>
                  </div>
                )
              })}
            </div>
          )}
          {booking.delivery_fee > 0 && (
            <div className="mt-2 text-xs font-bold" style={{ color: '#4a5a52' }}>
              Doručení (separátní pole): <span className="font-extrabold" style={{ color: '#0f1a14' }}>{Number(booking.delivery_fee).toLocaleString('cs-CZ')} Kč</span>
            </div>
          )}
        </div>
      )}

      {(() => {
        const cleanNotes = booking.notes ? booking.notes.replace(/Čas převzetí:\s*\d{1,2}:\d{2}\s*/gi, '').replace(/pickup_time[=:]\s*\S+\s*/gi, '').trim() : ''
        return cleanNotes ? (
          <div className="mt-3 p-3 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fde68a' }}>
            <div className="text-xs font-extrabold uppercase tracking-wider mb-1" style={{ color: '#92400e' }}>Poznámky</div>
            <div className="text-sm font-semibold" style={{ color: '#78350f' }}>{cleanNotes}</div>
          </div>
        ) : null
      })()}
      {error && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{error}</p>}
      <div className="flex gap-3 mt-5">
        {actions.map(a => (
          <Button key={a.status} onClick={() => onAction(a)} green={a.green}
            style={a.danger ? { background: '#dc2626', color: '#fff', boxShadow: '0 4px 16px rgba(220,38,38,.25)' } : undefined}>
            {a.label}
          </Button>
        ))}
      </div>
    </Card>
  )
}

function KeyValueTile({ label, value, sub, accent, big }) {
  return (
    <div className="rounded-lg p-2.5" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
      <div className="text-[11px] font-extrabold uppercase tracking-wider mb-1" style={{ color: '#4a5a52' }}>{label}</div>
      <div className={big ? 'text-base font-extrabold' : 'text-sm font-extrabold'} style={{ color: accent || '#0f1a14' }}>{value}</div>
      {sub && <div className="text-xs font-bold mt-0.5" style={{ color: '#4a5a52' }}>{sub}</div>}
    </div>
  )
}

function insuranceLabel(t) {
  const map = { basic: 'Basic', standard: 'Standard', premium: 'Premium', plus: 'Plus' }
  return map[String(t).toLowerCase()] || t
}
