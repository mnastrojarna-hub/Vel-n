// Velín Auditor — systematically checks every page, button, flow, data integrity
// Generates structured audit log for Claude Code analysis
import { supabase } from './supabase'

const AUDIT_LOG_KEY = 'motogo_velin_audit_log'

// All Velín pages with expected data queries and UI elements
export const VELIN_PAGES = [
  {
    id: 'dashboard', path: '/', label: 'Velín (Dashboard)', icon: '⚡',
    checks: [
      { id: 'stats_load', label: 'Statistiky se načtou', query: 'bookings,motorcycles,profiles,sos_incidents' },
      { id: 'revenue_chart', label: 'Graf tržeb', query: 'bookings(total_price)' },
      { id: 'active_bookings', label: 'Aktivní rezervace widget', query: 'bookings.status=active' },
      { id: 'sos_alert', label: 'SOS upozornění', query: 'sos_incidents.status!=resolved' },
    ],
  },
  {
    id: 'fleet', path: '/flotila', label: 'Flotila', icon: '🏍️',
    checks: [
      { id: 'moto_list', label: 'Seznam motorek se načte', query: 'motorcycles' },
      { id: 'moto_status_filter', label: 'Filtr dle stavu (active/maintenance/unavailable)', type: 'filter' },
      { id: 'moto_detail_link', label: 'Klik na motorku otevře detail', type: 'navigation' },
      { id: 'moto_edit', label: 'Editace motorky', type: 'form' },
      { id: 'moto_pricing', label: 'Nastavení cen (price_weekday/weekend/per-day)', query: 'moto_day_prices' },
      { id: 'moto_images', label: 'Upload fotek', type: 'upload' },
    ],
  },
  {
    id: 'bookings', path: '/rezervace', label: 'Rezervace', icon: '📅',
    checks: [
      { id: 'booking_list', label: 'Seznam rezervací', query: 'bookings' },
      { id: 'booking_status_filter', label: 'Filtr dle stavu (pending/reserved/active/completed/cancelled)', type: 'filter' },
      { id: 'booking_detail', label: 'Detail rezervace s timeline', type: 'navigation' },
      { id: 'booking_cancel', label: 'Storno rezervace s důvodem', type: 'action' },
      { id: 'booking_confirm_payment', label: 'Potvrzení platby', type: 'action' },
      { id: 'booking_extend', label: 'Prodloužení/zkrácení termínu', type: 'action' },
      { id: 'booking_create', label: 'Vytvoření nové rezervace z velínu', type: 'form' },
    ],
  },
  {
    id: 'customers', path: '/zakaznici', label: 'Zákazníci', icon: '👥',
    checks: [
      { id: 'customer_list', label: 'Seznam zákazníků', query: 'profiles' },
      { id: 'customer_search', label: 'Vyhledávání (jméno, email, telefon)', type: 'filter' },
      { id: 'customer_detail', label: 'Detail zákazníka (historie, doklady, platby)', type: 'navigation' },
      { id: 'customer_block', label: 'Blokace zákazníka', type: 'action' },
      { id: 'customer_docs', label: 'Ověření dokladů (řidičák, OP)', query: 'documents' },
    ],
  },
  {
    id: 'finance', path: '/finance', label: 'Finance', icon: '💰',
    checks: [
      { id: 'revenue_summary', label: 'Přehled tržeb', query: 'bookings,invoices' },
      { id: 'invoices_list', label: 'Seznam faktur', query: 'invoices' },
      { id: 'invoice_create', label: 'Vytvoření faktury', type: 'form' },
      { id: 'accounting_entries', label: 'Účetní záznamy', query: 'accounting_entries' },
      { id: 'vat_returns', label: 'DPH přiznání', type: 'report' },
      { id: 'promo_usage', label: 'Statistiky promo kódů', query: 'promo_code_usage' },
    ],
  },
  {
    id: 'service', path: '/servis', label: 'Servis', icon: '🔧',
    checks: [
      { id: 'service_orders', label: 'Seznam servisních zakázek', query: 'service_orders' },
      { id: 'service_create', label: 'Nová servisní zakázka', type: 'form' },
      { id: 'service_complete', label: 'Dokončení servisu', type: 'action' },
      { id: 'maintenance_log', label: 'Maintenance log', query: 'maintenance_log' },
      { id: 'inventory', label: 'Sklad dílů', query: 'inventory_items' },
    ],
  },
  {
    id: 'messages', path: '/zpravy', label: 'Zprávy', icon: '💬',
    checks: [
      { id: 'thread_list', label: 'Seznam konverzací', query: 'message_threads' },
      { id: 'message_send', label: 'Odeslání zprávy zákazníkovi', type: 'action' },
      { id: 'template_use', label: 'Použití šablony', query: 'message_templates' },
      { id: 'realtime', label: 'Realtime notifikace nových zpráv', type: 'realtime' },
    ],
  },
  {
    id: 'sos', path: '/sos', label: 'SOS Panel', icon: '🚨',
    checks: [
      { id: 'sos_list', label: 'Seznam incidentů', query: 'sos_incidents' },
      { id: 'sos_detail', label: 'Detail incidentu (timeline, mapa)', type: 'navigation' },
      { id: 'sos_assign', label: 'Přiřazení technika', type: 'action' },
      { id: 'sos_resolve', label: 'Vyřešení incidentu', type: 'action' },
      { id: 'sos_replacement', label: 'Náhradní motorka flow', type: 'flow' },
      { id: 'sos_realtime', label: 'Realtime nové incidenty', type: 'realtime' },
    ],
  },
  {
    id: 'branches', path: '/pobocky', label: 'Pobočky', icon: '🏢',
    checks: [
      { id: 'branch_list', label: 'Seznam poboček', query: 'branches' },
      { id: 'branch_hours', label: 'Otevírací doba', type: 'form' },
      { id: 'branch_accessories', label: 'Příslušenství na pobočce', query: 'branch_accessories' },
      { id: 'branch_door_codes', label: 'Přístupové kódy', query: 'branch_door_codes' },
    ],
  },
  {
    id: 'eshop', path: '/e-shop', label: 'E-shop', icon: '🛒',
    checks: [
      { id: 'products_list', label: 'Seznam produktů', query: 'products' },
      { id: 'orders_list', label: 'Objednávky', query: 'shop_orders' },
      { id: 'order_status', label: 'Změna stavu objednávky', type: 'action' },
      { id: 'vouchers', label: 'Vouchery', query: 'vouchers' },
    ],
  },
  {
    id: 'employees', path: '/zamestnanci', label: 'Zaměstnanci', icon: '👷',
    checks: [
      { id: 'emp_list', label: 'Seznam zaměstnanců', query: 'acc_employees' },
      { id: 'shifts', label: 'Směny', query: 'emp_shifts' },
      { id: 'attendance', label: 'Docházka', query: 'emp_attendance' },
      { id: 'vacations', label: 'Dovolené', query: 'emp_vacations' },
    ],
  },
  {
    id: 'documents', path: '/dokumenty', label: 'Dokumenty', icon: '📄',
    checks: [
      { id: 'docs_list', label: 'Seznam dokumentů', query: 'documents' },
      { id: 'contracts', label: 'Smlouvy', query: 'contracts' },
      { id: 'templates', label: 'Šablony dokumentů', query: 'document_templates' },
    ],
  },
  {
    id: 'cms', path: '/cms', label: 'Web CMS', icon: '🌐',
    checks: [
      { id: 'app_settings', label: 'Nastavení aplikace', query: 'app_settings' },
      { id: 'email_templates', label: 'Emailové šablony', query: 'email_templates' },
      { id: 'feature_flags', label: 'Feature flagy', type: 'form' },
    ],
  },
  {
    id: 'discount_codes', path: '/slevove-kody', label: 'Slevové kódy', icon: '🏷️',
    checks: [
      { id: 'promo_list', label: 'Seznam promo kódů', query: 'promo_codes' },
      { id: 'promo_create', label: 'Vytvoření nového kódu', type: 'form' },
      { id: 'gift_vouchers', label: 'Dárkové poukazy', query: 'vouchers' },
    ],
  },
  {
    id: 'government', path: '/statni-sprava', label: 'Státní správa', icon: '🏛️',
    checks: [
      { id: 'stk_overview', label: 'Přehled STK', query: 'motorcycles(stk_valid_until)' },
      { id: 'insurance', label: 'Pojistky', type: 'report' },
    ],
  },
  {
    id: 'analyza', path: '/analyza', label: 'Analýza', icon: '🧠',
    checks: [
      { id: 'analytics_load', label: 'Analytické grafy', query: 'bookings,motorcycles' },
      { id: 'predictions', label: 'Predikce poptávky', type: 'report' },
      { id: 'performance', label: 'Výkon poboček/motorek', type: 'report' },
    ],
  },
]

