// Nálezy agentů — český dashboard s checkboxy pro reportování
import { useState } from 'react'
import { AGENTS } from '../../lib/aiAgents'
import { getAgentLearningLog, getMetrics } from '../../lib/aiLearning'

const SEV = {
  ok:   { bg: '#dcfce7', color: '#166534', label: 'OK', cz: 'V pořádku' },
  fail: { bg: '#fef2f2', color: '#dc2626', label: 'PROBLÉM', cz: 'Nalezen problém' },
  warn: { bg: '#fef3c7', color: '#92400e', label: 'VAROVÁNÍ', cz: 'Vyžaduje pozornost' },
  info: { bg: '#eff6ff', color: '#1e40af', label: 'INFO', cz: 'Informace' },
}

// Czech descriptions for known actions
const ACTION_DESC = {
  // Fleet
  alert_stk_expiring: 'STK brzy vyprší — naplánovat kontrolu',
  alert_stk_expired: 'STK PROŠLÁ — motorka nesmí jezdit!',
  alert_stk_missing: 'STK není vyplněna v systému',
  inconsistency_active_but_in_service: 'Motorka je "aktivní" ale má otevřenou servisní zakázku',
  alert_no_pricing: 'Motorka nemá nastavený ceník',
  check_stk: 'Kontrola platnosti STK',
  cross_check_service_ok: 'Servis vs stav motorky — v pořádku',
  moto_has_active_bookings: 'Motorka má aktivní rezervace',
  moto_no_bookings: 'Motorka nemá žádné rezervace',
  fetch_fleet: 'Načtení flotily',
  set_maintenance: 'Motorka přepnuta do servisu',
  verify_returned_active: 'Motorka vrácena do stavu "aktivní"',
  detect_maintenance: 'Detekce přechodu do servisu',
  verify_active: 'Kontrola návratu motorky do stavu "aktivní" po servisu',
  verify_pricing_set: 'Ceník je nastaven',
  verify_pricing: 'Kontrola ceníku',
  // Customers
  alert_incomplete_profile: 'Zákazník má nekompletní profil (chybí telefon/doklady)',
  detect_booking_without_docs: 'Zákazník má rezervaci ale nemá ověřené doklady!',
  detect_missing_docs: 'Zákazníkovi chybí doklady',
  detect_duplicate_profiles: 'Nalezeny duplicitní profily (stejný email)',
  detect_incomplete_profile: 'Nekompletní profil zákazníka',
  detect_no_docs: 'Zákazník bez dokladů',
  pool_created: 'Testovací zákazníci vytvořeni',
  verify_profile: 'Kontrola profilu zákazníka',
  verify_profile_completeness: 'Kontrola kompletnosti profilu',
  handle_live_message: 'Zpracování živé zprávy od zákazníka',
  handle_message: 'Zpracování zprávy',
  check_blocked_status: 'Kontrola blokace zákazníka',
  booking_without_docs: 'Rezervace vytvořena bez dokladů',
  // Bookings
  customer_reserves: 'Zákazník vytvořil rezervaci',
  customer_pays: 'Zákazník zaplatil',
  customer_picks_up: 'Zákazník vyzvednul motorku',
  customer_returns: 'Zákazník vrátil motorku',
  customer_extends: 'Zákazník prodloužil rezervaci',
  customer_shortens: 'Zákazník zkrátil rezervaci',
  customer_cancels: 'Zákazník stornoval rezervaci',
  customer_complains: 'Zákazník podal reklamaci',
  customer_rates_5: 'Zákazník hodnotil 5 hvězdiček',
  customer_rates_4: 'Zákazník hodnotil 4 hvězdičky',
  customer_rates_3: 'Zákazník hodnotil 3 hvězdičky',
  customer_rates_2: 'Zákazník hodnotil 2 hvězdičky',
  customer_rates_1: 'Zákazník hodnotil 1 hvězdičku',
  complaint_during_ride: 'Zákazník si stěžuje během jízdy',
  auto_cancel_no_payment: 'Automatické storno — zákazník nezaplatil',
  waiting_for_payment: 'Čeká se na platbu',
  payment_confirmed: 'Platba potvrzena',
  velin_created_booking: 'Velín vytvořil rezervaci',
  change_pickup_location: 'Změna místa vyzvednutí',
  change_return_location: 'Změna místa vrácení',
  watchdog_availability: 'Kontrola dostupnosti motorky',
  verify_price: 'Kontrola ceny',
  verify_invoice_generated: 'Kontrola vygenerování faktury',
  edge_shorten: 'Test zkrácení rezervace',
  cancel_and_verify: 'Storno a kontrola',
  create_for_change_test: 'Rezervace pro test změny',
  detect_overlap: 'Detekována kolize termínů — motorka je již zarezervována',
  first_booking: 'První rezervace (test kolize)',
  booking_no_docs: 'Rezervace bez dokladů (test)',
  edge_cancel_after_pay: 'Test storna po zaplacení',
  edge_booking_on_maintenance_moto: 'Test rezervace motorky v servisu',
  edge_multiple_bookings: 'Test více rezervací jednoho zákazníka',
  // Finance
  alert_missing_kf: 'Po dokončení rezervace se NEVYGENEROVALA konečná faktura',
  alert_zero_price: 'Ceník vrací nulovou cenu — chyba v nastavení',
  verify_kf_generated: 'Kontrola vygenerování konečné faktury',
  cross_check_payment_invoice: 'Zaplacená rezervace — kontrola existence faktury',
  verify_document_chain: 'Kontrola kompletní dokladové řady (ZF→DL→KF)',
  verify_price_calculation: 'Kontrola výpočtu ceny',
  verify_promo_discount: 'Kontrola slevy promo kódu',
  create_test_promo: 'Vytvoření testovacího promo kódu',
  verify_payment: 'Kontrola platby',
  verify_promo: 'Kontrola promo kódu',
  // Service
  verify_log: 'Kontrola zápisu do servisního logu',
  verify_log_entry: 'Kontrola záznamu v servisním logu',
  sos_triggered_repair: 'SOS incident vyvolal servisní zakázku',
  velin_created_order: 'Velín vytvořil servisní zakázku',
  verify_repair: 'Kontrola opravy',
  sos_service: 'Servisní zakázka po SOS',
  // SOS
  sos_light: 'Lehký SOS incident (porucha/defekt)',
  sos_heavy: 'Těžký SOS incident (nehoda/krádež)',
  create_incident: 'Vytvořen SOS incident',
  coordinate: 'Koordinace řešení SOS',
  resolve: 'SOS incident vyřešen',
  booking_failed: 'Rezervace pro SOS se nepodařila',
  post_sos_complete: 'Rezervace dokončena po SOS',
  coordinate_technician: 'Přiřazen technik',
  // HR
  alert_missing_checkout: 'Zaměstnanci nemají zapsaný odchod v docházce',
  alert_pending_vacations: 'Neschválené žádosti o dovolenou',
  inconsistency_vacation_vs_shift: 'Zaměstnanec na dovolené má přiřazenou směnu!',
  alert_overtime: 'Překročen limit přesčasů (>5 směn/týden)',
  fetch_employees: 'Načtení zaměstnanců',
  verify_employee_profile: 'Kontrola profilu zaměstnance',
  fetch_shifts: 'Načtení směn',
  check_11h_rest: 'Kontrola 11h odpočinku mezi směnami',
  fetch_attendance: 'Načtení docházky',
  fetch_vacations: 'Načtení dovolených',
  vacation_shift_ok: 'Dovolená vs směny — v pořádku',
  check_overtime_ok: 'Přesčasy v normě',
  fetch_employee_docs: 'Načtení dokumentů zaměstnanců',
  // Analytics
  anomaly_no_price: 'Aktivní motorky bez nastaveného ceníku',
  fetch_fleet_data: 'Načtení dat flotily',
  count_bookings_reserved: 'Počet rezervací ve stavu "rezervováno"',
  count_bookings_active: 'Počet aktivních rezervací',
  count_bookings_completed: 'Počet dokončených rezervací',
  count_bookings_cancelled: 'Počet stornovaných rezervací',
  customer_segmentation: 'Segmentace zákazníků',
  sos_by_type: 'SOS incidenty dle typu',
  price_analysis: 'Cenová analýza',
  branch_occupancy: 'Obsazenost pobočky',
  rating_analysis: 'Analýza hodnocení zákazníků',
  analyze_pricing: 'Analýza ceníku motorky',
  analyze_branches: 'Analýza poboček',
  generate_report: 'Generování reportu',
  // Government
  alert_stk_critical: 'STK vyprší do 14 dní — URGENTNÍ',
  alert_stk_warning: 'STK vyprší do 30 dní',
  inconsistency_expired_stk_active: 'Motorka s prošlou STK je stále ve stavu "aktivní"!',
  check_vin_completeness: 'Kontrola vyplnění VIN u všech motorek',
  check_spz_completeness: 'Kontrola vyplnění SPZ u všech motorek',
  verify_stk: 'Kontrola platnosti STK',
  compliance_summary: 'Souhrn shody s předpisy',
  // CMS
  alert_empty_template: 'Emailová šablona má prázdný obsah — nebude fungovat',
  alert_empty_msg_templates: 'Šablony zpráv s prázdným obsahem',
  alert_missing_contract_template: 'CHYBÍ šablona nájemní smlouvy!',
  alert_missing_vop_template: 'CHYBÍ šablona VOP!',
  fetch_settings: 'Načtení nastavení',
  fetch_email_templates: 'Načtení emailových šablon',
  verify_email_template: 'Kontrola emailové šablony',
  fetch_message_templates: 'Načtení šablon zpráv',
  check_contract_template: 'Kontrola šablony smlouvy',
  check_vop_template: 'Kontrola šablony VOP',
  fetch_automation_rules: 'Načtení automatických pravidel',
  automation_summary: 'Souhrn automatických pravidel',
  template_trigger_consistency: 'Konzistence šablon a pravidel',
  // Tester
  fk_bookings_moto: 'Integrita dat: rezervace → motorka',
  fk_bookings_user: 'Integrita dat: rezervace → zákazník',
  completed_has_returned_at: 'Dokončené rezervace mají datum vrácení',
  active_has_paid: 'Aktivní rezervace mají zaplaceno',
  resolved_has_date: 'Vyřešené SOS mají datum vyřešení',
  active_has_price: 'Aktivní motorky mají nastavený ceník',
  orphan_threads: 'Konverzace bez zpráv (osiřelé záznamy)',
  invoices_complete: 'Faktury mají číslo a částku',
  branches_audit: 'Kontrola poboček',
  admin_users_exist: 'Existence admin uživatelů',
  integrity_summary: 'Celkový souhrn integrity dat',
  // Orchestrator
  check_unassigned_sos: 'Otevřené SOS incidenty bez přiřazeného řešitele',
  check_old_unpaid: 'Nezaplacené rezervace starší 24 hodin',
  check_long_maintenance: 'Servisní zakázky otevřené déle než 7 dní',
  check_closed_branches: 'Zavřené pobočky',
  check_unanswered_messages: 'Nezodpovězené zprávy zákazníků',
  check_admin_users: 'Kontrola admin uživatelů',
  kpi_summary: 'Souhrn klíčových ukazatelů (KPI)',
  agent_coordination_check: 'Kontrola zdraví všech agentů',
  // Eshop
  create_promo: 'Vytvoření promo kódu',
  verify_promo: 'Kontrola promo kódu',
  promo_audit: 'Audit promo kódů',
  alert_expired_active_promos: 'Promo kódy po expiraci stále aktivní!',
  alert_overused_promos: 'Promo kódy překročily limit použití!',
  fetch_accessory_types: 'Načtení příslušenství',
  voucher_audit: 'Audit voucherů',
  alert_expired_vouchers: 'Vouchery po expiraci stále aktivní!',
  fetch_orders: 'Načtení objednávek',
  pending_orders: 'Nevyřízené objednávky',
  verify_stock: 'Kontrola skladu',
}

