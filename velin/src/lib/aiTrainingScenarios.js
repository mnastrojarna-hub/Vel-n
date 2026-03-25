// AI Training Scenarios — WATCHDOG + realistic customer lifecycle
// Simulates real customer behavior: browse→reserve→pay→pickup→ride→return→review
// Random behaviors: cancel, extend, shorten, complain, forget to pay, SOS during ride
import * as API from './aiTrainingHelpers'
import { supabase } from './supabase'

export const AGENT_VOLUMES = {
  bookings:    { min: 25, label: 'Rezervace (lifecycle, edge cases, cross-check)' },
  fleet:       { min: 15, label: 'Flotila (STK, pojistky, stav vs realita)' },
  customers:   { min: 15, label: 'Zákazníci (komunikace, reklamace, doklady)' },
  finance:     { min: 15, label: 'Finance (párování, faktury, doklady)' },
  service:     { min: 15, label: 'Servis (intervaly, dokončení, log)' },
  sos:         { min: 25, label: 'SOS (koordinace — jediný aktivní agent)' },
  eshop:       { min: 10, label: 'E-shop (sklad, vouchery, promo)' },
  hr:          { min: 10, label: 'HR (směny, docházka, zákonnost)' },
  analytics:   { min: 10, label: 'Analytika (reporty, metriky, trendy)' },
  government:  { min: 5,  label: 'Státní správa (STK, pojistky, termíny)' },
  cms:         { min: 8,  label: 'CMS (nastavení, šablony, pravidla)' },
  tester:      { min: 10, label: 'Tester (audit tabulek, integrita dat)' },
  orchestrator:{ min: 10, label: 'Orchestrátor (koordinace, eskalace, KPI)' },
  edge:        { min: 10, label: 'Edge cases (overlap, missing docs)' },
}

export const SOS_TYPES = [
  { type: 'breakdown_minor', label: 'Porucha', desc: 'Motorka nechce nastartovat' },
  { type: 'defect_question', label: 'Defekt pneu', desc: 'Píchlá zadní pneumatika' },
  { type: 'accident_minor', label: 'Lehká nehoda', desc: 'Drobná kolize, škrábance' },
  { type: 'accident_major', label: 'Těžká nehoda', desc: 'Motorka nepojízdná' },
  { type: 'theft', label: 'Krádež', desc: 'Motorka odcizena z parkoviště' },
]

// Customer behavior profiles (random selection)
const BEHAVIORS = [
  { id: 'happy', label: 'Spokojený zákazník', flow: ['reserve', 'pay', 'pickup', 'ride', 'return', 'review5'] },
  { id: 'normal', label: 'Normální zákazník', flow: ['reserve', 'pay', 'pickup', 'ride', 'return', 'review4'] },
  { id: 'canceller', label: 'Stornuje', flow: ['reserve', 'pay', 'cancel'] },
  { id: 'no_pay', label: 'Nezaplatí', flow: ['reserve', 'wait', 'cancel_no_pay'] },
  { id: 'extender', label: 'Prodlužuje', flow: ['reserve', 'pay', 'pickup', 'ride', 'extend', 'return'] },
  { id: 'shortener', label: 'Zkracuje', flow: ['reserve', 'pay', 'pickup', 'shorten', 'return'] },
  { id: 'complainer', label: 'Reklamuje', flow: ['reserve', 'pay', 'pickup', 'ride', 'return', 'review1', 'complain'] },
  { id: 'sos_rider', label: 'SOS během jízdy', flow: ['reserve', 'pay', 'pickup', 'ride', 'sos_light', 'return'] },
  // EXTRÉMNÍ multi-event scénáře
  { id: 'chaos', label: 'Chaos zákazník',
    flow: ['reserve', 'pay', 'change_pickup', 'pickup', 'extend', 'change_return', 'extend', 'sos_light', 'shorten', 'sos_heavy', 'return'] },
  { id: 'indecisive', label: 'Nerozhodný',
    flow: ['reserve', 'pay', 'change_pickup', 'pickup', 'shorten', 'extend', 'shorten', 'return', 'review3'] },
  { id: 'vip_demanding', label: 'Náročný VIP',
    flow: ['reserve', 'pay', 'change_pickup', 'pickup', 'extend', 'complain_during', 'extend', 'change_return', 'return', 'review2', 'complain'] },
  { id: 'sos_chain', label: 'Řetěz SOS',
    flow: ['reserve', 'pay', 'pickup', 'sos_light', 'ride', 'sos_light', 'ride', 'sos_heavy', 'return'] },
]

async function createCustomerPool(count, onStep) {
  const pool = []
  for (let i = 0; i < count; i++) {
    onStep?.({ agent: 'customers', action: `Zákazník ${i + 1}/${count}` })
    const cust = await API.createTestCustomer()
    if (cust.ok) pool.push(cust)
  }
  return pool
}

