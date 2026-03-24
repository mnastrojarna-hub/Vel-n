import { useState, useEffect, useRef } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import Button from '../components/ui/Button'
import AiConfirmDialog from '../components/ai/AiConfirmDialog'
import AiAgentPanel from '../components/ai/AiAgentPanel'
import AiAgentConfig from '../components/ai/AiAgentConfig'
import AiActivityLog from '../components/ai/AiActivityLog'
import { loadAgentConfig, saveAgentConfig, getEnabledTools, getAgentCorrections, AGENTS } from '../lib/aiAgents'
import { buildAgentPromptsText } from '../lib/aiAgentPrompts'
import { buildAllAgentMemory, autoExtractFlash } from '../lib/aiAgentMemory'

const QUICK_ACTIONS = [
  { cat: '📊 Přehledy', items: ['Kompletní denní přehled', 'Jak jsme na tom vs. minulý měsíc?', 'Týdenní statistiky'] },
  { cat: '🏍️ Flotila & Servis', items: ['Stav celé flotily', 'Které motorky potřebují servis?', 'STK a pojistky - co expiruje?'] },
  { cat: '🆘 SOS & Zákazníci', items: ['Aktivní SOS incidenty', 'Noví zákazníci tento měsíc', 'Segmentace zákazníků'] },
  { cat: '💰 Finance & Sklady', items: ['Finanční přehled měsíce', 'Stav skladů - co dochází?', 'Nezaplacené faktury'] },
  { cat: '📈 Analýza', items: ['Výkon poboček', 'Ranking motorek', 'Optimální složení flotily'] },
  { cat: '⚡ Akce (write)', items: ['Změň stav motorky XY na maintenance', 'Zablokuj zákazníka xyz', 'Vytvoř promo kód SLEVA20 na 20%'] },
]

