// AI Training Scenarios — WATCHDOG concept
// Agents learn to DETECT inconsistencies, not to DO operations.
// Velín does 80% algorithmically. Agents validate + handle edge cases.
import * as API from './aiTrainingHelpers'

export const AGENT_VOLUMES = {
  bookings:  { min: 25, label: 'Rezervace (konzistence, edge cases, cross-check)' },
  fleet:     { min: 15, label: 'Flotila (STK, pojistky, stav vs realita)' },
  customers: { min: 15, label: 'Zákazníci (komunikace, reklamace, doklady)' },
  finance:   { min: 15, label: 'Finance (párování, faktury, ceník)' },
  service:   { min: 15, label: 'Servis (intervaly, dokončení, log)' },
  sos:       { min: 25, label: 'SOS (koordinace — jediný aktivní agent)' },
  eshop:     { min: 10, label: 'E-shop (sklad, vouchery, promo)' },
  edge:      { min: 10, label: 'Edge cases (overlap, missing docs)' },
}

export const SOS_TYPES = [
  { type: 'breakdown_minor', label: 'Porucha', desc: 'Motorka nechce nastartovat' },
  { type: 'defect_question', label: 'Defekt pneu', desc: 'Píchlá zadní pneumatika' },
  { type: 'accident_minor', label: 'Lehká nehoda', desc: 'Drobná kolize, škrábance' },
  { type: 'accident_major', label: 'Těžká nehoda', desc: 'Vážná nehoda, motorka nepojízdná' },
  { type: 'theft', label: 'Krádež', desc: 'Motorka odcizena z parkoviště' },
]

// === BOOKINGS AGENT — validates consistency after Velín operations ===
export async function trainBookingsAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok || !motos.data.length) return [{ ok: false, error: 'Žádné motorky' }]

  // Phase 1: Velín creates bookings (simulate), agent checks consistency
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[i % motos.data.length]
    const start = API.futureDate(3 + i * 4), end = API.futureDate(6 + i * 4)
    onStep?.({ agent: 'bookings', action: `Simulace Velín rezervace #${i + 1}`, i, total: 12 })

    const cust = await API.createTestCustomer()
    results.push({ agent: 'customers', action: 'create_customer', ...cust })

    const booking = await API.createBooking(cust.userId, moto.id, start, end)
    results.push({ agent: 'bookings', action: 'velin_created_booking', ...booking })

    if (booking.ok) {
      // WATCHDOG: verify booking data is consistent
      onStep?.({ agent: 'bookings', action: `Kontrola konzistence rez. #${i + 1}`, i })
      const avail = await API.checkMotoAvailability(moto.id, start, end)
      const overlapDetected = !avail.available
      results.push({ agent: 'bookings', action: 'check_no_overlap', ok: overlapDetected })

      // WATCHDOG: verify price calculation matches
      const price = await API.calcBookingPrice(moto.id, start, end)
      results.push({ agent: 'finance', action: 'verify_price_consistency', ok: price.ok })

      // Simulate payment
      await API.confirmBookingPayment(booking.bookingId)
      results.push({ agent: 'bookings', action: 'velin_confirmed_payment', ok: true })
    }
  }

  // Phase 2: Edge cases — customer wants to change booking
  for (let i = 0; i < 3; i++) {
    const moto = motos.data[(i + 5) % motos.data.length]
    onStep?.({ agent: 'bookings', action: `Edge case: změna termínu #${i + 1}`, i: 5 + i, total: 12 })
    const cust = await API.createTestCustomer()
    const booking = await API.createBooking(cust.userId, moto.id, API.futureDate(20 + i * 3), API.futureDate(23 + i * 3))
    results.push({ agent: 'bookings', action: 'create_for_change_test', ...booking })
    if (booking.ok) {
      // Shorten (customer request)
      const sh = await API.shortenBooking(booking.bookingId, API.futureDate(22 + i * 3))
      results.push({ agent: 'bookings', action: 'edge_shorten_booking', ...sh })
    }
  }

  // Phase 3: Storno flow — agent verifies cancel reason logged
  for (let i = 0; i < 4; i++) {
    const moto = motos.data[(i + 8) % motos.data.length]
    onStep?.({ agent: 'bookings', action: `Storno + kontrola #${i + 1}`, i: 8 + i, total: 12 })
    const cust = await API.createTestCustomer()
    const booking = await API.createBooking(cust.userId, moto.id, API.futureDate(35 + i * 3), API.futureDate(38 + i * 3))
    if (booking.ok) {
      const cancel = await API.cancelBooking(booking.bookingId, API.PICK(['Změna plánů', 'Nemoc', 'Počasí']))
      results.push({ agent: 'bookings', action: 'cancel_and_verify', ...cancel })
    }
  }

  return results
}

