import { SmallBtn } from './BranchHelpers'
import { fmtSince, rideAutoCloseHint } from '../lib/rideStats'

// Stav běžící nahrávky v detailu jízdy + dlaždice statistik.
//   standing = nahrává se, ale 15+ min bez bodu: nová appka při stání
//              (oběd, noc) nic neposílá — to je v pořádku, ne závada;
//   stuck    = bez bodu déle, než by to dávalo smysl (3 h stará appka,
//              24 h stará appka na výpůjčce, 72 h nová appka) — „visí".
// „Ukončit záznam" zůstává u obou (stejná cesta jako appka i cron).

const fmtDate = (v) => v ? new Date(v).toLocaleString('cs-CZ', { dateStyle: 'medium', timeStyle: 'short' }) : '—'

/** Mřížka dlaždic `[emoji, popisek, hodnota, vysvětlení]`. */
export function RideStatTiles({ cells, className = '' }) {
  return (
    <div className={`grid gap-2 ${className}`} style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))' }}>
      {cells.map(([emoji, label, value, title]) => (
        <div key={label} className="rounded-card" title={title || undefined}
          style={{ background: '#f1faf7', border: '1px solid #d4e8e0', padding: '8px 10px' }}>
          <div className="text-[10px] font-extrabold uppercase max-lg:text-[11px]" style={{ color: '#6b8f7b' }}>
            {emoji} {label}
          </div>
          <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{value}</div>
        </div>
      ))}
    </div>
  )
}

export default function TrasyJizdaStav({ ride, state, closing, onEnd }) {
  if (state !== 'standing' && state !== 'stuck') return null
  const hint = rideAutoCloseHint(ride)
  const since = ride.last_fix_at || ride.updated_at

  if (state === 'stuck') {
    return (
      <div className="rounded-card max-lg:[&>button]:min-h-[36px]" style={{
        background: '#fef2f2', border: '1px solid #fecaca', padding: '10px 12px',
      }}>
        <p className="text-xs mb-2" style={{ color: '#991b1b' }}>
          <b>Záznam visí.</b> Tváří se jako běžící, ale poslední GPS bod
          dorazil {fmtDate(since)}. Dokud je otevřený, nevznikne zákazníkovi
          žádná další jízda. Server ho uklidí sám {hint} — tímhle to uzavřete hned.
        </p>
        <SmallBtn color="#dc2626" onClick={onEnd} disabled={closing}>{closing ? 'Ukončuji…' : 'Ukončit záznam'}</SmallBtn>
      </div>
    )
  }

  const confirmEnd = () => {
    const ok = window.confirm('Ukončit záznam teď? Jízda se uloží s tím, co je nahrané. '
      + 'Když zákazník znovu vyjede, appka založí novou jízdu'
      + (ride.booking_id ? ' (u výpůjčky ji ukáže ve stejné cestě).' : '.'))
    if (ok) onEnd()
  }
  return (
    <div className="rounded-card max-lg:[&>button]:min-h-[36px]" style={{
      background: '#f1f5f9', border: '1px solid #cbd5e1', padding: '10px 12px',
    }}>
      <p className="text-xs mb-2" style={{ color: '#334155' }}>
        {ride.pause_aware ? (
          <><b>Záznam je pozastavený</b> — motorka stojí od {fmtSince(since)} (appka
            nahrává jen při jízdě, při rozjezdu pokračuje sama). Server ho uzavře sám {hint}.</>
        ) : (
          <><b>Motorka nejspíš stojí</b> — poslední GPS bod dorazil {fmtDate(since)}.
            Starší verze appky při stání body neposílá (případně je telefon bez signálu).
            Server záznam uzavře sám {hint}.</>
        )}
      </p>
      <SmallBtn color="#475569" onClick={confirmEnd} disabled={closing}>{closing ? 'Ukončuji…' : 'Ukončit záznam'}</SmallBtn>
    </div>
  )
}
