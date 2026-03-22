import { CANCEL_SOURCE_LABELS } from './bookingConstants'

export default function Timeline({ booking }) {
  const steps = [
    { label: 'Vytvořeno', done: true, time: booking.created_at },
    { label: 'Rezervováno', done: ['reserved', 'active', 'completed'].includes(booking.status), time: booking.confirmed_at },
    { label: 'Vydáno', done: ['active', 'completed'].includes(booking.status) && !!booking.picked_up_at, time: booking.picked_up_at },
    { label: 'Vráceno', done: booking.status === 'completed', time: booking.returned_at },
  ]

  if (booking.status === 'cancelled') {
    const sourceLabel = CANCEL_SOURCE_LABELS[booking.cancelled_by_source] || booking.cancelled_by_source || ''
    return (
      <div>
        <div className="flex items-center gap-6 mb-4">
          {steps.filter(s => s.done || s.time).map((s, i) => (
            <div key={s.label} className="flex flex-col items-center">
              <div className="rounded-full flex items-center justify-center" style={{ width: 28, height: 28, background: '#74FB71' }}>
                <span style={{ fontSize: 14 }}>✓</span>
              </div>
              <span className="text-sm font-extrabold uppercase tracking-wide mt-1" style={{ color: '#1a8a18' }}>{s.label}</span>
              {s.time && <span className="text-[9px] mt-0.5" style={{ color: '#1a2e22' }}>{new Date(s.time).toLocaleString('cs-CZ')}</span>}
            </div>
          ))}
        </div>
        <div className="p-4 rounded-lg" style={{ background: '#fee2e2' }}>
          <span style={{ color: '#dc2626', fontWeight: 700, fontSize: 13 }}>Zrušena</span>
          {booking.cancelled_at && <span className="ml-3 text-sm" style={{ color: '#dc2626' }}>{new Date(booking.cancelled_at).toLocaleString('cs-CZ')}</span>}
          {sourceLabel && <span className="ml-3 text-sm font-bold" style={{ color: '#991b1b' }}>— {sourceLabel}</span>}
        </div>
      </div>
    )
  }
  return (
    <div className="flex items-start">
      {steps.map((s, i) => (
        <div key={s.label} className="flex items-center">
          <div className="flex flex-col items-center">
            <div className="rounded-full flex items-center justify-center" style={{ width: 28, height: 28, background: s.done ? '#74FB71' : '#f1faf7', border: s.done ? 'none' : '2px solid #d4e8e0' }}>
              {s.done && <span style={{ fontSize: 14 }}>✓</span>}
            </div>
            <span className="text-sm font-extrabold uppercase tracking-wide mt-1" style={{ color: s.done ? '#1a8a18' : '#1a2e22' }}>{s.label}</span>
            {s.time && <span className="text-[9px] mt-0.5" style={{ color: '#1a2e22' }}>{new Date(s.time).toLocaleString('cs-CZ')}</span>}
          </div>
          {i < steps.length - 1 && <div style={{ width: 60, height: 2, background: s.done ? '#74FB71' : '#d4e8e0', margin: '0 4px', marginBottom: 20 }} />}
        </div>
      ))}
    </div>
  )
}
