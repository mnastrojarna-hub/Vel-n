/**
 * MotoGo24 Velín — CMS / AI návštěvnost
 *
 * Per-stránka přehled AI traffic z `ai_traffic_log`. Pro každou statickou
 * stránku webu zobrazí:
 *   - počet návštěv od AI crawlerů (GPTBot, ClaudeBot, ...)
 *   - rozpad per bot (graf)
 *   - kolik z toho vedlo k rezervaci (outcome='booking_created')
 *
 * Slouží jako podklad pro rozhodnutí "kterou stránku přepsat víc AI-friendly".
 *
 * Data: server-side agregace přes RPC `get_ai_traffic_stats` (overview) a
 * `get_page_ai_traffic` (detail per stránka). NESTAHUJE raw řádky z
 * `ai_traffic_log` — Supabase PostgREST má default max-rows 1000, takže
 * po překročení 1000 záznamů v okně by se KPI tvrdě uťala. RPC vrací
 * jeden JSON s agregáty bez ohledu na velikost tabulky.
 */
import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, LineChart, Line } from 'recharts'

// Známé statické stránky webu — drží se shodně s sitemap.php
const STATIC_PAGES = [
  { path: '/',                          label: 'Domovská stránka' },
  { path: '/katalog',                   label: 'Katalog motorek' },
  { path: '/katalog/cestovni',          label: 'Katalog — cestovní' },
  { path: '/katalog/naked',             label: 'Katalog — naked' },
  { path: '/katalog/supermoto',         label: 'Katalog — supermoto' },
  { path: '/katalog/detske',            label: 'Katalog — dětské' },
  { path: '/pujcovna-motorek',          label: 'O půjčovně' },
  { path: '/jak-pujcit',                label: 'Jak si půjčit motorku' },
  { path: '/jak-pujcit/postup',         label: 'Postup půjčení' },
  { path: '/jak-pujcit/pristaveni',     label: 'Přistavení' },
  { path: '/jak-pujcit/vyzvednuti',     label: 'Vyzvednutí' },
  { path: '/jak-pujcit/vraceni-pujcovna', label: 'Vrácení v půjčovně' },
  { path: '/jak-pujcit/vraceni-jinde',  label: 'Vrácení jinde' },
  { path: '/jak-pujcit/co-v-cene',      label: 'Co je v ceně' },
  { path: '/jak-pujcit/dokumenty',      label: 'Potřebné dokumenty' },
  { path: '/jak-pujcit/faq',            label: 'FAQ' },
  { path: '/poukazy',                   label: 'Dárkové poukazy' },
  { path: '/eshop',                     label: 'E-shop' },
  { path: '/blog',                      label: 'Blog' },
  { path: '/kontakt',                   label: 'Kontakt' },
  { path: '/llms.txt',                  label: '🤖 llms.txt (AI index)' },
  { path: '/llms-full.txt',             label: '🤖 llms-full.txt (AI full)' },
  { path: '/sitemap.xml',               label: '🤖 sitemap.xml' },
  { path: '/robots.txt',                label: '🤖 robots.txt' },
]

const PERIODS = [
  { id: '7d',  label: '7 dní',  ms: 7  * 24 * 3600 * 1000 },
  { id: '30d', label: '30 dní', ms: 30 * 24 * 3600 * 1000 },
  { id: '90d', label: '90 dní', ms: 90 * 24 * 3600 * 1000 },
  { id: '1y',  label: '1 rok',  ms: 365 * 24 * 3600 * 1000 },
]

const BOT_COLORS = {
  'GPTBot': '#10a37f', 'ChatGPT-User': '#10a37f', 'OAI-SearchBot': '#10a37f',
  'ClaudeBot': '#d4a017', 'Claude-User': '#d4a017', 'Claude-SearchBot': '#d4a017', 'anthropic-ai': '#d4a017',
  'PerplexityBot': '#20a3a8', 'Perplexity-User': '#20a3a8',
  'Google-Extended': '#4285f4', 'GoogleOther': '#4285f4',
  'Applebot-Extended': '#000000',
  'Meta-ExternalAgent': '#1877f2', 'Meta-ExternalFetcher': '#1877f2', 'FacebookBot': '#1877f2',
  'Bytespider': '#ff6b6b', 'DuckAssistBot': '#de5833',
}

