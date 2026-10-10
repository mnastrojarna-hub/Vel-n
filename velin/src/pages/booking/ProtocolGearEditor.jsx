import { useState } from 'react'

// Předávací protokol (Velín) — „Předané příslušenství“: velikost, nepřevzato (odškrtnutí),
// a u OBSLUŽNÉ pobočky (canEdit) navíc smazání položky a přidání výbavy navíc.
// Položka: { label, size, type, field, checked, origSize, added?, deleted? }
//  - field = sloupec bookings.*_size (řidič / spolujezdec); u „jiné“ položky null (jen do protokolu)
//  - added = přidáno při předání → při uložení se velikost propíše do rezervace (Logistika zboží,
//    historie změn); deleted = smazáno z protokolu → z rezervace se odebere (jako nepřevzato).
// Cena rezervace / booking_extras se protokolem nemění (stejně jako při odebrání).

export const GEAR_TYPES = [
  { key: 'helmet', label: 'Helma' },
  { key: 'jacket', label: 'Bunda / vesta' },
  { key: 'pants', label: 'Kalhoty' },
  { key: 'boots', label: 'Boty' },
  { key: 'gloves', label: 'Rukavice' },
]
const WHO = [{ prefix: '', label: 'řidič' }, { prefix: 'passenger_', label: 'spolujezdec' }]
const OTHER = '__other__'

const btn = { borderRadius: 8, fontSize: 13, fontWeight: 700, cursor: 'pointer', border: '1px solid #b6dccb', background: '#fff', padding: '6px 12px' }

