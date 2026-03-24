import { useState, useRef, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import { loadAgentConfig, getEnabledTools, getAgentCorrections, AGENTS } from '../../lib/aiAgents'
import { useAiContext, PAGE_QUICK_ACTIONS } from '../../hooks/useAiContext'
import AiConfirmDialog from './AiConfirmDialog'

function renderMd(text) {
  if (!text) return ''
  let h = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  h = h.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
  h = h.replace(/`([^`]+)`/g, '<code style="background:#f1faf7;padding:1px 4px;border-radius:3px;font-size:11px">$1</code>')
  h = h.replace(/^- (.+)$/gm, '<li style="margin-left:14px;list-style:disc;font-size:12px">$1</li>')
  h = h.replace(/\n/g, '<br/>')
  return h
}

// Parse navigation commands from AI response
function parseNavCommand(text) {
  const m = text.match(/\[NAV:([^\]]+)\]/)
  return m ? m[1].trim() : null
}

export default function FloatingAiPanel() {
  const [open, setOpen] = useState(false)
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [sending, setSending] = useState(false)
  const [pending, setPending] = useState(null)
  const [minimized, setMinimized] = useState(false)
  const bottomRef = useRef(null)
  const navigate = useNavigate()
  const ctx = useAiContext()
  const quickActions = PAGE_QUICK_ACTIONS[ctx.page] || PAGE_QUICK_ACTIONS.dashboard

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages])

  // Don't show on AI Copilot page (has its own full UI)
  if (ctx.page === 'ai') return null

  async function send(msg) {
    if (!msg || sending) return
    const config = loadAgentConfig()
    const userMsg = { role: 'user', content: msg, ts: new Date().toISOString() }
    const newMsgs = [...messages, userMsg]
    setMessages(newMsgs)
    setInput('')
    setSending(true)

    try {
      // Add page context to message
      const contextPrefix = `[Kontext: stránka "${ctx.label}"${ctx.entityId ? `, ID: ${ctx.entityId}` : ''}] `
      const { data, error } = await supabase.functions.invoke('ai-copilot', {
        body: {
          message: contextPrefix + msg,
          conversation_history: newMsgs,
          enabled_tools: getEnabledTools(config),
          agent_corrections: getAgentCorrections(config),
        },
      })
      if (error) throw error

      const aiMsg = { role: 'assistant', content: data?.response || 'Nedostupný', ts: new Date().toISOString() }
      setMessages([...newMsgs, aiMsg])

      // Check for navigation commands
      const nav = parseNavCommand(data?.response || '')
      if (nav) navigate(nav)

      // Check for pending actions
      if (data?.pending_actions?.length > 0) setPending(data.pending_actions)
    } catch {
      setMessages(m => [...m, { role: 'assistant', content: 'Chyba. Zkuste to znovu.', ts: new Date().toISOString(), err: true }])
    } finally { setSending(false) }
  }

  async function handleConfirm() {
    if (!pending) return
    setSending(true)
    try {
      const { data } = await supabase.functions.invoke('ai-copilot', { body: { mode: 'execute', actions: pending } })
      setMessages(m => [...m, { role: 'assistant', content: data?.response || 'Provedeno.', ts: new Date().toISOString() }])
    } catch (e) {
      setMessages(m => [...m, { role: 'assistant', content: `Chyba: ${e.message}`, ts: new Date().toISOString(), err: true }])
    } finally { setPending(null); setSending(false) }
  }

  // Floating button
  if (!open) return (
    <button onClick={() => setOpen(true)} title="AI Copilot" style={{
      position: 'fixed', bottom: 20, right: 20, zIndex: 9000,
      width: 52, height: 52, borderRadius: '50%', border: 'none', cursor: 'pointer',
      background: 'linear-gradient(135deg, #1a2e22, #2d5a3e)', color: '#74FB71',
      boxShadow: '0 4px 20px rgba(26,46,34,0.4)', fontSize: 22,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      transition: 'transform 0.2s',
    }} onMouseEnter={e => e.target.style.transform = 'scale(1.1)'} onMouseLeave={e => e.target.style.transform = 'scale(1)'}>
      🤖
    </button>
  )

  // Minimized bar
  if (minimized) return (
    <div style={{
      position: 'fixed', bottom: 20, right: 20, zIndex: 9000,
      background: '#1a2e22', borderRadius: 12, padding: '8px 14px',
      display: 'flex', alignItems: 'center', gap: 8, boxShadow: '0 4px 20px rgba(0,0,0,0.3)',
    }}>
      <span style={{ fontSize: 14 }}>🤖</span>
      <span style={{ color: '#74FB71', fontSize: 12, fontWeight: 600 }}>AI Copilot</span>
      {sending && <span style={{ color: '#fbbf24', fontSize: 11 }}>Pracuji...</span>}
      <button onClick={() => setMinimized(false)} style={{ color: '#74FB71', background: 'none', border: 'none', cursor: 'pointer', fontSize: 14 }}>▲</button>
      <button onClick={() => { setOpen(false); setMinimized(false) }} style={{ color: '#9ca3af', background: 'none', border: 'none', cursor: 'pointer', fontSize: 14 }}>✕</button>
    </div>
  )

  return (
    <>
      {pending && <AiConfirmDialog actions={pending} onConfirm={handleConfirm} onReject={() => { setMessages(m => [...m, { role: 'assistant', content: 'Zamítnuto.', ts: new Date().toISOString() }]); setPending(null) }} onEdit={() => { setPending(null); setInput('Uprav: ') }} />}

      <div style={{
        position: 'fixed', bottom: 20, right: 20, zIndex: 9000,
        width: 380, height: 520, borderRadius: 16, overflow: 'hidden',
        background: '#fff', boxShadow: '0 8px 40px rgba(0,0,0,0.25)',
        display: 'flex', flexDirection: 'column',
      }}>
        {/* Header */}
        <div style={{
          background: '#1a2e22', padding: '10px 14px', display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <span style={{ fontSize: 16 }}>🤖</span>
          <div style={{ flex: 1 }}>
            <div style={{ color: '#74FB71', fontSize: 13, fontWeight: 700 }}>AI Copilot</div>
            <div style={{ color: '#9ca3af', fontSize: 10 }}>{ctx.label}{ctx.entityId ? ` #${ctx.entityId.slice(-6)}` : ''}</div>
          </div>
          <button onClick={() => setMinimized(true)} style={{ color: '#9ca3af', background: 'none', border: 'none', cursor: 'pointer', fontSize: 14 }}>▼</button>
          <button onClick={() => setOpen(false)} style={{ color: '#9ca3af', background: 'none', border: 'none', cursor: 'pointer', fontSize: 14 }}>✕</button>
        </div>

        {/* Messages */}
        <div style={{ flex: 1, overflow: 'auto', padding: 10, background: '#f8fcfa' }}>
          {messages.length === 0 && (
            <div style={{ textAlign: 'center', padding: '16px 0' }}>
              <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14', marginBottom: 8 }}>
                {ctx.label} — Rychlé akce
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                {quickActions.map(q => (
                  <button key={q} onClick={() => send(q)} style={{
                    padding: '6px 10px', fontSize: 12, textAlign: 'left', borderRadius: 8,
                    border: '1px solid #d4e8e0', background: '#fff', cursor: 'pointer',
                    color: '#1a2e22', transition: 'background 0.15s',
                  }} onMouseEnter={e => e.target.style.background = '#f1faf7'} onMouseLeave={e => e.target.style.background = '#fff'}>
                    {q}
                  </button>
                ))}
              </div>
            </div>
          )}

          {messages.map((m, i) => (
            <div key={i} style={{ marginBottom: 8, display: 'flex', flexDirection: m.role === 'user' ? 'row-reverse' : 'row', gap: 6 }}>
              <div style={{
                maxWidth: '80%', padding: '8px 10px', borderRadius: 10, fontSize: 12, lineHeight: 1.5,
                background: m.role === 'user' ? '#74FB71' : '#fff', color: '#0f1a14',
                boxShadow: '0 1px 4px rgba(0,0,0,0.06)',
              }}>
                {m.role === 'user' ? (
                  <span style={{ whiteSpace: 'pre-wrap' }}>{m.content}</span>
                ) : (
                  <div dangerouslySetInnerHTML={{ __html: renderMd(m.content) }} />
                )}
              </div>
            </div>
          ))}

          {sending && (
            <div style={{ marginBottom: 8, display: 'flex', gap: 6 }}>
              <div style={{ padding: '8px 10px', borderRadius: 10, background: '#fff', fontSize: 12, color: '#666' }}>
                Analyzuji...
              </div>
            </div>
          )}
          <div ref={bottomRef} />
        </div>

        {/* Input */}
        <div style={{ padding: 8, borderTop: '1px solid #d4e8e0', display: 'flex', gap: 6 }}>
          <input value={input} onChange={e => setInput(e.target.value)} placeholder="Dotaz nebo příkaz..."
            onKeyDown={e => { if (e.key === 'Enter') send(input.trim()) }}
            style={{ flex: 1, padding: '8px 10px', fontSize: 12, borderRadius: 8, border: '1px solid #d4e8e0', outline: 'none' }}
          />
          <button onClick={() => send(input.trim())} disabled={sending || !input.trim()} style={{
            padding: '8px 12px', borderRadius: 8, border: 'none', cursor: 'pointer', fontSize: 12, fontWeight: 700,
            background: sending || !input.trim() ? '#d1d5db' : '#74FB71', color: '#1a2e22',
          }}>
            {sending ? '...' : '→'}
          </button>
        </div>
      </div>
    </>
  )
}
