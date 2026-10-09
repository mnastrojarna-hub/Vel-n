import AiSuggestionPanel from './AiSuggestionPanel'

// Bubliny chatu pro mobil/tablet (≤ 1023 px): čas jen HH:mm, mezi dny oddělovač „Dnes / Včera / den“.

function dayKey(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '' : d.toDateString()
}

function dayLabel(iso) {
  const d = new Date(iso)
  const today = new Date()
  const yesterday = new Date(today)
  yesterday.setDate(today.getDate() - 1)
  if (d.toDateString() === today.toDateString()) return 'Dnes'
  if (d.toDateString() === yesterday.toDateString()) return 'Včera'
  return d.toLocaleDateString('cs-CZ', { weekday: 'long', day: 'numeric', month: 'numeric', year: 'numeric' })
}

function timeLabel(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' })
}

const TEXT = { fontSize: 15, lineHeight: 1.45, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', margin: 0 }
const SHADOW = '0 2px 8px rgba(15,26,20,.06)'

function DaySeparator({ iso }) {
  return (
    <div className="flex justify-center" style={{ margin: '6px 0 2px' }}>
      <span style={{ fontSize: 12, fontWeight: 700, color: '#1a2e22', background: '#e8f3ee', padding: '4px 12px', borderRadius: 999 }}>
        {dayLabel(iso)}
      </span>
    </div>
  )
}

function Bubble({ message, threadId, currentAdminId, onAiAction, aiEdits }) {
  const isAdmin = message.direction === 'admin' || message.direction === 'outbound'
  const isSystem = message.direction === 'system'
  const isCustomer = message.direction === 'customer' || message.direction === 'inbound'

  if (isSystem) {
    return (
      <div className="flex justify-start">
        <div className="rounded-card" style={{ maxWidth: '90%', padding: '8px 12px', background: '#f3f4f6', color: '#1a2e22', boxShadow: SHADOW }}>
          <div className="flex items-start" style={{ gap: 8 }}>
            <span style={{ fontSize: 14 }}>&#x1F916;</span>
            <p style={{ ...TEXT, fontSize: 14 }}>{message.content}</p>
          </div>
          <div style={{ fontSize: 11, marginTop: 4, textAlign: 'right', color: '#1a2e22' }}>{timeLabel(message.created_at)}</div>
        </div>
      </div>
    )
  }

  const bubble = (
    <div
      className="rounded-card"
      style={{
        width: 'fit-content',
        maxWidth: '100%',
        padding: '8px 12px',
        background: isAdmin ? '#74FB71' : '#fff',
        color: isAdmin ? '#1a2e22' : '#0f1a14',
        boxShadow: SHADOW,
        marginLeft: isAdmin ? 'auto' : 0,
      }}
    >
      <p style={TEXT}>{message.content}</p>
      <div style={{ fontSize: 11, marginTop: 2, textAlign: 'right', color: isAdmin ? '#1a6a18' : '#1a2e22' }}>
        {timeLabel(message.created_at)}
      </div>
    </div>
  )

  if (isCustomer) {
    // Pevná šířka obalu — pod bublinou je místo pro panel s AI návrhem.
    return (
      <div className="flex justify-start">
        <div style={{ width: 'min(88%, 560px)', minWidth: 0 }}>
          {bubble}
          <AiSuggestionPanel
            mobile
            message={message}
            threadId={threadId}
            currentAdminId={currentAdminId}
            onApprovedSent={onAiAction}
            editDrafts={aiEdits}
          />
        </div>
      </div>
    )
  }

  return (
    <div className={`flex ${isAdmin ? 'justify-end' : 'justify-start'}`}>
      <div style={{ maxWidth: 'min(85%, 560px)', minWidth: 0 }}>{bubble}</div>
    </div>
  )
}

export default function ChatMobileMessages({ messages, threadId, currentAdminId, onAiAction, aiEdits }) {
  let lastDay = null
  const items = []
  for (const m of messages) {
    const key = dayKey(m.created_at)
    if (key && key !== lastDay) {
      items.push(<DaySeparator key={`day-${key}`} iso={m.created_at} />)
      lastDay = key
    }
    items.push(
      <Bubble key={m.id} message={m} threadId={threadId} currentAdminId={currentAdminId} onAiAction={onAiAction} aiEdits={aiEdits} />
    )
  }
  return items
}
