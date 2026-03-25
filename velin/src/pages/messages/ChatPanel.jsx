import { useState, useEffect, useRef } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'

import Button from '../../components/ui/Button'
import { loadAgentConfig, getEnabledTools } from '../../lib/aiAgents'
import { buildAgentPromptsText } from '../../lib/aiAgentPrompts'

export default function ChatPanel({ thread, onThreadUpdate }) {
  const [messages, setMessages] = useState([])
  const [templates, setTemplates] = useState([])
  const [admins, setAdmins] = useState([])
  const [loading, setLoading] = useState(true)
  const [reply, setReply] = useState('')
  const [sending, setSending] = useState(false)
  const [aiLoading, setAiLoading] = useState(false)
  const bottomRef = useRef(null)

  useEffect(() => {
    if (thread) { loadMessages(); loadTemplates(); loadAdmins() }
  }, [thread?.id])

  // Realtime subscription for new messages
  useEffect(() => {
    if (!thread) return
    const channel = supabase
      .channel(`chat-${thread.id}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'messages',
        filter: `thread_id=eq.${thread.id}`,
      }, (payload) => {
        setMessages(prev => {
          if (prev.some(m => m.id === payload.new.id)) return prev
          return [...prev, payload.new]
        })
      })
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [thread?.id])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  async function loadMessages() {
    setLoading(true)
    const { data } = await debugAction('loadMessages', 'ChatPanel', () =>
      supabase
        .from('messages')
        .select('*')
        .eq('thread_id', thread.id)
        .order('created_at'),
      { thread_id: thread.id }
    )
    setMessages(data || [])
    setLoading(false)
    // Mark customer messages as read
    await supabase.from('messages').update({ read_at: new Date().toISOString() })
      .eq('thread_id', thread.id).eq('direction', 'customer').is('read_at', null)
  }

  async function loadTemplates() {
    const { data } = await supabase.from('message_templates').select('*').eq('is_active', true).order('name')
    // Deduplicate by slug (SMS+email versions have same slug)
    const seen = new Set()
    const unique = (data || []).filter(t => {
      if (seen.has(t.slug)) return false
      seen.add(t.slug); return true
    })
    setTemplates(unique)
  }

  async function loadAdmins() {
    const { data } = await supabase.from('admin_users').select('id, name').eq('active', true)
    setAdmins(data || [])
  }

  async function handleSend() {
    if (!reply.trim()) return
    setSending(true)
    try {
      await debugAction('handleSend:insert', 'ChatPanel', () =>
        supabase.from('messages').insert({
          thread_id: thread.id,
          direction: 'admin',
          sender_name: 'Admin',
          content: reply.trim(),
          read_at: new Date().toISOString(),
        }),
        { thread_id: thread.id, content: reply.trim() }
      )
      await debugAction('handleSend:updateThread', 'ChatPanel', () =>
        supabase.from('message_threads').update({
          last_message_at: new Date().toISOString(),
          status: 'open',
        }).eq('id', thread.id),
        { thread_id: thread.id }
      )

      // Detekce technické stížnosti → automaticky vytvořit servisní zakázku
      const techKeywords = ['zvuk', 'brzdění', 'brzdy', 'blinkr', 'blikr', 'motor', 'řetěz', 'pneu', 'poškráb', 'nefunguje', 'rozbité', 'porucha', 'závada', 'olej', 'únik', 'vibrac']
      const allCustomerMsgs = messages.filter(m => m.direction === 'customer').map(m => m.content?.toLowerCase() || '').join(' ')
      const isTechComplaint = techKeywords.some(kw => allCustomerMsgs.includes(kw))

      if (isTechComplaint && thread?.customer_id) {
        // Najdi poslední booking zákazníka → motorku
        const { data: lastBooking } = await supabase.from('bookings')
          .select('id, moto_id, motorcycles(model)')
          .eq('user_id', thread.customer_id)
          .order('created_at', { ascending: false }).limit(1).maybeSingle()

        if (lastBooking?.moto_id) {
          // Najdi volný den pro servis (den kdy motorka nemá rezervaci)
          const today = new Date()
          let serviceDate = null
          for (let d = 1; d <= 14; d++) {
            const checkDate = new Date(today.getTime() + d * 86400000)
            const iso = checkDate.toISOString().split('T')[0]
            const { data: conflicts } = await supabase.from('bookings')
              .select('id').eq('moto_id', lastBooking.moto_id)
              .in('status', ['reserved', 'active'])
              .lte('start_date', iso).gte('end_date', iso).limit(1)
            if (!conflicts?.length) { serviceDate = iso; break }
          }

          const motoName = lastBooking.motorcycles?.model || 'motorka'
          const desc = `Reklamace zákazníka: ${allCustomerMsgs.slice(0, 200)}. Naplánováno na ${serviceDate || 'co nejdříve'}.`

          // Vytvoř servisní zakázku
          const { error: svcErr } = await supabase.from('service_orders').insert({
            moto_id: lastBooking.moto_id,
            type: 'repair',
            notes: desc,
            status: 'pending',
          })

          if (!svcErr) {
            // Informuj admina v chatu systémovou zprávou
            await supabase.from('messages').insert({
              thread_id: thread.id, direction: 'system',
              content: `Servisní zakázka vytvořena pro ${motoName}. Plánovaný servis: ${serviceDate || 'nutno naplánovat ručně'}. Typ: oprava na základě reklamace zákazníka.`,
              sender_name: 'Systém',
            })
          }
        }
      }

      setReply('')
      await loadMessages()
    } catch {}
    setSending(false)
  }

  async function toggleStatus() {
    const newStatus = thread.status === 'closed' ? 'open' : 'closed'
    await debugAction('toggleStatus', 'ChatPanel', () =>
      supabase.from('message_threads').update({ status: newStatus }).eq('id', thread.id),
      { thread_id: thread.id, newStatus }
    )
    onThreadUpdate?.({ ...thread, status: newStatus })
  }

  async function assignAdmin(adminId) {
    await debugAction('assignAdmin', 'ChatPanel', () =>
      supabase.from('message_threads').update({ assigned_admin: adminId || null }).eq('id', thread.id),
      { thread_id: thread.id, adminId: adminId || null }
    )
    onThreadUpdate?.({ ...thread, assigned_admin: adminId || null })
  }

  function applyTemplate(tpl) {
    setReply(tpl.content || '')
  }

  async function aiSuggestReply() {
    if (messages.length === 0) return
    setAiLoading(true)
    try {
      const config = loadAgentConfig()
      const enabledIds = ['customers', 'bookings', 'fleet']
      const lastMsgs = messages.slice(-5).map(m =>
        `[${m.direction === 'customer' ? 'Zákazník' : 'Admin'}]: ${m.content}`
      ).join('\n')
      const customerName = thread?.profiles?.full_name || 'zákazník'
      const customerEmail = thread?.profiles?.email || ''

      const { data } = await supabase.functions.invoke('ai-copilot', {
        body: {
          message: `Jsi zákaznická podpora MotoGo24 — skutečný člověk, NE robot.

PRAVIDLA:
- Piš ROVNOU odpověď zákazníkovi. ŽÁDNÝ úvod typu "Na základě informací vidím..." nebo "Připravím odpověď...".
- Začni přímo oslovením (Dobrý den, pane/paní...).
- Piš krátce, lidsky, vstřícně. Max 5-6 vět.
- Nikdy nepiš "jako AI agent" nebo "předávám booking agentovi" — zákazník nesmí vědět o agentech.
- Pokud zákazník hlásí technický problém s motorkou (zvuk, blinkr, brzdy, poškrábání): napiš že to prověříme a naplánujeme opravu PŘED dalším nasazením motorky.
- Pokud zákazník chce změnu rezervace: napiš že to zařídíme a ozveme se s potvrzením.
- Vždy uveď kontakt +420 774 256 271.

Zákazník: "${customerName}" (${customerEmail})

Konverzace:
${lastMsgs}

Napiš POUZE text odpovědi — nic jiného.`,
          enabled_tools: getEnabledTools(config),
          agent_prompts: buildAgentPromptsText(enabledIds),
        },
      })
      if (data?.response) setReply(data.response.replace(/^["']|["']$/g, '').trim())
    } catch (e) { console.error('[AI suggest]', e) }
    setAiLoading(false)
  }

  if (!thread) {
    return (
      <div className="flex items-center justify-center h-full" style={{ color: '#1a2e22', fontSize: 13 }}>
        Vyberte konverzaci
      </div>
    )
  }

  const isClosed = thread.status === 'closed'

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center gap-3 p-4" style={{ borderBottom: '1px solid #d4e8e0' }}>
        <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>
          {thread.profiles?.full_name || 'Zákazník'}
        </span>
        <span className="text-sm" style={{ color: '#1a2e22' }}>{thread.profiles?.email}</span>
        {thread.subject && <span className="text-sm" style={{ color: '#1a2e22' }}>{thread.subject}</span>}

        <div className="ml-auto flex items-center gap-2">
          {/* Assign admin */}
          <select
            value={thread.assigned_admin || ''}
            onChange={e => assignAdmin(e.target.value)}
            className="rounded-btn text-sm outline-none cursor-pointer"
            style={{ padding: '4px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
          >
            <option value="">Nepřiřazeno</option>
            {admins.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>

          {/* Close/Reopen thread */}
          <button
            onClick={toggleStatus}
            className="text-sm font-bold cursor-pointer border-none rounded-btn"
            style={{
              padding: '4px 12px',
              background: isClosed ? '#dcfce7' : '#fee2e2',
              color: isClosed ? '#1a8a18' : '#991b1b',
            }}
          >
            {isClosed ? 'Znovu otevřít' : 'Uzavřít'}
          </button>
        </div>
      </div>

      {/* Closed banner */}
      {isClosed && (
        <div className="text-center text-sm font-bold py-2" style={{ background: '#f3f4f6', color: '#1a2e22' }}>
          Konverzace je uzavřena
        </div>
      )}

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
            <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Šablona:</span>
            <select
              onChange={e => {
                const tpl = templates.find(t => t.id === e.target.value)
                if (tpl) applyTemplate(tpl)
              }}
              className="rounded-btn text-sm outline-none cursor-pointer"
              style={{ padding: '4px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
              value=""
            >
              <option value="">— Použít šablonu —</option>
              {templates.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
          </div>
        )}
        <div className="flex gap-2 mb-2">
          <button onClick={aiSuggestReply} disabled={aiLoading || messages.length === 0}
            className="text-sm font-bold cursor-pointer border-none rounded-btn"
            style={{ padding: '4px 12px', background: aiLoading ? '#e5e7eb' : '#eff6ff', color: '#2563eb' }}>
            {aiLoading ? 'AI přemýšlí…' : '🤖 AI návrh odpovědi'}
          </button>
        </div>
        <div className="flex gap-2">
          <textarea
            value={reply}
            onChange={e => setReply(e.target.value)}
            placeholder={isClosed ? 'Odpovědí se konverzace znovu otevře…' : 'Napište odpověď…'}
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
          style={{ padding: '10px 14px', background: '#f3f4f6', color: '#1a2e22', boxShadow: '0 2px 8px rgba(15,26,20,.06)' }}>
          <div className="flex items-start gap-2">
            <span style={{ fontSize: 14 }}>&#x1F916;</span>
            <p className="text-sm" style={{ lineHeight: 1.5, whiteSpace: 'pre-wrap' }}>{message.content}</p>
          </div>
          <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>
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
        <div className="text-sm mt-1" style={{ color: isAdmin ? '#1a6a18' : '#1a2e22' }}>
          {message.created_at ? new Date(message.created_at).toLocaleString('cs-CZ') : ''}
        </div>
      </div>
    </div>
  )
}
