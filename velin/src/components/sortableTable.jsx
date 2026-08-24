import { useState } from 'react'

// Sdílené klikací řazení tabulek v Analýze. Sloupec: { label, key, str?, value? }
// — str = textové řazení (česká abeceda, 1. klik A→Z), jinak číselné (1. klik sestupně);
// value(row) = getter, když hodnota není přímo row[key]. Sloupec bez key se neřadí.
// Prázdné hodnoty (null/undefined/NaN) jsou vždy na konci bez ohledu na směr.

export function useTableSort(columns, initial = null) {
  const [sort, setSort] = useState(initial)
  const toggle = key => {
    const c = columns.find(x => x.key === key)
    setSort(s => (s?.key === key ? { key, dir: s.dir === 'desc' ? 'asc' : 'desc' } : { key, dir: c?.str ? 'asc' : 'desc' }))
  }
  return { sort, toggle }
}

export function sortRows(rows, columns, sort) {
  if (!sort?.key) return rows
  const c = columns.find(x => x.key === sort.key) || {}
  const dir = sort.dir === 'asc' ? 1 : -1
  const val = c.value || (r => r[sort.key])
  return [...rows].sort((a, b) => {
    const av = val(a), bv = val(b)
    if (c.str) return dir * String(av ?? '').localeCompare(String(bv ?? ''), 'cs')
    const an = av == null || Number.isNaN(Number(av)) ? null : Number(av)
    const bn = bv == null || Number.isNaN(Number(bv)) ? null : Number(bv)
    if (an == null && bn == null) return 0
    if (an == null) return 1
    if (bn == null) return -1
    return dir * (an - bn)
  })
}

export function SortableHeaderRow({ columns, sort, toggle, thStyle = { color: '#1a2e22' } }) {
  return (
    <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
      {columns.map(c => c.key ? (
        <th key={c.key} className="text-left font-bold py-2 px-3" title={c.title || 'Seřadit dle sloupce'}
            style={{ ...thStyle, cursor: 'pointer', userSelect: 'none', whiteSpace: 'nowrap' }}
            onClick={() => toggle(c.key)}>
          {c.label}{sort?.key === c.key ? (sort.dir === 'desc' ? ' ▼' : ' ▲') : ''}
        </th>
      ) : (
        <th key={c.label} className="text-left font-bold py-2 px-3" style={thStyle} title={c.title}>{c.label}</th>
      ))}
    </tr>
  )
}
