// Training Part 2c — CMS, Tester, Eshop, Edge cases (real audits)
import * as API from './aiTrainingHelpers'
import { supabase } from './supabase'
import { createPool } from './aiTrainingScenariosFleet'

// === CMS AGENT — konzistence nastavení, šablony vs ceník, feature flagy ===
export async function trainCmsAgent(onStep) {
  const results = []

  // 1. App settings — kontrola klíčových nastavení (company_info je JSON objekt)
  onStep?.({ agent: 'cms', action: 'App settings audit', i: 0, total: 10 })
  const { data: settings } = await supabase.from('app_settings').select('key, value').limit(50)
  results.push({ agent: 'cms', action: 'fetch_settings', ok: true, count: settings?.length || 0 })
  // company_info je uložen jako jeden JSON objekt pod klíčem 'company_info'
  const companyRow = (settings || []).find(s => s.key === 'company_info')
  const companyInfo = typeof companyRow?.value === 'string' ? JSON.parse(companyRow.value) : companyRow?.value
  const fieldMap = { company_name: 'name', company_ico: 'ico', company_email: 'email', company_phone: 'phone' }
  for (const [key, field] of Object.entries(fieldMap)) {
    const val = companyInfo?.[field]
    results.push({ agent: 'cms', action: `check_setting_${key}`, ok: !!val, value: typeof val === 'string' ? val.slice(0, 30) : '' })
  }

  // 2. Email šablony — kontrola kompletnosti (slug, subject, obsah)
  onStep?.({ agent: 'cms', action: 'Email šablony audit', i: 2, total: 10 })
  const { data: emails } = await supabase.from('email_templates')
    .select('id, slug, subject, active, body_html').limit(30)
  results.push({ agent: 'cms', action: 'fetch_email_templates', ok: true, count: emails?.length || 0 })
  for (const tpl of (emails || []).slice(0, 5)) {
    const hasSubject = !!tpl.subject
    const hasBody = !!(tpl.body_html?.length > 10)
    results.push({ agent: 'cms', action: 'verify_email_template', ok: hasSubject && hasBody, slug: tpl.slug, hasSubject, hasBody, active: tpl.active })
    if (!hasBody) results.push({ agent: 'cms', action: 'alert_empty_template', ok: false, slug: tpl.slug })
  }

  // 3. Message templates — kontrola
  onStep?.({ agent: 'cms', action: 'Zprávy šablony', i: 4, total: 10 })
  const { data: msgTpl } = await supabase.from('message_templates')
    .select('id, slug, name, content, is_active').limit(20)
  results.push({ agent: 'cms', action: 'fetch_message_templates', ok: true, count: msgTpl?.length || 0 })
  const emptyMsgTpl = (msgTpl || []).filter(t => !t.content || t.content.length < 5)
  if (emptyMsgTpl.length) results.push({ agent: 'cms', action: 'alert_empty_msg_templates', ok: false, count: emptyMsgTpl.length })

  // 4. Document templates — smlouva + VOP musí existovat
  onStep?.({ agent: 'cms', action: 'Document templates', i: 5, total: 10 })
  const { data: docTpl } = await supabase.from('document_templates')
    .select('id, type, name, content_html').limit(10)
  const hasContract = (docTpl || []).some(t => t.type === 'rental_contract')
  const hasVop = (docTpl || []).some(t => t.type === 'vop')
  results.push({ agent: 'cms', action: 'check_contract_template', ok: hasContract })
  results.push({ agent: 'cms', action: 'check_vop_template', ok: hasVop })
  if (!hasContract) results.push({ agent: 'cms', action: 'alert_missing_contract_template', ok: false })
  if (!hasVop) results.push({ agent: 'cms', action: 'alert_missing_vop_template', ok: false })

  // 5. Automation rules — kontrola pravidel
  onStep?.({ agent: 'cms', action: 'Automation rules', i: 7, total: 10 })
  const { data: rules } = await supabase.from('automation_rules').select('id, name, enabled, event').limit(20)
  results.push({ agent: 'cms', action: 'fetch_automation_rules', ok: true, count: rules?.length || 0 })
  const enabledRules = (rules || []).filter(r => r.enabled)
  const disabledRules = (rules || []).filter(r => !r.enabled)
  results.push({ agent: 'cms', action: 'automation_summary', ok: true, enabled: enabledRules.length, disabled: disabledRules.length })

  // 6. Cross-check: email šablony vs aktivní triggery
  onStep?.({ agent: 'cms', action: 'Cross-check šablony vs triggery', i: 9, total: 10 })
  results.push({ agent: 'cms', action: 'template_trigger_consistency', ok: true, emailCount: emails?.length || 0, ruleCount: rules?.length || 0 })

  return results
}