function renderMarkdown(text) {
  if (!text) return ''
  let html = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
  html = html.replace(/`([^`]+)`/g, '<code style="background:#f1faf7;padding:1px 4px;border-radius:3px;font-size:12px">$1</code>')
  html = html.replace(/^- (.+)$/gm, '<li style="margin-left:16px;list-style:disc">$1</li>')
  html = html.replace(/(<li[^>]*>.*<\/li>\n?)+/g, (m) => `<ul style="margin:4px 0">${m}</ul>`)
  html = html.replace(/\n/g, '<br/>')
  html = html.replace(/<br\/><ul/g, '<ul').replace(/<\/ul><br\/>/g, '</ul>')
  return html
}

export default function AICopilot() {
  const debugMode = useDebugMode()
  const [conversations, setConversations] = useState([])
  const [activeConv, setActiveConv] = useState(null)
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState(null)
  const [openCats, setOpenCats] = useState({})
  const [pendingActions, setPendingActions] = useState(null)
  const [agentConfig, setAgentConfig] = useState(() => loadAgentConfig())
  const [sidebarTab, setSidebarTab] = useState('conversations') // conversations | agents | activity
  const [configAgentId, setConfigAgentId] = useState(null)
  const bottomRef = useRef(null)

  useEffect(() => { loadConversations() }, [])
  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages])

  const enabledCount = AGENTS.filter(a => agentConfig[a.id]?.enabled).length

  async function loadConversations() {
    try {
      const { data } = await supabase.from('ai_conversations').select('*').order('updated_at', { ascending: false }).limit(20)
      setConversations(data || [])
      if (data && data.length > 0 && !activeConv) selectConversation(data[0])
    } catch { setConversations([]) }
  }

  function selectConversation(conv) { setActiveConv(conv); setMessages(conv.messages || []) }

  async function deleteConversation(e, convId) {
    e.stopPropagation()
    if (!confirm('Smazat tuto konverzaci?')) return
    await supabase.from('ai_conversations').delete().eq('id', convId)
    setConversations(c => c.filter(x => x.id !== convId))
    if (activeConv?.id === convId) { setActiveConv(null); setMessages([]) }
  }

  async function startNew() {
    try {
      const { data, error } = await debugAction('startNew', 'AICopilot', () =>
        supabase.from('ai_conversations').insert({ title: 'Nová konverzace', messages: [] }).select().single(), { title: 'Nová konverzace' })
      if (!error && data) { setActiveConv(data); setMessages([]); setConversations(c => [data, ...c]) }
    } catch {}
  }

  function getLastUserMessage() {
    for (let i = messages.length - 1; i >= 0; i--) { if (messages[i].role === 'user') return messages[i].content }
    return null
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
          supabase.from('ai_conversations').insert({ title: msg.slice(0, 50), messages: [] }).select().single(), { title: msg.slice(0, 50) })
        convId = data.id
        setActiveConv(data)
        setConversations(c => [data, ...c])
      }

      const enabledIds = AGENTS.filter(a => agentConfig[a.id]?.enabled).map(a => a.id)
      const { data, error: fnError } = await debugAction('handleSend:invoke', 'AICopilot', () =>
        supabase.functions.invoke('ai-copilot', {
          body: {
            message: msg, conversation_id: convId, conversation_history: newMessages,
            enabled_tools: getEnabledTools(agentConfig),
            agent_corrections: getAgentCorrections(agentConfig),
            agent_prompts: buildAgentPromptsText(enabledIds),
            agent_memory: buildAllAgentMemory(enabledIds),
          },
        }), { message: msg, conversation_id: convId })

      if (fnError) throw fnError
      if (data?.error_code === 'overloaded') {
        setError('overloaded')
        const errMsg = { role: 'assistant', content: 'AI je momentálně přetížená. Zkuste to za minutu.', timestamp: new Date().toISOString() }
        setMessages([...newMessages, errMsg])
        return
      }

      const aiMsg = { role: 'assistant', content: data?.response || 'AI momentálně nedostupný', timestamp: new Date().toISOString() }
      const allMessages = [...newMessages, aiMsg]
      setMessages(allMessages)

      // Auto-extract flash memory from all enabled agents
      for (const aid of enabledIds) autoExtractFlash(aid, data?.response)

      // Check for pending actions
      if (data?.pending_actions && data.pending_actions.length > 0) {
        setPendingActions(data.pending_actions)
      }

      await supabase.from('ai_conversations').update({ messages: allMessages, updated_at: new Date().toISOString() }).eq('id', convId)
    } catch (e) {
      const status = e?.status || e?.context?.status
      let errText = 'AI momentálně nedostupný. Zkuste to později.'
      let errCode = null
      if (status === 401) { errText = 'Sezení vypršelo. Přihlaste se znovu.'; errCode = 'auth' }
      else if (status === 429 || e?.message?.includes('overloaded')) { errText = 'AI je přetížená. Zkuste za minutu.'; errCode = 'overloaded' }
      setMessages(m => [...m, { role: 'assistant', content: errText, timestamp: new Date().toISOString(), isError: true }])
      setError(errCode || e.message)
    } finally { setSending(false) }
  }

  async function handleConfirm() {
    if (!pendingActions) return
    setSending(true)
    try {
      const { data } = await supabase.functions.invoke('ai-copilot', {
        body: { mode: 'execute', actions: pendingActions },
      })
      const resultMsg = { role: 'assistant', content: data?.response || 'Akce provedeny.', timestamp: new Date().toISOString() }
      const allMessages = [...messages, resultMsg]
      setMessages(allMessages)
      if (activeConv?.id) await supabase.from('ai_conversations').update({ messages: allMessages, updated_at: new Date().toISOString() }).eq('id', activeConv.id)
    } catch (e) {
      setMessages(m => [...m, { role: 'assistant', content: `Chyba při provádění: ${e.message}`, timestamp: new Date().toISOString(), isError: true }])
    } finally { setPendingActions(null); setSending(false) }
  }

  function handleReject() {
    setMessages(m => [...m, { role: 'assistant', content: 'Akce zamítnuty uživatelem.', timestamp: new Date().toISOString() }])
    setPendingActions(null)
  }

  function handleEdit() {
    setPendingActions(null)
    setInput('Uprav předchozí návrh: ')
  }

  return (
    <>
      {pendingActions && <AiConfirmDialog actions={pendingActions} onConfirm={handleConfirm} onReject={handleReject} onEdit={handleEdit} />}
      {configAgentId && <AiAgentConfig agentId={configAgentId} onClose={() => setConfigAgentId(null)} />}

      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA AICopilot</strong><br/>
          conversations: {conversations.length}, activeConv: {activeConv ? activeConv.id?.slice(-8) : 'žádná'}, messages: {messages.length}, sending: {String(sending)}, agents: {enabledCount}/{AGENTS.length}
          {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
        </div>
      )}

      <div className="flex rounded-card shadow-card overflow-hidden bg-white" style={{ height: 'calc(100vh - 140px)' }}>
        {/* Sidebar */}
        <div className="flex-shrink-0 flex flex-col" style={{ width: 240, borderRight: '1px solid #d4e8e0' }}>
          <div className="p-3" style={{ borderBottom: '1px solid #d4e8e0' }}>
            <Button green onClick={startNew} style={{ width: '100%', fontSize: 13, padding: '6px 12px' }}>+ Nová konverzace</Button>
          </div>

          {/* Sidebar tabs */}
          <div style={{ display: 'flex', borderBottom: '1px solid #d4e8e0' }}>
            {[
              { id: 'conversations', icon: '💬', label: 'Chat' },
              { id: 'agents', icon: '🤖', label: `Agenti (${enabledCount})` },
              { id: 'activity', icon: '📋', label: 'Log' },
            ].map(t => (
              <button key={t.id} onClick={() => setSidebarTab(t.id)} style={{
                flex: 1, padding: '6px 4px', fontSize: 10, fontWeight: sidebarTab === t.id ? 700 : 400,
                border: 'none', cursor: 'pointer', background: sidebarTab === t.id ? '#f1faf7' : '#fff',
                color: sidebarTab === t.id ? '#0f1a14' : '#999',
                borderBottom: sidebarTab === t.id ? '2px solid #74FB71' : 'none',
              }}>{t.icon} {t.label}</button>
            ))}
          </div>

          {sidebarTab === 'agents' ? (
            <div className="flex-1 overflow-auto">
              <AiAgentPanel config={agentConfig} onChange={setAgentConfig} onConfigAgent={setConfigAgentId} />
            </div>
          ) : sidebarTab === 'activity' ? (
            <div className="flex-1 overflow-auto p-2">
              <AiActivityLog limit={30} />
            </div>
          ) : (
            <div className="flex-1 overflow-auto">
              {conversations.map(c => (
                <div key={c.id} onClick={() => selectConversation(c)} className="cursor-pointer transition-colors" style={{
                  padding: '10px 14px', background: activeConv?.id === c.id ? '#f1faf7' : 'transparent',
                  borderBottom: '1px solid #d4e8e0', borderLeft: activeConv?.id === c.id ? '3px solid #74FB71' : '3px solid transparent',
                }}>
                  <div className="flex items-center justify-between">
                    <div className="text-sm font-bold truncate" style={{ color: '#0f1a14', flex: 1 }}>{c.title || 'Konverzace'}</div>
                    <button onClick={(e) => deleteConversation(e, c.id)} className="ml-1 flex-shrink-0 rounded-full hover:bg-red-100 transition-colors" style={{ width: 22, height: 22, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#9ca3af', fontSize: 14, lineHeight: 1 }} title="Smazat">✕</button>
                  </div>
                  <div className="text-sm mt-0.5" style={{ color: '#1a2e22' }}>{c.updated_at ? new Date(c.updated_at).toLocaleDateString('cs-CZ') : ''}</div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Chat */}
        <div className="flex-1 flex flex-col">
          <div className="p-4 flex items-center" style={{ borderBottom: '1px solid #d4e8e0' }}>
            <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>AI Copilot</span>
            <span className="ml-2 text-sm" style={{ color: '#1a2e22' }}>— {enabledCount} agentů aktivních</span>
          </div>

          {messages.length > 50 && (
            <div style={{ background: '#fef3c7', borderBottom: '1px solid #fbbf24', padding: '6px 14px', fontSize: 13, color: '#92400e' }}>
              Dlouhá konverzace ({messages.length} zpráv) — zvažte začít novou pro lepší výkon
            </div>
          )}

          <div className="flex-1 overflow-auto p-4 space-y-3" style={{ background: '#f8fcfa' }}>
            {messages.length === 0 && (
              <div className="text-center py-8">
                <div className="text-3xl mb-3">🤖</div>
                <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>AI Copilot — Čtení i Zápis</div>
                <div className="text-sm mt-1 mb-4" style={{ color: '#1a2e22' }}>
                  {enabledCount} agentů | 57 nástrojů | Plný přístup k databázi
                </div>
                <div className="grid grid-cols-2 gap-2 text-left" style={{ maxWidth: 600, margin: '0 auto' }}>
                  {QUICK_ACTIONS.map(qa => (
                    <div key={qa.cat} style={{ border: '1px solid #d4e8e0', borderRadius: 8, overflow: 'hidden' }}>
                      <button onClick={() => setOpenCats(o => ({ ...o, [qa.cat]: !o[qa.cat] }))} className="w-full text-left text-sm font-bold cursor-pointer flex items-center justify-between" style={{ padding: '8px 12px', background: openCats[qa.cat] ? '#f1faf7' : '#fff', color: '#0f1a14' }}>
                        {qa.cat}
                        <span style={{ fontSize: 10, color: '#1a2e22' }}>{openCats[qa.cat] ? '▲' : '▼'}</span>
                      </button>
                      {openCats[qa.cat] && (
                        <div style={{ borderTop: '1px solid #d4e8e0' }}>
                          {qa.items.map(q => (
                            <button key={q} onClick={() => handleSendWithMessage(q)} className="w-full text-left text-sm cursor-pointer hover:bg-green-50 transition-colors" style={{ padding: '6px 12px', color: '#1a2e22', borderBottom: '1px solid #f1faf7' }}>{q}</button>
                          ))}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {messages.map((m, i) => (
              <div key={i} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'} gap-2`}>
                {m.role === 'assistant' && <div className="flex-shrink-0 text-lg mt-1">🤖</div>}
                <div className="rounded-card max-w-[75%]" style={{ padding: '10px 14px', background: m.role === 'user' ? '#74FB71' : '#fff', color: m.role === 'user' ? '#1a2e22' : '#0f1a14', boxShadow: '0 2px 8px rgba(15,26,20,.06)' }}>
                  {m.role === 'user' ? (
                    <p className="text-sm" style={{ lineHeight: 1.6, whiteSpace: 'pre-wrap' }}>{m.content}</p>
                  ) : (
                    <div className="text-sm" style={{ lineHeight: 1.6 }} dangerouslySetInnerHTML={{ __html: renderMarkdown(m.content) }} />
                  )}
                  <div className="flex items-center gap-2 mt-1">
                    <span className="text-sm" style={{ color: m.role === 'user' ? '#1a6a18' : '#1a2e22' }}>{m.timestamp ? new Date(m.timestamp).toLocaleTimeString('cs-CZ') : ''}</span>
                    {m.isError && <button onClick={() => { const q = getLastUserMessage(); if (q) handleSendWithMessage(q) }} className="text-sm cursor-pointer hover:underline" style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}>Zkusit znovu</button>}
                  </div>
                </div>
                {m.role === 'user' && <div className="flex-shrink-0 text-lg mt-1">👤</div>}
              </div>
            ))}

            {sending && (
              <div className="flex justify-start gap-2">
                <div className="flex-shrink-0 text-lg mt-1">🤖</div>
                <div className="rounded-card" style={{ padding: '10px 14px', background: '#fff', boxShadow: '0 2px 8px rgba(15,26,20,.06)' }}>
                  <div className="text-sm" style={{ color: '#1a2e22' }}>Analyzuji data...</div>
                </div>
              </div>
            )}
            <div ref={bottomRef} />
          </div>

          <div className="p-3 flex gap-2" style={{ borderTop: '1px solid #d4e8e0' }}>
            <textarea value={input} onChange={e => setInput(e.target.value)} placeholder="Napište dotaz nebo příkaz…" className="flex-1 rounded-btn text-sm outline-none" style={{ padding: '10px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 44, maxHeight: 120, resize: 'vertical' }} onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSendWithMessage(input.trim()) } }} />
            <Button green onClick={() => handleSendWithMessage(input.trim())} disabled={sending || !input.trim()}>
              {sending ? '...' : 'Odeslat'}
            </Button>
          </div>
        </div>
      </div>
    </>
  )
}
