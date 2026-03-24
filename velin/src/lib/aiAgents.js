// AI Agent Registry — 12 specialized agents for MotoGo24 Velín
// Each agent can be independently toggled on/off and corrected

const STORAGE_KEY = 'motogo_ai_agents'

export const AGENTS = [
  {
    id: 'bookings',
    name: 'Správce rezervací',
    icon: '📅',
    desc: 'Správa rezervací, potvrzení plateb, storna, úpravy termínů, extras',
    tools: ['update_booking_status', 'update_booking_details', 'confirm_booking_payment', 'cancel_booking', 'create_booking'],
    readTools: ['get_bookings_summary', 'get_bookings_detail', 'get_booking_extras', 'get_booking_cancellations'],
    defaultEnabled: true,
  },
  {
    id: 'fleet',
    name: 'Správce flotily a poboček',
    icon: '🏍️',
    desc: 'Správa motorek, stavů, ceníku, poboček, příslušenství',
    tools: ['update_motorcycle', 'update_motorcycle_pricing', 'update_branch', 'update_branch_accessories'],
    readTools: ['get_fleet_overview', 'get_motorcycle_detail', 'get_branches', 'get_branch_detail', 'get_pricing_overview'],
    defaultEnabled: true,
  },
  {
    id: 'customers',
    name: 'Správce zákazníků',
    icon: '👥',
    desc: 'Profily zákazníků, blokace, komunikace, reklamace, platební metody',
    tools: ['update_customer', 'block_customer', 'send_customer_message'],
    readTools: ['get_customers', 'get_customer_detail', 'get_messages_overview', 'get_reviews', 'get_booking_complaints', 'get_payment_methods', 'get_notification_log'],
    defaultEnabled: true,
  },
  {
    id: 'finance',
    name: 'Finanční agent',
    icon: '💰',
    desc: 'Účetnictví, fakturace, DPH, párování dokladů, závazky, majetek, odpisy',
    tools: ['create_invoice', 'update_invoice_status', 'create_accounting_entry', 'match_delivery_note'],
    readTools: ['get_financial_overview', 'get_invoices', 'get_vouchers_and_promos', 'get_accounting_entries', 'get_cash_register', 'get_long_term_assets', 'get_short_term_assets', 'get_depreciation', 'get_liabilities', 'get_vat_returns', 'get_tax_returns', 'get_tax_records', 'get_flexi_reports'],
    defaultEnabled: true,
  },
  {
    id: 'service',
    name: 'Servisní manažer',
    icon: '🔧',
    desc: 'Plánování servisů, objednávky dílů, přidělování techniků, GPS lokace',
    tools: ['create_service_order', 'update_service_order', 'complete_service', 'create_maintenance_log', 'create_purchase_order', 'create_inventory_movement'],
    readTools: ['get_service_status', 'get_inventory', 'get_inventory_movements', 'get_service_parts', 'get_moto_locations', 'get_purchase_orders', 'get_auto_order_rules', 'get_suppliers', 'get_delivery_notes'],
    defaultEnabled: true,
  },
  {
    id: 'hr',
    name: 'HR agent',
    icon: '👷',
    desc: 'Směny, docházka, dovolená, mzdy, zaměstnanecké dokumenty',
    tools: ['update_employee', 'create_attendance', 'manage_vacation', 'manage_shifts', 'create_emp_document'],
    readTools: ['get_employees', 'get_employee_detail', 'get_attendance_overview', 'get_pending_vacations', 'get_shifts_overview', 'get_payrolls'],
    defaultEnabled: false,
  },
  {
    id: 'eshop',
    name: 'E-shop agent',
    icon: '🛒',
    desc: 'Objednávky, produkty, sklad, vouchery, promo kódy, příslušenství',
    tools: ['update_shop_order', 'update_product', 'create_product', 'create_promo_code', 'create_voucher'],
    readTools: ['get_shop_orders', 'get_accessory_types'],
    defaultEnabled: false,
  },
  {
    id: 'analytics',
    name: 'Analytik',
    icon: '📊',
    desc: 'Statistiky, reporty, predikce, segmentace, optimalizace, performance',
    tools: [],
    readTools: ['get_daily_stats', 'analyze_branch_performance', 'analyze_motorcycle_performance', 'analyze_category_demand', 'analyze_optimal_fleet', 'analyze_customers', 'forecast_predictions', 'get_performance_stats'],
    defaultEnabled: true,
  },
  {
    id: 'government',
    name: 'Státní správa',
    icon: '🏛️',
    desc: 'Datová schránka, STK, pojistky, daňová přiznání, DPH',
    tools: ['update_stk_date', 'submit_government_report'],
    readTools: ['get_government_overview'],
    defaultEnabled: false,
  },
  {
    id: 'cms',
    name: 'Web / CMS agent',
    icon: '🌐',
    desc: 'Správa webu, nastavení, feature flagy, šablony, emaily, smlouvy',
    tools: ['update_app_setting', 'update_feature_flag', 'update_cms_variable', 'update_email_template'],
    readTools: ['get_cms_settings', 'get_documents', 'get_message_templates', 'get_contracts'],
    defaultEnabled: false,
  },
  {
    id: 'sos',
    name: 'SOS koordinátor',
    icon: '🚨',
    desc: 'Řešení SOS incidentů, koordinace odtahu, náhradní motorky',
    tools: ['update_sos_incident', 'assign_sos', 'resolve_sos'],
    readTools: ['get_sos_incidents', 'get_sos_detail'],
    defaultEnabled: true,
  },
  {
    id: 'tester',
    name: 'Tester / Vývojář',
    icon: '🧪',
    desc: 'Testování flow, modelové situace, reporty chyb, návrhy zlepšení',
    tools: ['generate_test_report', 'simulate_scenario', 'check_data_integrity', 'test_booking_flow', 'test_payment_flow', 'test_sos_flow', 'run_full_system_test', 'simulate_customer_scenario', 'test_agent_response', 'analyze_agent_for_rewrite', 'generate_optimized_prompt', 'create_test_user', 'create_test_promo', 'cleanup_test_data', 'check_edge_functions', 'verify_app_consistency', 'generate_e2e_report'],
    readTools: ['get_audit_log'],
    defaultEnabled: false,
  },
  {
    id: 'orchestrator',
    name: 'Orchestrátor (Ředitel)',
    icon: '👔',
    desc: 'Denní briefing, KPI monitoring, prioritní fronta, eskalace, autonomní řízení',
    tools: ['generate_daily_briefing', 'check_agent_health', 'get_priority_queue'],
    readTools: ['get_bookings_summary', 'get_fleet_overview', 'get_financial_overview', 'get_sos_incidents', 'get_daily_stats'],
    defaultEnabled: true,
  },
]

