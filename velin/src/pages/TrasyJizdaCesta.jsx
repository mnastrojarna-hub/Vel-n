import { tripTotals, tripDates } from '../lib/rideTrip'
import { fmtLongSec, cz } from '../lib/rideStats'

// Příslušnost jízdy k CESTĚ — appka zákazníka ukazuje tyhle jízdy jako jednu
// položku „Moje jízdy" (sloučil je jezdec, nebo jde o jízdy téže výpůjčky).
// Velín cestu jen ukazuje; sloučit / rozdělit ji může jen zákazník v appce.

const fmtDate = (v) => v ? new Date(v).toLocaleString('cs-CZ', { dateStyle: 'medium', timeStyle: 'short' }) : '—'

export default function TrasyJizdaCesta({ trip, currentId, onOpen }) {
  if (!trip || trip.rides.length < 2) return null
  const t = tripTotals(trip)
  const why = trip.explicit
    ? 'Jízdy sloučil zákazník v appce do jedné cesty.'
    : 'Jízdy téže výpůjčky — appka je ukazuje jako jednu cestu (starší záznam výpůjčku přes noc rozděloval).'

  return (
    <div className="rounded-card" style={{ background: '#f5f8ff', border: '1px solid #c7d6ee', padding: '10px 12px' }}>
      <h4 className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>
        🧳 Součást cesty „{trip.name}“
      </h4>
      <p className="text-xs mt-1" style={{ color: '#4a6357' }}>
        {why} Celkem {cz(t.count, 'jízda', 'jízdy', 'jízd')} · {t.km.toFixed(1)} km
        · {fmtLongSec(t.moving)} v sedle · {cz(t.days, 'den', 'dny', 'dní')} · {tripDates(trip.rides)}
      </p>
      <div className="flex flex-col gap-1 mt-2">
        {trip.rides.map((r, i) => {
          const me = r.id === currentId
          return (
            <div key={r.id} className="flex items-center gap-2 flex-wrap text-xs"
              style={{ color: '#1a2e22', fontWeight: me ? 800 : 600 }}>
              <span className="tabular-nums" style={{ color: '#6b8f7b', minWidth: 18 }}>{i + 1}.</span>
              <span className="truncate" style={{ maxWidth: 260 }}>{r.name || 'Projetá jízda'}</span>
              <span style={{ color: '#6b8f7b' }}>{fmtDate(r.started_at)} · {Number(r.distance_km || 0).toFixed(1)} km</span>
              {r.is_recording && <span style={{ color: '#15803d' }}>● nahrává se</span>}
              {me ? (
                <span className="rounded-btn" style={{ padding: '1px 6px', background: '#e0e9f8', color: '#33507a' }}>právě otevřená</span>
              ) : onOpen && (
                <button onClick={() => onOpen(r)}
                  className="rounded-btn cursor-pointer font-extrabold max-lg:min-h-[36px]"
                  style={{ padding: '2px 8px', border: 'none', background: '#e8ffe8', color: '#1a8a18' }}>
                  Otevřít
                </button>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
