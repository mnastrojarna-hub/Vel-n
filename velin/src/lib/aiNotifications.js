// AI Agent Notifications — stores findings as actionable notifications
// Stored in localStorage, shown in Velín header, with deeplinks to problems

const NOTIF_KEY = 'motogo_ai_notifications'
const MAX_NOTIFICATIONS = 200

// Severity levels
export const NOTIF_SEVERITY = {
  critical: { label: 'Kritické', color: '#dc2626', bg: '#fef2f2' },
  warning: { label: 'Varování', color: '#f59e0b', bg: '#fef3c7' },
  info: { label: 'Info', color: '#3b82f6', bg: '#eff6ff' },
}

// Create a notification from agent finding
export function createAgentNotification({ agentId, agentName, agentIcon, severity, title, detail, link }) {
  const notifs = getNotifications()
  const notif = {
    id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
    agentId,
    agentName,
    agentIcon,
    severity: severity || 'info',
    title,
    detail: detail || '',
    link: link || null, // deeplink: { path: '/flotila', query: '?id=xxx' }
    read: false,
    createdAt: new Date().toISOString(),
  }
  notifs.unshift(notif)
  if (notifs.length > MAX_NOTIFICATIONS) notifs.length = MAX_NOTIFICATIONS
  localStorage.setItem(NOTIF_KEY, JSON.stringify(notifs))
  return notif
}

// Get all notifications
export function getNotifications() {
  try {
    return JSON.parse(localStorage.getItem(NOTIF_KEY)) || []
  } catch { return [] }
}

// Get unread count
export function getUnreadCount() {
  return getNotifications().filter(n => !n.read).length
}

// Mark as read
export function markRead(id) {
  const notifs = getNotifications()
  const n = notifs.find(n => n.id === id)
  if (n) n.read = true
  localStorage.setItem(NOTIF_KEY, JSON.stringify(notifs))
}

// Mark all as read
export function markAllRead() {
  const notifs = getNotifications()
  notifs.forEach(n => { n.read = true })
  localStorage.setItem(NOTIF_KEY, JSON.stringify(notifs))
}

// Clear all
export function clearNotifications() {
  localStorage.removeItem(NOTIF_KEY)
}

// Deeplink mapping: agent finding action → Velín page
const DEEPLINKS = {
  // Fleet
  alert_stk_expiring: { path: '/flotila', label: 'Flotila' },
  alert_stk_expired: { path: '/flotila', label: 'Flotila' },
  inconsistency_active_but_in_service: { path: '/servis', label: 'Servis' },
  alert_no_pricing: { path: '/flotila', label: 'Flotila' },
  // Bookings
  alert_missing_kf: { path: '/finance', label: 'Finance' },
  customer_complains: { path: '/zpravy', label: 'Zprávy' },
  // Customers
  alert_incomplete_profile: { path: '/zakaznici', label: 'Zákazníci' },
  // Finance
  cross_check_payment_invoice: { path: '/finance', label: 'Finance' },
  // SOS
  check_unassigned_sos: { path: '/sos', label: 'SOS Panel' },
  // HR
  inconsistency_vacation_vs_shift: { path: '/zamestnanci', label: 'Zaměstnanci' },
  alert_overtime: { path: '/zamestnanci', label: 'Zaměstnanci' },
  // Government
  inconsistency_expired_stk_active: { path: '/flotila', label: 'Flotila' },
  // CMS
  alert_missing_contract_template: { path: '/cms', label: 'CMS' },
  alert_missing_vop_template: { path: '/cms', label: 'CMS' },
  // Orchestrator
  check_old_unpaid: { path: '/rezervace', label: 'Rezervace' },
  check_long_maintenance: { path: '/servis', label: 'Servis' },
  check_unanswered_messages: { path: '/zpravy', label: 'Zprávy' },
}

export function getDeeplink(action) {
  return DEEPLINKS[action] || null
}

