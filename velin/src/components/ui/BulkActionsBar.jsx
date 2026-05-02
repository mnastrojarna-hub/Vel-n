import { useState } from 'react'

/**
 * Generic bulk actions bar — sticky toolbar that appears when items are selected.
 *
 * Props:
 *   count — number of selected items
 *   onClear — clear selection callback
 *   actions — array of { label, onClick, danger?, confirm? (string), icon? }
 *
 * Each action may set `confirm: 'message'` to require window.confirm before running.
 */
export default function BulkActionsBar({ count, onClear, actions = [] }) {
  const [busy, setBusy] = useState(false)
  if (!count) return null
  const handle = async (a) => {
    if (a.confirm && !window.confirm(a.confirm.replace('{count}', count))) return
    setBusy(true)
    try { await a.onClick() } finally { setBusy(false) }
  }
  return (
    <div className="mb-3 flex items-center gap-2 flex-wrap rounded-card"
      style={{ padding: '8px 14px', background: '#fef9c3', border: '1px solid #fde68a' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#92400e' }}>
        ☰ Vybráno: {count}
      </span>
      <div className="flex items-center gap-1.5 flex-wrap">
        {actions.map((a, i) => (
          <button key={i} onClick={() => handle(a)} disabled={busy}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer disabled:opacity-50"
            style={{
              padding: '6px 12px',
              background: a.danger ? '#fee2e2' : '#fff',
              border: `1px solid ${a.danger ? '#fca5a5' : '#d4e8e0'}`,
              color: a.danger ? '#dc2626' : '#1a2e22',
            }}>
            {a.icon ? `${a.icon} ` : ''}{a.label}
          </button>
        ))}
      </div>
      <button onClick={onClear} disabled={busy}
        className="ml-auto rounded-btn text-sm font-bold cursor-pointer disabled:opacity-50"
        style={{ padding: '6px 10px', background: 'transparent', border: '1px solid #d4e8e0', color: '#6b7280' }}>
        ✕ Zrušit výběr
      </button>
    </div>
  )
}

/**
 * Helper component for a checkbox <th> cell that selects/deselects all visible rows.
 */
export function SelectAllCheckbox({ items, selectedIds, setSelectedIds }) {
  const allSelected = items.length > 0 && items.every(i => selectedIds.has(i.id))
  return (
    <input type="checkbox" className="accent-[#1a8a18] cursor-pointer" style={{ width: 16, height: 16 }}
      checked={allSelected}
      onChange={e => {
        const next = new Set(selectedIds)
        if (e.target.checked) items.forEach(i => next.add(i.id))
        else items.forEach(i => next.delete(i.id))
        setSelectedIds(next)
      }} />
  )
}

/**
 * Helper component for a per-row checkbox <td>.
 */
export function RowCheckbox({ id, selectedIds, setSelectedIds, stopPropagation = true }) {
  return (
    <input type="checkbox" className="accent-[#1a8a18] cursor-pointer" style={{ width: 16, height: 16 }}
      checked={selectedIds.has(id)}
      onClick={stopPropagation ? e => e.stopPropagation() : undefined}
      onChange={e => {
        const next = new Set(selectedIds)
        if (e.target.checked) next.add(id); else next.delete(id)
        setSelectedIds(next)
      }} />
  )
}

/**
 * Status dropdown that triggers an action on change.
 */
export function BulkStatusSelect({ label, options, onChange, disabled }) {
  return (
    <select disabled={disabled} defaultValue=""
      onChange={e => { const v = e.target.value; if (v) { onChange(v); e.target.value = '' } }}
      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none disabled:opacity-50"
      style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
      <option value="">{label}</option>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}
