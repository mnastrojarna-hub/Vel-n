import { SumRow } from './BookingUIHelpers'
import { fmtDT, hasPassengerGearOrdered } from './bookingConstants'

// Doba vyplnění formuláře v sekundách → čitelný formát (např. „2 min 15 s")
function fmtDuration(s) {
  s = Math.round(Number(s) || 0)
  if (s < 60) return `${s} s`
  const m = Math.floor(s / 60)
  const rest = s % 60
  if (m < 60) return rest ? `${m} min ${rest} s` : `${m} min`
  const h = Math.floor(m / 60)
  return `${h} h ${m % 60} min`
}

// Doplňující informace k rezervaci — JEN údaje, které nejsou nikde jinde na
// stránce: výbava (velikosti), nájezd, poškození, průběh webového flow a
// stav smlouvy/reklamace. Zbytek (zákazník, motorka, termín, platba, slevy,
// adresy, SOS, zrušení, poznámky, milníky) mají vlastní karty / Timeline.
export default function BookingSummary({ booking, bookingExtras }) {
  const b = booking
  const devLabel = d => d === 'pc' ? 'PC' : d === 'mobile' ? 'Mobil' : d === 'tablet' ? 'Tablet' : null
  const devStart = devLabel(b.created_device)
  const devEnd = devLabel(b.completed_device)
  const deviceVal = (devStart && devEnd && devEnd !== devStart)
    ? `${devStart} → ${devEnd}`
    : (devStart || devEnd || null)

  return (
    <div className="space-y-1">
      {(b.helmet_size || b.jacket_size || b.pants_size || b.boots_size || b.gloves_size) && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Výbava — řidič</div>
          <SumRow label="Helma" value={b.helmet_size ? `vel. ${b.helmet_size}` : null} />
          <SumRow label="Bunda" value={b.jacket_size ? `vel. ${b.jacket_size}` : null} />
          <SumRow label="Kalhoty" value={b.pants_size ? `vel. ${b.pants_size}` : null} />
          <SumRow label="Boty" value={b.boots_size ? `vel. ${b.boots_size}` : null} />
          <SumRow label="Rukavice" value={b.gloves_size ? `vel. ${b.gloves_size}` : null} />
        </>
      )}
      {/* Výbava spolujezdce zobrazujeme JEN když ji zákazník skutečně objednal
          (existuje booking_extra se „spolujez" / „passenger", nebo je vyplněno
          ≥2 velikostí — tedy reálná sada). Sám fakt, že je v `bookings`
          vyplněna jediná passenger_*_size, neznamená objednávku. */}
      {hasPassengerGearOrdered(b, bookingExtras) && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Výbava — spolujezdec</div>
          <SumRow label="Helma" value={b.passenger_helmet_size ? `vel. ${b.passenger_helmet_size}` : null} />
          <SumRow label="Bunda" value={b.passenger_jacket_size ? `vel. ${b.passenger_jacket_size}` : null} />
          <SumRow label="Kalhoty" value={b.passenger_pants_size ? `vel. ${b.passenger_pants_size}` : null} />
          <SumRow label="Boty" value={b.passenger_boots_size ? `vel. ${b.passenger_boots_size}` : null} />
          <SumRow label="Rukavice" value={b.passenger_gloves_size ? `vel. ${b.passenger_gloves_size}` : null} />
        </>
      )}

      {(b.mileage_start || b.mileage_end) && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Nájezd</div>
          {b.mileage_start && <SumRow label="Při převzetí" value={`${b.mileage_start} km`} />}
          {b.mileage_end && <SumRow label="Při vrácení" value={`${b.mileage_end} km`} />}
          {b.mileage_start && b.mileage_end && <SumRow label="Najeto" value={`${b.mileage_end - b.mileage_start} km`} />}
        </>
      )}

      {b.damage_report && <SumRow label="Poškození" value={b.damage_report} color="#dc2626" />}

      <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Průběh</div>
      {b.booking_source === 'web' && (() => {
        const paid = ['paid', 'partial_refund', 'refund_pending'].includes(b.payment_status)
        const reachedGw = !!(b.checkout_started_at || b.stripe_checkout_url || b.chosen_payment_method || b.pay_channel)
        const isQr = b.chosen_payment_method === 'qr' || b.pay_channel === 'qr'
        let step, label, color
        if (paid && b.docs_completed_at) { step = 4; label = 'dokončeno (doklady vyplněny)'; color = '#16a34a' }
        else if (paid) { step = 4; label = 'doklady (zaplaceno, čeká na doklady)'; color = '#7c3aed' }
        else if (reachedGw) { step = 3; label = isQr ? 'QR / bankovní převod (čeká na připsání)' : 'platba kartou / brána (nezaplaceno)'; color = '#f59e0b' }
        else { step = 2; label = 'přehled'; color = '#dc2626' }
        return <SumRow label="Krok ve flow" value={`${step}/4 — ${label}`} color={color} />
      })()}
      {b.booking_source === 'web' && deviceVal && (
        <SumRow label="Zařízení" value={deviceVal} color={devStart && devEnd && devEnd !== devStart ? '#7c3aed' : undefined} />
      )}
      {Number.isFinite(b.form_fill_seconds) && b.form_fill_seconds >= 0 && (
        <SumRow label="Doba vyplnění formuláře" value={fmtDuration(b.form_fill_seconds)} />
      )}
      {Number.isFinite(b.payment_fill_seconds) && b.payment_fill_seconds >= 0 && (
        <SumRow label="Doba do zaplacení" value={fmtDuration(b.payment_fill_seconds)} />
      )}
      {b.booking_source === 'web' && b.payment_status !== 'paid' && b.chosen_payment_method && (
        <SumRow label="Zvolená platba" value={b.chosen_payment_method === 'qr' ? 'QR / převod' : 'Karta (online)'} />
      )}
      {b.docs_completed_at && (
        <SumRow label="Doklady doplněny (po platbě)" value={fmtDT(b.docs_completed_at)} color="#7c3aed" />
      )}
      {b.actual_return_date && <SumRow label="Skutečné vrácení" value={fmtDT(b.actual_return_date)} />}
      {b.rated_at && <SumRow label="Hodnoceno" value={`${fmtDT(b.rated_at)} (${b.rating}/5)`} />}

      {b.contract_url && <SumRow label="Smlouva" value={b.signed_contract ? 'Podepsána' : 'Nepodepsána'} />}
      {b.complaint_status && <SumRow label="Reklamace" value={b.complaint_status} color="#b45309" />}
    </div>
  )
}
