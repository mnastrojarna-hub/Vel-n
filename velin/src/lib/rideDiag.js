// Diagnostika záznamu jízdy zákazníka (Velín → Trasy → Jízdy zákazníků →
// detail jízdy). Zdroj: `app_debug_logs` z appky — kategorie `lifecycle`
// (popředí / pozadí / zavření okna appky; posílá každá verze) a `ride`
// (GPS stream, pauzy bez fixu, start/konec záznamu; od verze s opravou
// záznamu 2026-10-15). Časy jsou z hodin telefonu, stejně jako body stopy.

import { fmtGap } from './rideTrack'

const ATTACH_REASON = {
  start: 'start záznamu',
  restore: 'obnova ruční jízdy po restartu appky',
  resume_no_fix: 'po návratu do appky — předtím žádný fix',
  resume_error: 'po návratu do appky — GPS hlásilo chybu',
  resume_no_stream: 'po návratu do appky — GPS stream neběžel',
  no_fix: 'po připojení nepřišel žádný fix',
  foreign_closed: 'po zavření navigace',
}

/** Jeden řádek logu → {icon, text, tone} pro časovou osu, nebo null (šum). */
export function describeDiagRow(r) {
  const d = r?.data || {}
  const app = d.app ? ` · appka: ${appStateLabel(d.app)}` : ''
  if (r?.category === 'lifecycle') {
    switch (r.action) {
      case 'app_start': return { icon: '🚀', text: 'Appka spuštěna (nový start procesu)', tone: 'info' }
      case 'resumed': return { icon: '🟢', text: 'Appka v popředí', tone: 'ok' }
      case 'paused': return { icon: '⚪', text: 'Appka na pozadí (zhasnutý displej / jiná appka)', tone: 'info' }
      case 'detached': return { icon: '❌', text: 'Okno appky zavřeno (odsunutí z posledních aplikací / ukončení)', tone: 'bad' }
      default: return null // inactive / hidden = přechodové stavy, jen šum
    }
  }
  if (r?.category !== 'ride') return null
  switch (r.action) {
    case 'stream_attach':
      return { icon: '🛰️', text: `GPS připojeno — ${ATTACH_REASON[r.detail] || r.detail || '?'}${d.shared ? ' (sdílené s navigací)' : ''}${d.error ? `, chyba: ${d.error}` : ''}${app}`, tone: d.error ? 'bad' : 'info' }
    case 'stream_error': return { icon: '⚠️', text: `Chyba GPS: ${r.detail || '?'}${app}`, tone: 'bad' }
    case 'stream_done': return { icon: '⚠️', text: `GPS stream skončil${app}`, tone: 'bad' }
    case 'fix_gap': {
      const moved = Number.isFinite(Number(d.m)) ? `, posun ${fmtMeters(d.m)}` : ''
      // Posun do 300 m = stál (filtr 20 m fixy při stání neposílá) — v pořádku.
      const still = Number(d.m) <= 300
      return { icon: still ? '⏸️' : '📵', text: `${fmtGap(d.sec)} bez fixu${moved}${still ? ' (stál)' : ''}${app}`, tone: still ? 'info' : 'bad' }
    }
    case 'ride_start': return { icon: '▶️', text: d.resumed ? 'Navázáno na rozjetou jízdu (server)' : 'Jízda založena na serveru', tone: 'ok' }
    case 'server_start_failed': return { icon: '⚠️', text: 'Server nedostupný při startu (offline) — body se drží v telefonu', tone: 'bad' }
    case 'ride_closed_by_server': return { icon: '⏹️', text: 'Server jízdu uzavřel (úklid) — navazuje se novou', tone: 'info' }
    case 'ride_continue_no_booking': return { icon: '⏹️', text: 'Výpůjčka už neběží — záznam ukončen', tone: 'info' }
    case 'ride_stop': return { icon: '⏹️', text: d.kept === false ? 'Záznam ukončen (jízda pod 1 km zahozena)' : 'Záznam ukončen', tone: 'info' }
    case 'keep_alive_failed': return { icon: '⚠️', text: `Udržení appky naživu selhalo: ${r.detail || '?'}`, tone: 'bad' }
    default: return { icon: '•', text: `${r.action}${r.detail ? `: ${r.detail}` : ''}`, tone: 'info' }
  }
}

function fmtMeters(m) {
  const n = Number(m) || 0
  return n >= 1000 ? `${(n / 1000).toFixed(1)} km` : `${Math.round(n)} m`
}

function appStateLabel(s) {
  return { resumed: 'v popředí', paused: 'na pozadí', inactive: 'přechod', hidden: 'skrytá', detached: 'okno zavřené' }[s] || s
}

/** Časová osa: popsané řádky bez šumu a bez opakování téhož stavu. */
export function diagTimeline(rows) {
  const out = []
  for (const r of rows || []) {
    const e = describeDiagRow(r)
    if (!e) continue
    const prev = out[out.length - 1]
    if (prev && r.category === 'lifecycle' && prev.action === r.action && prev.category === 'lifecycle') continue
    out.push({ ...e, at: r.created_at, action: r.action, category: r.category })
  }
  return out
}

/**
 * Shrnutí pro operátora — jen jednoznačné případy, nic nedomýšlí.
 * @returns {string[]} věty
 */
export function diagVerdict(ride, rows) {
  const list = rows || []
  if (!list.length) {
    return ['Appka v době jízdy neposlala žádné logy — byla vypnutá, bez internetu, nebo zákazník jezdil s jiným telefonem.']
  }
  const out = []
  const from = new Date(ride?.started_at || 0).getTime()
  const to = new Date(ride?.ended_at || ride?.last_fix_at || Date.now()).getTime()
  const inRide = (r) => { const t = new Date(r.created_at).getTime(); return t >= from && t <= to }
  if (list.some(r => r.category === 'lifecycle' && r.action === 'detached' && inRide(r))) {
    out.push('Během jízdy se okno appky zavřelo (odsunutí z posledních aplikací nebo ukončení systémem). '
      + 'Starší verze appky tím záznam ukončily; nová verze na Androidu nahrává dál, '
      + 'na iPhonu vynucené ukončení appky záznam zastaví vždy.')
  }
  if (list.some(r => r.category === 'ride' && (r.action === 'stream_error' || r.action === 'stream_done'))) {
    out.push('GPS služba v telefonu hlásila chybu — viz časová osa.')
  }
  if (!list.some(r => r.category === 'ride')) {
    out.push('Tahle verze appky ještě neposílá podrobnou diagnostiku GPS (jen popředí/pozadí).')
  }
  return out
}

/** „Android 4.1.3+116, iOS 4.1.0+112" — verze appky, ze kterých logy přišly. */
export function diagVersions(rows) {
  const seen = new Set()
  for (const r of rows || []) {
    if (!r.app_version && !r.platform) continue
    const p = r.platform === 'ios' ? 'iOS' : r.platform === 'android' ? 'Android' : (r.platform || '?')
    seen.add(`${p} ${r.app_version || '?'}`)
  }
  return [...seen].join(', ')
}