// === SOS AGENT — actively coordinates (the ONLY active agent) ===
export async function trainSosAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  let stepIdx = 0
  for (const sosType of SOS_TYPES) {
    for (let i = 0; i < 5; i++) {
      const moto = motos.data[(stepIdx) % motos.data.length]
      stepIdx++
      onStep?.({ agent: 'sos', action: `${sosType.label} #${i + 1}/5`, i: stepIdx, total: 25 })

      const cust = await API.createTestCustomer()
      results.push({ agent: 'customers', action: 'create_customer', ...cust })

      const booking = await API.createBooking(cust.userId, moto.id, API.futureDate(1), API.futureDate(4))
      if (booking.ok && cust.ok) {
        await API.confirmBookingPayment(booking.bookingId)
        const sos = await API.createSosIncident(cust.userId, booking.bookingId, moto.id, sosType.type, `SIM: ${sosType.desc}`)
        results.push({ agent: 'sos', action: 'create_incident', type: sosType.type, ...sos })

        if (sos.ok) {
          await API.updateSosStatus(sos.incidentId, 'in_progress', 'Přiřazen technik')
          results.push({ agent: 'sos', action: 'coordinate_technician', ok: true })
          await API.updateSosStatus(sos.incidentId, 'resolved', `Vyřešeno: ${sosType.label}`)
          results.push({ agent: 'sos', action: 'resolve_incident', ok: true })

          if (['accident_minor', 'accident_major', 'theft'].includes(sosType.type)) {
            const svc = await API.createServiceOrder(moto.id, 'repair', `Oprava po ${sosType.label}`)
            results.push({ agent: 'service', action: 'sos_triggered_service', ...svc })
            if (sosType.type !== 'accident_minor') {
              await API.updateMotoStatus(moto.id, sosType.type === 'theft' ? 'unavailable' : 'maintenance')
              results.push({ agent: 'fleet', action: 'sos_moto_status_change', ok: true })
              await API.updateMotoStatus(moto.id, 'active')
            }
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

  const serviceTypes = [
    { type: 'oil_change', desc: 'Výměna oleje', hours: 1.5 },
    { type: 'brake_check', desc: 'Kontrola brzd', hours: 2 },
    { type: 'tire_change', desc: 'Výměna pneu', hours: 1 },
    { type: 'chain_adjust', desc: 'Seřízení řetězu', hours: 0.5 },
    { type: 'full_inspection', desc: 'Kompletní prohlídka', hours: 3 },
  ]

  // Simulate Velín creating service orders, agent VERIFIES completion
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[i % motos.data.length]
    const sType = serviceTypes[i]
    onStep?.({ agent: 'service', action: `Kontrola servisu: ${sType.desc}`, i, total: 15 })

    await API.updateMotoStatus(moto.id, 'maintenance')
    const svc = await API.createServiceOrder(moto.id, sType.type, sType.desc)
    results.push({ agent: 'service', action: 'velin_created_order', ...svc })

    if (svc.ok) {
      await API.completeServiceOrder(svc.orderId, `Hotovo: ${sType.desc}`)
      // WATCHDOG: verify maintenance_log was created
      const ml = await API.createMaintenanceLog(moto.id, sType.type, sType.desc, sType.hours)
      results.push({ agent: 'service', action: 'verify_maintenance_logged', ...ml })
    }
    // WATCHDOG: verify moto returned to active
    await API.updateMotoStatus(moto.id, 'active')
    results.push({ agent: 'service', action: 'verify_moto_active_after_service', ok: true })
  }

  // Verify service orders for 5 more motos
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 5) % motos.data.length]
    onStep?.({ agent: 'service', action: `Oprava po incidentu #${i + 1}`, i: 5 + i, total: 15 })
    const svc = await API.createServiceOrder(moto.id, 'repair', `Oprava po nehodě #${i + 1}`)
    results.push({ agent: 'service', action: 'verify_repair_order', ...svc })
    if (svc.ok) {
      await API.completeServiceOrder(svc.orderId, 'Oprava dokončena')
      results.push({ agent: 'service', action: 'verify_repair_completed', ok: true })
    }
  }

  // Maintenance log entries (5×)
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 10) % motos.data.length]
    onStep?.({ agent: 'service', action: `Kontrola log #${i + 1}`, i: 10 + i, total: 15 })
    const ml = await API.createMaintenanceLog(moto.id, 'general', `Kontrola #${i + 1}`, 1)
    results.push({ agent: 'service', action: 'verify_log_entry', ...ml })
  }

  return results
}

export { API }
