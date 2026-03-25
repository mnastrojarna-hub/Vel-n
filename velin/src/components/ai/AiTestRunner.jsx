import { useState, useRef } from 'react'
import { supabase } from '../../lib/supabase'
import { loadAgentConfig, getEnabledTools, getAgentCorrections, AGENTS } from '../../lib/aiAgents'
import { buildAgentPromptsText } from '../../lib/aiAgentPrompts'
import { buildAllAgentMemory } from '../../lib/aiAgentMemory'
import { recordOutcome } from '../../lib/aiLearning'
import { auditAllPages, getAuditLog, exportAuditMarkdown, analyzeMissingFeatures, VELIN_PAGES } from '../../lib/aiVelinAuditor'
import { runAppFlowTest, exportAppFlowMarkdown, APP_FLOW_STEPS } from '../../lib/aiAppFlowTest'
import Button from '../ui/Button'

const APP_URL = 'https://motogo24.cz'
const TEST_STEPS = [
  { id: 'setup', label: 'Příprava testovacích dat', icon: '🔧', tools: ['create_test_user', 'create_test_promo'] },
  { id: 'consistency', label: 'Kontrola konzistence dat', icon: '🔍', tools: ['verify_app_consistency'] },
  { id: 'edge_fn', label: 'Kontrola Edge Functions', icon: '⚡', tools: ['check_edge_functions'] },
  { id: 'booking_flow', label: 'Test booking flow', icon: '📅', tools: ['test_booking_flow'] },
  { id: 'payment_flow', label: 'Test platební flow', icon: '💳', tools: ['test_payment_flow'] },
  { id: 'sos_flow', label: 'Test SOS flow', icon: '🚨', tools: ['test_sos_flow'] },
  { id: 'system_test', label: 'Kompletní systémový test', icon: '🔬', tools: ['run_full_system_test'] },
  { id: 'e2e_report', label: 'E2E report zákaznické app', icon: '📋', tools: ['generate_e2e_report'] },
  { id: 'cleanup', label: 'Úklid testovacích dat', icon: '🧹', tools: ['cleanup_test_data'] },
]

const STATUS_STYLE = {
  pass: { bg: '#dcfce7', border: '#22c55e', color: '#166534', icon: 'OK' },
  fail: { bg: '#fef2f2', border: '#ef4444', color: '#dc2626', icon: 'FAIL' },
  warning: { bg: '#fef3c7', border: '#f59e0b', color: '#92400e', icon: 'WARN' },
  manual: { bg: '#eff6ff', border: '#3b82f6', color: '#1e40af', icon: '?' },
  unknown: { bg: '#f9fafb', border: '#d1d5db', color: '#6b7280', icon: '-' },
}

