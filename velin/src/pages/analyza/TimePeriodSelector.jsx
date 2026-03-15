import { useState, useMemo } from 'react'

const MONTHS_CS = ['Leden','Únor','Březen','Duben','Květen','Červen','Červenec','Srpen','Září','Říjen','Listopad','Prosinec']

// Fiscal year = Apr–Mar (Czech accounting)
function getFiscalYearRange(year) {
  return { from: new Date(year - 1, 3, 1), to: new Date(year, 2, 31, 23, 59, 59) }
}

export function getTimePeriodLabel(period) {
  if (period.type === 'all') return 'Celkem'
  if (period.type === 'month') return `${MONTHS_CS[period.month]} ${period.year}`
  if (period.type === 'calendar_year') return `Rok ${period.year}`
  if (period.type === 'fiscal_year') return `Účetní rok ${period.year - 1}/${period.year}`
  if (period.type === 'custom') return `${period.from} — ${period.to}`
  return ''
}

export function filterByPeriod(items, period, dateField = 'created_at') {
  if (period.type === 'all') return items
  let from, to
  if (period.type === 'month') {
    from = new Date(period.year, period.month, 1)
    to = new Date(period.year, period.month + 1, 0, 23, 59, 59)
  } else if (period.type === 'calendar_year') {
    from = new Date(period.year, 0, 1)
    to = new Date(period.year, 11, 31, 23, 59, 59)
  } else if (period.type === 'fiscal_year') {
    const r = getFiscalYearRange(period.year)
    from = r.from; to = r.to
  } else if (period.type === 'custom') {
    from = new Date(period.from)
    to = new Date(period.to + 'T23:59:59')
  }
  return items.filter(item => {
    const d = new Date(item[dateField])
    return d >= from && d <= to
  })
}

export function hasMinimumData(bookings, monthsRequired = 3) {
  if (!bookings || bookings.length === 0) return false
  const dates = bookings.map(b => new Date(b.created_at || b.start_date)).filter(d => !isNaN(d))
  if (dates.length === 0) return false
  const oldest = Math.min(...dates)
  const diffMs = Date.now() - oldest
  const diffMonths = diffMs / (1000 * 60 * 60 * 24 * 30)
  return diffMonths >= monthsRequired
}

export function diffDays(start, end) {
  return Math.max(1, Math.round((new Date(end) - new Date(start)) / 86400000))
}

export default function TimePeriodSelector({ value, onChange }) {
  const [showCustom, setShowCustom] = useState(value.type === 'custom')
  const now = new Date()
  const currentYear = now.getFullYear()
  const currentMonth = now.getMonth()

  const years = useMemo(() => {
    const arr = []
    for (let y = currentYear; y >= currentYear - 5; y--) arr.push(y)
    return arr
  }, [currentYear])

  const btnStyle = (active) => ({
    padding: '6px 14px', borderRadius: 8, border: 'none', cursor: 'pointer',
    fontSize: 12, fontWeight: 700,
    background: active ? '#74FB71' : '#f1faf7', color: '#1a2e22',
    boxShadow: active ? '0 2px 8px rgba(116,251,113,.3)' : 'none',
  })

  const selStyle = {
    padding: '6px 10px', borderRadius: 8, border: '1px solid #d4e8e0',
    background: '#f1faf7', color: '#1a2e22', fontSize: 12, fontWeight: 600, cursor: 'pointer',
  }

  return (
    <div className="flex flex-wrap items-center gap-2 mb-5" style={{ background: '#fff', borderRadius: 12, padding: '10px 14px', boxShadow: '0 1px 4px rgba(0,0,0,.04)' }}>
      <span className="text-xs font-bold uppercase" style={{ color: '#888', letterSpacing: 1 }}>Období:</span>

      <button style={btnStyle(value.type === 'all')} onClick={() => { setShowCustom(false); onChange({ type: 'all' }) }}>Celkem</button>

      <button style={btnStyle(value.type === 'month')} onClick={() => { setShowCustom(false); onChange({ type: 'month', year: currentYear, month: currentMonth }) }}>Měsíc</button>
      {value.type === 'month' && (
        <>
          <select value={value.month} onChange={e => onChange({ ...value, month: Number(e.target.value) })} style={selStyle}>
            {MONTHS_CS.map((m, i) => <option key={i} value={i}>{m}</option>)}
          </select>
          <select value={value.year} onChange={e => onChange({ ...value, year: Number(e.target.value) })} style={selStyle}>
            {years.map(y => <option key={y} value={y}>{y}</option>)}
          </select>
        </>
      )}

      <button style={btnStyle(value.type === 'calendar_year')} onClick={() => { setShowCustom(false); onChange({ type: 'calendar_year', year: currentYear }) }}>Kalendářní rok</button>
      {value.type === 'calendar_year' && (
        <select value={value.year} onChange={e => onChange({ ...value, year: Number(e.target.value) })} style={selStyle}>
          {years.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
      )}

      <button style={btnStyle(value.type === 'fiscal_year')} onClick={() => { setShowCustom(false); onChange({ type: 'fiscal_year', year: currentYear }) }}>Účetní rok</button>
      {value.type === 'fiscal_year' && (
        <select value={value.year} onChange={e => onChange({ ...value, year: Number(e.target.value) })} style={selStyle}>
          {years.map(y => <option key={y} value={y}>{`${y - 1}/${y}`}</option>)}
        </select>
      )}

      <button style={btnStyle(value.type === 'custom')} onClick={() => { setShowCustom(true); onChange({ type: 'custom', from: '', to: '' }) }}>Vlastní</button>
      {value.type === 'custom' && (
        <>
          <input type="date" value={value.from || ''} onChange={e => onChange({ ...value, from: e.target.value })} style={selStyle} />
          <span className="text-xs font-bold" style={{ color: '#888' }}>—</span>
          <input type="date" value={value.to || ''} onChange={e => onChange({ ...value, to: e.target.value })} style={selStyle} />
        </>
      )}
    </div>
  )
}
