// AI Training Scenarios — WATCHDOG concept
// Agents learn to DETECT inconsistencies, not to DO operations.
// Uses a POOL of pre-created customers to avoid signUp rate limits.
import * as API from './aiTrainingHelpers'

export const AGENT_VOLUMES = {
  bookings:    { min: 25, label: 'Rezervace (konzistence, edge cases, cross-check)' },
  fleet:       { min: 15, label: 'Flotila (STK, pojistky, stav vs realita)' },
  customers:   { min: 15, label: 'Zákazníci (komunikace, reklamace, doklady)' },
  finance:     { min: 15, label: 'Finance (párování, faktury, ceník)' },
  service:     { min: 15, label: 'Servis (intervaly, dokončení, log)' },
  sos:         { min: 25, label: 'SOS (koordinace — jediný aktivní agent)' },
  eshop:       { min: 10, label: 'E-shop (sklad, vouchery, promo)' },
  hr:          { min: 10, label: 'HR (směny, docházka, zákonnost)' },
  analytics:   { min: 10, label: 'Analytika (reporty, metriky, trendy)' },
  government:  { min: 5,  label: 'Státní správa (STK, pojistky, termíny)' },
  cms:         { min: 8,  label: 'CMS (nastavení, šablony, pravidla)' },
  tester:      { min: 10, label: 'Tester (audit tabulek, integrita dat)' },
  edge:        { min: 10, label: 'Edge cases (overlap, missing docs)' },
}

export const SOS_TYPES = [
  { type: 'breakdown_minor', label: 'Porucha', desc: 'Motorka nechce nastartovat' },
  { type: 'defect_question', label: 'Defekt pneu', desc: 'Píchlá zadní pneumatika' },
  { type: 'accident_minor', label: 'Lehká nehoda', desc: 'Drobná kolize, škrábance' },
  { type: 'accident_major', label: 'Těžká nehoda', desc: 'Vážná nehoda, motorka nepojízdná' },
  { type: 'theft', label: 'Krádež', desc: 'Motorka odcizena z parkoviště' },
]

// Pre-create a pool of test customers (max 5 to avoid rate limits)
async function createCustomerPool(count, onStep) {
  const pool = []
  for (let i = 0; i < count; i++) {
    onStep?.({ agent: 'customers', action: `Příprava zákazníka ${i + 1}/${count}` })
    const cust = await API.createTestCustomer()
    if (cust.ok) pool.push(cust)
  }
  return pool
}

// === BOOKINGS AGENT — validates consistency ===
export async function trainBookingsAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok || !motos.data.length) return [{ ok: false, error: 'Žádné motorky' }]

  onStep?.({ agent: 'bookings', action: 'Příprava zákazníků...', i: 0, total: 12 })
  const pool = await createCustomerPool(3, onStep)
  if (!pool.length) return [{ ok: false, error: 'Nepodařilo se vytvořit zákazníky (rate limit)' }]
  results.push({ agent: 'customers', action: 'pool_created', ok: true, count: pool.length })

  // Phase 1: Velín creates bookings, agent checks consistency
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[i % motos.data.length]
    const cust = pool[i % pool.length]
    const start = API.futureDate(3 + i * 4), end = API.futureDate(6 + i * 4)
    onStep?.({ agent: 'bookings', action: `Konzistence rez. #${i + 1}`, i, total: 12 })

    const booking = await API.createBooking(cust.userId, moto.id, start, end)
    results.push({ agent: 'bookings', action: 'velin_created_booking', ...booking })

    if (booking.ok) {
      const avail = await API.checkMotoAvailability(moto.id, start, end)
      results.push({ agent: 'bookings', action: 'check_no_overlap', ok: !avail.available })
      const price = await API.calcBookingPrice(moto.id, start, end)
      results.push({ agent: 'finance', action: 'verify_price', ok: price.ok })
      await API.confirmBookingPayment(booking.bookingId)
      results.push({ agent: 'bookings', action: 'payment_confirmed', ok: true })
    }
  }

  // Phase 2: Edge cases — shorten booking
  for (let i = 0; i < 3; i++) {
    const moto = motos.data[(i + 5) % motos.data.length]
    const cust = pool[i % pool.length]
    onStep?.({ agent: 'bookings', action: `Edge: zkrácení #${i + 1}`, i: 5 + i, total: 12 })
    const booking = await API.createBooking(cust.userId, moto.id, API.futureDate(20 + i * 3), API.futureDate(23 + i * 3))
    if (booking.ok) {
      const sh = await API.shortenBooking(booking.bookingId, API.futureDate(22 + i * 3))
      results.push({ agent: 'bookings', action: 'edge_shorten', ...sh })
    }
  }

  // Phase 3: Storno
  for (let i = 0; i < 4; i++) {
    const moto = motos.data[(i + 8) % motos.data.length]
    const cust = pool[i % pool.length]
    onStep?.({ agent: 'bookings', action: `Storno #${i + 1}`, i: 8 + i, total: 12 })
    const booking = await API.createBooking(cust.userId, moto.id, API.futureDate(35 + i * 3), API.futureDate(38 + i * 3))
    if (booking.ok) {
      const cancel = await API.cancelBooking(booking.bookingId, API.PICK(['Změna plánů', 'Nemoc', 'Počasí']))
      results.push({ agent: 'bookings', action: 'cancel_and_verify', ...cancel })
    }
  }
  return results
}

