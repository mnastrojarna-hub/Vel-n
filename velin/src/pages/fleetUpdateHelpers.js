import { supabase } from '../lib/supabase'
import { isRpiDevice } from './BranchRpiUi'

// ─── Hromadná aktualizace řídicích jednotek — datová vrstva + čisté helpery ──
// Tabulky: kiosk_releases, kiosk_rollouts, kiosk_rollout_devices, kiosk_devices, kiosk_fleet_settings.
// RPC: kiosk_rollout_start / kiosk_rollout_cancel / kiosk_rollout_tick (kontrakt §2).

export const ONLINE_MS = 70 * 1000
export const ACTIVE_STATUSES = ['canary', 'soak', 'rollout']
export const DEFAULT_SETTINGS = {
  id: true, nightly_enabled: false, nightly_hour: 3, canary_device_id: null, soak_minutes: 180, wait_idle_s: 1800,
  system_enabled: false, system_every_days: 28, system_auto_reboot: true, last_nightly_date: null, last_system_date: null,
}

export const ROLLOUT_STATUS_CZ = {
  canary: 'Kanárek', soak: 'Sledování', rollout: 'Rozesílání', done: 'Hotovo', failed: 'Selhalo', cancelled: 'Zrušeno',
}
export const ROLLOUT_STATUS_TONE = { canary: 'amber', soak: 'blue', rollout: 'dark', done: 'green', failed: 'red', cancelled: 'gray' }
export const DEV_STATUS_CZ = {
  pending: 'čeká na řadu', commanded: 'příkaz odeslán', updated: 'aktualizováno', failed: 'selhalo', offline: 'offline', skipped: 'přeskočeno',
}
export const DEV_STATUS_TONE = { pending: 'gray', commanded: 'amber', updated: 'green', failed: 'red', offline: 'red', skipped: 'gray' }
export const KIND_CZ = { software: 'Software', system: 'OS (Debian)' }
export const MODE_CZ = { manual: 'ručně', nightly: 'noční automatika' }

const RPC_ERRORS_CZ = {
  forbidden: 'Nemáte oprávnění (jen správce).',
  invalid_kind: 'Neplatný typ aktualizace.',
  invalid_mode: 'Neplatný režim spuštění.',
  rollout_active: 'Už probíhá jiná hromadná aktualizace — nejdřív ji nechte doběhnout nebo ji zrušte.',
  release_not_found: 'Release nebyl nalezen — GitHub Action ho zatím do kiosk_releases nezapsala.',
  no_canary: 'Žádná řídicí jednotka není online — kanárka není z čeho vybrat.',
  canary_not_found: 'Vybraný kanárek není aktivní řídicí jednotka (Raspberry).',
  not_found: 'Rollout nebyl nalezen.',
  not_active: 'Rollout už neběží (je dokončený nebo zrušený).',
}
// Celé číslo v rozsahu CHECK; prázdné / neplatné → fallback (NIKDY 0 — prázdné „čekání na klid“ by vypnulo pojistku 1),
// desetinné → zaokrouhlit (int sloupce / int parametry RPC by Postgres odmítl)
export const isIntInput = v => v !== '' && v != null && Number.isFinite(Number(v))
export function intInRange(v, min, max, fallback) {
  if (!isIntInput(v)) return fallback
  return Math.min(max, Math.max(min, Math.round(Number(v))))
}

export function rpcErrorText(code) {
  return RPC_ERRORS_CZ[code] || `Chyba: ${code || 'neznámá'}`
}

// Chyba rolloutu (kiosk_rollouts.error) → česky
export function rolloutErrorText(err) {
  if (!err) return ''
  const s = String(err)
  if (s.startsWith('canary_failed')) return `Kanárek selhal (${s.slice('canary_failed:'.length).trim() || '?'})`
  if (s === 'canary_timeout') return 'Kanárek se v limitu neaktualizoval (čekání na klid + 45 min)'
  if (s.startsWith('canary_errors')) return `Kanárek během sledování hlásil chyby (${s.split(':')[1]?.trim() || '?'})`
  if (s === 'canary_offline') return 'Kanárek během sledování přestal komunikovat (offline > 10 min)'
  if (s.startsWith('devices_failed')) return `Aktualizace selhala na ${s.split(':')[1]?.trim() || '?'} jednotkách`
  if (s === 'cancelled') return 'Zrušeno z Velína'
  return s
}

// ── Verze ──
export const sha7 = commit => (commit ? String(commit).slice(0, 7) : '')
export function versionMatches(appVersion, commit) {
  const short = String(appVersion || '').split('+')[1] || ''
  return short.length >= 7 && !!commit && String(commit).startsWith(short)
}

// ── Bezpečné čtení status JSON ze zařízení ──
const obj = v => (v && typeof v === 'object' && !Array.isArray(v) ? v : {})
export const deviceStatus = dev => obj(dev?.status)
export const deviceSys = dev => obj(obj(deviceStatus(dev).health).sys)
export const deviceUpdate = dev => obj(deviceStatus(dev).update)
export const isOnline = (dev, now) => !!(dev?.last_seen_at && now - new Date(dev.last_seen_at).getTime() < ONLINE_MS)

