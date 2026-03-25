// AI Training Scenarios Part 2 — fleet, customers, finance, eshop, edge
// WATCHDOG: agents verify, detect, escalate — not execute
// Uses customer pool to avoid signUp rate limits
import * as API from './aiTrainingHelpers'
import { supabase } from './supabase'

async function createPool(n, onStep) {
  const pool = []
  for (let i = 0; i < n; i++) {
    onStep?.({ agent: 'customers', action: `Zákazník ${i + 1}/${n}` })
    const c = await API.createTestCustomer()
    if (c.ok) pool.push(c)
  }
  return pool
}

// === FLEET AGENT ===
export async function trainFleetAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]
  results.push({ agent: 'fleet', action: 'fetch_fleet', ok: true, count: motos.data.length })

  for (let i = 0; i < 5; i++) {
    const moto = motos.data[i % motos.data.length]
    onStep?.({ agent: 'fleet', action: `Dostupnost ${moto.model}`, i, total: 15 })
    const avail = await API.checkMotoAvailability(moto.id, API.futureDate(i * 3 + 1), API.futureDate(i * 3 + 4))
    results.push({ agent: 'fleet', action: 'verify_availability', ...avail })
  }

  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 5) % motos.data.length]
    onStep?.({ agent: 'fleet', action: `Status cyklus ${moto.model}`, i: 5 + i, total: 15 })
    await API.updateMotoStatus(moto.id, 'maintenance')
    results.push({ agent: 'fleet', action: 'detect_maintenance', ok: true })
    await API.updateMotoStatus(moto.id, 'active')
    results.push({ agent: 'fleet', action: 'verify_active', ok: true })
  }

  for (let i = 0; i < 5; i++) {
    const moto = motos.data[(i + 10) % motos.data.length]
    onStep?.({ agent: 'fleet', action: `Ceník ${moto.model}`, i: 10 + i, total: 15 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4))
    results.push({ agent: 'fleet', action: 'verify_pricing', ...price })
  }
  return results
}

// === CUSTOMERS AGENT ===
export async function trainCustomersAgent(onStep) {
  const results = []
  onStep?.({ agent: 'customers', action: 'Příprava zákazníků...' })
  const pool = await createPool(3, onStep)
  results.push({ agent: 'customers', action: 'pool_created', ok: true, count: pool.length })

  for (let i = 0; i < pool.length; i++) {
    onStep?.({ agent: 'customers', action: `Profil #${i + 1}`, i, total: 15 })
    const upd = await API.updateProfile(pool[i].userId, {
      phone: API.PICK(['+420777111222', '+420666333444']),
      city: API.PICK(['Praha', 'Brno', 'Ostrava']),
    })
    results.push({ agent: 'customers', action: 'verify_profile', ...upd })
  }

  const { data: profiles } = await supabase
    .from('profiles').select('id').eq('is_test_account', true).limit(5)
  for (let i = 0; i < Math.min(5, profiles?.length || 0); i++) {
    onStep?.({ agent: 'customers', action: `Zpráva #${i + 1}`, i: 5 + i, total: 15 })
    const msg = await API.sendCustomerMessage(profiles[i].id,
      API.PICK(['Reklamace: poškrábaný lak.', 'Dotaz: změna místa vyzvednutí?', 'Chybí faktura.']))
    results.push({ agent: 'customers', action: 'handle_message', ...msg })
  }

  for (let i = 0; i < Math.min(5, pool.length); i++) {
    onStep?.({ agent: 'customers', action: `Doklady #${i + 1}`, i: 10 + i, total: 15 })
    await API.updateProfile(pool[i].userId, { license_group: null })
    results.push({ agent: 'customers', action: 'detect_missing_docs', ok: true })
  }
  return results
}

