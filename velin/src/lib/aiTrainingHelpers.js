// Training Helpers — REAL Supabase API calls for agent training
import { supabase, supabaseUrl, supabaseAnonKey } from './supabase'
import { createClient } from '@supabase/supabase-js'

// Isolated client for signUp — does NOT share session with main admin client
const signupClient = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { persistSession: false, autoRefreshToken: false, storageKey: 'sb-signup-tmp' }
})

const TS = () => Date.now().toString(36).slice(-4)
const PICK = (arr) => arr[Math.random() * arr.length | 0]
const PHONE = () => `+420${600 + Math.random() * 99 | 0}${(100000 + Math.random() * 899999 | 0)}`
const FIRST = () => PICK(['Jan','Petra','Tomáš','Eva','Martin','Lucie','Pavel','Alena','Karel','Dana','Jiří','Monika'])
const LAST = () => PICK(['Novák','Černá','Horák','Dvořák','Svoboda','Malá','Veselý','Krejčí','Šťastný','Procházka'])
// Random offset to avoid overlap with previous training runs
const _dateOffset = Math.floor(Math.random() * 200) + 30
const futureDate = (days) => {
  const d = new Date(); d.setDate(d.getDate() + _dateOffset + days)
  return d.toISOString().split('T')[0]
}

// Delay helper to avoid rate limits
const delay = (ms) => new Promise(r => setTimeout(r, ms))

// --- REAL API CALLS ---

// 1. Create test customer via auth.signUp
export async function createTestCustomer() {
  const tag = TS(), fn = FIRST(), ln = LAST()
  const email = `test.sim.${tag}@motogo24.cz`
  const password = `SimTest${tag}!23`

  const { data, error } = await signupClient.auth.signUp({
    email, password,
    options: { data: { full_name: `${fn} ${ln}`, phone: PHONE(), is_test: true } }
  })
  if (error) {
    console.error('[createTestCustomer] signUp FAIL:', error.message)
    return { ok: false, error: error.message, email }
  }

  const userId = data?.user?.id
  if (userId) {
    // Wait for handle_new_user trigger, then verify profile exists (FK requirement)
    let profileFound = false
    for (let retry = 0; retry < 5; retry++) {
      await delay(1000)
      const { data: profile } = await supabase.from('profiles').select('id').eq('id', userId).maybeSingle()
      if (profile) { profileFound = true; break }
    }
    if (!profileFound) console.error('[createTestCustomer] Profile NOT created after 5s for', userId)
    await supabase.from('profiles').update({
      full_name: `${fn} ${ln}`,
      phone: PHONE(),
      license_group: PICK([['A'], ['A2'], ['A', 'B'], ['A2', 'B']]),
      is_test_account: true,
    }).eq('id', userId)
  }
  // Throttle to avoid 429 rate limit on signUp (free tier = ~1/3s)
  await delay(3000)
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
    .eq('moto_id', motoId)
    .in('status', ['pending', 'reserved', 'active'])
    .lte('start_date', endISO)
    .gte('end_date', startISO)
  return { ok: !error, available: !data?.length, conflicts: data || [], error: error?.message }
}

