// Training Helpers — REAL Supabase API calls (same as motogo-app)
// Creates real data in DB for agent training
import { supabase, supabaseUrl, supabaseAnonKey } from './supabase'
import { createClient } from '@supabase/supabase-js'

// Isolated client for signUp — does NOT share session with main admin client
// This prevents auth.signUp from switching the admin session to the new test user
const signupClient = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { persistSession: false, autoRefreshToken: false }
})

const TS = () => Date.now().toString(36).slice(-4)
const PICK = (arr) => arr[Math.random() * arr.length | 0]
const PHONE = () => `+420${600 + Math.random() * 99 | 0}${(100000 + Math.random() * 899999 | 0)}`
const FIRST = () => PICK(['Jan','Petra','Tomáš','Eva','Martin','Lucie','Pavel','Alena','Karel','Dana','Jiří','Monika'])
const LAST = () => PICK(['Novák','Černá','Horák','Dvořák','Svoboda','Malá','Veselý','Krejčí','Šťastný','Procházka'])
const futureDate = (days) => {
  const d = new Date(); d.setDate(d.getDate() + days)
  return d.toISOString().split('T')[0]
}

// --- REAL API CALLS ---

// 1. Create test customer via auth.signUp (creates auth.users + profile via trigger)
// Note: signUp triggers admin_users lookup → 406/401 console noise — harmless, ignore
export async function createTestCustomer() {
  const tag = TS(), fn = FIRST(), ln = LAST()
  const email = `test.sim.${tag}@motogo24.cz`
  const password = `SimTest${tag}!23`

  // Use isolated client so admin session is NOT replaced by new user
  const { data, error } = await signupClient.auth.signUp({
    email, password,
    options: { data: { full_name: `${fn} ${ln}`, phone: PHONE(), is_test: true } }
  })
  if (error) return { ok: false, error: error.message, email }

  const userId = data?.user?.id
  if (userId) {
    // Wait for handle_new_user trigger to create the profile row
    await new Promise(r => setTimeout(r, 500))
    // Mark profile as test + add details
    await supabase.from('profiles').update({
      full_name: `${fn} ${ln}`,
      phone: PHONE(),
      license_group: PICK([['A'], ['A2'], ['A', 'B'], ['A2', 'B']]),
      is_test_account: true,
    }).eq('id', userId)
  }
  return { ok: true, userId, email, name: `${fn} ${ln}` }
}

// 2. Fetch available motorcycles
export async function fetchAvailableMotos() {
  const { data, error } = await supabase
    .from('motorcycles')
    .select('id, model, brand, category, status, branch_id, price_weekday, license_required, branches(name, city)')
    .eq('status', 'active')
    .limit(20)
  return { ok: !error, data: data || [], error: error?.message }
}

// 3. Check motorcycle availability for date range
export async function checkMotoAvailability(motoId, startISO, endISO) {
  const { data, error } = await supabase
    .from('bookings')
    .select('id, start_date, end_date, status')
    .eq('motorcycle_id', motoId)
    .in('status', ['pending', 'reserved', 'active'])
    .lte('start_date', endISO)
    .gte('end_date', startISO)
  return { ok: !error, available: !data?.length, conflicts: data || [], error: error?.message }
}

// 4. Create booking
export async function createBooking(userId, motoId, startDate, endDate) {
  const { data: moto } = await supabase
    .from('motorcycles').select('branch_id').eq('id', motoId).single()

  const { data, error } = await supabase.from('bookings').insert({
    user_id: userId,
    motorcycle_id: motoId,
    start_date: startDate,
    end_date: endDate,
    status: 'reserved',
    payment_status: 'unpaid',
    branch_id: moto?.branch_id,
    booking_source: 'app',
    is_test: true,
  }).select().single()
  return { ok: !error, bookingId: data?.id, data, error: error?.message }
}

// 5. Calculate booking price (RPC)
export async function calcBookingPrice(motoId, startISO, endISO, promo = null) {
  const { data, error } = await supabase.rpc('calc_booking_price_v2', {
    p_moto_id: motoId, p_start: startISO, p_end: endISO, p_promo: promo
  })
  return { ok: !error, price: data, error: error?.message }
}

// 6. Confirm booking payment (simulate webhook)
export async function confirmBookingPayment(bookingId) {
  const { error } = await supabase.from('bookings').update({
    payment_status: 'paid', status: 'active'
  }).eq('id', bookingId)
  return { ok: !error, error: error?.message }
}

// 7. Cancel booking (RPC)
export async function cancelBooking(bookingId, reason = 'Test simulace') {
  const { data, error } = await supabase.rpc('cancel_booking_tracked', {
    p_booking_id: bookingId, p_reason: reason
  })
  return { ok: !error, data, error: error?.message }
}

// 8. Extend booking (RPC)
export async function extendBooking(bookingId, newEndDate) {
  const { data, error } = await supabase.rpc('extend_booking', {
    p_booking_id: bookingId, p_new_end_date: newEndDate
  })
  return { ok: !error, data, error: error?.message }
}

// 9. Shorten booking
export async function shortenBooking(bookingId, newEndDate) {
  const { error } = await supabase.from('bookings').update({
    end_date: newEndDate
  }).eq('id', bookingId)
  return { ok: !error, error: error?.message }
}

