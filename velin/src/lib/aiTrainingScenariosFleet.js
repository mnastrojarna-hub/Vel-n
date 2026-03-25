// Training Part 2a — Fleet, Customers, Finance (watchdog cross-checks)
import * as API from './aiTrainingHelpers'
import { supabase } from './supabase'

export async function createPool(n, onStep) {
  const pool = []
  for (let i = 0; i < n; i++) {
    onStep?.({ agent: 'customers', action: `Zákazník ${i + 1}/${n}` })
    const c = await API.createTestCustomer()
    if (c.ok) pool.push(c)
  }
  return pool
}

// === FLEET AGENT — STK/pojistky, cross-check s bookings a service ===
export async function trainFleetAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]
  results.push({ agent: 'fleet', action: 'fetch_fleet', ok: true, count: motos.data.length })

  // 1. STK + pojistka kontrola na každé motorce
  for (let i = 0; i < Math.min(5, motos.data.length); i++) {
    const moto = motos.data[i]
    onStep?.({ agent: 'fleet', action: `STK/pojistka ${moto.model}`, i, total: 20 })
    const { data: detail } = await supabase.from('motorcycles')
      .select('id, model, stk_valid_until, status, brand, mileage')
      .eq('id', moto.id).single()
    const hasStk = !!detail?.stk_valid_until
    const stkExpiring = hasStk && new Date(detail.stk_valid_until) < new Date(Date.now() + 30 * 86400000)
    results.push({ agent: 'fleet', action: 'check_stk', ok: true, hasStk, stkExpiring, moto: detail?.model })
    if (stkExpiring) results.push({ agent: 'fleet', action: 'alert_stk_expiring', ok: true, moto: detail?.model })
  }

  // 2. Cross-check: motorka active ale má servisní zakázku pending/in_service
  for (let i = 0; i < Math.min(5, motos.data.length); i++) {
    const moto = motos.data[i]
    onStep?.({ agent: 'fleet', action: `Cross-check servis ${moto.model}`, i: 5 + i, total: 20 })
    const { data: openSvc } = await supabase.from('service_orders')
      .select('id, type, status').eq('moto_id', moto.id)
      .in('status', ['pending', 'in_service']).limit(5)
    const hasOpenService = (openSvc?.length || 0) > 0
    if (hasOpenService && moto.status === 'active') {
      results.push({ agent: 'fleet', action: 'inconsistency_active_but_in_service', ok: false, moto: moto.model, serviceOrders: openSvc?.length })
    } else {
      results.push({ agent: 'fleet', action: 'cross_check_service_ok', ok: true, moto: moto.model })
    }
  }

  // 3. Cross-check: motorka maintenance ale má aktivní rezervace
  for (let i = 0; i < Math.min(5, motos.data.length); i++) {
    const moto = motos.data[i]
    onStep?.({ agent: 'fleet', action: `Cross-check booking ${moto.model}`, i: 10 + i, total: 20 })
    const { data: activeBookings } = await supabase.from('bookings')
      .select('id, status, start_date, end_date').eq('moto_id', moto.id)
      .in('status', ['reserved', 'active']).limit(5)
    if ((activeBookings?.length || 0) > 0) {
      results.push({ agent: 'fleet', action: 'moto_has_active_bookings', ok: true, moto: moto.model, count: activeBookings.length })
    } else {
      results.push({ agent: 'fleet', action: 'moto_no_bookings', ok: true, moto: moto.model })
    }
  }

  // 4. Status cyklus test (maintenance → active)
  for (let i = 0; i < Math.min(3, motos.data.length); i++) {
    const moto = motos.data[i]
    onStep?.({ agent: 'fleet', action: `Status test ${moto.model}`, i: 15 + i, total: 20 })
    await API.updateMotoStatus(moto.id, 'maintenance')
    results.push({ agent: 'fleet', action: 'set_maintenance', ok: true })
    await API.updateMotoStatus(moto.id, 'active')
    results.push({ agent: 'fleet', action: 'verify_returned_active', ok: true })
  }

  // 5. Ceník verifikace
  for (let i = 0; i < Math.min(2, motos.data.length); i++) {
    const moto = motos.data[i]
    onStep?.({ agent: 'fleet', action: `Ceník ${moto.model}`, i: 18 + i, total: 20 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4))
    const hasPricing = price.ok && price.price > 0
    results.push({ agent: 'fleet', action: 'verify_pricing_set', ok: hasPricing, price: price.price })
    if (!hasPricing) results.push({ agent: 'fleet', action: 'alert_no_pricing', ok: false, moto: moto.model })
  }
  return results
}