export default function AiTestRunner() {
  const [view, setView] = useState('audit') // audit | e2e | log
  const [results, setResults] = useState({})
  const [running, setRunning] = useState(null)
  const [testUser, setTestUser] = useState(null)
  const [testPromo, setTestPromo] = useState(null)
  // Audit state
  const [auditRunning, setAuditRunning] = useState(false)
  const [auditProgress, setAuditProgress] = useState(null)
  const [auditLog, setAuditLog] = useState(() => getAuditLog())
  const [auditFilter, setAuditFilter] = useState('all')
  const [suggestions, setSuggestions] = useState([])
  const logRef = useRef(null)
  // App flow state
  const [appFlowResults, setAppFlowResults] = useState(null)
  const [appFlowRunning, setAppFlowRunning] = useState(false)
  const [appFlowProgress, setAppFlowProgress] = useState(null)

  // --- App Flow Test ---
  async function runAppFlow() {
    setAppFlowRunning(true)
    const results = await runAppFlowTest((p) => setAppFlowProgress(p))
    setAppFlowResults(results)
    setAppFlowRunning(false)
    setAppFlowProgress(null)
  }

  // --- E2E Tests (existing) ---
  async function runStep(step) {
    setRunning(step.id)
    const config = loadAgentConfig()
    const enabledIds = AGENTS.filter(a => config[a.id]?.enabled).map(a => a.id)
    try {
      const { data } = await supabase.functions.invoke('ai-copilot', {
        body: {
          message: `Spusť test: ${step.label}. Zavolej nástroje: ${step.tools.join(', ')}. Výsledky prezentuj strukturovaně.`,
          enabled_tools: [...getEnabledTools(config), ...step.tools],
          agent_corrections: getAgentCorrections(config),
          agent_prompts: buildAgentPromptsText(enabledIds),
          agent_memory: buildAllAgentMemory(enabledIds),
        },
      })
      const result = { response: data?.response, status: 'done', timestamp: new Date().toISOString() }
      setResults(r => ({ ...r, [step.id]: result }))
      if (step.id === 'setup' && data?.response) {
        const emailMatch = data.response.match(/test\.ai\.tester\+[^@]+@motogo24\.cz/)
        const promoMatch = data.response.match(/AITEST_[A-Z0-9]+/)
        if (emailMatch) setTestUser(emailMatch[0])
        if (promoMatch) setTestPromo(promoMatch[0])
      }
      recordOutcome('tester', step.id, {}, result, true)
    } catch (e) {
      setResults(r => ({ ...r, [step.id]: { status: 'error', error: e.message } }))
      recordOutcome('tester', step.id, {}, { error: e.message }, false)
    }
    setRunning(null)
  }

  async function runAllE2E() {
    for (const step of TEST_STEPS) await runStep(step)
  }

  // --- Velín Audit ---
  async function runAudit() {
    setAuditRunning(true)
    setAuditProgress({ phase: 'start' })
    try {
      const log = await auditAllPages((progress) => setAuditProgress(progress))
      setAuditLog(log)
      setSuggestions(analyzeMissingFeatures(log))
    } catch (e) {
      console.error('Audit error:', e)
    }
    setAuditRunning(false)
    setAuditProgress(null)
  }

  function copyAuditLog() {
    const md = exportAuditMarkdown(auditLog)
    navigator.clipboard.writeText(md)
    alert('Audit log zkopírován do schránky (Markdown)')
  }

  function downloadAuditLog() {
    const md = exportAuditMarkdown(auditLog)
    const blob = new Blob([md], { type: 'text/markdown' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `velin-audit-${new Date().toISOString().split('T')[0]}.md`
    a.click(); URL.revokeObjectURL(url)
  }

  // Filtered audit results
  const filteredResults = auditLog?.results?.filter(r =>
    auditFilter === 'all' || r.status === auditFilter
  ) || []

  // Group by page
  const byPage = {}
  for (const r of filteredResults) {
    if (!byPage[r.pageId]) byPage[r.pageId] = { label: r.pageLabel, path: r.pagePath, checks: [] }
    byPage[r.pageId].checks.push(r)
  }

  const doneCount = Object.keys(results).length
  const passCount = Object.values(results).filter(r => r.status === 'done').length

  return (
    <div>
      {/* View tabs */}
      <div style={{ display: 'flex', gap: 4, marginBottom: 12 }}>
        {[
          { id: 'appflow', label: 'App flow', icon: '📱' },
          { id: 'audit', label: 'Audit velínu', icon: '🔍' },
          { id: 'e2e', label: 'E2E testy', icon: '🧪' },
          { id: 'log', label: 'Návrhy oprav', icon: '💡' },
        ].map(v => (
          <button key={v.id} onClick={() => setView(v.id)} style={{
            padding: '8px 14px', borderRadius: 8, border: 'none', cursor: 'pointer', fontSize: 12, fontWeight: 700,
            background: view === v.id ? '#0f1a14' : '#f1f5f9', color: view === v.id ? '#74FB71' : '#666',
          }}>{v.icon} {v.label}</button>
        ))}
      </div>

      {/* ===================== APP FLOW VIEW ===================== */}
      {view === 'appflow' && (
        <div>
          <div className="flex items-center justify-between mb-3">
            <div>
              <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Test MotoGo24 App Flow</div>
              <div style={{ fontSize: 11, color: '#666' }}>
                {APP_FLOW_STEPS.length} kontrol: Auth, Katalog, Rezervace, Platby, Dokumenty, Zprávy, SOS, Edge
              </div>
            </div>
            <div className="flex gap-2">
              {appFlowResults && (
                <button onClick={() => { navigator.clipboard.writeText(exportAppFlowMarkdown(appFlowResults)); alert('Zkopírováno') }}
                  style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, border: '1px solid #d4e8e0', background: '#f8fcfa', cursor: 'pointer' }}>
                  Kopírovat MD
                </button>
              )}
              <Button green onClick={runAppFlow} disabled={appFlowRunning} style={{ fontSize: 12, padding: '6px 14px' }}>
                {appFlowRunning ? `Testuji… ${appFlowProgress?.label || ''}` : 'Spustit test'}
              </Button>
            </div>
          </div>

          {appFlowResults && (() => {
            const pass = appFlowResults.filter(r => r.ok).length
            const fail = appFlowResults.filter(r => !r.ok).length
            return (
              <div style={{ padding: '8px 12px', borderRadius: 8, marginBottom: 10,
                background: fail ? '#fef2f2' : '#dcfce7', border: `1px solid ${fail ? '#ef4444' : '#22c55e'}` }}>
                <span style={{ fontWeight: 700, fontSize: 13 }}>{pass} OK | {fail} FAIL | {appFlowResults.length} celkem</span>
              </div>
            )
          })()}

          {appFlowResults ? (() => {
            let lastPhase = ''
            return appFlowResults.map((r, i) => {
              const showPhase = r.phase !== lastPhase
              lastPhase = r.phase
              return (
                <div key={i}>
                  {showPhase && <div style={{ fontWeight: 800, fontSize: 12, color: '#0f1a14', marginTop: 8, marginBottom: 4 }}>{r.phase}</div>}
                  <div style={{
                    display: 'flex', gap: 8, padding: '5px 10px', marginBottom: 2, borderRadius: 6, fontSize: 11,
                    background: r.ok ? '#f0fdf4' : '#fef2f2', border: `1px solid ${r.ok ? '#d4e8e0' : '#fecaca'}`,
                  }}>
                    <span style={{ fontSize: 9, padding: '1px 5px', borderRadius: 4, fontWeight: 700, minWidth: 30, textAlign: 'center',
                      background: r.ok ? '#22c55e' : '#ef4444', color: '#fff' }}>{r.ok ? 'OK' : 'FAIL'}</span>
                    <span style={{ fontWeight: 600, color: '#0f1a14', minWidth: 180 }}>{r.label}</span>
                    <span style={{ color: r.ok ? '#666' : '#dc2626', flex: 1 }}>{r.detail}</span>
                  </div>
                </div>
              )
            })
          })() : (
            <div style={{ textAlign: 'center', padding: 30, color: '#999', fontSize: 12 }}>
              Test ověří celý zákaznický flow: přihlášení → katalog → ceník → dostupnost → platby → dokumenty → SOS → edge funkce.<br />
              Klikni "Spustit test" pro zahájení.
            </div>
          )}
        </div>
      )}

      {/* ===================== AUDIT VIEW ===================== */}
      {view === 'audit' && (
        <div>
          <div className="flex items-center justify-between mb-3">
            <div>
              <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Audit stránek Velínu</div>
              <div style={{ fontSize: 11, color: '#666' }}>
                {VELIN_PAGES.length} stránek, {VELIN_PAGES.reduce((s, p) => s + p.checks.length, 0)} kontrol
                {auditLog && ` | Poslední: ${new Date(auditLog.timestamp).toLocaleString('cs-CZ')}`}
              </div>
            </div>
            <div className="flex gap-2">
              {auditLog && (
                <>
                  <button onClick={copyAuditLog} style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, border: '1px solid #d4e8e0', background: '#f8fcfa', cursor: 'pointer' }}>
                    Kopírovat MD
                  </button>
                  <button onClick={downloadAuditLog} style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, border: '1px solid #d4e8e0', background: '#f8fcfa', cursor: 'pointer' }}>
                    Stáhnout .md
                  </button>
                </>
              )}
              <Button green onClick={runAudit} disabled={auditRunning} style={{ fontSize: 12, padding: '6px 14px' }}>
                {auditRunning ? `Audituji... ${auditProgress?.pageLabel || ''}` : 'Spustit audit'}
              </Button>
            </div>
          </div>

          {/* Summary bar */}
          {auditLog && (
            <div style={{ display: 'flex', gap: 8, marginBottom: 10 }}>
              {[
                { id: 'all', label: `Vše (${auditLog.summary.total})` },
                { id: 'pass', label: `OK (${auditLog.summary.pass})`, color: '#22c55e' },
                { id: 'fail', label: `Chyby (${auditLog.summary.fail})`, color: '#ef4444' },
                { id: 'warning', label: `Varování (${auditLog.summary.warning})`, color: '#f59e0b' },
                { id: 'manual', label: `Manuální (${auditLog.summary.manual})`, color: '#3b82f6' },
              ].map(f => (
                <button key={f.id} onClick={() => setAuditFilter(f.id)} style={{
                  padding: '4px 10px', borderRadius: 6, fontSize: 11, fontWeight: auditFilter === f.id ? 700 : 400,
                  border: auditFilter === f.id ? `2px solid ${f.color || '#0f1a14'}` : '1px solid #e5e7eb',
                  background: auditFilter === f.id ? (STATUS_STYLE[f.id]?.bg || '#f1f5f9') : '#fff',
                  color: f.color || '#333', cursor: 'pointer',
                }}>{f.label}</button>
              ))}
            </div>
          )}

          {/* Page-by-page results */}
          {auditLog && (
            <div ref={logRef} style={{ maxHeight: 500, overflow: 'auto' }}>
              {Object.entries(byPage).map(([pageId, page]) => {
                const hasFail = page.checks.some(c => c.status === 'fail')
                const hasWarn = page.checks.some(c => c.status === 'warning')
                return (
                  <div key={pageId} style={{
                    marginBottom: 8, borderRadius: 10, overflow: 'hidden',
                    border: `1px solid ${hasFail ? '#fecaca' : hasWarn ? '#fde68a' : '#d4e8e0'}`,
                  }}>
                    <div style={{
                      padding: '8px 12px', fontWeight: 700, fontSize: 12,
                      background: hasFail ? '#fef2f2' : hasWarn ? '#fef3c7' : '#f0fdf4',
                      color: hasFail ? '#dc2626' : hasWarn ? '#92400e' : '#166534',
                      display: 'flex', alignItems: 'center', gap: 6,
                    }}>
                      <span>{VELIN_PAGES.find(p => p.id === pageId)?.icon}</span>
                      <span style={{ flex: 1 }}>{page.label}</span>
                      <span style={{ fontSize: 10, color: '#666' }}>{page.path}</span>
                    </div>
                    {page.checks.map((c, i) => {
                      const st = STATUS_STYLE[c.status] || STATUS_STYLE.unknown
                      return (
                        <div key={i} style={{
                          display: 'flex', alignItems: 'start', gap: 6, padding: '5px 12px',
                          borderTop: '1px solid #f1f5f9', fontSize: 11,
                        }}>
                          <span style={{
                            fontSize: 9, padding: '1px 4px', borderRadius: 4, fontWeight: 700, minWidth: 32, textAlign: 'center',
                            background: st.bg, color: st.color, border: `1px solid ${st.border}`,
                          }}>{st.icon}</span>
                          <span style={{ fontWeight: 600, color: '#0f1a14', minWidth: 200 }}>{c.checkLabel}</span>
                          <span style={{ color: '#666', flex: 1, fontSize: 10 }}>{c.detail}</span>
                        </div>
                      )
                    })}
                  </div>
                )
              })}
            </div>
          )}

          {!auditLog && !auditRunning && (
            <div style={{ textAlign: 'center', padding: 30, color: '#999', fontSize: 12 }}>
              Klikni "Spustit audit" pro kontrolu všech stránek velínu.<br />
              Audit testuje dostupnost tabulek, datové toky a identifikuje chybějící funkce.
            </div>
          )}
        </div>
      )}

      {/* ===================== E2E VIEW ===================== */}
      {view === 'e2e' && (
        <div>
          <div className="flex items-center justify-between mb-3">
            <div>
              <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>E2E Test Runner</div>
              <div style={{ fontSize: 11, color: '#666' }}>{doneCount}/{TEST_STEPS.length} kroků | {passCount} úspěšných</div>
            </div>
            <Button green onClick={runAllE2E} disabled={!!running} style={{ fontSize: 12, padding: '6px 14px' }}>
              {running ? 'Běží...' : 'Spustit vše'}
            </Button>
          </div>

          {(testUser || testPromo) && (
            <div style={{ padding: '8px 12px', borderRadius: 8, background: '#eff6ff', border: '1px solid #bfdbfe', marginBottom: 8, fontSize: 12 }}>
              {testUser && <div><strong>Test účet:</strong> {testUser}</div>}
              {testPromo && <div><strong>100% promo:</strong> {testPromo}</div>}
              <a href={APP_URL} target="_blank" rel="noopener noreferrer" style={{ color: '#2563eb', textDecoration: 'underline', fontSize: 11 }}>
                Otevřít MotoGo24 App
              </a>
            </div>
          )}

          <div style={{ marginBottom: 8, padding: '8px 12px', borderRadius: 8, background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
            <div style={{ fontSize: 11, fontWeight: 700, marginBottom: 4, color: '#0f1a14' }}>Manuální testy v prohlížeči:</div>
            <div className="flex flex-wrap gap-2">
              {[
                { label: 'Registrace', url: `${APP_URL}/#register` },
                { label: 'Přihlášení', url: `${APP_URL}/#login` },
                { label: 'Reset hesla', url: `${APP_URL}/#reset` },
                { label: 'Katalog', url: `${APP_URL}/#catalog` },
                { label: 'Rezervace', url: `${APP_URL}/#booking` },
                { label: 'E-shop', url: `${APP_URL}/#shop` },
                { label: 'Profil', url: `${APP_URL}/#profile` },
              ].map(l => (
                <a key={l.label} href={l.url} target="_blank" rel="noopener noreferrer" style={{
                  fontSize: 10, padding: '3px 8px', borderRadius: 4, background: '#fff', border: '1px solid #d4e8e0', color: '#2563eb', textDecoration: 'none',
                }}>{l.label}</a>
              ))}
            </div>
          </div>

          <div className="space-y-2">
            {TEST_STEPS.map(step => {
              const result = results[step.id]
              const isRunning = running === step.id
              return (
                <div key={step.id} style={{
                  padding: '10px 12px', borderRadius: 10,
                  border: '1px solid ' + (result?.status === 'done' ? '#22c55e' : result?.status === 'error' ? '#ef4444' : '#d4e8e0'),
                  background: result?.status === 'done' ? '#f0fdf4' : result?.status === 'error' ? '#fef2f2' : '#fff',
                }}>
                  <div className="flex items-center gap-2">
                    <span style={{ fontSize: 14 }}>{step.icon}</span>
                    <span className="text-sm font-bold" style={{ color: '#0f1a14', flex: 1 }}>{step.label}</span>
                    {result?.status === 'done' && <span style={{ fontSize: 12, color: '#22c55e' }}>OK</span>}
                    {result?.status === 'error' && <span style={{ fontSize: 12, color: '#ef4444' }}>X</span>}
                    <Button onClick={() => runStep(step)} disabled={!!running} style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                      {isRunning ? '...' : 'Spustit'}
                    </Button>
                  </div>
                  {result?.response && (
                    <div style={{ marginTop: 6, fontSize: 11, color: '#1a2e22', lineHeight: 1.5, maxHeight: 150, overflow: 'auto', whiteSpace: 'pre-wrap', background: '#f8fcfa', padding: 8, borderRadius: 6 }}>
                      {result.response}
                    </div>
                  )}
                  {result?.error && <div style={{ marginTop: 4, fontSize: 11, color: '#dc2626' }}>Chyba: {result.error}</div>}
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* ===================== SUGGESTIONS VIEW ===================== */}
      {view === 'log' && (
        <div>
          <div className="flex items-center justify-between mb-3">
            <div>
              <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Návrhy oprav a chybějící funkce</div>
              <div style={{ fontSize: 11, color: '#666' }}>
                Na základě auditu — {suggestions.length} návrhů
              </div>
            </div>
            {!suggestions.length && auditLog && (
              <button onClick={() => setSuggestions(analyzeMissingFeatures(auditLog))}
                style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, border: '1px solid #d4e8e0', background: '#f8fcfa', cursor: 'pointer' }}>
                Analyzovat
              </button>
            )}
          </div>

          {suggestions.length === 0 && (
            <div style={{ textAlign: 'center', padding: 30, color: '#999', fontSize: 12 }}>
              Nejprve spusť audit velínu, potom se zde zobrazí návrhy na opravy.
            </div>
          )}

          {suggestions.map((s, i) => (
            <div key={i} style={{
              padding: '8px 12px', marginBottom: 6, borderRadius: 8,
              background: s.severity === 'critical' ? '#fef2f2' : s.severity === 'warning' ? '#fef3c7' : '#eff6ff',
              border: `1px solid ${s.severity === 'critical' ? '#fecaca' : s.severity === 'warning' ? '#fde68a' : '#bfdbfe'}`,
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 2 }}>
                <span style={{
                  fontSize: 9, padding: '1px 6px', borderRadius: 4, fontWeight: 700,
                  background: s.severity === 'critical' ? '#dc2626' : s.severity === 'warning' ? '#f59e0b' : '#3b82f6',
                  color: '#fff',
                }}>{s.severity === 'critical' ? 'CRITICAL' : s.severity === 'warning' ? 'WARNING' : 'INFO'}</span>
                <span style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14' }}>{s.page}</span>
                <span style={{ fontSize: 10, color: '#666' }}>{s.path}</span>
              </div>
              <div style={{ fontSize: 11, color: '#1a2e22', marginBottom: 2 }}>{s.issue}</div>
              {s.detail && <div style={{ fontSize: 10, color: '#666' }}>{s.detail}</div>}
              <div style={{ fontSize: 11, color: '#2563eb', marginTop: 2, fontStyle: 'italic' }}>{s.suggestion}</div>
            </div>
          ))}

          {/* Export for Claude Code */}
          {auditLog && (
            <div style={{ marginTop: 12, padding: 10, borderRadius: 8, background: '#f1f5f9', border: '1px solid #e2e8f0' }}>
              <div style={{ fontSize: 11, fontWeight: 700, color: '#0f1a14', marginBottom: 4 }}>Export pro Claude Code</div>
              <div style={{ fontSize: 10, color: '#666', marginBottom: 6 }}>
                Zkopíruj audit log jako Markdown a vlož do Claude Code pro automatickou analýzu a opravu bugů.
              </div>
              <div className="flex gap-2">
                <button onClick={copyAuditLog} style={{
                  fontSize: 11, padding: '6px 14px', borderRadius: 6, border: 'none',
                  background: '#0f1a14', color: '#74FB71', cursor: 'pointer', fontWeight: 700,
                }}>Kopírovat Markdown do schránky</button>
                <button onClick={downloadAuditLog} style={{
                  fontSize: 11, padding: '6px 14px', borderRadius: 6, border: '1px solid #d4e8e0',
                  background: '#fff', cursor: 'pointer',
                }}>Stáhnout .md soubor</button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
