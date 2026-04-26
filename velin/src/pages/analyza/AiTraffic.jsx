/**
 * MotoGo24 Velín — Analýza / AI traffic
 *
 * Holistický přehled AI provozu napříč všemi kanály:
 *   - crawler (GPTBot, ClaudeBot, ...)
 *   - rest_api (partneři přes X-Api-Key nebo anon)
 *   - mcp (Model Context Protocol klienti)
 *   - widget (chat bubble na motogo24.cz)
 *
 * Plus ručně zadávané citation tracking (kde nás zmínil ChatGPT/Claude).
 */
import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, LineChart, Line, PieChart, Pie, Cell, Legend } from 'recharts'
import { CreateApiKeyModal, RevokeApiKeyConfirm } from './ApiKeyModals'

const PERIODS = [
  { id: '7d',  label: '7 dní',  ms: 7  * 24 * 3600 * 1000 },
  { id: '30d', label: '30 dní', ms: 30 * 24 * 3600 * 1000 },
  { id: '90d', label: '90 dní', ms: 90 * 24 * 3600 * 1000 },
]

const SOURCE_COLORS = {
  crawler: '#74FB71', rest_api: '#4285f4', mcp: '#d4a017', widget: '#f97316', unknown: '#888',
}
const SOURCE_LABELS = {
  crawler: 'Crawler', rest_api: 'REST API', mcp: 'MCP', widget: 'Web widget', unknown: 'Neznámý',
}

const PLATFORMS = [
  { id: 'chatgpt',    label: 'ChatGPT',    color: '#10a37f' },
  { id: 'claude',     label: 'Claude',     color: '#d4a017' },
  { id: 'perplexity', label: 'Perplexity', color: '#20a3a8' },
  { id: 'gemini',     label: 'Gemini',     color: '#4285f4' },
  { id: 'copilot',    label: 'Copilot',    color: '#0078d4' },
  { id: 'grok',       label: 'Grok',       color: '#000000' },
  { id: 'duckassist', label: 'DuckAssist', color: '#de5833' },
  { id: 'other',      label: 'Ostatní',    color: '#888' },
]

