/**
 * MotoGo24 Velín — Analýza / Aplikace → Hlášení chyb (bugy z appky)
 *
 * Když mobilní appka spadne tak, že zákazníkovi ukáže obrazovku
 * „🔄 Restartujte aplikaci", appka o tom AUTOMATICKY pošle kompletní hlášení
 * do tabulky `app_crash_reports` (severity='critical'). Hlášení nese:
 *   - typ a text chyby + stack trace (zkrácený na 4000 znaků),
 *   - obrazovku, na které k pádu došlo (`screen` / `extra_data.current_screen`),
 *   - app verzi + platformu (android/ios) + uživatele (user_id),
 *   - „log" = `extra_data.breadcrumbs` = posledních ~40 akcí, API volání,
 *     přechodů obrazovek a payTeb, které k pádu vedly.
 *
 * Tady to zobrazujeme jako řešitelný bug: seznam + rozklikávací detail s celým
 * popisem a logem. Čte se přímo z `app_crash_reports` (admin RLS), bez RPC.
 * Tabulka NENÍ v realtime publikaci, takže místo live streamu auto-obnovujeme
 * každých 30 s (+ tlačítko „Obnovit").
 */
import { useEffect, useState, useRef } from 'react'
import { supabase } from '../../lib/supabase'

const SEV = {
  critical: { label: 'Kritická (restart appky)', bg: '#fde8e8', fg: '#9a2a2a', dot: '#dc2626' },
  error: { label: 'Chyba', bg: '#fef3e8', fg: '#9a5a2a', dot: '#f59e0b' },
  warning: { label: 'Varování', bg: '#fffbe8', fg: '#8a7a2a', dot: '#eab308' },
  info: { label: 'Info', bg: '#eef6ff', fg: '#2a5a9a', dot: '#3b82f6' },
}

const FILTERS = [
  { key: 'fatal', label: 'Pády (restart appky)', sevs: ['critical'] },
  { key: 'errors', label: 'Pády + chyby', sevs: ['critical', 'error'] },
  { key: 'all', label: 'Vše', sevs: null },
]

function fmtTime(iso) {
  try {
    return new Date(iso).toLocaleString('cs-CZ', {
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
    })
  } catch { return iso }
}

function Breadcrumbs({ items }) {
  if (!Array.isArray(items) || items.length === 0) {
    return <div style={{ fontSize: 12, color: '#9aa' }}>Bez logu (starší verze appky tento trail ještě neposílá).</div>
  }
  return (
    <div style={{ background: '#0f1a14', borderRadius: 10, padding: 12, maxHeight: 360, overflow: 'auto' }}>
      {items.map((b, i) => (
        <div key={i} style={{ display: 'flex', gap: 8, fontFamily: 'monospace', fontSize: 11.5, lineHeight: 1.7, color: '#bfe9c9' }}>
          <span style={{ color: '#5f8f6f', minWidth: 64 }}>{(b.t || '').slice(11, 19)}</span>
          <span style={{ color: '#74FB71', minWidth: 78 }}>{b.cat}</span>
          <span style={{ color: '#e8fff0' }}>
            {b.action}
            {b.detail ? <span style={{ color: '#9fc9af' }}> · {b.detail}</span> : null}
            {b.ms != null ? <span style={{ color: '#5f8f6f' }}> ({b.ms} ms)</span> : null}
            {b.data ? <span style={{ color: '#7fae8f' }}> {JSON.stringify(b.data)}</span> : null}
          </span>
        </div>
      ))}
    </div>
  )
}