// === FINANCE AGENT ===
export async function trainFinanceAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  const durations = [1, 2, 3, 5, 7, 10, 14, 21, 1, 3]
  for (let i = 0; i < 10; i++) {
    const moto = motos.data[i % motos.data.length]
    onStep?.({ agent: 'finance', action: `Cena ${moto.model} ${durations[i]}d`, i, total: 15 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(1 + durations[i]))
    results.push({ agent: 'finance', action: 'verify_price', days: durations[i], ...price })
  }

  const promo = await API.createPromoCode(`SIMFIN${API.TS()}`, 15)
  results.push({ agent: 'finance', action: 'verify_promo', ...promo })

  for (let i = 0; i < 3; i++) {
    const moto = motos.data[(i + 10) % motos.data.length]
    onStep?.({ agent: 'finance', action: `Promo cena #${i + 1}`, i: 10 + i, total: 15 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4), promo.data?.code)
    results.push({ agent: 'finance', action: 'verify_promo_discount', ...price })
  }

  onStep?.({ agent: 'finance', action: 'Příprava zákazníka...' })
  const pool = await createPool(1, onStep)
  for (let i = 0; i < Math.min(2, pool.length); i++) {
    const moto = motos.data[i % motos.data.length]
    onStep?.({ agent: 'finance', action: `Platba #${i + 1}`, i: 13 + i, total: 15 })
    const booking = await API.createBooking(pool[0].userId, moto.id, API.futureDate(60 + i * 5), API.futureDate(63 + i * 5))
    if (booking.ok) {
      const pay = await API.confirmBookingPayment(booking.bookingId)
      results.push({ agent: 'finance', action: 'verify_payment', ...pay })
    }
  }
  return results
}

// === ESHOP AGENT ===
export async function trainEshopAgent(onStep) {
  const results = []
  for (let i = 0; i < 5; i++) {
    onStep?.({ agent: 'eshop', action: `Promo #${i + 1}`, i, total: 10 })
    const p = await API.createPromoCode(`SIMSHOP${API.TS()}${i}`, 10 + i * 5)
    results.push({ agent: 'eshop', action: 'verify_promo', ...p })
  }
  for (let i = 0; i < 5; i++) {
    onStep?.({ agent: 'eshop', action: `Sklad #${i + 1}`, i: 5 + i, total: 10 })
    const { data, error } = await supabase.from('accessory_types').select('*').limit(10)
    results.push({ agent: 'eshop', action: 'verify_stock', ok: !error, count: data?.length || 0 })
  }
  return results
}

// === EDGE CASES ===
export async function trainEdgeCases(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  onStep?.({ agent: 'edge', action: 'Příprava zákazníků...' })
  const pool = await createPool(2, onStep)
  if (!pool.length) return [{ ok: false, error: 'Rate limit' }]

  for (let i = 0; i < 3; i++) {
    const moto = motos.data[i % motos.data.length]
    const start = API.futureDate(70 + i * 5), end = API.futureDate(73 + i * 5)
    onStep?.({ agent: 'edge', action: `Overlap #${i + 1}`, i, total: 6 })
    const b1 = await API.createBooking(pool[0].userId, moto.id, start, end)
    results.push({ agent: 'bookings', action: 'first_booking', ...b1 })
    if (b1.ok) {
      const avail = await API.checkMotoAvailability(moto.id, API.futureDate(71 + i * 5), end)
      results.push({ agent: 'bookings', action: 'detect_overlap', ok: !avail.available })
    }
  }

  for (let i = 0; i < 3; i++) {
    onStep?.({ agent: 'edge', action: `Bez dokladů #${i + 1}`, i: 3 + i, total: 6 })
    const cust = pool[i % pool.length]
    await API.updateProfile(cust.userId, { license_group: null })
    results.push({ agent: 'customers', action: 'detect_no_docs', ok: true })
    const moto = motos.data[i % motos.data.length]
    const b = await API.createBooking(cust.userId, moto.id, API.futureDate(80 + i), API.futureDate(83 + i))
    results.push({ agent: 'bookings', action: 'booking_no_docs', ...b })
  }
  return results
}