export default function ProtocolGearEditor({ accessories, setAccessories, sizesByType, canEdit, childSuffix = '' }) {
  const [adding, setAdding] = useState(false)
  const [slot, setSlot] = useState('')
  const [size, setSize] = useState('')
  const [otherLabel, setOtherLabel] = useState('')

  const update = (i, patch) => setAccessories(a => a.map((x, idx) => (idx === i ? { ...x, ...patch } : x)))
  // Odškrtnutí vrací velikost z rezervace (origSize) — dokument u nepřevzaté položky ukáže objednanou velikost
  const toggle = (i) => setAccessories(a => a.map((x, idx) => (idx === i ? { ...x, checked: !x.checked, size: x.checked && !x.added ? x.origSize : x.size } : x)))
  // Přidaná položka se smaže úplně; položka z rezervace se označí (lze vrátit) a při uložení odebere
  const remove = (i) => setAccessories(a => (a[i].added ? a.filter((_, idx) => idx !== i) : a.map((x, idx) => (idx === i ? { ...x, deleted: true, size: x.origSize } : x))))
  const restore = (i) => update(i, { deleted: false, checked: true })

  // Volné sloty = sloupce výbavy, které v protokolu ještě nejsou (smazané se vrací tlačítkem „Vrátit“)
  const used = new Set(accessories.map(a => a.field).filter(Boolean))
  const freeSlots = []
  for (const w of WHO) for (const t of GEAR_TYPES) {
    const field = `${w.prefix}${t.key}_size`
    if (!used.has(field)) freeSlots.push({ field, type: t.key, label: `${t.label} (${w.label})${childSuffix}` })
  }
  const picked = freeSlots.find(s => s.field === slot)
  const opts = picked ? (sizesByType[picked.type] || []) : []

  function openAdd() {
    const first = freeSlots[0]
    setSlot(first ? first.field : OTHER)
    setSize(first ? ((sizesByType[first.type] || [])[0] || '') : '')
    setOtherLabel('')
    setAdding(true)
  }
  function pickSlot(v) {
    setSlot(v)
    const s = freeSlots.find(x => x.field === v)
    setSize(s ? ((sizesByType[s.type] || [])[0] || '') : '')
  }
  function confirmAdd() {
    if (slot === OTHER) {
      const label = otherLabel.trim()
      if (!label) return
      setAccessories(a => [...a, { label, size: size.trim(), type: null, field: null, checked: true, origSize: null, added: true }])
    } else {
      if (!picked || !size.trim()) return
      setAccessories(a => [...a, { label: picked.label, size: size.trim(), type: picked.type, field: picked.field, checked: true, origSize: null, added: true }])
    }
    setAdding(false)
  }

  const cbStyle = { width: 22, height: 22, accentColor: '#3dba3a', cursor: 'pointer', flexShrink: 0 }
  const labelStyle = { fontSize: 14, color: '#0f1a14', cursor: 'pointer', lineHeight: 1.3 }
  const deleted = accessories.map((a, i) => ({ a, i })).filter(x => x.a.deleted)

  return (
    <div>
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Předané příslušenství</h3>
      <p style={{ fontSize: 12, color: '#4b5f52', marginBottom: 8 }}>
        Pokud zákazník dostal jinou velikost, změňte ji zde. Co si nevzal, odškrtněte — položka se z rezervace odebere.
        {canEdit && ' Položku lze ✕ smazat z protokolu (z rezervace se také odebere) a výbavu navíc přidat tlačítkem „+ Přidat položku“.'}
        {' '}U zaškrtnutých položek se skutečnost propíše do rezervace a Logistiky zboží.
      </p>
      <div className="space-y-2">
        {accessories.map((a, i) => {
          if (a.deleted) return null
          const sizes = a.type ? (sizesByType[a.type] || []) : []
          const optList = sizes.includes(a.size) || !a.size ? sizes : [a.size, ...sizes]
          const off = !a.checked
          const changed = !off && !a.added && a.size !== a.origSize
          const sizeStyle = { padding: '6px 10px', borderRadius: 8, border: `1px solid ${changed ? '#f59e0b' : '#b6dccb'}`, fontSize: 14, fontWeight: 700, background: off ? '#f1f5f3' : '#fff', color: off ? '#9ca3af' : undefined }
          return (
            <div key={a.field || `x${i}`} className="flex items-center gap-3 p-2 rounded-lg max-sm:flex-wrap max-sm:gap-y-1" style={{ background: a.added ? '#f0fdf4' : '#f8faf9', ...(a.added ? { boxShadow: 'inset 0 0 0 1px #86efac' } : {}) }}>
              <input type="checkbox" checked={a.checked} onChange={() => toggle(i)} style={cbStyle} />
              <span style={{ ...labelStyle, flex: 1, ...(off ? { textDecoration: 'line-through', color: '#9ca3af' } : {}) }} onClick={() => toggle(i)}>
                {a.label}
                {a.added && <span style={{ marginLeft: 6, fontSize: 11, fontWeight: 800, color: '#15803d', whiteSpace: 'nowrap' }}>+ přidáno</span>}
              </span>
              {sizes.length > 0 ? (
                <select value={a.size} disabled={off} onChange={e => update(i, { size: e.target.value })} style={sizeStyle}>
                  {optList.map(s => <option key={s} value={s}>{s}</option>)}
                </select>
              ) : (
                <input type="text" value={a.size} disabled={off} placeholder="vel." onChange={e => update(i, { size: e.target.value })}
                  style={{ ...sizeStyle, width: 80, textAlign: 'center' }} />
              )}
              {off ? (
                <span style={{ fontSize: 11, fontWeight: 700, color: '#dc2626', whiteSpace: 'nowrap' }}>{a.added ? 'nepřevzato — nepřidá se' : 'nepřevzato — odebere se z rezervace'}</span>
              ) : changed && (
                <span style={{ fontSize: 11, fontWeight: 700, color: '#b45309', whiteSpace: 'nowrap' }}>bylo {a.origSize}</span>
              )}
              {canEdit && (
                <button type="button" onClick={() => remove(i)} title="Smazat položku z protokolu" aria-label={`Smazat ${a.label}`}
                  className="shrink-0 max-lg:min-w-[40px] max-lg:min-h-[40px]"
                  style={{ ...btn, padding: '4px 10px', color: '#dc2626', borderColor: '#fca5a5' }}>✕</button>
              )}
            </div>
          )
        })}
        {accessories.every(a => a.deleted) && (
          <p style={{ fontSize: 12, color: '#6b7280' }}>V protokolu není žádné příslušenství.</p>
        )}
      </div>

      {canEdit && deleted.length > 0 && (
        <div className="mt-2 p-2 rounded-lg flex flex-wrap items-center gap-2" style={{ background: '#fef2f2', fontSize: 12, color: '#991b1b' }}>
          <span style={{ fontWeight: 700 }}>Smazáno z protokolu (z rezervace se odebere):</span>
          {deleted.map(({ a, i }) => (
            <span key={a.field || `d${i}`} className="inline-flex items-center gap-1">
              {a.label}
              <button type="button" onClick={() => restore(i)} className="max-lg:min-h-[36px]" style={{ ...btn, padding: '2px 8px', fontSize: 12, color: '#15803d' }}>Vrátit</button>
            </span>
          ))}
        </div>
      )}

      {canEdit && (adding ? (
        <div className="mt-3 p-3 rounded-lg space-y-2" style={{ background: '#f0fdf4', border: '1px solid #86efac' }}>
          <div className="flex flex-wrap gap-2 items-center">
            <select value={slot} onChange={e => pickSlot(e.target.value)} className="max-sm:w-full" style={{ ...btn, fontWeight: 600, minWidth: 220 }}>
              {freeSlots.map(s => <option key={s.field} value={s.field}>{s.label}</option>)}
              <option value={OTHER}>Jiná položka (jen do protokolu)…</option>
            </select>
            {slot === OTHER && (
              <input type="text" value={otherLabel} onChange={e => setOtherLabel(e.target.value)} placeholder="Název (např. kukla, kufr)"
                className="max-sm:w-full" style={{ ...btn, fontWeight: 500, flex: 1, minWidth: 160 }} />
            )}
            {opts.length > 0 ? (
              <select value={size} onChange={e => setSize(e.target.value)} style={{ ...btn, minWidth: 80 }}>
                {opts.map(s => <option key={s} value={s}>{s}</option>)}
              </select>
            ) : (
              <input type="text" value={size} onChange={e => setSize(e.target.value)} placeholder="velikost" style={{ ...btn, fontWeight: 500, width: 100 }} />
            )}
          </div>
          {slot !== OTHER && /(^|_)(boots|passenger_)/.test(slot) && (
            <p style={{ fontSize: 12, color: '#b45309' }}>Placená výbava (boty / výbava spolujezdce) — cena rezervace se protokolem nemění, případný doplatek vyřešte přes „Upravit rezervaci“.</p>
          )}
          <div className="flex gap-2 justify-end">
            <button type="button" onClick={() => setAdding(false)} className="max-lg:min-h-[40px]" style={btn}>Zrušit</button>
            <button type="button" onClick={confirmAdd} disabled={slot === OTHER ? !otherLabel.trim() : !size.trim()}
              className="max-lg:min-h-[40px] disabled:opacity-50" style={{ ...btn, background: '#74FB71', borderColor: '#74FB71', color: '#1a2e22' }}>Přidat</button>
          </div>
        </div>
      ) : (
        <button type="button" onClick={openAdd} className="mt-3 max-lg:min-h-[40px]" style={{ ...btn, color: '#15803d', borderColor: '#86efac', background: '#f0fdf4' }}>+ Přidat položku</button>
      ))}
    </div>
  )
}
