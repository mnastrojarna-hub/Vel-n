/**
 * Analýza → AI konverzace
 *
 * Přehled všech konverzací s veřejným AI agentem (motogo24.cz widget). Každý
 * řádek = jedna session (browser session_id, upsertuje se z edge funkce
 * ai-public-agent). Klik otevře drawer s kompletním vláknem + page_context
 * + případnou vazbou na vytvořenou rezervaci.
 *
 * Záměrně bez pretty grafů — toto je nástroj pro reading konverzací,
 * ne dashboard. Statistiky drží paralelní záložka „AI traffic".
 */
import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'

const PERIODS = [
  { id: '24h', label: '24 h',   ms: 24 * 3600 * 1000 },
  { id: '7d',  label: '7 dní',  ms: 7  * 24 * 3600 * 1000 },
  { id: '30d', label: '30 dní', ms: 30 * 24 * 3600 * 1000 },
  { id: '90d', label: '90 dní', ms: 90 * 24 * 3600 * 1000 },
]

const OUTCOMES = [
  { id: 'all', label: 'Vše' },
  { id: 'booking_created', label: 'Vznikla rezervace' },
  { id: 'view', label: 'Jen prohlížení' },
  { id: 'error', label: 'Chyby' },
]

const OUTCOME_LABEL = {
  booking_created: 'Rezervace',
  view: 'Prohlížení',
  quote: 'Cenová poptávka',
  error: 'Chyba',
  rate_limited: 'Rate limit',
}

const OUTCOME_COLOR = {
  booking_created: '#166534',
  view: '#888',
  quote: '#d4a017',
  error: '#dc2626',
  rate_limited: '#7c3aed',
}

