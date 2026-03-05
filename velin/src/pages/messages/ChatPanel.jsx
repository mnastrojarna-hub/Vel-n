import { useState, useEffect, useRef } from 'react'
import { supabase } from '../../lib/supabase'

import Button from '../../components/ui/Button'

const TEMPLATE_LABELS = {
  booking_reserved: 'Potvrzení rezervace',
  booking_abandoned: 'Nedokončená rezervace',
  booking_cancelled: 'Storno rezervace',
  booking_completed: 'Po skončení rezervace',
  voucher_purchased: 'Nákup poukazu',
}

export default function ChatPanel({ thread }) {
  const [messages, setMessages] = useState([])
  const [templates, setTemplates] = useState([])
  const [loading, setLoading] = useState(true)
  const [reply, setReply] = useState('')
  const [sending, setSending] = useState(false)
  const bottomRef = useRef(null)

  useEffect(() => {
    if (thread) { loadMessages(); loadTemplates() }
  }, [thread?.id])

  // Polling every 10s
  useEffect(() => {
    if (!thread) return
    const interval = setInterval(loadMessages, 10000)
    return () => clearInterval(interval)
  }, [thread?.id])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  async function loadMessages() {
    setLoading(true)
    const { data } = await supabase
      .from('messages')
      .select('*')
      .eq('thread_id', thread.id)
      .order('created_at')
    setMessages(data || [])
    setLoading(false)
    // Mark as read
    await supabase.from('messages').update({ read_at: new Date().toISOString() }).eq('thread_id', thread.id).is('read_at', null)
  }

  async function loadTemplates() {
    const { data } = await supabase.from('message_templates').select('*').order('name')
    setTemplates(data || [])
  }

  async function handleSend() {
    if (!reply.trim()) return
    setSending(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('messages').insert({
        thread_id: thread.id,
        direction: 'admin',
        sender_name: 'Admin',
        content: reply.trim(),
        read_at: new Date().toISOString(),
      })
      await supabase.from('message_threads').update({ last_message_at: new Date().toISOString() }).eq('id', thread.id)
      setReply('')
      await loadMessages()
    } catch {}
    setSending(false)
  }

  function applyTemplate(tpl) {
    setReply(tpl.content || '')
  }

  if (!thread) {
    return (
      <div className="flex items-center justify-center h-full" style={{ color: '#8aab99', fontSize: 13 }}>
        Vyberte konverzaci
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center gap-3 p-4" style={{ borderBottom: '1px solid #d4e8e0' }}>
        <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>
          {thread.profiles?.full_name || 'Zákazník'}
        </span>
        <span className="text-xs" style={{ color: '#8aab99' }}>{thread.profiles?.email}</span>
        {thread.subject && <span className="text-xs ml-auto" style={{ color: '#4a6357' }}>{thread.subject}</span>}
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-auto p-4 space-y-3" style={{ background: '#f8fcfa' }}>
        {loading && messages.length === 0 ? (
          <div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
        ) : (
          messages.map(m => (
            <MessageBubble key={m.id} message={m} />
          ))
        )}
        <div ref={bottomRef} />
      </div>

      {/* Reply */}
      <div className="p-3" style={{ borderTop: '1px solid #d4e8e0' }}>
        {templates.length > 0 && (
          <div className="flex items-center gap-2 mb-2">
            <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Šablona:</span>
            <select
              onChange={e => {
                const tpl = templates.find(t => t.id === e.target.value)
                if (tpl) applyTemplate(tpl)
              }}
              className="rounded-btn text-xs outline-none cursor-pointer"
              style={{ padding: '4px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}
              value=""
            >
              <option value="">— Použít šablonu —</option>
              {templates.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
          </div>
        )}
        <div className="flex gap-2">
          <textarea
            value={reply}
            onChange={e => setReply(e.target.value)}
            placeholder="Napište odpověď…"
            className="flex-1 rounded-btn text-sm outline-none"
            style={{ padding: '10px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 44, maxHeight: 120, resize: 'vertical' }}
            onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend() } }}
          />
          <Button green onClick={handleSend} disabled={sending || !reply.trim()}>
            {sending ? '…' : 'Odeslat'}
          </Button>
        </div>
      </div>
    </div>
  )
}

function MessageBubble({ message }) {
  const isAdmin = message.direction === 'admin'
  const isSystem = message.direction === 'system'

  if (isSystem) {
    return (
      <div className="flex justify-start">
        <div className="rounded-card max-w-[70%]"
          style={{ padding: '10px 14px', background: '#f3f4f6', color: '#4a6357', boxShadow: '0 2px 8px rgba(15,26,20,.06)' }}>
          <div className="flex items-start gap-2">
            <span style={{ fontSize: 14 }}>🤖</span>
            <p className="text-sm" style={{ lineHeight: 1.5, whiteSpace: 'pre-wrap' }}>{message.content}</p>
          </div>
          <div className="text-[10px] mt-1" style={{ color: '#8aab99' }}>
            {message.created_at ? new Date(message.created_at).toLocaleString('cs-CZ') : ''}
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className={`flex ${isAdmin ? 'justify-end' : 'justify-start'}`}>
      <div
        className="rounded-card max-w-[70%]"
        style={{
          padding: '10px 14px',
          background: isAdmin ? '#74FB71' : '#fff',
          color: isAdmin ? '#1a2e22' : '#0f1a14',
          boxShadow: '0 2px 8px rgba(15,26,20,.06)',
        }}
      >
        <p className="text-sm" style={{ lineHeight: 1.5, whiteSpace: 'pre-wrap' }}>{message.content}</p>
        <div className="text-[10px] mt-1" style={{ color: isAdmin ? '#1a6a18' : '#8aab99' }}>
          {message.created_at ? new Date(message.created_at).toLocaleString('cs-CZ') : ''}
        </div>
      </div>
    </div>
  )
}
