import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import { InfoRow } from './BookingUIHelpers'
import { CANCEL_REASONS, describeModification } from './bookingConstants'
import BookingSummary from './BookingSummary'
import Timeline from './BookingTimeline'

export default function DetailTab({ booking, set, error, saving, actions, onAction, navigate, promoUsage, voucherUsed, onModify }) {
  const [sosIncidents, setSosIncidents] = useState([])
  const [bookingExtras, setBookingExtras] = useState([])
  const [cancellation, setCancellation] = useState(null)

  useEffect(() => {
    if (!booking?.id) return
    supabase.from('sos_incidents').select('id,type,title,status,severity,created_at,resolved_at,description,damage_severity,customer_fault,replacement_booking_id,original_booking_id,replacement_status,replacement_data,moto_id,original_moto_id,replacement_moto_id,customer_decision')
      .or(`booking_id.eq.${booking.id},original_booking_id.eq.${booking.id},replacement_booking_id.eq.${booking.id}`)
      .order('created_at', { ascending: false })
      .then(({ data }) => { if (data) setSosIncidents(data) }).catch(() => {})
    supabase.from('booking_extras').select('*, extras_catalog(name, price)')
      .eq('booking_id', booking.id)
      .then(({ data }) => { if (data) setBookingExtras(data) }).catch(() => {})
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
                  <InfoRow label={`Promo kód ${i + 1}`} value={`${pu.promo_codes?.code || '—'} (${pu.promo_codes?.type === 'percent' ? pu.promo_codes.value + '%' : pu.promo_codes?.value + ' Kč'}) → sleva ${Number(pu.discount_applied || 0).toLocaleString('cs-CZ')} Kč`} />
                </div>
              ))}
              {voucherUsed && <InfoRow label="Dárkový poukaz" value={`${voucherUsed.code} — ${Number(voucherUsed.amount).toLocaleString('cs-CZ')} ${voucherUsed.currency}`} />}
            </div>
          </div>
        </Card>
      )}

      <DatesAndPaymentSection booking={booking} bookingExtras={bookingExtras} onModify={onModify} error={error} actions={actions} onAction={onAction} />

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

function SOSSection({ booking, sosIncidents, navigate }) {
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
          </div>
        )}
        {(rd.replacement_model || rd.payment_amount) && (
          <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm mb-3" style={{ padding: '10px 12px', background: 'rgba(255,255,255,.6)', borderRadius: 8 }}>
            <div className="col-span-2 text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Náhradní motorka</div>
            {rd.replacement_model && <InfoRow label="Model" value={rd.replacement_model} />}
            {rd.daily_price > 0 && <InfoRow label="Denní cena" value={`${Number(rd.daily_price).toLocaleString('cs-CZ')} Kč`} />}
            {rd.remaining_days && <InfoRow label="Zbývající dny" value={`${rd.remaining_days} ${rd.remaining_days === 1 ? 'den' : rd.remaining_days < 5 ? 'dny' : 'dní'}`} />}
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

function DatesAndPaymentSection({ booking, bookingExtras, onModify, error, actions, onAction }) {
  const _ld = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
  const hasModification = booking.original_start_date && booking.original_end_date &&
    (_ld(booking.start_date) !== _ld(booking.original_start_date) || _ld(booking.end_date) !== _ld(booking.original_end_date))

  return (
    <Card className="col-span-2">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Termín a platba</h3>
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
            <div className="p-2 rounded-lg flex items-center gap-3" style={{ background: mod.bg, fontSize: 13 }}>
              <span className="font-extrabold" style={{ color: mod.color }}>{mod.type}</span>
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
      <div className="grid grid-cols-4 gap-4 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
        <div><div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Od</div><div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{booking.start_date ? new Date(booking.start_date + 'T00:00:00').toLocaleDateString('cs-CZ') : '—'}</div></div>
        <div><div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Do</div><div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{booking.end_date ? new Date(booking.end_date + 'T00:00:00').toLocaleDateString('cs-CZ') : '—'}</div></div>
        <div><div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Celkem</div><div className="text-sm font-extrabold" style={{ color: '#1a8a18' }}>{Number(booking.total_price || 0).toLocaleString('cs-CZ')} Kč</div></div>
        <div><div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Dní</div><div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{(() => { const d = Math.max(1, Math.round((new Date(booking.end_date) - new Date(booking.start_date)) / 86400000) + 1); return `${d} ${d === 1 ? 'den' : d < 5 ? 'dny' : 'dní'}` })()}</div></div>
      </div>
      <div className="grid grid-cols-3 gap-4 mt-3 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
        <div><div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Přistavení</div><div className="text-sm">{booking.pickup_method === 'delivery' ? 'Přistavení na adresu' : 'Na pobočce'} — {booking.pickup_address || booking.motorcycles?.branches?.name || '—'}</div></div>
        <div><div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Vrácení</div><div className="text-sm">{booking.return_method === 'delivery' ? 'Svoz z adresy' : 'Na pobočce'} — {booking.return_address || booking.motorcycles?.branches?.name || '—'}</div></div>
        <div><div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Pojištění</div><div className="text-sm">{booking.insurance_type || '—'}</div></div>
      </div>
      <div className="grid grid-cols-4 gap-4 mt-3 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
        <div><div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Příslušenství</div><div className="text-sm font-bold">{booking.extras_price > 0 ? `${Number(booking.extras_price).toLocaleString('cs-CZ')} Kč` : '—'}</div>
          {bookingExtras.length > 0 && bookingExtras.map((ex, i) => <div key={i} className="text-sm" style={{ color: '#1a2e22' }}>{ex.extras_catalog?.name || `Extra ${i + 1}`}: {Number(ex.extras_catalog?.price || 0).toLocaleString('cs-CZ')} Kč</div>)}</div>
        <div><div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Doručení</div><div className="text-sm font-bold">{booking.delivery_fee > 0 ? `${Number(booking.delivery_fee).toLocaleString('cs-CZ')} Kč` : '—'}</div></div>
        <div><div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Sleva</div><div className="text-sm font-bold" style={{ color: booking.discount_amount > 0 ? '#1a8a18' : undefined }}>{booking.discount_amount > 0 ? `-${Number(booking.discount_amount).toLocaleString('cs-CZ')} Kč` : '—'}{booking.discount_code ? ` (${booking.discount_code})` : ''}</div></div>
        <div><div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Kauce</div><div className="text-sm font-bold">{booking.deposit > 0 ? `${Number(booking.deposit).toLocaleString('cs-CZ')} Kč` : '—'}</div></div>
      </div>
      {booking.notes && (
        <div className="mt-3 p-3 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fde68a' }}>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#92400e' }}>Poznámky</div>
          <div className="text-sm" style={{ color: '#78350f' }}>{booking.notes}</div>
        </div>
      )}
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