function fmtDate(iso) {
  if (!iso) return '—'
  try {
    const d = new Date(iso)
    return d.toLocaleString('cs-CZ', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
  } catch { return iso }
}

function fmtRelative(iso) {
  if (!iso) return ''
  const ms = Date.now() - new Date(iso).getTime()
  if (ms < 60_000) return 'právě teď'
  if (ms < 3_600_000) return `před ${Math.floor(ms / 60_000)} min`
  if (ms < 86_400_000) return `před ${Math.floor(ms / 3_600_000)} h`
  return `před ${Math.floor(ms / 86_400_000)} d`
}

export default function AiPublicConversations() {
  const [period, setPeriod] = useState('7d')
  const [outcome, setOutcome] = useState('all')
  const [search, setSearch] = useState('')
  const [rows, setRows] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [selected, setSelected] = useState(null) // celá row vč. messages

  useEffect(() => { loadData() }, [period, outcome])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const periodObj = PERIODS.find(p => p.id === period)
      const from = new Date(Date.now() - periodObj.ms).toISOString()
      let q = supabase.from('ai_public_conversations')
        .select('id, session_id, lang, page_context, messages, message_count, outcome, booking_id, ip_hash, user_agent, started_at, last_activity_at')
        .gte('started_at', from)
        .order('last_activity_at', { ascending: false })
        .limit(500)
      if (outcome !== 'all') q = q.eq('outcome', outcome)
      const { data, error } = await q
      // Tabulka může v DB ještě nebýt (čeká na admin SQL run) — toleruj graceful.
      const isMissing = error && (error.code === 'PGRST205' || error.code === '42P01' || (error.message || '').includes('schema cache'))
      if (error && !isMissing) throw error
      setRows(error ? [] : (data || []))
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const filtered = useMemo(() => {
    if (!search.trim()) return rows
    const s = search.toLowerCase()
    return rows.filter(r => {
      const msgs = Array.isArray(r.messages) ? r.messages : []
      const flat = msgs.map(m => (m && m.content) || '').join('\n').toLowerCase()
      return flat.includes(s)
        || (r.session_id || '').toLowerCase().includes(s)
        || (r.booking_id || '').toLowerCase().includes(s)
    })
  }, [rows, search])

  const stats = useMemo(() => {
    let bookings = 0, withErrors = 0
    for (const r of rows) {
      if (r.outcome === 'booking_created' || r.booking_id) bookings++
      if (r.outcome === 'error') withErrors++
    }
    return { total: rows.length, bookings, withErrors }
  }, [rows])

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>Chyba načítání: {error}</div>

  return (
    <div>
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <div>
          <h2 className="text-xl font-extrabold" style={{ color: '#1a2e22' }}>AI konverzace</h2>
          <p className="text-xs" style={{ color: '#888' }}>
            Kompletní log konverzací s veřejným AI agentem (motogo24.cz widget) pro analýzu — co zákazníci řeší, kde se zasekávají, jak končí.
          </p>
        </div>
        <div className="flex gap-2 flex-wrap">
          {PERIODS.map(p => (
            <button key={p.id} onClick={() => setPeriod(p.id)}
              className="rounded-btn text-xs font-bold cursor-pointer"
              style={{ padding: '6px 14px', background: period === p.id ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none' }}>
              {p.label}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-3 gap-3 mb-5">
        <KpiTile label="Celkem konverzací" value={stats.total} />
        <KpiTile label="Skončilo rezervací" value={stats.bookings} color="#166534" />
        <KpiTile label="Chyby" value={stats.withErrors} color={stats.withErrors > 0 ? '#dc2626' : '#888'} />
      </div>

      <div className="flex gap-2 mb-3 flex-wrap">
        {OUTCOMES.map(o => (
          <button key={o.id} onClick={() => setOutcome(o.id)}
            className="rounded-btn text-xs font-bold cursor-pointer"
            style={{ padding: '6px 14px', background: outcome === o.id ? '#1a2e22' : '#f1faf7', color: outcome === o.id ? '#74FB71' : '#1a2e22', border: 'none' }}>
            {o.label}
          </button>
        ))}
        <input
          type="text"
          placeholder="Hledat v textu konverzace, session ID, booking ID..."
          value={search}
          onChange={e => setSearch(e.target.value)}
          style={{ flex: '1 1 240px', padding: '6px 12px', borderRadius: 8, border: '1px solid #d4e8e0', fontSize: 13 }}
        />
      </div>

      {filtered.length === 0 ? (
        <div style={{ background: '#fff', borderRadius: 14, padding: 32, border: '1px solid #e3e8e5', textAlign: 'center', color: '#888' }}>
          Žádné konverzace pro toto období / filtr.
        </div>
      ) : (
        <div style={{ background: '#fff', borderRadius: 14, border: '1px solid #e3e8e5', overflow: 'hidden' }}>
          <table style={{ width: '100%', fontSize: 13, borderCollapse: 'collapse' }}>
            <thead style={{ background: '#f1faf7' }}>
              <tr style={{ textAlign: 'left' }}>
                <th style={{ padding: '8px 12px' }}>Začátek</th>
                <th style={{ padding: '8px 12px' }}>Poslední aktivita</th>
                <th style={{ padding: '8px 12px' }}>Zpráv</th>
                <th style={{ padding: '8px 12px' }}>Stránka</th>
                <th style={{ padding: '8px 12px' }}>Jazyk</th>
                <th style={{ padding: '8px 12px' }}>Výsledek</th>
                <th style={{ padding: '8px 12px' }}>Náhled</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(r => {
                const lastUserMsg = (() => {
                  const arr = Array.isArray(r.messages) ? r.messages : []
                  for (let i = arr.length - 1; i >= 0; i--) if (arr[i] && arr[i].role === 'user') return arr[i].content
                  return arr[0]?.content || ''
                })()
                const pcType = r.page_context && (r.page_context.type || r.page_context.path) || ''
                return (
                  <tr key={r.id}
                    onClick={() => setSelected(r)}
                    style={{ cursor: 'pointer', borderTop: '1px solid #e3e8e5' }}
                    onMouseEnter={e => e.currentTarget.style.background = '#f8f9fa'}
                    onMouseLeave={e => e.currentTarget.style.background = ''}>
                    <td style={{ padding: '8px 12px', whiteSpace: 'nowrap' }}>{fmtDate(r.started_at)}</td>
                    <td style={{ padding: '8px 12px', whiteSpace: 'nowrap', color: '#666' }}>{fmtRelative(r.last_activity_at)}</td>
                    <td style={{ padding: '8px 12px', textAlign: 'center', fontWeight: 700 }}>{r.message_count || 0}</td>
                    <td style={{ padding: '8px 12px', color: '#666', fontSize: 11 }}>{pcType || '—'}</td>
                    <td style={{ padding: '8px 12px', textAlign: 'center' }}>{r.lang || '—'}</td>
                    <td style={{ padding: '8px 12px' }}>
                      <span style={{
                        display: 'inline-block', padding: '2px 8px', borderRadius: 10, fontSize: 11, fontWeight: 700,
                        background: (OUTCOME_COLOR[r.outcome] || '#888') + '22',
                        color: OUTCOME_COLOR[r.outcome] || '#888',
                      }}>
                        {OUTCOME_LABEL[r.outcome] || r.outcome || '—'}
                      </span>
                      {r.booking_id && <span style={{ marginLeft: 6, fontSize: 11, color: '#166534' }}>✓</span>}
                    </td>
                    <td style={{ padding: '8px 12px', color: '#444', maxWidth: 360, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {lastUserMsg.slice(0, 120)}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}

      {selected && <ConversationDrawer row={selected} onClose={() => setSelected(null)} />}
    </div>
  )
}

function KpiTile({ label, value, color = '#1a2e22' }) {
  return (
    <div style={{ background: '#fff', borderRadius: 14, padding: 16, border: '1px solid #e3e8e5' }}>
      <div style={{ fontSize: 11, color: '#888', textTransform: 'uppercase', letterSpacing: '.5px', fontWeight: 700 }}>{label}</div>
      <div style={{ fontSize: 26, fontWeight: 800, color, marginTop: 4 }}>{value}</div>
    </div>
  )
}

function ConversationDrawer({ row, onClose }) {
  const messages = Array.isArray(row.messages) ? row.messages : []
  const ctx = row.page_context || {}
  return (
    <div
      onClick={onClose}
      style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,.4)', zIndex: 100, display: 'flex', justifyContent: 'flex-end' }}>
      <div
        onClick={e => e.stopPropagation()}
        style={{ width: 'min(640px, 100vw)', height: '100vh', background: '#fff', overflowY: 'auto', boxShadow: '-12px 0 32px rgba(0,0,0,.2)' }}>
        <div style={{ position: 'sticky', top: 0, background: '#1a2e22', color: '#74FB71', padding: '12px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', zIndex: 1 }}>
          <div>
            <div style={{ fontSize: 11, opacity: .7, letterSpacing: '.5px' }}>SESSION</div>
            <div style={{ fontSize: 13, fontFamily: 'monospace' }}>{row.session_id}</div>
          </div>
          <button onClick={onClose} style={{ background: 'none', border: 'none', color: '#74FB71', fontSize: 22, cursor: 'pointer' }}>✕</button>
        </div>

        <div style={{ padding: 18 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16, fontSize: 12 }}>
            <Field label="Začátek" value={fmtDate(row.started_at)} />
            <Field label="Poslední aktivita" value={fmtDate(row.last_activity_at)} />
            <Field label="Jazyk" value={row.lang || '—'} />
            <Field label="Zpráv" value={row.message_count} />
            <Field label="Výsledek" value={OUTCOME_LABEL[row.outcome] || row.outcome || '—'} color={OUTCOME_COLOR[row.outcome]} />
            <Field label="Booking ID" value={row.booking_id || '—'} mono />
          </div>

          {ctx && (ctx.url || ctx.path || ctx.type) && (
            <div style={{ background: '#f1faf7', borderRadius: 10, padding: 12, marginBottom: 16, fontSize: 12 }}>
              <div style={{ fontWeight: 700, color: '#1a2e22', marginBottom: 6 }}>Kontext stránky</div>
              {ctx.url && <div><span style={{ color: '#888' }}>URL: </span><a href={ctx.url} target="_blank" rel="noopener" style={{ color: '#1a8c1a' }}>{ctx.url}</a></div>}
              {ctx.type && <div><span style={{ color: '#888' }}>Typ: </span>{ctx.type}</div>}
              {ctx.h1 && <div><span style={{ color: '#888' }}>H1: </span>{ctx.h1}</div>}
              {ctx.moto_id && <div><span style={{ color: '#888' }}>moto_id: </span><code>{ctx.moto_id}</code></div>}
              {ctx.selection && <div><span style={{ color: '#888' }}>Označený text: </span>„{ctx.selection}"</div>}
            </div>
          )}

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {messages.map((m, i) => (
              <div key={i} style={{
                alignSelf: m.role === 'user' ? 'flex-end' : 'flex-start',
                maxWidth: '88%',
                background: m.role === 'user' ? '#1a2e22' : '#f1faf7',
                color: m.role === 'user' ? '#fff' : '#1a2e22',
                padding: '10px 14px',
                borderRadius: 12,
                fontSize: 13,
                lineHeight: 1.5,
                whiteSpace: 'pre-wrap',
                wordBreak: 'break-word',
              }}>
                <div style={{ fontSize: 10, fontWeight: 700, opacity: .7, marginBottom: 4, textTransform: 'uppercase', letterSpacing: '.5px' }}>
                  {m.role === 'user' ? 'Zákazník' : 'AI'}
                </div>
                {m.content}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

function Field({ label, value, mono, color }) {
  return (
    <div>
      <div style={{ fontSize: 10, color: '#888', textTransform: 'uppercase', letterSpacing: '.5px', fontWeight: 700 }}>{label}</div>
      <div style={{ fontSize: 13, fontWeight: 600, color: color || '#1a2e22', fontFamily: mono ? 'monospace' : 'inherit', wordBreak: 'break-all' }}>{value}</div>
    </div>
  )
}
