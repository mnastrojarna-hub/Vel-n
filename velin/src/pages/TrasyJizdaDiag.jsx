import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { diagTimeline, diagVerdict, diagVersions } from '../lib/rideDiag'

// Diagnostika záznamu jízdy — PROČ ve stopě chybí úsek. Rozbalovací sekce
// detailu jízdy; data se načtou až při otevření (jinak žádný dotaz navíc).
// Zdroj: `app_debug_logs` zákazníka v okně jízdy ±15 min (lifecycle = appka
// v popředí / na pozadí / okno zavřené; ride = GPS stream, pauzy bez fixu)
// a `app_installations` (zařízení a verze appky). Obojí admin čte přes RLS.

const PAD_MS = 15 * 60 * 1000
const fmtTime = (v) => v
  ? new Date(v).toLocaleString('cs-CZ', { day: 'numeric', month: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit' })
  : '—'
const TONE = { ok: '#1a8a18', bad: '#b91c1c', info: '#1a2e22' }

export default function TrasyJizdaDiag({ ride }) {
  const [open, setOpen] = useState(false)
  const [data, setData] = useState(null) // { rows, installs, error }

  useEffect(() => {
    if (!open || data || !ride?.user_id) return
    let alive = true
    const start = new Date(ride.started_at).getTime()
    const end = new Date(ride.ended_at || ride.last_fix_at || Date.now()).getTime()
    Promise.all([
      supabase.from('app_debug_logs')
        .select('created_at, category, action, detail, data, app_version, platform')
        .eq('user_id', ride.user_id)
        .in('category', ['lifecycle', 'ride'])
        .gte('created_at', new Date(start - PAD_MS).toISOString())
        .lte('created_at', new Date(end + PAD_MS).toISOString())
        .order('created_at', { ascending: true })
        .limit(500),
      supabase.from('app_installations')
        .select('platform, app_version, last_seen_at')
        .eq('user_id', ride.user_id)
        .order('last_seen_at', { ascending: false })
        .limit(5),
    ]).then(([logs, inst]) => {
      if (!alive) return
      setData({
        rows: logs.data || [],
        installs: inst.data || [],
        error: logs.error?.message || inst.error?.message || null,
      })
    })
    return () => { alive = false }
  }, [open, data, ride?.user_id, ride?.started_at, ride?.ended_at, ride?.last_fix_at])

  const timeline = data ? diagTimeline(data.rows) : []
  const verdict = data ? diagVerdict(ride, data.rows) : []
  const versions = data ? diagVersions(data.rows) : ''

  return (
    <details className="rounded-card" onToggle={e => setOpen(e.currentTarget.open)}
      style={{ background: '#f8fafc', border: '1px solid #d4e8e0', padding: '8px 12px' }}>
      <summary className="text-sm font-extrabold cursor-pointer max-lg:min-h-[36px] max-lg:flex max-lg:items-center"
        style={{ color: '#1a2e22' }}>
        🔎 Diagnostika záznamu (appka zákazníka)
      </summary>
      {!data ? (
        <p className="text-xs mt-2" style={{ color: '#6b8f7b' }}>Načítám logy appky…</p>
      ) : (
        <div className="mt-2 flex flex-col gap-2 text-xs" style={{ color: '#1a2e22' }}>
          {data.error && <p style={{ color: '#dc2626' }}>{data.error}</p>}
          <p>
            <b>Appka v době jízdy:</b> {versions || 'žádné logy'}
            {data.installs.length > 0 && (
              <> · <b>zařízení:</b> {data.installs.map(i =>
                `${i.platform === 'ios' ? 'iOS' : i.platform === 'android' ? 'Android' : (i.platform || '?')} ${i.app_version || '?'} (naposledy ${fmtTime(i.last_seen_at)})`,
              ).join(', ')}</>
            )}
          </p>
          {verdict.map((v, i) => (
            <p key={i} className="rounded-card" style={{ background: '#fffbeb', border: '1px solid #fde68a', color: '#92400e', padding: '6px 8px' }}>
              {v}
            </p>
          ))}
          {timeline.length > 0 && (
            <div className="flex flex-col gap-0.5" style={{ maxHeight: 260, overflowY: 'auto' }}>
              {timeline.map((e, i) => (
                <div key={i} className="flex gap-2">
                  <span className="shrink-0 tabular-nums" style={{ color: '#6b8f7b', minWidth: 112 }}>{fmtTime(e.at)}</span>
                  <span style={{ color: TONE[e.tone] || TONE.info }}>{e.icon} {e.text}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </details>
  )
}
