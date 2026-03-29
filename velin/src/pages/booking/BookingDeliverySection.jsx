export default function BookingDeliverySection({
  pickupMethod, setPickupMethod, pickupAddress, setPickupAddress,
  returnMethod, setReturnMethod, returnAddress, setReturnAddress,
  deliveryFee, setDeliveryFee, setShowMapPicker,
}) {
  return (
    <div className="mb-5">
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Pristaveni a vraceni</h3>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Vyzvednuti</label>
          <select value={pickupMethod} onChange={e => setPickupMethod(e.target.value)} className="w-full text-sm font-bold cursor-pointer" style={{ padding: '7px 10px', borderRadius: 8, border: '1px solid #d4e8e0', background: '#f1faf7', color: '#1a2e22' }}>
            <option value="on_branch">Na pobocce</option><option value="delivery">Pristaveni na adresu</option>
          </select>
          {pickupMethod === 'delivery' && (<>
            <input value={pickupAddress} onChange={e => setPickupAddress(e.target.value)} placeholder="Obec, ulice a c.p. / c.o." className="w-full mt-2 text-sm rounded-btn outline-none" style={{ padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
            <button type="button" onClick={() => setShowMapPicker('pickup')} className="mt-1 text-xs font-bold cursor-pointer" style={{ padding: '4px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 6, color: '#1a2e22' }}>{'\ud83d\uddfa\ufe0f'} Vybrat na mape</button>
          </>)}
          {pickupMethod === 'on_branch' && pickupAddress && <div className="mt-1 text-xs" style={{ color: '#6b7280' }}>Puvodni adresa: {pickupAddress}</div>}
        </div>
        <div>
          <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Vraceni</label>
          <select value={returnMethod} onChange={e => setReturnMethod(e.target.value)} className="w-full text-sm font-bold cursor-pointer" style={{ padding: '7px 10px', borderRadius: 8, border: '1px solid #d4e8e0', background: '#f1faf7', color: '#1a2e22' }}>
            <option value="on_branch">Na pobocce</option><option value="delivery">Svoz z adresy</option>
          </select>
          {returnMethod === 'delivery' && (<>
            <input value={returnAddress} onChange={e => setReturnAddress(e.target.value)} placeholder="Obec, ulice a c.p. / c.o." className="w-full mt-2 text-sm rounded-btn outline-none" style={{ padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
            <button type="button" onClick={() => setShowMapPicker('return')} className="mt-1 text-xs font-bold cursor-pointer" style={{ padding: '4px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 6, color: '#1a2e22' }}>{'\ud83d\uddfa\ufe0f'} Vybrat na mape</button>
          </>)}
          {returnMethod === 'on_branch' && returnAddress && <div className="mt-1 text-xs" style={{ color: '#6b7280' }}>Puvodni adresa: {returnAddress}</div>}
        </div>
      </div>
      {(pickupMethod === 'delivery' || returnMethod === 'delivery') && (
        <div className="mt-3">
          <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Poplatek za doruceni (Kc)</label>
          <input type="number" value={deliveryFee} onChange={e => setDeliveryFee(Number(e.target.value) || 0)} className="text-sm rounded-btn outline-none" style={{ padding: '7px 10px', width: 140, background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>
      )}
    </div>
  )
}
