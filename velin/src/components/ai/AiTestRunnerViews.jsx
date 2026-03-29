import { useState, useRef } from 'react'
import { auditAllPages, getAuditLog, exportAuditMarkdown, analyzeMissingFeatures, VELIN_PAGES } from '../../lib/aiVelinAuditor'
import { runAppFlowTest, exportAppFlowMarkdown, APP_FLOW_STEPS } from '../../lib/aiAppFlowTest'
import Button from '../ui/Button'

const STATUS_STYLE = {
  pass: { bg: '#dcfce7', border: '#22c55e', color: '#166534', icon: 'OK' },
  fail: { bg: '#fef2f2', border: '#ef4444', color: '#dc2626', icon: 'FAIL' },
  warning: { bg: '#fef3c7', border: '#f59e0b', color: '#92400e', icon: 'WARN' },
  manual: { bg: '#eff6ff', border: '#3b82f6', color: '#1e40af', icon: '?' },
  unknown: { bg: '#f9fafb', border: '#d1d5db', color: '#6b7280', icon: '-' },
}

export function AppFlowView({ appFlowResults, appFlowRunning, appFlowProgress, runAppFlow }) {
  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <div>
          <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Test MotoGo24 App Flow</div>
          <div style={{ fontSize: 11, color: '#666' }}>{APP_FLOW_STEPS.length} kontrol: Auth, Katalog, Rezervace, Platby, Dokumenty, Zprávy, SOS, Edge</div>
        </div>
        <div className="flex gap-2">
          {appFlowResults && <button onClick={() => { navigator.clipboard.writeText(exportAppFlowMarkdown(appFlowResults)); alert('Zkopírováno') }} style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, border: '1px solid #d4e8e0', background: '#f8fcfa', cursor: 'pointer' }}>Kopírovat MD</button>}
          <Button green onClick={runAppFlow} disabled={appFlowRunning} style={{ fontSize: 12, padding: '6px 14px' }}>{appFlowRunning ? `Testuji… ${appFlowProgress?.label || ''}` : 'Spustit test'}</Button>
        </div>
      </div>
      {appFlowResults && (() => { const pass = appFlowResults.filter(r => r.ok).length; const fail = appFlowResults.filter(r => !r.ok).length; return (<div style={{ padding: '8px 12px', borderRadius: 8, marginBottom: 10, background: fail ? '#fef2f2' : '#dcfce7', border: `1px solid ${fail ? '#ef4444' : '#22c55e'}` }}><span style={{ fontWeight: 700, fontSize: 13 }}>{pass} OK | {fail} FAIL | {appFlowResults.length} celkem</span></div>) })()}
      {appFlowResults ? (() => { let lastPhase = ''; return appFlowResults.map((r, i) => { const showPhase = r.phase !== lastPhase; lastPhase = r.phase; return (<div key={i}>{showPhase && <div style={{ fontWeight: 800, fontSize: 12, color: '#0f1a14', marginTop: 8, marginBottom: 4 }}>{r.phase}</div>}<div style={{ display: 'flex', gap: 8, padding: '5px 10px', marginBottom: 2, borderRadius: 6, fontSize: 11, background: r.ok ? '#f0fdf4' : '#fef2f2', border: `1px solid ${r.ok ? '#d4e8e0' : '#fecaca'}` }}><span style={{ fontSize: 9, padding: '1px 5px', borderRadius: 4, fontWeight: 700, minWidth: 30, textAlign: 'center', background: r.ok ? '#22c55e' : '#ef4444', color: '#fff' }}>{r.ok ? 'OK' : 'FAIL'}</span><span style={{ fontWeight: 600, color: '#0f1a14', minWidth: 180 }}>{r.label}</span><span style={{ color: r.ok ? '#666' : '#dc2626', flex: 1 }}>{r.detail}</span></div></div>) }) })() : (<div style={{ textAlign: 'center', padding: 30, color: '#999', fontSize: 12 }}>Test ověří celý zákaznický flow: přihlášení → katalog → ceník → dostupnost → platby → dokumenty → SOS → edge funkce.<br />Klikni "Spustit test" pro zahájení.</div>)}
    </div>
  )
}

