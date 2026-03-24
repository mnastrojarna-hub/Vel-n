// AI Training Scenarios Part 2 — fleet, customers, finance, eshop, edge cases
// All calls go through REAL Supabase API
import * as API from './aiTrainingHelpers'
import { supabase } from './supabase'

// === FLEET AGENT TRAINING ===
// Check availability, update statuses, verify pricing
export async function trainFleetAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  results.push({ agent: 'fleet', action: 'fetch_fleet', ok: true, count: motos.data.length })

  // 5× availability checks
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[i % motos.data.length]
    const start = API.futureDate(i * 3 + 1), end = API.futureDate(i * 3 + 4)
    onStep?.({ agent: 'fleet', action: `Dostupnost ${moto.model} ${start}→${end}`, i, total: 15 })
    const avail = await API.checkMotoAvailability(moto.id, start, end)
    results.push({ agent: 'fleet', action: 'check_availability', ...avail })
  }

  // 5× status cycle: available → maintenance → available
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 5) % motos.data.length]
    onStep?.({ agent: 'fleet', action: `Status cyklus ${moto.model}`, i: 5 + i, total: 15 })
    const r1 = await API.updateMotoStatus(moto.id, 'maintenance')
    results.push({ agent: 'fleet', action: 'set_maintenance', ...r1 })
    const r2 = await API.updateMotoStatus(moto.id, 'available')
    results.push({ agent: 'fleet', action: 'set_available', ...r2 })
  }

  // 5× price calculations
  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 10) % motos.data.length]
    onStep?.({ agent: 'fleet', action: `Ceník ${moto.model}`, i: 10 + i, total: 15 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4))
    results.push({ agent: 'fleet', action: 'calc_price', ...price })
  }

  return results
}

// === CUSTOMERS AGENT TRAINING ===
// Register, update profile, send messages
export async function trainCustomersAgent(onStep) {
  const results = []

  // 8× register customers
  for (let i = 0; i < 8; i++) {
    onStep?.({ agent: 'customers', action: `Registrace zákazníka #${i + 1}`, i, total: 15 })
    const cust = await API.createTestCustomer()
    results.push({ agent: 'customers', action: 'create_customer', ...cust })

    // Update profile for each
    if (cust.ok && cust.userId) {
      onStep?.({ agent: 'customers', action: `Aktualizace profilu #${i + 1}`, i })
      const upd = await API.updateProfile(cust.userId, {
        phone: API.PICK(['+420777111222', '+420666333444', '+420605987654']),
        city: API.PICK(['Praha', 'Brno', 'Ostrava', 'Plzeň']),
      })
      results.push({ agent: 'customers', action: 'update_profile', ...upd })
    }
  }

  // 5× admin messages (simulate customer communication)
  const { data: profiles } = await supabase
    .from('profiles').select('id').eq('is_test_account', true).limit(5)

  for (let i = 0; i < Math.min(5, profiles?.length || 0); i++) {
    onStep?.({ agent: 'customers', action: `Zpráva zákazníkovi #${i + 1}`, i: 8 + i, total: 15 })
    const msg = await API.sendAdminMessage(
      profiles[i].id,
      API.PICK(['Informace k rezervaci', 'Připomínka dokladů', 'Potvrzení vrácení']),
      'Toto je testovací zpráva z AI tréninku.'
    )
    results.push({ agent: 'customers', action: 'send_message', ...msg })
  }

  return results
}

// === FINANCE AGENT TRAINING ===
// Price calculations, booking prices for various durations
export async function trainFinanceAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  // 10× price calculations (different motos, durations)
  const durations = [1, 2, 3, 5, 7, 10, 14, 21, 1, 3]
  for (let i = 0; i < 10; i++) {
    const moto = motos.data[i % motos.data.length]
    const days = durations[i]
    onStep?.({ agent: 'finance', action: `Cena ${moto.model} na ${days} dní`, i, total: 15 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(1 + days))
    results.push({ agent: 'finance', action: 'calc_price', days, ...price })
  }

  // 3× price with promo code
  const promo = await API.createPromoCode(`SIMFIN${API.TS()}`, 15)
  results.push({ agent: 'eshop', action: 'create_promo', ...promo })

  for (let i = 0; i < 3; i++) {
    const moto = motos.data[(i + 10) % motos.data.length]
    onStep?.({ agent: 'finance', action: `Cena s promo kódem #${i + 1}`, i: 10 + i, total: 15 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4), promo.data?.code)
    results.push({ agent: 'finance', action: 'calc_price_promo', ...price })
  }

  // 2× full booking with payment
  for (let i = 0; i < 2; i++) {
    const moto = motos.data[i % motos.data.length]
    onStep?.({ agent: 'finance', action: `Platba za rezervaci #${i + 1}`, i: 13 + i, total: 15 })
    const cust = await API.createTestCustomer()
    const booking = await API.createBooking(cust.userId, moto.id, API.futureDate(60 + i * 5), API.futureDate(63 + i * 5))
    results.push({ agent: 'bookings', action: 'create_booking', ...booking })
    if (booking.ok) {
      const pay = await API.confirmBookingPayment(booking.bookingId)
      results.push({ agent: 'finance', action: 'confirm_payment', ...pay })
    }
  }

  return results
}

