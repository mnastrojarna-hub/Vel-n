import { useState, useEffect, useRef } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import Button from '../components/ui/Button'

export default function AICopilot() {
  const debugMode = useDebugMode()
  const [conversations, setConversations] = useState([])
  const [activeConv, setActiveConv] = useState(null)
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState(null)
  const bottomRef = useRef(null)

  useEffect(() => { loadConversations() }, [])
  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages])

  async function loadConversations() {
    try {
      const { data } = await supabase
        .from('ai_conversations')
        .select('*')
        .order('updated_at', { ascending: false })
        .limit(20)
      setConversations(data || [])
      if (data && data.length > 0 && !activeConv) {
        selectConversation(data[0])
      }
    } catch {
      setConversations([])
    }
  }

  async function selectConversation(conv) {
    setActiveConv(conv)
    setMessages(conv.messages || [])
  }

  async function deleteConversation(e, convId) {
    e.stopPropagation()
    if (!confirm('Smazat tuto konverzaci?')) return
    await supabase.from('ai_conversations').delete().eq('id', convId)
    setConversations(c => c.filter(x => x.id !== convId))
    if (activeConv?.id === convId) {
      setActiveConv(null)
      setMessages([])
    }
  }

  async function startNew() {
    try {
      const { data, error } = await debugAction('startNew', 'AICopilot', () =>
        supabase
          .from('ai_conversations')
          .insert({ title: 'Nová konverzace', messages: [] })
          .select()
          .single(),
        { title: 'Nová konverzace' }
      )
      if (!error && data) {
        setActiveConv(data)
        setMessages([])
        setConversations(c => [data, ...c])
      }
    } catch {}
  }

  async function handleSendWithMessage(msg) {
    if (!msg || sending) return
    setError(null)
    const userMsg = { role: 'user', content: msg, timestamp: new Date().toISOString() }
    const newMessages = [...messages, userMsg]
    setMessages(newMessages)
    setInput('')
    setSending(true)

    try {
      let convId = activeConv?.id
      if (!convId) {
        const { data } = await debugAction('handleSend:createConv', 'AICopilot', () =>
          supabase
            .from('ai_conversations')
            .insert({ title: msg.slice(0, 50), messages: [] })
            .select().single(),
          { title: msg.slice(0, 50) }
        )
        convId = data.id
        setActiveConv(data)
        setConversations(c => [data, ...c])
      }

      const { data, error: fnError } = await debugAction('handleSend:invoke', 'AICopilot', () =>
        supabase.functions.invoke('ai-copilot', {
          body: { message: msg, conversation_id: convId },
        }),
        { message: msg, conversation_id: convId }
      )

      if (fnError) throw fnError

      const aiMsg = {
        role: 'assistant',
        content: data?.response || data?.message || 'AI momentálně nedostupný',
        timestamp: new Date().toISOString(),
      }
      const allMessages = [...newMessages, aiMsg]
      setMessages(allMessages)

      await supabase.from('ai_conversations')
        .update({ messages: allMessages, updated_at: new Date().toISOString() })
        .eq('id', convId)
    } catch (e) {
      const errMsg = {
        role: 'assistant',
        content: 'AI momentálně nedostupný. Zkuste to později.',
        timestamp: new Date().toISOString(),
      }
      setMessages(m => [...m, errMsg])
      setError(e.message)
    } finally {
      setSending(false)
    }
  }

  async function handleSend() {
    if (!input.trim() || sending) return
    setError(null)
    const userMsg = { role: 'user', content: input.trim(), timestamp: new Date().toISOString() }
    const newMessages = [...messages, userMsg]
    setMessages(newMessages)
    setInput('')
    setSending(true)

    try {
      let convId = activeConv?.id
      if (!convId) {
        const { data } = await debugAction('handleSend:createConv', 'AICopilot', () =>
          supabase
            .from('ai_conversations')
            .insert({ title: input.trim().slice(0, 50), messages: [] })
            .select().single(),
          { title: input.trim().slice(0, 50) }
        )
        convId = data.id
        setActiveConv(data)
        setConversations(c => [data, ...c])
      }

      const { data, error: fnError } = await debugAction('handleSend:invoke', 'AICopilot', () =>
        supabase.functions.invoke('ai-copilot', {
          body: { message: input.trim(), conversation_id: convId },
        }),
        { message: input.trim(), conversation_id: convId }
      )

      if (fnError) throw fnError

      const aiMsg = {
        role: 'assistant',
        content: data?.response || data?.message || 'AI momentálně nedostupný',
        timestamp: new Date().toISOString(),
      }
      const allMessages = [...newMessages, aiMsg]
      setMessages(allMessages)

      await supabase.from('ai_conversations')
        .update({ messages: allMessages, updated_at: new Date().toISOString() })
        .eq('id', convId)
    } catch (e) {
      const errMsg = {
        role: 'assistant',
        content: 'AI momentálně nedostupný. Zkuste to později.',
        timestamp: new Date().toISOString(),
      }
      setMessages(m => [...m, errMsg])
      setError(e.message)
    } finally {
      setSending(false)
    }
  }

  return (
    <>
    {/* DIAGNOSTIKA */}
    {debugMode && (
    <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
      <strong>DIAGNOSTIKA AICopilot</strong><br/>
      <div>conversations: {conversations.length}, activeConv: {activeConv ? activeConv.id?.slice(-8) : 'žádná'}</div>
      <div>messages: {messages.length}, sending: {String(sending)}</div>
      {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
    </div>
    )}
    <div className="flex rounded-card shadow-card overflow-hidden bg-white" style={{ height: 'calc(100vh - 140px)' }}>
      {/* Conversation list */}
      <div className="flex-shrink-0 flex flex-col" style={{ width: 240, borderRight: '1px solid #d4e8e0' }}>
        <div className="p-3" style={{ borderBottom: '1px solid #d4e8e0' }}>
          <Button green onClick={startNew} style={{ width: '100%', fontSize: 13, padding: '6px 12px' }}>+ Nová konverzace</Button>
        </div>
        <div className="flex-1 overflow-auto">
          {conversations.map(c => (
            <div
              key={c.id}
              onClick={() => selectConversation(c)}
              className="cursor-pointer transition-colors"
              style={{
                padding: '10px 14px',
                background: activeConv?.id === c.id ? '#f1faf7' : 'transparent',
                borderBottom: '1px solid #d4e8e0',
                borderLeft: activeConv?.id === c.id ? '3px solid #74FB71' : '3px solid transparent',
              }}
            >
              <div className="flex items-center justify-between">
                <div className="text-sm font-bold truncate" style={{ color: '#0f1a14', flex: 1 }}>{c.title || 'Konverzace'}</div>
                <button
                  onClick={(e) => deleteConversation(e, c.id)}
                  className="ml-1 flex-shrink-0 rounded-full hover:bg-red-100 transition-colors"
                  style={{ width: 22, height: 22, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#9ca3af', fontSize: 14, lineHeight: 1 }}
                  title="Smazat konverzaci"
                >
                  ✕
                </button>
              </div>
              <div className="text-sm mt-0.5" style={{ color: '#1a2e22' }}>
                {c.updated_at ? new Date(c.updated_at).toLocaleDateString('cs-CZ') : ''}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Chat */}
      <div className="flex-1 flex flex-col">
        <div className="p-4 flex items-center" style={{ borderBottom: '1px solid #d4e8e0' }}>
          <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>AI Copilot</span>
          <span className="ml-2 text-sm" style={{ color: '#1a2e22' }}>— Asistent pro řízení MotoGo24</span>
        </div>

        <div className="flex-1 overflow-auto p-4 space-y-3" style={{ background: '#f8fcfa' }}>
          {messages.length === 0 && (
            <div className="text-center py-12">
              <div className="text-3xl mb-3">🤖</div>
              <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>Jak vám mohu pomoci?</div>
              <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>
                Ptejte se na tržby, flotilu, servis nebo cokoli dalšího.
              </div>
              <div className="flex flex-wrap gap-2 justify-center mt-4">
                {['Dej mi kompletní přehled firmy', 'Kolik jsme vydělali a jak jsme na tom vs. minulý měsíc?', 'Které motorky potřebují servis?', 'Shrň aktivní SOS incidenty', 'Jaký je stav poboček a flotily?', 'Přehled e-shopu a voucherů'].map(q => (
                  <button key={q} onClick={() => { setInput(q); setTimeout(() => { handleSendWithMessage(q) }, 0) }}
                    className="rounded-btn text-sm cursor-pointer"
                    style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
                    {q}
                  </button>
                ))}
              </div>
            </div>
          )}
          {messages.map((m, i) => (
            <div key={i} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}>
              <div className="rounded-card max-w-[75%]" style={{
                padding: '10px 14px',
                background: m.role === 'user' ? '#74FB71' : '#fff',
                color: m.role === 'user' ? '#1a2e22' : '#0f1a14',
                boxShadow: '0 2px 8px rgba(15,26,20,.06)',
              }}>
                <p className="text-sm" style={{ lineHeight: 1.6, whiteSpace: 'pre-wrap' }}>{m.content}</p>
                <div className="text-sm mt-1" style={{ color: m.role === 'user' ? '#1a6a18' : '#1a2e22' }}>
                  {m.timestamp ? new Date(m.timestamp).toLocaleTimeString('cs-CZ') : ''}
                </div>
              </div>
            </div>
          ))}
          {sending && (
            <div className="flex justify-start">
              <div className="rounded-card" style={{ padding: '10px 14px', background: '#fff', boxShadow: '0 2px 8px rgba(15,26,20,.06)' }}>
                <div className="flex gap-1">
                  <span className="animate-bounce text-sm" style={{ animationDelay: '0ms' }}>●</span>
                  <span className="animate-bounce text-sm" style={{ animationDelay: '150ms' }}>●</span>
                  <span className="animate-bounce text-sm" style={{ animationDelay: '300ms' }}>●</span>
                </div>
              </div>
            </div>
          )}
          <div ref={bottomRef} />
        </div>

        <div className="p-3 flex gap-2" style={{ borderTop: '1px solid #d4e8e0' }}>
          <textarea
            value={input}
            onChange={e => setInput(e.target.value)}
            placeholder="Napište dotaz…"
            className="flex-1 rounded-btn text-sm outline-none"
            style={{ padding: '10px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 44, maxHeight: 120, resize: 'vertical' }}
            onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend() } }}
          />
          <Button green onClick={handleSend} disabled={sending || !input.trim()}>
            {sending ? '…' : 'Odeslat'}
          </Button>
        </div>
      </div>
    </div>
    </>
  )
}
