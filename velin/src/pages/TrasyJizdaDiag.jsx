import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { diagTimeline, diagVerdict, diagVersions } from '../lib/rideDiag'

// Diagnostika záznamu jízdy — PROČ ve stopě chybí úsek. Rozbalovací sekce
// detailu jízdy; data se načtou až při otevření (jinak žádný dotaz navíc).
// Zdroj: `app_debug_logs` zákazníka v okně jízdy ±15 min — okno začíná
// nejpozději prvním bodem stopy (appka nahrává i dřív, než jízda vznikne na
// serveru, třeba při startu bez signálu) (lifecycle = appka
// v popředí / na pozadí / okno zavřené; ride = GPS stream, pauzy bez fixu)
// a `app_installations` (zařízení a verze appky). Obojí admin čte přes RLS.

const PAD_MS = 15 * 60 * 1000
// Vícedenní cesta je jeden záznam → logů je víc; načítáme po stránkách
// (PostgREST vrací max 1000 řádků), nejvýš tolik:
const LOG_PAGE = 1000
const LOG_MAX = 4000
const fmtTime = (v) => v
  ? new Date(v).toLocaleString('cs-CZ', { day: 'numeric', month: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit' })
  : '—'
const TONE = { ok: '#1a8a18', bad: '#b91c1c', info: '#1a2e22' }

/** Okno jízdy v ms: od prvního bodu stopy (nebo startu na serveru, co je
 *  dřív) do konce / posledního bodu (co je později). Body = [lat,lng,ts s]. */
function rideWindow(ride, track) {
  const t = Array.isArray(track) ? track : []
  const ts = (p) => (Array.isArray(p) && p.length > 2 && Number(p[2]) > 0 ? Number(p[2]) * 1000 : NaN)
  const first = ts(t[0])
  const last = ts(t[t.length - 1])
  const started = new Date(ride?.started_at).getTime()
  // Rozjetá jízda bez fixu: „teď" zaokrouhlené na minutu, ať se okno
  // (a s ním dotaz) nemění při každém překreslení.
  const ended = ride?.ended_at || ride?.last_fix_at
    ? new Date(ride.ended_at || ride.last_fix_at).getTime()
    : Math.ceil(Date.now() / 60000) * 60000
  return {
    from: Number.isFinite(first) ? Math.min(started, first) : started,
    to: Number.isFinite(last) ? Math.max(ended, last) : ended,
  }
}

export default function TrasyJizdaDiag({ ride, track }) {
  const [open, setOpen] = useState(false)
  const [data, setData] = useState(null) // { key, rows, installs, logsError, instError }
  const { from, to } = rideWindow(ride, track)
  const winKey = `${from}-${to}`
  // Výsledek patří k oknu, pro které se načítal (stopa se dotahuje zvlášť).
  const loaded = data && data.key === winKey ? data : null

  useEffect(() => {
    if (!open || loaded || !ride?.user_id) return
    let alive = true
    const start = from
    const end = to
    const loadLogs = async () => {
      const rows = []
      for (let from = 0; from < LOG_MAX; from += LOG_PAGE) {
        const { data: page, error } = await supabase.from('app_debug_logs')
          .select('created_at, category, action, detail, data, app_version, platform')
          .eq('user_id', ride.user_id)
          .in('category', ['lifecycle', 'ride'])
          .gte('created_at', new Date(start - PAD_MS).toISOString())
          .lte('created_at', new Date(end + PAD_MS).toISOString())
          .order('created_at', { ascending: true }).order('id', { ascending: true })
          .range(from, from + LOG_PAGE - 1)
        if (error) return { data: rows.length ? rows : null, error }
        rows.push(...(page || []))
        if (!page || page.length < LOG_PAGE) return { data: rows, error: null, truncated: false }
      }
      return { data: rows, error: null, truncated: true }
    }
    Promise.all([
      loadLogs(),
      supabase.from('app_installations')
        .select('platform, app_version, last_seen_at')
        .eq('user_id', ride.user_id)
        .order('last_seen_at', { ascending: false })
        .limit(5),
    ]).then(([logs, inst]) => {
      if (!alive) return
      setData({
        key: winKey,
        rows: logs.data || [],
        truncated: !!logs.truncated,
        installs: inst.data || [],
        // Nenačtené logy ≠ „appka žádné neposlala" — závěr se pak neukazuje.
        logsError: logs.error?.message || null,
        instError: inst.error?.message || null,
      })
    })
    return () => { alive = false }
  }, [open, loaded, ride?.user_id, from, to, winKey])

  const ok = loaded && !loaded.logsError
  const timeline = ok ? diagTimeline(loaded.rows) : []
  const verdict = ok ? diagVerdict(ride, loaded.rows, from, to) : []
  const versions = ok ? diagVersions(loaded.rows) : ''

  return (
    <details className="rounded-card" onToggle={e => setOpen(e.currentTarget.open)}
      style={{ background: '#f8fafc', border: '1px solid #d4e8e0', padding: '8px 12px' }}>
      <summary className="text-sm font-extrabold cursor-pointer max-lg:min-h-[36px] max-lg:flex max-lg:items-center"
        style={{ color: '#1a2e22' }}>
        🔎 Diagnostika záznamu (appka zákazníka)
      </summary>
      {!loaded ? (
        <p className="text-xs mt-2" style={{ color: '#6b8f7b' }}>Načítám logy appky…</p>
      ) : (
        <div className="mt-2 flex flex-col gap-2 text-xs" style={{ color: '#1a2e22' }}>
          {(loaded.logsError || loaded.instError) && (
            <p style={{ color: '#dc2626' }}>
              {loaded.logsError ? 'Logy appky' : 'Zařízení zákazníka'} se nepodařilo načíst
              ({loaded.logsError || loaded.instError}).{' '}
              <button className="underline cursor-pointer" onClick={() => setData(null)}
                style={{ background: 'none', border: 'none', color: '#dc2626', padding: 0 }}>Zkusit znovu</button>
            </p>
          )}
          <p>
            <b>Appka v době jízdy:</b> {loaded.logsError ? 'nenačteno' : (versions || 'žádné logy')}
            {loaded.installs.length > 0 && (
              <> · <b>zařízení:</b> {loaded.installs.map(i =>
                `${i.platform === 'ios' ? 'iOS' : i.platform === 'android' ? 'Android' : (i.platform || '?')} ${i.app_version || '?'} (naposledy ${fmtTime(i.last_seen_at)})`,
              ).join(', ')}</>
            )}
          </p>
          {loaded.truncated && (
            <p style={{ color: '#6b8f7b' }}>Dlouhá cesta — zobrazeno prvních {LOG_MAX} záznamů logu.</p>
          )}
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
