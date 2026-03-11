import { useState, useEffect, useRef } from 'react'
import { addLogListener, getLogBuffer, clearLogBuffer, exportLogText } from '../lib/debugLog'

export default function DebugPanel() {
  const [open, setOpen] = useState(false)
  const [logs, setLogs] = useState(() => getLogBuffer())
  const [filter, setFilter] = useState('all')
  const [copied, setCopied] = useState(false)
  const logRef = useRef(null)

  useEffect(() => {
    return addLogListener(setLogs)
  }, [])

  const errorCount = logs.filter(l => l.status === 'error').length

  const filtered = filter === 'all' ? logs : logs.filter(l => l.status === filter)

  function handleCopy() {
    const text = exportLogText()
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="fixed bottom-4 right-4 z-50 rounded-full cursor-pointer"
        style={{
          padding: '8px 16px',
          background: errorCount > 0 ? '#dc2626' : '#1a2e22',
          color: '#fff',
          border: 'none',
          fontSize: 13,
          fontWeight: 800,
          boxShadow: '0 4px 16px rgba(0,0,0,.3)',
        }}
      >
        {errorCount > 0 ? `${errorCount} ERR` : 'LOG'} ({logs.length})
      </button>
    )
  }

  return (
    <div
      className="fixed bottom-0 left-0 right-0 z-50"
      style={{
        height: 320,
        background: '#0f1a14',
        borderTop: '2px solid #74FB71',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      {/* Header */}
      <div className="flex items-center gap-2 px-3 py-2" style={{ borderBottom: '1px solid #1a3a28' }}>
        <span style={{ color: '#74FB71', fontSize: 13, fontWeight: 800 }}>DEBUG LOG</span>
        <span style={{ color: '#1a2e22', fontSize: 13 }}>{logs.length} zazn.</span>

        {/* Filters */}
        {['all', 'error', 'success', 'info'].map(f => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className="cursor-pointer"
            style={{
              padding: '2px 8px',
              fontSize: 9,
              fontWeight: 800,
              textTransform: 'uppercase',
              border: 'none',
              borderRadius: 4,
              background: filter === f ? (f === 'error' ? '#dc2626' : f === 'success' ? '#1a8a18' : '#1a2e22') : 'transparent',
              color: filter === f ? '#fff' : '#1a2e22',
            }}
          >
            {f === 'all' ? `Vse (${logs.length})` : f === 'error' ? `Err (${logs.filter(l => l.status === 'error').length})` : f === 'success' ? `OK (${logs.filter(l => l.status === 'success').length})` : `Info (${logs.filter(l => l.status === 'info').length})`}
          </button>
        ))}

        <div className="ml-auto flex gap-2">
          <button
            onClick={handleCopy}
            className="cursor-pointer"
            style={{ padding: '3px 10px', fontSize: 13, fontWeight: 800, background: copied ? '#1a8a18' : '#2563eb', color: '#fff', border: 'none', borderRadius: 4 }}
          >
            {copied ? 'Zkopirovano!' : 'Kopirovat log'}
          </button>
          <button
            onClick={() => clearLogBuffer()}
            className="cursor-pointer"
            style={{ padding: '3px 10px', fontSize: 13, fontWeight: 800, background: '#1a2e22', color: '#fff', border: 'none', borderRadius: 4 }}
          >
            Smazat
          </button>
          <button
            onClick={() => setOpen(false)}
            className="cursor-pointer"
            style={{ padding: '3px 10px', fontSize: 13, fontWeight: 800, background: '#dc2626', color: '#fff', border: 'none', borderRadius: 4 }}
          >
            Zavrit
          </button>
        </div>
      </div>

      {/* Log entries */}
      <div ref={logRef} className="flex-1 overflow-auto px-3 py-1" style={{ fontFamily: 'monospace', fontSize: 13, lineHeight: 1.6 }}>
        {filtered.length === 0 && (
          <div style={{ color: '#1a2e22', padding: 20, textAlign: 'center' }}>Zadne zaznamy</div>
        )}
        {filtered.map(e => (
          <LogEntry key={e.id} entry={e} />
        ))}
      </div>
    </div>
  )
}

function LogEntry({ entry: e }) {
  const [expanded, setExpanded] = useState(false)
  const time = e.created_at?.slice(11, 19) || ''
  const statusColor = e.status === 'error' ? '#ef4444' : e.status === 'success' ? '#22c55e' : e.status === 'warning' ? '#f59e0b' : '#6b7280'
  const statusLabel = e.status === 'error' ? 'ERR' : e.status === 'success' ? 'OK' : e.status === 'warning' ? 'WARN' : 'INFO'

  return (
    <div
      onClick={() => setExpanded(!expanded)}
      className="cursor-pointer"
      style={{
        padding: '3px 0',
        borderBottom: '1px solid #1a3a28',
        color: '#d4e8e0',
      }}
    >
      <div className="flex items-center gap-2">
        <span style={{ color: '#1a2e22', minWidth: 55 }}>{time}</span>
        <span style={{ color: statusColor, fontWeight: 800, minWidth: 35 }}>{statusLabel}</span>
        {e.duration_ms > 0 && <span style={{ color: e.duration_ms > 2000 ? '#f59e0b' : '#1a2e22', minWidth: 40 }}>{e.duration_ms}ms</span>}
        <span style={{ color: '#74FB71', minWidth: 100 }}>{e.component || '-'}</span>
        <span style={{ color: '#d4e8e0' }}>{e.action}</span>
        {e.error_message && <span style={{ color: '#ef4444', marginLeft: 8 }}>{e.error_message.slice(0, 60)}</span>}
      </div>
      {expanded && (
        <div style={{ padding: '4px 0 4px 60px', fontSize: 13, color: '#1a2e22' }}>
          {e.error_message && <div style={{ color: '#ef4444' }}>ERROR: {e.error_message}</div>}
          {e.error_stack && <pre style={{ color: '#b45309', margin: '2px 0', whiteSpace: 'pre-wrap' }}>{e.error_stack}</pre>}
          {e.request_data && <div>REQ: {JSON.stringify(e.request_data).slice(0, 500)}</div>}
          {e.response_data && <div>RESP: {JSON.stringify(e.response_data).slice(0, 500)}</div>}
        </div>
      )}
    </div>
  )
}
