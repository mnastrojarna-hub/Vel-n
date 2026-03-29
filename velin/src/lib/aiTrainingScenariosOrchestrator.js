// Training — Orchestrator + Edge cases + Eshop
import * as API from './aiTrainingHelpers'
import { supabase } from './supabase'
import { createPool } from './aiTrainingScenariosFleet'

export async function trainEshopAgent(onStep) {
  const results = []
  for (let i = 0; i < 3; i++) {
    onStep?.({ agent: 'eshop', action: `Promo kód #${i + 1}`, i, total: 15 })
    const p = await API.createPromoCode(`SIMSHOP${API.TS()}${i}`, 10 + i * 5)
    results.push({ agent: 'eshop', action: 'create_promo', ...p })
  }
  onStep?.({ agent: 'eshop', action: 'Kontrola promo kódů', i: 3, total: 15 })
  const { data: promos } = await supabase.from('promo_codes').select('id, code, value, active, max_uses, used_count, valid_to').limit(20)
  const expired = (promos || []).filter(p => p.valid_to && new Date(p.valid_to) < new Date() && p.active)
  if (expired.length) results.push({ agent: 'eshop', action: 'alert_expired_active_promos', ok: false, count: expired.length })
  const overused = (promos || []).filter(p => p.max_uses && p.used_count >= p.max_uses && p.active)
  if (overused.length) results.push({ agent: 'eshop', action: 'alert_overused_promos', ok: false, count: overused.length })
  results.push({ agent: 'eshop', action: 'promo_audit', ok: true, total: promos?.length || 0, expired: expired.length, overused: overused.length })
  onStep?.({ agent: 'eshop', action: 'Sklad příslušenství', i: 5, total: 15 })
  const { data: acc } = await supabase.from('accessory_types').select('id, key, label, is_active').limit(20)
  results.push({ agent: 'eshop', action: 'fetch_accessory_types', ok: true, count: acc?.length || 0 })
  const inactive = (acc || []).filter(a => !a.is_active)
  if (inactive.length) results.push({ agent: 'eshop', action: 'alert_inactive_accessories', ok: false, count: inactive.length })
  onStep?.({ agent: 'eshop', action: 'Kontrola voucherů', i: 7, total: 15 })
  const { data: vouchers } = await supabase.from('vouchers').select('id, code, status, amount, valid_until').limit(20)
  const activeVouchers = (vouchers || []).filter(v => v.status === 'active')
  const expiredVouchers = (vouchers || []).filter(v => v.valid_until && new Date(v.valid_until) < new Date() && v.status === 'active')
  results.push({ agent: 'eshop', action: 'voucher_audit', ok: true, total: vouchers?.length || 0, active: activeVouchers.length, expired: expiredVouchers.length })
  if (expiredVouchers.length) results.push({ agent: 'eshop', action: 'alert_expired_vouchers', ok: false, count: expiredVouchers.length })
  const zeroVouchers = activeVouchers.filter(v => !v.amount || v.amount <= 0)
  if (zeroVouchers.length) results.push({ agent: 'eshop', action: 'alert_zero_value_voucher', ok: false, count: zeroVouchers.length })
  onStep?.({ agent: 'eshop', action: 'Kontrola objednávek', i: 9, total: 15 })
  const { data: orders } = await supabase.from('shop_orders').select('id, status, payment_status, total, created_at').limit(20)
  results.push({ agent: 'eshop', action: 'fetch_orders', ok: true, count: orders?.length || 0 })
  const pendingOrders = (orders || []).filter(o => o.status === 'pending')
  if (pendingOrders.length) results.push({ agent: 'eshop', action: 'pending_orders', ok: true, count: pendingOrders.length })
  const dayAgo = new Date(Date.now() - 86400000).toISOString()
  const staleOrders = pendingOrders.filter(o => o.created_at < dayAgo)
  if (staleOrders.length) results.push({ agent: 'eshop', action: 'alert_stale_pending_orders', ok: false, count: staleOrders.length })
  onStep?.({ agent: 'eshop', action: 'Kontrola zaplacených objednávek', i: 11, total: 15 })
  const paidNotDone = (orders || []).filter(o => o.payment_status === 'paid' && !['completed', 'shipped', 'processing'].includes(o.status))
  if (paidNotDone.length) results.push({ agent: 'eshop', action: 'alert_paid_not_shipped', ok: false, count: paidNotDone.length })
  onStep?.({ agent: 'eshop', action: 'Kontrola neplatných slev', i: 13, total: 15 })
  const invalidPromos = (promos || []).filter(p => p.type === 'percent' && p.value > 100)
  if (invalidPromos.length) results.push({ agent: 'eshop', action: 'alert_invalid_promo_value', ok: false, count: invalidPromos.length })
  return results
}

