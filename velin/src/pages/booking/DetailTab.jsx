import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import { InfoRow } from './BookingUIHelpers'
import { CANCEL_SOURCE_LABELS } from './bookingConstants'
import BookingSummary from './BookingSummary'
import Timeline from './BookingTimeline'
import { SOSSection, DoorCodesSection, DatesAndPaymentSection } from './DetailTabSections'

// Stav motorky pro zobrazení: syrový `motorcycles.status` říká „V servisu" i motorce,
// která má jen NAPLÁNOVANÝ servis v budoucnu (pending log). Otevřené záznamy
// z maintenance_log proto rozliší skutečný probíhající servis od plánu.
function motoStatusDisplay(status, openLogs) {
  const base = { active: 'Aktivní', maintenance: 'V servisu', unavailable: 'Dočasně vyřazena', retired: 'Trvale vyřazena' }[status] || status
  if (!Array.isArray(openLogs)) return base
  const today = new Date().toLocaleDateString('sv-SE')
  const inServiceNow = openLogs.some(l => l.status === 'in_service' || (l.status === 'pending' && l.service_date && l.service_date.slice(0, 10) <= today))
  const futurePlan = openLogs.find(l => l.status === 'pending' && l.service_date && l.service_date.slice(0, 10) > today)
  const planLbl = futurePlan ? `servis naplánován od ${new Date(futurePlan.service_date).toLocaleDateString('cs-CZ')}` : null
  if (status === 'maintenance' && !inServiceNow && planLbl) return `Aktivní · ${planLbl}`
  if (status === 'active' && planLbl) return `Aktivní · ${planLbl}`
  return base
}

