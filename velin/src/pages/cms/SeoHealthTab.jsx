import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { WEB_PAGES } from './webTextsPages'
import { analyzeSeo, severityColor, severityLabel, scoreColor } from '../../lib/seoChecker'

// SEO Health Dashboard
// ====================
// Pro kazdou stranku z WEB_PAGES (definice CMS textu) nacte aktualni hodnoty z
// `cms_variables` a spusti SEO check (delka title/description, H1 vs body,
// pocet slov, pocet odstavcu, klicova slova v body).
//
// UX: tabulka stranek se score 0-100%, seznam issues, klik na 'Opravit'
// preda klic odkazu na 'Texty webu' tab + cms_highlight pro jump na pole.
//
// Cil: dat adminu jasny todo seznam co konkretne na webu opravit pred dalsim
// SEO crawlem. Pri zelene barve = stranka v poradku.

export default function SeoHealthTab({ onJumpToText }) {
  const [variables, setVariables] = useState({})
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('all') // all | critical | important | tip | ok
  const [search, setSearch] = useState('')

  useEffect(() => {
    let cancelled = false
    async function load() {
      setLoading(true)
      // Nacti vsechny cms_variables s prefix 'web.' (struktura podle stranek)
      const { data, error } = await supabase
        .from('cms_variables')
        .select('key, value')
      if (cancelled) return
      if (error) {
        console.error('SEO Health: cms_variables load error', error)
        setLoading(false)
        return
      }
      const map = {}
      ;(data || []).forEach(row => {
        if (row.key && typeof row.value === 'string') map[row.key] = row.value
      })
      setVariables(map)
      setLoading(false)
    }
    load()
    return () => { cancelled = true }
  }, [])

  // Pro kazdou stranku spocti SEO score
  const reports = useMemo(() => {
    return WEB_PAGES.map(page => {
      const result = analyzeSeo(page, variables)
      return { page, ...result }
    }).sort((a, b) => a.score - b.score) // nejhorsi nahore
  }, [variables])

  // Aggregate
  const totals = useMemo(() => {
    let critical = 0, important = 0, tip = 0
    reports.forEach(r => {
      r.issues.forEach(i => {
        if (i.severity === 'critical') critical++
        else if (i.severity === 'important') important++
        else tip++
      })
    })
    const avgScore = reports.length
      ? Math.round(reports.reduce((sum, r) => sum + r.score, 0) / reports.length)
      : 0
    return { critical, important, tip, avgScore, count: reports.length }
  }, [reports])

  // Filter
  const filtered = reports.filter(r => {
    if (search && !r.page.label.toLowerCase().includes(search.toLowerCase())) return false
    if (filter === 'all') return true
    if (filter === 'ok') return r.issues.length === 0
    return r.issues.some(i => i.severity === filter)
  })

  if (loading) {
    return <div style={{ padding: 20, textAlign: 'center', color: '#6b7a72' }}>Načítám SEO data…</div>
  }

  return (
    <div>
      {/* Header s celkovymi statistikami */}
      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 16
      }}>
        <StatCard label="Průměrné SEO score" value={`${totals.avgScore}%`}
          color={scoreColor(totals.avgScore)} />
        <StatCard label="Kritických" value={totals.critical} color="#dc2626" />
        <StatCard label="Důležitých" value={totals.important} color="#f59e0b" />
        <StatCard label="Tipů" value={totals.tip} color="#16a34a" />
      </div>

      {/* Filtrovaci panel */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap' }}>
        {[
          { id: 'all', label: 'Vše' },
          { id: 'critical', label: 'Kritické', color: '#dc2626' },
          { id: 'important', label: 'Důležité', color: '#f59e0b' },
          { id: 'tip', label: 'Tipy', color: '#16a34a' },
          { id: 'ok', label: 'V pořádku', color: '#16a34a' },
        ].map(f => (
          <button key={f.id}
            onClick={() => setFilter(f.id)}
            className="rounded-btn cursor-pointer"
            style={{
              padding: '6px 14px', fontSize: 13, fontWeight: 700, textTransform: 'uppercase',
              background: filter === f.id ? (f.color || '#74FB71') : '#f1faf7',
              color: filter === f.id ? '#fff' : '#1a2e22',
              border: 'none',
            }}
          >{f.label}</button>
        ))}
        <input type="text" placeholder="Filtrovat stránky…"
          value={search} onChange={e => setSearch(e.target.value)}
          style={{ flex: 1, minWidth: 200, padding: '6px 12px', borderRadius: 8, border: '1px solid #d4e8e0' }}
        />
      </div>

      {/* Pomoc */}
      <div style={{
        background: '#f1faf7', padding: 12, borderRadius: 8, fontSize: 13, marginBottom: 16,
        borderLeft: '4px solid #74FB71'
      }}>
        <strong>Jak to funguje:</strong> Každá stránka má SEO score 0-100% (vyšší je lepší).
        Klikněte na <strong>Opravit</strong> u konkrétního problému — přepne na záložku
        „Texty webu" a otevře pole co potřebuje doplnit.
        Po opravě se score automaticky aktualizuje.
      </div>

      {/* Tabulka stranek */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {filtered.length === 0 && (
          <div style={{ padding: 20, textAlign: 'center', color: '#6b7a72' }}>
            Žádné stránky nesplňují filtr.
          </div>
        )}
        {filtered.map(r => (
          <PageCard key={r.page.id} report={r} onJumpToText={onJumpToText} />
        ))}
      </div>
    </div>
  )
}