export async function trainEdgeCases(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]
  onStep?.({ agent: 'edge', action: 'Příprava zákazníků...' })
  const pool = await createPool(2, onStep)
  if (!pool.length) return [{ ok: false, error: 'Rate limit' }]

  for (let i = 0; i < 2; i++) {
    const moto = motos.data[(i + 3) % motos.data.length]
    onStep?.({ agent: 'edge', action: `Storno po platbě #${i + 1}`, i, total: 8 })
    const b = await API.createBooking(pool[0].userId, moto.id, API.futureDate(100 + i * 10), API.futureDate(103 + i * 10))
    if (b.ok) { await API.confirmBookingPayment(b.bookingId); await API.cancelBooking(b.bookingId, 'Zákazník stornoval — změna plánů'); results.push({ agent: 'finance', action: 'edge_cancel_after_pay', ok: true, bookingId: b.bookingId }) }
  }
  onStep?.({ agent: 'edge', action: 'Motorka v servisu', i: 2, total: 8 })
  if (motos.data.length > 2) {
    const testMoto = motos.data[motos.data.length - 1]
    await API.updateMotoStatus(testMoto.id, 'maintenance')
    const { data: bookingsOnMaint } = await supabase.from('bookings').select('id, status').eq('moto_id', testMoto.id).in('status', ['reserved', 'active']).limit(5)
    results.push({ agent: 'fleet', action: 'verify_no_bookings_on_maintenance', ok: !(bookingsOnMaint?.length), count: bookingsOnMaint?.length || 0 })
    await API.updateMotoStatus(testMoto.id, 'active')
  }
  for (let i = 0; i < 2; i++) {
    const moto = motos.data[i % motos.data.length]
    onStep?.({ agent: 'edge', action: `Full lifecycle test #${i + 1}`, i: 3 + i, total: 8 })
    const b = await API.createBooking(pool[0].userId, moto.id, API.futureDate(140 + i * 10), API.futureDate(143 + i * 10))
    if (b.ok) { await API.confirmBookingPayment(b.bookingId); await API.pickupBooking(b.bookingId); await API.completeBooking(b.bookingId); const { data: invs } = await supabase.from('invoices').select('id, type').eq('booking_id', b.bookingId); results.push({ agent: 'finance', action: 'verify_full_lifecycle_invoice', ok: (invs?.length || 0) > 0, invoices: invs?.length || 0 }) }
  }
  onStep?.({ agent: 'edge', action: 'Změna míst vyzvednutí/vrácení', i: 5, total: 8 })
  const b3 = await API.createBooking(pool[1].userId, motos.data[0].id, API.futureDate(160), API.futureDate(163))
  if (b3.ok) { await API.confirmBookingPayment(b3.bookingId); await supabase.rpc('update_test_booking_fields', { p_booking_id: b3.bookingId, p_fields: { pickup_method: 'delivery', pickup_address: 'Hotel Hilton, Praha 8', return_method: 'delivery', return_address: 'Letiště Václava Havla, Praha 6' } }); results.push({ agent: 'bookings', action: 'edge_change_both_locations', ok: true }) }
  onStep?.({ agent: 'edge', action: 'Dvojité prodloužení', i: 6, total: 8 })
  const b4 = await API.createBooking(pool[0].userId, motos.data[1 % motos.data.length].id, API.futureDate(170), API.futureDate(173))
  if (b4.ok) { await API.confirmBookingPayment(b4.bookingId); await API.extendBooking(b4.bookingId, API.futureDate(175)); results.push({ agent: 'bookings', action: 'edge_first_extend', ok: true }); await API.extendBooking(b4.bookingId, API.futureDate(178)); results.push({ agent: 'bookings', action: 'edge_second_extend', ok: true }) }
  onStep?.({ agent: 'edge', action: 'Dvojitý SOS test', i: 7, total: 8 })
  const b5 = await API.createBooking(pool[1].userId, motos.data[0].id, API.futureDate(180), API.futureDate(183))
  if (b5.ok) { await API.confirmBookingPayment(b5.bookingId); await API.pickupBooking(b5.bookingId); const sos1 = await API.createSosIncident(pool[1].userId, b5.bookingId, motos.data[0].id, 'breakdown_minor', 'Drobná porucha'); results.push({ agent: 'sos', action: 'edge_first_sos', ok: sos1.ok }); const sos2 = await API.createSosIncident(pool[1].userId, b5.bookingId, motos.data[0].id, 'breakdown_minor', 'Další drobná porucha'); results.push({ agent: 'sos', action: 'edge_second_light_sos', ok: sos2.ok }); if (sos1.ok) await API.updateSosStatus(sos1.incidentId, 'resolved', 'Vyřešeno'); if (sos2.ok) await API.updateSosStatus(sos2.incidentId, 'resolved', 'Vyřešeno') }
  return results
}