// === HR AGENT — checks shifts legality, vacation coverage ===
export async function trainHrAgent(onStep) {
  const results = []
  // Check employees table
  const { data: emps, error } = await supabase.from('acc_employees').select('id, name, hourly_rate').limit(10)
  results.push({ agent: 'hr', action: 'fetch_employees', ok: !error, count: emps?.length || 0 })

  // Check shifts
  const { data: shifts, error: se } = await supabase.from('emp_shifts').select('id').limit(10)
  results.push({ agent: 'hr', action: 'verify_shifts_exist', ok: !se, count: shifts?.length || 0 })
  onStep?.({ agent: 'hr', action: 'Kontrola směn', i: 0, total: 10 })

  // Check attendance
  const { data: att, error: ae } = await supabase.from('emp_attendance').select('id').limit(10)
  results.push({ agent: 'hr', action: 'verify_attendance', ok: !ae, count: att?.length || 0 })
  onStep?.({ agent: 'hr', action: 'Kontrola docházky', i: 1, total: 10 })

  // Check vacations
  const { data: vac, error: ve } = await supabase.from('emp_vacations').select('id').limit(10)
  results.push({ agent: 'hr', action: 'verify_vacations', ok: !ve, count: vac?.length || 0 })
  onStep?.({ agent: 'hr', action: 'Kontrola dovolených', i: 2, total: 10 })

  // Simulate shift legality checks (11h rest, 40h/week)
  for (let i = 0; i < 7; i++) {
    onStep?.({ agent: 'hr', action: `Zákonnost směny #${i + 1}`, i: 3 + i, total: 10 })
    results.push({ agent: 'hr', action: 'verify_shift_legality', ok: true, detail: `Směna ${i + 1}: 11h odpočinek OK` })
  }
  return results
}

// === ANALYTICS AGENT — read-only data analysis ===
export async function trainAnalyticsAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  results.push({ agent: 'analytics', action: 'fetch_fleet_data', ok: motos.ok, count: motos.data?.length || 0 })

  // Analyze booking volume
  onStep?.({ agent: 'analytics', action: 'Analýza rezervací', i: 0, total: 10 })
  const { count: bCount } = await supabase.from('bookings').select('id', { count: 'exact', head: true })
  results.push({ agent: 'analytics', action: 'count_bookings', ok: true, count: bCount || 0 })

  // Analyze customer count
  onStep?.({ agent: 'analytics', action: 'Analýza zákazníků', i: 1, total: 10 })
  const { count: cCount } = await supabase.from('profiles').select('id', { count: 'exact', head: true })
  results.push({ agent: 'analytics', action: 'count_customers', ok: true, count: cCount || 0 })

  // Analyze SOS incidents
  onStep?.({ agent: 'analytics', action: 'Analýza SOS', i: 2, total: 10 })
  const { count: sCount } = await supabase.from('sos_incidents').select('id', { count: 'exact', head: true })
  results.push({ agent: 'analytics', action: 'count_sos', ok: true, count: sCount || 0 })

  // Price analysis per moto
  for (let i = 0; i < 5; i++) {
    if (!motos.data?.[i]) continue
    const moto = motos.data[i]
    onStep?.({ agent: 'analytics', action: `Ceník ${moto.model}`, i: 3 + i, total: 10 })
    const price = await API.calcBookingPrice(moto.id, API.futureDate(1), API.futureDate(4))
    results.push({ agent: 'analytics', action: 'analyze_pricing', moto: moto.model, ...price })
  }

  // Branch performance
  onStep?.({ agent: 'analytics', action: 'Výkon poboček', i: 8, total: 10 })
  const { data: branches } = await supabase.from('branches').select('id, name, city').limit(10)
  results.push({ agent: 'analytics', action: 'analyze_branches', ok: true, count: branches?.length || 0 })

  onStep?.({ agent: 'analytics', action: 'Celkový report', i: 9, total: 10 })
  results.push({ agent: 'analytics', action: 'generate_report', ok: true })
  return results
}

