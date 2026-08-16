/**
 * Indikátor „zákazník má nainstalovanou mobilní appku" — sdílené UI pro
 * seznam rezervací (booking/BookingsTable.jsx), detail rezervace
 * (BookingDetail.jsx), seznam zákazníků (Customers.jsx) a detail zákazníka
 * (CustomerDetail.jsx).
 *
 * Zdroj: tabulka `app_installations` (heartbeat z appky se stabilním device
 * UUID, throttle ~12 h; admin SELECT přes RLS). Instalace = zařízení
 * s heartbeatem za posledních 30 dní — stejná definice jako `active_devices`
 * (MAU) v RPC `get_app_install_stats`. Po odinstalaci heartbeat ustane
 * a indikátor do 30 dnů sám zmizí (řádek v tabulce zůstává).
 *
 * props:
 *  - install = záznam z `loadAppInstalls` pro daného user_id (undefined = bez appky)
 */
const ACTIVE_DAYS = 30

export default function AppInstallBadge({ install }) {
  if (!install?.active) return null
  const plats = [...install.platforms]
    .map(p => p === 'ios' ? 'iOS' : p === 'android' ? 'Android' : p)
    .join(' + ')
  const seen = install.lastSeen ? new Date(install.lastSeen).toLocaleDateString('cs-CZ') : '—'
  return (
    <span className="ml-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded-btn"
      title={`Má nainstalovanou aplikaci MotoGo24${plats ? ` (${plats})` : ''} — naposledy aktivní ${seen}`}
      style={{ background: '#f3e8ff', color: '#7e22ce', whiteSpace: 'nowrap' }}>
      📱 APPKA
    </span>
  )
}

/** Dávkové načtení instalací appky pro seznam uživatelů →
 *  Map<user_id, {active, platforms:Set, lastSeen}>. Jeden dotaz s `in`
 *  (vzor `loadDocScans`); počítají se jen zařízení aktivní do 30 dní. */
export async function loadAppInstalls(supabase, userIds) {
  const ids = [...new Set((userIds || []).filter(Boolean))]
  if (!ids.length) return {}
  const since = new Date(Date.now() - ACTIVE_DAYS * 86400000).toISOString()
  const { data } = await supabase.from('app_installations')
    .select('user_id, platform, last_seen_at')
    .in('user_id', ids)
    .gte('last_seen_at', since)
  const map = {}
  ;(data || []).forEach(r => {
    if (!r.user_id) return
    const cur = map[r.user_id] || { active: true, platforms: new Set(), lastSeen: null }
    if (r.platform) cur.platforms.add(String(r.platform).toLowerCase())
    if (!cur.lastSeen || r.last_seen_at > cur.lastSeen) cur.lastSeen = r.last_seen_at
    map[r.user_id] = cur
  })
  return map
}