export async function trainOrchestratorAgent(onStep) {
  const results = []
  const criticalTables = ['bookings', 'motorcycles', 'profiles', 'sos_incidents', 'invoices', 'branches']
  for (let i = 0; i < criticalTables.length; i++) {
    onStep?.({ agent: 'orchestrator', action: `Zdraví: ${criticalTables[i]}`, i, total: 15 })
    const { count, error } = await supabase.from(criticalTables[i]).select('id', { count: 'exact', head: true })
    results.push({ agent: 'orchestrator', action: `system_health_${criticalTables[i]}`, ok: !error, count: count || 0 })
  }
  onStep?.({ agent: 'orchestrator', action: 'Neřešené SOS', i: 6, total: 15 })
  const { data: openSos } = await supabase.from('sos_incidents').select('id, type, status, assigned_to').in('status', ['reported', 'acknowledged', 'in_progress'])
  const unassigned = (openSos || []).filter(s => !s.assigned_to)
  results.push({ agent: 'orchestrator', action: 'check_unassigned_sos', ok: unassigned.length === 0, unassigned: unassigned.length, total: openSos?.length || 0 })
  onStep?.({ agent: 'orchestrator', action: 'Nezaplacené bookings', i: 7, total: 15 })
  const yesterday = new Date(Date.now() - 86400000).toISOString()
  const { data: oldUnpaid } = await supabase.from('bookings').select('id, created_at, status, payment_status').eq('payment_status', 'unpaid').in('status', ['pending', 'reserved']).lt('created_at', yesterday).limit(10)
  results.push({ agent: 'orchestrator', action: 'check_old_unpaid', ok: !(oldUnpaid?.length), count: oldUnpaid?.length || 0 })
  onStep?.({ agent: 'orchestrator', action: 'Dlouhodobý maintenance', i: 8, total: 15 })
  const weekAgo = new Date(Date.now() - 7 * 86400000).toISOString()
  const { data: longMaint } = await supabase.from('maintenance_log').select('id, moto_id, service_date, status, description').eq('status', 'in_service').is('completed_date', null).lt('service_date', weekAgo.slice(0, 10)).limit(10)
  results.push({ agent: 'orchestrator', action: 'check_long_maintenance', ok: !(longMaint?.length), count: longMaint?.length || 0 })
  onStep?.({ agent: 'orchestrator', action: 'Pobočky status', i: 9, total: 15 })
  const { data: closedBranches } = await supabase.from('branches').select('id, name').eq('is_open', false)
  results.push({ agent: 'orchestrator', action: 'check_closed_branches', ok: !(closedBranches?.length), closed: closedBranches?.length || 0 })
  onStep?.({ agent: 'orchestrator', action: 'Admin users', i: 10, total: 15 })
  const { count: adminCount } = await supabase.from('admin_users').select('id', { count: 'exact', head: true })
  results.push({ agent: 'orchestrator', action: 'check_admin_users', ok: (adminCount || 0) > 0, count: adminCount || 0 })
  onStep?.({ agent: 'orchestrator', action: 'Nezodpovězené zprávy', i: 11, total: 15 })
  const { data: unanswered } = await supabase.from('message_threads').select('id, status').eq('status', 'open').limit(20)
  results.push({ agent: 'orchestrator', action: 'check_unanswered_messages', ok: true, openThreads: unanswered?.length || 0 })
  onStep?.({ agent: 'orchestrator', action: 'KPI souhrn', i: 12, total: 15 })
  const { count: activeBookings } = await supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'active')
  const { count: totalCustomers } = await supabase.from('profiles').select('id', { count: 'exact', head: true })
  results.push({ agent: 'orchestrator', action: 'kpi_summary', ok: true, activeBookings: activeBookings || 0, customers: totalCustomers || 0 })
  onStep?.({ agent: 'orchestrator', action: 'Agent health check', i: 13, total: 15 })
  const failSummary = results.filter(r => !r.ok)
  results.push({ agent: 'orchestrator', action: 'agent_coordination_check', ok: failSummary.length === 0, issues: failSummary.length })
  return results
}