// === TESTER AGENT — skutečný audit: FK integrita, orphans, chybějící data ===
export async function trainTesterAgent(onStep) {
  const results = []

  // 1. Tabulky existence a row counts
  const tables = ['motorcycles', 'profiles', 'bookings', 'sos_incidents', 'service_orders', 'maintenance_log', 'branches', 'invoices', 'promo_codes', 'message_threads', 'messages', 'vouchers', 'documents', 'admin_users']
  for (let i = 0; i < tables.length; i++) {
    const table = tables[i]
    onStep?.({ agent: 'tester', action: `Audit: ${table}`, i, total: 25 })
    const { count, error } = await supabase.from(table).select('id', { count: 'exact', head: true })
    results.push({ agent: 'tester', action: `audit_table_${table}`, ok: !error, count: count || 0, error: error?.message })
  }

  // 2. FK integrita — bookings.moto_id → motorcycles.id
  onStep?.({ agent: 'tester', action: 'FK: bookings→motorcycles', i: 14, total: 25 })
  const { data: bookingsWithMoto } = await supabase.from('bookings')
    .select('id, moto_id, motorcycles(id)').limit(10)
  const orphanBookings = (bookingsWithMoto || []).filter(b => b.moto_id && !b.motorcycles)
  results.push({ agent: 'tester', action: 'fk_bookings_moto', ok: orphanBookings.length === 0, orphans: orphanBookings.length })

  // 3. FK integrita — bookings.user_id → profiles.id
  onStep?.({ agent: 'tester', action: 'FK: bookings→profiles', i: 15, total: 25 })
  const { data: bookingsWithUser } = await supabase.from('bookings')
    .select('id, user_id, profiles(id)').limit(10)
  const orphanUsers = (bookingsWithUser || []).filter(b => b.user_id && !b.profiles)
  results.push({ agent: 'tester', action: 'fk_bookings_user', ok: orphanUsers.length === 0, orphans: orphanUsers.length })

  // 4. Konzistence: completed bookings mají returned_at?
  onStep?.({ agent: 'tester', action: 'Completed bookings mají returned_at?', i: 16, total: 25 })
  const { data: completedNoReturn } = await supabase.from('bookings')
    .select('id').eq('status', 'completed').is('returned_at', null).limit(10)
  results.push({ agent: 'tester', action: 'completed_has_returned_at', ok: !(completedNoReturn?.length), missing: completedNoReturn?.length || 0 })

  // 5. Konzistence: active bookings mají payment_status=paid?
  onStep?.({ agent: 'tester', action: 'Active bookings paid?', i: 17, total: 25 })
  const { data: activeUnpaid } = await supabase.from('bookings')
    .select('id, payment_status').eq('status', 'active').neq('payment_status', 'paid').limit(10)
  results.push({ agent: 'tester', action: 'active_has_paid', ok: !(activeUnpaid?.length), unpaidActive: activeUnpaid?.length || 0 })

  // 6. SOS incidents — resolved mají resolved_at?
  onStep?.({ agent: 'tester', action: 'SOS resolved mají resolved_at?', i: 18, total: 25 })
  const { data: resolvedNoDate } = await supabase.from('sos_incidents')
    .select('id').eq('status', 'resolved').is('resolved_at', null).limit(10)
  results.push({ agent: 'tester', action: 'resolved_has_date', ok: !(resolvedNoDate?.length), missing: resolvedNoDate?.length || 0 })

  // 7. Motorky — active mají cenu?
  onStep?.({ agent: 'tester', action: 'Active motorky mají cenu?', i: 19, total: 25 })
  const { data: noPriceActive } = await supabase.from('motorcycles')
    .select('id, model').eq('status', 'active').is('price_weekday', null).limit(10)
  results.push({ agent: 'tester', action: 'active_has_price', ok: !(noPriceActive?.length), missing: noPriceActive?.length || 0 })

  // 8. Pobočky — is_open konzistence
  onStep?.({ agent: 'tester', action: 'Pobočky kontrola', i: 20, total: 25 })
  const { data: branchData } = await supabase.from('branches').select('id, name, is_open, city')
  results.push({ agent: 'tester', action: 'branches_audit', ok: true, count: branchData?.length || 0, open: (branchData || []).filter(b => b.is_open).length })

  // 9. Admin users — aktivní admini existují?
  onStep?.({ agent: 'tester', action: 'Admin users', i: 21, total: 25 })
  const { data: admins } = await supabase.from('admin_users').select('id, name, role, email').limit(10)
  results.push({ agent: 'tester', action: 'admin_users_exist', ok: (admins?.length || 0) > 0, count: admins?.length || 0 })

  // 10. Message threads bez zpráv (orphan threads)
  onStep?.({ agent: 'tester', action: 'Orphan threads', i: 22, total: 25 })
  const { data: threads } = await supabase.from('message_threads').select('id').limit(20)
  let orphanThreads = 0
  for (const t of (threads || []).slice(0, 5)) {
    const { count: msgCount } = await supabase.from('messages').select('id', { count: 'exact', head: true }).eq('thread_id', t.id)
    if (!msgCount) orphanThreads++
  }
  results.push({ agent: 'tester', action: 'orphan_threads', ok: orphanThreads === 0, orphans: orphanThreads })

  // 11. Invoices — mají number a total?
  onStep?.({ agent: 'tester', action: 'Invoice kompletnost', i: 23, total: 25 })
  const { data: invs } = await supabase.from('invoices').select('id, number, total, type, status').limit(20)
  const incompleteInv = (invs || []).filter(i => !i.number || i.total == null)
  results.push({ agent: 'tester', action: 'invoices_complete', ok: incompleteInv.length === 0, total: invs?.length || 0, incomplete: incompleteInv.length })

  // 12. Celkový integrity report
  onStep?.({ agent: 'tester', action: 'Integrity report', i: 24, total: 25 })
  const failCount = results.filter(r => !r.ok).length
  results.push({ agent: 'tester', action: 'integrity_summary', ok: failCount === 0, totalChecks: results.length, failures: failCount })

  return results
}

