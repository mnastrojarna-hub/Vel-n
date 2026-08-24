/**
 * Analýza → AI konverzace → zdroj „AI agent (appka)"
 *
 * Přehled konverzací přihlášených zákazníků s AI servisním agentem v mobilní
 * appce (tabulka ai_customer_conversations, plní edge fn ai-moto-agent po
 * každé odpovědi). Klik otevře drawer s kompletním vláknem + zákazníkem
 * + případnou vazbou na rezervaci.
 */
import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { useTableSort, sortRows } from '../../components/sortableTable'

const PERIODS = [
  { id: '24h', label: '24 h',   ms: 24 * 3600 * 1000 },
  { id: '7d',  label: '7 dní',  ms: 7  * 24 * 3600 * 1000 },
  { id: '30d', label: '30 dní', ms: 30 * 24 * 3600 * 1000 },
  { id: '90d', label: '90 dní', ms: 90 * 24 * 3600 * 1000 },
]

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

export default function AiAppConversations() {
  const [period, setPeriod] = useState('7d')
  const [search, setSearch] = useState('')
  const [rows, setRows] = useState([])
  const [profiles, setProfiles] = useState({}) // user_id -> { full_name, email }
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [selected, setSelected] = useState(null)
  const CONV_COLUMNS = [
    { label: 'Začátek', key: 'created_at', value: r => (r.created_at ? new Date(r.created_at).getTime() : null) },
    { label: 'Poslední aktivita', key: 'updated_at', value: r => (r.updated_at ? new Date(r.updated_at).getTime() : null) },
    { label: 'Zpráv', key: 'msgCount', value: r => (Array.isArray(r.messages) ? r.messages.length : 0) },
    { label: 'Zákazník', key: 'customer', str: true, value: r => { const p = profiles[r.user_id] || {}; return p.full_name || p.email || '' } },
    { label: 'Rezervace', key: 'booking', value: r => (r.booking_id ? 1 : 0) },
    { label: 'Náhled' },
  ]
  const convSort = useTableSort(CONV_COLUMNS)

  useEffect(() => { loadData() }, [period])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const periodObj = PERIODS.find(p => p.id === period)
      const from = new Date(Date.now() - periodObj.ms).toISOString()
      const { data, error } = await supabase.from('ai_customer_conversations')
        .select('id, user_id, title, messages, booking_id, created_at, updated_at')
        .gte('updated_at', from)
        .order('updated_at', { ascending: false })
        .limit(500)
      if (error) throw error
      const list = data || []
      setRows(list)

      const userIds = [...new Set(list.map(r => r.user_id).filter(Boolean))]
      if (userIds.length > 0) {
        const { data: profs } = await supabase.from('profiles')
          .select('id, full_name, email')
          .in('id', userIds)
        const map = {}
        for (const p of profs || []) map[p.id] = p
        setProfiles(map)
      } else {
        setProfiles({})
      }
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
      const prof = profiles[r.user_id] || {}
      return flat.includes(s)
        || (r.title || '').toLowerCase().includes(s)
        || (r.booking_id || '').toLowerCase().includes(s)
        || (prof.full_name || '').toLowerCase().includes(s)
        || (prof.email || '').toLowerCase().includes(s)
    })
  }, [rows, search, profiles])

  const stats = useMemo(() => {
    const users = new Set()
    let withBooking = 0
    for (const r of rows) {
      if (r.user_id) users.add(r.user_id)
      if (r.booking_id) withBooking++
    }
    return { total: rows.length, users: users.size, withBooking }
  }, [rows])

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>Chyba načítání: {error}</div>

  return (
    <div>
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <p className="text-xs" style={{ color: '#888' }}>
          Konverzace přihlášených zákazníků s AI servisním agentem v mobilní appce — diagnostika závad, dotazy k motorce a rezervaci.
        </p>
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
        <KpiTile label="Zákazníků" value={stats.users} />
        <KpiTile label="S rezervací" value={stats.withBooking} color="#166534" />
      </div>

      <div className="flex gap-2 mb-3 flex-wrap">
        <input
          type="text"
          placeholder="Hledat v textu konverzace, jménu, emailu, booking ID..."
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
        <div style={{ background: '#fff', borderRadius: 14, border: '1px solid #e3e8e5', overflowX: 'auto' }}>
          <table style={{ width: '100%', fontSize: 13, borderCollapse: 'collapse' }}>
            <thead style={{ background: '#f1faf7' }}>
              <tr style={{ textAlign: 'left' }}>
                {CONV_COLUMNS.map(c => (
                  <th key={c.key || c.label} style={{ padding: '8px 12px', cursor: c.key ? 'pointer' : 'default', userSelect: 'none', whiteSpace: 'nowrap' }}
                      title={c.key ? 'Seřadit dle sloupce' : undefined}
                      onClick={() => c.key && convSort.toggle(c.key)}>
                    {c.label}{convSort.sort?.key === c.key ? (convSort.sort.dir === 'desc' ? ' ▼' : ' ▲') : ''}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {sortRows(filtered, CONV_COLUMNS, convSort.sort).map(r => {
                const msgs = Array.isArray(r.messages) ? r.messages : []
                const lastUserMsg = (() => {
                  for (let i = msgs.length - 1; i >= 0; i--) if (msgs[i] && msgs[i].role === 'user') return msgs[i].content
                  return msgs[0]?.content || r.title || ''
                })()
                const prof = profiles[r.user_id] || {}
                return (
                  <tr key={r.id}
                    onClick={() => setSelected(r)}
                    style={{ cursor: 'pointer', borderTop: '1px solid #e3e8e5' }}
                    onMouseEnter={e => e.currentTarget.style.background = '#f8f9fa'}
                    onMouseLeave={e => e.currentTarget.style.background = ''}>
                    <td style={{ padding: '8px 12px', whiteSpace: 'nowrap' }}>{fmtDate(r.created_at)}</td>
                    <td style={{ padding: '8px 12px', whiteSpace: 'nowrap', color: '#666' }}>{fmtRelative(r.updated_at)}</td>
                    <td style={{ padding: '8px 12px', textAlign: 'center', fontWeight: 700 }}>{msgs.length}</td>
                    <td style={{ padding: '8px 12px', color: '#1a2e22' }}>
                      {prof.full_name || prof.email || '—'}
                    </td>
                    <td style={{ padding: '8px 12px', textAlign: 'center' }}>
                      {r.booking_id ? <span style={{ color: '#166534', fontWeight: 700 }}>✓</span> : <span style={{ color: '#ccc' }}>—</span>}
                    </td>
                    <td style={{ padding: '8px 12px', color: '#444', maxWidth: 360, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {String(lastUserMsg).slice(0, 120)}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}

      {selected && (
        <ConversationDrawer
          row={selected}
          profile={profiles[selected.user_id]}
          onClose={() => setSelected(null)}
        />
      )}
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

function ConversationDrawer({ row, profile, onClose }) {
  const messages = Array.isArray(row.messages) ? row.messages : []
  return (
    <div
      onClick={onClose}
      style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,.4)', zIndex: 100, display: 'flex', justifyContent: 'flex-end' }}>
      <div
        onClick={e => e.stopPropagation()}
        style={{ width: 'min(640px, 100vw)', height: '100vh', background: '#fff', overflowY: 'auto', boxShadow: '-12px 0 32px rgba(0,0,0,.2)' }}>
        <div style={{ position: 'sticky', top: 0, background: '#1a2e22', color: '#74FB71', padding: '12px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', zIndex: 1 }}>
          <div>
            <div style={{ fontSize: 11, opacity: .7, letterSpacing: '.5px' }}>ZÁKAZNÍK</div>
            <div style={{ fontSize: 13 }}>{profile?.full_name || profile?.email || row.user_id}</div>
          </div>
          <button onClick={onClose} style={{ background: 'none', border: 'none', color: '#74FB71', fontSize: 22, cursor: 'pointer' }}>✕</button>
        </div>

        <div style={{ padding: 18 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16, fontSize: 12 }}>
            <Field label="Začátek" value={fmtDate(row.created_at)} />
            <Field label="Poslední aktivita" value={fmtDate(row.updated_at)} />
            <Field label="Email" value={profile?.email || '—'} />
            <Field label="Zpráv" value={messages.length} />
            <Field label="Booking ID" value={row.booking_id || '—'} mono />
            <Field label="Titulek" value={row.title || '—'} />
          </div>

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

function Field({ label, value, mono }) {
  return (
    <div>
      <div style={{ fontSize: 10, color: '#888', textTransform: 'uppercase', letterSpacing: '.5px', fontWeight: 700 }}>{label}</div>
      <div style={{ fontSize: 13, fontWeight: 600, color: '#1a2e22', fontFamily: mono ? 'monospace' : 'inherit', wordBreak: 'break-all' }}>{value}</div>
    </div>
  )
}