// Run audit on a single page — queries Supabase tables to verify data availability
export async function auditPage(page) {
  const results = []
  for (const check of page.checks) {
    const entry = {
      pageId: page.id,
      pagePath: page.path,
      pageLabel: page.label,
      checkId: check.id,
      checkLabel: check.label,
      checkType: check.type || 'query',
      timestamp: new Date().toISOString(),
      status: 'unknown',
      detail: '',
    }

    if (check.query) {
      // Test the primary table query
      const tables = check.query.split(',').map(t => t.trim().split('(')[0].split('.')[0])
      const tableResults = []
      for (const table of tables) {
        try {
          const { count, error } = await supabase.from(table).select('id', { count: 'exact', head: true })
          if (error) {
            tableResults.push({ table, status: 'error', error: error.message, count: 0 })
          } else {
            tableResults.push({ table, status: 'ok', count: count || 0 })
          }
        } catch (e) {
          tableResults.push({ table, status: 'error', error: e.message, count: 0 })
        }
      }
      const hasError = tableResults.some(t => t.status === 'error')
      const isEmpty = tableResults.every(t => t.count === 0)
      entry.status = hasError ? 'fail' : isEmpty ? 'warning' : 'pass'
      entry.detail = tableResults.map(t =>
        `${t.table}: ${t.status === 'error' ? `ERROR ${t.error}` : `${t.count} rows`}`
      ).join(', ')
      entry.tables = tableResults
    } else {
      // UI-only checks — mark as manual review needed
      entry.status = 'manual'
      entry.detail = `Typ: ${check.type} — vyžaduje manuální ověření v UI`
    }
    results.push(entry)
  }
  return results
}