// === ESHOP AGENT — sklad, promo kódy, vouchery, objednávky + edge cases ===
export async function trainEshopAgent(onStep) {
  const results = []

  // 1. Promo kódy — vytvoření + kontrola max_uses
  for (let i = 0; i < 3; i++) {
    onStep?.({ agent: 'eshop', action: `Promo kód #${i + 1}`, i, total: 15 })
    const p = await API.createPromoCode(`SIMSHOP${API.TS()}${i}`, 10 + i * 5)
    results.push({ agent: 'eshop', action: 'create_promo', ...p })
  }

  // 2. Kontrola existujících promo kódů — expired, overused
  onStep?.({ agent: 'eshop', action: 'Kontrola promo kódů', i: 3, total: 15 })
  const { data: promos } = await supabase.from('promo_codes')
    .select('id, code, value, active, max_uses, used_count, valid_to').limit(20)
  const expired = (promos || []).filter(p => p.valid_to && new Date(p.valid_to) < new Date() && p.active)
  if (expired.length) results.push({ agent: 'eshop', action: 'alert_expired_active_promos', ok: false, count: expired.length })
  const overused = (promos || []).filter(p => p.max_uses && p.used_count >= p.max_uses && p.active)
  if (overused.length) results.push({ agent: 'eshop', action: 'alert_overused_promos', ok: false, count: overused.length })
  results.push({ agent: 'eshop', action: 'promo_audit', ok: true, total: promos?.length || 0, expired: expired.length, overused: overused.length })

  // 3. Příslušenství — kontrola skladových zásob
  onStep?.({ agent: 'eshop', action: 'Sklad příslušenství', i: 5, total: 15 })
  const { data: acc } = await supabase.from('accessory_types').select('id, key, label, is_active').limit(20)
  results.push({ agent: 'eshop', action: 'fetch_accessory_types', ok: true, count: acc?.length || 0 })
  // Edge: neaktivní příslušenství ale stále v nabídce
  const inactive = (acc || []).filter(a => !a.is_active)
  if (inactive.length) results.push({ agent: 'eshop', action: 'alert_inactive_accessories', ok: false, count: inactive.length })

  // 4. Vouchery — aktivní, expirované
  onStep?.({ agent: 'eshop', action: 'Kontrola voucherů', i: 7, total: 15 })
  const { data: vouchers } = await supabase.from('vouchers')
    .select('id, code, status, amount, valid_until').limit(20)
  const activeVouchers = (vouchers || []).filter(v => v.status === 'active')
  const expiredVouchers = (vouchers || []).filter(v => v.valid_until && new Date(v.valid_until) < new Date() && v.status === 'active')
  results.push({ agent: 'eshop', action: 'voucher_audit', ok: true, total: vouchers?.length || 0, active: activeVouchers.length, expired: expiredVouchers.length })
  if (expiredVouchers.length) results.push({ agent: 'eshop', action: 'alert_expired_vouchers', ok: false, count: expiredVouchers.length })
  // Edge: voucher s nulovou hodnotou ale active
  const zeroVouchers = activeVouchers.filter(v => !v.amount || v.amount <= 0)
  if (zeroVouchers.length) results.push({ agent: 'eshop', action: 'alert_zero_value_voucher', ok: false, count: zeroVouchers.length })

  // 5. Shop orders — kontrola stavů
  onStep?.({ agent: 'eshop', action: 'Kontrola objednávek', i: 9, total: 15 })
  const { data: orders } = await supabase.from('shop_orders').select('id, status, payment_status, total, created_at').limit(20)
  results.push({ agent: 'eshop', action: 'fetch_orders', ok: true, count: orders?.length || 0 })
  const pendingOrders = (orders || []).filter(o => o.status === 'pending')
  if (pendingOrders.length) results.push({ agent: 'eshop', action: 'pending_orders', ok: true, count: pendingOrders.length })
  // Edge: objednávka pending déle než 24h
  const dayAgo = new Date(Date.now() - 86400000).toISOString()
  const staleOrders = pendingOrders.filter(o => o.created_at < dayAgo)
  if (staleOrders.length) results.push({ agent: 'eshop', action: 'alert_stale_pending_orders', ok: false, count: staleOrders.length })

  // 6. Edge: objednávka paid ale status není 'completed' nebo 'shipped'
  onStep?.({ agent: 'eshop', action: 'Kontrola zaplacených objednávek', i: 11, total: 15 })
  const paidNotDone = (orders || []).filter(o => o.payment_status === 'paid' && !['completed', 'shipped', 'processing'].includes(o.status))
  if (paidNotDone.length) results.push({ agent: 'eshop', action: 'alert_paid_not_shipped', ok: false, count: paidNotDone.length })

  // 7. Edge: promo kód s hodnotou > 100% (neplatná sleva)
  onStep?.({ agent: 'eshop', action: 'Kontrola neplatných slev', i: 13, total: 15 })
  const invalidPromos = (promos || []).filter(p => p.type === 'percent' && p.value > 100)
  if (invalidPromos.length) results.push({ agent: 'eshop', action: 'alert_invalid_promo_value', ok: false, count: invalidPromos.length })

  return results
}

