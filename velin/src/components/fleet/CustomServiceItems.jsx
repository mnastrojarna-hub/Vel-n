import { useState } from 'react'
import { SERVICE_CHECKLIST_LABELS } from './motoActionConstants'

/**
 * „Jiné“ — vlastní servisní úkony mimo standardní checklist (zadání majitele:
 * zaškrtnu Jiné a vypíšu, co se dělalo; položek může být víc). Ukládají se do
 * `maintenance_log.items` vedle standardních jako `{ label, done, note, custom: true }`,
 * takže je vidí servisní karta i servisní kniha stejně jako ostatní úkony.
 */

/** Štítky vlastních úkonů z uložených items (vše, co není ve standardním checklistu). */
export function customLabelsFromItems(items, extraKnown = []) {
  if (!Array.isArray(items)) return []
  const known = new Set([...SERVICE_CHECKLIST_LABELS, ...extraKnown])
  const out = []
  for (const it of items) {
    const label = typeof it?.label === 'string' ? it.label.trim() : ''
    if (label && !known.has(label) && !out.includes(label)) out.push(label)
  }
  return out
}

/** Vlastní štítky → položky items (stejný tvar jako standardní + příznak custom). */
export function customLabelsToItems(labels) {
  return (labels || []).map(label => ({ label, done: false, note: '', custom: true }))
}

/** Smíšený seznam štítků (standardní + vlastní) → items; vlastní dostanou `custom: true`. */
export function labelsToItems(labels, extraKnown = []) {
  const known = new Set([...SERVICE_CHECKLIST_LABELS, ...extraKnown])
  return (labels || []).map(label => known.has(label)
    ? { label, done: false, note: '' }
    : { label, done: false, note: '', custom: true })
}

export default function CustomServiceItems({ labels, onChange, compact = false }) {
  const [open, setOpen] = useState(labels.length > 0)
  const [draft, setDraft] = useState('')
  const active = open || labels.length > 0

  function add() {
    const v = draft.trim()
    if (!v) return
    if (!labels.includes(v)) onChange([...labels, v])
    setDraft('')
  }
  function remove(label) {
    const next = labels.filter(l => l !== label)
    onChange(next)
  }
  function toggle(checked) {
    setOpen(checked)
    if (!checked && labels.length > 0) onChange([])
  }

  return (
    <div className={compact ? 'mt-2' : 'mt-3'} style={{ padding: compact ? '8px 10px' : '10px 12px', borderRadius: 10, background: active ? '#e8fde8' : '#f1faf7', border: `1px solid ${active ? '#74FB71' : '#d4e8e0'}` }}>
      <label className="flex items-center gap-2 cursor-pointer">
        <input type="checkbox" checked={active} onChange={e => toggle(e.target.checked)}
          style={{ accentColor: '#16a34a', width: 16, height: 16, cursor: 'pointer' }} />
        <span className="text-sm" style={{ color: '#1a2e22', fontWeight: active ? 700 : 500 }}>
          Jiné — vlastní úkon (vypište){labels.length > 0 && <span style={{ color: '#1a8a18' }}> · {labels.length}</span>}
        </span>
      </label>
      {active && (
        <div className="mt-2">
          {labels.length > 0 && (
            <div className="flex flex-wrap gap-1 mb-2">
              {labels.map(l => (
                <span key={l} className="inline-flex items-center gap-1 text-sm font-bold" style={{ padding: '3px 8px', borderRadius: 8, background: '#fff', border: '1px solid #b6dccb', color: '#0f1a14' }}>
                  ✎ {l}
                  <button type="button" onClick={() => remove(l)} title="Odebrat" className="cursor-pointer"
                    style={{ background: 'none', border: 'none', color: '#dc2626', fontWeight: 800, padding: 0, lineHeight: 1 }}>×</button>
                </span>
              ))}
            </div>
          )}
          <div className="flex gap-2">
            <input type="text" value={draft} onChange={e => setDraft(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); add() } }}
              onBlur={add}
              placeholder="Např. výměna brzdových hadic, seřízení karburátoru…"
              className="flex-1 rounded-btn text-sm outline-none"
              style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
            <button type="button" onClick={add} disabled={!draft.trim()} className="rounded-btn text-sm font-extrabold uppercase cursor-pointer disabled:opacity-50"
              style={{ padding: '6px 12px', background: '#74FB71', color: '#1a2e22', border: 'none' }}>Přidat</button>
          </div>
          <div className="text-xs mt-1" style={{ color: '#6b7280' }}>Každý úkon potvrďte tlačítkem Přidat nebo klávesou Enter (rozepsaný text se přidá i sám při opuštění pole) — lze zadat víc úkonů.</div>
        </div>
      )}
    </div>
  )
}
