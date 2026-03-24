// AI Training Scenarios Part 1 — PER-AGENT training programs
// Each agent has required volume: min actions to reach "trained" state
// Scenarios call REAL Supabase API (same as motogo-app)
import * as API from './aiTrainingHelpers'

// How many successful actions each agent needs to reach confidence
export const AGENT_VOLUMES = {
  bookings:  { min: 25, label: 'Rezervace (create, cancel, extend, shorten, pay)' },
  fleet:     { min: 15, label: 'Flotila (dostupnost, stavy motorek)' },
  customers: { min: 15, label: 'Zákazníci (registrace, profily, komunikace)' },
  finance:   { min: 15, label: 'Finance (ceny, fakturace)' },
  service:   { min: 15, label: 'Servis (zakázky, údržba, díly)' },
  sos:       { min: 25, label: 'SOS (5× typ: porucha, defekt, nehoda_lehká, nehoda_těžká, krádež)' },
  eshop:     { min: 10, label: 'E-shop (objednávky, promo kódy)' },
  hr:        { min: 10, label: 'HR (směny, docházka)' },
  analytics: { min: 10, label: 'Analytika (reporty, predikce)' },
  cms:       { min: 8,  label: 'CMS (nastavení, šablony)' },
  government:{ min: 5,  label: 'Státní správa (STK, pojistky)' },
}

// SOS types that must each have 5 incidents
export const SOS_TYPES = [
  { type: 'breakdown_minor', label: 'Porucha', desc: 'Motorka nechce nastartovat' },
  { type: 'defect_question', label: 'Defekt pneu', desc: 'Píchlá zadní pneumatika' },
  { type: 'accident_minor', label: 'Lehká nehoda', desc: 'Drobná kolize, škrábance' },
  { type: 'accident_major', label: 'Těžká nehoda', desc: 'Vážná nehoda, motorka nepojízdná' },
  { type: 'theft', label: 'Krádež', desc: 'Motorka odcizena z parkoviště' },
]

// === BOOKINGS AGENT TRAINING ===
// Creates 5 full booking lifecycles + 3 cancellations + 2 extends + 2 shortens
export async function trainBookingsAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok || !motos.data.length) return [{ ok: false, error: 'Žádné motorky' }]

  // 5× full booking: create → pay → complete
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[i % motos.data.length]
    const start = API.futureDate(3 + i * 4), end = API.futureDate(6 + i * 4)

    onStep?.({ agent: 'bookings', action: `Registrace zákazníka #${i + 1}`, i, total: 12 })
    const cust = await API.createTestCustomer()
    results.push({ agent: 'customers', action: 'create_customer', ...cust })

    onStep?.({ agent: 'bookings', action: `Kontrola dostupnosti ${moto.model}`, i })
    const avail = await API.checkMotoAvailability(moto.id, start, end)
    results.push({ agent: 'fleet', action: 'check_availability', ...avail })

    onStep?.({ agent: 'bookings', action: `Kalkulace ceny ${moto.model}`, i })
    const price = await API.calcBookingPrice(moto.id, start, end)
    results.push({ agent: 'finance', action: 'calc_price', ...price })

    onStep?.({ agent: 'bookings', action: `Vytvoření rezervace ${moto.model} ${start}→${end}`, i })
    const booking = await API.createBooking(cust.userId, moto.id, start, end)
    results.push({ agent: 'bookings', action: 'create_booking', ...booking })

    if (booking.ok) {
      onStep?.({ agent: 'bookings', action: `Potvrzení platby rez. #${i + 1}`, i })
      const pay = await API.confirmBookingPayment(booking.bookingId)
      results.push({ agent: 'bookings', action: 'confirm_payment', ...pay })
    }
  }

  // 3× cancel: create → cancel
  for (let i = 0; i < 3; i++) {
    const moto = motos.data[(i + 5) % motos.data.length]
    const start = API.futureDate(20 + i * 3), end = API.futureDate(23 + i * 3)

    onStep?.({ agent: 'bookings', action: `Storno scénář #${i + 1}`, i: 5 + i, total: 12 })
    const cust = await API.createTestCustomer()
    results.push({ agent: 'customers', action: 'create_customer', ...cust })

    const booking = await API.createBooking(cust.userId, moto.id, start, end)
    results.push({ agent: 'bookings', action: 'create_booking', ...booking })

    if (booking.ok) {
      const cancel = await API.cancelBooking(booking.bookingId, API.PICK(['Změna plánů', 'Nemoc', 'Počasí']))
      results.push({ agent: 'bookings', action: 'cancel_booking', ...cancel })
    }
  }

  // 2× extend
  for (let i = 0; i < 2; i++) {
    const moto = motos.data[(i + 8) % motos.data.length]
    const start = API.futureDate(35 + i * 5), end = API.futureDate(38 + i * 5)

    onStep?.({ agent: 'bookings', action: `Prodloužení scénář #${i + 1}`, i: 8 + i, total: 12 })
    const cust = await API.createTestCustomer()
    const booking = await API.createBooking(cust.userId, moto.id, start, end)
    results.push({ agent: 'bookings', action: 'create_booking', ...booking })

    if (booking.ok) {
      await API.confirmBookingPayment(booking.bookingId)
      const ext = await API.extendBooking(booking.bookingId, API.futureDate(41 + i * 5))
      results.push({ agent: 'bookings', action: 'extend_booking', ...ext })
    }
  }

  // 2× shorten
  for (let i = 0; i < 2; i++) {
    const moto = motos.data[(i + 10) % motos.data.length]
    const start = API.futureDate(50 + i * 5), end = API.futureDate(55 + i * 5)

    onStep?.({ agent: 'bookings', action: `Zkrácení scénář #${i + 1}`, i: 10 + i, total: 12 })
    const cust = await API.createTestCustomer()
    const booking = await API.createBooking(cust.userId, moto.id, start, end)
    results.push({ agent: 'bookings', action: 'create_booking', ...booking })

    if (booking.ok) {
      await API.confirmBookingPayment(booking.bookingId)
      const sh = await API.shortenBooking(booking.bookingId, API.futureDate(52 + i * 5))
      results.push({ agent: 'bookings', action: 'shorten_booking', ...sh })
    }
  }

  return results
}

