const DAY_NAMES = ['Po', 'Ut', 'St', 'Ct', 'Pa', 'So', 'Ne']
const MONTH_NAMES = ['Leden', 'Unor', 'Brezen', 'Duben', 'Kveten', 'Cerven', 'Cervenec', 'Srpen', 'Zari', 'Rijen', 'Listopad', 'Prosinec']

function sameDay(a, b) { return a && b && isoDate(a) === isoDate(b) }
function isoDate(d) {
  if (!d) return ''
  if (typeof d === 'string') return d.slice(0, 10)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export default function BookingCalendar({ calMonth, setCalMonth, calStep, startDate, endDate, origStart, origEnd, onCalClick }) {
  const { m, y } = calMonth
  const firstDay = new Date(y, m, 1)
  let startIdx = firstDay.getDay() - 1; if (startIdx < 0) startIdx = 6
  const daysInMonth = new Date(y, m + 1, 0).getDate()
  const today = new Date(); today.setHours(0, 0, 0, 0)
  const cells = []
  for (let i = 0; i < startIdx; i++) cells.push(null)
  for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(y, m, d))

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <button onClick={() => setCalMonth(p => p.m === 0 ? { m: 11, y: p.y - 1 } : { m: p.m - 1, y: p.y })}
          className="cursor-pointer text-sm font-bold" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 10px', color: '#1a2e22' }}>&#8592;</button>
        <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{MONTH_NAMES[m]} {y}</span>
        <button onClick={() => setCalMonth(p => p.m === 11 ? { m: 0, y: p.y + 1 } : { m: p.m + 1, y: p.y })}
          className="cursor-pointer text-sm font-bold" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 10px', color: '#1a2e22' }}>&#8594;</button>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2 }}>
        {DAY_NAMES.map(n => <div key={n} className="text-sm font-bold text-center" style={{ color: '#1a2e22', padding: 3 }}>{n}</div>)}
        {cells.map((date, i) => {
          if (!date) return <div key={`e${i}`} />
          const past = date < today
          const isStart = sameDay(date, startDate)
          const isEnd = sameDay(date, endDate)
          const isInRange = startDate && endDate && date >= startDate && date <= endDate
          const isSelected = isStart || isEnd
          const isOrigRange = date >= origStart && date <= origEnd && !isInRange

          let bg = '#fff', color = '#0f1a14', border = '1px solid #e5e7eb', fontWeight = 500
          if (past) { color = '#d1d5db'; border = '1px solid #f3f4f6' }
          else if (isSelected) { bg = '#74FB71'; color = '#0f1a14'; border = '2px solid #3dba3a'; fontWeight = 800 }
          else if (isInRange) { bg = '#d1fae5'; border = '1px solid #a7f3d0' }
          else if (isOrigRange) { bg = '#fef3c7'; border = '1px solid #fde68a' }

          const isOrigStart = sameDay(date, origStart)
          const isOrigEnd = sameDay(date, origEnd)

          return (
            <button key={i} disabled={past || calStep === 0}
              onClick={() => !past && calStep > 0 && onCalClick(date)}
              className="text-sm text-center" style={{
                background: bg, color, border, borderRadius: 6, padding: '6px 0', fontWeight,
                opacity: past ? 0.35 : calStep === 0 ? 0.7 : 1,
                cursor: past || calStep === 0 ? 'default' : 'pointer',
                position: 'relative',
              }}>
              {date.getDate()}
              {(isOrigStart || isOrigEnd) && !isSelected && (
                <div style={{ position: 'absolute', bottom: 1, left: '50%', transform: 'translateX(-50%)', width: 4, height: 4, borderRadius: '50%', background: '#f59e0b' }} />
              )}
            </button>
          )
        })}
      </div>
      <div className="flex items-center gap-4 mt-2 text-xs" style={{ color: '#1a2e22' }}>
        <span><span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 2, background: '#fef3c7', border: '1px solid #fde68a', verticalAlign: 'middle', marginRight: 3 }} />Puvodni termin</span>
        <span><span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 2, background: '#d1fae5', border: '1px solid #a7f3d0', verticalAlign: 'middle', marginRight: 3 }} />Novy termin</span>
      </div>
    </div>
  )
}
