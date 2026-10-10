import { CANCEL_SOURCE_LABELS } from './bookingConstants'
import { useMediaQuery } from '../../hooks/useIsMobile'

// „Vydáno" na POBOČCE (samoobslužná i obslužná) až po podepsaném předávacím protokolu
// (2026-09-28, parita s appkou `res_modification_history._issuedAt`): same-day platba
// dřív nastavovala picked_up_at už při potvrzení. Čas = pozdější z převzetí a podpisu.
// Svoz/přistavení a starší dokončené rezervace (před protokoly) beze změny.
function issuedAt(b) {
  if (!b.picked_up_at) return null
  const type = b.motorcycles?.branches?.type
  const delivery = b.pickup_method === 'delivery' || !!(b.pickup_address || '').trim()
  if (!['obslužná', 'samoobslužná'].includes(type) || delivery) return b.picked_up_at
  if (!b.handover_protocol_filled_at) return (b.returned_at || b.status === 'completed') ? b.picked_up_at : null
  return new Date(b.picked_up_at) < new Date(b.handover_protocol_filled_at) ? b.handover_protocol_filled_at : b.picked_up_at
}

export default function Timeline({ booking }) {
  // Telefon (< 768 px): 4 kroky vedle sebe se nevejdou → svislá osa (desktop/tablet beze změny)
  const phone = useMediaQuery('(max-width: 767px)')
  const issued = issuedAt(booking)
  const steps = [
    { label: 'Vytvořeno', done: true, time: booking.created_at },
    { label: 'Rezervováno', done: ['reserved', 'active', 'completed'].includes(booking.status), time: booking.confirmed_at },
    { label: 'Vydáno', done: ['active', 'completed'].includes(booking.status) && !!issued, time: issued },
    { label: 'Vráceno', done: booking.status === 'completed', time: booking.returned_at },
  ]

  if (booking.status === 'cancelled') {
    const sourceLabel = CANCEL_SOURCE_LABELS[booking.cancelled_by_source] || booking.cancelled_by_source || ''
    const passed = steps.filter(s => s.done || s.time)
    return (
      <div>
        {phone ? <div className="mb-4"><VerticalSteps steps={passed.map(s => ({ ...s, done: true }))} /></div> : (
        <div className="flex items-center gap-6 mb-4 max-lg:flex-wrap max-lg:gap-y-3">
          {passed.map((s, i) => (
            <div key={s.label} className="flex flex-col items-center">
              <div className="rounded-full flex items-center justify-center" style={{ width: 28, height: 28, background: '#74FB71' }}>
                <span style={{ fontSize: 14 }}>✓</span>
              </div>
              <span className="text-sm font-extrabold uppercase tracking-wide mt-1" style={{ color: '#1a8a18' }}>{s.label}</span>
              {s.time && <span className="text-[9px] max-lg:text-[11px] mt-0.5" style={{ color: '#1a2e22' }}>{new Date(s.time).toLocaleString('cs-CZ')}</span>}
            </div>
          ))}
        </div>
        )}
        <div className="p-4 rounded-lg" style={{ background: '#fee2e2' }}>
          <span style={{ color: '#dc2626', fontWeight: 700, fontSize: 13 }}>Zrušena</span>
          {booking.cancelled_at && <span className="ml-3 text-sm" style={{ color: '#dc2626' }}>{new Date(booking.cancelled_at).toLocaleString('cs-CZ')}</span>}
          {sourceLabel && <span className="ml-3 text-sm font-bold" style={{ color: '#991b1b' }}>— {sourceLabel}</span>}
        </div>
      </div>
    )
  }
  if (phone) return <VerticalSteps steps={steps} />
  return (
    <div className="flex items-start">
      {steps.map((s, i) => (
        <div key={s.label} className="flex items-center">
          <div className="flex flex-col items-center">
            <div className="rounded-full flex items-center justify-center" style={{ width: 28, height: 28, background: s.done ? '#74FB71' : '#f1faf7', border: s.done ? 'none' : '2px solid #d4e8e0' }}>
              {s.done && <span style={{ fontSize: 14 }}>✓</span>}
            </div>
            <span className="text-sm font-extrabold uppercase tracking-wide mt-1" style={{ color: s.done ? '#1a8a18' : '#1a2e22' }}>{s.label}</span>
            {s.time && <span className="text-[9px] max-lg:text-[11px] mt-0.5" style={{ color: '#1a2e22' }}>{new Date(s.time).toLocaleString('cs-CZ')}</span>}
          </div>
          {i < steps.length - 1 && <div style={{ width: 60, height: 2, background: s.done ? '#74FB71' : '#d4e8e0', margin: '0 4px', marginBottom: 20 }} />}
        </div>
      ))}
    </div>
  )
}

// Telefon: kroky pod sebou (svislá osa) — běžná i zrušená rezervace stejně
function VerticalSteps({ steps }) {
  return (
    <div>
      {steps.map((s, i) => (
        <div key={s.label} className="flex items-stretch gap-3">
          <div className="flex flex-col items-center">
            <div className="rounded-full flex items-center justify-center shrink-0" style={{ width: 28, height: 28, background: s.done ? '#74FB71' : '#f1faf7', border: s.done ? 'none' : '2px solid #d4e8e0' }}>
              {s.done && <span style={{ fontSize: 14 }}>✓</span>}
            </div>
            {i < steps.length - 1 && <div style={{ width: 2, flex: 1, minHeight: 14, background: s.done ? '#74FB71' : '#d4e8e0' }} />}
          </div>
          <div className={i < steps.length - 1 ? 'pb-3' : ''} style={{ paddingTop: 4 }}>
            <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: s.done ? '#1a8a18' : '#1a2e22' }}>{s.label}</div>
            {s.time && <div className="text-xs mt-0.5" style={{ color: '#1a2e22' }}>{new Date(s.time).toLocaleString('cs-CZ')}</div>}
          </div>
        </div>
      ))}
    </div>
  )
}