// RPC vrací jsonb — pole vnitřních agregátů (by_bot, by_source, top_paths,
// daily_timeline, ...) může přijít buď jako object map {key: count} nebo
// jako array [{key_field, count}]. Bez SQL definice neumíme určit, normalizuj.
function toMap(v, keyFields = ['name', 'key', 'bot', 'bot_name', 'source', 'path', 'partner_id', 'date']) {
  if (!v) return {}
  if (Array.isArray(v)) {
    const out = {}
    for (const r of v) {
      if (r == null) continue
      const k = keyFields.map(f => r[f]).find(x => x != null)
      const c = r.count ?? r.total ?? r.requests ?? r.value ?? 0
      if (k != null) out[k] = (out[k] || 0) + Number(c)
    }
    return out
  }
  if (typeof v === 'object') return v
  return {}
}

function toArray(v, keyFields = ['path', 'name', 'partner_id', 'date']) {
  if (!v) return []
  if (Array.isArray(v)) return v
  if (typeof v === 'object') {
    return Object.entries(v).map(([k, val]) => {
      // Pokud value je číslo → jednoduchá mapa {key: count}
      if (typeof val === 'number') return { [keyFields[0]]: k, count: val }
      // Jinak je to {date: 'x', count: N} nebo podobně — vrať jak je
      return { [keyFields[0]]: k, ...val }
    })
  }
  return []
}

