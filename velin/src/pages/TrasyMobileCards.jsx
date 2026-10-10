import { catLabel, poiPhoto } from '../lib/poiCategories'

// Mobil + tablet (< 1024 px): karty místo širokých tabulek v záložce Trasy
// (seznam tras a katalog míst). Desktop dál vykresluje původní tabulky —
// tyhle komponenty se renderují JEN když useIsMobile() vrátí true.
// Obsah, akce i texty jsou stejné jako v řádcích tabulek.

const btn = 'rounded-btn text-sm font-bold cursor-pointer'
const btnStyle = (color) => ({ color, background: '#f1faf7', border: 'none', padding: '8px 12px', minHeight: 38 })
const card = { background: '#fff', borderRadius: 18, boxShadow: '0 2px 10px rgba(15,26,20,.08)', padding: 12 }
const chip = { padding: '3px 8px', background: '#f1faf7', color: '#1a2e22', borderRadius: 50 }

function SelectAll({ checked, onChange, label }) {
  return (
    <label className="flex items-center gap-2 mb-3 cursor-pointer text-sm font-extrabold uppercase tracking-wide"
      style={{ ...card, padding: '10px 14px', color: '#1a2e22', display: 'inline-flex' }}>
      <input type="checkbox" checked={checked} onChange={onChange} />
      {label}
    </label>
  )
}