export default function AiTraffic() {
  const [period, setPeriod] = useState('30d')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [rows, setRows] = useState([])
  const [partners, setPartners] = useState([])
  const [citations, setCitations] = useState([])
  const [showAddCitation, setShowAddCitation] = useState(false)
  const [showCreateKey, setShowCreateKey] = useState(false)
  const [revokeKey, setRevokeKey] = useState(null)

  useEffect(() => { loadData() }, [period])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const periodObj = PERIODS.find(p => p.id === period)
      const from = new Date(Date.now() - periodObj.ms).toISOString()
      const [tr, pa, ci] = await Promise.all([
        supabase.from('ai_traffic_log').select('source, bot_name, endpoint, outcome, partner_id, ts').gte('ts', from).order('ts', { ascending: false }).limit(20000),
        supabase.from('api_keys').select('id, partner_name, partner_email, key_prefix, is_active, request_count, last_used_at, rate_limit_rpm, scopes, created_at, revoked_at'),
        supabase.from('ai_citations').select('*').gte('observed_at', from).order('observed_at', { ascending: false }),
      ])
      // ai_traffic_log / api_keys / ai_citations nemusí v DB ještě existovat
      // (pre-req SQL z 2026-04-26 čeká na admin run). Toleruj missing tabulky.
      const isMissingTable = (e) => e && (e.code === 'PGRST205' || e.code === '42P01' || (e.message || '').includes('schema cache'))
      if (tr.error && !isMissingTable(tr.error)) throw tr.error
      setRows(tr.error ? [] : (tr.data || []))
      setPartners(pa.error ? [] : (pa.data || []))
      setCitations(ci.error ? [] : (ci.data || []))
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  // ---- Aggregations ----
  const stats = useMemo(() => {
    const bySource = {}, byBot = {}, byPartner = {}, byEndpoint = {}, daily = {}
    let bookings = 0, errors = 0, rateLimited = 0
    for (const r of rows) {
      bySource[r.source] = (bySource[r.source] || 0) + 1
      if (r.bot_name) byBot[r.bot_name] = (byBot[r.bot_name] || 0) + 1
      if (r.partner_id) byPartner[r.partner_id] = (byPartner[r.partner_id] || 0) + 1
      if (r.endpoint) byEndpoint[r.endpoint] = (byEndpoint[r.endpoint] || 0) + 1
      const d = r.ts.slice(0, 10)
      daily[d] = (daily[d] || 0) + 1
      if (r.outcome === 'booking_created') bookings++
      if (r.outcome === 'error') errors++
      if (r.outcome === 'rate_limited') rateLimited++
    }
    return { bySource, byBot, byPartner, byEndpoint, daily, bookings, errors, rateLimited, total: rows.length }
  }, [rows])

  const periodObj = PERIODS.find(p => p.id === period)
  const dailyData = useMemo(() => {
    const days = Math.ceil(periodObj.ms / (24 * 3600 * 1000))
    const out = []
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(Date.now() - i * 24 * 3600 * 1000).toISOString().slice(0, 10)
      out.push({ date: d.slice(5), count: stats.daily[d] || 0 })
    }
    return out
  }, [stats.daily, period])

  const sourcePieData = Object.entries(stats.bySource).map(([source, count]) => ({ name: SOURCE_LABELS[source] || source, value: count, color: SOURCE_COLORS[source] || '#888' }))
  const topBotsData = Object.entries(stats.byBot).sort((a, b) => b[1] - a[1]).slice(0, 12).map(([bot, count]) => ({ bot, count }))
  const topEndpoints = Object.entries(stats.byEndpoint).sort((a, b) => b[1] - a[1]).slice(0, 10)

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>Chyba načítání: {error}</div>

  return (
    <div>
      {/* Period selector */}
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <div>
          <h2 className="text-xl font-extrabold" style={{ color: '#1a2e22' }}>AI traffic</h2>
          <p className="text-xs" style={{ color: '#888' }}>
            Holistický přehled AI provozu — crawleři, REST API partneři, MCP klienti, web widget, manuální citation tracking.
          </p>
        </div>
        <div className="flex gap-2">
          {PERIODS.map(p => (
            <button key={p.id} onClick={() => setPeriod(p.id)}
              className="rounded-btn text-xs font-bold cursor-pointer"
              style={{ padding: '6px 14px', background: period === p.id ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none' }}>
              {p.label}
            </button>
          ))}
        </div>
      </div>

      {/* KPI tiles */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-5">
        <KpiTile label="Total AI requests" value={stats.total.toLocaleString('cs-CZ')} hint={periodObj.label} color="#74FB71" />
        <KpiTile label="Crawler hits" value={(stats.bySource.crawler || 0).toLocaleString('cs-CZ')} hint="GPTBot, ClaudeBot..." color="#74FB71" />
        <KpiTile label="REST API + MCP" value={((stats.bySource.rest_api || 0) + (stats.bySource.mcp || 0)).toLocaleString('cs-CZ')} hint="Partneři + agenti" color="#4285f4" />
        <KpiTile label="Widget chats" value={(stats.bySource.widget || 0).toLocaleString('cs-CZ')} hint="Floating bubble" color="#f97316" />
        <KpiTile label="Rezervací z AI" value={stats.bookings} hint="outcome=booking_created" color="#166534" />
      </div>

      {/* Daily timeline */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5', marginBottom: 20 }}>
        <h3 className="font-extrabold text-sm mb-3" style={{ color: '#1a2e22' }}>Návštěvnost v čase</h3>
        <ResponsiveContainer width="100%" height={220}>
          <LineChart data={dailyData}>
            <XAxis dataKey="date" fontSize={10} />
            <YAxis fontSize={10} />
            <Tooltip />
            <Line type="monotone" dataKey="count" stroke="#74FB71" strokeWidth={2} dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>

      {/* Source breakdown + Top bots */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-5">
        <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5' }}>
          <h3 className="font-extrabold text-sm mb-3" style={{ color: '#1a2e22' }}>Rozpad podle zdroje</h3>
          {sourcePieData.length > 0 ? (
            <ResponsiveContainer width="100%" height={220}>
              <PieChart>
                <Pie data={sourcePieData} dataKey="value" nameKey="name" outerRadius={80} label>
                  {sourcePieData.map((d, i) => <Cell key={i} fill={d.color} />)}
                </Pie>
                <Legend />
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          ) : <NoData />}
        </div>
        <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5' }}>
          <h3 className="font-extrabold text-sm mb-3" style={{ color: '#1a2e22' }}>Top AI boti / klienti</h3>
          {topBotsData.length > 0 ? (
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={topBotsData}>
                <XAxis dataKey="bot" fontSize={9} angle={-30} textAnchor="end" height={70} />
                <YAxis fontSize={10} />
                <Tooltip />
                <Bar dataKey="count" fill="#74FB71" />
              </BarChart>
            </ResponsiveContainer>
          ) : <NoData />}
        </div>
      </div>

      {/* Partners (API keys) */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5', marginBottom: 20 }}>
        <div className="flex justify-between items-center mb-3">
          <div>
            <h3 className="font-extrabold text-sm" style={{ color: '#1a2e22' }}>API partneři</h3>
            <p style={{ color: '#888', fontSize: 11 }}>REST API klíče s rate-limity per partner. Klíč v plain textu se zobrazí pouze 1× při vytvoření.</p>
          </div>
          <button onClick={() => setShowCreateKey(true)}
            className="rounded-btn text-xs font-bold cursor-pointer"
            style={{ padding: '6px 14px', background: '#74FB71', color: '#1a2e22', border: 'none' }}>
            + Nový API klíč
          </button>
        </div>
        {partners.length === 0 ? (
          <p style={{ color: '#888', fontSize: 13 }}>Žádní partneři. Klíč vytvoříš tlačítkem nahoře nebo přes RPC <code>create_api_key()</code>.</p>
        ) : (
          <table className="w-full text-xs">
            <thead>
              <tr style={{ borderBottom: '1px solid #e3e8e5', textAlign: 'left' }}>
                <th className="p-2">Partner</th>
                <th className="p-2">E-mail</th>
                <th className="p-2">Prefix</th>
                <th className="p-2 text-right">Rate / min</th>
                <th className="p-2">Scopes</th>
                <th className="p-2 text-right">Requests ({periodObj.label})</th>
                <th className="p-2">Last used</th>
                <th className="p-2">Status</th>
                <th className="p-2"></th>
              </tr>
            </thead>
            <tbody>
              {partners.map(p => (
                <tr key={p.id} style={{ borderBottom: '1px solid #f1f1f1' }}>
                  <td className="p-2 font-bold" style={{ color: '#1a2e22' }}>{p.partner_name}</td>
                  <td className="p-2">{p.partner_email}</td>
                  <td className="p-2"><code style={{ background: '#f1faf7', padding: '2px 6px', borderRadius: 4, fontSize: 10 }}>{p.key_prefix}…</code></td>
                  <td className="p-2 text-right">{p.rate_limit_rpm}</td>
                  <td className="p-2" style={{ fontSize: 10 }}>{(p.scopes || []).join(', ')}</td>
                  <td className="p-2 text-right font-bold" style={{ color: '#1a2e22' }}>{(stats.byPartner[p.id] || 0).toLocaleString('cs-CZ')}</td>
                  <td className="p-2" style={{ fontSize: 10, color: '#888' }}>{p.last_used_at ? new Date(p.last_used_at).toLocaleDateString('cs-CZ') : '—'}</td>
                  <td className="p-2">
                    <span style={{
                      padding: '2px 8px', borderRadius: 8, fontSize: 10, fontWeight: 700,
                      background: p.is_active && !p.revoked_at ? '#dcfce7' : '#fecaca',
                      color: p.is_active && !p.revoked_at ? '#166534' : '#991b1b',
                    }}>{p.is_active && !p.revoked_at ? 'Aktivní' : 'Revokovaný'}</span>
                  </td>
                  <td className="p-2">
                    {p.is_active && !p.revoked_at && (
                      <button onClick={() => setRevokeKey(p)}
                        style={{ background: 'none', border: 'none', color: '#dc2626', cursor: 'pointer', fontSize: 11, fontWeight: 700 }}
                        title="Zneplatnit klíč">Revoke</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showCreateKey && <CreateApiKeyModal onClose={() => setShowCreateKey(false)} onCreated={loadData} />}
      {revokeKey && <RevokeApiKeyConfirm apiKey={revokeKey} onClose={() => setRevokeKey(null)} onRevoked={loadData} />}

      {/* Top endpoints */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5', marginBottom: 20 }}>
        <h3 className="font-extrabold text-sm mb-3" style={{ color: '#1a2e22' }}>Top endpointy / nástroje</h3>
        {topEndpoints.length === 0 ? <NoData /> : (
          <table className="w-full text-xs">
            <tbody>
              {topEndpoints.map(([ep, c]) => (
                <tr key={ep}>
                  <td className="p-2"><code style={{ background: '#f1faf7', padding: '2px 6px', borderRadius: 4 }}>{ep}</code></td>
                  <td className="p-2 text-right font-bold" style={{ color: '#1a2e22' }}>{c.toLocaleString('cs-CZ')}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Citations (manual log) */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5' }}>
        <div className="flex justify-between items-center mb-3">
          <div>
            <h3 className="font-extrabold text-sm" style={{ color: '#1a2e22' }}>Citation tracking</h3>
            <p style={{ color: '#888', fontSize: 11 }}>Manuální log "kde nás zmínil ChatGPT/Claude/Perplexity"</p>
          </div>
          <button onClick={() => setShowAddCitation(s => !s)}
            className="rounded-btn text-xs font-bold cursor-pointer"
            style={{ padding: '6px 14px', background: '#74FB71', color: '#1a2e22', border: 'none' }}>
            {showAddCitation ? 'Zavřít' : '+ Přidat citation'}
          </button>
        </div>

        {showAddCitation && <AddCitationForm onSaved={() => { setShowAddCitation(false); loadData() }} />}

        {citations.length === 0 ? (
          <p style={{ color: '#888', fontSize: 13, marginTop: 10 }}>Žádné záznamy. Když najdeš zmínku MotoGo24 v AI odpovědi, ulož ji pro tracking trendů.</p>
        ) : (
          <table className="w-full text-xs mt-3">
            <thead>
              <tr style={{ borderBottom: '1px solid #e3e8e5', textAlign: 'left' }}>
                <th className="p-2">Datum</th>
                <th className="p-2">Platforma</th>
                <th className="p-2">Query</th>
                <th className="p-2">Citovaná URL</th>
                <th className="p-2">Pozice</th>
              </tr>
            </thead>
            <tbody>
              {citations.map(c => {
                const pl = PLATFORMS.find(p => p.id === c.ai_platform) || PLATFORMS[7]
                return (
                  <tr key={c.id} style={{ borderBottom: '1px solid #f1f1f1' }}>
                    <td className="p-2" style={{ color: '#888' }}>{new Date(c.observed_at).toLocaleDateString('cs-CZ')}</td>
                    <td className="p-2"><span style={{ padding: '2px 8px', borderRadius: 8, background: pl.color + '22', color: pl.color, fontWeight: 700 }}>{pl.label}</span></td>
                    <td className="p-2" style={{ maxWidth: 300, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={c.query}>{c.query}</td>
                    <td className="p-2" style={{ fontSize: 10 }}>{c.cited_url ? <a href={c.cited_url} target="_blank" rel="noopener noreferrer" style={{ color: '#1a8c1a' }}>{c.cited_url}</a> : '—'}</td>
                    <td className="p-2 text-right">{c.rank || '—'}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}

function KpiTile({ label, value, hint, color = '#1a2e22' }) {
  return (
    <div style={{ background: '#fff', borderRadius: 14, padding: 14, border: '1px solid #e3e8e5' }}>
      <div style={{ color: '#888', fontSize: 10, fontWeight: 700, textTransform: 'uppercase' }}>{label}</div>
      <div style={{ color, fontSize: 22, fontWeight: 800, margin: '4px 0' }}>{value}</div>
      <div style={{ color: '#bbb', fontSize: 10 }}>{hint}</div>
    </div>
  )
}

function NoData() {
  return <p style={{ color: '#888', fontSize: 12, textAlign: 'center', padding: '40px 0' }}>Žádná data v tomto období</p>
}

function AddCitationForm({ onSaved }) {
  const [form, setForm] = useState({ ai_platform: 'chatgpt', query: '', cited_url: '', rank: '', notes: '' })
  const [saving, setSaving] = useState(false)
  async function save() {
    if (!form.query) return
    setSaving(true)
    try {
      await supabase.from('ai_citations').insert({
        ai_platform: form.ai_platform,
        query: form.query,
        cited_url: form.cited_url || null,
        rank: form.rank ? parseInt(form.rank) : null,
        notes: form.notes || null,
      })
      onSaved()
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }
  return (
    <div style={{ background: '#f1faf7', padding: 12, borderRadius: 10, marginTop: 8 }}>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
        <select value={form.ai_platform} onChange={e => setForm(f => ({ ...f, ai_platform: e.target.value }))}
          style={{ padding: 8, borderRadius: 8, border: '1px solid #d4e8e0', fontSize: 12 }}>
          {PLATFORMS.map(p => <option key={p.id} value={p.id}>{p.label}</option>)}
        </select>
        <input placeholder="Pozice v odpovědi (1-10)" type="number" value={form.rank} onChange={e => setForm(f => ({ ...f, rank: e.target.value }))}
          style={{ padding: 8, borderRadius: 8, border: '1px solid #d4e8e0', fontSize: 12 }} />
        <input placeholder="Query (co jsem se ptal AI)" value={form.query} onChange={e => setForm(f => ({ ...f, query: e.target.value }))}
          style={{ padding: 8, borderRadius: 8, border: '1px solid #d4e8e0', fontSize: 12, gridColumn: '1 / -1' }} />
        <input placeholder="Citovaná URL motogo24.cz/..." value={form.cited_url} onChange={e => setForm(f => ({ ...f, cited_url: e.target.value }))}
          style={{ padding: 8, borderRadius: 8, border: '1px solid #d4e8e0', fontSize: 12, gridColumn: '1 / -1' }} />
        <textarea placeholder="Poznámka (volitelné)" rows={2} value={form.notes} onChange={e => setForm(f => ({ ...f, notes: e.target.value }))}
          style={{ padding: 8, borderRadius: 8, border: '1px solid #d4e8e0', fontSize: 12, gridColumn: '1 / -1', resize: 'vertical' }} />
      </div>
      <button onClick={save} disabled={saving || !form.query}
        className="rounded-btn text-xs font-bold cursor-pointer mt-2"
        style={{ padding: '8px 18px', background: '#74FB71', color: '#1a2e22', border: 'none', opacity: saving || !form.query ? 0.5 : 1 }}>
        {saving ? 'Ukládám...' : 'Uložit'}
      </button>
    </div>
  )
}