// === ESHOP AGENT TRAINING ===
export async function trainEshopAgent(onStep) {
  const results = []

  // 5× promo codes
  for (let i = 0; i < 5; i++) {
    onStep?.({ agent: 'eshop', action: `Promo kód #${i + 1}`, i, total: 10 })
    const p = await API.createPromoCode(`SIMSHOP${API.TS()}${i}`, 10 + i * 5)
    results.push({ agent: 'eshop', action: 'create_promo', ...p })
  }

  // 5× fetch accessory types (read operations)
  for (let i = 0; i < 5; i++) {
    onStep?.({ agent: 'eshop', action: `Kontrola sortimentu #${i + 1}`, i: 5 + i, total: 10 })
    const { data, error } = await supabase.from('accessory_types').select('*').limit(10)
    results.push({ agent: 'eshop', action: 'get_accessory_types', ok: !error, count: data?.length || 0 })
  }

  return results
}

// === EDGE CASES — overlap, missing docs, wrong license ===
export async function trainEdgeCases(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  // 3× double booking attempt (same moto, overlapping dates)
  for (let i = 0; i < 3; i++) {
    const moto = motos.data[i % motos.data.length]
    const start = API.futureDate(70 + i * 5), end = API.futureDate(73 + i * 5)
    onStep?.({ agent: 'bookings', action: `Overlap test #${i + 1}`, i, total: 6 })

    const c1 = await API.createTestCustomer()
    const b1 = await API.createBooking(c1.userId, moto.id, start, end)
    results.push({ agent: 'bookings', action: 'create_booking_1', ...b1 })

    if (b1.ok) {
      // Second booking same moto, overlapping
      const c2 = await API.createTestCustomer()
      const overlap = API.futureDate(71 + i * 5)
      const avail = await API.checkMotoAvailability(moto.id, overlap, end)
      results.push({ agent: 'fleet', action: 'check_overlap', available: avail.available, ok: true })

      // Should detect conflict
      if (!avail.available) {
        results.push({ agent: 'bookings', action: 'overlap_detected', ok: true })
      } else {
        // If somehow available, create and test
        const b2 = await API.createBooking(c2.userId, moto.id, overlap, end)
        results.push({ agent: 'bookings', action: 'overlap_booking', ...b2 })
      }
    }
  }

  // 3× booking without docs (customer without license)
  for (let i = 0; i < 3; i++) {
    onStep?.({ agent: 'customers', action: `Zákazník bez dokladů #${i + 1}`, i: 3 + i, total: 6 })
    const cust = await API.createTestCustomer()
    if (cust.ok && cust.userId) {
      // Clear license to simulate missing docs
      await API.updateProfile(cust.userId, { license_group: null, docs_verified: false })
      results.push({ agent: 'customers', action: 'missing_docs_customer', ok: true })

      // Try booking — should still work at DB level but agent should flag it
      const moto = motos.data[i % motos.data.length]
      const b = await API.createBooking(cust.userId, moto.id, API.futureDate(80 + i), API.futureDate(83 + i))
      results.push({ agent: 'bookings', action: 'booking_without_docs', ...b })
    }
  }

  return results
}

// All training functions registry
export const TRAINING_PROGRAMS = {
  bookings:  { fn: 'trainBookingsAgent', label: '📅 Rezervace', file: 'scenarios' },
  sos:       { fn: 'trainSosAgent', label: '🚨 SOS koordinátor', file: 'scenarios' },
  service:   { fn: 'trainServiceAgent', label: '🔧 Servis', file: 'scenarios' },
  fleet:     { fn: 'trainFleetAgent', label: '🏍️ Flotila', file: 'extra' },
  customers: { fn: 'trainCustomersAgent', label: '👥 Zákazníci', file: 'extra' },
  finance:   { fn: 'trainFinanceAgent', label: '💰 Finance', file: 'extra' },
  eshop:     { fn: 'trainEshopAgent', label: '🛒 E-shop', file: 'extra' },
  edge:      { fn: 'trainEdgeCases', label: '⚠️ Edge cases', file: 'extra' },
}
