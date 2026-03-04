import { useState } from 'react'
import ThreadList from './messages/ThreadList'
import ChatPanel from './messages/ChatPanel'

export default function Messages() {
  const [selected, setSelected] = useState(null)

  return (
    <div className="flex bg-white rounded-card shadow-card overflow-hidden" style={{ height: 'calc(100vh - 140px)' }}>
      {/* Thread list — left panel */}
      <div className="flex-shrink-0" style={{ width: 320, borderRight: '1px solid #d4e8e0' }}>
        <ThreadList selectedId={selected?.id} onSelect={setSelected} />
      </div>

      {/* Chat — right panel */}
      <div className="flex-1">
        <ChatPanel thread={selected} />
      </div>
    </div>
  )
}
