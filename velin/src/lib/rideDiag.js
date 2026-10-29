// Diagnostika záznamu jízdy zákazníka (Velín → Trasy → Jízdy zákazníků →
// detail jízdy). Zdroj: `app_debug_logs` z appky — kategorie `lifecycle`
// (popředí / pozadí / zavření okna appky; posílá každá verze) a `ride`
// (GPS stream, pauzy bez fixu, start/konec záznamu; od verze s opravou
// záznamu 2026-10-15; stavy záznamu, auto-pauza a pokračování od verze
// s pauzami 2026-10). Časy jsou z hodin telefonu, stejně jako body stopy.

import { fmtGap } from './rideTrack'

const ATTACH_REASON = {
  start: 'start záznamu',
  restore: 'obnova ruční jízdy po restartu appky',
  resume_no_fix: 'po návratu do appky — předtím žádný fix',
  resume_error: 'po návratu do appky — GPS hlásilo chybu',
  resume_no_stream: 'po návratu do appky — GPS stream neběžel',
  no_fix: 'po připojení nepřišel žádný fix',
  foreign_closed: 'po zavření navigace',
  resume_manual: 'pokračování po ruční pauze',
  service_on: 'poloha v telefonu znovu zapnutá',
}

// Stav záznamu nové appky (RidePhase) a důvod pauzy (RidePauseReason).
const PHASE = { riding: 'jízda', autoPaused: 'auto-pauza', manualPaused: 'pauza (GPS vypnuto)' }
const REASON = {
  start: 'připraveno — čeká na rozjezd', stop: 'stání', walk: 'chůze', silence: 'ticho bez GPS',
  manual: 'ručně', home: 'doma', long: 'dlouhá pauza',
}
const reasonLabel = (x) => REASON[x] || x || '?'
const CONT_REASON = {
  closed: 'server jízdu uzavřel', gone: 'jízda na serveru chybí', booking_ended: 'výpůjčka skončila',
  upgrade: 'přechod na cesty s pauzami',
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
      // Během pauzy (nová appka) je ticho normální — nahrává se jen při jízdě.
      const still = Number(d.m) <= 300 || (d.phase && d.phase !== 'riding')
      const ph = d.phase && d.phase !== 'riding' ? `, ${PHASE[d.phase] || d.phase}` : ''
      return { icon: still ? '⏸️' : '📵', text: `${fmtGap(d.sec)} bez fixu${moved}${Number(d.m) <= 300 ? ' (stál)' : ''}${ph}${app}`, tone: still ? 'info' : 'bad' }
    }
    case 'ride_start': return {
      icon: '▶️',
      text: (d.resumed ? 'Navázáno na rozjetou jízdu (server)' : 'Jízda založena na serveru')
        + (d.proto === 'trip' ? ' — cesta s pauzami' : (d.proto === 'legacy' ? ' — starý způsob (server bez pauz)' : '')),
      tone: 'ok',
    }
    case 'server_start_failed': return { icon: '⚠️', text: 'Server nedostupný při startu (offline) — body se drží v telefonu', tone: 'bad' }
    case 'ride_closed_by_server': return {
      icon: '⏹️',
      text: d.booking_ended ? 'Výpůjčka skončila (vrácení) — server jízdu uzavřel k času vrácení'
        : (d.result === 'gone' ? 'Jízda na serveru už není (smazaná) — záznam se nenavazuje do ní'
          : 'Server jízdu uzavřel (úklid) — navazuje se novou'),
      tone: 'info',
    }
    case 'ride_continue_no_booking': return { icon: '⏹️', text: 'Výpůjčka už neběží — záznam ukončen', tone: 'info' }
    case 'ride_stop': return { icon: '⏹️', text: d.kept === false ? 'Záznam ukončen (jízda pod 1 km zahozena)' : 'Záznam ukončen', tone: 'info' }
    case 'engine_reattached': return { icon: '🔁', text: 'Appka znovu otevřena — navázáno na běžící záznam', tone: 'ok' }
    case 'keep_alive_failed': return { icon: '⚠️', text: `Udržení appky naživu selhalo: ${r.detail || '?'}`, tone: 'bad' }
    case 'ride_discard': return { icon: '🗑️', text: 'Záznam zahozen jezdcem (nic se neuložilo)', tone: 'info' }
    default: return describePauseRow(r, d, app)
  }
}

