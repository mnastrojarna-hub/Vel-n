import { useState } from 'react'

export default function PartsPanel({ parts, inventoryItems, scheduleId, onAdd, onRemove, onUpdateQty }) {
  const [adding, setAdding] = useState(false)
  const [selItem, setSelItem] = useState('')
  const [selQty, setSelQty] = useState(1)
  const usedIds = new Set(parts.map(p => p.inventory_item_id))
  const available = inventoryItems.filter(i => !usedIds.has(i.id))

  return (
    <div className="ml-4 mr-2 mb-2 p-3 rounded-lg" style={{ background: '#eff6ff', border: '1px solid #bfdbfe', fontSize: 12 }}>
      <div className="font-bold text-xs uppercase tracking-wide mb-2" style={{ color: '#2563eb' }}>Dily pro tento servis</div>
      {parts.length === 0 && !adding && (
        <p style={{ color: '#6b7280', fontSize: 12 }}>Zadne dily — kliknete + Pridat dil</p>
      )}
      {parts.map(p => (
        <div key={p.id} className="flex items-center gap-2 mb-1 p-2 rounded" style={{ background: '#fff' }}>
          <span className="flex-1 font-bold">{p.inventory?.name || '\u2014'}</span>
          <span className="font-mono" style={{ color: '#6b7280' }}>{p.inventory?.sku || ''}</span>
          <span style={{ color: (p.inventory?.stock || 0) < p.quantity ? '#dc2626' : '#1a8a18', fontWeight: 700 }}>
            sklad: {p.inventory?.stock ?? '?'}
          </span>
          <span style={{ color: '#1a2e22' }}>{'\u00d7'}</span>
          <input type="number" min={1} value={p.quantity}
            onChange={e => onUpdateQty(p.id, e.target.value)}
            className="rounded text-xs text-center outline-none" style={{ width: 40, padding: '2px 4px', border: '1px solid #d1d5db' }} />
          <button onClick={() => onRemove(p.id, scheduleId)} className="text-xs font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none' }}>{'\u00d7'}</button>
        </div>
      ))}
      {adding ? (
        <div className="flex items-center gap-2 mt-2">
          <select value={selItem} onChange={e => setSelItem(e.target.value)}
            className="rounded text-xs outline-none flex-1" style={{ padding: '4px 6px', border: '1px solid #d1d5db', background: '#fff' }}>
            <option value="">— Vyberte dil —</option>
            {available.map(i => (
              <option key={i.id} value={i.id}>{i.name} ({i.sku || '\u2014'}) — sklad: {i.stock}</option>
            ))}
          </select>
          <input type="number" min={1} value={selQty} onChange={e => setSelQty(e.target.value)}
            className="rounded text-xs text-center outline-none" style={{ width: 40, padding: '4px', border: '1px solid #d1d5db' }} />
          <button onClick={() => { if (selItem) { onAdd(scheduleId, selItem, selQty); setAdding(false); setSelItem(''); setSelQty(1) } }}
            disabled={!selItem} className="text-xs font-bold cursor-pointer" style={{ color: '#1a8a18', background: 'none', border: 'none' }}>Pridat</button>
          <button onClick={() => setAdding(false)} className="text-xs cursor-pointer" style={{ color: '#6b7280', background: 'none', border: 'none' }}>Zrusit</button>
        </div>
      ) : (
        <button onClick={() => setAdding(true)} className="text-xs font-bold cursor-pointer mt-1" style={{ color: '#2563eb', background: 'none', border: 'none' }}>+ Pridat dil</button>
      )}
    </div>
  )
}