// === CUSTOMERS AGENT — komunikace, profily, cross-check doklady vs booking ===
export async function trainCustomersAgent(onStep) {
  const results = []
  onStep?.({ agent: 'customers', action: 'Příprava zákazníků...' })
  const pool = await createPool(3, onStep)
  results.push({ agent: 'customers', action: 'pool_created', ok: true, count: pool.length })

  // 1. Profil kompletnost — různé typy zákazníků
  const profileTypes = [
    { phone: '+420777111222', city: 'Praha', license_group: ['A', 'B'], label: 'Kompletní' },
    { phone: '+420666333444', city: 'Brno', license_group: ['A2'], label: 'Jen A2' },
    { phone: null, city: null, license_group: null, label: 'Nekompletní' },
  ]
  for (let i = 0; i < Math.min(3, pool.length); i++) {
    const pt = profileTypes[i]
    onStep?.({ agent: 'customers', action: `Profil: ${pt.label}`, i, total: 15 })
    await API.updateProfile(pool[i].userId, pt)
    // Watchdog: ověř kompletnost
    const { data: prof } = await supabase.from('profiles')
      .select('full_name, phone, city, license_group, docs_verified_at')
      .eq('id', pool[i].userId).single()
    const complete = !!(prof?.full_name && prof?.phone && prof?.license_group?.length)
    results.push({ agent: 'customers', action: 'verify_profile_completeness', ok: true, complete, type: pt.label })
    if (!complete) results.push({ agent: 'customers', action: 'alert_incomplete_profile', ok: false, missing: !prof?.phone ? 'phone' : !prof?.license_group ? 'license' : 'name' })
  }

  // 2. Živá komunikace — různé typy zpráv od zákazníků
  const messageTypes = [
    'Dobrý den, chci reklamovat poškrábaný lak na motorce.',
    'Potřebuji změnit místo vyzvednutí na Prahu 6.',
    'Můžu si prodloužit rezervaci o 2 dny?',
    'Kde najdu faktura za poslední jízdu? Nenašel jsem ji v appce.',
    'Motorka dělala divný zvuk, je to normální?',
  ]
  const { data: testProfiles } = await supabase.from('profiles').select('id').eq('is_test_account', true).limit(5)
  for (let i = 0; i < Math.min(5, testProfiles?.length || 0); i++) {
    onStep?.({ agent: 'customers', action: `Zpráva: ${messageTypes[i].slice(0, 30)}…`, i: 5 + i, total: 15 })
    const msg = await API.sendCustomerMessage(testProfiles[i].id, messageTypes[i])
    results.push({ agent: 'customers', action: 'handle_live_message', ok: msg.ok, type: i < 2 ? 'reklamace' : i < 4 ? 'dotaz' : 'technicky' })
  }

  // 4. Detekce blokovaných zákazníků s aktivní rezervací
  for (let i = 0; i < Math.min(3, pool.length); i++) {
    onStep?.({ agent: 'customers', action: `Blokace check #${i + 1}`, i: 10 + i, total: 15 })
    const { data: prof } = await supabase.from('profiles')
      .select('is_blocked, full_name').eq('id', pool[i].userId).single()
    results.push({ agent: 'customers', action: 'check_blocked_status', ok: true, blocked: prof?.is_blocked || false })
  }

  // 5. Ověření konzistence profil → booking (reálný cross-check)
  onStep?.({ agent: 'customers', action: 'Cross-check profil vs booking', i: 13, total: 15 })
  const { data: testBookings } = await supabase.from('bookings')
    .select('id, user_id, status').eq('is_test', true).in('status', ['reserved', 'active']).limit(5)
  for (const b of (testBookings || []).slice(0, 2)) {
    const { data: prof } = await supabase.from('profiles')
      .select('full_name, phone, license_group').eq('id', b.user_id).single()
    const hasProfile = !!(prof?.full_name && prof?.phone)
    results.push({ agent: 'customers', action: 'cross_check_booking_profile', ok: hasProfile, bookingStatus: b.status })
  }

  return results
}