/** Řádky nové appky s pauzami (stav, pauza, pokračování, pojistky). */
function describePauseRow(r, d, app) {
  switch (r.action) {
    case 'phase': {
      const b = d.battery && Number.isFinite(Number(d.battery.pct))
        ? ` · baterie ${Math.round(Number(d.battery.pct))} %${d.battery.charging ? ' (nabíjí se)' : ''}` : ''
      return {
        icon: d.to === 'riding' ? '▶️' : '⏸️',
        text: `Stav záznamu: ${PHASE[d.from] || d.from || '?'} → ${PHASE[d.to] || d.to || '?'}${d.reason ? ` (${reasonLabel(d.reason)})` : ''}${b}${app}`,
        tone: 'info',
      }
    }
    case 'pause': {
      const m = Number.isFinite(Number(d.m)) ? `, posun ${fmtMeters(d.m)}` : ''
      const held = Number(d.held) > 0 ? `, ${d.held} bodů pomalého úseku zadrženo` : ''
      return { icon: '⏸️', text: `Pozastaveno (${reasonLabel(d.reason || r.detail)})${m}${held}${app}`, tone: 'info' }
    }
    case 'resume': {
      const manual = (d.mode || r.detail) === 'manual'
      const p = Number(d.pause_sec) > 0 ? `, pauza ${fmtGap(d.pause_sec)}` : ''
      const m = Number.isFinite(Number(d.m)) ? `, ${fmtMeters(d.m)} od místa zastavení` : ''
      const pre = Number(d.preroll) > 0 ? `, ${d.preroll} bodů rozjezdu` : ''
      const from = d.from ? ` (předtím: ${reasonLabel(d.from)})` : ''
      const far = d.kill_gap ? ' — po restartu appky daleko od místa zastavení' : ''
      return { icon: '▶️', text: `Pokračuje ${manual ? 'ručně' : 'automaticky (rozjezd)'}${from}${p}${m}${pre}${far}${app}`, tone: 'ok' }
    }
    case 'tail_restore':
      return { icon: '↩️', text: `Obnovený pomalý úsek (kolona, hledání parkování): ${d.n || '?'} bodů, ${fmtMeters(d.m)}`, tone: 'info' }
    case 'home_pause':
      return { icon: '🏠', text: `Pauza doma (GPS vypnuto) — motorka stojí u startu${d.h ? ` ${d.h} h` : ''}; appka se jezdce zeptá, jestli pokračovat`, tone: 'info' }
    case 'long_pause':
      return { icon: '🛌', text: `Dlouhá pauza (GPS vypnuto kvůli baterii)${d.h ? ` po ${d.h} h` : ''} — pokračuje po otevření appky`, tone: 'info' }
    case 'trip_continue':
      return { icon: '🔗', text: `Nová jízda po uzavření serverem (${CONT_REASON[d.reason] || d.reason || '?'})`, tone: 'info' }
    case 'caps':
      return { icon: '🧩', text: `Server: podpora cest s pauzami ${d.trips ? 'ano' : 'ne (starý server — nahrává se postaru)'}`, tone: d.trips ? 'ok' : 'info' }
    case 'clock_offset':
      return { icon: '🕒', text: `Posun hodin telefonu: ${Math.abs(Number(d.sec)) || '?'} s proti serveru — časy bodů appka opravuje`, tone: Math.abs(Number(d.sec)) >= 120 ? 'bad' : 'info' }
    case 'notif_failed': return { icon: '⚠️', text: `Notifikace selhala${r.detail ? `: ${r.detail}` : ''}`, tone: 'bad' }
    case 'own_saved_for_rental':
      return { icon: '💾', text: `Vlastní cesta uložena kvůli výpůjčce${d.kept === false ? ' (pod 1 km — zahozena)' : ''}`, tone: 'info' }
    case 'flag':
      return { icon: '🚩', text: `Auto-pauza ${d.on === false ? 'VYPNUTÁ (flag ride_autopause)' : 'zapnutá'}${flagCond(d.cond)}`, tone: d.on === false ? 'bad' : 'info' }
    default: return { icon: '•', text: `${r.action}${r.detail ? `: ${r.detail}` : ''}`, tone: 'info' }
  }
}

function flagCond(c) {
  if (!c || typeof c !== 'object') return ''
  const parts = []
  // Appka loguje zkrácené klíče (RideAutoPauseFlag.toJson), flag v DB plné.
  const v = (a, b) => c[a] ?? c[b]
  if (v('stop', 'stop_min') != null) parts.push(`stání ${v('stop', 'stop_min')} min`)
  if (v('walk', 'walk_min') != null) parts.push(`chůze ${v('walk', 'walk_min')} min`)
  if (v('resume', 'resume_kmh') != null) parts.push(`rozjezd ${v('resume', 'resume_kmh')} km/h`)
  return parts.length ? ` (${parts.join(', ')})` : ''
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
export function diagVerdict(ride, rows, fromMs, toMs) {
  const list = rows || []
  if (!list.length) {
    return ['Appka v době jízdy neposlala žádné logy — byla vypnutá, bez internetu, nebo zákazník jezdil s jiným telefonem.']
  }
  const out = []
  // Okno jízdy (TrasyJizdaDiag ho počítá i z bodů stopy), jinak ze serveru.
  const from = Number.isFinite(fromMs) ? fromMs : new Date(ride?.started_at || 0).getTime()
  const to = Number.isFinite(toMs) ? toMs : new Date(ride?.ended_at || ride?.last_fix_at || Date.now()).getTime()
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
  const rideRows = list.filter(r => r.category === 'ride' && inRide(r))
  const autoPauses = rideRows.filter(r => r.action === 'pause' && (r.data?.reason || r.detail) !== 'manual').length
  if (autoPauses > 0) {
    out.push(`Záznam se ${autoPauses}× sám pozastavil (stání, chůze, noc) — v pořádku: nová appka nahrává jen při jízdě `
      + 'a pauzy se nepočítají do kilometrů ani do času na cestě.')
  }
  if (rideRows.some(r => r.action === 'home_pause' || r.action === 'long_pause')) {
    out.push('Během dlouhé pauzy appka vypnula GPS kvůli baterii — záznam pokračuje, až jezdec appku otevře.')
  }
  if (rideRows.some(r => r.action === 'flag' && r.data?.on === false)) {
    out.push('Auto-pauza byla vypnutá (příznak ride_autopause) — záznam běžel bez automatických pauz.')
  }
  if (rideRows.some(r => r.action === 'caps' && r.data?.trips === false)) {
    out.push('Server v době jízdy ještě neuměl cesty s pauzami — jízda se nahrávala postaru (přes noc se mohla rozdělit).')
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