function StatCard({ label, value, color }) {
  return (
    <div style={{
      background: '#fff', padding: 16, borderRadius: 12, border: '1px solid #e2ece7',
      borderTop: `4px solid ${color}`,
      textAlign: 'center'
    }}>
      <div style={{ fontSize: 28, fontWeight: 800, color, marginBottom: 4 }}>{value}</div>
      <div style={{ fontSize: 12, color: '#6b7a72', textTransform: 'uppercase', letterSpacing: 0.5 }}>{label}</div>
    </div>
  )
}

function PageCard({ report, onJumpToText }) {
  const { page, score, issues, stats } = report
  const [expanded, setExpanded] = useState(issues.length > 0 && score < 80)
  const color = scoreColor(score)
  const isOk = issues.length === 0

  return (
    <div style={{
      background: '#fff', borderRadius: 12, border: '1px solid #e2ece7',
      borderLeft: `5px solid ${color}`,
      overflow: 'hidden'
    }}>
      <div
        onClick={() => setExpanded(!expanded)}
        style={{
          padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer',
          background: expanded ? '#f1faf7' : '#fff'
        }}>
        <div style={{
          minWidth: 50, fontWeight: 800, fontSize: 18, color, textAlign: 'center'
        }}>{score}%</div>
        <div style={{ flex: 1 }}>
          <div style={{ fontWeight: 700, fontSize: 14 }}>
            {page.icon} {page.label}
            <span style={{ marginLeft: 8, fontSize: 12, color: '#6b7a72', fontWeight: 400 }}>
              {page.url}
            </span>
          </div>
          <div style={{ fontSize: 12, color: '#6b7a72', marginTop: 2 }}>
            {isOk ? '✓ Bez problémů' : `${issues.length} problém${issues.length === 1 ? '' : (issues.length < 5 ? 'y' : 'ů')}`}
            {' · '}{stats.bodyLen} slov
            {' · '}{stats.paragraphCount} odstavců
          </div>
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          {issues.filter(i => i.severity === 'critical').length > 0 && (
            <span style={{
              background: '#dc2626', color: '#fff', fontSize: 11, padding: '2px 8px',
              borderRadius: 10, fontWeight: 700
            }}>{issues.filter(i => i.severity === 'critical').length} kritické</span>
          )}
          {issues.filter(i => i.severity === 'important').length > 0 && (
            <span style={{
              background: '#f59e0b', color: '#fff', fontSize: 11, padding: '2px 8px',
              borderRadius: 10, fontWeight: 700
            }}>{issues.filter(i => i.severity === 'important').length} důležité</span>
          )}
          {issues.filter(i => i.severity === 'tip').length > 0 && (
            <span style={{
              background: '#16a34a', color: '#fff', fontSize: 11, padding: '2px 8px',
              borderRadius: 10, fontWeight: 700
            }}>{issues.filter(i => i.severity === 'tip').length} tipů</span>
          )}
          <span style={{ fontSize: 18, color: '#6b7a72' }}>{expanded ? '▾' : '▸'}</span>
        </div>
      </div>

      {expanded && issues.length > 0 && (
        <div style={{ padding: '0 16px 12px 16px', borderTop: '1px solid #e2ece7' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 8 }}>
            {issues.map((iss, idx) => (
              <div key={idx} style={{
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '8px 12px', background: '#fafafa', borderRadius: 8, fontSize: 13,
                borderLeft: `3px solid ${severityColor(iss.severity)}`
              }}>
                <span style={{
                  fontSize: 11, fontWeight: 700, color: severityColor(iss.severity),
                  textTransform: 'uppercase', minWidth: 70
                }}>{severityLabel(iss.severity)}</span>
                <span style={{ flex: 1 }}>{iss.message}</span>
                <button
                  onClick={(e) => { e.stopPropagation(); onJumpToText && onJumpToText(page.id) }}
                  className="rounded-btn cursor-pointer"
                  style={{
                    background: '#74FB71', color: '#1a2e22', border: 'none',
                    padding: '4px 10px', fontSize: 11, fontWeight: 700, textTransform: 'uppercase'
                  }}
                >Opravit →</button>
              </div>
            ))}
          </div>
          {/* Footer s linky na page */}
          <div style={{ marginTop: 10, display: 'flex', gap: 8, fontSize: 12 }}>
            <a href={`https://www.motogo24.cz${page.url}`} target="_blank" rel="noopener noreferrer"
              style={{ color: '#0d6e0d', textDecoration: 'underline' }}>
              ↗ Otevřít stránku na webu
            </a>
            <button
              onClick={() => onJumpToText && onJumpToText(page.id)}
              className="cursor-pointer"
              style={{
                background: 'transparent', border: 'none', color: '#0d6e0d',
                textDecoration: 'underline', cursor: 'pointer', fontSize: 12, padding: 0
              }}
            >→ Editovat texty této stránky</button>
          </div>
        </div>
      )}

      {expanded && issues.length === 0 && (
        <div style={{ padding: '12px 16px', borderTop: '1px solid #e2ece7', fontSize: 13, color: '#16a34a' }}>
          ✓ Stránka splňuje všechny SEO kontroly. {stats.bodyLen} slov, {stats.paragraphCount} odstavců,
          title {stats.titleLen} znaků, meta {stats.descLen} znaků.
        </div>
      )}
    </div>
  )
}