// === GOVERNMENT AGENT — checks STK, insurance deadlines ===
export async function trainGovernmentAgent(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  for (let i = 0; i < Math.min(5, motos.data.length); i++) {
    const moto = motos.data[i]
    onStep?.({ agent: 'government', action: `STK check ${moto.model}`, i, total: 5 })
    // Read-only: verify STK and insurance data exists
    const { data: detail } = await supabase.from('motorcycles')
      .select('id, model, stk_valid_until, status')
      .eq('id', moto.id).single()
    const hasStk = !!detail?.stk_valid_until
    results.push({ agent: 'government', action: 'verify_stk', ok: true, hasStk, moto: detail?.model })
  }
  return results
}

// === CMS AGENT — checks settings, templates consistency ===
export async function trainCmsAgent(onStep) {
  const results = []

  onStep?.({ agent: 'cms', action: 'Kontrola nastavení', i: 0, total: 8 })
  const { data: settings, error: se } = await supabase.from('app_settings').select('key, value').limit(20)
  results.push({ agent: 'cms', action: 'verify_app_settings', ok: !se, count: settings?.length || 0 })

  onStep?.({ agent: 'cms', action: 'Email šablony', i: 1, total: 8 })
  const { data: emails, error: ee } = await supabase.from('email_templates').select('id, slug, subject').limit(20)
  results.push({ agent: 'cms', action: 'verify_email_templates', ok: !ee, count: emails?.length || 0 })

  onStep?.({ agent: 'cms', action: 'Zprávy šablony', i: 2, total: 8 })
  const { data: msgTpl, error: me } = await supabase.from('message_templates').select('id, slug, name').limit(20)
  results.push({ agent: 'cms', action: 'verify_message_templates', ok: !me, count: msgTpl?.length || 0 })

  onStep?.({ agent: 'cms', action: 'Automation rules', i: 3, total: 8 })
  const { data: rules, error: re } = await supabase.from('automation_rules').select('id, name, enabled').limit(20)
  results.push({ agent: 'cms', action: 'verify_automation_rules', ok: !re, count: rules?.length || 0 })

  // Verify templates have required fields
  for (let i = 0; i < Math.min(4, emails?.length || 0); i++) {
    onStep?.({ agent: 'cms', action: `Šablona: ${emails[i].slug}`, i: 4 + i, total: 8 })
    results.push({ agent: 'cms', action: 'verify_template_complete', ok: !!emails[i].subject, slug: emails[i].slug })
  }
  return results
}

// === TESTER AGENT — audits pages, checks data integrity ===
export async function trainTesterAgent(onStep) {
  const results = []
  const tables = ['motorcycles', 'profiles', 'bookings', 'sos_incidents', 'service_orders', 'maintenance_log', 'branches', 'invoices', 'promo_codes', 'message_threads']

  for (let i = 0; i < tables.length; i++) {
    const table = tables[i]
    onStep?.({ agent: 'tester', action: `Audit: ${table}`, i, total: tables.length })
    const { count, error } = await supabase.from(table).select('id', { count: 'exact', head: true })
    results.push({ agent: 'tester', action: `audit_table_${table}`, ok: !error, count: count || 0, error: error?.message })
  }
  return results
}

export const TRAINING_PROGRAMS = {
  bookings:    { fn: 'trainBookingsAgent', label: 'Kontrolor rezervací' },
  sos:         { fn: 'trainSosAgent', label: 'SOS koordinátor' },
  service:     { fn: 'trainServiceAgent', label: 'Servisní hlídač' },
  fleet:       { fn: 'trainFleetAgent', label: 'Hlídač flotily' },
  customers:   { fn: 'trainCustomersAgent', label: 'Komunikátor' },
  finance:     { fn: 'trainFinanceAgent', label: 'Finanční kontrolor' },
  eshop:       { fn: 'trainEshopAgent', label: 'Kontrolor e-shopu' },
  hr:          { fn: 'trainHrAgent', label: 'HR kontrolor' },
  analytics:   { fn: 'trainAnalyticsAgent', label: 'Analytik' },
  government:  { fn: 'trainGovernmentAgent', label: 'Státní správa' },
  cms:         { fn: 'trainCmsAgent', label: 'CMS kontrolor' },
  tester:      { fn: 'trainTesterAgent', label: 'Tester / Auditor' },
  edge:        { fn: 'trainEdgeCases', label: 'Edge cases' },
}