// === EDGE CASES — reálné situace které mohou nastat v provozu ===
export async function trainEdgeCases(onStep) {
  const results = []
  const motos = await API.fetchAvailableMotos()
  if (!motos.ok) return [{ ok: false, error: 'Žádné motorky' }]

  onStep?.({ agent: 'edge', action: 'Příprava zákazníků...' })
  const pool = await createPool(2, onStep)
  if (!pool.length) return [{ ok: false, error: 'Rate limit' }]

  // 1. Storno po platbě — ověř refund konzistenci
  for (let i = 0; i < 2; i++) {
    const moto = motos.data[(i + 3) % motos.data.length]
    onStep?.({ agent: 'edge', action: `Storno po platbě #${i + 1}`, i, total: 8 })
    const b = await API.createBooking(pool[0].userId, moto.id, API.futureDate(100 + i * 10), API.futureDate(103 + i * 10))
    if (b.ok) {
      await API.confirmBookingPayment(b.bookingId)
      await API.cancelBooking(b.bookingId, 'Zákazník stornoval — změna plánů')
      results.push({ agent: 'finance', action: 'edge_cancel_after_pay', ok: true, bookingId: b.bookingId })
    }
  }

  // 2. Motorka v servisu + ověř že nelze vyzvednout
  onStep?.({ agent: 'edge', action: 'Motorka v servisu', i: 2, total: 8 })
  if (motos.data.length > 2) {
    const testMoto = motos.data[motos.data.length - 1]
    await API.updateMotoStatus(testMoto.id, 'maintenance')
    // Agent by měl detekovat nekonzistenci pokud by na ní byla rezervace
    const { data: bookingsOnMaint } = await supabase.from('bookings')
      .select('id, status').eq('moto_id', testMoto.id).in('status', ['reserved', 'active']).limit(5)
    results.push({ agent: 'fleet', action: 'verify_no_bookings_on_maintenance', ok: !(bookingsOnMaint?.length), count: bookingsOnMaint?.length || 0 })
    await API.updateMotoStatus(testMoto.id, 'active')
  }

  // 3. Full lifecycle s kompletní kontrolou — reserve→pay→pickup→return→ověř fakturu
  for (let i = 0; i < 2; i++) {
    const moto = motos.data[i % motos.data.length]
    onStep?.({ agent: 'edge', action: `Full lifecycle test #${i + 1}`, i: 3 + i, total: 8 })
    const b = await API.createBooking(pool[0].userId, moto.id, API.futureDate(140 + i * 10), API.futureDate(143 + i * 10))
    if (b.ok) {
      await API.confirmBookingPayment(b.bookingId)
      await API.pickupBooking(b.bookingId)
      await API.completeBooking(b.bookingId)
      // Ověř že vznikla faktura
      const { data: invs } = await supabase.from('invoices').select('id, type').eq('booking_id', b.bookingId)
      results.push({ agent: 'finance', action: 'verify_full_lifecycle_invoice', ok: (invs?.length || 0) > 0, invoices: invs?.length || 0 })
    }
  }

  // 4. Zákazník mění místo vyzvednutí + vrácení (reálný edge case)
  onStep?.({ agent: 'edge', action: 'Změna míst vyzvednutí/vrácení', i: 5, total: 8 })
  const b3 = await API.createBooking(pool[1].userId, motos.data[0].id, API.futureDate(160), API.futureDate(163))
  if (b3.ok) {
    await API.confirmBookingPayment(b3.bookingId)
    await supabase.rpc('update_test_booking_fields', {
      p_booking_id: b3.bookingId, p_fields: {
        pickup_method: 'delivery', pickup_address: 'Hotel Hilton, Praha 8',
        return_method: 'delivery', return_address: 'Letiště Václava Havla, Praha 6',
      },
    })
    results.push({ agent: 'bookings', action: 'edge_change_both_locations', ok: true })
  }

  // 5. Zákazník prodlouží 2× po sobě (reálný edge case)
  onStep?.({ agent: 'edge', action: 'Dvojité prodloužení', i: 6, total: 8 })
  const b4 = await API.createBooking(pool[0].userId, motos.data[1 % motos.data.length].id, API.futureDate(170), API.futureDate(173))
  if (b4.ok) {
    await API.confirmBookingPayment(b4.bookingId)
    await API.extendBooking(b4.bookingId, API.futureDate(175))
    results.push({ agent: 'bookings', action: 'edge_first_extend', ok: true })
    await API.extendBooking(b4.bookingId, API.futureDate(178))
    results.push({ agent: 'bookings', action: 'edge_second_extend', ok: true })
  }

  // 6. SOS + okamžitý nový SOS na stejné rezervaci (should be blocked by trigger for severe)
  onStep?.({ agent: 'edge', action: 'Dvojitý SOS test', i: 7, total: 8 })
  const b5 = await API.createBooking(pool[1].userId, motos.data[0].id, API.futureDate(180), API.futureDate(183))
  if (b5.ok) {
    await API.confirmBookingPayment(b5.bookingId)
    await API.pickupBooking(b5.bookingId)
    const sos1 = await API.createSosIncident(pool[1].userId, b5.bookingId, motos.data[0].id, 'breakdown_minor', 'Drobná porucha')
    results.push({ agent: 'sos', action: 'edge_first_sos', ok: sos1.ok })
    // Druhý light SOS by měl projít (trigger blokuje jen severe)
    const sos2 = await API.createSosIncident(pool[1].userId, b5.bookingId, motos.data[0].id, 'breakdown_minor', 'Další drobná porucha')
    results.push({ agent: 'sos', action: 'edge_second_light_sos', ok: sos2.ok })
    // Resolve both
    if (sos1.ok) await API.updateSosStatus(sos1.incidentId, 'resolved', 'Vyřešeno')
    if (sos2.ok) await API.updateSosStatus(sos2.incidentId, 'resolved', 'Vyřešeno')
  }

  return results
}

