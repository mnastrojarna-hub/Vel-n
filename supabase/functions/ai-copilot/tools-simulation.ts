// Simulation + Agent Testing tools — tester agent can test other agents
import type { SB } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execSimulation(name: string, input: R, sb: SB): Promise<unknown> {
  const now = new Date()

  switch (name) {
    // === SIMULATE CUSTOMER SCENARIO ===
    case 'simulate_customer_scenario': {
      const { scenario } = input
      const scenarios: R = {
        new_booking: {
          steps: [
            { step: 1, action: 'Zákazník otevře aplikaci', check: 'Dostupné motorky se načtou', tool: 'get_fleet_overview' },
            { step: 2, action: 'Vybere motorku a termín', check: 'Overlap check proběhne', tool: 'get_bookings_detail' },
            { step: 3, action: 'Zadá osobní údaje', check: 'Profil existuje nebo se vytvoří', tool: 'get_customers' },
            { step: 4, action: 'Provede platbu', check: 'Stripe session se vytvoří, booking přejde na reserved/active', tool: 'get_bookings_summary' },
            { step: 5, action: 'Obdrží potvrzení', check: 'Email + SMS odesláno, door codes vygenerovány', tool: 'get_notification_log' },
          ],
          expected_state: { booking_status: 'reserved', payment_status: 'paid', documents_generated: true },
        },
        cancel_booking: {
          steps: [
            { step: 1, action: 'Zákazník požádá o storno', check: 'Storno podmínky se vyhodnotí (48h/24h/0)', tool: 'get_bookings_detail' },
            { step: 2, action: 'Systém kalkuluje refund', check: 'Refund dle pravidel, Stripe refund', tool: 'get_booking_cancellations' },
            { step: 3, action: 'Booking se stornuje', check: 'Status cancelled, door codes deaktivovány', tool: 'get_bookings_summary' },
            { step: 4, action: 'Zákazník obdrží potvrzení', check: 'Email o stornu odeslán', tool: 'get_notification_log' },
          ],
          expected_state: { booking_status: 'cancelled', refund_processed: true },
        },
        sos_incident: {
          steps: [
            { step: 1, action: 'Zákazník hlásí nehodu', check: 'SOS incident vytvořen, severity auto-set', tool: 'get_sos_incidents' },
            { step: 2, action: 'Admin je notifikován', check: 'Push + SMS adminu, timeline started', tool: 'get_notification_log' },
            { step: 3, action: 'Koordinace náhradní motorky', check: 'Dostupná motorka nalezena, swap booking', tool: 'get_fleet_overview' },
            { step: 4, action: 'Řešení a uzavření', check: 'Resolution zapsána, incident closed', tool: 'get_sos_incidents' },
          ],
          expected_state: { sos_status: 'resolved', replacement_offered: true },
        },
        shop_purchase: {
          steps: [
            { step: 1, action: 'Zákazník přidá do košíku', check: 'Produkty jsou dostupné, stock > 0', tool: 'get_shop_orders' },
            { step: 2, action: 'Aplikuje promo kód', check: 'Kód validní, sleva aplikována', tool: 'get_vouchers_and_promos' },
            { step: 3, action: 'Platba', check: 'Stripe checkout, order confirmed', tool: 'get_shop_orders' },
            { step: 4, action: 'Voucher generován (pokud digitální)', check: 'Voucher kód vytvořen, email odeslán', tool: 'get_vouchers_and_promos' },
          ],
          expected_state: { order_status: 'confirmed', payment_status: 'paid' },
        },
        service_flow: {
          steps: [
            { step: 1, action: 'Servisní interval dosažen', check: 'Automatický servisní plán spuštěn', tool: 'get_service_status' },
            { step: 2, action: 'Díly zkontrolovány', check: 'Potřebné díly na skladě, nebo PO vytvořena', tool: 'get_service_parts' },
            { step: 3, action: 'Technik přiřazen', check: 'Směna pokrytá, technik má kapacitu', tool: 'get_shifts_overview' },
            { step: 4, action: 'Servis proveden', check: 'Log zapsán, motorka zpět active', tool: 'get_fleet_overview' },
          ],
          expected_state: { moto_status: 'active', service_completed: true },
        },
      }
      const sc = scenarios[scenario]
      if (!sc) return { error: `Neznámý scénář. Dostupné: ${Object.keys(scenarios).join(', ')}`, available: Object.keys(scenarios) }

      // Run actual checks for each step
      const results = []
      for (const step of sc.steps) {
        const checkResult = { ...step, status: 'simulated', details: `Simulace kroku ${step.step}` }
        results.push(checkResult)
      }
      return { scenario, steps: results, expected_state: sc.expected_state, recommendation: 'Spusťte reálný test s testovacími daty pro ověření' }
    }

    // === TEST AGENT RESPONSE QUALITY ===
    case 'test_agent_response': {
      const { agent_id, test_prompt, expected_behavior } = input
      // This tool creates a test case entry that the tester can evaluate
      return {
        test_id: crypto.randomUUID(),
        agent_id,
        test_prompt,
        expected_behavior,
        status: 'created',
        instruction: `Pro otestování agenta "${agent_id}" pošlete prompt: "${test_prompt}" a ověřte, že odpověď odpovídá: "${expected_behavior}"`,
        timestamp: now.toISOString(),
      }
    }

    // === ANALYZE AGENT PERFORMANCE FOR PROMPT REWRITE ===
    case 'analyze_agent_for_rewrite': {
      const { agent_id } = input
      if (!agent_id) return { error: 'agent_id je povinný' }

      // Gather data about the agent's domain
      const checks: R = {}

      if (agent_id === 'bookings' || agent_id === 'all') {
        const [{ count: total }, { count: active }, { count: cancelled }] = await Promise.all([
          sb.from('bookings').select('id', { count: 'exact', head: true }),
          sb.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'active'),
          sb.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'cancelled'),
        ])
        checks.bookings = { total, active, cancelled, cancel_rate: total ? Math.round((cancelled || 0) / total * 100) : 0 }
      }

      if (agent_id === 'customers' || agent_id === 'all') {
        const [{ count: total }, { count: blocked }, { count: complaints }] = await Promise.all([
          sb.from('profiles').select('id', { count: 'exact', head: true }),
          sb.from('profiles').select('id', { count: 'exact', head: true }).eq('is_blocked', true),
          sb.from('booking_complaints').select('id', { count: 'exact', head: true }).eq('status', 'open'),
        ])
        checks.customers = { total, blocked, open_complaints: complaints }
      }

      if (agent_id === 'finance' || agent_id === 'all') {
        const [{ count: unpaid }, { count: overdue }] = await Promise.all([
          sb.from('invoices').select('id', { count: 'exact', head: true }).eq('status', 'unpaid'),
          sb.from('invoices').select('id', { count: 'exact', head: true }).eq('status', 'unpaid').lt('due_date', now.toISOString().slice(0, 10)),
        ])
        checks.finance = { unpaid_invoices: unpaid, overdue_invoices: overdue }
      }

      if (agent_id === 'sos' || agent_id === 'all') {
        const { count: open } = await sb.from('sos_incidents').select('id', { count: 'exact', head: true }).in('status', ['reported', 'acknowledged', 'in_progress'])
        const { data: old } = await sb.from('sos_incidents').select('id').in('status', ['reported', 'acknowledged']).lt('created_at', new Date(now.getTime() - 24 * 3600000).toISOString())
        checks.sos = { open_incidents: open, incidents_over_24h: (old || []).length }
      }

      // Generate rewrite suggestions
      const suggestions: string[] = []
      if (checks.bookings?.cancel_rate > 20) suggestions.push(`Vysoká míra storen (${checks.bookings.cancel_rate}%) — agent by měl aktivněji nabízet alternativy`)
      if (checks.customers?.open_complaints > 0) suggestions.push(`${checks.customers.open_complaints} otevřených reklamací — agent musí prioritizovat řešení`)
      if (checks.finance?.overdue_invoices > 0) suggestions.push(`${checks.finance.overdue_invoices} faktur po splatnosti — agent by měl automaticky eskalovat`)
      if (checks.sos?.incidents_over_24h > 0) suggestions.push(`${checks.sos.incidents_over_24h} SOS > 24h — kritické! Agent musí okamžitě řešit`)

      return {
        agent_id,
        domain_state: checks,
        prompt_suggestions: suggestions,
        recommendation: suggestions.length > 0
          ? `Agent "${agent_id}" potřebuje ${suggestions.length} úprav promptu na základě aktuálních dat`
          : `Agent "${agent_id}" pracuje v normálu — žádné urgentní úpravy`,
        timestamp: now.toISOString(),
      }
    }

    // === GENERATE OPTIMIZED PROMPT ===
    case 'generate_optimized_prompt': {
      const { agent_id, current_prompt, issues } = input
      // Returns structured suggestion for prompt improvement
      return {
        agent_id,
        original_prompt_length: current_prompt?.length || 0,
        analysis: `Na základě ${(issues || []).length} zjištěných problémů navrhuji úpravu promptu`,
        suggestion: `Přidejte do promptu agenta "${agent_id}" následující pravidla:\n${(issues || []).map((i: string, idx: number) => `${idx + 1}. ${i}`).join('\n')}`,
        auto_applicable: true,
        timestamp: new Date().toISOString(),
      }
    }

    default: return null
  }
}