/** Seznam tras jako karty (Trasy → záložka Trasy). Klik na kartu = otevřít trasu. */
export function TrasyRouteCards({ rows, filtered, selected, setSelected, toggleSel, poiCounts, reviewStats,
  openingRoute, onOpen, onToggleActive, onDelete, onReviews, typeLabel, emptyText }) {
  return (
    <div>
      <SelectAll label="Vybrat vše (dle filtru)"
        checked={filtered.length > 0 && filtered.every(r => selected.has(r.id))}
        onChange={e => setSelected(e.target.checked ? new Set(filtered.map(r => r.id)) : new Set())} />
      {rows.length === 0 && emptyText && (
        <div className="text-sm text-center py-6" style={{ ...card, color: '#1a2e22' }}>{emptyText}</div>
      )}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {rows.map(r => {
          const st = reviewStats[r.id]
          return (
            <div key={r.id} className="cursor-pointer" style={card} onClick={() => onOpen(r)}>
              <div className="flex items-start gap-3" style={{ opacity: r.is_active ? 1 : 0.55 }}>
                <input type="checkbox" checked={selected.has(r.id)} className="mt-1 shrink-0"
                  onClick={e => e.stopPropagation()} onChange={() => toggleSel(r.id)} />
                {r.cover_image ? (
                  <img src={r.cover_image} alt={r.name} loading="lazy" className="shrink-0"
                    style={{ width: 72, height: 50, objectFit: 'cover', borderRadius: 8, border: '1px solid #d4e8e0' }}
                    onError={e => { e.target.style.opacity = 0.3 }} />
                ) : (
                  <div className="shrink-0" style={{ width: 72, height: 50, borderRadius: 8, background: '#e2f5ec', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20 }}>🛣️</div>
                )}
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-bold" style={{ color: '#0f1a14', overflowWrap: 'anywhere' }}>{r.name}</div>
                  {Array.isArray(r.countries) && r.countries.length > 0 && (
                    <div className="flex gap-1 flex-wrap mt-1">
                      {r.countries.map(c => (
                        <span key={c} className="inline-block rounded-btn text-xs font-bold"
                          style={{ padding: '1px 6px', background: '#eef2ff', color: '#4338ca' }}>{c}</span>
                      ))}
                    </div>
                  )}
                </div>
                <span className="shrink-0 inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                  style={{ padding: '3px 8px', background: r.is_active ? '#dcfce7' : '#fee2e2', color: r.is_active ? '#1a8a18' : '#dc2626' }}>
                  {r.is_active ? 'Publikováno' : 'Skryto'}
                </span>
              </div>
              <div className="flex gap-2 flex-wrap items-center mt-2 text-xs font-bold">
                <span style={chip}>{typeLabel[r.route_type] || r.route_type || '—'}</span>
                <span style={chip}>{r.distance_km ? `${r.distance_km} km` : '—'}</span>
                <span style={{ ...chip, color: poiCounts[r.id] > 0 ? '#8b5cf6' : '#1a2e22' }}>Body zájmu: {poiCounts[r.id] || 0}</span>
                <button onClick={e => { e.stopPropagation(); onReviews(r) }} title="Zobrazit / moderovat recenze"
                  className="cursor-pointer text-xs font-bold"
                  style={{ ...chip, border: 'none', minHeight: 30, color: st ? '#f59e0b' : '#6b8f7b' }}>
                  {st ? `★ ${st.avg} (${st.count})` : 'Recenze: —'}
                </button>
              </div>
              <div className="flex gap-2 flex-wrap mt-3" onClick={e => e.stopPropagation()}>
                <button className={btn} style={btnStyle('#2563eb')} onClick={() => onOpen(r)}>
                  {openingRoute === r.id ? 'Otevírám…' : 'Upravit'}
                </button>
                <button className={btn} style={btnStyle(r.is_active ? '#b45309' : '#1a8a18')} onClick={() => onToggleActive(r)}>
                  {r.is_active ? 'Skrýt' : 'Publikovat'}
                </button>
                <button className={btn} style={btnStyle('#dc2626')} onClick={() => onDelete(r)}>Smazat</button>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

/** Katalog míst jako karty (Trasy → Katalog míst). */
export function TrasyPoiCards({ rows, selected, allOnPage, togglePage, toggleRow, stats, onEdit, onReviews, onToggleActive, onDelete }) {
  return (
    <div>
      <SelectAll label="Vybrat stránku" checked={allOnPage} onChange={togglePage} />
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {rows.map(p => (
          <div key={p.id} style={{ ...card, border: '1px solid #e5efe9' }}>
            <div className="flex items-start gap-3">
              <input type="checkbox" checked={selected.has(p.id)} onChange={() => toggleRow(p.id)} className="mt-1 shrink-0" />
              {poiPhoto(p)
                ? <img src={poiPhoto(p)} alt="" loading="lazy" className="shrink-0" style={{ width: 64, height: 48, objectFit: 'cover', borderRadius: 6 }} />
                : <div className="shrink-0 text-xs" style={{ width: 64, height: 48, borderRadius: 6, background: '#f3f4f6', display: 'grid', placeItems: 'center', color: '#9ca3af' }}>—</div>}
              <div className="min-w-0 flex-1">
                <div className="text-sm font-semibold" style={{ overflowWrap: 'anywhere' }}>{p.name}</div>
                {p.description && (
                  <div className="text-xs" style={{ color: '#6b7280', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{p.description}</div>
                )}
              </div>
              <span className="shrink-0 text-xs font-bold px-2 py-1 rounded-full"
                style={p.is_active ? { background: '#dcfce7', color: '#166534' } : { background: '#f3f4f6', color: '#6b7280' }}>
                {p.is_active ? 'Aktivní' : 'Skrytý'}
              </span>
            </div>
            <div className="flex gap-2 flex-wrap items-center mt-2 text-xs font-bold" style={{ color: '#374151' }}>
              <span style={chip}>{catLabel(p.category)}</span>
              <span style={chip}>{p.country || '—'}</span>
              <span style={{ ...chip, fontWeight: 600 }}>GPS {p.lat?.toFixed(4)}, {p.lng?.toFixed(4)}</span>
              <span style={{ ...chip, fontWeight: 600 }}>{p.source || '—'}</span>
            </div>
            <div className="flex gap-1.5 flex-wrap mt-3">
              <button className={btn} style={btnStyle('#2563eb')} onClick={() => onEdit(p)}>Upravit</button>
              <button className={btn} style={btnStyle(stats[p.id] ? '#f59e0b' : '#6b7280')} onClick={() => onReviews(p)}>
                {stats[p.id] ? `★ ${stats[p.id].avg} (${stats[p.id].count})` : '💬 Komentáře'}
              </button>
              <button className={btn} style={btnStyle(p.is_active ? '#b45309' : '#1a8a18')} onClick={() => onToggleActive(p)}>
                {p.is_active ? 'Skrýt' : 'Aktivovat'}
              </button>
              <button className={btn} style={btnStyle('#dc2626')} onClick={() => onDelete(p)}>Smazat</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
