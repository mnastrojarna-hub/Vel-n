import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { WEB_PAGES } from './webTextsPages'
import { analyzeSeo, severityColor, severityLabel, severityIcon, scoreColor } from '../../lib/seoChecker'

const ALL_FIELDS = WEB_PAGES.flatMap(p => (p.sections || []).flatMap(s => s.fields || []))

// SEO Health Dashboard pro neprogramátorského admina
// ===================================================
// Pro kazdou stranku: vypocita SEO score 0-100% z aktualnich textu v cms_variables.
// Kazdy issue ma srozumitelnou hlasku v cestine + priklad jak text vypadat ma +
// presny klic na pole co opravit. Klik 'Opravit' otevre Texty webu tab,
// pripne na konkretni stranku a auto-scrolluje + zvyrazni cilove pole.

export default function SeoHealthTab({ onJumpToText }) {
  const [variables, setVariables] = useState({})
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [seeding, setSeeding] = useState(false)
  const [seedResult, setSeedResult] = useState(null)
  const [expandedPages, setExpandedPages] = useState({}) // pageId -> bool

  async function loadVariables() {
    const { data, error } = await supabase.from('cms_variables').select('key, value')
    if (error) { console.error('SEO Health: load error', error); return }
    const map = {}
    ;(data || []).forEach(row => {
      if (row.key && typeof row.value === 'string') map[row.key] = row.value
    })
    setVariables(map)
  }

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      setLoading(true); await loadVariables()
      if (!cancelled) setLoading(false)
    })()
    return () => { cancelled = true }
  }, [])

  async function promoteAllDefaults() {
    if (!confirm('Uloží všechny výchozí texty z Velínu do databáze. Existující ručně upravené texty zůstanou beze změny. Pokračovat?')) return
    setSeeding(true); setSeedResult(null)
    const missing = ALL_FIELDS.filter(f => !variables[f.key] && f.default != null && f.default !== '')
    let inserted = 0, failed = 0
    for (let i = 0; i < missing.length; i += 50) {
      const batch = missing.slice(i, i + 50).map(f => ({
        key: f.key, value: String(f.default), category: 'web'
      }))
      const { error } = await supabase.from('cms_variables').insert(batch)
      if (error) { console.error('Promote batch error', error); failed += batch.length }
      else { inserted += batch.length }
    }
    await loadVariables()
    setSeedResult({ inserted, failed, total: missing.length })
    setSeeding(false)
  }

  const reports = useMemo(() => {
    if (loading) return []
    return WEB_PAGES.map(page => {
      const result = analyzeSeo(page, variables)
      return { page, ...result }
    }).sort((a, b) => a.score - b.score)
  }, [variables, loading])

  const totals = useMemo(() => {
    let critical = 0, important = 0, tip = 0
    reports.forEach(r => r.issues.forEach(i => {
      if (i.severity === 'critical') critical++
      else if (i.severity === 'important') important++
      else tip++
    }))
    const avgScore = reports.length ? Math.round(reports.reduce((s, r) => s + r.score, 0) / reports.length) : 0
    return { critical, important, tip, avgScore, count: reports.length }
  }, [reports])

  // FIX: filter teď správně pracuje včetně OK stavu a kritičnosti
  const filtered = useMemo(() => {
    const s = search.toLowerCase().trim()
    return reports.filter(r => {
      if (s && !r.page.label.toLowerCase().includes(s)) return false
      if (filter === 'all') return true
      if (filter === 'ok') return r.issues.length === 0
      return r.issues.some(i => i.severity === filter)
    })
  }, [reports, filter, search])

  function handleFix(pageId, fieldKey, sectionId) {
    onJumpToText && onJumpToText(pageId, fieldKey, sectionId)
  }

  if (loading) return <div style={{ padding: 40, textAlign: 'center', color: '#6b7a72' }}>Načítám SEO data…</div>

  const missingDefaults = ALL_FIELDS.filter(f => !variables[f.key] && f.default != null && f.default !== '').length

  return (
    <div>
      {/* Statistiky nahore */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 16 }}>
        <StatCard label="Průměrné SEO skóre" value={`${totals.avgScore}%`} color={scoreColor(totals.avgScore)} />
        <StatCard label="K opravě hned" value={totals.critical} color="#dc2626" icon="⛔" />
        <StatCard label="Důležité" value={totals.important} color="#f59e0b" icon="⚠️" />
        <StatCard label="Doporučení" value={totals.tip} color="#16a34a" icon="💡" />
      </div>

      {/* Promote defaults banner */}
      {(missingDefaults > 0 || seedResult) && (
        <div style={{
          background: '#fffbeb', padding: 14, borderRadius: 8, marginBottom: 16,
          borderLeft: '4px solid #f59e0b', display: 'flex', alignItems: 'center', gap: 12
        }}>
          <div style={{ flex: 1 }}>
            {seedResult ? (
              <div>
                <strong style={{ color: '#16a34a' }}>✓ Uloženo!</strong> Promotnuto {seedResult.inserted} výchozích textů do databáze.
                {seedResult.failed > 0 && <span style={{ color: '#dc2626' }}> {seedResult.failed} chyb.</span>}
              </div>
            ) : (
              <div>
                <strong>📌 {missingDefaults} textů z Velínu není v databázi</strong>
                <div style={{ fontSize: 12, color: '#6b7a72', marginTop: 4 }}>
                  Tlačítko níže uloží všechny výchozí texty do DB najednou.
                  Existující ručně upravené texty se NEPŘEPÍŠOU. Po uložení svítí texty zeleně.
                </div>
              </div>
            )}
          </div>
          {!seedResult && (
            <button onClick={promoteAllDefaults} disabled={seeding} className="rounded-btn cursor-pointer"
              style={{ padding: '10px 18px', background: '#1a2e22', color: '#74FB71', border: 'none',
                fontWeight: 800, fontSize: 13, textTransform: 'uppercase', whiteSpace: 'nowrap' }}
            >{seeding ? 'Ukládám…' : `Uložit ${missingDefaults} textů`}</button>
          )}
        </div>
      )}

      {/* Filter — FIXED */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap', alignItems: 'center' }}>
        <span style={{ fontSize: 12, fontWeight: 700, color: '#6b7a72', textTransform: 'uppercase' }}>Filtr:</span>
        {[
          { id: 'all', label: 'Vše', count: reports.length },
          { id: 'critical', label: '⛔ K opravě', count: reports.filter(r => r.issues.some(i => i.severity === 'critical')).length, color: '#dc2626' },
          { id: 'important', label: '⚠️ Důležité', count: reports.filter(r => r.issues.some(i => i.severity === 'important')).length, color: '#f59e0b' },
          { id: 'tip', label: '💡 Doporučení', count: reports.filter(r => r.issues.some(i => i.severity === 'tip')).length, color: '#16a34a' },
          { id: 'ok', label: '✓ Bez problémů', count: reports.filter(r => r.issues.length === 0).length, color: '#16a34a' },
        ].map(f => (
          <button key={f.id} onClick={() => setFilter(f.id)} className="rounded-btn cursor-pointer"
            style={{
              padding: '6px 14px', fontSize: 13, fontWeight: 700,
              background: filter === f.id ? (f.color || '#1a2e22') : '#f1faf7',
              color: filter === f.id ? '#fff' : '#1a2e22',
              border: filter === f.id ? `2px solid ${f.color || '#1a2e22'}` : '2px solid transparent',
            }}
          >{f.label} <span style={{ opacity: 0.7, fontSize: 11 }}>({f.count})</span></button>
        ))}
        <input type="text" placeholder="Hledat stránku…" value={search} onChange={e => setSearch(e.target.value)}
          style={{ flex: 1, minWidth: 200, padding: '6px 12px', borderRadius: 8, border: '1px solid #d4e8e0' }}
        />
      </div>

      {/* Help banner */}
      <div style={{
        background: '#f1faf7', padding: 12, borderRadius: 8, fontSize: 13, marginBottom: 16,
        borderLeft: '4px solid #74FB71'
      }}>
        <strong>Jak to funguje:</strong> Klikněte na stránku pro detail problémů.
        U každého problému je <strong>vysvětlení česky</strong> + <strong>příklad jak text má vypadat</strong>.
        Klik na <strong>Opravit →</strong> otevře přesné pole v Texty webu kde to opravit.
      </div>

      {/* Tabulka stranek */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {filtered.length === 0 && (
          <div style={{ padding: 30, textAlign: 'center', color: '#6b7a72', background: '#fafafa', borderRadius: 12 }}>
            Žádné stránky neodpovídají filtru.
          </div>
        )}
        {filtered.map(r => (
          <PageCard
            key={r.page.id}
            report={r}
            expanded={!!expandedPages[r.page.id]}
            onToggle={() => setExpandedPages(s => ({ ...s, [r.page.id]: !s[r.page.id] }))}
            onFix={handleFix}
          />
        ))}
      </div>
    </div>
  )
}