// 10. Create SOS incident
export async function createSosIncident(userId, bookingId, motoId, type, desc) {
  const lat = 49.5 + Math.random() * 1.5
  const lng = 14 + Math.random() * 3
  const { data, error } = await supabase.from('sos_incidents').insert({
    user_id: userId,
    booking_id: bookingId,
    moto_id: motoId,
    type,
    description: desc,
    status: 'reported',
    latitude: lat,
    longitude: lng,
    is_test: true,
  }).select().single()

  if (data?.id) {
    await supabase.from('sos_timeline').insert({
      incident_id: data.id, action: 'incident_created',
      details: JSON.stringify({ type, desc })
    })
  }
  return { ok: !error, incidentId: data?.id, data, error: error?.message }
}

// 11. Update SOS incident status
export async function updateSosStatus(incidentId, status, notes = '') {
  const { error } = await supabase.from('sos_incidents').update({
    status, admin_notes: notes
  }).eq('id', incidentId)

  await supabase.from('sos_timeline').insert({
    incident_id: incidentId, action: `status_${status}`, details: notes
  })
  return { ok: !error, error: error?.message }
}

// 12. Create service order
export async function createServiceOrder(motoId, type, desc) {
  const { data, error } = await supabase.from('service_orders').insert({
    motorcycle_id: motoId,
    type,
    description: desc,
    status: 'pending',
    is_test: true,
  }).select().single()
  return { ok: !error, orderId: data?.id, data, error: error?.message }
}

// 13. Complete service order
export async function completeServiceOrder(orderId, notes) {
  const { error } = await supabase.from('service_orders').update({
    status: 'completed', completed_at: new Date().toISOString(), notes
  }).eq('id', orderId)
  return { ok: !error, error: error?.message }
}

// 14. Create maintenance log
export async function createMaintenanceLog(motoId, type, desc, hours) {
  const { data, error } = await supabase.from('maintenance_log').insert({
    motorcycle_id: motoId, service_type: type, description: desc, labor_hours: hours,
    service_date: new Date().toISOString().split('T')[0], status: 'completed', is_test: true
  }).select().single()
  return { ok: !error, data, error: error?.message }
}

// 15. Update motorcycle status
export async function updateMotoStatus(motoId, status) {
  const { error } = await supabase.from('motorcycles').update({ status }).eq('id', motoId)
  return { ok: !error, error: error?.message }
}

// 16. Create promo code (correct columns: type, discount_percent)
export async function createPromoCode(code, discountPct) {
  const { data, error } = await supabase.from('promo_codes').insert({
    code,
    type: 'percent',
    discount_percent: discountPct,
    valid_from: new Date().toISOString(),
    valid_to: new Date(Date.now() + 30 * 86400000).toISOString(),
    max_uses: 10,
    is_active: true,
    is_test: true,
  }).select().single()
  return { ok: !error, data, error: error?.message }
}

// 17. Send message via message_threads + messages (not admin_messages)
export async function sendCustomerMessage(userId, content) {
  // Create or find thread
  const { data: existing } = await supabase.from('message_threads')
    .select('id').eq('customer_id', userId).limit(1).single()

  let threadId = existing?.id
  if (!threadId) {
    const { data: thread } = await supabase.from('message_threads').insert({
      customer_id: userId, status: 'open', channel: 'app'
    }).select().single()
    threadId = thread?.id
  }
  if (!threadId) return { ok: false, error: 'Nelze vytvořit vlákno' }

  const { error } = await supabase.from('messages').insert({
    thread_id: threadId, direction: 'admin', content,
    sender_name: 'AI Simulátor'
  })
  return { ok: !error, threadId, error: error?.message }
}

// 18. Update customer profile
export async function updateProfile(userId, updates) {
  const { error } = await supabase.from('profiles').update(updates).eq('id', userId)
  return { ok: !error, error: error?.message }
}

// --- CLEANUP ---
export async function cleanupTestData() {
  const results = []
  // Order matters: delete dependents first
  // Delete test SOS timeline entries for test incidents
  const { data: testSos } = await supabase.from('sos_incidents').select('id').eq('is_test', true)
  if (testSos?.length) {
    for (const s of testSos) {
      await supabase.from('sos_timeline').delete().eq('incident_id', s.id)
    }
  }
  // Delete test bookings
  const { count: b } = await supabase.from('bookings').delete({ count: 'exact' }).eq('is_test', true)
  results.push(`Bookings: ${b || 0}`)
  // Delete test SOS
  const { count: si } = await supabase.from('sos_incidents').delete({ count: 'exact' }).eq('is_test', true)
  results.push(`SOS: ${si || 0}`)
  // Delete test service orders
  const { count: so } = await supabase.from('service_orders').delete({ count: 'exact' }).eq('is_test', true)
  results.push(`Service: ${so || 0}`)
  // Delete test promos
  const { count: p } = await supabase.from('promo_codes').delete({ count: 'exact' }).eq('is_test', true)
  results.push(`Promo: ${p || 0}`)
  // Delete test maintenance logs
  const { count: ml } = await supabase.from('maintenance_log').delete({ count: 'exact' }).eq('is_test', true)
  results.push(`Maintenance: ${ml || 0}`)
  // Delete test message threads + messages for test profiles
  const { data: testProfiles } = await supabase.from('profiles').select('id').eq('is_test_account', true)
  if (testProfiles?.length) {
    for (const pr of testProfiles) {
      const { data: threads } = await supabase.from('message_threads').select('id').eq('customer_id', pr.id)
      for (const t of (threads || [])) {
        await supabase.from('messages').delete().eq('thread_id', t.id)
      }
      await supabase.from('message_threads').delete().eq('customer_id', pr.id)
    }
  }
  // Delete test profiles
  const { count: pr } = await supabase.from('profiles').delete({ count: 'exact' }).eq('is_test_account', true)
  results.push(`Profiles: ${pr || 0}`)
  return results
}

export { TS, FIRST, LAST, PICK, futureDate }
