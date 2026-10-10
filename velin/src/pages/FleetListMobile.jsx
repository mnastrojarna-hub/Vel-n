import { useState } from 'react'
import SearchInput from '../components/ui/SearchInput'
import StatusBadge from '../components/ui/StatusBadge'

// Mobilní (≤ 1023 px) rozvržení seznamu Flotily: hledání + skládací panel filtrů
// a karty motorek místo 12sloupcové tabulky. Desktop tyto komponenty nepoužívá.

const FIELD = { width: '100%', minWidth: 0, minHeight: 44, padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', display: 'block' }
const SMALL_LABEL = { fontSize: 11, color: '#1a2e22', marginBottom: 6 }

function countActive(f) {
  let n = 0
  if (f.statuses?.length > 0) n++
  if (f.branch) n++
  if (f.category) n++
  if (f.sort && f.sort !== 'model') n++
  if (f.occupiedToday) n++
  if (f.occupiedFrom || f.occupiedTo) n++
  return n
}

export function FleetMobileFilters({ filters, update, onReset, branches, categories, statusOptions, sortOptions, selectedCount, onBulk, onAdd }) {
  const [open, setOpen] = useState(false)
  const active = countActive(filters)
  const statuses = filters.statuses || []
  const toggleStatus = val => update({ statuses: statuses.includes(val) ? statuses.filter(v => v !== val) : [...statuses, val] })
  const select = (value, key, options) => (
    <select value={value} onChange={e => update({ [key]: e.target.value })}
      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none" style={FIELD}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )

  return (
    <div className="mb-4">
      <div className="flex items-center" style={{ gap: 8 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <SearchInput fullWidth value={filters.search} onChange={v => update({ search: v })} placeholder="Hledat model, SPZ…" />
        </div>
        <button type="button" onClick={() => setOpen(o => !o)} aria-expanded={open}
          className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer shrink-0 flex items-center"
          style={{ minHeight: 42, padding: '8px 12px', fontSize: 13, gap: 6, color: '#1a2e22', background: open || active > 0 ? '#e8fee7' : '#f1faf7', border: `1px solid ${active > 0 ? '#74FB71' : '#d4e8e0'}` }}>
          Filtry
          {active > 0 && (
            <span className="font-extrabold" style={{ background: '#74FB71', color: '#0f1a14', borderRadius: 50, minWidth: 20, height: 20, fontSize: 12, lineHeight: '20px', textAlign: 'center', padding: '0 5px' }}>{active}</span>
          )}
          <span aria-hidden style={{ fontSize: 10 }}>{open ? '▲' : '▼'}</span>
        </button>
      </div>

      {open && (
        <div className="bg-white rounded-card shadow-card" style={{ padding: 14, marginTop: 10 }}>
          <div className="font-extrabold uppercase tracking-wide" style={SMALL_LABEL}>Stav</div>
          <div className="flex flex-wrap" style={{ gap: 8 }}>
            {statusOptions.map(o => {
              const on = statuses.includes(o.value)
              return (
                <label key={o.value} className="flex items-center cursor-pointer rounded-btn"
                  style={{ minHeight: 40, padding: '6px 12px', gap: 8, background: on ? '#74FB71' : '#f1faf7', border: `1px solid ${on ? '#74FB71' : '#d4e8e0'}` }}>
                  <input type="checkbox" checked={on} onChange={() => toggleStatus(o.value)} className="accent-[#1a8a18]" style={{ width: 18, height: 18 }} />
                  <span className="font-bold" style={{ fontSize: 14, color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
                </label>
              )
            })}
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2" style={{ gap: 10, marginTop: 14 }}>
            {select(filters.branch, 'branch', [{ value: '', label: 'Všechny pobočky' }, ...branches.map(b => ({ value: b.id, label: b.name }))])}
            {select(filters.category, 'category', [{ value: '', label: 'Všechny kategorie' }, ...categories])}
            {select(filters.sort, 'sort', sortOptions)}
            <label className="flex items-center cursor-pointer rounded-btn text-sm font-extrabold uppercase tracking-wide"
              style={{ minHeight: 44, padding: '8px 14px', gap: 8, background: filters.occupiedToday ? '#74FB71' : '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
              <input type="checkbox" checked={filters.occupiedToday} onChange={e => update({ occupiedToday: e.target.checked })} className="accent-[#1a8a18]" style={{ width: 18, height: 18 }} />
              Dnes obsazené
            </label>
          </div>
          <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 10, marginTop: 14 }}>
            <label className="block">
              <div className="font-extrabold uppercase tracking-wide" style={SMALL_LABEL}>Od</div>
              <input type="date" value={filters.occupiedFrom} onChange={e => update({ occupiedFrom: e.target.value })} className="rounded-btn text-sm outline-none cursor-pointer" style={FIELD} />
            </label>
            <label className="block">
              <div className="font-extrabold uppercase tracking-wide" style={SMALL_LABEL}>Do</div>
              <input type="date" value={filters.occupiedTo} onChange={e => update({ occupiedTo: e.target.value })} className="rounded-btn text-sm outline-none cursor-pointer" style={FIELD} />
            </label>
          </div>
          <button type="button" onClick={onReset}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer w-full"
            style={{ minHeight: 44, marginTop: 14, background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
            Reset
          </button>
        </div>
      )}

      <div className="flex" style={{ gap: 8, marginTop: 10 }}>
        <button type="button" onClick={onBulk} disabled={selectedCount === 0}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer disabled:cursor-not-allowed"
          style={{ flex: 1, minHeight: 44, padding: '8px 10px', border: 'none', background: selectedCount > 0 ? '#fde68a' : '#f1faf7', color: '#92400e', opacity: selectedCount === 0 ? 0.5 : 1 }}>
          ☰ Hromadná správa{selectedCount > 0 ? ` (${selectedCount})` : ''}
        </button>
        <button type="button" onClick={onAdd}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ flex: 1, minHeight: 44, padding: '8px 10px', border: 'none', background: '#74FB71', color: '#1a2e22', boxShadow: '0 4px 16px rgba(116,251,113,.35)' }}>
          + Nová motorka
        </button>
      </div>
    </div>
  )
}

function priceLabel(m) {
  const days = [m.price_mon, m.price_tue, m.price_wed, m.price_thu, m.price_fri, m.price_sat, m.price_sun].map(Number).filter(v => v > 0)
  if (!days.length) return '—'
  const min = Math.min(...days), max = Math.max(...days)
  return min === max ? `${min.toLocaleString('cs-CZ')} Kč` : `${min.toLocaleString('cs-CZ')}–${max.toLocaleString('cs-CZ')} Kč`
}

function Thumb({ src, alt }) {
  const [failed, setFailed] = useState(false)
  const box = { width: 64, height: 48, borderRadius: 8, background: '#f1faf7', flexShrink: 0 }
  if (!src || failed) return <div style={{ ...box, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20 }}>🏍️</div>
  return <img src={src} alt={alt} loading="lazy" decoding="async" onError={() => setFailed(true)} style={{ ...box, objectFit: 'cover' }} />
}

function Info({ label, children }) {
  return (
    <div style={{ minWidth: 0 }}>
      <div className="font-extrabold uppercase tracking-wide" style={{ fontSize: 11, color: '#4a6357' }}>{label}</div>
      <div style={{ fontSize: 13, fontWeight: 600, color: '#0f1a14', overflowWrap: 'anywhere' }}>{children}</div>
    </div>
  )
}

export function FleetMobileCards({ motos, selected, setSelected, missingAssetDocs, catLabels, onOpen, onAction }) {
  const allOn = motos.length > 0 && motos.every(m => selected.has(m.id))
  const toggleAll = on => {
    const next = new Map(selected)
    motos.forEach(m => { if (on) next.set(m.id, m); else next.delete(m.id) })
    setSelected(next)
  }
  const toggle = (m, on) => {
    const next = new Map(selected)
    if (on) next.set(m.id, m); else next.delete(m.id)
    setSelected(next)
  }

  if (motos.length === 0) {
    return <div className="bg-white rounded-card shadow-card text-center" style={{ padding: '24px 16px', color: '#1a2e22', fontSize: 14 }}>Žádné motorky</div>
  }

  return (
    <div>
      <label className="inline-flex items-center cursor-pointer rounded-btn font-bold"
        style={{ minHeight: 40, padding: '6px 12px', gap: 8, marginBottom: 10, background: '#fff', fontSize: 13, color: '#1a2e22', boxShadow: '0 2px 8px rgba(15,26,20,.08)' }}>
        <input type="checkbox" checked={allOn} onChange={e => toggleAll(e.target.checked)} className="accent-[#1a8a18]" style={{ width: 18, height: 18 }} />
        Vybrat vše ({motos.length})
      </label>
      <div className="grid grid-cols-1 sm:grid-cols-2" style={{ gap: 10 }}>
        {motos.map(m => {
          const isSel = selected.has(m.id)
          return (
            <div key={m.id} onClick={() => onOpen(m)} className="bg-white rounded-card shadow-card cursor-pointer"
              style={{ padding: '12px 14px', minWidth: 0, background: isSel ? '#fef9c3' : '#fff', border: `2px solid ${isSel ? '#fde68a' : 'transparent'}` }}>
              <div className="flex items-start" style={{ gap: 10 }}>
                <label onClick={e => e.stopPropagation()} className="flex items-center justify-center cursor-pointer shrink-0" style={{ width: 36, height: 48, margin: '0 -6px 0 -8px' }}>
                  <input type="checkbox" checked={isSel} onChange={e => toggle(m, e.target.checked)} className="accent-[#1a8a18]" style={{ width: 20, height: 20 }} />
                </label>
                <Thumb src={m.image_url || (m.images && m.images[0]) || null} alt={m.model} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="font-bold" style={{ fontSize: 14, color: '#0f1a14', lineHeight: 1.3 }}>
                    {m.sort_order != null && (
                      <span className="mr-1.5 text-xs font-extrabold rounded" style={{ padding: '1px 5px', background: '#e8fde8', color: '#1a8a18' }}>#{m.sort_order}</span>
                    )}
                    {m.model}
                  </div>
                  <div style={{ fontSize: 13, color: '#1a2e22', marginTop: 2 }}>
                    <span style={{ fontFamily: 'monospace' }}>{m.spz || '—'}</span> · {catLabels[m.category] || m.category || '—'}
                  </div>
                  <div style={{ marginTop: 6 }}><StatusBadge status={m.status} /></div>
                </div>
              </div>
              {missingAssetDocs.has(m.id) && (
                <div className="font-bold" style={{ fontSize: 12, color: '#dc2626', marginTop: 6 }}>! Chybí doklad o nabytí v majetku</div>
              )}
              <div className="grid grid-cols-2" style={{ gap: '8px 12px', marginTop: 10 }}>
                <Info label="Pobočka">{m.branches?.name || '—'}</Info>
                <Info label="Cena/den">{priceLabel(m)}</Info>
                <Info label="Km">{m.mileage?.toLocaleString('cs-CZ') || '—'}</Info>
                <Info label="Pořízeno">{m.acquired_at ? new Date(m.acquired_at).toLocaleDateString('cs-CZ') : '—'}</Info>
                <Info label="Další servis">{m.next_service_date || '—'}</Info>
                <button type="button" onClick={e => { e.stopPropagation(); onAction(m) }}
                  className="rounded-btn text-sm font-extrabold uppercase cursor-pointer w-full self-end"
                  style={{ minHeight: 40, background: '#dbeafe', color: '#2563eb', border: 'none' }}>
                  Správa
                </button>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