function StatCard({ label, value, color, icon }) {
  return (
    <div style={{
      background: '#fff', padding: 16, borderRadius: 12, border: '1px solid #e2ece7',
      borderTop: `4px solid ${color}`, textAlign: 'center'
    }}>
      <div style={{ fontSize: 28, fontWeight: 800, color, marginBottom: 4 }}>
        {icon && <span style={{ marginRight: 6 }}>{icon}</span>}{value}
      </div>
      <div style={{ fontSize: 11, color: '#6b7a72', textTransform: 'uppercase', letterSpacing: 0.5 }}>{label}</div>
    </div>
  )
}

function PageCard({ report, expanded, onToggle, onFix }) {
  const { page, score, issues, stats } = report
  const color = scoreColor(score)
  const isOk = issues.length === 0
  const counts = {
    critical: issues.filter(i => i.severity === 'critical').length,
    important: issues.filter(i => i.severity === 'important').length,
    tip: issues.filter(i => i.severity === 'tip').length,
  }

  return (
    <div style={{
      background: '#fff', borderRadius: 12, border: '1px solid #e2ece7',
      borderLeft: `5px solid ${color}`, overflow: 'hidden'
    }}>
      <div onClick={onToggle} style={{
        padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer',
        background: expanded ? '#f1faf7' : '#fff'
      }}>
        <div style={{ minWidth: 60, fontWeight: 800, fontSize: 22, color, textAlign: 'center' }}>{score}%</div>
        <div style={{ flex: 1 }}>
          <div style={{ fontWeight: 700, fontSize: 15 }}>
            {page.icon} {page.label}
            <span style={{ marginLeft: 8, fontSize: 12, color: '#6b7a72', fontWeight: 400 }}>{page.url}</span>
          </div>
          <div style={{ fontSize: 12, color: '#6b7a72', marginTop: 3 }}>
            {isOk ? '✓ Vše v pořádku' : `${issues.length} ${issues.length === 1 ? 'problém' : (issues.length < 5 ? 'problémy' : 'problémů')} — klikni pro detaily`}
            {' · '}{stats.bodyLen} slov v textu
          </div>
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          {counts.critical > 0 && <Badge color="#dc2626" icon="⛔" count={counts.critical} />}
          {counts.important > 0 && <Badge color="#f59e0b" icon="⚠️" count={counts.important} />}
          {counts.tip > 0 && <Badge color="#16a34a" icon="💡" count={counts.tip} />}
          <span style={{ fontSize: 20, color: '#6b7a72', marginLeft: 4 }}>{expanded ? '▾' : '▸'}</span>
        </div>
      </div>

      {expanded && issues.length > 0 && (
        <div style={{ padding: '0 16px 14px 16px', borderTop: '1px solid #e2ece7' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 12 }}>
            {issues.map((iss, idx) => (
              <IssueCard key={idx} issue={iss} onFix={() => onFix(page.id, iss.fieldKey, iss.sectionId)} />
            ))}
          </div>
          <div style={{ marginTop: 14, display: 'flex', gap: 12, fontSize: 12, flexWrap: 'wrap', alignItems: 'center' }}>
            <a href={`https://www.motogo24.cz${page.url}`} target="_blank" rel="noopener noreferrer"
              style={{ color: '#0d6e0d', textDecoration: 'underline', fontWeight: 600 }}>
              ↗ Otevřít stránku na webu
            </a>
            <button onClick={() => onFix(page.id, null, null)} className="cursor-pointer"
              style={{ background: 'transparent', border: 'none', color: '#0d6e0d',
                textDecoration: 'underline', cursor: 'pointer', fontSize: 12, padding: 0, fontWeight: 600 }}>
              → Otevřít všechny texty této stránky
            </button>
          </div>
        </div>
      )}

      {expanded && issues.length === 0 && (
        <div style={{ padding: '12px 16px', borderTop: '1px solid #e2ece7', fontSize: 13, color: '#16a34a' }}>
          ✓ Stránka splňuje všechny SEO kontroly. {stats.bodyLen} slov · {stats.paragraphCount} odstavců ·
          titulek {stats.titleLen} znaků · popisek {stats.descLen} znaků.
        </div>
      )}
    </div>
  )
}

