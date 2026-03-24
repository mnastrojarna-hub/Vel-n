// AI Agent Registry — 12 specialized agents for MotoGo24 Velín
// Each agent can be independently toggled on/off and corrected

const STORAGE_KEY = 'motogo_ai_agents'

export const AGENTS = [
  {
    id: 'bookings',
    name: 'Správce rezervací',
    icon: '📅',
    desc: 'Správa rezervací, potvrzení plateb, storna, úpravy termínů',
    tools: ['update_booking_status', 'update_booking_details', 'confirm_booking_payment', 'cancel_booking', 'create_booking'],
    readTools: ['get_bookings_summary', 'get_bookings_detail'],
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
    desc: 'Profily zákazníků, blokace, komunikace, reklamace',
    tools: ['update_customer', 'block_customer', 'send_customer_message'],
    readTools: ['get_customers', 'get_customer_detail', 'get_messages_overview', 'get_reviews'],
    defaultEnabled: true,
  },
  {
    id: 'finance',
    name: 'Finanční agent',
    icon: '💰',
    desc: 'Účetnictví, fakturace, DPH, párování dokladů, závazky',
    tools: ['create_invoice', 'update_invoice_status', 'create_accounting_entry', 'match_delivery_note'],
    readTools: ['get_financial_overview', 'get_invoices', 'get_vouchers_and_promos'],
    defaultEnabled: true,
  },
  {
    id: 'service',
    name: 'Servisní manažer',
    icon: '🔧',
    desc: 'Plánování servisů, objednávky dílů, přidělování techniků',
    tools: ['create_service_order', 'update_service_order', 'complete_service', 'create_maintenance_log'],
    readTools: ['get_service_status', 'get_inventory', 'get_inventory_movements'],
    defaultEnabled: true,
  },
  {
    id: 'hr',
    name: 'HR agent',
    icon: '👷',
    desc: 'Směny, docházka, dovolená, mzdy, zaměstnanecké dokumenty',
    tools: ['update_employee', 'create_attendance', 'manage_vacation', 'manage_shifts', 'create_emp_document'],
    readTools: [],
    defaultEnabled: false,
  },
  {
    id: 'eshop',
    name: 'E-shop agent',
    icon: '🛒',
    desc: 'Objednávky, produkty, sklad, vouchery, promo kódy',
    tools: ['update_shop_order', 'update_product', 'create_product', 'create_promo_code', 'create_voucher'],
    readTools: ['get_shop_orders'],
    defaultEnabled: false,
  },
  {
    id: 'analytics',
    name: 'Analytik',
    icon: '📊',
    desc: 'Statistiky, reporty, predikce, segmentace, optimalizace',
    tools: [],
    readTools: ['get_daily_stats', 'analyze_branch_performance', 'analyze_motorcycle_performance', 'analyze_category_demand', 'analyze_optimal_fleet', 'analyze_customers', 'forecast_predictions'],
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
    desc: 'Správa webu, nastavení, feature flagy, šablony, emaily',
    tools: ['update_app_setting', 'update_feature_flag', 'update_cms_variable', 'update_email_template'],
    readTools: ['get_cms_settings', 'get_documents'],
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
    tools: ['generate_test_report', 'simulate_scenario', 'check_data_integrity'],
    readTools: ['get_audit_log'],
    defaultEnabled: false,
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
