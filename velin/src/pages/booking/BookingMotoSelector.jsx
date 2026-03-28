export default function BookingMotoSelector({
  changingMoto, setChangingMoto, branchFilter, setBranchFilter, branches,
  availableMotos, unavailableMotos, loadingMotos, selectedMotoId, setSelectedMotoId,
  booking, motoChanged, selectedMoto, calcMotoPrice, newDeliveryFee, origPaidPrice, fmtCZK,
}) {
  return (
    <div className="mb-5">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Motorka</h3>
        <button onClick={() => setChangingMoto(!changingMoto)}
          className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}>
          {changingMoto ? 'Skryt vyber' : 'Zmenit motorku'}
        </button>
      </div>

      <div className="p-3 rounded-lg" style={{ background: motoChanged ? '#dbeafe' : '#f1faf7', border: `1px solid ${motoChanged ? '#93c5fd' : '#d4e8e0'}` }}>
        <div className="flex items-center gap-3">
          <div className="flex-1">
            <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>
              {selectedMoto?.model || booking.motorcycles?.model || '\u2014'}
            </div>
            <div className="text-xs" style={{ color: '#1a2e22' }}>
              {selectedMoto?.spz || booking.motorcycles?.spz || '\u2014'} \u00b7 {selectedMoto?.category || '\u2014'}
            </div>
          </div>
          {motoChanged && (
            <div className="text-right">
              <div className="text-xs" style={{ color: '#9ca3af' }}>bylo: {booking.motorcycles?.model}</div>
              <button onClick={() => { setSelectedMotoId(booking.moto_id); setChangingMoto(false) }}
                className="text-xs font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none', padding: 0 }}>
                Vratit puvodni
              </button>
            </div>
          )}
        </div>
      </div>

      {changingMoto && (
        <div className="mt-3">
          <div className="flex items-center gap-3 mb-2">
            <select value={branchFilter} onChange={e => setBranchFilter(e.target.value)}
              className="text-sm font-bold cursor-pointer" style={{ padding: '4px 8px', borderRadius: 8, border: '1px solid #d4e8e0', background: '#f1faf7', color: '#1a2e22' }}>
              <option value="">Vsechny pobocky</option>
              {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
            <span className="text-xs font-bold" style={{ color: '#1a8a18' }}>{availableMotos.length} volnych</span>
          </div>
          {loadingMotos ? (
            <div className="py-4 text-center"><div className="animate-spin inline-block rounded-full h-5 w-5 border-t-2 border-brand-gd" /></div>
          ) : (
            <div style={{ maxHeight: 260, overflowY: 'auto' }}>
              {availableMotos.map(m => {
                const price = calcMotoPrice(m.id)
                const isSelected = m.id === selectedMotoId
                const isCurrent = m.id === booking.moto_id
                const pDiff = price !== null ? price + newDeliveryFee - origPaidPrice : null
                return (
                  <div key={m.id} onClick={() => setSelectedMotoId(m.id)}
                    className="flex items-center gap-3 p-2 rounded-lg mb-1 cursor-pointer" style={{
                      background: isSelected ? '#eafbe9' : '#f8faf9',
                      border: isSelected ? '2px solid #74FB71' : '1px solid #e5e7eb',
                    }}>
                    {m.image_url ? (
                      <img src={m.image_url} alt={m.model} style={{ width: 56, height: 38, objectFit: 'cover', borderRadius: 6 }} />
                    ) : (
                      <div style={{ width: 56, height: 38, borderRadius: 6, background: '#f1faf7', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18 }}>&#127949;&#65039;</div>
                    )}
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>
                        {m.model} {isCurrent && <span className="text-xs font-bold" style={{ color: '#1a8a18' }}>(aktualni)</span>}
                      </div>
                      <div className="text-xs" style={{ color: '#1a2e22' }}>{m.spz || '\u2014'} \u00b7 {m.category || '\u2014'}</div>
                    </div>
                    <div className="text-right">
                      <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{price !== null ? fmtCZK(price) + ' Kc' : '\u2014'}</div>
                      {pDiff !== null && pDiff !== 0 && (
                        <div className="text-xs font-bold" style={{ color: pDiff > 0 ? '#dc2626' : '#1a8a18' }}>
                          {pDiff > 0 ? '+' : ''}{fmtCZK(pDiff)} Kc
                        </div>
                      )}
                    </div>
                    {isSelected && <span style={{ color: '#1a8a18', fontWeight: 800 }}>{'\u2713'}</span>}
                  </div>
                )
              })}
              {unavailableMotos.length > 0 && (
                <>
                  <div className="text-xs font-bold uppercase tracking-wide mt-3 mb-1" style={{ color: '#dc2626' }}>Obsazene ({unavailableMotos.length})</div>
                  {unavailableMotos.map(m => (
                    <div key={m.id} className="flex items-center gap-3 p-2 rounded-lg mb-1" style={{ background: '#fafafa', border: '1px solid #f3f4f6', opacity: 0.4 }}>
                      <div style={{ width: 56, height: 38, borderRadius: 6, background: '#f3f4f6', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18 }}>&#127949;&#65039;</div>
                      <div className="flex-1"><div className="text-sm font-bold" style={{ color: '#1a2e22' }}>{m.model}</div><div className="text-xs" style={{ color: '#1a2e22' }}>{m.spz || '\u2014'} \u00b7 Obsazena</div></div>
                    </div>
                  ))}
                </>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