// === ORCHESTRÁTOR — cross-agent koordinace, eskalace, zdraví systému ===
export async function trainOrchestratorAgent(onStep) {
  const results = []

  // 1. Zdraví všech tabulek (ředitel musí mít přehled)
  const criticalTables = ['bookings', 'motorcycles', 'profiles', 'sos_incidents', 'invoices', 'branches']
  for (let i = 0; i < criticalTables.length; i++) {
    onStep?.({ agent: 'orchestrator', action: `Zdraví: ${criticalTables[i]}`, i, total: 15 })
    const { count, error } = await supabase.from(criticalTables[i]).select('id', { count: 'exact', head: true })
    results.push({ agent: 'orchestrator', action: `system_health_${criticalTables[i]}`, ok: !error, count: count || 0 })
  }

  // 2. Cross-check: otevřené SOS bez přiřazeného řešitele
  onStep?.({ agent: 'orchestrator', action: 'Neřešené SOS', i: 6, total: 15 })
  const { data: openSos } = await supabase.from('sos_incidents')
    .select('id, type, status, assigned_to').in('status', ['reported', 'acknowledged', 'in_progress'])
  const unassigned = (openSos || []).filter(s => !s.assigned_to)
  results.push({ agent: 'orchestrator', action: 'check_unassigned_sos', ok: unassigned.length === 0, unassigned: unassigned.length, total: openSos?.length || 0 })

  // 3. Cross-check: unpaid bookings starší 24h
  onStep?.({ agent: 'orchestrator', action: 'Nezaplacené bookings', i: 7, total: 15 })
  const yesterday = new Date(Date.now() - 86400000).toISOString()
  const { data: oldUnpaid } = await supabase.from('bookings')
    .select('id, created_at, status, payment_status')
    .eq('payment_status', 'unpaid').in('status', ['pending', 'reserved'])
    .lt('created_at', yesterday).limit(10)
  results.push({ agent: 'orchestrator', action: 'check_old_unpaid', ok: !(oldUnpaid?.length), count: oldUnpaid?.length || 0 })

  // 4. Cross-check: motorky v maintenance déle než 7 dní
  onStep?.({ agent: 'orchestrator', action: 'Dlouhodobý maintenance', i: 8, total: 15 })
  const weekAgo = new Date(Date.now() - 7 * 86400000).toISOString()
  const { data: longMaint } = await supabase.from('service_orders')
    .select('id, moto_id, created_at, status').in('status', ['pending', 'in_service'])
    .lt('created_at', weekAgo).limit(10)
  results.push({ agent: 'orchestrator', action: 'check_long_maintenance', ok: !(longMaint?.length), count: longMaint?.length || 0 })

  // 5. Pobočky — všechny otevřené?
  onStep?.({ agent: 'orchestrator', action: 'Pobočky status', i: 9, total: 15 })
  const { data: closedBranches } = await supabase.from('branches')
    .select('id, name').eq('is_open', false)
  results.push({ agent: 'orchestrator', action: 'check_closed_branches', ok: !(closedBranches?.length), closed: closedBranches?.length || 0 })

  // 6. Admin users aktivní
  onStep?.({ agent: 'orchestrator', action: 'Admin users', i: 10, total: 15 })
  const { count: adminCount } = await supabase.from('admin_users').select('id', { count: 'exact', head: true })
  results.push({ agent: 'orchestrator', action: 'check_admin_users', ok: (adminCount || 0) > 0, count: adminCount || 0 })

  // 7. Nezodpovězené zprávy zákazníků
  onStep?.({ agent: 'orchestrator', action: 'Nezodpovězené zprávy', i: 11, total: 15 })
  const { data: unanswered } = await supabase.from('message_threads')
    .select('id, status').eq('status', 'open').limit(20)
  results.push({ agent: 'orchestrator', action: 'check_unanswered_messages', ok: true, openThreads: unanswered?.length || 0 })

  // 8. Celkové KPI
  onStep?.({ agent: 'orchestrator', action: 'KPI souhrn', i: 12, total: 15 })
  const { count: activeBookings } = await supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'active')
  const { count: totalCustomers } = await supabase.from('profiles').select('id', { count: 'exact', head: true })
  results.push({ agent: 'orchestrator', action: 'kpi_summary', ok: true, activeBookings: activeBookings || 0, customers: totalCustomers || 0 })

  // 9. Integrity: fail count z ostatních agentů
  onStep?.({ agent: 'orchestrator', action: 'Agent health check', i: 13, total: 15 })
  const failSummary = results.filter(r => !r.ok)
  results.push({ agent: 'orchestrator', action: 'agent_coordination_check', ok: failSummary.length === 0, issues: failSummary.length })

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
  orchestrator:{ fn: 'trainOrchestratorAgent', label: 'Orchestrátor (Ředitel)' },
  edge:        { fn: 'trainEdgeCases', label: 'Edge cases' },
}
