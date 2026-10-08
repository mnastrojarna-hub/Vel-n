import { useEffect, useRef } from 'react'

// Mobilní (≤ 1023 px) přepínače sekce Zprávy: kanály jako 4 stejné segmenty v jedné řadě,
// pod-záložky jako jedna vodorovně posuvná řada. Desktop je nepoužívá.

export function ChatMobileChannelTabs({ channels, active, onSelect }) {
  return (
    <div className="mb-3" style={{ display: 'grid', gridTemplateColumns: 'repeat(4, minmax(0, 1fr))', gap: 6 }}>
      {channels.map(ch => {
        const on = active === ch.key
        return (
          <button
            key={ch.key}
            type="button"
            onClick={() => onSelect(ch.key)}
            aria-pressed={on}
            className="rounded-btn font-extrabold uppercase cursor-pointer flex flex-col items-center justify-center"
            style={{
              minHeight: 48,
              minWidth: 0,
              padding: '6px 2px',
              gap: 2,
              background: on ? '#74FB71' : '#f1faf7',
              color: '#1a2e22',
              border: 'none',
              boxShadow: on ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}
          >
            <span style={{ fontSize: 18, lineHeight: 1 }}>{ch.icon}</span>
            <span style={{ fontSize: 11, lineHeight: 1.2, letterSpacing: 'normal', whiteSpace: 'nowrap' }}>{ch.label}</span>
          </button>
        )
      })}
    </div>
  )
}

export function ChatMobileSubTabs({ tabs, active, onSelect }) {
  const rowRef = useRef(null)
  const btnRefs = useRef({})

  // Aktivní pod-záložku posuň do viditelné části řady jen vodorovně
  // (scrollIntoView by posouval i svislé předky — celou stránku).
  useEffect(() => {
    const row = rowRef.current
    const btn = btnRefs.current[active]
    if (!row || !btn) return
    const left = btn.offsetLeft // řada má position: relative → offset je vůči ní
    const right = left + btn.offsetWidth
    if (left < row.scrollLeft) row.scrollLeft = Math.max(0, left - 12)
    else if (right > row.scrollLeft + row.clientWidth) row.scrollLeft = right - row.clientWidth + 12
  }, [active])

  return (
    <div ref={rowRef} className="mg-hscroll flex mb-3" style={{ gap: 6, position: 'relative' }}>
      {tabs.map(st => {
        const on = active === st.key
        return (
          <button
            key={st.key}
            ref={el => { btnRefs.current[st.key] = el }}
            type="button"
            onClick={() => onSelect(st.key)}
            aria-pressed={on}
            className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer flex-shrink-0 whitespace-nowrap"
            style={{
              minHeight: 38,
              padding: '6px 14px',
              background: on ? '#e8fee7' : '#f1faf7',
              color: '#1a2e22',
              border: on ? '1px solid #74FB71' : '1px solid transparent',
              boxShadow: on ? '0 2px 8px rgba(116,251,113,.2)' : 'none',
            }}
          >
            {st.label}
          </button>
        )
      })}
    </div>
  )
}