export function AuditView({ auditLog: initialLog, auditRunning: initialRunning }) {
  const [auditRunning, setAuditRunning] = useState(initialRunning || false)
  const [auditProgress, setAuditProgress] = useState(null)
  const [auditLog, setAuditLog] = useState(() => initialLog || getAuditLog())
  const [auditFilter, setAuditFilter] = useState('all')
  const logRef = useRef(null)

  async function runAudit() {
    setAuditRunning(true); setAuditProgress({ phase: 'start' })
    try { const log = await auditAllPages((p) => setAuditProgress(p)); setAuditLog(log) } catch (e) { console.error('Audit error:', e) }
    setAuditRunning(false); setAuditProgress(null)
  }

  function copyAuditLog() { navigator.clipboard.writeText(exportAuditMarkdown(auditLog)); alert('Audit log zkopírován do schránky (Markdown)') }
  function downloadAuditLog() { const md = exportAuditMarkdown(auditLog); const blob = new Blob([md], { type: 'text/markdown' }); const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = `velin-audit-${new Date().toISOString().split('T')[0]}.md`; a.click(); URL.revokeObjectURL(url) }

  const filteredResults = auditLog?.results?.filter(r => auditFilter === 'all' || r.status === auditFilter) || []
  const byPage = {}
  for (const r of filteredResults) { if (!byPage[r.pageId]) byPage[r.pageId] = { label: r.pageLabel, path: r.pagePath, checks: [] }; byPage[r.pageId].checks.push(r) }

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <div>
          <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Audit stránek Velínu</div>
          <div style={{ fontSize: 11, color: '#666' }}>{VELIN_PAGES.length} stránek, {VELIN_PAGES.reduce((s, p) => s + p.checks.length, 0)} kontrol{auditLog && ` | Poslední: ${new Date(auditLog.timestamp).toLocaleString('cs-CZ')}`}</div>
        </div>
        <div className="flex gap-2">
          {auditLog && (<><button onClick={copyAuditLog} style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, border: '1px solid #d4e8e0', background: '#f8fcfa', cursor: 'pointer' }}>Kopírovat MD</button><button onClick={downloadAuditLog} style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, border: '1px solid #d4e8e0', background: '#f8fcfa', cursor: 'pointer' }}>Stáhnout .md</button></>)}
          <Button green onClick={runAudit} disabled={auditRunning} style={{ fontSize: 12, padding: '6px 14px' }}>{auditRunning ? `Audituji... ${auditProgress?.pageLabel || ''}` : 'Spustit audit'}</Button>
        </div>
      </div>
      {auditLog && (<div style={{ display: 'flex', gap: 8, marginBottom: 10 }}>{[{ id: 'all', label: `Vše (${auditLog.summary.total})` }, { id: 'pass', label: `OK (${auditLog.summary.pass})`, color: '#22c55e' }, { id: 'fail', label: `Chyby (${auditLog.summary.fail})`, color: '#ef4444' }, { id: 'warning', label: `Varování (${auditLog.summary.warning})`, color: '#f59e0b' }, { id: 'manual', label: `Manuální (${auditLog.summary.manual})`, color: '#3b82f6' }].map(f => (<button key={f.id} onClick={() => setAuditFilter(f.id)} style={{ padding: '4px 10px', borderRadius: 6, fontSize: 11, fontWeight: auditFilter === f.id ? 700 : 400, border: auditFilter === f.id ? `2px solid ${f.color || '#0f1a14'}` : '1px solid #e5e7eb', background: auditFilter === f.id ? (STATUS_STYLE[f.id]?.bg || '#f1f5f9') : '#fff', color: f.color || '#333', cursor: 'pointer' }}>{f.label}</button>))}</div>)}
      {auditLog && (<div ref={logRef} style={{ maxHeight: 500, overflow: 'auto' }}>{Object.entries(byPage).map(([pageId, page]) => { const hasFail = page.checks.some(c => c.status === 'fail'); const hasWarn = page.checks.some(c => c.status === 'warning'); return (<div key={pageId} style={{ marginBottom: 8, borderRadius: 10, overflow: 'hidden', border: `1px solid ${hasFail ? '#fecaca' : hasWarn ? '#fde68a' : '#d4e8e0'}` }}><div style={{ padding: '8px 12px', fontWeight: 700, fontSize: 12, background: hasFail ? '#fef2f2' : hasWarn ? '#fef3c7' : '#f0fdf4', color: hasFail ? '#dc2626' : hasWarn ? '#92400e' : '#166534', display: 'flex', alignItems: 'center', gap: 6 }}><span>{VELIN_PAGES.find(p => p.id === pageId)?.icon}</span><span style={{ flex: 1 }}>{page.label}</span><span style={{ fontSize: 10, color: '#666' }}>{page.path}</span></div>{page.checks.map((c, i) => { const st = STATUS_STYLE[c.status] || STATUS_STYLE.unknown; return (<div key={i} style={{ display: 'flex', alignItems: 'start', gap: 6, padding: '5px 12px', borderTop: '1px solid #f1f5f9', fontSize: 11 }}><span style={{ fontSize: 9, padding: '1px 4px', borderRadius: 4, fontWeight: 700, minWidth: 32, textAlign: 'center', background: st.bg, color: st.color, border: `1px solid ${st.border}` }}>{st.icon}</span><span style={{ fontWeight: 600, color: '#0f1a14', minWidth: 200 }}>{c.checkLabel}</span><span style={{ color: '#666', flex: 1, fontSize: 10 }}>{c.detail}</span></div>) })}</div>) })}</div>)}
      {!auditLog && !auditRunning && <div style={{ textAlign: 'center', padding: 30, color: '#999', fontSize: 12 }}>Klikni "Spustit audit" pro kontrolu všech stránek velínu.<br />Audit testuje dostupnost tabulek, datové toky a identifikuje chybějící funkce.</div>}
    </div>
  )
}