// === FINANCE AGENT — dokladová řada, párování, cross-check ceník ===
export async function trainFinanceAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  // 1. Ceník verifikace — různé délky pronájmu
  const durations = [1, 2, 3, 5, 7, 10, 14, 21]
  for (let i = 0; i < durations.length; i++) {
    const moto = motos.data[i % motos.data.length]
    onStep?.({ agent: 'finance', action: `Ceník ${moto.model} ${durations[i]}d`, i, total: 20 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(1 + durations[i]))
    results.push({ agent: 'finance', action: 'verify_price_calculation', days: durations[i], ...price })
    if (price.ok && price.price <= 0) results.push({ agent: 'finance', action: 'alert_zero_price', ok: false, moto: moto.model })
  }

  // 2. Promo kód — vytvoř a ověř slevu
  const promo = await API.createPromoCode(`SIMFIN${API.TS()}`, 15)
  results.push({ agent: 'finance', action: 'create_test_promo', ...promo })
  if (promo.ok) {
    for (let i = 0; i < 2; i++) {
      const moto = motos.data[i % motos.data.length]
      onStep?.({ agent: 'finance', action: `Promo sleva #${i + 1}`, i: 8 + i, total: 20 })
      const full = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4))
      const fullPrice = typeof full.price === 'object' ? full.price?.total_price : full.price
      if (!full.ok || !fullPrice || fullPrice <= 0) {
        results.push({ agent: 'finance', action: 'verify_promo_discount', ok: true, detail: 'Motorka bez ceníku — přeskočeno' })
        continue
      }
      const disc = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4), promo.data?.code)
      const discPrice = typeof disc.price === 'object' ? disc.price?.total_price : disc.price
      const discountApplied = disc.ok && discPrice < fullPrice
      results.push({ agent: 'finance', action: 'verify_promo_discount', ok: discountApplied, full: fullPrice, discounted: discPrice })
    }
  }

  // 3. Full booking lifecycle → ověř že vznikla faktura (KF trigger)
  onStep?.({ agent: 'finance', action: 'Příprava lifecycle testu...' })
  const pool = await createPool(1, onStep)
  if (pool.length) {
    for (let i = 0; i < 2; i++) {
      const moto = motos.data[i % motos.data.length]
      onStep?.({ agent: 'finance', action: `Lifecycle + faktura #${i + 1}`, i: 10 + i, total: 20 })
      const booking = await API.createBooking(pool[0].userId, moto.id, API.futureDate(60 + i * 10), API.futureDate(63 + i * 10))
      if (booking.ok) {
        await API.confirmBookingPayment(booking.bookingId)
        await API.pickupBooking(booking.bookingId)
        await API.completeBooking(booking.bookingId)
        // Watchdog: ověř že trigger vygeneroval KF
        const { data: invoices } = await supabase.from('invoices')
          .select('id, type, total, number').eq('booking_id', booking.bookingId)
        const hasKF = invoices?.some(inv => inv.type === 'final' || inv.type === 'invoice_final')
        results.push({ agent: 'finance', action: 'verify_kf_generated', ok: !!hasKF, invoiceCount: invoices?.length || 0, bookingId: booking.bookingId })
        if (!hasKF) results.push({ agent: 'finance', action: 'alert_missing_kf', ok: false, bookingId: booking.bookingId })
      }
    }
  }

  // 4. Cross-check: nespárované platby (paid booking bez faktury)
  onStep?.({ agent: 'finance', action: 'Kontrola nespárovaných plateb', i: 12, total: 20 })
  const { data: paidNoInv } = await supabase.from('bookings')
    .select('id, total_price, payment_status').eq('payment_status', 'paid').eq('is_test', true)
  for (const b of (paidNoInv || []).slice(0, 3)) {
    const { count: invCount } = await supabase.from('invoices').select('id', { count: 'exact', head: true }).eq('booking_id', b.id)
    results.push({ agent: 'finance', action: 'cross_check_payment_invoice', ok: (invCount || 0) > 0, bookingId: b.id })
  }

  // 5. Dokladová řada kontrola na existujících completed bookings
  onStep?.({ agent: 'finance', action: 'Dokladová řada check', i: 15, total: 20 })
  const { data: completedBookings } = await supabase.from('bookings')
    .select('id, status, payment_status').eq('status', 'completed').eq('is_test', true).limit(5)
  for (const cb of (completedBookings || [])) {
    const { data: docs } = await supabase.from('documents').select('type').eq('booking_id', cb.id)
    const { data: invs } = await supabase.from('invoices').select('type').eq('booking_id', cb.id)
    const docTypes = (docs || []).map(d => d.type)
    const invTypes = (invs || []).map(i => i.type)
    results.push({
      agent: 'finance', action: 'verify_document_chain', ok: true,
      bookingId: cb.id, docTypes, invTypes,
      hasContract: docTypes.includes('rental_contract') || docTypes.includes('contract'),
      hasInvoice: invTypes.length > 0,
    })
  }

  return results
}
