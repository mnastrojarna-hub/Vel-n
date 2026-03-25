// AI Agent Monitoring — periodically runs agent checks on REAL data
// Runs in background, generates notifications for problems
import { supabase } from './supabase'
import { AGENTS } from './aiAgents'
import { recordOutcome } from './aiLearning'
import { createAgentNotification, getDeeplink } from './aiNotifications'

const MONITOR_KEY = 'motogo_ai_monitor_last_run'
const MONITOR_INTERVAL = 15 * 60 * 1000 // 15 min
let _monitorTimer = null

// ACTION_DESC for Czech notification titles
const TITLES = {
  stk_expiring: 'STK brzy vyprší',
  stk_expired: 'STK prošlá!',
  active_in_service: 'Motorka active ale v servisu',
  unpaid_old: 'Nezaplacená rezervace > 24h',
  unassigned_sos: 'SOS bez přiřazeného řešitele',
  long_maintenance: 'Servis otevřený > 7 dní',
  unanswered_msg: 'Nezodpovězené zprávy zákazníků',
  missing_invoice: 'Zaplacená rezervace bez faktury',
}

// Core monitoring checks — lightweight, runs every 15 min
export async function runMonitoringCycle() {
  const results = []

  // 1. STK expiring < 14 days
  const { data: stkMotos } = await supabase.from('motorcycles')
    .select('id, model, stk_valid_until').eq('status', 'active')
    .lt('stk_valid_until', new Date(Date.now() + 14 * 86400000).toISOString()).limit(10)
  for (const m of (stkMotos || [])) {
    const days = Math.floor((new Date(m.stk_valid_until) - new Date()) / 86400000)
    const sev = days < 0 ? 'critical' : 'warning'
    const agent = AGENTS.find(a => a.id === 'fleet')
    createAgentNotification({
      agentId: 'fleet', agentName: agent.name, agentIcon: agent.icon, severity: sev,
      title: days < 0 ? TITLES.stk_expired : TITLES.stk_expiring,
      detail: `${m.model}: ${days < 0 ? 'prošlá' : `vyprší za ${days} dní`}`,
      link: getDeeplink('alert_stk_expiring'),
    })
    results.push({ agent: 'fleet', action: 'monitor_stk', ok: false })
  }

  // 2. Unassigned SOS
  const { data: openSos } = await supabase.from('sos_incidents')
    .select('id, type').in('status', ['reported', 'acknowledged']).is('assigned_to', null).limit(5)
  if (openSos?.length) {
    const agent = AGENTS.find(a => a.id === 'sos')
    createAgentNotification({
      agentId: 'sos', agentName: agent.name, agentIcon: agent.icon, severity: 'critical',
      title: TITLES.unassigned_sos, detail: `${openSos.length} SOS bez řešitele`,
      link: getDeeplink('check_unassigned_sos'),
    })
  }

  // 3. Unpaid bookings > 24h
  const yesterday = new Date(Date.now() - 86400000).toISOString()
  const { data: oldUnpaid } = await supabase.from('bookings')
    .select('id').eq('payment_status', 'unpaid').in('status', ['pending', 'reserved'])
    .lt('created_at', yesterday).limit(5)
  if (oldUnpaid?.length) {
    const agent = AGENTS.find(a => a.id === 'bookings')
    createAgentNotification({
      agentId: 'bookings', agentName: agent.name, agentIcon: agent.icon, severity: 'warning',
      title: TITLES.unpaid_old, detail: `${oldUnpaid.length} rezervací čeká na platbu > 24h`,
      link: getDeeplink('check_old_unpaid'),
    })
  }

  // 4. Unanswered messages
  const { count: openThreads } = await supabase.from('message_threads')
    .select('id', { count: 'exact', head: true }).eq('status', 'open')
  if (openThreads > 0) {
    const agent = AGENTS.find(a => a.id === 'customers')
    createAgentNotification({
      agentId: 'customers', agentName: agent.name, agentIcon: agent.icon, severity: 'info',
      title: TITLES.unanswered_msg, detail: `${openThreads} otevřených konverzací`,
      link: getDeeplink('check_unanswered_messages'),
    })
  }

  localStorage.setItem(MONITOR_KEY, new Date().toISOString())
  return results
}

// Start monitoring loop
export function startMonitoring() {
  if (_monitorTimer) return
  // Run immediately if > 15 min since last run
  const lastRun = localStorage.getItem(MONITOR_KEY)
  const elapsed = lastRun ? Date.now() - new Date(lastRun).getTime() : Infinity
  if (elapsed > MONITOR_INTERVAL) {
    runMonitoringCycle().catch(console.error)
  }
  _monitorTimer = setInterval(() => {
    runMonitoringCycle().catch(console.error)
  }, MONITOR_INTERVAL)
}

// Stop monitoring
export function stopMonitoring() {
  if (_monitorTimer) { clearInterval(_monitorTimer); _monitorTimer = null }
}

// Get last run time
export function getLastMonitorRun() {
  return localStorage.getItem(MONITOR_KEY)
}