export const RISK_LEVELS = {
  low: { label: 'Nízké', color: '#22c55e', auto: true },
  medium: { label: 'Střední', color: '#f59e0b', auto: false },
  high: { label: 'Vysoké', color: '#ef4444', auto: false },
}

export function loadAgentConfig() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return JSON.parse(raw)
  } catch { /* ignore */ }
  const config = {}
  for (const a of AGENTS) {
    config[a.id] = { enabled: a.defaultEnabled, corrections: [], autoConfirm: false }
  }
  return config
}

export function saveAgentConfig(config) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(config))
}

export function getEnabledAgentIds(config) {
  return AGENTS.filter(a => config[a.id]?.enabled).map(a => a.id)
}

export function getEnabledTools(config) {
  const tools = new Set()
  for (const a of AGENTS) {
    if (!config[a.id]?.enabled) continue
    for (const t of a.readTools) tools.add(t)
    for (const t of a.tools) tools.add(t)
  }
  return [...tools]
}

export function getAgentCorrections(config) {
  const corrections = {}
  for (const a of AGENTS) {
    if (config[a.id]?.corrections?.length > 0) {
      corrections[a.id] = config[a.id].corrections
    }
  }
  return corrections
}

export function getAgentForTool(toolName) {
  for (const a of AGENTS) {
    if (a.tools.includes(toolName) || a.readTools.includes(toolName)) return a
  }
  return null
}
