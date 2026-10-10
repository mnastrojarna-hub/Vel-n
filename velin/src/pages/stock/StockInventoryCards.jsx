import SkuTag from '../../components/ui/SkuTag'

// Mobil + tablet (≤ 1023 px): karty skladových položek místo 10sloupcové tabulky
// (Sklady, Logistika → Sklad, Finance → Sklad). Desktop dál vykresluje tabulku v Inventory.jsx.

const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'
const CAT_LABELS = { material: 'Materiál', inventory: 'Zboží', supplies: 'Spotřební materiál', prislusenstvi: 'Příslušenství' }

function Info({ label, children, color, wide }) {
  return (
    <div style={{ minWidth: 0, gridColumn: wide ? '1 / -1' : undefined }}>
      <div className="font-extrabold uppercase tracking-wide" style={{ fontSize: 11, color: '#4a6357' }}>{label}</div>
      <div style={{ fontSize: 13, fontWeight: 600, color: color || '#0f1a14', overflowWrap: 'anywhere' }}>{children}</div>
    </div>
  )
}

export default function StockInventoryCards({ items, selectedIds, setSelectedIds, onOpen, onIssue }) {
  const allOn = items.length > 0 && items.every(i => selectedIds.has(i.id))
  const toggleAll = on => {
    const next = new Set(selectedIds)
    items.forEach(i => { if (on) next.add(i.id); else next.delete(i.id) })
    setSelectedIds(next)
  }
  const toggle = (id, on) => {
    const next = new Set(selectedIds)
    if (on) next.add(id); else next.delete(id)
    setSelectedIds(next)
  }

  if (items.length === 0) {
    return <div className="bg-white rounded-card shadow-card text-center" style={{ padding: '24px 16px', color: '#1a2e22', fontSize: 14 }}>Žádné položky</div>
  }

  return (
    <div>
      <label className="inline-flex items-center cursor-pointer rounded-btn font-bold"
        style={{ minHeight: 40, padding: '6px 12px', gap: 8, marginBottom: 10, background: '#fff', fontSize: 13, color: '#1a2e22', boxShadow: '0 2px 8px rgba(15,26,20,.08)' }}>
        <input type="checkbox" checked={allOn} onChange={e => toggleAll(e.target.checked)} className="accent-[#1a8a18]" style={{ width: 18, height: 18 }} />
        Vybrat vše ({items.length})
      </label>
      <div className="grid grid-cols-1 sm:grid-cols-2" style={{ gap: 10 }}>
        {items.map(item => {
          const isLow = (item.min_stock || 0) > 0 && item.stock <= item.min_stock
          const isSel = selectedIds.has(item.id)
          const canIssue = item.category === 'prislusenstvi' && item.stock > 0
          return (
            <div key={item.id} onClick={() => onOpen(item)} className="bg-white rounded-card shadow-card cursor-pointer"
              style={{ padding: '12px 14px', minWidth: 0, background: isSel ? '#fef9c3' : isLow ? '#fff5f5' : '#fff', border: `2px solid ${isSel ? '#fde68a' : 'transparent'}` }}>
              <div className="flex items-start" style={{ gap: 8 }}>
                <label onClick={e => e.stopPropagation()} className="flex items-center justify-center cursor-pointer shrink-0" style={{ width: 36, height: 36, margin: '-6px -4px 0 -8px' }}>
                  <input type="checkbox" checked={isSel} onChange={e => toggle(item.id, e.target.checked)} className="accent-[#1a8a18]" style={{ width: 20, height: 20 }} />
                </label>
                <div className="font-bold" style={{ flex: 1, minWidth: 0, fontSize: 14, color: '#0f1a14', lineHeight: 1.35, overflowWrap: 'anywhere' }}>{item.name}</div>
                <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase shrink-0"
                  style={{ padding: '4px 10px', background: isLow ? '#fee2e2' : '#dcfce7', color: isLow ? '#dc2626' : '#1a8a18' }}>
                  {isLow ? 'Nízké' : 'OK'}
                </span>
              </div>
              {/* SKU s nápovědou — klik nesmí otevřít detail položky */}
              <div onClick={e => e.stopPropagation()} style={{ marginTop: 6, fontSize: 13, overflowWrap: 'anywhere' }}>
                <SkuTag sku={item.sku} />
              </div>
              <div className="grid grid-cols-3" style={{ gap: '8px 12px', marginTop: 10 }}>
                <Info label="Sklad" color={isLow ? '#dc2626' : '#0f1a14'}><b>{item.stock ?? 0}</b></Info>
                <Info label="Minimum">{item.min_stock ?? 0}</Info>
                <Info label="Cena/ks">{item.unit_price ? fmt(item.unit_price) : '—'}</Info>
                <Info label="Kategorie">{CAT_LABELS[item.category] || item.category || '—'}</Info>
                <Info label="Dodavatel" wide>{item.suppliers?.name || '—'}</Info>
              </div>
              {canIssue && (
                <button type="button" onClick={e => { e.stopPropagation(); onIssue(item) }}
                  className="rounded-btn text-sm font-bold cursor-pointer border-none w-full"
                  style={{ minHeight: 40, marginTop: 10, background: '#1a2e22', color: '#74FB71' }}>
                  → Vydat na pobočku
                </button>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
