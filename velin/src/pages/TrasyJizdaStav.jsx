import { SmallBtn } from './BranchHelpers'
import { fmtSince, rideAutoCloseHint, rideAwait, rideAwaitLabel, rideUnder1Km } from '../lib/rideStats'

// Stav běžící nahrávky v detailu jízdy + dlaždice statistik.
//   standing = nahrává se, ale 15+ min bez bodu: nová appka při stání
//              (oběd, noc) nic neposílá — to je v pořádku, ne závada;
//   awaiting = jízda pod 1 km, kterou server drží otevřenou kvůli bodům
//              z telefonu bez internetu (vrácená výpůjčka 7 dní po vrácení,
//              vlastní cesta nové appky 30 dní od startu) — nevisí;
//   stuck    = bez bodu déle, než by to dávalo smysl (3 h stará appka,
//              24 h stará appka na výpůjčce, 72 h vlastní cesta nové appky;
//              výpůjčka nové appky jen po skončení rezervace, bez jejího
//              stavu až po 7 dnech) — „visí".
// „Ukončit záznam" zůstává u všech; jízdu pod 1 km uzavření SMAŽE (i s daty,
// která telefon ještě pošle) — proto se před ním vždy ptá (`confirmRideEnd`).

const fmtDate = (v) => v ? new Date(v).toLocaleString('cs-CZ', { dateStyle: 'medium', timeStyle: 'short' }) : '—'

/** Potvrzení „Ukončit záznam" (Velín, admin_finish_user_ride). true = ukončit. */
export function confirmRideEnd(ride, state) {
  if (state === 'awaiting') {
    return window.confirm('Záznam čeká na data z telefonu, který byl bez internetu. Když ho ukončíte teď, '
      + 'jízda pod 1 km se smaže a data, která telefon ještě pošle, se už neuloží. '
      + 'Server ho uzavře sám, až čekání vyprší — nic dělat nemusíte.\n\nOpravdu ukončit a smazat?')
  }
  if (rideUnder1Km(ride)) {
    return window.confirm('Ukončit záznam teď? Jízda má zatím pod 1 km, takže se uzavřením smaže '
      + '(parkování se do deníku neukládá) a data, která telefon případně ještě pošle, se už neuloží.')
  }
  if (state === 'standing') {
    return window.confirm('Ukončit záznam teď? Jízda se uloží s tím, co je nahrané. '
      + 'Když zákazník znovu vyjede, appka založí novou jízdu'
      + (ride.booking_id ? ' (u výpůjčky ji ukáže ve stejné cestě).' : '.'))
  }
  return true
}

/** Box „Čeká na data z telefonu" (detail jízdy i Mapa a poloha). */
export function RideAwaitBox({ ride, booking = null, closing, onEnd }) {
  const aw = rideAwait(ride, booking)
  const km = Number(ride.distance_km || 0).toFixed(1)
  const last = ride.last_fix_at || ride.updated_at
  return (
    <div className="rounded-card max-lg:[&>button]:min-h-[40px]" style={{
      background: '#fffbeb', border: '1px solid #fde68a', padding: '10px 12px',
    }}>
      <p className="text-xs mb-2" style={{ color: '#92400e' }}>
        <b>Čeká na data z telefonu.</b> {aw?.kind === 'rental' ? 'Motorka je vrácená, ale na serveru' : 'Na serveru'} má
        jízda zatím jen {km} km ({last ? `poslední bod ${fmtDate(last)}` : 'zatím bez GPS bodu'}) — telefon byl nejspíš
        bez internetu a body pošle, až se připojí. Server záznam drží {aw ? rideAwaitLabel(aw) : 'ještě pár dní'} a
        pak ho sám uzavře, nic dělat nemusíte. Ukončení teď by jízdu pod 1 km smazalo i s daty, která telefon ještě pošle.
      </p>
      <SmallBtn color="#92400e" onClick={() => confirmRideEnd(ride, 'awaiting') && onEnd()} disabled={closing}>
        {closing ? 'Ukončuji…' : 'Ukončit záznam (smaže jízdu)'}
      </SmallBtn>
    </div>
  )
}

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

/** `rental` = rentalHoldsRide(rezervace), `booking` = rezervace (vrácení) — když je známe. */
export default function TrasyJizdaStav({ ride, state, closing, onEnd, rental = null, booking = null }) {
  if (state === 'awaiting') return <RideAwaitBox ride={ride} booking={booking} closing={closing} onEnd={onEnd} />
  if (state !== 'standing' && state !== 'stuck') return null
  const hint = rideAutoCloseHint(ride, rental, booking)
  const since = ride.last_fix_at || ride.updated_at
  const end = () => { if (confirmRideEnd(ride, state)) onEnd() }

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
        <SmallBtn color="#dc2626" onClick={end} disabled={closing}>{closing ? 'Ukončuji…' : 'Ukončit záznam'}</SmallBtn>
      </div>
    )
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
      <SmallBtn color="#475569" onClick={end} disabled={closing}>{closing ? 'Ukončuji…' : 'Ukončit záznam'}</SmallBtn>
    </div>
  )
}