// Czech translations for notification titles
const CZ_TITLES = {
  alert_stk_expiring: 'STK brzy vyprší', alert_stk_expired: 'STK prošlá!', alert_stk_missing: 'STK chybí',
  alert_no_pricing: 'Motorka bez ceníku', alert_missing_kf: 'Chybí konečná faktura',
  alert_zero_price: 'Nulová cena v ceníku', alert_incomplete_profile: 'Nekompletní profil zákazníka',
  alert_missing_checkout: 'Chybí odchod v docházce', alert_pending_vacations: 'Neschválené dovolené',
  alert_overtime: 'Přesčas zaměstnance', alert_empty_template: 'Prázdná emailová šablona',
  alert_missing_contract_template: 'Chybí šablona smlouvy', alert_missing_vop_template: 'Chybí šablona VOP',
  alert_expired_active_promos: 'Promo kódy po expiraci', alert_overused_promos: 'Překročený limit promo',
  alert_expired_vouchers: 'Vouchery po expiraci', alert_stale_pending_orders: 'Objednávky čekají >24h',
  alert_paid_not_shipped: 'Zaplaceno ale neodesláno', alert_employee_without_docs: 'Zaměstnanec bez dokumentů',
  alert_duplicate_shifts: 'Duplicitní směny', alert_no_hourly_rate: 'Zaměstnanec bez sazby',
  alert_employee_no_contact: 'Zaměstnanec bez kontaktu', alert_too_many_on_vacation: 'Moc lidí na dovolené',
  alert_inactive_accessories: 'Neaktivní příslušenství', alert_zero_value_voucher: 'Voucher s nulovou hodnotou',
  alert_invalid_promo_value: 'Neplatná hodnota promo',
  inconsistency_active_but_in_service: 'Motorka active ale v servisu',
  inconsistency_vacation_vs_shift: 'Dovolená vs směna konflikt',
  inconsistency_expired_stk_active: 'Prošlá STK ale motorka active',
  check_unassigned_sos: 'SOS bez řešitele', check_old_unpaid: 'Nezaplacené rezervace >24h',
  check_long_maintenance: 'Servis otevřený >7 dní', check_closed_branches: 'Zavřené pobočky',
  check_unanswered_messages: 'Nezodpovězené zprávy', agent_coordination_check: 'Problémy koordinace agentů',
  check_vin_completeness: 'Motorky bez VIN', check_spz_completeness: 'Motorky bez SPZ',
  check_setting_company_name: 'Chybí nastavení: název firmy', check_setting_company_ico: 'Chybí nastavení: IČO',
  check_setting_company_email: 'Chybí nastavení: email firmy', check_setting_company_phone: 'Chybí nastavení: telefon firmy',
  verify_pricing_set: 'Ceník není nastaven', verify_promo_discount: 'Sleva promo nefunguje',
  customer_complains: 'Reklamace zákazníka', complaint_during_ride: 'Stížnost během jízdy',
  booking_failed: 'Rezervace selhala', detect_overlap: 'Kolize termínů',
}

function czTitle(action) {
  return CZ_TITLES[action] || action?.replace(/_/g, ' ')?.replace(/^[a-z]/, c => c.toUpperCase()) || 'Problém'
}

// Process training results → generate notifications for problems
export function processTrainingResults(results, agents) {
  let count = 0
  for (const r of results) {
    if (r.ok === false || r.action?.includes('alert_') || r.action?.includes('inconsistency_')) {
      const agent = agents.find(a => a.id === r.agent) || { name: r.agent, icon: '🤖' }
      const link = getDeeplink(r.action)
      createAgentNotification({
        agentId: r.agent,
        agentName: agent.name,
        agentIcon: agent.icon,
        severity: r.action?.includes('inconsistency_') || r.action?.includes('alert_missing') ? 'critical' : 'warning',
        title: czTitle(r.action),
        detail: r.result_summary || r.error || '',
        link,
      })
      count++
    }
  }
  return count
}