// Run full audit on ALL pages
export async function auditAllPages(onProgress) {
  const allResults = []
  for (let i = 0; i < VELIN_PAGES.length; i++) {
    const page = VELIN_PAGES[i]
    onProgress?.({ phase: 'page', pageId: page.id, pageLabel: page.label, index: i, total: VELIN_PAGES.length })
    const results = await auditPage(page)
    allResults.push(...results)
  }

  // Save to localStorage
  const log = {
    timestamp: new Date().toISOString(),
    results: allResults,
    summary: {
      total: allResults.length,
      pass: allResults.filter(r => r.status === 'pass').length,
      fail: allResults.filter(r => r.status === 'fail').length,
      warning: allResults.filter(r => r.status === 'warning').length,
      manual: allResults.filter(r => r.status === 'manual').length,
    },
  }
  localStorage.setItem(AUDIT_LOG_KEY, JSON.stringify(log))
  return log
}

// Get last audit log
export function getAuditLog() {
  try {
    return JSON.parse(localStorage.getItem(AUDIT_LOG_KEY)) || null
  } catch { return null }
}

// Export audit log as markdown for Claude Code
export function exportAuditMarkdown(log) {
  if (!log) return ''
  let md = `# Velín Audit Report\n`
  md += `**Datum:** ${new Date(log.timestamp).toLocaleString('cs-CZ')}\n`
  md += `**Celkem kontrol:** ${log.summary.total}\n`
  md += `**Pass:** ${log.summary.pass} | **Fail:** ${log.summary.fail} | **Warning:** ${log.summary.warning} | **Manual:** ${log.summary.manual}\n\n`

  // Group by page
  const byPage = {}
  for (const r of log.results) {
    if (!byPage[r.pageId]) byPage[r.pageId] = { label: r.pageLabel, path: r.pagePath, checks: [] }
    byPage[r.pageId].checks.push(r)
  }

  for (const [pageId, page] of Object.entries(byPage)) {
    const fails = page.checks.filter(c => c.status === 'fail')
    const warns = page.checks.filter(c => c.status === 'warning')
    const statusIcon = fails.length ? 'FAIL' : warns.length ? 'WARN' : 'OK'
    md += `## ${statusIcon} ${page.label} (${page.path})\n`
    for (const c of page.checks) {
      const icon = c.status === 'pass' ? 'PASS' : c.status === 'fail' ? 'FAIL' : c.status === 'warning' ? 'WARN' : 'MANUAL'
      md += `- [${icon}] ${c.checkLabel}: ${c.detail}\n`
    }
    md += '\n'
  }

  // Issues section
  const issues = log.results.filter(r => r.status === 'fail' || r.status === 'warning')
  if (issues.length) {
    md += `## Issues to fix\n`
    for (const issue of issues) {
      md += `- **${issue.pageLabel}** > ${issue.checkLabel}: ${issue.detail}\n`
    }
  }

  return md
}

// Analyze missing features / flows based on audit
export function analyzeMissingFeatures(log) {
  if (!log) return []
  const suggestions = []

  const fails = log.results.filter(r => r.status === 'fail')
  const warnings = log.results.filter(r => r.status === 'warning')
  const manuals = log.results.filter(r => r.status === 'manual')

  for (const f of fails) {
    suggestions.push({
      severity: 'critical',
      page: f.pageLabel,
      path: f.pagePath,
      issue: f.checkLabel,
      detail: f.detail,
      suggestion: `Opravit: ${f.checkLabel} na stránce ${f.pageLabel} — query selhává`,
    })
  }

  for (const w of warnings) {
    suggestions.push({
      severity: 'warning',
      page: w.pageLabel,
      path: w.pagePath,
      issue: w.checkLabel,
      detail: w.detail,
      suggestion: `Ověřit: ${w.checkLabel} — tabulky jsou prázdné, zkontroluj zda je to očekávané`,
    })
  }

  // Check for missing CRUD operations
  const pagesWithCreate = log.results.filter(r => r.checkId?.includes('create') || r.checkId?.includes('_create'))
  const pagesWithoutCreate = VELIN_PAGES.filter(p =>
    !pagesWithCreate.some(c => c.pageId === p.id) &&
    !['dashboard', 'analyza', 'government'].includes(p.id)
  )
  for (const p of pagesWithoutCreate) {
    suggestions.push({
      severity: 'info',
      page: p.label,
      path: p.path,
      issue: 'Chybí tlačítko pro vytvoření záznamu',
      detail: '',
      suggestion: `Zvážit přidání "Nový záznam" tlačítka na stránce ${p.label}`,
    })
  }

  return suggestions
}
