import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { debugLog } from '../lib/debugLog'

// Monitorovací panel automatického uplatňování Slevomat poukazů.
// Vlastní uplatnění dělá nezávislý automat (GitHub Actions, denně) na partner
// portálu — tato záložka jen ŽIVĚ zobrazuje stav z vouchers.slevomat_apply_*.
// Auto-refresh každých 30 s = „non-stop hlídání".

const STATUS = {
  applied: { label: 'Uplatněno', bg: '#e6f9ec', fg: '#137a3a' },
  already_redeemed: { label: 'Už bylo uplatněno', bg: '#e6f9ec', fg: '#137a3a' },
  invalid: { label: 'Neplatný', bg: '#fde8e8', fg: '#b42318' },
  not_paid: { label: 'Nezaplaceno', bg: '#fde8e8', fg: '#b42318' },
  cancelled: { label: 'Storno/refund', bg: '#fde8e8', fg: '#b42318' },
  failed: { label: 'Chyba (zkusí znovu)', bg: '#fff4e5', fg: '#b25e09' },
  pending: { label: 'Čeká na automat', bg: '#eef2ff', fg: '#3538cd' },
}

function Badge({ status }) {
  const s = STATUS[status] || STATUS.pending
  return (
    <span className="text-xs font-bold rounded-btn" style={{ padding: '3px 10px', background: s.bg, color: s.fg }}>
      {s.label}
    </span>
  )
}

function Stat({ label, value, color }) {
  return (
    <div className="rounded-card" style={{ padding: '16px 20px', background: '#fff', border: '1px solid #eef2ef', minWidth: 140 }}>
      <div className="text-3xl font-extrabold" style={{ color }}>{value}</div>
      <div className="text-xs font-bold uppercase tracking-wide" style={{ color: '#888' }}>{label}</div>
    </div>
  )
}

function fmt(ts) {
  if (!ts) return '—'
  try { return new Date(ts).toLocaleString('cs-CZ') } catch { return ts }
}

export default function Slevomat() {
  const [rows, setRows] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [lastSync, setLastSync] = useState(null)

  const load = useCallback(async () => {
    const { data, error } = await supabase
      .from('vouchers')
      .select('id, code, amount, status, redeemed_at, slevomat_applied_at, slevomat_apply_status, slevomat_apply_error, slevomat_apply_attempts, slevomat_apply_last_at')
      .eq('source', 'slevomat')
      .order('redeemed_at', { ascending: false, nullsFirst: false })
      .limit(300)
    if (error) { setError(error.message); setLoading(false); return }
    setRows(data || [])
    setError(null)
    setLoading(false)
    setLastSync(new Date())
  }, [])

  useEffect(() => {
    debugLog('page.mount', 'Slevomat')
    load()
    const t = setInterval(load, 30000) // auto-refresh = non-stop hlídání
    return () => clearInterval(t)
  }, [load])

  // Stav řádku: hotovo / čeká / chyba (pro frontu počítáme jen redeemed bez applied).
  const effStatus = (r) =>
    r.slevomat_applied_at ? r.slevomat_apply_status
      : r.status === 'redeemed' ? (r.slevomat_apply_status || 'pending')
      : null

  const queue = rows.filter((r) => r.status === 'redeemed' && !r.slevomat_applied_at)
  const pending = queue.filter((r) => (r.slevomat_apply_status || 'pending') === 'pending' || !r.slevomat_apply_status).length
  const failed = queue.filter((r) => ['failed', 'invalid', 'not_paid', 'cancelled'].includes(r.slevomat_apply_status)).length
  const applied = rows.filter((r) => r.slevomat_applied_at).length

  return (
    <div>
      <p className="text-sm mb-5" style={{ color: '#888' }}>
        Automatické uplatňování poukazů přes Slevomat Partner API · panel se obnovuje každých 30 s
      </p>

      <div className="flex gap-3 mb-5 flex-wrap">
        <Stat label="Čeká na uplatnění" value={pending} color="#3538cd" />
        <Stat label="Chyby / k řešení" value={failed} color="#b42318" />
        <Stat label="Uplatněno celkem" value={applied} color="#137a3a" />
      </div>

      <div className="flex items-center gap-3 mb-3">
        <button
          onClick={load}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 18px', background: '#74FB71', color: '#1a2e22', border: 'none' }}
        >
          Obnovit
        </button>
        <span className="text-xs" style={{ color: '#aaa' }}>Naposledy: {lastSync ? lastSync.toLocaleTimeString('cs-CZ') : '—'}</span>
      </div>

      {error && (
        <div className="rounded-card text-sm mb-4" style={{ padding: '12px 16px', background: '#fde8e8', color: '#b42318' }}>
          Chyba načtení: {error}
        </div>
      )}

      <div className="rounded-card" style={{ background: '#fff', border: '1px solid #eef2ef', overflow: 'hidden' }}>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ background: '#f7faf9', color: '#888', textAlign: 'left' }}>
              <th style={{ padding: '10px 14px' }}>Kód</th>
              <th style={{ padding: '10px 14px' }}>Částka</th>
              <th style={{ padding: '10px 14px' }}>Stav na Slevomatu</th>
              <th style={{ padding: '10px 14px' }}>Uplatněno u nás</th>
              <th style={{ padding: '10px 14px' }}>Odesláno na Slevomat</th>
              <th style={{ padding: '10px 14px' }}>Pokusů</th>
              <th style={{ padding: '10px 14px' }}>Poznámka</th>
            </tr>
          </thead>
          <tbody>
            {loading && (
              <tr><td colSpan={7} style={{ padding: '24px', textAlign: 'center', color: '#aaa' }}>Načítám…</td></tr>
            )}
            {!loading && rows.length === 0 && (
              <tr><td colSpan={7} style={{ padding: '24px', textAlign: 'center', color: '#aaa' }}>Žádné Slevomat poukazy.</td></tr>
            )}
            {!loading && rows.map((r) => {
              const st = effStatus(r)
              return (
                <tr key={r.id} style={{ borderTop: '1px solid #f0f4f2' }}>
                  <td style={{ padding: '10px 14px', fontFamily: 'monospace', fontWeight: 700 }}>{r.code}</td>
                  <td style={{ padding: '10px 14px' }}>{r.amount != null ? `${r.amount} Kč` : '—'}</td>
                  <td style={{ padding: '10px 14px' }}>{st ? <Badge status={st} /> : <span style={{ color: '#bbb' }}>—</span>}</td>
                  <td style={{ padding: '10px 14px', color: '#666' }}>{fmt(r.redeemed_at)}</td>
                  <td style={{ padding: '10px 14px', color: '#666' }}>{fmt(r.slevomat_applied_at)}</td>
                  <td style={{ padding: '10px 14px', textAlign: 'center', color: '#666' }}>{r.slevomat_apply_attempts || 0}</td>
                  <td style={{ padding: '10px 14px', color: '#b42318', fontSize: 12, maxWidth: 320 }}>{r.slevomat_apply_error || ''}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
