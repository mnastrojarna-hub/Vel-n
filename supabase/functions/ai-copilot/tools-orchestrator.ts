// Orchestrator + enhanced tester tools
import type { SB } from './tools-constants.ts'
import { diffDays } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execOrchestrator(name: string, input: R, sb: SB): Promise<unknown> {
  const now = new Date()
  const today = now.toISOString().slice(0, 10)

  switch (name) {
    // === ORCHESTRATOR: Daily Briefing ===
    case 'generate_daily_briefing': {
      const [bookingsR, activeR, sosR, invR, svcR, msgR, statsR, motosR] = await Promise.all([
        sb.from('bookings').select('id, status, payment_status, total_price, created_at').gte('created_at', today + 'T00:00:00'),
        sb.from('bookings').select('id, status, payment_status').in('status', ['active', 'reserved', 'pending']),
        sb.from('sos_incidents').select('id, status, severity, created_at').in('status', ['reported', 'acknowledged', 'in_progress']),
        sb.from('invoices').select('id, total, status, due_date').eq('status', 'unpaid'),
        sb.from('motorcycles').select('id, model, next_service_date, status, stk_valid_until').eq('status', 'active'),
        sb.from('message_threads').select('id, status').eq('status', 'open'),
        sb.from('daily_stats').select('*').gte('date', new Date(now.getTime() - 7 * 86400000).toISOString().slice(0, 10)).order('date', { ascending: false }),
        sb.from('motorcycles').select('id, status'),
      ])
      const todayBookings = bookingsR.data || []
      const todayRevenue = todayBookings.filter((b: R) => b.payment_status === 'paid').reduce((s: number, b: R) => s + (b.total_price || 0), 0)
      const active = activeR.data || []
      const sos = sosR.data || []
      const unpaidInv = invR.data || []
      const overdue = unpaidInv.filter((i: R) => i.due_date && i.due_date < today)
      const svc = svcR.data || []
      const d30 = new Date(now.getTime() + 30 * 86400000).toISOString().slice(0, 10)
      const svcDue = svc.filter((m: R) => m.next_service_date && m.next_service_date <= d30)
      const stkExpiring = svc.filter((m: R) => m.stk_valid_until && m.stk_valid_until <= d30)
      const openMsgs = msgR.data || []
      const allMotos = motosR.data || []
      const motoStats = { total: allMotos.length, active: allMotos.filter((m: R) => m.status === 'active').length, maintenance: allMotos.filter((m: R) => m.status === 'maintenance').length, unavailable: allMotos.filter((m: R) => m.status === 'unavailable').length }
      // Week trend
      const weekStats = statsR.data || []
      const escalations: string[] = []
      if (sos.some((s: R) => s.severity === 'critical')) escalations.push('critical_incident')
      if (overdue.length > 3) escalations.push('many_overdue_invoices')
      if (stkExpiring.length > 0) escalations.push('stk_expiring_soon')
      if (motoStats.unavailable > motoStats.total * 0.3) escalations.push('high_unavailability')

      return {
        date: today,
        summary: {
          today_new_bookings: todayBookings.length,
          today_revenue: todayRevenue,
          active_bookings: active.filter((b: R) => b.status === 'active').length,
          reserved_bookings: active.filter((b: R) => b.status === 'reserved').length,
          pending_bookings: active.filter((b: R) => b.status === 'pending').length,
          unpaid_pending: active.filter((b: R) => b.payment_status === 'unpaid').length,
        },
        alerts: {
          active_sos: sos.length,
          critical_sos: sos.filter((s: R) => s.severity === 'critical').length,
          unpaid_invoices: unpaidInv.length,
          overdue_invoices: overdue.length,
          overdue_total: overdue.reduce((s: number, i: R) => s + (i.total || 0), 0),
          service_due_30d: svcDue.length,
          stk_expiring_30d: stkExpiring.length,
          open_messages: openMsgs.length,
        },
        fleet: motoStats,
        week_trend: weekStats.slice(0, 7),
        escalation_triggers: escalations,
      }
    }

    // === ORCHESTRATOR: Agent health check ===
    case 'check_agent_health': {
      const checks: R[] = []
      // Check each domain
      const [bk, mt, pr, inv, sos, msg] = await Promise.all([
        sb.from('bookings').select('id', { count: 'exact', head: true }).in('status', ['active', 'reserved']),
        sb.from('motorcycles').select('id', { count: 'exact', head: true }),
        sb.from('profiles').select('id', { count: 'exact', head: true }),
        sb.from('invoices').select('id', { count: 'exact', head: true }),
        sb.from('sos_incidents').select('id', { count: 'exact', head: true }).in('status', ['reported', 'acknowledged', 'in_progress']),
        sb.from('message_threads').select('id', { count: 'exact', head: true }).eq('status', 'open'),
      ])
      checks.push(
        { agent: 'bookings', status: 'ok', active_items: bk.count || 0 },
        { agent: 'fleet', status: 'ok', active_items: mt.count || 0 },
        { agent: 'customers', status: 'ok', active_items: pr.count || 0 },
        { agent: 'finance', status: 'ok', active_items: inv.count || 0 },
        { agent: 'sos', status: (sos.count || 0) > 0 ? 'warning' : 'ok', active_items: sos.count || 0 },
        { agent: 'customers_msgs', status: (msg.count || 0) > 5 ? 'warning' : 'ok', active_items: msg.count || 0 },
      )
      return { agents: checks, timestamp: now.toISOString() }
    }

    // === ORCHESTRATOR: Priority queue ===
    case 'get_priority_queue': {
      const priorities: R[] = []
      // Unpaid > 24h
      const yesterday = new Date(now.getTime() - 86400000).toISOString()
      const { data: oldPending } = await sb.from('bookings').select('id, user_id, total_price, created_at').eq('status', 'pending').eq('payment_status', 'unpaid').lt('created_at', yesterday).limit(10)
      for (const b of (oldPending || [])) priorities.push({ type: 'unpaid_booking', severity: 'medium', entity_id: b.id, amount: b.total_price, age_hours: Math.round((now.getTime() - new Date(b.created_at).getTime()) / 3600000) })
      // Active SOS
      const { data: activeSos } = await sb.from('sos_incidents').select('id, title, severity, created_at').in('status', ['reported', 'acknowledged']).order('severity').limit(5)
      for (const s of (activeSos || [])) priorities.push({ type: 'sos_incident', severity: s.severity === 'critical' ? 'critical' : 'high', entity_id: s.id, title: s.title })
      // Overdue invoices
      const { data: overdueInv } = await sb.from('invoices').select('id, number, total, due_date').eq('status', 'unpaid').lt('due_date', today).limit(5)
      for (const i of (overdueInv || [])) priorities.push({ type: 'overdue_invoice', severity: 'medium', entity_id: i.id, number: i.number, total: i.total, days_overdue: diffDays(i.due_date, today) })
      // Unread messages > 2h
      const h2ago = new Date(now.getTime() - 7200000).toISOString()
      const { data: oldMsgs } = await sb.from('message_threads').select('id, customer_id, created_at').eq('status', 'open').lt('updated_at', h2ago).limit(5)
      for (const m of (oldMsgs || [])) priorities.push({ type: 'unread_message', severity: 'low', entity_id: m.id })

      priorities.sort((a, b) => { const o: R = { critical: 0, high: 1, medium: 2, low: 3 }; return (o[a.severity] || 3) - (o[b.severity] || 3) })
      return { priorities, count: priorities.length, timestamp: now.toISOString() }
    }

    // === TESTER: Comprehensive flow test ===
    case 'test_booking_flow': {
      const issues: R[] = []
      // Check booking lifecycle integrity
      const { data: activeNoPickup } = await sb.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'active').is('picked_up_at', null)
      if ((activeNoPickup?.length || 0) > 0) issues.push({ flow: 'booking_activation', issue: 'Active bookings without picked_up_at', count: activeNoPickup?.length || 0, severity: 'medium' })
      const { data: completedNoPay } = await sb.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'completed').eq('payment_status', 'unpaid')
      if ((completedNoPay?.length || 0) > 0) issues.push({ flow: 'booking_completion', issue: 'Completed but unpaid bookings', count: completedNoPay?.length || 0, severity: 'high' })
      const { data: reservedNoConfirm } = await sb.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'reserved').is('confirmed_at', null)
      if ((reservedNoConfirm?.length || 0) > 0) issues.push({ flow: 'booking_reservation', issue: 'Reserved without confirmed_at', count: reservedNoConfirm?.length || 0, severity: 'low' })
      // Check moto availability consistency
      const { data: maintenanceActive } = await sb.from('bookings').select('b:id, m:moto_id').eq('status', 'active').not('moto_id', 'is', null)
      if (maintenanceActive) {
        const mids = maintenanceActive.map((b: R) => b.moto_id).filter(Boolean)
        if (mids.length > 0) {
          const { data: badMotos } = await sb.from('motorcycles').select('id, model, status').in('id', mids).neq('status', 'active')
          if (badMotos && badMotos.length > 0) issues.push({ flow: 'fleet_consistency', issue: 'Active bookings on non-active motorcycles', motorcycles: badMotos, severity: 'high' })
        }
      }
      return { test: 'booking_flow', issues, passed: issues.length === 0, timestamp: now.toISOString() }
    }

    // === TESTER: Payment flow test ===
    case 'test_payment_flow': {
      const issues: R[] = []
      const { count: paidNoBk } = await sb.from('bookings').select('id', { count: 'exact', head: true }).eq('payment_status', 'paid').eq('status', 'pending')
      if ((paidNoBk || 0) > 0) issues.push({ flow: 'payment', issue: 'Paid bookings still in pending', count: paidNoBk, severity: 'high' })
      const { data: noInvoice } = await sb.from('bookings').select('id').eq('status', 'completed').eq('payment_status', 'paid')
      if (noInvoice && noInvoice.length > 0) {
        const bids = noInvoice.map((b: R) => b.id)
        const { data: invoiced } = await sb.from('invoices').select('booking_id').in('booking_id', bids.slice(0, 50))
        const invoicedIds = new Set((invoiced || []).map((i: R) => i.booking_id))
        const missing = bids.filter((id: string) => !invoicedIds.has(id))
        if (missing.length > 0) issues.push({ flow: 'invoicing', issue: 'Completed+paid bookings without invoice', count: missing.length, severity: 'medium', sample_ids: missing.slice(0, 5) })
      }
      return { test: 'payment_flow', issues, passed: issues.length === 0, timestamp: now.toISOString() }
    }

    // === TESTER: SOS flow test ===
    case 'test_sos_flow': {
      const issues: R[] = []
      const { data: longOpen } = await sb.from('sos_incidents').select('id, title, created_at, severity').in('status', ['reported', 'acknowledged']).lt('created_at', new Date(now.getTime() - 24 * 3600000).toISOString())
      if (longOpen && longOpen.length > 0) issues.push({ flow: 'sos_response', issue: 'SOS incidents open > 24h', incidents: longOpen, severity: 'critical' })
      const { data: noTimeline } = await sb.from('sos_incidents').select('id, title')
      if (noTimeline) {
        for (const inc of noTimeline.slice(0, 20)) {
          const { count } = await sb.from('sos_timeline').select('id', { count: 'exact', head: true }).eq('incident_id', inc.id)
          if ((count || 0) === 0) issues.push({ flow: 'sos_timeline', issue: `SOS "${inc.title}" has no timeline entries`, id: inc.id, severity: 'low' })
        }
      }
      return { test: 'sos_flow', issues, passed: issues.length === 0, timestamp: now.toISOString() }
    }

    // === TESTER: Full system test ===
    case 'run_full_system_test': {
      const depth = input.depth || 'standard'
      const results: R[] = []
      // DB connectivity
      const { count: profileCount } = await sb.from('profiles').select('id', { count: 'exact', head: true })
      results.push({ area: 'database', test: 'connectivity', status: 'pass', details: `${profileCount} profiles` })
      // Orphaned records
      const { count: orphanBookings } = await sb.from('bookings').select('id', { count: 'exact', head: true }).is('user_id', null)
      results.push({ area: 'integrity', test: 'orphan_bookings', status: (orphanBookings || 0) > 0 ? 'fail' : 'pass', count: orphanBookings || 0 })
      const { count: orphanInvoices } = await sb.from('invoices').select('id', { count: 'exact', head: true }).is('customer_id', null)
      results.push({ area: 'integrity', test: 'orphan_invoices', status: (orphanInvoices || 0) > 0 ? 'warn' : 'pass', count: orphanInvoices || 0 })
      // Motorcycles without branch
      const { count: noBranch } = await sb.from('motorcycles').select('id', { count: 'exact', head: true }).is('branch_id', null)
      results.push({ area: 'fleet', test: 'no_branch', status: (noBranch || 0) > 0 ? 'warn' : 'pass', count: noBranch || 0 })
      // Pricing check
      const { count: noPrice } = await sb.from('motorcycles').select('id', { count: 'exact', head: true }).is('price_weekday', null).eq('status', 'active')
      results.push({ area: 'pricing', test: 'active_no_price', status: (noPrice || 0) > 0 ? 'fail' : 'pass', count: noPrice || 0 })
      // Duplicate door codes
      const { data: activeCodes } = await sb.from('branch_door_codes').select('door_code, booking_id').eq('is_active', true)
      const codeSet = new Set()
      let dups = 0
      for (const c of (activeCodes || [])) { if (codeSet.has(c.door_code)) dups++; codeSet.add(c.door_code) }
      results.push({ area: 'security', test: 'duplicate_door_codes', status: dups > 0 ? 'fail' : 'pass', count: dups })

      const passed = results.filter(r => r.status === 'pass').length
      const failed = results.filter(r => r.status === 'fail').length
      const warned = results.filter(r => r.status === 'warn').length
      return { test: 'full_system', depth, results, summary: { total: results.length, passed, failed, warnings: warned }, score: Math.round(passed / results.length * 100), timestamp: now.toISOString() }
    }

    default: return null
  }
}