// === SOS AGENT TRAINING ===
// 5× each SOS type = 25 incidents, each needs a booking first
export async function trainSosAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  let stepIdx = 0
  for (const sosType of SOS_TYPES) {
    for (let i = 0; i < 5; i++) {
      const moto = motos.data[(stepIdx) % motos.data.length]
      const start = API.futureDate(1), end = API.futureDate(4)
      stepIdx++

      onStep?.({ agent: 'sos', action: `${sosType.label} #${i + 1}/5`, i: stepIdx, total: 25 })

      // Create customer + booking (prerequisite)
      const cust = await API.createTestCustomer()
      results.push({ agent: 'customers', action: 'create_customer', ...cust })

      const booking = await API.createBooking(cust.userId, moto.id, start, end)
      results.push({ agent: 'bookings', action: 'create_booking', ...booking })

      if (booking.ok && cust.ok) {
        await API.confirmBookingPayment(booking.bookingId)

        // Create SOS incident
        const sos = await API.createSosIncident(
          cust.userId, booking.bookingId, moto.id,
          sosType.type, `SIM: ${sosType.desc} — test #${i + 1}`
        )
        results.push({ agent: 'sos', action: 'create_incident', type: sosType.type, ...sos })

        if (sos.ok) {
          // Progress: reported → investigating → resolved
          await API.updateSosStatus(sos.incidentId, 'investigating', 'Přiřazen technik')
          results.push({ agent: 'sos', action: 'assign_technician', ok: true })

          await API.updateSosStatus(sos.incidentId, 'resolved', `Vyřešeno: ${sosType.label}`)
          results.push({ agent: 'sos', action: 'resolve_incident', ok: true })

          // If accident/theft → create service order + update moto
          if (['accident_minor', 'accident_major', 'theft'].includes(sosType.type)) {
            const svc = await API.createServiceOrder(moto.id, 'repair', `Oprava po ${sosType.label}`)
            results.push({ agent: 'service', action: 'create_service_order', ...svc })

            if (sosType.type === 'theft') {
              await API.updateMotoStatus(moto.id, 'stolen')
              results.push({ agent: 'fleet', action: 'update_moto_stolen', ok: true })
              // Restore for next tests
              await API.updateMotoStatus(moto.id, 'available')
            } else if (sosType.type === 'accident_major') {
              await API.updateMotoStatus(moto.id, 'maintenance')
              results.push({ agent: 'fleet', action: 'update_moto_maintenance', ok: true })
              await API.updateMotoStatus(moto.id, 'available')
            }
          }
        }
      }
    }
  }
  return results
}

// === SERVICE AGENT TRAINING ===
// 5× planned maintenance + 5× repair after SOS + 5× parts order
export async function trainServiceAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  const serviceTypes = [
    { type: 'oil_change', desc: 'Výměna oleje a filtrů', hours: 1.5 },
    { type: 'brake_check', desc: 'Kontrola a výměna brzdových destiček', hours: 2 },
    { type: 'tire_change', desc: 'Výměna pneumatik', hours: 1 },
    { type: 'chain_adjust', desc: 'Seřízení a mazání řetězu', hours: 0.5 },
    { type: 'full_inspection', desc: 'Kompletní technická prohlídka', hours: 3 },
  ]

  // 5× planned maintenance
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[i % motos.data.length]
    const sType = serviceTypes[i]

    onStep?.({ agent: 'service', action: `Plánovaný servis: ${sType.desc}`, i, total: 15 })

    await API.updateMotoStatus(moto.id, 'maintenance')
    results.push({ agent: 'fleet', action: 'set_maintenance', ok: true })

    const svc = await API.createServiceOrder(moto.id, sType.type, sType.desc)
    results.push({ agent: 'service', action: 'create_service_order', ...svc })

    if (svc.ok) {
      const complete = await API.completeServiceOrder(svc.orderId, `Hotovo: ${sType.desc}`)
      results.push({ agent: 'service', action: 'complete_service', ...complete })
    }

    const ml = await API.createMaintenanceLog(moto.id, sType.type, sType.desc, sType.hours)
    results.push({ agent: 'service', action: 'create_maintenance_log', ...ml })

    await API.updateMotoStatus(moto.id, 'available')
    results.push({ agent: 'fleet', action: 'set_available', ok: true })
  }

  // 5× repair after incident
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 5) % motos.data.length]
    onStep?.({ agent: 'service', action: `Oprava po incidentu #${i + 1}`, i: 5 + i, total: 15 })

    const svc = await API.createServiceOrder(moto.id, 'repair', `Oprava po nehodě — test #${i + 1}`)
    results.push({ agent: 'service', action: 'create_repair_order', ...svc })

    if (svc.ok) {
      await API.completeServiceOrder(svc.orderId, 'Oprava dokončena')
      results.push({ agent: 'service', action: 'complete_repair', ok: true })
    }
  }

  // 5× maintenance log entries
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 10) % motos.data.length]
    onStep?.({ agent: 'service', action: `Zápis do maintenance logu #${i + 1}`, i: 10 + i, total: 15 })
    const ml = await API.createMaintenanceLog(moto.id, 'general', `Pravidelná kontrola #${i + 1}`, 1)
    results.push({ agent: 'service', action: 'maintenance_log', ...ml })
  }

  return results
}

export { API }
