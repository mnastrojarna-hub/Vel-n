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

export default function AiTrafficTab() {
  const [period, setPeriod] = useState('30d')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [rows, setRows] = useState([])
  const [selectedPath, setSelectedPath] = useState(null)
  const [trafficMissing, setTrafficMissing] = useState(false)
  const [webUsersCount, setWebUsersCount] = useState(0)
  const [appUsersCount, setAppUsersCount] = useState(0)

  useEffect(() => { loadData() }, [period])

  async function loadData() {
    setLoading(true); setError(null); setTrafficMissing(false)
    try {
      const periodObj = PERIODS.find(p => p.id === period)
      const from = new Date(Date.now() - periodObj.ms).toISOString()

      // Načti AI traffic + počty uživatelů paralelně.
      const [trafficRes, webRes, appRes] = await Promise.all([
        supabase
          .from('ai_traffic_log')
          .select('path, bot_name, source, outcome, ts')
          .gte('ts', from)
          .order('ts', { ascending: false })
          .limit(20000),
        supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('registration_source', 'web'),
        supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('registration_source', 'app'),
      ])

      // Tabulka ai_traffic_log nemusí ještě v DB existovat — degradujeme na info hlášku
      // a necháme zbytek dashboardu (uživatelé webu/app) fungovat.
      if (trafficRes.error) {
        const msg = trafficRes.error.message || ''
        if (msg.includes('ai_traffic_log') || trafficRes.error.code === 'PGRST205' || trafficRes.error.code === '42P01') {
          setTrafficMissing(true)
          setRows([])
        } else {
          throw trafficRes.error
        }
      } else {
        setRows(trafficRes.data || [])
      }

      setWebUsersCount(webRes.count || 0)
      setAppUsersCount(appRes.count || 0)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const aggregated = useMemo(() => {
    const m = new Map()
    for (const r of rows) {
      if (!r.path) continue
      let p = m.get(r.path)
      if (!p) { p = { path: r.path, total: 0, by_bot: {}, by_source: {}, bookings: 0 }; m.set(r.path, p) }
      p.total++
      if (r.bot_name) p.by_bot[r.bot_name] = (p.by_bot[r.bot_name] || 0) + 1
      if (r.source) p.by_source[r.source] = (p.by_source[r.source] || 0) + 1
      if (r.outcome === 'booking_created') p.bookings++
    }
    return m
  }, [rows])

  const totalAi = rows.length
  const uniqueBots = new Set(rows.map(r => r.bot_name).filter(Boolean)).size
  const totalBookings = rows.filter(r => r.outcome === 'booking_created').length

  const pageRows = STATIC_PAGES.map(p => {
    const agg = aggregated.get(p.path) || { total: 0, by_bot: {}, bookings: 0 }
    return { ...p, ...agg }
  }).sort((a, b) => b.total - a.total)

  // Detail drawer pro vybranou stránku
  const detail = selectedPath ? aggregated.get(selectedPath) : null
  const detailDaily = useMemo(() => {
    if (!selectedPath) return []
    const periodObj = PERIODS.find(p => p.id === period)
    const days = Math.ceil(periodObj.ms / (24 * 3600 * 1000))
    const buckets = new Map()
    for (let i = 0; i < days; i++) {
      const d = new Date(Date.now() - i * 24 * 3600 * 1000).toISOString().slice(0, 10)
      buckets.set(d, 0)
    }
    for (const r of rows) {
      if (r.path !== selectedPath) continue
      const d = r.ts.slice(0, 10)
      if (buckets.has(d)) buckets.set(d, buckets.get(d) + 1)
    }
    return Array.from(buckets.entries()).map(([date, count]) => ({ date: date.slice(5), count })).reverse()
  }, [rows, selectedPath, period])

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>Chyba načítání: {error}</div>

  return (
    <div>
      {/* Hlavička + period selector */}
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <div>
          <h2 className="text-xl font-extrabold" style={{ color: '#1a2e22' }}>AI návštěvnost</h2>
          <p className="text-xs" style={{ color: '#888' }}>
            Které stránky čtou AI crawlery (GPTBot, ClaudeBot, PerplexityBot, ...) a kolik z nich vede k rezervaci.
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

      {/* KPI tiles */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 mb-5">
        <KpiTile label="AI requests" value={totalAi.toLocaleString('cs-CZ')} hint={`${PERIODS.find(p => p.id === period).label} zpětně`} />
        <KpiTile label="Celková návštěvnost webu" value={(webUsersCount + appUsersCount).toLocaleString('cs-CZ')} hint="registrovaní zákazníci celkem" />
        <KpiTile label="Uživatelé webu" value={webUsersCount.toLocaleString('cs-CZ')} hint="profiles.registration_source='web'" />
        <KpiTile label="Uživatelé app" value={appUsersCount.toLocaleString('cs-CZ')} hint="profiles.registration_source='app'" />
        <KpiTile label="Unikátních botů" value={uniqueBots} hint="GPTBot, ClaudeBot, ..." />
        <KpiTile label="Rezervací z AI" value={totalBookings} hint="outcome='booking_created'" />
      </div>

      {trafficMissing && (
        <div style={{ marginBottom: 16, padding: 14, background: '#fef3c7', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
          <strong>Tabulka <code>ai_traffic_log</code> ještě není v databázi.</strong> Spusť pre-req SQL z chatu (changelog 2026-04-26) — bez něj edge funkce <code>public-api</code>, <code>mcp-server</code> a <code>ai-public-agent</code> nelogují provoz a tento dashboard nemá data. Počty uživatelů webu/app fungují i tak.
        </div>
      )}

      {/* Tabulka per stránka */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5' }}>
        <h3 className="font-extrabold text-sm mb-3" style={{ color: '#1a2e22' }}>Návštěvnost per stránka</h3>
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
                }} onClick={() => setSelectedPath(p.path === selectedPath ? null : p.path)}>
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
                    <a href={`https://motogo24.cz${p.path}`} target="_blank" rel="noopener noreferrer"
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
      {selectedPath && detail && (
        <div style={{ marginTop: 16, background: '#fff', borderRadius: 14, padding: 16, border: '2px solid #74FB71' }}>
          <div className="flex justify-between items-start mb-3">
            <div>
              <h3 className="font-extrabold text-sm" style={{ color: '#1a2e22' }}>
                Detail: {STATIC_PAGES.find(p => p.path === selectedPath)?.label}
              </h3>
              <p style={{ color: '#888', fontSize: 11 }}>{selectedPath}</p>
            </div>
            <button onClick={() => setSelectedPath(null)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#888', fontSize: 16 }}>✕</button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <h4 className="font-bold text-xs mb-2" style={{ color: '#1a2e22' }}>Návštěvnost v čase</h4>
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
                <BarChart data={Object.entries(detail.by_bot).map(([bot, count]) => ({ bot, count })).sort((a, b) => b.count - a.count).slice(0, 10)}>
                  <XAxis dataKey="bot" fontSize={9} angle={-30} textAnchor="end" height={60} />
                  <YAxis fontSize={10} />
                  <Tooltip />
                  <Bar dataKey="count" fill="#74FB71" />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>
      )}

      {totalAi === 0 && (
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
