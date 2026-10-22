import { useState } from 'react'
import { quote, itemsSum, czk, daysLabel, INPUT } from './gearShared'

// Živý příklad výpočtu podle aktuálního ceníku: pro každý aktivní komplet
// „zákazník vybere všechny jeho kusy na N dní“ → kolik zaplatí (stejné pravidlo jako DB).
export default function GearExample({ prices }) {
  const [days, setDays] = useState(3)
  const n = Math.min(366, Math.max(1, parseInt(days, 10) || 1))
  const sets = prices.filter(p => p.kind === 'set' && p.is_active)
  const activeItems = prices.filter(p => p.kind === 'item' && p.is_active)

  return (
    <div className="rounded-lg text-sm" style={{ padding: '10px 12px', background: '#f1faf7', color: '#1a2e22' }}>
      <div className="flex flex-wrap items-center gap-2 mb-2">
        <strong>Příklad výpočtu</strong>
        <span>na</span>
        <input type="number" min="1" max="366" value={days} onChange={e => setDays(e.target.value)}
          style={{ ...INPUT, width: 70, padding: '3px 8px', background: '#fff' }} className="max-lg:min-h-[36px]" />
        <span>{daysLabel(n)}:</span>
      </div>
      {sets.length === 0 && activeItems.length === 0 && <div>Ceník je prázdný.</div>}
      <ul className="space-y-1" style={{ margin: 0, paddingLeft: 18 }}>
        {sets.map(s => {
          const keys = (s.includes || []).filter(k => activeItems.some(i => i.key === k))
          const complete = keys.length === (s.includes || []).length
          const q = quote(prices, keys)
          const sum = itemsSum(prices, s.includes)
          const applied = q.lines.some(l => l.key === s.key)
          return (
            <li key={s.key}>
              <strong>{s.label}</strong>
              {!complete
                ? <span style={{ color: '#b45309' }}> — obsahuje neaktivní nebo smazaný kus, na webu ho nejde složit</span>
                : <>
                    {' '}{n} {daysLabel(n)} = <strong>{czk(q.perDay * n)}</strong>
                    {applied
                      ? <span style={{ color: '#1a8a18' }}> (kusy zvlášť by stály {czk(sum * n)})</span>
                      : <span style={{ color: '#b45309' }}> — tento komplet se neuplatní, není levnější než jeho kusy ({czk(sum)} / den)</span>}
                  </>}
            </li>
          )
        })}
        {activeItems.slice(0, 1).map(i => (
          <li key={i.key}>Jen {String(i.label).toLowerCase()} {n} {daysLabel(n)} = <strong>{czk(Number(i.price_per_day) * n)}</strong></li>
        ))}
      </ul>
      <p className="text-xs mt-2" style={{ color: '#6b7a72' }}>
        Ceny jsou <strong>za den</strong> (cena × počet dní, od–do včetně). Komplet se použije jen tehdy, když zákazník vybere
        <strong> všechny</strong> jeho kusy a komplet je <strong>levnější</strong> než součet těchto kusů; jinak se účtuje po kusech.
      </p>
    </div>
  )
}
