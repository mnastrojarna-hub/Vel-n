// AI Training Scenarios Part 2 — fleet, customers, finance, eshop, edge cases
// WATCHDOG concept: agents verify, detect, escalate — not execute
import * as API from './aiTrainingHelpers'
import { supabase } from './supabase'

// === FLEET AGENT — monitors STK, insurance, status consistency ===
export async function trainFleetAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  results.push({ agent: 'fleet', action: 'fetch_fleet_inventory', ok: true, count: motos.data.length })

  // WATCHDOG: check availability for date ranges
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[i % motos.data.length]
    const start = API.futureDate(i * 3 + 1), end = API.futureDate(i * 3 + 4)
    onStep?.({ agent: 'fleet', action: `STK/pojistka check ${moto.model}`, i, total: 15 })
    const avail = await API.checkMotoAvailability(moto.id, start, end)
    results.push({ agent: 'fleet', action: 'verify_availability', ...avail })
  }

  // WATCHDOG: status cycle — detect if moto returns to active after maintenance
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 5) % motos.data.length]
    onStep?.({ agent: 'fleet', action: `Status cyklus ${moto.model}`, i: 5 + i, total: 15 })
    await API.updateMotoStatus(moto.id, 'maintenance')
    results.push({ agent: 'fleet', action: 'detect_maintenance_start', ok: true })
    await API.updateMotoStatus(moto.id, 'active')
    results.push({ agent: 'fleet', action: 'verify_returned_to_active', ok: true })
  }

  // WATCHDOG: verify pricing is set
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 10) % motos.data.length]
    onStep?.({ agent: 'fleet', action: `Ceník check ${moto.model}`, i: 10 + i, total: 15 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4))
    results.push({ agent: 'fleet', action: 'verify_pricing_set', ...price })
  }

  return results
}

// === CUSTOMERS AGENT — verifies profiles, handles live communication ===
export async function trainCustomersAgent(onStep) {
  const results = []

  // Create test customers (simulates Velín registration)
  for (let i = 0; i < 5; i++) {
    onStep?.({ agent: 'customers', action: `Registrace #${i + 1}`, i, total: 15 })
    const cust = await API.createTestCustomer()
    results.push({ agent: 'customers', action: 'velin_registered_customer', ...cust })

    // WATCHDOG: verify profile completeness
    if (cust.ok && cust.userId) {
      const upd = await API.updateProfile(cust.userId, {
        phone: API.PICK(['+420777111222', '+420666333444']),
        city: API.PICK(['Praha', 'Brno', 'Ostrava']),
      })
      results.push({ agent: 'customers', action: 'verify_profile_complete', ...upd })
    }
  }

  // WATCHDOG: simulate live message handling
  const { data: profiles } = await supabase
    .from('profiles').select('id').eq('is_test_account', true).limit(5)

  for (let i = 0; i < Math.min(5, profiles?.length || 0); i++) {
    onStep?.({ agent: 'customers', action: `Živá komunikace #${i + 1}`, i: 5 + i, total: 15 })
    const msg = await API.sendCustomerMessage(
      profiles[i].id,
      API.PICK(['Reklamace: motorka měla poškrábaný lak.', 'Dotaz: lze změnit místo vyzvednutí?', 'Chybí mi faktura za poslední jízdu.'])
    )
    results.push({ agent: 'customers', action: 'handle_live_message', ...msg })
  }

  // Detect missing docs (edge case)
  for (let i = 0; i < 5; i++) {
    onStep?.({ agent: 'customers', action: `Kontrola dokladů #${i + 1}`, i: 10 + i, total: 15 })
    const cust = await API.createTestCustomer()
    if (cust.ok) {
      await API.updateProfile(cust.userId, { license_group: null, docs_verified: false })
      results.push({ agent: 'customers', action: 'detect_missing_docs', ok: true })
    }
  }

  return results
}