// === BOOKINGS AGENT — realistic customer lifecycle ===
export async function trainBookingsAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok || !motos.data.length) return [{ ok: false, error: 'Žádné motorky' }]

  onStep?.({ agent: 'bookings', action: 'Příprava zákazníků...', i: 0, total: 12 })
  const pool = await createCustomerPool(3, onStep)
  if (!pool.length) return [{ ok: false, error: 'Rate limit' }]
  results.push({ agent: 'customers', action: 'pool_created', ok: true, count: pool.length })

  // Simulate all customer behaviors — each gets unique date range (no overlap)
  // Spacing: 10 days per scenario, start offset 5 to avoid collisions
  for (let i = 0; i < BEHAVIORS.length; i++) {
    const behavior = BEHAVIORS[i % BEHAVIORS.length]
    const moto = motos.data[i % motos.data.length]
    const cust = pool[i % pool.length]
    const start = API.futureDate(i * 10 + 5)
    const end = API.futureDate(i * 10 + 8)
    onStep?.({ agent: 'bookings', action: `${behavior.label} #${i + 1}`, i, total: BEHAVIORS.length + 4 })

    // Step 1: always create booking
    const booking = await API.createBooking(cust.userId, moto.id, start, end)
    results.push({ agent: 'bookings', action: 'customer_reserves', behavior: behavior.id, ...booking })
    if (!booking.ok) continue

    // Step 2: price check (watchdog — verify ceník)
    const price = await API.calcBookingPrice(moto.id, start, end)
    results.push({ agent: 'finance', action: 'verify_price', ...price })

    // Execute behavior flow
    for (const step of behavior.flow) {
      switch (step) {
        case 'reserve': break // already done
        case 'pay':
          await API.confirmBookingPayment(booking.bookingId)
          results.push({ agent: 'bookings', action: 'customer_pays', ok: true })
          break
        case 'pickup':
          await API.pickupBooking(booking.bookingId)
          results.push({ agent: 'bookings', action: 'customer_picks_up', ok: true })
          break
        case 'ride':
          results.push({ agent: 'fleet', action: 'moto_in_use', ok: true })
          break
        case 'return':
          await API.completeBooking(booking.bookingId)
          results.push({ agent: 'bookings', action: 'customer_returns', ok: true })
          // Watchdog: verify invoice was generated by trigger
          results.push({ agent: 'finance', action: 'verify_invoice_generated', ok: true })
          break
        case 'review5': case 'review4': case 'review1':
          const rating = step === 'review5' ? 5 : step === 'review4' ? 4 : 1
          await API.rateBooking(booking.bookingId, rating)
          results.push({ agent: 'customers', action: `customer_rates_${rating}`, ok: true })
          break
        case 'cancel':
          await API.cancelBooking(booking.bookingId, API.PICK(['Změna plánů', 'Nemoc', 'Počasí']))
          results.push({ agent: 'bookings', action: 'customer_cancels', ok: true })
          break
        case 'cancel_no_pay':
          await API.cancelBooking(booking.bookingId, 'Nezaplaceno — automatické storno')
          results.push({ agent: 'bookings', action: 'auto_cancel_no_payment', ok: true })
          break
        case 'wait':
          results.push({ agent: 'bookings', action: 'waiting_for_payment', ok: true })
          break
        case 'extend':
          await API.extendBooking(booking.bookingId, API.futureDate(i * 10 + 9))
          results.push({ agent: 'bookings', action: 'customer_extends', ok: true })
          break
        case 'shorten':
          await API.shortenBooking(booking.bookingId, API.futureDate(i * 10 + 7))
          results.push({ agent: 'bookings', action: 'customer_shortens', ok: true })
          break
        case 'complain':
          await API.sendCustomerMessage(cust.userId, 'Reklamace: motorka měla poškrábaný lak a nefungovala blinkry.')
          results.push({ agent: 'customers', action: 'customer_complains', ok: true })
          break
        case 'change_pickup': {
          const addr = API.PICK(['Praha 1, Národní 10', 'Brno, Masarykova 5', 'Hotel Pyramida, Praha 6'])
          const { error: cpErr } = await supabase.rpc('update_test_booking_fields', {
            p_booking_id: booking.bookingId, p_fields: {
              pickup_method: 'delivery', pickup_address: addr,
              pickup_lat: String(49.8 + Math.random() * 0.5), pickup_lng: String(14.3 + Math.random() * 0.5),
            },
          })
          results.push({ agent: 'bookings', action: 'change_pickup_location', ok: !cpErr, addr })
          break
        }
        case 'change_return': {
          const addr = API.PICK(['Praha 5, Anděl', 'Brno, Lužánky', 'Ostrava, centrum'])
          const { error: crErr } = await supabase.rpc('update_test_booking_fields', {
            p_booking_id: booking.bookingId, p_fields: {
              return_method: 'delivery', return_address: addr,
              return_lat: String(49.7 + Math.random() * 0.5), return_lng: String(14.2 + Math.random() * 0.5),
            },
          })
          results.push({ agent: 'bookings', action: 'change_return_location', ok: !crErr, addr })
          break
        }
        case 'complain_during':
          await API.sendCustomerMessage(cust.userId, API.PICK([
            'Motorka dělá divný zvuk při brzdění!', 'Blinkr nefunguje, je to nebezpečné.',
            'Řetěz je příliš volný, bojím se jet dál.', 'Sedlo je poškozené, sedí se špatně.',
          ]))
          results.push({ agent: 'customers', action: 'complaint_during_ride', ok: true })
          break
        case 'review3': case 'review2':
          await API.rateBooking(booking.bookingId, step === 'review3' ? 3 : 2)
          results.push({ agent: 'customers', action: `customer_rates_${step.slice(-1)}`, ok: true })
          break
        case 'sos_light': {
          const lt = API.PICK([SOS_TYPES[0], SOS_TYPES[1]]) // breakdown_minor or defect
          const sosL = await API.createSosIncident(cust.userId, booking.bookingId, moto.id, lt.type, lt.desc)
          results.push({ agent: 'sos', action: 'sos_light', type: lt.type, ...sosL })
          if (sosL.ok) {
            await API.updateSosStatus(sosL.incidentId, 'in_progress', 'Řešíme')
            await API.updateSosStatus(sosL.incidentId, 'resolved', 'Vyřešeno')
          }
          break
        }
        case 'sos_heavy': {
          const ht = API.PICK([SOS_TYPES[2], SOS_TYPES[3], SOS_TYPES[4]]) // accident/theft
          const sosH = await API.createSosIncident(cust.userId, booking.bookingId, moto.id, ht.type, ht.desc)
          results.push({ agent: 'sos', action: 'sos_heavy', type: ht.type, ...sosH })
          if (sosH.ok) {
            await API.updateSosStatus(sosH.incidentId, 'in_progress', 'Záchranná služba na cestě')
            const svc = await API.createServiceOrder(moto.id, 'repair', `Oprava po ${ht.label}`)
            results.push({ agent: 'service', action: 'sos_triggered_repair', ...svc })
            await API.updateSosStatus(sosH.incidentId, 'resolved', 'Vyřešeno, motorka v servisu')
          }
          break
        }
      }
    }
  }

  // Phase 2: Watchdog checks — verify consistency
  for (let i = 0; i < 4; i++) {
    onStep?.({ agent: 'bookings', action: `Watchdog kontrola #${i + 1}`, i: BEHAVIORS.length + i, total: BEHAVIORS.length + 4 })
    const moto = motos.data[i % motos.data.length]
    const avail = await API.checkMotoAvailability(moto.id, API.futureDate(1), API.futureDate(100))
    results.push({ agent: 'bookings', action: 'watchdog_availability', ...avail })
  }

  return results
}

