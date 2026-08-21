const inputStyle = { padding: '6px 8px', background: '#fff', border: '1px solid #d4e8e0' }

// Sdílený volič výše vratky (storno modal + potvrzení vrácení u zrušené
// rezervace): rychlé volby 100/50/0 % + ručně editovatelná procenta i částka
// v Kč, obousměrně provázané. Rodič drží stav { pct, amount } (stringy) a
// dostává ho přes onChange; clamp 0..total.
export default function RefundAmountPicker({ total, pct, amount, onChange }) {
  const amountNum = Math.round(Number(amount))
  const applyPct = (p) => {
    const pc = Math.min(100, Math.max(0, Math.round(Number(p) || 0)))
    onChange({ pct: String(pc), amount: String(Math.round(total * pc / 100)) })
  }
  const applyAmount = (a) => {
    const an = Number(a)
    onChange({
      pct: total > 0 && Number.isFinite(an) ? String(Math.round(Math.min(100, Math.max(0, an / total * 100)))) : pct,
      amount: a,
    })
  }
  return (
    <>
      <div className="flex gap-2 mb-2">
        {[100, 50, 0].map(p => (
          <button key={p} type="button" onClick={() => applyPct(p)}
            className="rounded-btn text-sm font-extrabold cursor-pointer"
            style={{ padding: '6px 14px', border: '1px solid #d4e8e0', background: Number(pct) === p && amountNum === Math.round(total * p / 100) ? '#74FB71' : '#fff', color: '#1a2e22' }}>
            {p} %
          </button>
        ))}
      </div>
      <div className="flex items-center gap-3">
        <label className="flex items-center gap-1 text-sm" style={{ color: '#1a2e22' }}>
          <input type="number" min="0" max="100" step="1" value={pct} onChange={e => applyPct(e.target.value)}
            className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 70 }} />
          %
        </label>
        <label className="flex items-center gap-1 text-sm" style={{ color: '#1a2e22' }}>
          <input type="number" min="0" max={total} step="1" value={amount} onChange={e => applyAmount(e.target.value)}
            className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 110 }} />
          Kč
        </label>
      </div>
    </>
  )
}

// Validace zadané částky vůči celkové ceně (sdílí obě modální okna).
export function refundAmountValid(amount, total) {
  const n = Math.round(Number(amount))
  return Number.isFinite(n) && n >= 0 && n <= total
}