export function SuggestionsView({ auditLog, suggestions: initialSuggestions }) {
  const [suggestions, setSuggestions] = useState(initialSuggestions || [])

  function copyAuditLog() { const md = exportAuditMarkdown(auditLog); navigator.clipboard.writeText(md); alert('Audit log zkopírován do schránky (Markdown)') }
  function downloadAuditLog() { const md = exportAuditMarkdown(auditLog); const blob = new Blob([md], { type: 'text/markdown' }); const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = `velin-audit-${new Date().toISOString().split('T')[0]}.md`; a.click(); URL.revokeObjectURL(url) }

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <div><div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Návrhy oprav a chybějící funkce</div><div style={{ fontSize: 11, color: '#666' }}>Na základě auditu — {suggestions.length} návrhů</div></div>
        {!suggestions.length && auditLog && <button onClick={() => setSuggestions(analyzeMissingFeatures(auditLog))} style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, border: '1px solid #d4e8e0', background: '#f8fcfa', cursor: 'pointer' }}>Analyzovat</button>}
      </div>
      {suggestions.length === 0 && <div style={{ textAlign: 'center', padding: 30, color: '#999', fontSize: 12 }}>Nejprve spusť audit velínu, potom se zde zobrazí návrhy na opravy.</div>}
      {suggestions.map((s, i) => (<div key={i} style={{ padding: '8px 12px', marginBottom: 6, borderRadius: 8, background: s.severity === 'critical' ? '#fef2f2' : s.severity === 'warning' ? '#fef3c7' : '#eff6ff', border: `1px solid ${s.severity === 'critical' ? '#fecaca' : s.severity === 'warning' ? '#fde68a' : '#bfdbfe'}` }}><div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 2 }}><span style={{ fontSize: 9, padding: '1px 6px', borderRadius: 4, fontWeight: 700, background: s.severity === 'critical' ? '#dc2626' : s.severity === 'warning' ? '#f59e0b' : '#3b82f6', color: '#fff' }}>{s.severity === 'critical' ? 'CRITICAL' : s.severity === 'warning' ? 'WARNING' : 'INFO'}</span><span style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14' }}>{s.page}</span><span style={{ fontSize: 10, color: '#666' }}>{s.path}</span></div><div style={{ fontSize: 11, color: '#1a2e22', marginBottom: 2 }}>{s.issue}</div>{s.detail && <div style={{ fontSize: 10, color: '#666' }}>{s.detail}</div>}<div style={{ fontSize: 11, color: '#2563eb', marginTop: 2, fontStyle: 'italic' }}>{s.suggestion}</div></div>))}
      {auditLog && (<div style={{ marginTop: 12, padding: 10, borderRadius: 8, background: '#f1f5f9', border: '1px solid #e2e8f0' }}><div style={{ fontSize: 11, fontWeight: 700, color: '#0f1a14', marginBottom: 4 }}>Export pro Claude Code</div><div style={{ fontSize: 10, color: '#666', marginBottom: 6 }}>Zkopíruj audit log jako Markdown a vlož do Claude Code pro automatickou analýzu a opravu bugů.</div><div className="flex gap-2"><button onClick={copyAuditLog} style={{ fontSize: 11, padding: '6px 14px', borderRadius: 6, border: 'none', background: '#0f1a14', color: '#74FB71', cursor: 'pointer', fontWeight: 700 }}>Kopírovat Markdown do schránky</button><button onClick={downloadAuditLog} style={{ fontSize: 11, padding: '6px 14px', borderRadius: 6, border: '1px solid #d4e8e0', background: '#fff', cursor: 'pointer' }}>Stáhnout .md soubor</button></div></div>)}
    </div>
  )
}