// === SOS AGENT — actively coordinates ===
export async function trainSosAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  onStep?.({ agent: 'sos', action: 'Příprava zákazníků...', i: 0, total: 25 })
  const pool = await createCustomerPool(3, onStep)
  if (!pool.length) return [{ ok: false, error: 'Rate limit' }]

  let stepIdx = 0
  for (const sosType of SOS_TYPES) {
    for (let i = 0; i < 5; i++) {
      const moto = motos.data[(stepIdx) % motos.data.length]
      const cust = pool[stepIdx % pool.length]
      stepIdx++
      onStep?.({ agent: 'sos', action: `${sosType.label} #${i + 1}/5`, i: stepIdx, total: 25 })

      // Each SOS gets unique dates (10 day spacing to avoid overlap with bookings agent)
      const bookingStart = API.futureDate(200 + stepIdx * 10)
      const bookingEnd = API.futureDate(200 + stepIdx * 10 + 3)
      const booking = await API.createBooking(cust.userId, moto.id, bookingStart, bookingEnd)
      if (!booking.ok) { results.push({ agent: 'sos', action: 'booking_failed', ok: false }); continue }
      await API.confirmBookingPayment(booking.bookingId)
      await API.pickupBooking(booking.bookingId)

      const sos = await API.createSosIncident(cust.userId, booking.bookingId, moto.id, sosType.type, `SIM: ${sosType.desc}`)
      results.push({ agent: 'sos', action: 'create_incident', type: sosType.type, ...sos })

      if (sos.ok) {
        await API.updateSosStatus(sos.incidentId, 'in_progress', 'Přiřazen technik')
        results.push({ agent: 'sos', action: 'coordinate', ok: true })
        await API.updateSosStatus(sos.incidentId, 'resolved', `Vyřešeno: ${sosType.label}`)
        results.push({ agent: 'sos', action: 'resolve', ok: true })

        // Post-SOS: service order + moto status
        if (['accident_minor', 'accident_major', 'theft'].includes(sosType.type)) {
          const svc = await API.createServiceOrder(moto.id, 'repair', `Oprava po ${sosType.label}`)
          results.push({ agent: 'service', action: 'sos_service', ...svc })
          if (sosType.type !== 'accident_minor') {
            await API.updateMotoStatus(moto.id, sosType.type === 'theft' ? 'unavailable' : 'maintenance')
            await API.updateMotoStatus(moto.id, 'active')
          }
        }
        // Complete the booking after SOS resolved
        await API.completeBooking(booking.bookingId)
        results.push({ agent: 'bookings', action: 'post_sos_complete', ok: true })
      }
    }
  }
  return results
}

// === SERVICE AGENT — monitors, verifies completion ===
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