function Badge({ color, icon, count }) {
  return <span style={{
    background: color, color: '#fff', fontSize: 11, padding: '3px 9px',
    borderRadius: 12, fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: 4
  }}>{icon} {count}</span>
}

function IssueCard({ issue, onFix }) {
  const color = severityColor(issue.severity)
  return (
    <div style={{
      background: '#fafafa', borderRadius: 8, padding: 12, borderLeft: `4px solid ${color}`,
      fontSize: 13
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
        <div style={{ fontSize: 18 }}>{severityIcon(issue.severity)}</div>
        <div style={{ flex: 1 }}>
          <div style={{ fontWeight: 700, color, marginBottom: 4, fontSize: 14 }}>{issue.title}</div>
          <div style={{ color: '#1a2e22', lineHeight: 1.5 }}>{issue.message}</div>
          {issue.example && (
            <div style={{
              marginTop: 8, padding: '8px 12px', background: '#f0fdf4', borderRadius: 6,
              borderLeft: '3px solid #16a34a', fontSize: 12, color: '#14532d'
            }}>
              <strong>👍 Příklad / doporučení:</strong>{' '}
              <span style={{ fontStyle: 'italic' }}>{issue.example}</span>
            </div>
          )}
        </div>
        <button onClick={onFix} className="rounded-btn cursor-pointer"
          style={{
            background: '#74FB71', color: '#1a2e22', border: 'none', padding: '6px 14px',
            fontSize: 12, fontWeight: 800, textTransform: 'uppercase', whiteSpace: 'nowrap'
          }}
        >Opravit →</button>
      </div>
    </div>
  )
}