// Stav aktualizace na jednotce (status.update.state) → {text, tone} nebo null (idle / neznámé)
export function updateStateInfo(upd) {
  const st = String(upd?.state || 'idle')
  const kind = upd?.kind === 'system' ? 'OS' : 'software'
  if (st === 'waiting') return { text: `čeká na klid (${kind})`, tone: 'amber' }
  if (st === 'running') return { text: `probíhá (${kind})`, tone: 'blue' }
  if (st === 'rebooting') return { text: 'restart OS', tone: 'amber' }
  const err = upd?.error == null ? '' : typeof upd.error === 'string' ? upd.error : JSON.stringify(upd.error)
  if (st === 'failed') return { text: `selhalo (${kind})${err ? `: ${err.slice(0, 120)}` : ''}`, tone: 'red' }
  if (st === 'done') return { text: `hotovo (${kind})`, tone: 'green' }
  return null
}

// ── Formátování ──
export function fmtDT(ts) {
  if (!ts) return '—'
  const d = new Date(ts)
  return Number.isFinite(d.getTime()) ? d.toLocaleString('cs-CZ', { day: 'numeric', month: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—'
}
export function fmtTime(ts) {
  if (!ts) return '—'
  const d = new Date(ts)
  return Number.isFinite(d.getTime()) ? d.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' }) : '—'
}
export const deviceLabel = dev => (dev ? `${dev.branches?.name || 'bez pobočky'} — ${dev.name || 'Raspberry'}` : '?')

// Popis fáze aktivního rolloutu (kontrakt §6.4)
export function phaseText(rollout, rows, devById) {
  if (!rollout) return ''
  if (rollout.status === 'canary') {
    const canary = devById[rollout.canary_device_id]
    return `Kanárek: čeká na aktualizaci „${canary?.branches?.name || canary?.name || '?'}“`
  }
  if (rollout.status === 'soak') return `Sledování: bez chyb do ${fmtTime(rollout.soak_until)}`
  if (rollout.status === 'rollout') {
    const fleet = rows.filter(r => r.role === 'fleet' && r.status !== 'skipped')
    const done = fleet.filter(r => r.status === 'updated').length
    return `Rozesílání: ${done} z ${fleet.length} hotovo`
  }
  return ROLLOUT_STATUS_CZ[rollout.status] || rollout.status
}

// ── Načtení všeho, co blok potřebuje (jedno volání → jeden setState) ──
export async function loadFleetData() {
  const [rel, dev, set, act, hist] = await Promise.all([
    supabase.from('kiosk_releases').select('*')
      .order('committed_at', { ascending: false, nullsFirst: false }).order('created_at', { ascending: false }).limit(10),
    supabase.from('kiosk_devices').select('id, branch_id, name, platform, app_version, last_seen_at, is_active, status, status_at, branches(name)')
      .order('name'),
    supabase.from('kiosk_fleet_settings').select('*').eq('id', true).maybeSingle(),
    supabase.from('kiosk_rollouts').select('*, kiosk_releases(version, commit)').in('status', ACTIVE_STATUSES)
      .order('created_at', { ascending: false }).limit(1).maybeSingle(),
    supabase.from('kiosk_rollouts').select('*, kiosk_releases(version, commit)').in('status', ['done', 'failed', 'cancelled'])
      .order('created_at', { ascending: false }).limit(10),
  ])
  const firstErr = [rel, dev, set, act, hist].find(r => r.error)?.error
  if (firstErr) throw new Error(firstErr.message || 'Načtení dat aktualizací selhalo')
  let activeRows = []
  if (act.data) {
    const { data, error } = await supabase.from('kiosk_rollout_devices').select('*').eq('rollout_id', act.data.id)
    if (error) throw new Error(error.message)
    activeRows = data || []
  }
  const devices = (dev.data || []).filter(d => isRpiDevice(d) && d.is_active !== false)
  return {
    releases: rel.data || [], devices, settings: { ...DEFAULT_SETTINGS, ...(set.data || {}) },
    active: act.data || null, activeRows, history: hist.data || [],
  }
}

// Jeden příkaz jedné jednotce (stejně jako BranchSelfService.sendCommand — branch_id + created_by). Vrací true/false.
export async function sendDeviceCommand(dev, command, params = {}) {
  const { data: { user } } = await supabase.auth.getUser()
  const { error } = await supabase.from('kiosk_commands').insert({
    device_id: dev.id, branch_id: dev.branch_id, command, params, created_by: user?.id || null,
  })
  if (error) throw new Error(error.message)
  return true
}

// RPC obálka: chyba supabase → výjimka, {ok:false,error} → výjimka s českým textem
export async function fleetRpc(name, args) {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw new Error(error.message)
  if (data && data.ok === false) throw new Error(rpcErrorText(data.error))
  return data
}

export async function saveFleetSettings(form) {
  const row = {
    id: true,
    nightly_enabled: !!form.nightly_enabled,
    nightly_hour: intInRange(form.nightly_hour, 0, 23, DEFAULT_SETTINGS.nightly_hour),
    canary_device_id: form.canary_device_id || null,
    soak_minutes: intInRange(form.soak_minutes, 5, 1440, DEFAULT_SETTINGS.soak_minutes),
    wait_idle_s: intInRange(form.wait_idle_s, 0, 14400, DEFAULT_SETTINGS.wait_idle_s),
    system_enabled: !!form.system_enabled,
    system_every_days: intInRange(form.system_every_days, 1, 365, DEFAULT_SETTINGS.system_every_days),
    system_auto_reboot: !!form.system_auto_reboot,
    updated_at: new Date().toISOString(),
  }
  const { error } = await supabase.from('kiosk_fleet_settings').upsert(row, { onConflict: 'id' })
  if (error) throw new Error(error.message)
  return row
}
