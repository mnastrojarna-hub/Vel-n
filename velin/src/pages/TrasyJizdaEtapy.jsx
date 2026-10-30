import { normStages, fmtLongSec } from '../lib/rideStats'

// Etapy (dny) jedné vícedenní jízdy — počítá je server (`user_rides.stages`):
// nová etapa začíná po pauze ≥ 6 h nebo po pauze ≥ 30 min přes noc
// (00:00–05:00 Praha). Stejné řádky ukazuje appka v detailu jízdy.
// Jednodenní jízda (jedna etapa) tabulku nemá — vše je v dlaždicích nahoře.

const fmtDay = (ts) => new Date(ts * 1000).toLocaleDateString('cs-CZ',
  { weekday: 'short', day: 'numeric', month: 'numeric', timeZone: 'Europe/Prague' })
const fmtTime = (ts) => new Date(ts * 1000).toLocaleTimeString('cs-CZ',
  { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Prague' })
const dash = (v, f) => (v == null || v <= 0 ? '—' : f(v))

export default function TrasyJizdaEtapy({ stages }) {
  const rows = normStages(stages)
  if (rows.length < 2) return null
  const anyGap = rows.some(s => s.gap > 0)
  const th = 'text-left font-extrabold px-2 py-1 whitespace-nowrap'
  const td = 'px-2 py-1 whitespace-nowrap tabular-nums'

  return (
    <div className="rounded-card" style={{ background: '#f8fafc', border: '1px solid #d4e8e0', padding: '8px 12px' }}>
      <h4 className="font-extrabold text-sm mb-1" style={{ color: '#0f1a14' }}>
        📅 Etapy ({rows.length})
      </h4>
      <p className="text-xs mb-2" style={{ color: '#6b8f7b' }}>
        Jedna jízda přes víc dní — den končí noční nebo dlouhou pauzou. Noci se nepočítají do času na cestě.
      </p>
      <div className="overflow-x-auto">
        <table className="text-xs w-full" style={{ color: '#1a2e22', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ color: '#6b8f7b', borderBottom: '1px solid #d4e8e0' }}>
              <th className={th}>Den</th>
              <th className={th}>Kdy</th>
              <th className={th}>Ujeto</th>
              <th className={th} title="Čas, kdy se motorka pohybovala">V sedle</th>
              <th className={th}>Ø</th>
              <th className={th}>Max</th>
              <th className={th} title="Nastoupáno">⛰️</th>
              <th className={th} title="Krátká stání během dne (zbytek času)">Zastávky</th>
              <th className={th} title="Delší přestávky uvnitř dne (oběd…)">Pauzy</th>
              {anyGap && <th className={th} title="Projeto bez GPS bodů — do km se nepočítá">Bez signálu</th>}
            </tr>
          </thead>
          <tbody>
            {rows.map((s, i) => (
              <tr key={i} style={{ borderBottom: i < rows.length - 1 ? '1px solid #e8f2ee' : 'none' }}>
                <td className={`${td} font-extrabold`}>Den {i + 1}</td>
                <td className={td}>
                  {fmtDay(s.from)} {fmtTime(s.from)}–{fmtDay(s.to) !== fmtDay(s.from) ? `${fmtDay(s.to)} ` : ''}{fmtTime(s.to)}
                </td>
                <td className={`${td} font-extrabold`}>{s.km.toFixed(1)} km</td>
                <td className={td}>{dash(s.mv, fmtLongSec)}</td>
                <td className={td}>{s.avg == null ? '—' : `${Math.round(s.avg)} km/h`}</td>
                <td className={td}>{s.max == null ? '—' : `${Math.round(s.max)} km/h`}</td>
                <td className={td}>{dash(s.gain, v => `${Math.round(v)} m`)}</td>
                <td className={td}>{s.idle >= 60 ? fmtLongSec(s.idle) : '—'}</td>
                <td className={td}>{s.ps >= 60 ? fmtLongSec(s.ps) : '—'}</td>
                {anyGap && <td className={td}>{s.gap >= 60 ? fmtLongSec(s.gap) : '—'}</td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
