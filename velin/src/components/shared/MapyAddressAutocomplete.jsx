import { useEffect, useRef, useState } from 'react'
import { suggest } from '../../lib/mapyCz'

// Autocomplete pro adresy postavene nad Mapy.cz Suggest API.
// Slouzi napric flow: tvorba / uprava rezervace, SOS incidenty (poloha, nejblizsi servis).
export default function MapyAddressAutocomplete({
  value,
  onChange,
  onSelect,
  placeholder = 'Obec, ulice a c.p. / c.o.',
  className = '',
  style,
  openMapPicker,
  limit = 8,
}) {
  const [items, setItems] = useState([])
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(-1)
  const [loading, setLoading] = useState(false)
  const wrapRef = useRef(null)
  const debounceRef = useRef(null)

  useEffect(() => {
    const onDoc = (e) => { if (wrapRef.current && !wrapRef.current.contains(e.target)) setOpen(false) }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [])

  function runSuggest(q) {
    if (debounceRef.current) clearTimeout(debounceRef.current)
    if (!q || q.trim().length < 2) {
      setItems([]); setLoading(false); return
    }
    setLoading(true)
    debounceRef.current = setTimeout(async () => {
      const data = await suggest(q, { limit })
      setItems(data)
      setLoading(false)
      setOpen(true)
    }, 220)
  }

  function pick(item) {
    const full = item.full || item.label || ''
    onChange?.(full)
    onSelect?.({
      full,
      label: item.label,
      description: item.description,
      zip: item.zip,
      lat: item.lat,
      lng: item.lng,
      raw: item.raw,
    })
    setOpen(false)
    setActive(-1)
  }

  function handleKey(e) {
    if (!open || items.length === 0) {
      if (e.key === 'ArrowDown' && value) runSuggest(value)
      return
    }
    if (e.key === 'ArrowDown') { e.preventDefault(); setActive(a => Math.min(items.length - 1, a + 1)) }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActive(a => Math.max(0, a - 1)) }
    else if (e.key === 'Enter' && active >= 0) { e.preventDefault(); pick(items[active]) }
    else if (e.key === 'Escape') setOpen(false)
  }

  return (
    <div ref={wrapRef} style={{ position: 'relative', ...(style || {}) }}>
      <div style={{ display: 'flex', gap: 6, alignItems: 'stretch' }}>
        <input
          value={value || ''}
          onChange={e => { onChange?.(e.target.value); runSuggest(e.target.value) }}
          onFocus={() => { if (items.length) setOpen(true) }}
          onKeyDown={handleKey}
          placeholder={placeholder}
          className={className}
          style={{ flex: 1, padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0', borderRadius: 8, fontSize: 14, outline: 'none' }}
          autoComplete="off"
        />
        {openMapPicker && (
          <button
            type="button"
            onClick={openMapPicker}
            title="Vybrat na mape"
            style={{ padding: '4px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, color: '#1a2e22', cursor: 'pointer', fontSize: 12, fontWeight: 700 }}
          >
            {'🗺️'}
          </button>
        )}
      </div>
      {open && (loading || items.length > 0) && (
        <div style={{
          position: 'absolute', top: '100%', left: 0, right: 0, zIndex: 30,
          background: '#fff', border: '1px solid #d4e8e0', borderRadius: 8,
          marginTop: 4, maxHeight: 260, overflowY: 'auto', boxShadow: '0 6px 18px rgba(15,26,20,.12)',
        }}>
          {loading && <div style={{ padding: '8px 10px', fontSize: 12, color: '#6b7280' }}>Hledam…</div>}
          {!loading && items.length === 0 && <div style={{ padding: '8px 10px', fontSize: 12, color: '#6b7280' }}>Zadne navrhy</div>}
          {items.map((it, i) => (
            <div key={i}
              onMouseEnter={() => setActive(i)}
              onMouseDown={(e) => { e.preventDefault(); pick(it) }}
              style={{
                padding: '7px 10px', cursor: 'pointer', fontSize: 13,
                background: i === active ? '#f1faf7' : '#fff',
                borderTop: i === 0 ? 'none' : '1px solid #eef5f1',
              }}>
              <div style={{ fontWeight: 700, color: '#0f1a14' }}>{it.label}</div>
              {it.description && <div style={{ fontSize: 11, color: '#6b7280' }}>{it.description}</div>}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
