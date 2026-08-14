import { isRealizedBooking } from '../../lib/revenueUtils'

const DAYS_CS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']

// Den v týdnu z data výjezdu (start_date) bez posunů časovou zónou —
// parsuje se jen datumová část, ne ISO timestamp (ten by se bral jako UTC).
function weekdayIndex(dateStr) {
  if (!dateStr) return null
  const [y, m, d] = String(dateStr).split('T')[0].split('-').map(Number)
  if (!y || !m || !d) return null
  const day = new Date(y, m - 1, d).getDay() // 0 = neděle
  return (day + 6) % 7 // 0 = pondělí
}

// Buňka heatmapy — sytost zelené dle podílu na maximu řádku.
function HeatCell({ count, rowMax, total, bold }) {
  const ratio = rowMax > 0 ? count / rowMax : 0
  const pct = total > 0 ? (count / total) * 100 : 0
  return (
    <td className="py-2 px-3 text-center" style={{ background: count > 0 ? `rgba(116,251,113,${(0.12 + ratio * 0.55).toFixed(2)})` : 'transparent' }}>
      <div style={{ fontWeight: bold || ratio === 1 ? 800 : 600, color: '#1a2e22' }}>{count}</div>
      <div style={{ fontSize: 10, color: '#5b6b62' }}>{count > 0 ? `${pct.toFixed(0)} %` : '—'}</div>
    </td>
  )
}

/**
 * Počet rezervací (výjezdů) dle dne v týdnu za CELOU dobu fungování —
 * záměrně nezávisle na zvoleném období, aby vzorec dnů nebyl zkreslený
 * krátkým výsekem. Den = start_date rezervace (den, kdy motorka vyjíždí).
 * Řádky: kategorie motorek + souhrn napříč všemi stroji.
 */
export default function RezervaceDnyTydne({ bookings, motorcycles }) {
  const categoryByMoto = Object.fromEntries((motorcycles || []).map(m => [m.id, m.category || 'Bez kategorie']))

  const rowsMap = {}
  const totalRow = { label: 'Všechny stroje', days: Array(7).fill(0), total: 0 }
  for (const b of (bookings || []).filter(isRealizedBooking)) {
    const idx = weekdayIndex(b.start_date)
    if (idx === null) continue
    const cat = categoryByMoto[b.moto_id] || 'Bez kategorie'
    if (!rowsMap[cat]) rowsMap[cat] = { label: cat, days: Array(7).fill(0), total: 0 }
    rowsMap[cat].days[idx]++
    rowsMap[cat].total++
    totalRow.days[idx]++
    totalRow.total++
  }
  const catRows = Object.values(rowsMap).sort((a, b) => b.total - a.total)

  if (totalRow.total === 0) return null

  const topIdx = totalRow.days.indexOf(Math.max(...totalRow.days))

  return (
    <div style={{ background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, overflowX: 'auto', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
      <div className="font-bold" style={{ color: '#1a2e22' }}>Výjezdy dle dne v týdnu</div>
      <div className="mb-3" style={{ fontSize: 11, color: '#888' }}>
        Počet zaplacených rezervací podle dne, kdy motorka vyjíždí (start rezervace) — za celou dobu fungování, nezávisle na zvoleném období.
        Nejčastější den výjezdu celkem: <strong style={{ color: '#1a2e22' }}>{['Pondělí', 'Úterý', 'Středa', 'Čtvrtek', 'Pátek', 'Sobota', 'Neděle'][topIdx]}</strong>.
      </div>
      <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
        <thead>
          <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
            <th className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>Kategorie</th>
            {DAYS_CS.map(d => <th key={d} className="text-center font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{d}</th>)}
            <th className="text-center font-bold py-2 px-3" style={{ color: '#1a2e22' }}>Celkem</th>
          </tr>
        </thead>
        <tbody>
          {catRows.map(r => {
            const rowMax = Math.max(...r.days)
            return (
              <tr key={r.label} style={{ borderBottom: '1px solid #f3f4f6' }}>
                <td className="py-2 px-3 font-semibold">{r.label}</td>
                {r.days.map((c, i) => <HeatCell key={i} count={c} rowMax={rowMax} total={r.total} />)}
                <td className="py-2 px-3 text-center font-bold">{r.total}</td>
              </tr>
            )
          })}
          <tr style={{ borderTop: '2px solid #e5e7eb', background: '#f9fdfb' }}>
            <td className="py-2 px-3 font-extrabold">{totalRow.label}</td>
            {totalRow.days.map((c, i) => <HeatCell key={i} count={c} rowMax={Math.max(...totalRow.days)} total={totalRow.total} bold />)}
            <td className="py-2 px-3 text-center font-extrabold">{totalRow.total}</td>
          </tr>
        </tbody>
      </table>
    </div>
  )
}
