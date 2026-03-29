import { fmtCZK } from './bookingModifyHelpers'

export default function BookingPriceCalc({
  newBreakdown, selectedMoto, booking, origCalcPrice, origPaidPrice,
  origDays, newCalcPrice, newDeliveryFee, newTotalPrice, priceDiff,
  days, chargeCustomer, setChargeCustomer,
}) {
  return (
    <div className="mb-5">
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Kalkulace ceny</h3>
      {newBreakdown.length > 0 && (
        <div className="mb-3 p-3 rounded-lg" style={{ background: '#f8faf9', border: '1px solid #e5e7eb' }}>
          <div className="text-xs font-bold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Rozpad po dnech {'\u2014'} {selectedMoto?.model || booking.motorcycles?.model}</div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(130px, 1fr))', gap: 4 }}>
            {newBreakdown.map((d, i) => (
              <div key={i} className="flex items-center justify-between text-xs px-2 py-1 rounded" style={{ background: d.dow === 0 || d.dow === 6 ? '#fef3c7' : '#fff', border: '1px solid #f3f4f6' }}>
                <span style={{ color: '#1a2e22' }}>{d.dowLabel} {d.date.getDate()}.{d.date.getMonth() + 1}.</span>
                <span className="font-extrabold" style={{ color: '#0f1a14' }}>{fmtCZK(d.price)} Kc</span>
              </div>
            ))}
          </div>
        </div>
      )}
      <div className="p-4 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <div className="space-y-2">
          <div className="flex justify-between text-sm"><span style={{ color: '#1a2e22' }}>Puvodni cena (zaplaceno)</span><span className="font-bold" style={{ color: '#0f1a14' }}>{fmtCZK(origPaidPrice)} Kc</span></div>
          {origCalcPrice > 0 && origCalcPrice !== origPaidPrice && <div className="flex justify-between text-xs"><span style={{ color: '#9ca3af' }}>Dle ceniku (puvodni motorka x {origDays}d)</span><span style={{ color: '#9ca3af' }}>{fmtCZK(origCalcPrice)} Kc</span></div>}
          <div className="flex justify-between text-sm"><span style={{ color: '#1a2e22' }}>Nova cena dle ceniku ({days}d)</span><span className="font-bold" style={{ color: '#0f1a14' }}>{fmtCZK(newCalcPrice)} Kc</span></div>
          {newDeliveryFee > 0 && <div className="flex justify-between text-sm"><span style={{ color: '#1a2e22' }}>Doruceni</span><span className="font-bold">{fmtCZK(newDeliveryFee)} Kc</span></div>}
          <div style={{ borderTop: '2px solid #d4e8e0', paddingTop: 8, marginTop: 4 }}><div className="flex justify-between text-sm font-extrabold"><span style={{ color: '#1a2e22' }}>Nova celkova cena</span><span style={{ color: '#0f1a14' }}>{fmtCZK(newTotalPrice)} Kc</span></div></div>
          {priceDiff !== 0 && (
            <div className="flex justify-between text-sm font-extrabold mt-1 p-2 rounded" style={{ background: priceDiff > 0 ? '#fee2e2' : '#dcfce7', border: `1px solid ${priceDiff > 0 ? '#fca5a5' : '#86efac'}` }}>
              <span style={{ color: priceDiff > 0 ? '#dc2626' : '#1a8a18' }}>{priceDiff > 0 ? 'Doplatek' : 'Preplatek'}</span>
              <span style={{ color: priceDiff > 0 ? '#dc2626' : '#1a8a18' }}>{priceDiff > 0 ? '+' : ''}{fmtCZK(priceDiff)} Kc</span>
            </div>
          )}
        </div>
        {priceDiff !== 0 && (
          <div className="mt-4 space-y-2">
            <div className="text-xs font-bold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Reseni cenoveho rozdilu</div>
            <label className="flex items-center gap-2 cursor-pointer p-2 rounded-lg" style={{ background: chargeCustomer ? '#eafbe9' : '#fff', border: `1px solid ${chargeCustomer ? '#74FB71' : '#e5e7eb'}` }}>
              <input type="radio" checked={chargeCustomer} onChange={() => setChargeCustomer(true)} style={{ accentColor: '#1a8a18' }} />
              <div>
                <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{priceDiff > 0 ? `Zakaznik doplati (+${fmtCZK(priceDiff)} Kc)` : `Vratit zakaznikovi (${fmtCZK(Math.abs(priceDiff))} Kc)`}</div>
                <div className="text-xs" style={{ color: '#1a2e22' }}>Celkem bude {fmtCZK(newTotalPrice)} Kc</div>
              </div>
            </label>
            <label className="flex items-center gap-2 cursor-pointer p-2 rounded-lg" style={{ background: !chargeCustomer ? '#eafbe9' : '#fff', border: `1px solid ${!chargeCustomer ? '#74FB71' : '#e5e7eb'}` }}>
              <input type="radio" checked={!chargeCustomer} onChange={() => setChargeCustomer(false)} style={{ accentColor: '#1a8a18' }} />
              <div>
                <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>Zdarma (bez doplatku)</div>
                <div className="text-xs" style={{ color: '#1a2e22' }}>Cena zustane {fmtCZK(origPaidPrice)} Kc</div>
              </div>
            </label>
          </div>
        )}
      </div>
    </div>
  )
}
