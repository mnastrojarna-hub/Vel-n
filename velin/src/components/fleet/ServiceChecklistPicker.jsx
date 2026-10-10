import { useMemo, useState } from 'react'
import { SERVICE_GROUPS, taskAppliesTo } from './serviceCatalog'
import CustomServiceItems from './CustomServiceItems'

/**
 * Jednotný výběr servisních úkonů (všechny servisní formuláře). Katalog ~95 úkonů v 10 skupinách:
 * hledání, sbalitelné skupiny (otevřené = skupina s vybranou položkou), filtr dle motorky
 * (řetěz / kardan / řemen, chlazení) a neomezené „Jiné“.
 * Props: checked (Set|object id→bool), onToggle(id), customLabels, onCustomChange, moto, compact
 */
const KIND_ICON = { replace: '🔁', check: '🔍', adjust: '🔧', repair: '🛠', other: '•' }

export default function ServiceChecklistPicker({ checked, onToggle, customLabels, onCustomChange, moto, compact = false, maxHeight = 420 }) {
  const [q, setQ] = useState('')
  const [open, setOpen] = useState({})
  const [showAll, setShowAll] = useState(false)
  const isChecked = (id) => checked instanceof Set ? checked.has(id) : !!checked?.[id]
  const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  const query = norm(q.trim())
  const tokens = query.split(/\s+/).filter(Boolean)
  const hay = (i, g) => norm([i.label, ...(i.aliases || []), g.label].join(' '))

  const groups = useMemo(() => SERVICE_GROUPS.map(g => {
    const items = g.items.filter(i => (showAll || !moto || taskAppliesTo(i, moto) || isChecked(i.id)) && (tokens.length === 0 || tokens.every(t => hay(i, g).includes(t))))
    return { ...g, items, selected: g.items.filter(i => isChecked(i.id)).length }
  }).filter(g => g.items.length > 0), [q, showAll, moto, checked])

  const total = SERVICE_GROUPS.reduce((n, g) => n + g.items.filter(i => isChecked(i.id)).length, 0) + (customLabels?.length || 0)
  const isOpen = (g) => query ? true : (open[g.key] ?? g.selected > 0)

  return (
    <div>
      <div className="flex items-center gap-2 mb-2 flex-wrap">
        <input value={q} onChange={e => setQ(e.target.value)} placeholder="Hledat úkon… (olej, brzd, řetěz, plexi)"
          className="rounded-btn text-sm outline-none flex-1" style={{ padding: '7px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minWidth: 180 }} />
        <span className="text-xs font-bold" style={{ color: total > 0 ? '#1a8a18' : '#6b7280' }}>{total > 0 ? `Vybráno ${total}` : 'Nic nevybráno'}</span>
        {moto && (
          <label className="flex items-center gap-1 text-xs cursor-pointer" style={{ color: '#6b7280' }} title="Zobrazit i úkony, které se této motorky netýkají (např. kardan u řetězové)">
            <input type="checkbox" checked={showAll} onChange={e => setShowAll(e.target.checked)} style={{ accentColor: '#16a34a' }} /> vše
          </label>
        )}
        <button type="button" onClick={() => setOpen(Object.fromEntries(SERVICE_GROUPS.map(g => [g.key, true])))} className="text-xs font-bold cursor-pointer max-lg:py-2" style={{ background: 'none', border: 'none', color: '#2563eb' }}>rozbalit vše</button>
      </div>
      <div className="space-y-1" style={{ maxHeight, overflowY: 'auto', paddingRight: 2 }}>
        {groups.map(g => (
          <div key={g.key} className="rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <button type="button" onClick={() => setOpen(o => ({ ...o, [g.key]: !isOpen(g) }))}
              className={`w-full flex items-center gap-2 cursor-pointer text-left ${compact ? 'px-2.5 py-1.5' : 'px-3 py-2'} max-lg:py-2.5`} style={{ background: 'none', border: 'none' }}>
              <span style={{ fontSize: 11, transform: isOpen(g) ? 'rotate(90deg)' : 'none', transition: 'transform .15s', color: '#1a2e22' }}>▶</span>
              <span className="text-xs font-extrabold uppercase tracking-wide flex-1" style={{ color: '#1a8a18' }}>{g.label}</span>
              {g.selected > 0 && <span className="text-xs font-bold rounded-full" style={{ padding: '1px 8px', background: '#74FB71', color: '#1a2e22' }}>{g.selected}</span>}
              <span className="text-xs" style={{ color: '#9ca3af' }}>{g.items.length}</span>
            </button>
            {isOpen(g) && (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-1" style={{ padding: '0 8px 8px' }}>
                {g.items.map(i => {
                  const on = isChecked(i.id)
                  return (
                    <label key={i.id} className="flex items-center gap-2 cursor-pointer rounded px-1.5 py-1 max-lg:py-1.5" style={{ background: on ? '#dcfce7' : '#fff', border: `1px solid ${on ? '#86efac' : '#e5efe9'}` }}>
                      <input type="checkbox" checked={on} onChange={() => onToggle(i.id)} style={{ accentColor: '#16a34a', width: 15, height: 15, cursor: 'pointer' }} />
                      <span className="text-sm" style={{ color: '#0f1a14', fontWeight: on ? 700 : 400 }}>
                        <span title={{ replace: 'výměna', check: 'kontrola', adjust: 'seřízení', repair: 'oprava' }[i.kind] || ''} style={{ fontSize: 11, marginRight: 4, opacity: .7 }}>{KIND_ICON[i.kind] || '•'}</span>{i.label}
                      </span>
                    </label>
                  )
                })}
              </div>
            )}
          </div>
        ))}
        {groups.length === 0 && <div className="text-sm py-3 text-center" style={{ color: '#6b7280' }}>Žádný úkon neodpovídá hledání — zapište ho níže jako „Jiné“.</div>}
      </div>
      <CustomServiceItems labels={customLabels || []} onChange={onCustomChange} compact={compact} />
    </div>
  )
}
