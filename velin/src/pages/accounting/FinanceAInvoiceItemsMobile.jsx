// Položky nové faktury na telefonu (< 640 px) — místo úzké tabulky karta na položku:
// popis přes celou šířku, pod ním Ks / Cena/ks / Celkem. Stejné handlery jako tabulka
// v InvoiceCreateModal (desktop a tablet tabulku vykreslují beze změny).
const fieldStyle = { padding: '8px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 10, width: '100%', color: '#0f1a14' }
const labelCls = 'block text-[11px] font-extrabold uppercase tracking-wide mb-1'

export default function FinanceAInvoiceItemsMobile({ items, updateItem, removeItem }) {
  return (
    <div className="space-y-2">
      {items.map((it, i) => (
        <div key={i} className="rounded-lg" style={{ border: '1px solid #d4e8e0', padding: 10, background: '#fff' }}>
          <div className="flex items-start gap-2">
            <input value={it.description} onChange={e => updateItem(i, 'description', e.target.value)}
              className="flex-1 min-w-0 text-sm outline-none" style={fieldStyle} placeholder="Popis položky…" />
            {items.length > 1 && (
              <button onClick={() => removeItem(i)} aria-label="Odebrat položku" className="cursor-pointer shrink-0"
                style={{ width: 40, height: 40, borderRadius: 10, background: '#fee2e2', border: 'none', color: '#dc2626', fontSize: 16 }}>✕</button>
            )}
          </div>
          {it.inventory_id && <div style={{ fontSize: 11, color: '#1a8a18', fontWeight: 700, marginTop: 4 }}>● sklad ({it.max_stock} ks)</div>}
          <div className="grid gap-2 mt-2" style={{ gridTemplateColumns: '1fr 1.3fr 1.3fr' }}>
            <div>
              <span className={labelCls} style={{ color: '#4a6357' }}>Ks</span>
              <input type="number" value={it.qty} onChange={e => updateItem(i, 'qty', Number(e.target.value))} min="1"
                className="text-sm text-center outline-none"
                style={{ ...fieldStyle, color: it.inventory_id && it.qty > it.max_stock ? '#dc2626' : fieldStyle.color }} />
            </div>
            <div>
              <span className={labelCls} style={{ color: '#4a6357' }}>Cena/ks</span>
              <input type="number" value={it.unit_price} onChange={e => updateItem(i, 'unit_price', Number(e.target.value))}
                className="text-sm text-right outline-none" style={fieldStyle} />
            </div>
            <div>
              <span className={labelCls} style={{ color: '#4a6357' }}>Celkem</span>
              <div className="text-sm text-right" style={{ padding: '9px 2px', fontWeight: 700, color: '#0f1a14' }}>
                {((it.unit_price || 0) * (it.qty || 1)).toLocaleString('cs-CZ')} Kč
              </div>
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}
