/**
 * Analýza → AI konverzace — přepínač zdroje:
 *  - „Web widget"      → ai_public_conversations (anonymní agent na motogo24.cz)
 *  - „AI agent (appka)" → ai_customer_conversations (přihlášení zákazníci v mobilní appce)
 */
import { useState } from 'react'
import AiPublicConversations from './AiPublicConversations'
import AiAppConversations from './AiAppConversations'

const SOURCES = [
  { id: 'web', label: 'Web widget' },
  { id: 'app', label: 'AI agent (appka)' },
]

export default function AiConversations() {
  const [source, setSource] = useState('web')
  return (
    <div>
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        <h2 className="text-xl font-extrabold" style={{ color: '#1a2e22', marginRight: 8 }}>AI konverzace</h2>
        {SOURCES.map(s => (
          <button key={s.id} onClick={() => setSource(s.id)}
            className="rounded-btn text-xs font-bold cursor-pointer"
            style={{ padding: '6px 14px', background: source === s.id ? '#1a2e22' : '#f1faf7', color: source === s.id ? '#74FB71' : '#1a2e22', border: 'none' }}>
            {s.label}
          </button>
        ))}
      </div>
      {source === 'web' ? <AiPublicConversations /> : <AiAppConversations />}
    </div>
  )
}
