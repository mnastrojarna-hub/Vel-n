// Training Part 2c — CMS, Tester, Eshop, Edge cases (real audits)
// Split into: aiTrainingScenariosCms.js, aiTrainingScenariosOrchestrator.js, this file (Tester)
import { supabase } from './supabase'

// Re-export from split modules
export { trainCmsAgent } from './aiTrainingScenariosCms'
export { trainEshopAgent, trainEdgeCases, trainOrchestratorAgent } from './aiTrainingScenariosOrchestrator'

// === TESTER AGENT — skutečný audit: FK integrita, orphans, chybějící data ===
export async function trainTesterAgent(onStep) {
  const results = []

  const tables = ['motorcycles', 'profiles', 'bookings', 'sos_incidents', 'service_orders', 'maintenance_log', 'branches', 'invoices', 'promo_codes', 'message_threads', 'messages', 'vouchers', 'documents', 'admin_users']
  for (let i = 0; i < tables.length; i++) {
    const table = tables[i]
    onStep?.({ agent: 'tester', action: `Audit: ${table}`, i, total: 25 })
    const { count, error } = await supabase.from(table).select('id', { count: 'exact', head: true })
    results.push({ agent: 'tester', action: `audit_table_${table}`, ok: !error, count: count || 0, error: error?.message })
  }

  onStep?.({ agent: 'tester', action: 'FK: bookings→motorcycles', i: 14, total: 25 })
  const { data: bookingsWithMoto } = await supabase.from('bookings').select('id, moto_id, motorcycles(id)').limit(10)
  const orphanBookings = (bookingsWithMoto || []).filter(b => b.moto_id && !b.motorcycles)
  results.push({ agent: 'tester', action: 'fk_bookings_moto', ok: orphanBookings.length === 0, orphans: orphanBookings.length })

  onStep?.({ agent: 'tester', action: 'FK: bookings→profiles', i: 15, total: 25 })
  const { data: bookingsWithUser } = await supabase.from('bookings').select('id, user_id, profiles(id)').limit(10)
  const orphanUsers = (bookingsWithUser || []).filter(b => b.user_id && !b.profiles)
  results.push({ agent: 'tester', action: 'fk_bookings_user', ok: orphanUsers.length === 0, orphans: orphanUsers.length })

  onStep?.({ agent: 'tester', action: 'Completed bookings mají returned_at?', i: 16, total: 25 })
  const { data: completedNoReturn } = await supabase.from('bookings').select('id').eq('status', 'completed').is('returned_at', null).limit(10)
  results.push({ agent: 'tester', action: 'completed_has_returned_at', ok: !(completedNoReturn?.length), missing: completedNoReturn?.length || 0 })

  onStep?.({ agent: 'tester', action: 'Active bookings paid?', i: 17, total: 25 })
  const { data: activeUnpaid } = await supabase.from('bookings').select('id, payment_status').eq('status', 'active').neq('payment_status', 'paid').limit(10)
  results.push({ agent: 'tester', action: 'active_has_paid', ok: !(activeUnpaid?.length), unpaidActive: activeUnpaid?.length || 0 })

  onStep?.({ agent: 'tester', action: 'SOS resolved mají resolved_at?', i: 18, total: 25 })
  const { data: resolvedNoDate } = await supabase.from('sos_incidents').select('id').eq('status', 'resolved').is('resolved_at', null).limit(10)
  results.push({ agent: 'tester', action: 'resolved_has_date', ok: !(resolvedNoDate?.length), missing: resolvedNoDate?.length || 0 })

  onStep?.({ agent: 'tester', action: 'Active motorky mají cenu?', i: 19, total: 25 })
  const { data: noPriceActive } = await supabase.from('motorcycles').select('id, model').eq('status', 'active').is('price_weekday', null).limit(10)
  results.push({ agent: 'tester', action: 'active_has_price', ok: !(noPriceActive?.length), missing: noPriceActive?.length || 0 })

  onStep?.({ agent: 'tester', action: 'Pobočky kontrola', i: 20, total: 25 })
  const { data: branchData } = await supabase.from('branches').select('id, name, is_open, city')
  results.push({ agent: 'tester', action: 'branches_audit', ok: true, count: branchData?.length || 0, open: (branchData || []).filter(b => b.is_open).length })

  onStep?.({ agent: 'tester', action: 'Admin users', i: 21, total: 25 })
  const { data: admins } = await supabase.from('admin_users').select('id, name, role, email').limit(10)
  results.push({ agent: 'tester', action: 'admin_users_exist', ok: (admins?.length || 0) > 0, count: admins?.length || 0 })

  onStep?.({ agent: 'tester', action: 'Orphan threads', i: 22, total: 25 })
  const { data: threads } = await supabase.from('message_threads').select('id').limit(20)
  let orphanThreads = 0
  for (const t of (threads || []).slice(0, 5)) {
    const { count: msgCount } = await supabase.from('messages').select('id', { count: 'exact', head: true }).eq('thread_id', t.id)
    if (!msgCount) orphanThreads++
  }
  results.push({ agent: 'tester', action: 'orphan_threads', ok: orphanThreads === 0, orphans: orphanThreads })

  onStep?.({ agent: 'tester', action: 'Invoice kompletnost', i: 23, total: 25 })
  const { data: invs } = await supabase.from('invoices').select('id, number, total, type, status').limit(20)
  const incompleteInv = (invs || []).filter(i => !i.number || i.total == null)
  results.push({ agent: 'tester', action: 'invoices_complete', ok: incompleteInv.length === 0, total: invs?.length || 0, incomplete: incompleteInv.length })

  onStep?.({ agent: 'tester', action: 'Integrity report', i: 24, total: 25 })
  const failCount = results.filter(r => !r.ok).length
  results.push({ agent: 'tester', action: 'integrity_summary', ok: failCount === 0, totalChecks: results.length, failures: failCount })

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
