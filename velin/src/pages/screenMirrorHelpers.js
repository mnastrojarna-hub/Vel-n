import { supabase } from '../lib/supabase'

// Zrcadlení obrazovky kiosku (CONTRACT §29): relace v kiosk_screen_sessions (drží ji keepalive z Velína), snímky
// v kiosk_screen_frames (1 řádek / zařízení, realtime). Jednotka posílá jen změněné snímky, ≤ 1 fps, ~50 kB.
export const SESSION_TTL_S = 600          // tvrdý limit relace (jednotka ho hlídá sama)
export const KEEPALIVE_MS = 30 * 1000     // expires_at = now + 90 s, prodlužuje se á 30 s
export const KEEPALIVE_WINDOW_S = 90
const FRAME_COLS = 'device_id, session_id, seq, frame, width, height, captured_at, meta, updated_at'

export async function startSession(device, { control = false } = {}) {
  let uid = null
  try { uid = (await supabase.auth.getUser()).data?.user?.id || null } catch { /* bez uživatele */ }
  // Jedna aktivní relace na zařízení (partial UNIQUE) — starou (zapomenutou) nejdřív ukončit.
  await supabase.from('kiosk_screen_sessions').update({ ended_at: new Date().toISOString() }).eq('device_id', device.id).is('ended_at', null)
  const { data, error } = await supabase.from('kiosk_screen_sessions').insert({
    device_id: device.id, branch_id: device.branch_id || null, created_by: uid, control,
    expires_at: new Date(Date.now() + KEEPALIVE_WINDOW_S * 1000).toISOString(),
  }).select('id').single()
  if (error) throw error
  return data.id
}

export async function keepalive(sessionId) {
  const { error } = await supabase.from('kiosk_screen_sessions')
    .update({ expires_at: new Date(Date.now() + KEEPALIVE_WINDOW_S * 1000).toISOString() }).eq('id', sessionId).is('ended_at', null)
  return !error
}

export async function setControl(sessionId, control) {
  const { error } = await supabase.from('kiosk_screen_sessions').update({ control: !!control }).eq('id', sessionId).is('ended_at', null)
  return !error
}

export async function endSession(sessionId) {
  if (!sessionId) return
  await supabase.from('kiosk_screen_sessions').update({ ended_at: new Date().toISOString() }).eq('id', sessionId).is('ended_at', null)
}

export async function fetchFrame(deviceId, sinceSeq = -1) {
  // Nejdřív jen seq (levné), celý snímek (~50 kB) až když je nový — polling každých pár sekund jako pojistka realtime.
  const { data: head, error } = await supabase.from('kiosk_screen_frames').select('seq, session_id, meta, updated_at').eq('device_id', deviceId).maybeSingle()
  if (error || !head) return null
  if (Number(head.seq) <= sinceSeq) return { ...head, frame: undefined }
  const { data } = await supabase.from('kiosk_screen_frames').select(FRAME_COLS).eq('device_id', deviceId).maybeSingle()
  return data || null
}

export function subscribeFrames(deviceId, onChange) {
  const name = 'screen-' + deviceId + '-' + Math.random().toString(36).slice(2, 8)
  const channel = supabase.channel(name)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'kiosk_screen_frames', filter: `device_id=eq.${deviceId}` }, () => onChange())
    .subscribe()
  return () => { supabase.removeChannel(channel) }
}

// Klik na <img> s object-fit: contain → souřadnice 0..1 v obraze (mimo obraz = null).
export function pointInImage(e, img) {
  const rect = img.getBoundingClientRect()
  const nw = img.naturalWidth || 16, nh = img.naturalHeight || 9
  const scale = Math.min(rect.width / nw, rect.height / nh)
  const w = nw * scale, h = nh * scale
  const ox = rect.left + (rect.width - w) / 2, oy = rect.top + (rect.height - h) / 2
  const x = (e.clientX - ox) / w, y = (e.clientY - oy) / h
  if (x < 0 || x > 1 || y < 0 || y > 1) return null
  return { x: Math.round(x * 10000) / 10000, y: Math.round(y * 10000) / 10000 }
}

export const fmtMb = (bytes) => `${(bytes / 1048576).toFixed(2)} MB`
