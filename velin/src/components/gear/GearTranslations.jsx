import { useState } from 'react'
import { LANGS, INPUT } from './gearShared'

// Volitelné překlady názvu a popisu pro web (translations = {lang: {label, description}}).
// Prázdné pole = web použije český text. Jiné klíče v JSON zůstávají zachované.
export function cleanTranslations(tr) {
  const out = {}
  Object.entries(tr || {}).forEach(([lang, val]) => {
    if (!val || typeof val !== 'object') return
    const next = { ...val }
    ;['label', 'description'].forEach(f => {
      const v = typeof next[f] === 'string' ? next[f].trim() : next[f]
      if (v) next[f] = v
      else delete next[f]
    })
    if (Object.keys(next).length) out[lang] = next
  })
  return out
}

export default function GearTranslations({ value, onChange, showDesc }) {
  const [open, setOpen] = useState(false)
  const tr = value || {}
  const filled = LANGS.filter(l => tr[l]?.label).length
  const set = (lang, field, v) => onChange({ ...tr, [lang]: { ...(tr[lang] || {}), [field]: v } })

  return (
    <div className="rounded-lg" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
      <button type="button" onClick={() => setOpen(o => !o)}
        className="w-full flex items-center justify-between cursor-pointer border-none bg-transparent text-sm font-extrabold uppercase tracking-wide max-lg:min-h-[40px]"
        style={{ padding: '8px 12px', color: '#1a2e22' }}>
        <span>Překlady pro web (nepovinné) · {filled}/{LANGS.length}</span>
        <span aria-hidden style={{ fontSize: 10 }}>{open ? '▲' : '▼'}</span>
      </button>
      {open && (
        <div style={{ padding: '0 12px 12px' }}>
          <p className="text-xs mb-2" style={{ color: '#6b7a72' }}>
            Co necháš prázdné, web v daném jazyce ukáže česky. Po změně českého názvu zkontroluj i překlady.
          </p>
          <div className="space-y-2">
            {LANGS.map(lang => (
              <div key={lang} className="flex items-center gap-2 max-sm:flex-wrap">
                <span className="font-mono font-bold text-sm uppercase" style={{ width: 28, color: '#1a2e22' }}>{lang}</span>
                <input value={tr[lang]?.label || ''} onChange={e => set(lang, 'label', e.target.value)}
                  placeholder="Název" style={{ ...INPUT, flex: 1, minWidth: 120 }} className="max-lg:min-h-[40px]" />
                {showDesc && (
                  <input value={tr[lang]?.description || ''} onChange={e => set(lang, 'description', e.target.value)}
                    placeholder="Popis" style={{ ...INPUT, flex: 2, minWidth: 160 }} className="max-lg:min-h-[40px]" />
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
