import { SelectAllCheckbox, RowCheckbox } from '../../components/ui/BulkActionsBar'

// E-shop → Produkty na telefonu a tabletu (< 1024 px): kompaktní karty místo 9sloupcové
// tabulky. Stejná data i akce jako tabulka na PC (výběr, aktivace, úprava, smazání);
// klepnutí na fotku/název otevře úpravu (jako ✏️). Tablet = 2 karty vedle sebe.
export default function ProductCardsMobile({ products, selectedIds, setSelectedIds, onEdit, onToggle, onDelete, fmt, totalStock, renderSizes }) {
  if (products.length === 0) {
    return <div className="bg-white rounded-card shadow-card text-sm" style={{ padding: '16px 18px', color: '#0f1a14' }}>Žádné produkty</div>
  }
  return (
    <div>
      <label className="inline-flex items-center gap-2 mb-3 rounded-btn bg-white cursor-pointer text-sm font-extrabold uppercase tracking-wide"
        style={{ padding: '8px 14px', minHeight: 40, color: '#1a2e22', boxShadow: '0 2px 8px rgba(15,26,20,.08)' }}>
        <SelectAllCheckbox items={products} selectedIds={selectedIds} setSelectedIds={setSelectedIds} />
        Vybrat vše
      </label>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {products.map(p => {
          const stock = totalStock(p)
          const stockColor = stock <= 0 ? '#dc2626' : stock <= 10 ? '#b45309' : '#1a8a18'
          const hasSizes = p?.sizes?.length > 0
          return (
            <div key={p.id} className="rounded-card shadow-card flex flex-col gap-2"
              style={{ padding: 12, background: selectedIds.has(p.id) ? '#fef9c3' : '#fff' }}>
              <div className="flex items-start gap-2">
                <label className="flex items-center justify-center cursor-pointer shrink-0" style={{ width: 32, height: 40 }}>
                  <RowCheckbox id={p.id} selectedIds={selectedIds} setSelectedIds={setSelectedIds} />
                </label>
                <button type="button" onClick={() => onEdit(p)}
                  className="flex items-start gap-3 flex-1 min-w-0 text-left cursor-pointer"
                  style={{ background: 'none', border: 'none', padding: 0 }}>
                  {p.images?.[0] ? (
                    <img src={p.images[0]} alt={p.name} className="shrink-0" style={{ width: 56, height: 56, objectFit: 'cover', borderRadius: 8, background: '#f1faf7' }} />
                  ) : (
                    <div className="shrink-0" style={{ width: 56, height: 56, background: '#f1faf7', borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22 }}>📦</div>
                  )}
                  <div className="min-w-0">
                    <div className="text-sm font-bold" style={{ color: '#0f1a14', overflowWrap: 'anywhere' }}>{p.name}</div>
                    <div className="text-xs font-mono" style={{ color: '#4a6357', overflowWrap: 'anywhere' }}>{p.sku || '—'}</div>
                    <div className="text-sm mt-1" style={{ color: '#0f1a14' }}>
                      <strong>{fmt(p.price)}</strong>
                      <span style={{ color: '#8aab99' }}> · </span>
                      <span style={{ fontWeight: 700, color: stockColor }}>{stock} ks</span>
                    </div>
                  </div>
                </button>
              </div>
              {hasSizes && <div style={{ paddingLeft: 40 }}>{renderSizes(p)}</div>}
              <div className="flex items-center gap-2" style={{ paddingLeft: 40 }}>
                <button type="button" onClick={() => onToggle(p)}
                  className="rounded-btn text-sm font-extrabold tracking-wide uppercase cursor-pointer"
                  style={{ padding: '6px 12px', minHeight: 36, border: 'none', background: p.is_active ? '#dcfce7' : '#fee2e2', color: p.is_active ? '#1a8a18' : '#dc2626' }}>
                  {p.is_active ? 'Aktivní' : 'Neaktivní'}
                </button>
                <div className="ml-auto flex gap-1">
                  <button type="button" onClick={() => onEdit(p)} aria-label="Upravit" className="rounded-btn cursor-pointer"
                    style={{ width: 40, height: 40, background: '#f1faf7', border: '1px solid #d4e8e0', fontSize: 16 }}>✏️</button>
                  <button type="button" onClick={() => onDelete(p.id)} aria-label="Smazat" className="rounded-btn cursor-pointer"
                    style={{ width: 40, height: 40, background: '#fee2e2', border: '1px solid #fca5a5', fontSize: 16 }}>🗑️</button>
                </div>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
