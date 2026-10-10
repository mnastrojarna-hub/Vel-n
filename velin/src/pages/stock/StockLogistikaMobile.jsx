// Logistika zboží — části jen pro mobil + tablet (≤ 1023 px). Desktop je nepoužívá.

const FIELD = { width: '100%', minWidth: 0, minHeight: 40, padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', color: '#0f1a14' }
const LABEL = { fontSize: 11, color: '#4a6357', marginBottom: 3 }

function F({ label, span2, children }) {
  return (
    <label className={`block${span2 ? ' col-span-2' : ''}`} style={{ minWidth: 0 }}>
      <div className="font-extrabold uppercase tracking-wide" style={LABEL}>{label}</div>
      {children}
    </label>
  )
}

// Naskladnění: jeden řádek dokladu jako karta s popisky polí (na desktopu jsou pole
// v jedné řadě bez popisků — Počet/Cena/Barva jen v tooltipu, který na dotyku nejde zobrazit).
export function StockReceiveLineMobile({ line, cats, def, types, sizes, sku, onChange, onRemove }) {
  return (
    <div className="rounded-btn" style={{ padding: 10, background: '#f9fdfb', border: '1px solid #e2eee8', borderRadius: 14 }}>
      <div className="flex items-center" style={{ gap: 6 }}>
        <input value={line.name} onChange={e => onChange({ name: e.target.value })} placeholder="Název položky"
          className="rounded-btn text-sm outline-none" style={{ ...FIELD, flex: 1 }} />
        <button type="button" onClick={onRemove} aria-label="Odebrat řádek" className="text-sm font-bold cursor-pointer shrink-0 rounded-btn"
          style={{ width: 40, height: 40, background: '#fff', border: '1px solid #fca5a5', color: '#dc2626' }}>✕</button>
      </div>
      <div className="grid grid-cols-2 md:grid-cols-4" style={{ gap: 8, marginTop: 8 }}>
        <F label="Kategorie" span2>
          <select value={line.cat} onChange={e => onChange({ cat: e.target.value, type: '', size: '' })} className="rounded-btn text-sm outline-none" style={FIELD}>
            {cats.map(c => <option key={c.key} value={c.key}>{c.label}</option>)}
          </select>
        </F>
        {def.sized ? (
          <>
            <F label="Typ">
              <select value={line.type} onChange={e => onChange({ type: e.target.value, size: '' })} className="rounded-btn text-sm outline-none" style={FIELD}>
                <option value="">typ</option>{types.map(t => <option key={t.key} value={t.key}>{t.label}</option>)}
              </select>
            </F>
            <F label="Velikost">
              <select value={line.size} onChange={e => onChange({ size: e.target.value })} className="rounded-btn text-sm outline-none" style={FIELD}>
                <option value="">vel.</option>{sizes.map(s => <option key={s} value={s}>{s}</option>)}
              </select>
            </F>
          </>
        ) : def.asset ? null : (
          <F label="Název pro SKU" span2>
            <input value={line.slug} onChange={e => onChange({ slug: e.target.value })} placeholder="název (kufr-givi-46l)" className="rounded-btn text-sm outline-none" style={FIELD} />
          </F>
        )}
        <F label="Počet">
          <input type="number" min={1} value={line.qty} onChange={e => onChange({ qty: e.target.value })} className="rounded-btn text-sm outline-none" style={FIELD} />
        </F>
        <F label="Cena/ks (CZK)">
          <input type="number" min={0} value={line.unit_price} onChange={e => onChange({ unit_price: e.target.value })} className="rounded-btn text-sm outline-none" style={FIELD} />
        </F>
        <F label="Barva">
          <input value={line.color || ''} onChange={e => onChange({ color: e.target.value })} placeholder="barva" className="rounded-btn text-sm outline-none" style={FIELD} />
        </F>
        <div style={{ minWidth: 0, alignSelf: 'end', paddingBottom: 8 }}>
          {def.asset
            ? <span className="text-xs font-mono" style={{ color: '#64748b' }}>jen finance <span className="font-sans" style={{ opacity: 0.8 }}>(dlouhodobý majetek se nenaskladňuje)</span></span>
            : <span className="text-xs font-mono" style={{ color: sku ? '#16a34a' : '#dc2626', overflowWrap: 'anywhere' }}>{sku || 'chybí SKU'}</span>}
        </div>
      </div>
    </div>
  )
}

// Dostupnost: na dotyku nejde zobrazit tooltip buňky (skladem / vybookováno) → klepnutí
// na buňku vypíše její detail pod tabulkou.
export function StockCalendarPickInfo({ pick, onClose }) {
  if (!pick) {
    return <div className="text-xs mb-4" style={{ color: '#1a2e22', opacity: 0.6, marginTop: -12 }}>Klepni na buňku pro detail (skladem · vybookováno).</div>
  }
  const { title, stock, booked, free, deficit } = pick
  return (
    <div className="flex items-start rounded-btn mb-4" style={{ marginTop: -12, gap: 8, padding: '8px 8px 8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 12 }}>
      <div className="text-sm" style={{ flex: 1, minWidth: 0, color: '#1a2e22' }}>
        <b>{title}</b><br />
        Skladem <b>{stock}</b> · Vybookováno <b>{booked}</b> · volné <b>{free}</b>
        {deficit > 0 && <> · chybí <b style={{ color: '#dc2626' }}>{deficit}</b></>}
      </div>
      <button type="button" onClick={onClose} aria-label="Zavřít" className="cursor-pointer shrink-0 font-bold"
        style={{ width: 32, height: 32, background: 'none', border: 'none', color: '#64748b' }}>✕</button>
    </div>
  )
}
