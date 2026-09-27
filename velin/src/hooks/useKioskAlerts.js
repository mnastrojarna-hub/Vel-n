import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '../lib/supabase'

// Poplachy samoobsluhy (kiosk_alerts, 2026-09-27): „dveře otevřeny bez kódu“ (FORCED_OPEN z jednotky → trigger
// v DB). Otevřený poplach = acknowledged_at IS NULL; zmizí až ručním „Potvrdit“. Realtime přes postgres_changes,
// k tomu polling 60 s jako pojistka, když realtime vypadne. `notify` = browser Notification (jen když je už povolena).
export const KIOSK_ALERT_SELECT = 'id, branch_id, device_id, door_id, zone, box_number, kind, title, detail, created_at, closed_at, acknowledged_at, branches(name)'

export function useKioskAlerts({ branchId = null, notify = false } = {}) {
  const [alerts, setAlerts] = useState([])
  const [loaded, setLoaded] = useState(false)
  const seq = useRef(0)

  const load = useCallback(async () => {
    const my = ++seq.current
    let q = supabase.from('kiosk_alerts').select(KIOSK_ALERT_SELECT).is('acknowledged_at', null)
      .order('created_at', { ascending: false }).limit(100)
    if (branchId) q = q.eq('branch_id', branchId)
    const { data, error } = await q
    if (my !== seq.current) return           // přišel novější výsledek
    if (!error) setAlerts(data || [])
    setLoaded(true)
  }, [branchId])

  useEffect(() => {
    load()
    const name = 'kiosk-alerts-' + (branchId || 'all') + '-' + Math.random().toString(36).slice(2, 8)
    const channel = supabase.channel(name)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'kiosk_alerts' }, (payload) => {
        load()
        const n = payload.new
        if (payload.eventType === 'INSERT' && n && (!branchId || n.branch_id === branchId) && notify
          && typeof window !== 'undefined' && 'Notification' in window && Notification.permission === 'granted') {
          try {
            new Notification('🚨 ' + (n.title || 'Dveře otevřeny bez kódu'), {
              body: 'Samoobsluha — otevřete Velín → Pobočky a poplach potvrďte.', tag: 'kiosk-alert-' + n.id,
            })
          } catch { /* prohlížeč bez notifikací */ }
        }
      })
      .subscribe()
    const t = setInterval(() => { if (!document.hidden) load() }, 60000)
    return () => { clearInterval(t); supabase.removeChannel(channel) }
  }, [load, branchId, notify])

  return { alerts, loaded, reload: load }
}

export async function acknowledgeKioskAlert(id) {
  let uid = null
  try { uid = (await supabase.auth.getUser()).data?.user?.id || null } catch { /* bez uživatele */ }
  const { error } = await supabase.from('kiosk_alerts')
    .update({ acknowledged_at: new Date().toISOString(), acknowledged_by: uid }).eq('id', id)
  return !error
}

export const fmtAlertTime = (iso) => {
  if (!iso) return ''
  const d = new Date(iso)
  const today = new Date().toDateString() === d.toDateString()
  return (today ? '' : d.toLocaleDateString('cs-CZ') + ' ') + d.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' })
}