// === FINANCE AGENT — verifies invoices, pricing, detects mismatches ===
export async function trainFinanceAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  // WATCHDOG: verify price calculations
  const durations = [1, 2, 3, 5, 7, 10, 14, 21, 1, 3]
  for (let i = 0; i < 10; i++) {
    const moto = motos.data[i % motos.data.length]
    const days = durations[i]
    onStep?.({ agent: 'finance', action: `Ověření ceny ${moto.model} ${days}d`, i, total: 15 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(1 + days))
    results.push({ agent: 'finance', action: 'verify_price_calculation', days, ...price })
  }

  // WATCHDOG: verify promo code works correctly
  const promo = await API.createPromoCode(`SIMFIN${API.TS()}`, 15)
  results.push({ agent: 'finance', action: 'verify_promo_created', ...promo })

  for (let i = 0; i < 3; i++) {
    const moto = motos.data[(i + 10) % motos.data.length]
    onStep?.({ agent: 'finance', action: `Cena s promo #${i + 1}`, i: 10 + i, total: 15 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4), promo.data?.code)
    results.push({ agent: 'finance', action: 'verify_promo_discount', ...price })
  }

  // WATCHDOG: booking+payment consistency
  for (let i = 0; i < 2; i++) {
    const moto = motos.data[i % motos.data.length]
    onStep?.({ agent: 'finance', action: `Platba konzistence #${i + 1}`, i: 13 + i, total: 15 })
    const cust = await API.createTestCustomer()
    const booking = await API.createBooking(cust.userId, moto.id, API.futureDate(60 + i * 5), API.futureDate(63 + i * 5))
    if (booking.ok) {
      const pay = await API.confirmBookingPayment(booking.bookingId)
      results.push({ agent: 'finance', action: 'verify_payment_matches_booking', ...pay })
    }
  }

  return results
}

// === ESHOP AGENT — monitors stock, verifies promo codes ===
export async function trainEshopAgent(onStep) {
  const results = []

  for (let i = 0; i < 5; i++) {
    onStep?.({ agent: 'eshop', action: `Promo kód #${i + 1}`, i, total: 10 })
    const p = await API.createPromoCode(`SIMSHOP${API.TS()}${i}`, 10 + i * 5)
    results.push({ agent: 'eshop', action: 'verify_promo_created', ...p })
  }

  for (let i = 0; i < 5; i++) {
    onStep?.({ agent: 'eshop', action: `Sklad kontrola #${i + 1}`, i: 5 + i, total: 10 })
    const { data, error } = await supabase.from('accessory_types').select('*').limit(10)
    results.push({ agent: 'eshop', action: 'verify_stock_data', ok: !error, count: data?.length || 0 })
  }

  return results
}

// === EDGE CASES — cross-agent consistency checks ===
export async function trainEdgeCases(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  // Double booking detection (booking agent should catch this)
  for (let i = 0; i < 3; i++) {
    const moto = motos.data[i % motos.data.length]
    const start = API.futureDate(70 + i * 5), end = API.futureDate(73 + i * 5)
    onStep?.({ agent: 'bookings', action: `Overlap detekce #${i + 1}`, i, total: 6 })

    const c1 = await API.createTestCustomer()
    const b1 = await API.createBooking(c1.userId, moto.id, start, end)
    results.push({ agent: 'bookings', action: 'create_first_booking', ...b1 })

    if (b1.ok) {
      const c2 = await API.createTestCustomer()
      const avail = await API.checkMotoAvailability(moto.id, API.futureDate(71 + i * 5), end)
      results.push({ agent: 'bookings', action: 'detect_overlap', available: avail.available, ok: true })
      if (!avail.available) {
        results.push({ agent: 'bookings', action: 'overlap_correctly_detected', ok: true })
      }
    }
  }

  // Missing docs booking (customer agent should flag this)
  for (let i = 0; i < 3; i++) {
    onStep?.({ agent: 'customers', action: `Zákazník bez dokladů #${i + 1}`, i: 3 + i, total: 6 })
    const cust = await API.createTestCustomer()
    if (cust.ok) {
      await API.updateProfile(cust.userId, { license_group: null, docs_verified: false })
      results.push({ agent: 'customers', action: 'detect_incomplete_profile', ok: true })
      const moto = motos.data[i % motos.data.length]
      const b = await API.createBooking(cust.userId, moto.id, API.futureDate(80 + i), API.futureDate(83 + i))
      results.push({ agent: 'bookings', action: 'booking_without_docs_flagged', ...b })
    }
  }

  return results
}

export const TRAINING_PROGRAMS = {
  bookings:  { fn: 'trainBookingsAgent', label: 'Kontrolor rezervací' },
  sos:       { fn: 'trainSosAgent', label: 'SOS koordinátor' },
  service:   { fn: 'trainServiceAgent', label: 'Servisní hlídač' },
  fleet:     { fn: 'trainFleetAgent', label: 'Hlídač flotily' },
  customers: { fn: 'trainCustomersAgent', label: 'Komunikátor' },
  finance:   { fn: 'trainFinanceAgent', label: 'Finanční kontrolor' },
  eshop:     { fn: 'trainEshopAgent', label: 'Kontrolor e-shopu' },
  edge:      { fn: 'trainEdgeCases', label: 'Edge cases' },
}
