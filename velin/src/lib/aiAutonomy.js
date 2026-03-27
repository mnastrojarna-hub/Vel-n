// Autonomy rules engine — schedules, escalation, auto-confirm per agent
// Stored in localStorage, synced with AI agent config

const AUTONOMY_KEY = 'motogo_ai_autonomy'

// Default autonomy rules per agent
export const DEFAULT_RULES = {
  bookings: {
    schedule: 'manual',
    autoTasks: ['check_unpaid_bookings', 'check_expiring_bookings', 'check_pending_reviews'],
    escalateOn: ['cancelled_spike', 'payment_failure', 'overlap_detected'],
    autoConfirmRisk: 'none',
  },
  fleet: {
    schedule: 'manual',
    autoTasks: ['check_service_due', 'check_stk_expiry', 'check_mileage_alerts'],
    escalateOn: ['motorcycle_breakdown', 'all_unavailable_branch'],
    autoConfirmRisk: 'none',
  },
  customers: {
    schedule: 'manual',
    autoTasks: ['check_unread_messages', 'check_complaints', 'check_blocked_customers'],
    escalateOn: ['complaint_spike', 'vip_issue'],
    autoConfirmRisk: 'none',
  },
  finance: {
    schedule: 'manual',
    autoTasks: ['check_unpaid_invoices', 'check_overdue', 'match_delivery_notes', 'check_cashflow'],
    escalateOn: ['large_refund', 'negative_cashflow', 'tax_deadline'],
    autoConfirmRisk: 'none',
  },
  service: {
    schedule: 'manual',
    autoTasks: ['check_upcoming_services', 'check_low_stock_parts', 'check_overdue_services'],
    escalateOn: ['critical_part_missing', 'service_overdue_7d'],
    autoConfirmRisk: 'none',
  },
  hr: {
    schedule: 'manual',
    autoTasks: ['check_attendance', 'check_pending_vacations', 'check_shift_coverage'],
    escalateOn: ['no_coverage', 'sick_spike'],
    autoConfirmRisk: 'none',
  },
  eshop: {
    schedule: 'manual',
    autoTasks: ['check_new_orders', 'check_low_stock_products', 'check_abandoned_carts'],
    escalateOn: ['order_spike', 'stock_depleted'],
    autoConfirmRisk: 'none',
  },
  analytics: {
    schedule: 'manual',
    autoTasks: ['daily_kpi_snapshot', 'revenue_trend_check', 'utilization_alert'],
    escalateOn: ['revenue_drop_20pct', 'utilization_below_30pct'],
    autoConfirmRisk: 'none',
  },
  government: {
    schedule: 'manual',
    autoTasks: ['check_stk_expiry_all', 'check_insurance_expiry', 'check_tax_deadlines'],
    escalateOn: ['stk_expired', 'insurance_lapsed', 'tax_overdue'],
    autoConfirmRisk: 'none',
  },
  cms: {
    schedule: 'manual',
    autoTasks: ['check_outdated_content', 'check_broken_links', 'check_feature_flags'],
    escalateOn: ['critical_flag_change'],
    autoConfirmRisk: 'none',
  },
  sos: {
    schedule: 'manual',
    autoTasks: ['monitor_active_incidents', 'check_unresolved_24h'],
    escalateOn: ['critical_incident', 'unresolved_12h', 'multiple_incidents'],
    autoConfirmRisk: 'none',
  },
  tester: {
    schedule: 'manual',
    autoTasks: ['integrity_check_all', 'flow_test_booking', 'flow_test_payment', 'orphan_detection'],
    escalateOn: ['integrity_failure', 'flow_broken'],
    autoConfirmRisk: 'none',
  },
}

export const SCHEDULES = {
  realtime: { label: 'Realtime', interval: 60000, icon: '⚡' },
  hourly: { label: 'Každou hodinu', interval: 3600000, icon: '🕐' },
  daily: { label: 'Denně', interval: 86400000, icon: '📆' },
  weekly: { label: 'Týdně', interval: 604800000, icon: '📅' },
  manual: { label: 'Manuální', interval: 0, icon: '✋' },
}

export const RISK_AUTO = {
  none: { label: 'Žádné auto-potvrzení', desc: 'Vše vyžaduje lidské potvrzení' },
  low: { label: 'Low-risk auto', desc: 'Nízké riziko se provede automaticky' },
  medium: { label: 'Medium-risk auto', desc: 'Nízké + střední riziko automaticky' },
  all: { label: 'Plně autonomní', desc: 'Vše se provede automaticky (pozor!)' },
}

export function loadAutonomyRules() {
  try {
    const raw = localStorage.getItem(AUTONOMY_KEY)
    if (raw) return JSON.parse(raw)
  } catch { /* ignore */ }
  return { ...DEFAULT_RULES }
}

export function saveAutonomyRules(rules) {
  localStorage.setItem(AUTONOMY_KEY, JSON.stringify(rules))
}

// Briefing data structure
export function createBriefingRequest(agents) {
  return {
    message: `Vytvoř denní briefing pro ředitele firmy. Pro KAŽDÉHO aktivního agenta proveď jeho autoTasks a shrň výsledky. Formát:
## Denní briefing — ${new Date().toLocaleDateString('cs-CZ')}
Pro každou oblast uveď: stav (OK/varování/kritické), klíčová čísla, co vyžaduje pozornost.
Na konci: TOP 3 priority dne + doporučené akce.
Aktivní agenti: ${agents.join(', ')}`,
    isOrchestrator: true,
  }
}

// Escalation check — returns items that need human attention
export function checkEscalation(agentId, taskResults, rules) {
  const agentRules = rules[agentId]
  if (!agentRules) return []
  const escalations = []
  for (const trigger of agentRules.escalateOn || []) {
    if (taskResults?.escalation_triggers?.includes(trigger)) {
      escalations.push({ agent: agentId, trigger, severity: 'high', timestamp: new Date().toISOString() })
    }
  }
  return escalations
}