export default function AiTrafficTab() {
  const [period, setPeriod] = useState('30d')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [stats, setStats] = useState(null)
  const [selectedPath, setSelectedPath] = useState(null)
  const [pageDetail, setPageDetail] = useState(null)
  const [pageDetailLoading, setPageDetailLoading] = useState(false)
  const [trafficMissing, setTrafficMissing] = useState(false)

  useEffect(() => { loadData() }, [period])

  async function loadData() {
    setLoading(true); setError(null); setTrafficMissing(false)
    setSelectedPath(null); setPageDetail(null)
    try {
      const periodObj = PERIODS.find(p => p.id === period)
      const from = new Date(Date.now() - periodObj.ms).toISOString()
      const to = new Date().toISOString()

      const statsRes = await supabase.rpc('get_ai_traffic_stats', { p_from: from, p_to: to })

      // RPC nemusí být v DB → tabulky/funkce ještě nejsou nasazené.
      // PGRST202 = function not found, 42883 = no such function.
      if (statsRes.error) {
        const code = statsRes.error.code
        const msg = statsRes.error.message || ''
        if (code === 'PGRST202' || code === '42883' || msg.includes('get_ai_traffic_stats') || msg.includes('ai_traffic_log')) {
          setTrafficMissing(true)
          setStats(null)
        } else {
          throw statsRes.error
        }
      } else {
        setStats(statsRes.data || null)
      }
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function loadPageDetail(path) {
    setPageDetailLoading(true); setPageDetail(null)
    try {
      const periodObj = PERIODS.find(p => p.id === period)
      const from = new Date(Date.now() - periodObj.ms).toISOString()
      const to = new Date().toISOString()
      const { data, error: e } = await supabase.rpc('get_page_ai_traffic', { p_path: path, p_from: from, p_to: to })
      if (e) throw e
      setPageDetail(data || null)
    } catch (e) {
      console.warn('get_page_ai_traffic failed:', e.message)
      setPageDetail({ total: 0, by_bot: {}, daily: [], led_to_bookings: 0 })
    } finally {
      setPageDetailLoading(false)
    }
  }

  function handleSelectPath(path) {
    if (path === selectedPath) {
      setSelectedPath(null); setPageDetail(null)
      return
    }
    setSelectedPath(path)
    loadPageDetail(path)
  }

  // Per-stránka agregace z stats.top_paths (RPC vrací top N stránek).
  // Statické stránky bez výskytu v top_paths zobrazujeme s nulou (current UX).
  const pageRows = useMemo(() => {
    const pathStats = new Map()
    if (stats) {
      const topPaths = toArray(stats.top_paths, ['path'])
      for (const row of topPaths) {
        const p = row.path
        if (!p) continue
        pathStats.set(p, {
          total: Number(row.count ?? row.total ?? 0),
          by_bot: toMap(row.by_bot),
          bookings: Number(row.bookings ?? row.led_to_bookings ?? 0),
        })
      }
    }
    return STATIC_PAGES.map(p => {
      const s = pathStats.get(p.path) || { total: 0, by_bot: {}, bookings: 0 }
      return { ...p, ...s }
    }).sort((a, b) => b.total - a.total)
  }, [stats])

  const totalAi = stats ? Number(stats.total_requests ?? stats.total ?? 0) : 0
  const byBot = useMemo(() => stats ? toMap(stats.by_bot) : {}, [stats])
  const uniqueBots = Object.keys(byBot).length
  const totalBookings = stats ? Number(stats.bookings_from_ai ?? stats.bookings ?? 0) : 0
  // Konverze = kolik z AI requestů skončilo rezervací (orientační — AI agent/widget vs. holé crawly).
  const convRate = totalAi > 0 ? ((totalBookings / totalAi) * 100) : 0

  const detailDaily = useMemo(() => {
    if (!pageDetail) return []
    const periodObj = PERIODS.find(p => p.id === period)
    const days = Math.ceil(periodObj.ms / (24 * 3600 * 1000))
    const buckets = new Map()
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(Date.now() - i * 24 * 3600 * 1000).toISOString().slice(0, 10)
      buckets.set(d, 0)
    }
    const dailyArr = toArray(pageDetail.daily, ['date'])
    for (const row of dailyArr) {
      const d = (row.date || '').slice(0, 10)
      if (buckets.has(d)) buckets.set(d, Number(row.count ?? row.total ?? 0))
    }
    return Array.from(buckets.entries()).map(([date, count]) => ({ date: date.slice(5), count }))
  }, [pageDetail, period])

  const detailByBot = useMemo(() => pageDetail ? toMap(pageDetail.by_bot) : {}, [pageDetail])

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>Chyba načítání: {error}</div>

  return (
    <div>
      {/* Hlavička + period selector */}
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <div>
          <h2 className="text-xl font-extrabold" style={{ color: '#1a2e22' }}>AI návštěvnost</h2>
          <p className="text-xs" style={{ color: '#888' }}>
            Návštěvy <strong>AI crawlerů a botů</strong> (GPTBot, ClaudeBot, PerplexityBot…) — odděleně od lidské
            návštěvnosti (ta je v <strong>Analýza → Návštěvnost</strong>). Které stránky AI čtou a kolik vede k rezervaci.
          </p>
        </div>
        <div className="flex gap-2">
          {PERIODS.map(p => (
            <button key={p.id} onClick={() => setPeriod(p.id)}
              className="rounded-btn text-xs font-bold cursor-pointer"
              style={{
                padding: '6px 14px',
                background: period === p.id ? '#74FB71' : '#f1faf7',
                color: '#1a2e22', border: 'none',
              }}>
              {p.label}
            </button>
          ))}
        </div>
      </div>

      {/* KPI tiles — výhradně AI provoz (registrace zákazníků jsou v Analýza → Zákazníci) */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-5">
        <KpiTile label="AI requestů" value={totalAi.toLocaleString('cs-CZ')} hint={`${PERIODS.find(p => p.id === period).label} zpětně`} />
        <KpiTile label="Unikátních botů" value={uniqueBots} hint="GPTBot, ClaudeBot, ..." />
        <KpiTile label="Rezervací z AI" value={totalBookings} hint="outcome='booking_created'" />
        <KpiTile label="Konverze AI" value={convRate ? convRate.toFixed(2) + ' %' : '—'} hint="rezervace / AI requesty" />
      </div>

      {trafficMissing && (
        <div style={{ marginBottom: 16, padding: 14, background: '#fef3c7', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
          <strong>RPC <code>get_ai_traffic_stats</code> není v databázi.</strong> Spusť pre-req SQL z chatu (changelog 2026-04-26) — bez něj edge funkce <code>public-api</code>, <code>mcp-server</code> a <code>ai-public-agent</code> nelogují provoz a tento dashboard nemá data.
        </div>
      )}

      {/* Tabulka per stránka */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5' }}>
        <h3 className="font-extrabold text-sm mb-3" style={{ color: '#1a2e22' }}>AI requesty per stránka</h3>
        <div style={{ overflowX: 'auto' }}>
          <table className="w-full text-xs">
            <thead>
              <tr style={{ borderBottom: '1px solid #e3e8e5', textAlign: 'left' }}>
                <th className="p-2">Stránka</th>
                <th className="p-2 text-right">AI requests</th>
                <th className="p-2 text-right">Top boti</th>
                <th className="p-2 text-right">Rezervace</th>
                <th className="p-2 text-right"></th>
              </tr>
            </thead>
            <tbody>
              {pageRows.map((p, i) => (
                <tr key={p.path} style={{
                  borderBottom: '1px solid #f1f1f1',
                  background: selectedPath === p.path ? '#f1faf7' : (i % 2 ? '#fafdfb' : '#fff'),
                  cursor: 'pointer',
                }} onClick={() => handleSelectPath(p.path)}>
                  <td className="p-2">
                    <div className="font-bold" style={{ color: '#1a2e22' }}>{p.label}</div>
                    <div style={{ color: '#888', fontSize: 10 }}>{p.path}</div>
                  </td>
                  <td className="p-2 text-right font-bold" style={{ color: p.total > 0 ? '#1a2e22' : '#bbb' }}>
                    {p.total.toLocaleString('cs-CZ')}
                  </td>
                  <td className="p-2 text-right" style={{ fontSize: 10, color: '#666' }}>
                    {Object.entries(p.by_bot).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([bot, c]) => (
                      <span key={bot} style={{
                        display: 'inline-block', padding: '2px 6px', borderRadius: 8, marginLeft: 4,
                        background: (BOT_COLORS[bot] || '#888') + '22',
                        color: BOT_COLORS[bot] || '#666',
                        fontWeight: 700,
                      }}>{bot} {c}</span>
                    )) || '—'}
                  </td>
                  <td className="p-2 text-right" style={{ color: p.bookings > 0 ? '#166534' : '#bbb', fontWeight: 700 }}>
                    {p.bookings || '—'}
                  </td>
                  <td className="p-2 text-right">
                    <a href={`https://www.motogo24.cz${p.path}`} target="_blank" rel="noopener noreferrer"
                       onClick={e => e.stopPropagation()}
                       style={{ color: '#1a8c1a', fontSize: 11, textDecoration: 'underline' }}>otevřít ↗</a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Detail drawer */}
      {selectedPath && (
        <div style={{ marginTop: 16, background: '#fff', borderRadius: 14, padding: 16, border: '2px solid #74FB71' }}>
          <div className="flex justify-between items-start mb-3">
            <div>
              <h3 className="font-extrabold text-sm" style={{ color: '#1a2e22' }}>
                Detail: {STATIC_PAGES.find(p => p.path === selectedPath)?.label}
              </h3>
              <p style={{ color: '#888', fontSize: 11 }}>{selectedPath}</p>
            </div>
            <button onClick={() => { setSelectedPath(null); setPageDetail(null) }} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#888', fontSize: 16 }}>✕</button>
          </div>

          {pageDetailLoading ? (
            <div className="flex items-center justify-center py-10"><div className="animate-spin rounded-full h-6 w-6 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <h4 className="font-bold text-xs mb-2" style={{ color: '#1a2e22' }}>AI requesty v čase</h4>
                <ResponsiveContainer width="100%" height={180}>
                  <LineChart data={detailDaily}>
                    <XAxis dataKey="date" fontSize={10} />
                    <YAxis fontSize={10} />
                    <Tooltip />
                    <Line type="monotone" dataKey="count" stroke="#74FB71" strokeWidth={2} dot={false} />
                  </LineChart>
                </ResponsiveContainer>
              </div>
              <div>
                <h4 className="font-bold text-xs mb-2" style={{ color: '#1a2e22' }}>Rozpad per bot</h4>
                <ResponsiveContainer width="100%" height={180}>
                  <BarChart data={Object.entries(detailByBot).map(([bot, count]) => ({ bot, count })).sort((a, b) => b.count - a.count).slice(0, 10)}>
                    <XAxis dataKey="bot" fontSize={9} angle={-30} textAnchor="end" height={60} />
                    <YAxis fontSize={10} />
                    <Tooltip />
                    <Bar dataKey="count" fill="#74FB71" />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}
        </div>
      )}

      {totalAi === 0 && !trafficMissing && (
        <div style={{ marginTop: 16, padding: 16, background: '#fffbeb', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
          <strong>Zatím žádná AI návštěvnost.</strong> AI crawleři objeví web v řádu dní až týdnů od nasazení.
          Zkontroluj že robots.txt obsahuje allowlist (✓), že je nasazený sitemap.xml + llms.txt (✓), a že stránky vrací status 200.
        </div>
      )}
    </div>
  )
}

function KpiTile({ label, value, hint }) {
  return (
    <div style={{ background: '#fff', borderRadius: 14, padding: 14, border: '1px solid #e3e8e5' }}>
      <div style={{ color: '#888', fontSize: 11, fontWeight: 700, textTransform: 'uppercase' }}>{label}</div>
      <div style={{ color: '#1a2e22', fontSize: 24, fontWeight: 800, margin: '4px 0' }}>{value}</div>
      <div style={{ color: '#bbb', fontSize: 10 }}>{hint}</div>
    </div>
  )
}