function CrashRow({ r, userName }) {
  const [open, setOpen] = useState(false)
  const sev = SEV[r.severity] || SEV.error
  const screen = r.screen || r.extra_data?.current_screen || '—'
  const breadcrumbs = r.extra_data?.breadcrumbs

  return (
    <div style={{ border: '1px solid #e3ece8', borderRadius: 12, marginBottom: 8, overflow: 'hidden', background: '#fff' }}>
      <button
        onClick={() => setOpen(o => !o)}
        style={{ width: '100%', textAlign: 'left', background: 'none', border: 'none', cursor: 'pointer', padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 12 }}
      >
        <span style={{ width: 9, height: 9, borderRadius: '50%', background: sev.dot, flexShrink: 0 }} />
        <span style={{ flex: 1, minWidth: 0 }}>
          <span style={{ display: 'block', fontWeight: 700, fontSize: 13.5, color: '#1a2e22', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {r.error_type}: {r.error_message}
          </span>
          <span style={{ display: 'block', fontSize: 12, color: '#7a8b82', marginTop: 2 }}>
            {fmtTime(r.created_at)} · {screen} · {r.platform || '?'} · v{r.app_version || '?'}
            {userName ? ` · ${userName}` : ''}
          </span>
        </span>
        <span style={{ fontSize: 11, fontWeight: 700, padding: '3px 8px', borderRadius: 999, background: sev.bg, color: sev.fg, flexShrink: 0 }}>
          {sev.label}
        </span>
        <span style={{ color: '#9aa', fontSize: 12, flexShrink: 0 }}>{open ? '▲' : '▼'}</span>
      </button>

      {open && (
        <div style={{ padding: '0 14px 14px', borderTop: '1px solid #f0f5f2' }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 10, margin: '12px 0' }}>
            <Meta label="Obrazovka" value={screen} />
            <Meta label="Akce / flow" value={r.action || '—'} />
            <Meta label="Platforma" value={r.platform || '—'} />
            <Meta label="Verze appky" value={r.app_version || '—'} />
            <Meta label="Uživatel" value={userName || r.user_id || 'anonymní'} />
            <Meta label="Čas" value={fmtTime(r.created_at)} />
          </div>

          <Section title="Popis chyby">
            <pre style={preStyle}>{r.error_type}: {r.error_message}</pre>
          </Section>

          {r.stack_trace && (
            <Section title="Stack trace">
              <pre style={{ ...preStyle, maxHeight: 260, overflow: 'auto' }}>{r.stack_trace}</pre>
            </Section>
          )}

          <Section title="Log před pádem (breadcrumbs)">
            <Breadcrumbs items={breadcrumbs} />
          </Section>

          {r.extra_data && Object.keys(r.extra_data).some(k => k !== 'breadcrumbs' && k !== 'current_screen') && (
            <Section title="Další kontext">
              <pre style={{ ...preStyle, maxHeight: 200, overflow: 'auto' }}>
                {JSON.stringify(
                  Object.fromEntries(Object.entries(r.extra_data).filter(([k]) => k !== 'breadcrumbs' && k !== 'current_screen')),
                  null, 2,
                )}
              </pre>
            </Section>
          )}
        </div>
      )}
    </div>
  )
}

const preStyle = { background: '#f6faf8', border: '1px solid #e3ece8', borderRadius: 8, padding: 10, fontSize: 12, color: '#1a2e22', whiteSpace: 'pre-wrap', wordBreak: 'break-word', margin: 0 }

const Meta = ({ label, value }) => (
  <div>
    <div style={{ fontSize: 11, color: '#9aa', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.04em' }}>{label}</div>
    <div style={{ fontSize: 13, color: '#1a2e22', marginTop: 2, wordBreak: 'break-word' }}>{value}</div>
  </div>
)

const Section = ({ title, children }) => (
  <div style={{ marginTop: 10 }}>
    <div style={{ fontSize: 12, fontWeight: 800, color: '#1a2e22', marginBottom: 5 }}>{title}</div>
    {children}
  </div>
)

export default function AppCrashReports() {
  const [rows, setRows] = useState([])
  const [names, setNames] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [filter, setFilter] = useState('fatal')
  const [lastLoaded, setLastLoaded] = useState(null)
  const [deleting, setDeleting] = useState(false)
  const filterRef = useRef(filter)
  filterRef.current = filter

  /// Smaže hlášení dle aktivního filtru (RLS: admin ALL na app_crash_reports).
  /// Maže VŠECHNY odpovídající řádky v DB, ne jen zobrazených ≤200.
  async function deleteAll() {
    const f = FILTERS.find(x => x.key === filterRef.current)
    const scope = f?.sevs ? `všechna hlášení typu „${f.label}"` : 'ÚPLNĚ VŠECHNA hlášení chyb'
    if (!window.confirm(`Opravdu smazat ${scope}? Akce je nevratná.`)) return
    setDeleting(true)
    setError(null)
    try {
      let q = supabase.from('app_crash_reports').delete()
      // supabase-js vyžaduje u delete() aspoň jeden filtr — bez severity
      // filtru mažeme vše přes vždy-pravdivou podmínku na id.
      q = f?.sevs ? q.in('severity', f.sevs) : q.not('id', 'is', null)
      const { error } = await q
      if (error) throw error
      await load()
    } catch (e) {
      setError(e?.message || String(e))
    } finally {
      setDeleting(false)
    }
  }

  async function load() {
    setError(null)
    try {
      const sevs = FILTERS.find(f => f.key === filterRef.current)?.sevs
      let q = supabase
        .from('app_crash_reports')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(200)
      if (sevs) q = q.in('severity', sevs)
      const { data, error } = await q
      if (error) throw error
      const list = data || []
      setRows(list)
      setLastLoaded(new Date())

      // Resolve user names (FK is to auth.users; profiles shares the same id).
      const ids = [...new Set(list.map(r => r.user_id).filter(Boolean))]
      if (ids.length) {
        const { data: profs } = await supabase.from('profiles').select('id, full_name, email').in('id', ids)
        const map = {}
        for (const p of profs || []) map[p.id] = p.full_name || p.email || null
        setNames(map)
      } else {
        setNames({})
      }
    } catch (e) {
      setError(e?.message || String(e))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { setLoading(true); load() /* eslint-disable-next-line */ }, [filter])

  // Auto-refresh every 30 s (table is not in the realtime publication).
  useEffect(() => {
    const id = setInterval(() => load(), 30000)
    return () => clearInterval(id)
    // eslint-disable-next-line
  }, [])

  return (
    <div style={{ marginTop: 26 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', marginBottom: 12 }}>
        <h2 style={{ fontSize: 18, fontWeight: 800, color: '#1a2e22', margin: 0 }}>🐞 Hlášení chyb z aplikace</h2>
        <span style={{ fontSize: 12.5, color: '#7a8b82' }}>
          Automaticky odeslané pády appky (vč. obrazovky „Restartujte aplikaci") s kompletním logem.
        </span>
        <button
          onClick={() => load()}
          style={{ marginLeft: 'auto', padding: '6px 14px', background: '#74FB71', border: 'none', borderRadius: 8, fontWeight: 700, cursor: 'pointer', fontSize: 13 }}
        >
          Obnovit
        </button>
        {rows.length > 0 && (
          <button
            onClick={deleteAll}
            disabled={deleting}
            title="Smaže všechna hlášení odpovídající aktivnímu filtru (nevratné)"
            style={{ padding: '6px 14px', background: '#fde8e8', color: '#9a2a2a', border: '1px solid #f0c0c0', borderRadius: 8, fontWeight: 700, cursor: deleting ? 'wait' : 'pointer', fontSize: 13, opacity: deleting ? 0.6 : 1 }}
          >
            {deleting ? 'Mažu…' : '🗑 Smazat chyby'}
          </button>
        )}
      </div>

      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 14 }}>
        {FILTERS.map(f => (
          <button
            key={f.key}
            onClick={() => setFilter(f.key)}
            style={{
              padding: '6px 14px', borderRadius: 8, border: 'none', cursor: 'pointer', fontSize: 12.5, fontWeight: 700,
              background: filter === f.key ? '#1a2e22' : '#f1faf7',
              color: filter === f.key ? '#74FB71' : '#1a2e22',
            }}
          >
            {f.label}
          </button>
        ))}
      </div>

      {error && (
        <div style={{ padding: 14, background: '#fff3f3', border: '1px solid #f0c0c0', borderRadius: 10, color: '#9a2a2a', fontSize: 13 }}>
          <strong>Hlášení chyb se nepodařilo načíst.</strong>
          <div style={{ marginTop: 6 }}>{error}</div>
        </div>
      )}

      {loading ? (
        <div style={{ padding: 16, color: '#888', fontSize: 13 }}>Načítám hlášení…</div>
      ) : rows.length === 0 ? (
        <div style={{ padding: 18, background: '#f1faf7', borderRadius: 12, color: '#5a7a68', fontSize: 13.5 }}>
          ✅ Žádné odpovídající hlášení chyb. (Appka pošle hlášení automaticky, jakmile nějaký pád nastane.)
        </div>
      ) : (
        <>
          {rows.map(r => <CrashRow key={r.id} r={r} userName={names[r.user_id]} />)}
          {lastLoaded && (
            <div style={{ fontSize: 11.5, color: '#9aa', marginTop: 8 }}>
              {rows.length} hlášení · poslední obnova {lastLoaded.toLocaleTimeString('cs-CZ')} · auto-obnova á 30 s
            </div>
          )}
        </>
      )}
    </div>
  )
}
