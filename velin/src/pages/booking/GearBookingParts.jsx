// Výpůjčka JEN výbavy (booking_kind = 'gear') — sdílené kousky UI rezervací: štítek „JEN VÝBAVA“,
// buňka „Motorka / výbava“ v seznamu (tabulka i karty) a karta „Výbava (bez motorky)“ v detailu.
import Card from '../../components/ui/Card'
import { InfoRow } from './BookingUIHelpers'
import { effBranch } from '../../lib/bookingBranch'
import { GEAR_PILL, gearItems, gearSizeSummary, gearLines, gearLineSizes } from '../../lib/bookingKind'
import { rentalDays } from '../../lib/rentalDays'

const czk = n => `${(Number(n) || 0).toLocaleString('cs-CZ', { maximumFractionDigits: 2 })} Kč`
const daysLbl = n => (n === 1 ? 'den' : n >= 2 && n <= 4 ? 'dny' : 'dní')

/** Štítek „JEN VÝBAVA“ (teal). `fs` = třída velikosti písma jako ostatní štítky řádku. */
export function GearOnlyPill({ fs = 'text-[9px]', className = '' }) {
  return (
    <span className={`${fs} font-extrabold px-1.5 py-0.5 rounded-btn whitespace-nowrap ${className}`}
      title="Výpůjčka jen výbavy bez motorky" style={{ background: GEAR_PILL.bg, color: GEAR_PILL.color }}>
      {GEAR_PILL.label}
    </span>
  )
}

/** Obsah buňky „Motorka / výbava“: štítek + souhrn velikostí. */
export function GearItemCell({ b, fs }) {
  const s = gearSizeSummary(b)
  return (
    <span className="inline-flex items-center gap-1.5 flex-wrap">
      <GearOnlyPill fs={fs} />
      {s && <span className="text-sm" style={{ color: '#1a2e22' }}>{s}</span>}
    </span>
  )
}

/** Karta detailu rezervace místo „Motorka“: pobočka, kusy a velikosti, ceník za den. */
export function GearDetailCard({ booking }) {
  const items = gearItems(booking)
  const lines = gearLines(booking)
  const days = rentalDays(booking.start_date, booking.end_date) || 1
  const br = effBranch(booking)
  return (
    <Card>
      <div className="flex items-center justify-between mb-3 gap-2">
        <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Výbava (bez motorky)</h3>
        <GearOnlyPill fs="text-xs" />
      </div>
      <InfoRow label="Pobočka" value={br?.name ? `${br.name}${br.type ? ` (${br.type})` : ''}` : null} />
      <InfoRow label="Kusy" value={items.length ? items.map(i => `${i.label} ${i.size}`).join(', ') : 'Žádný kus (chyba dat)'} accent={items.length ? undefined : '#dc2626'} />
      {lines.length > 0 && (
        <div className="mt-2 rounded-lg" style={{ background: '#f8faf9', border: '1px solid #e3efe9' }}>
          {lines.map((l, i) => (
            <div key={`${l.key}-${i}`} className="flex items-baseline gap-2 text-sm px-3 py-1.5" style={{ borderBottom: i < lines.length - 1 ? '1px solid #e8f1ec' : 'none' }}>
              <span className="font-bold min-w-0" style={{ color: '#0f1a14' }}>{l.label || l.key}{l.kind === 'set' ? ' (komplet)' : ''}</span>
              <span className="min-w-0" style={{ color: '#4a5a52' }}>{gearLineSizes(l)}</span>
              <span className="ml-auto font-bold whitespace-nowrap" style={{ color: '#0f1a14' }}>{czk(l.price_per_day)}/den</span>
            </div>
          ))}
        </div>
      )}
      <InfoRow label="Cena za den" value={booking.gear_per_day != null ? czk(booking.gear_per_day) : null} />
      <InfoRow label="Výbava celkem" value={booking.gear_per_day != null ? `${czk(Number(booking.gear_per_day) * days)} (${days} ${daysLbl(days)})` : null} />
    </Card>
  )
}