export default function DetailTab({ booking, set, error, saving, actions, onAction, navigate, promoUsage, voucherUsed, onModify }) {
  const [sosIncidents, setSosIncidents] = useState([])
  const [bookingExtras, setBookingExtras] = useState([])
  const [cancellation, setCancellation] = useState(null)
  const [doorCodes, setDoorCodes] = useState([])
  const [bookingDiscounts, setBookingDiscounts] = useState([])
  const [motoOpenLogs, setMotoOpenLogs] = useState(null)

  useEffect(() => {
    if (!booking?.id) return
    supabase.from('sos_incidents').select('id,type,title,status,severity,created_at,resolved_at,description,damage_severity,customer_fault,replacement_booking_id,original_booking_id,replacement_status,replacement_data,moto_id,original_moto_id,replacement_moto_id,customer_decision,latitude,longitude,address')
      .or(`booking_id.eq.${booking.id},original_booking_id.eq.${booking.id},replacement_booking_id.eq.${booking.id}`)
      .order('created_at', { ascending: false })
      .then(({ data }) => { if (data) setSosIncidents(data) }).catch(() => {})
    supabase.from('booking_extras').select('*, extras_catalog(name, price_per_day)')
      .eq('booking_id', booking.id)
      .then(({ data }) => { if (data) setBookingExtras(data) }).catch(() => {})
    supabase.from('branch_door_codes').select('*')
      .eq('booking_id', booking.id).order('code_type')
      .then(({ data }) => { if (data) setDoorCodes(data) }).catch(() => {})
    supabase.from('booking_discounts').select('*')
      .eq('booking_id', booking.id).order('created_at')
      .then(({ data }) => { if (data) setBookingDiscounts(data) }).catch(() => {})
    if (booking.status === 'cancelled') {
      supabase.from('booking_cancellations').select('*')
        .eq('booking_id', booking.id).limit(1).single()
        .then(({ data }) => { if (data) setCancellation(data) }).catch(() => {})
    }
  }, [booking?.id])

  useEffect(() => {
    const mid = booking?.motorcycles?.id
    if (!mid) { setMotoOpenLogs(null); return }
    supabase.from('maintenance_log').select('id, status, service_date')
      .eq('moto_id', mid).is('completed_date', null).in('status', ['pending', 'in_service'])
      .order('service_date', { ascending: true })
      .then(({ data }) => setMotoOpenLogs(data || []), () => setMotoOpenLogs(null))
  }, [booking?.motorcycles?.id])

  // Jednotný, DEDUPLIKOVANÝ seznam slev: stejný kód bývá zapsaný v booking_discounts
  // I v promo_code_usage (např. Slevomat) — zobrazí se jen jednou. Fallback na
  // bookings.discount_code jen když neexistuje žádný strukturovaný záznam.
  const discountRows = (() => {
    const rows = []
    const seen = new Set()
    const norm = c => String(c || '').trim().toUpperCase()
    for (const d of bookingDiscounts) {
      seen.add(norm(d.code))
      rows.push({
        key: `bd-${d.id}`,
        label: d.kind === 'voucher' ? 'Dárkový poukaz' : (d.discount_type === 'percent' ? `Slevový kód (${d.value} %)` : 'Slevový kód'),
        value: `${d.code} → -${Number(d.amount || 0).toLocaleString('cs-CZ')} Kč`,
      })
    }
    for (const pu of (promoUsage || [])) {
      const pc = pu.promo_codes
      if (!pc?.code || seen.has(norm(pc.code))) continue
      seen.add(norm(pc.code))
      const applied = Number(pu.discount_applied || 0)
      rows.push({
        key: `pu-${pu.id}`,
        label: pc.type === 'percent' ? `Slevový kód (${pc.value} %)` : `Slevový kód (${pc.value} Kč)`,
        value: applied > 0 ? `${pc.code} → -${applied.toLocaleString('cs-CZ')} Kč` : pc.code,
      })
    }
    if (voucherUsed?.code && !seen.has(norm(voucherUsed.code))) {
      seen.add(norm(voucherUsed.code))
      rows.push({ key: 'voucher', label: 'Dárkový poukaz', value: `${voucherUsed.code} — ${Number(voucherUsed.amount).toLocaleString('cs-CZ')} ${voucherUsed.currency}` })
    }
    if (rows.length === 0 && booking.discount_code) {
      rows.push({ key: 'code', label: 'Slevový kód', value: booking.discount_code })
    }
    if (booking.loyalty_discount_amount > 0) {
      rows.push({ key: 'loyalty', label: `★ Věrnostní sleva${booking.loyalty_percent ? ` ${booking.loyalty_percent} %` : ''} (jen app)`, value: `-${Number(booking.loyalty_discount_amount).toLocaleString('cs-CZ')} Kč` })
    }
    if (booking.late_pickup_discount_amount > 0) {
      rows.push({ key: 'late-pickup', label: '🌗 Sleva 50 % na 1. den (pozdní vyzvednutí)', value: `-${Number(booking.late_pickup_discount_amount).toLocaleString('cs-CZ')} Kč` })
    }
    return rows
  })()

  return (
    <div className="grid grid-cols-2 gap-5">
      <Card>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Zákazník</h3>
          {booking.profiles?.id && (
            <button onClick={() => navigate(`/zakaznici/${booking.profiles.id}`)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>→ Detail zákazníka</button>
          )}
        </div>
        <InfoRow label="Jméno" value={booking.profiles?.full_name} />
        <InfoRow label="Email" value={booking.profiles?.email} />
        <InfoRow label="Telefon" value={booking.profiles?.phone} />
        <InfoRow label="Město" value={booking.profiles?.city} />
      </Card>

      <Card>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Motorka</h3>
          {booking.motorcycles?.id && (
            <button onClick={() => navigate(`/flotila/${booking.motorcycles.id}`)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>→ Detail motorky</button>
          )}
        </div>
        <InfoRow label="Model" value={booking.motorcycles?.model} />
        <InfoRow label="SPZ" value={booking.motorcycles?.spz} />
        <InfoRow label="Stav" value={motoStatusDisplay(booking.motorcycles?.status, motoOpenLogs)} />
        <InfoRow label="Pobočka" value={booking.motorcycles?.branches?.name} />
      </Card>

      <SOSSection booking={booking} sosIncidents={sosIncidents} navigate={navigate} />

      {(discountRows.length > 0 || booking.discount_amount > 0) && (
        <Card className="col-span-2">
          <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#b45309' }}>Uplatněné slevy a kódy</h3>
          <div className="p-4 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fde68a' }}>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
              {discountRows.map(r => (
                <div key={r.key} className="min-w-0">
                  <InfoRow label={r.label} value={r.value} />
                </div>
              ))}
              {booking.discount_amount > 0 && discountRows.length !== 1 && (
                <InfoRow label="Sleva celkem" value={`-${Number(booking.discount_amount).toLocaleString('cs-CZ')} Kč`} />
              )}
            </div>
          </div>
        </Card>
      )}

      {doorCodes.length > 0 && <DoorCodesSection doorCodes={doorCodes} />}

      <DatesAndPaymentSection booking={booking} bookingExtras={bookingExtras} sosIncidents={sosIncidents} onModify={onModify} error={error} actions={actions} onAction={onAction} />

      {booking.status === 'cancelled' && (
        <Card className="col-span-2">
          <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#dc2626' }}>Informace o zrušení</h3>
          <div className="p-4 rounded-lg" style={{ background: '#fef2f2', border: '1px solid #fecaca' }}>
            <div className="grid grid-cols-2 gap-3">
              <InfoRow label="Zdroj" value={CANCEL_SOURCE_LABELS[booking.cancelled_by_source] || booking.cancelled_by_source || '—'} />
              <InfoRow label="Kdy" value={booking.cancelled_at ? new Date(booking.cancelled_at).toLocaleString('cs-CZ') : '—'} />
              <div className="col-span-2"><InfoRow label="Důvod" value={booking.cancellation_reason || '—'} /></div>
              <InfoRow label="Email odeslán" value={booking.cancellation_notified ? 'Ano' : 'Ne'} />
              {cancellation && (
                <InfoRow label="Vráceno" value={Number(cancellation.refund_amount) > 0
                  ? `${Number(cancellation.refund_amount).toLocaleString('cs-CZ')} Kč${cancellation.refund_percent != null ? ` (${cancellation.refund_percent} %)` : ''}`
                  : 'Bez vratky'} />
              )}
            </div>
          </div>
        </Card>
      )}

      <Card className="col-span-2">
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#1a2e22' }}>Doplňující informace</h3>
        <BookingSummary booking={booking} bookingExtras={bookingExtras} />
      </Card>

      <Card className="col-span-2">
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#1a2e22' }}>Timeline</h3>
        <Timeline booking={booking} />
      </Card>
    </div>
  )
}