function classify(entry) {
  if (!entry.success) return 'fail'
  if (entry.action?.includes('alert_') || entry.action?.includes('inconsistency_')) return 'fail'
  if (entry.action?.includes('detect_') || entry.action?.includes('anomaly_')) return 'warn'
  if (entry.action?.includes('verify_') || entry.action?.includes('check_') || entry.action?.includes('cross_check')) return 'ok'
  return 'info'
}

function descCz(entry) {
  const desc = ACTION_DESC[entry.action]
  if (desc) return desc
  // Fallback: humanize action name
  return (entry.action || '').replace(/_/g, ' ').replace(/^[a-z]/, c => c.toUpperCase())
}

function detailCz(entry) {
  const s = entry.result_summary
  if (!s || s === 'ok') return ''
  return s
}

export default function AiAgentFindingsPanel() {
  const [selected, setSelected] = useState('all')
  const [showOk, setShowOk] = useState(false)
  const [checked, setChecked] = useState({}) // { index: true }
  const [expanded, setExpanded] = useState({}) // { index: true }
  const [showExport, setShowExport] = useState(false)
  const metrics = getMetrics()

  // Build all findings
  const allFindings = []
  for (const a of AGENTS) {
    for (const entry of getAgentLearningLog(a.id)) {
      allFindings.push({ ...entry, agentId: a.id, severity: classify(entry) })
    }
  }

  // Filter + sort
  let filtered = allFindings
  if (selected !== 'all') filtered = filtered.filter(f => f.agentId === selected)
  if (!showOk) filtered = filtered.filter(f => f.severity !== 'ok' && f.severity !== 'info')
  filtered.sort((a, b) => ({ fail: 0, warn: 1, info: 2, ok: 3 }[a.severity] || 9) - ({ fail: 0, warn: 1, info: 2, ok: 3 }[b.severity] || 9))

  // Agent summary
  const summary = {}
  for (const a of AGENTS) {
    const findings = allFindings.filter(f => f.agentId === a.id)
    summary[a.id] = {
      problems: findings.filter(f => f.severity === 'fail').length,
      warnings: findings.filter(f => f.severity === 'warn').length,
      total: metrics[a.id]?.total || 0,
      confidence: metrics[a.id]?.confidence || 0,
    }
  }
  const totP = Object.values(summary).reduce((s, a) => s + a.problems, 0)
  const totW = Object.values(summary).reduce((s, a) => s + a.warnings, 0)
  const checkedCount = Object.values(checked).filter(Boolean).length

  // Toggle check
  function toggle(i) { setChecked(p => ({ ...p, [i]: !p[i] })) }
  function checkAllProblems() {
    const next = { ...checked }
    filtered.forEach((f, i) => { if (f.severity === 'fail' || f.severity === 'warn') next[i] = true })
    setChecked(next)
  }
  function uncheckAll() { setChecked({}) }

  // Export selected as markdown
  function exportSelected() {
    const items = filtered.filter((_, i) => checked[i])
    if (!items.length) return
    let md = `# Report nálezů agentů — MotoGo24\n**${new Date().toLocaleString('cs-CZ')}**\n**${items.length} vybraných problémů k řešení**\n\n`
    let lastAgent = ''
    for (const f of items) {
      const agent = AGENTS.find(a => a.id === f.agentId)
      if (f.agentId !== lastAgent) {
        md += `\n## ${agent?.icon} ${agent?.name}\n`
        lastAgent = f.agentId
      }
      const sev = SEV[f.severity]
      md += `- **[${sev.label}]** ${descCz(f)}`
      const det = detailCz(f)
      if (det) md += ` — ${det}`
      if (f.timestamp) md += ` _(${new Date(f.timestamp).toLocaleString('cs-CZ')})_`
      md += '\n'
    }
    md += `\n---\nVygenerováno z Velín AI Ředitel\n`
    setShowExport(md)
  }

  return (
    <div>
      {/* Souhrn */}
      <div style={{
        padding: '12px 16px', borderRadius: 12, marginBottom: 12,
        background: totP > 0 ? '#fef2f2' : totW > 0 ? '#fef3c7' : '#dcfce7',
        border: `2px solid ${totP > 0 ? '#ef4444' : totW > 0 ? '#f59e0b' : '#22c55e'}`,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div>
          <div style={{ fontWeight: 800, fontSize: 14, color: '#0f1a14' }}>
            {totP} {totP === 1 ? 'problém' : totP < 5 ? 'problémy' : 'problémů'} | {totW} {totW === 1 ? 'varování' : 'varování'} | {allFindings.length} kontrol celkem
          </div>
          <div style={{ fontSize: 11, color: '#666' }}>Nálezy z posledního tréninku všech {AGENTS.length} agentů</div>
        </div>
        <div className="flex gap-2 items-center">
          <label style={{ fontSize: 11, display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
            <input type="checkbox" checked={showOk} onChange={e => setShowOk(e.target.checked)} /> Zobrazit i OK
          </label>
        </div>
      </div>

      {/* Filtr agentů */}
      <div style={{ display: 'flex', gap: 4, marginBottom: 10, flexWrap: 'wrap' }}>
        <button onClick={() => setSelected('all')} style={{
          padding: '4px 10px', borderRadius: 6, fontSize: 11, fontWeight: selected === 'all' ? 700 : 400, cursor: 'pointer',
          border: selected === 'all' ? '2px solid #0f1a14' : '1px solid #e5e7eb',
          background: selected === 'all' ? '#0f1a14' : '#fff', color: selected === 'all' ? '#74FB71' : '#666',
        }}>Všichni ({totP + totW})</button>
        {AGENTS.map(a => {
          const s = summary[a.id]; const has = s.problems > 0 || s.warnings > 0
          return (<button key={a.id} onClick={() => setSelected(a.id)} style={{
            padding: '4px 8px', borderRadius: 6, fontSize: 11, cursor: 'pointer', fontWeight: selected === a.id ? 700 : 400,
            border: selected === a.id ? '2px solid #0f1a14' : `1px solid ${has ? '#fecaca' : '#e5e7eb'}`,
            background: selected === a.id ? '#0f1a14' : has ? '#fef2f2' : '#fff', color: selected === a.id ? '#74FB71' : has ? '#dc2626' : '#666',
          }}>{a.icon} {s.problems > 0 ? s.problems : s.warnings > 0 ? s.warnings : 'ok'}</button>)
        })}
      </div>

      {/* Akce: vybrat vše / zrušit / reportovat */}
      <div style={{ display: 'flex', gap: 6, marginBottom: 8 }}>
        <button onClick={checkAllProblems} style={{ fontSize: 10, padding: '3px 8px', borderRadius: 4, border: '1px solid #d4e8e0', background: '#f8fcfa', cursor: 'pointer' }}>
          Vybrat všechny problémy
        </button>
        {checkedCount > 0 && (
          <>
            <button onClick={uncheckAll} style={{ fontSize: 10, padding: '3px 8px', borderRadius: 4, border: '1px solid #e5e7eb', background: '#fff', cursor: 'pointer' }}>
              Zrušit výběr
            </button>
            <button onClick={exportSelected} style={{ fontSize: 10, padding: '3px 8px', borderRadius: 4, border: 'none', background: '#0f1a14', color: '#74FB71', cursor: 'pointer', fontWeight: 700 }}>
              Reportovat vybrané ({checkedCount})
            </button>
          </>
        )}
      </div>

      {/* Kartičky agentů */}
      {selected === 'all' && (
        <div className="grid grid-cols-3 gap-2" style={{ marginBottom: 12 }}>
          {AGENTS.map(a => {
            const s = summary[a.id]
            return (<div key={a.id} onClick={() => setSelected(a.id)} style={{
              padding: '8px 10px', borderRadius: 8, cursor: 'pointer',
              border: `1px solid ${s.problems ? '#fecaca' : s.warnings ? '#fde68a' : '#d4e8e0'}`,
              background: s.problems ? '#fef2f2' : s.warnings ? '#fef3c7' : '#f8fcfa',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 4, marginBottom: 2 }}>
                <span style={{ fontSize: 14 }}>{a.icon}</span>
                <span style={{ fontWeight: 700, fontSize: 11, color: '#0f1a14', flex: 1 }}>{a.name}</span>
              </div>
              <div style={{ fontSize: 10, color: '#666' }}>{s.total} kontrol | {s.confidence}%</div>
              {s.problems > 0 && <div style={{ fontSize: 10, color: '#dc2626', fontWeight: 700 }}>{s.problems} {s.problems === 1 ? 'problém' : 'problémů'}</div>}
              {s.warnings > 0 && <div style={{ fontSize: 10, color: '#92400e', fontWeight: 700 }}>{s.warnings} varování</div>}
              {!s.problems && !s.warnings && s.total > 0 && <div style={{ fontSize: 10, color: '#22c55e' }}>Vše OK</div>}
              {!s.total && <div style={{ fontSize: 10, color: '#999' }}>Netrénován</div>}
            </div>)
          })}
        </div>
      )}

      {/* Seznam nálezů */}
      <div style={{ maxHeight: 500, overflow: 'auto' }}>
        {filtered.length === 0 && (
          <div style={{ textAlign: 'center', padding: 30, color: '#999', fontSize: 12 }}>
            {showOk ? 'Žádné záznamy. Spusťte trénink.' : 'Žádné problémy nalezeny. Zapněte "Zobrazit i OK" pro kompletní přehled.'}
          </div>
        )}
        {filtered.map((f, i) => {
          const agent = AGENTS.find(a => a.id === f.agentId)
          const sev = SEV[f.severity] || SEV.info
          const isExpanded = expanded[i]
          const isChecked = checked[i]
          return (
            <div key={i} style={{
              marginBottom: 3, borderRadius: 8, background: sev.bg, border: `1px solid ${sev.color}33`,
              overflow: 'hidden',
            }}>
              <div style={{ display: 'flex', gap: 6, padding: '6px 10px', alignItems: 'center', cursor: 'pointer' }}
                onClick={() => setExpanded(p => ({ ...p, [i]: !p[i] }))}>
                {(f.severity === 'fail' || f.severity === 'warn') && (
                  <input type="checkbox" checked={!!isChecked} onChange={() => toggle(i)}
                    onClick={e => e.stopPropagation()}
                    style={{ width: 14, height: 14, cursor: 'pointer' }} />
                )}
                <span style={{
                  fontSize: 9, padding: '1px 5px', borderRadius: 4, fontWeight: 700,
                  background: sev.color, color: '#fff', minWidth: 55, textAlign: 'center',
                }}>{sev.label}</span>
                <span style={{ fontSize: 14 }}>{agent?.icon}</span>
                <div style={{ flex: 1, fontSize: 11 }}>
                  <span style={{ fontWeight: 600, color: '#0f1a14' }}>{descCz(f)}</span>
                </div>
                <span style={{ fontSize: 10, color: '#999' }}>
                  {f.timestamp ? new Date(f.timestamp).toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' }) : ''}
                </span>
                <span style={{ fontSize: 12, color: '#999', transform: isExpanded ? 'rotate(180deg)' : '', transition: 'transform 0.15s' }}>v</span>
              </div>
              {isExpanded && (
                <div style={{ padding: '6px 10px 8px 36px', borderTop: `1px solid ${sev.color}22`, fontSize: 11 }}>
                  <div style={{ color: '#666', marginBottom: 2 }}><b>Agent:</b> {agent?.name} ({f.agentId})</div>
                  <div style={{ color: '#666', marginBottom: 2 }}><b>Akce:</b> {f.action}</div>
                  {detailCz(f) && <div style={{ color: sev.color, marginBottom: 2 }}><b>Detail:</b> {detailCz(f)}</div>}
                  {f.input_summary && <div style={{ color: '#666', marginBottom: 2 }}><b>Vstup:</b> {f.input_summary}</div>}
                  <div style={{ color: '#999' }}><b>Čas:</b> {f.timestamp ? new Date(f.timestamp).toLocaleString('cs-CZ') : '—'}</div>
                </div>
              )}
            </div>
          )
        })}
      </div>

      {/* Export modal */}
      {showExport && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 9999, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,0,0,0.5)' }}>
          <div style={{ background: '#fff', borderRadius: 16, width: '90%', maxWidth: 700, maxHeight: '85vh', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
            <div style={{ padding: '14px 18px', borderBottom: '2px solid #d4e8e0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <span style={{ fontWeight: 800, fontSize: 15 }}>Report nálezů — zkopírujte pro Claude Code</span>
              <button onClick={() => setShowExport(false)} style={{ background: 'none', border: 'none', fontSize: 18, cursor: 'pointer', color: '#999' }}>X</button>
            </div>
            <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
              <textarea value={showExport} readOnly style={{
                width: '100%', minHeight: 300, fontSize: 11, padding: 10, borderRadius: 8,
                border: '1px solid #d4e8e0', fontFamily: 'monospace', lineHeight: 1.5, resize: 'vertical',
              }} />
            </div>
            <div style={{ padding: '12px 18px', borderTop: '1px solid #d4e8e0', display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
              <button onClick={() => { navigator.clipboard.writeText(showExport); alert('Zkopírováno do schránky!') }}
                style={{ padding: '8px 18px', borderRadius: 8, border: 'none', background: '#0f1a14', color: '#74FB71', cursor: 'pointer', fontWeight: 700 }}>
                Kopírovat do schránky
              </button>
              <button onClick={() => setShowExport(false)}
                style={{ padding: '8px 18px', borderRadius: 8, border: '1px solid #d4e8e0', background: '#fff', cursor: 'pointer' }}>
                Zavřít
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
