import { useState } from 'react'
import SearchInput from '../../components/ui/SearchInput'

// Mobilní filtry logu zpráv: hledání + tlačítko „Filtry" se skládacím panelem.
const LABEL = { fontSize: 11, color: '#1a2e22', marginBottom: 6 }
const FIELD = {
  width: '100%', minWidth: 0, minHeight: 44, padding: '8px 12px',
  background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', display: 'block',
}

export function countActiveFilters(filters, typeOptions) {
  let n = 0
  if (filters.statuses?.length > 0) n++
  if (filters.type && filters.type !== 'all' && typeOptions.some(o => o.value === filters.type)) n++
  if (filters.dateFrom) n++
  if (filters.dateTo) n++
  if (filters.sort && filters.sort !== 'date_desc') n++
  return n
}

export default function MessageLogMobileFilters({ channel, filters, setFilters, typeOptions, statusOptions, onReset }) {
  const [open, setOpen] = useState(false)
  const active = countActiveFilters(filters, typeOptions)
  const statuses = filters.statuses || []

  function toggleStatus(val) {
    const next = statuses.includes(val) ? statuses.filter(v => v !== val) : [...statuses, val]
    setFilters(f => ({ ...f, statuses: next }))
  }

  return (
    <div className="mb-3">
      <div className="flex items-center" style={{ gap: 8 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <SearchInput
            fullWidth
            value={filters.search}
            onChange={v => setFilters(f => ({ ...f, search: v }))}
            placeholder={channel === 'email' ? 'Hledat email, obsah…' : 'Hledat telefon, obsah…'}
          />
        </div>
        <button
          type="button"
          onClick={() => setOpen(o => !o)}
          aria-expanded={open}
          className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer shrink-0 flex items-center"
          style={{
            minHeight: 42, padding: '8px 12px', fontSize: 13, gap: 6, color: '#1a2e22',
            background: open || active > 0 ? '#e8fee7' : '#f1faf7',
            border: `1px solid ${active > 0 ? '#74FB71' : '#d4e8e0'}`,
          }}
        >
          Filtry
          {active > 0 && (
            <span className="font-extrabold" style={{ background: '#74FB71', color: '#0f1a14', borderRadius: 50, minWidth: 20, height: 20, fontSize: 12, lineHeight: '20px', textAlign: 'center', padding: '0 5px' }}>
              {active}
            </span>
          )}
          <span aria-hidden style={{ fontSize: 10 }}>{open ? '▲' : '▼'}</span>
        </button>
      </div>

      {open && (
        <div className="bg-white rounded-card shadow-card" style={{ padding: 14, marginTop: 10 }}>
          <div className="font-extrabold uppercase tracking-wide" style={LABEL}>Stav</div>
          <div className="flex flex-wrap" style={{ gap: 8 }}>
            {statusOptions.map(o => {
              const on = statuses.includes(o.value)
              return (
                <label key={o.value} className="flex items-center cursor-pointer rounded-btn"
                  style={{ minHeight: 40, padding: '6px 12px', gap: 8, background: on ? '#74FB71' : '#f1faf7', border: `1px solid ${on ? '#74FB71' : '#d4e8e0'}` }}>
                  <input type="checkbox" checked={on} onChange={() => toggleStatus(o.value)}
                    className="accent-[#1a8a18]" style={{ width: 18, height: 18 }} />
                  <span className="font-bold" style={{ fontSize: 14, color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
                </label>
              )
            })}
          </div>

          <label className="block" style={{ marginTop: 14 }}>
            <div className="font-extrabold uppercase tracking-wide" style={LABEL}>Typ</div>
            <select
              value={typeOptions.some(o => o.value === filters.type) ? filters.type : 'all'}
              onChange={e => setFilters(f => ({ ...f, type: e.target.value }))}
              className="rounded-btn font-bold cursor-pointer outline-none"
              style={FIELD}
            >
              {typeOptions.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </label>

          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)', gap: 10, marginTop: 14 }}>
            <label className="block" style={{ minWidth: 0 }}>
              <div className="font-extrabold uppercase tracking-wide" style={LABEL}>Od</div>
              <input type="date" value={filters.dateFrom}
                onChange={e => setFilters(f => ({ ...f, dateFrom: e.target.value }))}
                className="rounded-btn outline-none" style={FIELD} />
            </label>
            <label className="block" style={{ minWidth: 0 }}>
              <div className="font-extrabold uppercase tracking-wide" style={LABEL}>Do</div>
              <input type="date" value={filters.dateTo}
                onChange={e => setFilters(f => ({ ...f, dateTo: e.target.value }))}
                className="rounded-btn outline-none" style={FIELD} />
            </label>
          </div>

          <label className="block" style={{ marginTop: 14 }}>
            <div className="font-extrabold uppercase tracking-wide" style={LABEL}>Řazení</div>
            <select
              value={filters.sort}
              onChange={e => setFilters(f => ({ ...f, sort: e.target.value }))}
              className="rounded-btn font-bold cursor-pointer outline-none"
              style={FIELD}
            >
              <option value="date_desc">Datum ↓ nejnovější</option>
              <option value="date_asc">Datum ↑ nejstarší</option>
            </select>
          </label>

          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)', gap: 10, marginTop: 16 }}>
            <button
              type="button"
              onClick={onReset}
              className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer"
              style={{ minHeight: 44, fontSize: 13, background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}
            >
              Reset
            </button>
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer"
              style={{ minHeight: 44, fontSize: 13, background: '#74FB71', border: '1px solid #74FB71', color: '#0f1a14' }}
            >
              Hotovo
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
