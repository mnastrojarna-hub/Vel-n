// Mobilní (≤ 1023 px) přepínače sekce Zprávy: kanály jako stejné segmenty v jedné řadě,
// pod-záložky jako zalamovaná řada (všech 5 vždy vidět). Desktop je nepoužívá.
// Sloupce = počet kanálů; min-content: delší popisek (WhatsApp, Hodnocení) si na 360 px vezme
// šířku textu a ostatní segmenty se o zbytek podělí rovným dílem (žádné přetečení popisku).
// badges = { [kanál]: počet } → červený odznak v rohu segmentu (např. nevyřízená hodnocení).

export function ChatMobileChannelTabs({ channels, active, onSelect, badges = {} }) {
  return (
    <div className="mb-3" style={{ display: 'grid', gridTemplateColumns: `repeat(${channels.length}, minmax(min-content, 1fr))`, gap: 6 }}>
      {channels.map(ch => {
        const on = active === ch.key
        const badge = badges[ch.key] || 0
        return (
          <button
            key={ch.key}
            type="button"
            onClick={() => onSelect(ch.key)}
            aria-pressed={on}
            className="rounded-btn font-extrabold uppercase cursor-pointer flex flex-col items-center justify-center"
            style={{
              position: 'relative',
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
            {badge > 0 && (
              <span aria-label={`${badge} k vyřízení`} style={{ position: 'absolute', top: 2, right: 2, minWidth: 18, height: 18, padding: '0 5px', borderRadius: 9, background: '#dc2626', color: '#fff', fontSize: 10, lineHeight: '18px', textAlign: 'center' }}>
                {badge > 99 ? '99+' : badge}
              </span>
            )}
            <span style={{ fontSize: 18, lineHeight: 1 }}>{ch.icon}</span>
            <span style={{ fontSize: 11, lineHeight: 1.2, letterSpacing: 'normal', whiteSpace: 'nowrap' }}>{ch.label}</span>
          </button>
        )
      })}
    </div>
  )
}

export function ChatMobileSubTabs({ tabs, active, onSelect }) {
  // Zalamování místo vodorovného posouvání: na 360 px by Kampaně a Šablony byly schované mimo displej.
  return (
    <div className="flex flex-wrap mb-3" style={{ gap: 6 }}>
      {tabs.map(st => {
        const on = active === st.key
        return (
          <button
            key={st.key}
            type="button"
            onClick={() => onSelect(st.key)}
            aria-pressed={on}
            className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer flex-shrink-0 whitespace-nowrap"
            style={{
              minHeight: 40,
              padding: '6px 12px',
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