// 4. Create booking (via RPC to bypass RLS — admin inserting for another user)
export async function createBooking(userId, motoId, startDate, endDate) {
  // Try RPC first (SECURITY DEFINER, bypasses RLS)
  const { data: rpcId, error: rpcErr } = await supabase.rpc('create_test_booking', {
    p_user_id: userId, p_moto_id: motoId, p_start: startDate, p_end: endDate
  })
  if (!rpcErr && rpcId) return { ok: true, bookingId: rpcId, data: { id: rpcId }, error: null }

  // Fallback: direct insert (works if admin RLS allows it)
  const { data, error } = await supabase.from('bookings').insert({
    user_id: userId, moto_id: motoId, start_date: startDate, end_date: endDate,
    status: 'reserved', payment_status: 'unpaid', booking_source: 'app', is_test: true,
  }).select('id').single()
  if (error) console.error('[createBooking] FAIL:', error.message, error.code, error.details)
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

// 9b. Complete booking (triggers: KF invoice, door code deactivation, SMS)
export async function completeBooking(bookingId) {
  const { error } = await supabase.from('bookings').update({
    status: 'completed', returned_at: new Date().toISOString(),
    mileage_end: 100 + Math.floor(Math.random() * 500),
  }).eq('id', bookingId)
  return { ok: !error, error: error?.message }
}

// 9c. Pickup booking (mark as picked up with mileage)
export async function pickupBooking(bookingId) {
  const { error } = await supabase.from('bookings').update({
    picked_up_at: new Date().toISOString(),
    mileage_start: Math.floor(Math.random() * 30000),
  }).eq('id', bookingId)
  return { ok: !error, error: error?.message }
}

// 9d. Rate booking (customer review after completion)
export async function rateBooking(bookingId, rating) {
  const { error } = await supabase.from('bookings').update({
    rating, rated_at: new Date().toISOString(),
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
  }).select('id').single()

  if (data?.id) {
    await supabase.from('sos_timeline').insert({
      incident_id: data.id, action: 'incident_created',
      data: JSON.stringify({ type, desc })
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
    incident_id: incidentId, action: `status_${status}`, data: JSON.stringify({ notes })
  })
  return { ok: !error, error: error?.message }
}

// 12. Create service order (columns: moto_id, type, notes, status)
export async function createServiceOrder(motoId, type, desc) {
  // Try with is_test first, fallback without it if column doesn't exist
  let result = await supabase.from('service_orders').insert({
    moto_id: motoId, type, notes: desc, status: 'pending', is_test: true,
  }).select('id').single()
  if (result.error?.message?.includes('is_test')) {
    result = await supabase.from('service_orders').insert({
      moto_id: motoId, type, notes: desc, status: 'pending',
    }).select('id').single()
  }
  const { data, error } = result
  return { ok: !error, orderId: data?.id, data, error: error?.message }
}

// 13. Complete service order
export async function completeServiceOrder(orderId, notes) {
  const { error } = await supabase.from('service_orders').update({
    status: 'completed', completed_at: new Date().toISOString(), notes
  }).eq('id', orderId)
  return { ok: !error, error: error?.message }
}

// 14. Create maintenance log (columns: moto_id, service_type, description, etc.)
export async function createMaintenanceLog(motoId, type, desc, hours) {
  const row = {
    moto_id: motoId, service_type: type, description: desc, labor_hours: hours,
    service_date: new Date().toISOString().split('T')[0], status: 'completed', is_test: true
  }
  let result = await supabase.from('maintenance_log').insert(row).select('id').single()
  if (result.error?.message?.includes('is_test')) {
    delete row.is_test
    result = await supabase.from('maintenance_log').insert(row).select('id').single()
  }
  const { data, error } = result
  return { ok: !error, data, error: error?.message }
}

// 15. Update motorcycle status
export async function updateMotoStatus(motoId, status) {
  const { error } = await supabase.from('motorcycles').update({ status }).eq('id', motoId)
  return { ok: !error, error: error?.message }
}

// 16. Create promo code (columns: code, type, value, active)
export async function createPromoCode(code, discountPct) {
  const row = {
    code, type: 'percent', value: discountPct,
    valid_from: new Date().toISOString().split('T')[0],
    valid_to: futureDate(30),
    max_uses: 10, active: true, is_test: true,
  }
  let result = await supabase.from('promo_codes').insert(row).select('id, code').single()
  if (result.error?.message?.includes('is_test')) {
    delete row.is_test
    result = await supabase.from('promo_codes').insert(row).select('id, code').single()
  }
  const { data, error } = result
  return { ok: !error, data, error: error?.message }
}

// 17. Send message via message_threads + messages
export async function sendCustomerMessage(userId, content) {
  // Find existing thread (maybeSingle to avoid 406 when 0 rows)
  const { data: existing } = await supabase.from('message_threads')
    .select('id').eq('customer_id', userId).limit(1).maybeSingle()

  let threadId = existing?.id
  if (!threadId) {
    const { data: thread } = await supabase.from('message_threads').insert({
      customer_id: userId, status: 'open', channel: 'app'
    }).select('id').single()
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
  // Delete test SOS timeline entries
  const { data: testSos } = await supabase.from('sos_incidents').select('id').eq('is_test', true)
  if (testSos?.length) {
    for (const s of testSos) {
      await supabase.from('sos_timeline').delete().eq('incident_id', s.id)
    }
  }
  const { count: b } = await supabase.from('bookings').delete({ count: 'exact' }).eq('is_test', true)
  results.push(`Bookings: ${b || 0}`)
  const { count: si } = await supabase.from('sos_incidents').delete({ count: 'exact' }).eq('is_test', true)
  results.push(`SOS: ${si || 0}`)
  const { count: so } = await supabase.from('service_orders').delete({ count: 'exact' }).eq('is_test', true)
  results.push(`Service: ${so || 0}`)
  const { count: p } = await supabase.from('promo_codes').delete({ count: 'exact' }).eq('is_test', true)
  results.push(`Promo: ${p || 0}`)
  const { count: ml } = await supabase.from('maintenance_log').delete({ count: 'exact' }).eq('is_test', true)
  results.push(`Maintenance: ${ml || 0}`)
  // Delete test message threads
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
  const { count: pr } = await supabase.from('profiles').delete({ count: 'exact' }).eq('is_test_account', true)
  results.push(`Profiles: ${pr || 0}`)
  return results
}

export { TS, FIRST, LAST, PICK, futureDate }