// === SOS AGENT — actively coordinates ===
// IMPORTANT: trg_one_active_sos allows max 1 severe SOS per BOOKING.
// Light types (breakdown_minor, defect_question) are unlimited.
// Each severe SOS needs its own booking + must be resolved before next on same booking.
export async function trainSosAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  onStep?.({ agent: 'sos', action: 'Příprava zákazníků...', i: 0, total: 25 })
  const pool = await createCustomerPool(3, onStep)
  if (!pool.length) return [{ ok: false, error: 'Nepodařilo se vytvořit zákazníky' }]

  let stepIdx = 0
  for (const sosType of SOS_TYPES) {
    for (let i = 0; i < 5; i++) {
      const moto = motos.data[(stepIdx) % motos.data.length]
      const cust = pool[stepIdx % pool.length]
      stepIdx++
      onStep?.({ agent: 'sos', action: `${sosType.label} #${i + 1}/5`, i: stepIdx, total: 25 })

      // Each SOS needs its OWN unique booking (trigger checks per booking_id)
      const bookingStart = API.futureDate(stepIdx * 2)
      const bookingEnd = API.futureDate(stepIdx * 2 + 3)
      const booking = await API.createBooking(cust.userId, moto.id, bookingStart, bookingEnd)
      if (!booking.ok) {
        results.push({ agent: 'sos', action: 'booking_failed', ok: false, error: booking.error })
        continue
      }
      await API.confirmBookingPayment(booking.bookingId)

      const sos = await API.createSosIncident(cust.userId, booking.bookingId, moto.id, sosType.type, `SIM: ${sosType.desc}`)
      results.push({ agent: 'sos', action: 'create_incident', type: sosType.type, ...sos })

      if (sos.ok) {
        await API.updateSosStatus(sos.incidentId, 'in_progress', 'Přiřazen technik')
        results.push({ agent: 'sos', action: 'coordinate', ok: true })
        // MUST resolve before creating next severe SOS for same user
        await API.updateSosStatus(sos.incidentId, 'resolved', `Vyřešeno: ${sosType.label}`)
        results.push({ agent: 'sos', action: 'resolve', ok: true })

        if (['accident_minor', 'accident_major', 'theft'].includes(sosType.type)) {
          const svc = await API.createServiceOrder(moto.id, 'repair', `Oprava po ${sosType.label}`)
          results.push({ agent: 'service', action: 'sos_service', ...svc })
          if (sosType.type !== 'accident_minor') {
            await API.updateMotoStatus(moto.id, sosType.type === 'theft' ? 'unavailable' : 'maintenance')
            await API.updateMotoStatus(moto.id, 'active')
          }
        }
      }
    }
  }
  return results
}

// === SERVICE AGENT — monitors intervals, verifies completion ===
export async function trainServiceAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  const types = [
    { type: 'oil_change', desc: 'Výměna oleje', hours: 1.5 },
    { type: 'brake_check', desc: 'Kontrola brzd', hours: 2 },
    { type: 'tire_change', desc: 'Výměna pneu', hours: 1 },
    { type: 'chain_adjust', desc: 'Řetěz', hours: 0.5 },
    { type: 'full_inspection', desc: 'Kompletní prohlídka', hours: 3 },
  ]

  for (let i = 0; i < 5; i++) {
    const moto = motos.data[i % motos.data.length]
    const t = types[i]
    onStep?.({ agent: 'service', action: `Servis: ${t.desc}`, i, total: 15 })
    await API.updateMotoStatus(moto.id, 'maintenance')
    const svc = await API.createServiceOrder(moto.id, t.type, t.desc)
    results.push({ agent: 'service', action: 'velin_created_order', ...svc })
    if (svc.ok) {
      await API.completeServiceOrder(svc.orderId, `Hotovo: ${t.desc}`)
      const ml = await API.createMaintenanceLog(moto.id, t.type, t.desc, t.hours)
      results.push({ agent: 'service', action: 'verify_log', ...ml })
    }
    await API.updateMotoStatus(moto.id, 'active')
    results.push({ agent: 'service', action: 'verify_active', ok: true })
  }

  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 5) % motos.data.length]
    onStep?.({ agent: 'service', action: `Oprava #${i + 1}`, i: 5 + i, total: 15 })
    const svc = await API.createServiceOrder(moto.id, 'repair', `Oprava #${i + 1}`)
    results.push({ agent: 'service', action: 'verify_repair', ...svc })
    if (svc.ok) await API.completeServiceOrder(svc.orderId, 'Dokončeno')
  }

  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 10) % motos.data.length]
    onStep?.({ agent: 'service', action: `Log #${i + 1}`, i: 10 + i, total: 15 })
    const ml = await API.createMaintenanceLog(moto.id, 'general', `Kontrola #${i + 1}`, 1)
    results.push({ agent: 'service', action: 'verify_log_entry', ...ml })
  }
  return results
}

export { API }
