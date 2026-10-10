import { useState } from 'react'
import Card from '../../components/ui/Card'

// Směny na telefonu (< 640 px): týdenní mřížka 8 sloupců se na šířku nevejde → výběr dne
// (Po–Ne vybraného týdne) a seznam zaměstnanců se směnou v daném dni. Klepnutí otevře
// stejný ShiftModal jako buňka mřížky (onOpen = setShowAdd v ShiftsTab). Desktop/tablet beze změny.
export default function EmpShiftsDayMobile({ weekDates, employees, shiftMap, shiftTypes, dayNames, onOpen }) {
  const [day, setDay] = useState(() => Math.max(0, weekDates.indexOf(new Date().toISOString().slice(0, 10))))
  const date = weekDates[day]

  return (
    <div>
      <div className="grid grid-cols-7 gap-1 mb-3">
        {weekDates.map((d, i) => (
          <button key={d} onClick={() => setDay(i)} className="rounded-xl cursor-pointer text-center"
            style={{
              padding: '6px 0', minHeight: 48, border: 'none',
              background: i === day ? '#74FB71' : '#fff',
              boxShadow: i === day ? '0 4px 16px rgba(116,251,113,.35)' : '0 2px 8px rgba(15,26,20,.08)',
            }}>
            <span className="block text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>{dayNames[i]}</span>
            <span className="block text-xs font-bold" style={{ color: i === day ? '#1a2e22' : '#4a6357' }}>
              {new Date(d).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric' })}
            </span>
          </button>
        ))}
      </div>

      <Card className="overflow-hidden" style={{ padding: 0 }}>
        {employees.map((emp, i) => {
          const shift = shiftMap[`${emp.id}_${date}`]
          const st = shift ? shiftTypes[shift.shift_type] : null
          return (
            <button key={emp.id} onClick={() => onOpen({ empId: emp.id, date, shift })}
              className="w-full flex items-center justify-between gap-3 text-left cursor-pointer"
              style={{ padding: '10px 14px', minHeight: 56, background: 'none', border: 'none', borderTop: i ? '1px solid #d4e8e0' : 'none' }}>
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{emp.name}</span>
              <span className="rounded-lg text-center shrink-0"
                style={{ minWidth: 112, padding: '6px 10px', background: st ? st.bg : '#f9fafb', border: `1px solid ${st ? st.color + '30' : '#e5e7eb'}` }}>
                {shift ? <>
                  <span className="block text-xs font-bold" style={{ color: st?.color }}>{st?.label}</span>
                  {shift.start_time && <span className="block text-xs" style={{ color: '#6b7280' }}>{shift.start_time?.slice(0, 5)}-{shift.end_time?.slice(0, 5)}</span>}
                </> : <span className="block text-sm" style={{ color: '#9ca3af' }}>+</span>}
              </span>
            </button>
          )
        })}
      </Card>
    </div>
  )
}
