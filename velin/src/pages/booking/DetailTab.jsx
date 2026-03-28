import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import { InfoRow } from './BookingUIHelpers'
import { CANCEL_REASONS } from './bookingConstants'
import BookingSummary from './BookingSummary'
import Timeline from './BookingTimeline'
import { SOSSection, DoorCodesSection, DatesAndPaymentSection } from './DetailTabSections'

export default function DetailTab({ booking, set, error, saving, actions, onAction, navigate, promoUsage, voucherUsed, onModify }) {
  const [sosIncidents, setSosIncidents] = useState([])
  const [bookingExtras, setBookingExtras] = useState([])
  const [cancellation, setCancellation] = useState(null)
  const [doorCodes, setDoorCodes] = useState([])

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
    if (booking.status === 'cancelled') {
      supabase.from('booking_cancellations').select('*')
        .eq('booking_id', booking.id).limit(1).single()
        .then(({ data }) => { if (data) setCancellation(data) }).catch(() => {})
    }
  }, [booking?.id])

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
        <InfoRow label="Stav" value={{ active: 'Aktivní', maintenance: 'V servisu', unavailable: 'Dočasně vyřazena', retired: 'Trvale vyřazena' }[booking.motorcycles?.status] || booking.motorcycles?.status} />
        <InfoRow label="Pobočka" value={booking.motorcycles?.branches?.name} />
      </Card>

      <SOSSection booking={booking} sosIncidents={sosIncidents} navigate={navigate} />

      {(booking.discount_amount > 0 || booking.discount_code || (promoUsage && promoUsage.length > 0) || voucherUsed) && (
        <Card className="col-span-2">
          <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#b45309' }}>Uplatněné slevy a kódy</h3>
          <div className="p-4 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fde68a' }}>
            <div className="grid grid-cols-3 gap-3">
              {booking.discount_code && <InfoRow label="Slevový kód" value={booking.discount_code} />}
              {booking.discount_amount > 0 && <InfoRow label="Sleva" value={`-${Number(booking.discount_amount).toLocaleString('cs-CZ')} Kč`} />}
              {promoUsage && promoUsage.map((pu, i) => (
                <div key={pu.id || i}>
                  <InfoRow label={`Promo kód ${i + 1}`} value={`${pu.promo_codes?.code || '—'} (${pu.promo_codes?.type === 'percent' ? pu.promo_codes.value + '%' : pu.promo_codes?.value + ' Kč'}) → sleva ${pu.promo_codes?.type === 'percent' ? pu.promo_codes.value + '%' : Number(pu.discount_applied || 0).toLocaleString('cs-CZ') + ' Kč'}`} />
                </div>
              ))}
              {voucherUsed && <InfoRow label="Dárkový poukaz" value={`${voucherUsed.code} — ${Number(voucherUsed.amount).toLocaleString('cs-CZ')} ${voucherUsed.currency}`} />}
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
              <InfoRow label="Zdroj" value={CANCEL_REASONS.find(r => r.value === booking.cancelled_by_source)?.label || booking.cancelled_by_source || '—'} />
              <InfoRow label="Kdy" value={booking.cancelled_at ? new Date(booking.cancelled_at).toLocaleString('cs-CZ') : '—'} />
              <div className="col-span-2"><InfoRow label="Důvod" value={booking.cancellation_reason || '—'} /></div>
              <InfoRow label="Email odeslán" value={booking.cancellation_notified ? 'Ano' : 'Ne'} />
            </div>
          </div>
        </Card>
      )}

      <Card className="col-span-2">
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#1a2e22' }}>Kompletní přehled rezervace</h3>
        <BookingSummary booking={booking} sosIncidents={sosIncidents} bookingExtras={bookingExtras} cancellation={cancellation} promoUsage={promoUsage} voucherUsed={voucherUsed} />
      </Card>

      <Card className="col-span-2">
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#1a2e22' }}>Timeline</h3>
        <Timeline booking={booking} />
      </Card>
    </div>
  )
}
