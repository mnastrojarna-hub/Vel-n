import { rideStatsV2, fmtSince, fmtLongSec, rideDays, cz } from '../lib/rideStats'

// Řádek seznamu „Jízdy zákazníků": štítky stavu (nahrává se / stojí / čeká na data / visí,
// veřejná, skrytá, cesta) a krátké statistiky. Popisky stejné jako detail.

const fmtDate = (v) => v ? new Date(v).toLocaleString('cs-CZ', { dateStyle: 'medium', timeStyle: 'short' }) : '—'
const fmtMin = (min) => min == null ? '—' : fmtLongSec(Number(min) * 60)
const fmtSec = (sec) => !sec ? '—' : fmtLongSec(sec)
const fmtSpeed = (v) => v == null || Number(v) <= 0 ? '—' : `${Math.round(Number(v))} km/h`

const badge = (bg, color, text, title) => (
  <span className="text-[9px] font-extrabold uppercase rounded-btn" title={title}
    style={{ padding: '2px 6px', background: bg, color }}>{text}</span>
)

/** Štítky u názvu jízdy. `state` = rideRecState(ride), `trip` = cesta nebo null. */
export function RideBadges({ ride, state, trip }) {
  const since = ride.last_fix_at || ride.updated_at
  return (
    <>
      {ride.visibility === 'public' && badge('#e8ffe8', '#1a8a18', 'Veřejná')}
      {state === 'live' && badge('#dcfce7', '#15803d', '● Nahrává se')}
      {state === 'standing' && badge('#e2e8f0', '#334155', `⏸ Stojí od ${fmtSince(since)}`,
        ride.pause_aware
          ? 'Záznam běží, ale motorka stojí — appka nahrává jen při jízdě a při rozjezdu pokračuje sama.'
          : `Poslední GPS bod: ${fmtDate(since)}. Starší appka při stání body neposílá.`)}
      {state === 'awaiting' && badge('#fef3c7', '#92400e', '⏳ Čeká na data',
        'Jízda pod 1 km čeká na body z telefonu, který byl bez internetu — server ji drží (vrácená výpůjčka 7 dní po vrácení, vlastní cesta 30 dní od startu) a pak sám uzavře. Ukončení teď by ji smazalo.')}
      {state === 'stuck' && badge('#fee2e2', '#dc2626', 'Záznam visí',
        `Poslední GPS bod: ${fmtDate(since)}. Dokud záznam visí, nevznikne zákazníkovi další jízda.`)}
      {ride.status === 'hidden' && badge('#fee2e2', '#dc2626', 'Skryto')}
      {trip && badge('#e0e9f8', '#33507a', `🧳 ${trip.name} · ${trip.rides.findIndex(r => r.id === ride.id) + 1}/${trip.rides.length}`,
        trip.explicit ? 'Jízdy sloučené zákazníkem do jedné cesty' : 'Jízdy téže výpůjčky — appka je ukazuje jako jednu cestu')}
    </>
  )
}

/** Krátké statistiky jízdy (km, čas, pauzy, rychlosti…). */
export function RideStatsLine({ ride, stops, photos }) {
  const v2 = rideStatsV2(ride)
  const days = rideDays(ride)
  return (
    <>
      <span title="Celkem ujeto">📏 {Number(ride.distance_km || 0).toFixed(1)} km</span>
      <span title={v2 ? 'Na cestě (bez pauz) — od startu do konce bez nocí a delších přestávek' : 'Celkový čas (start → konec)'}>
        ⏱️ {fmtMin(ride.duration_min)}
      </span>
      <span title="Čas jízdy (v sedle)">🏍️ {fmtSec(ride.moving_sec)}</span>
      <span title={v2 ? 'Zastávky — krátká stání během jízdy (zbytek času na cestě)' : 'Čas stání (zastávky i pauzy)'}>
        ⏸️ {fmtSec(ride.idle_sec)}
      </span>
      {v2 && Number(ride.pause_sec) >= 60 && (
        <span title="Pauzy — noci a delší přestávky; do času na cestě se nepočítají">🛌 {fmtLongSec(ride.pause_sec)}</span>
      )}
      {days >= 2 && <span title="Dny na cestě">📅 {cz(days, 'den', 'dny', 'dní')}</span>}
      <span title="Průměrná rychlost z času jízdy">📊 {fmtSpeed(ride.avg_speed_kmh)}</span>
      <span title="Maximální rychlost">🚀 {fmtSpeed(ride.max_speed_kmh)}</span>
      {ride.gap_sec > 0 && (
        <span title="Čas bez GPS signálu — tyhle úseky trasy neznáme a nepočítají se do kilometrů"
          style={{ color: '#b45309' }}>📵 {fmtSec(ride.gap_sec)} bez signálu</span>
      )}
      {ride.elevation_gain_m > 0 && <span title="Nastoupáno">⛰️ {ride.elevation_gain_m} m</span>}
      <span>📍 {stops} zastávek</span>
      <span>📷 {photos} fotek</span>
      {ride.moto_name && <span>🛵 {ride.moto_name}</span>}
      {ride.booking_id && (
        <a href={`/rezervace/${ride.booking_id}`} className="max-lg:inline-flex max-lg:items-center max-lg:min-h-[32px]" style={{ color: '#1a8a18' }}>🔗 rezervace</a>
      )}
    </>
  )
}
