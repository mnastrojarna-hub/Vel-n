// Položka seznamu konverzací na mobilu/tabletu (≤ 1023 px) — celá řádka je dotyková plocha.

// Dnes → HH:mm, jinak „d. M.“ (u jiného roku i rok).
function shortTime(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  const now = new Date()
  if (d.toDateString() === now.toDateString()) {
    return d.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' })
  }
  return d.getFullYear() === now.getFullYear()
    ? `${d.getDate()}. ${d.getMonth() + 1}.`
    : `${d.getDate()}. ${d.getMonth() + 1}. ${d.getFullYear()}`
}

export default function ChatMobileThreadItem({ thread, selected, unreadCount, onClick }) {
  const hasUnread = unreadCount > 0
  const isClosed = thread.status === 'closed'
  const secondLine = thread.subject || thread.profiles?.email || ''
  return (
    <button
      type="button"
      onClick={onClick}
      className="w-full text-left cursor-pointer"
      style={{
        display: 'block',
        minHeight: 64,
        padding: '10px 14px 10px 13px',
        background: selected ? '#f1faf7' : '#fff',
        border: 'none',
        borderBottom: '1px solid #d4e8e0',
        borderLeft: selected ? '3px solid #74FB71' : '3px solid transparent',
        opacity: isClosed ? 0.65 : 1,
        color: '#0f1a14',
        font: 'inherit',
      }}
    >
      <span className="flex items-center" style={{ gap: 8, minWidth: 0 }}>
        {hasUnread && <span className="inline-block rounded-full shrink-0" style={{ width: 8, height: 8, background: '#74FB71' }} />}
        <span className="truncate" style={{ flex: '1 1 auto', minWidth: 0, fontSize: 15, fontWeight: hasUnread ? 800 : 600 }}>
          {thread.profiles?.full_name || 'Zákazník'}
        </span>
        <span className="shrink-0" style={{ fontSize: 12, color: hasUnread ? '#1a8a18' : '#1a2e22', fontWeight: hasUnread ? 800 : 500 }}>
          {shortTime(thread.last_message_at)}
        </span>
      </span>
      <span className="flex items-center" style={{ gap: 8, minWidth: 0, marginTop: 4 }}>
        <span className="truncate" style={{ flex: '1 1 auto', minWidth: 0, fontSize: 13, color: '#1a2e22', fontWeight: hasUnread ? 600 : 400 }}>
          {secondLine}
        </span>
        {isClosed && (
          <span className="shrink-0 font-bold uppercase rounded" style={{ fontSize: 11, padding: '1px 6px', background: '#f3f4f6', color: '#1a2e22' }}>
            uzavřeno
          </span>
        )}
        {hasUnread && (
          <span
            className="shrink-0 flex items-center justify-center"
            aria-label={`Nepřečtené: ${unreadCount}`}
            style={{ minWidth: 22, height: 22, borderRadius: 11, padding: '0 6px', background: '#74FB71', color: '#1a2e22', fontSize: 12, fontWeight: 800 }}
          >
            {unreadCount}
          </span>
        )}
      </span>
    </button>
  )
}
