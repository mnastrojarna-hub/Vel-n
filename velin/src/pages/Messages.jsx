import { useState, useEffect, useRef } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useDebugMode } from '../hooks/useDebugMode'
import { useIsMobile, useMediaQuery } from '../hooks/useIsMobile'
import { ChatMobileChannelTabs, ChatMobileSubTabs } from './messages/ChatMobileTabs'
import ThreadList from './messages/ThreadList'
import ChatPanel from './messages/ChatPanel'
import MessageLogTab from './messages/MessageLogTab'
import ManualSendTab from './messages/ManualSendTab'
import CampaignsTab from './messages/CampaignsTab'
import MessageTemplatesTab from './messages/MessageTemplatesTab'
import AutoMessagesTab from './messages/AutoMessagesTab'
import Modal from '../components/ui/Modal'
import Button from '../components/ui/Button'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'

const CHANNELS = [
  { key: 'sms', label: 'SMS', icon: '📱' },
  { key: 'email', label: 'E-mail', icon: '📧' },
  { key: 'whatsapp', label: 'WhatsApp', icon: '💬' },
  { key: 'chat', label: 'Chat', icon: '🗨️' },
]

const SUB_TABS = [
  { key: 'log', label: 'Log zpráv' },
  { key: 'auto', label: 'Automatické' },
  { key: 'manual', label: 'Ruční' },
  { key: 'campaigns', label: 'Kampaně' },
  { key: 'templates', label: 'Šablony' },
]

// Výška seznamu konverzací na mobilu: dynamický viewport (lišta prohlížeče), jinak 100vh.
// Odečet = horní lišta + odsazení stránky + řada kanálů + spodní rezerva Layoutu (60 px) → stránka neroluje.
const VH = typeof CSS !== 'undefined' && CSS.supports?.('height', '100dvh') ? '100dvh' : '100vh'
const LIST_OFFSET_PHONE = 192
const LIST_OFFSET_TABLET = 204

export default function Messages() {
  const debugMode = useDebugMode()
  const isMobile = useIsMobile()
  const isTabletUp = useMediaQuery('(min-width: 768px)')
  const location = useLocation()
  const navigate = useNavigate()
  const [channel, setChannel] = useState('sms')
  const [subTab, setSubTab] = useState('log')

  // Chat state (preserved from original)
  const [selected, setSelected] = useState(null)
  const [showNew, setShowNew] = useState(false)
  const [customers, setCustomers] = useState([])
  const [newCustomerId, setNewCustomerId] = useState('')
  const [newSubject, setNewSubject] = useState('')
  const [newMessage, setNewMessage] = useState('')
  const [creating, setCreating] = useState(false)
  const [customerSearch, setCustomerSearch] = useState('')

  // Mobil: otevřená konverzace = záznam v historii, takže systémové „zpět“
  // (gesto na Androidu, tlačítko prohlížeče) zavře chat místo opuštění Zpráv. Desktop = jen stav.
  const historyThreadId = location.state?.mgChatThread || null
  const prevHistoryThreadId = useRef(historyThreadId)

  function pushThreadEntry(threadId) {
    navigate(location.pathname + location.search, { state: { ...(location.state || {}), mgChatThread: threadId } })
  }

  function openThread(thread) {
    setSelected(thread)
    if (isMobile) pushThreadEntry(thread.id)
  }

  function closeThread() {
    if (historyThreadId && historyThreadId === selected?.id) navigate(-1)
    else setSelected(null)
  }

  // Zastaralý záznam (reload s otevřeným chatem) odstraň, aby „zpět“ vždy odpovídalo otevřenému chatu.
  useEffect(() => {
    if (!location.state?.mgChatThread) return
    const { mgChatThread, ...rest } = location.state
    navigate(location.pathname + location.search, { replace: true, state: Object.keys(rest).length ? rest : null })
  }, [])

  useEffect(() => {
    const popped = prevHistoryThreadId.current !== historyThreadId
    prevHistoryThreadId.current = historyThreadId
    if (!isMobile || channel !== 'chat' || !selected || historyThreadId === selected.id) return
    if (popped) setSelected(null) // „zpět“ → zpět na seznam konverzací
    else pushThreadEntry(selected.id) // tablet otočený z desktopové šířky: chat zůstane otevřený
  }, [isMobile, channel, historyThreadId])

  async function loadCustomers() {
    const { data } = await debugAction('messages.loadCustomers', 'Messages', () =>
      supabase.from('profiles').select('id, full_name, email').order('full_name').limit(100)
    )
    setCustomers(data || [])
  }

  function openNewThread() {
    loadCustomers()
    setNewCustomerId('')
    setNewSubject('')
    setNewMessage('')
    setCustomerSearch('')
    setShowNew(true)
  }

  async function handleCreateThread() {
    if (!newCustomerId || !newMessage.trim()) return
    setCreating(true)
    try {
      const threadInsertData = {
        customer_id: newCustomerId,
        channel: 'web',
        status: 'open',
        subject: newSubject || null,
        last_message_at: new Date().toISOString(),
      }
      const { data: thread } = await debugAction('messages.createThread', 'Messages', () =>
        supabase.from('message_threads').insert(threadInsertData).select('*, profiles(full_name, email)').single()
      , threadInsertData)

      if (thread) {
        const messageData = {
          thread_id: thread.id,
          direction: 'admin',
          sender_name: 'Admin',
          content: newMessage.trim(),
          read_at: new Date().toISOString(),
        }
        await debugAction('messages.insertMessage', 'Messages', () =>
          supabase.from('messages').insert(messageData)
        , messageData)
        openThread(thread)
      }
      setShowNew(false)
    } catch {}
    setCreating(false)
  }

  function handleThreadUpdate(updated) {
    setSelected(updated)
  }

  const filteredCustomers = customerSearch
    ? customers.filter(c =>
        (c.full_name || '').toLowerCase().includes(customerSearch.toLowerCase()) ||
        (c.email || '').toLowerCase().includes(customerSearch.toLowerCase())
      )
    : customers

  function renderSubTab() {
    switch (subTab) {
      case 'log': return <MessageLogTab channel={channel} />
      case 'auto': return <AutoMessagesTab channel={channel} />
      case 'manual': return <ManualSendTab channel={channel} />
      case 'campaigns': return <CampaignsTab channel={channel} />
      case 'templates': return <MessageTemplatesTab channel={channel} />
      default: return null
    }
  }

  function selectChannel(key) {
    setChannel(key); if (key !== 'chat') setSubTab('log')
  }

  return (
    <div className="mg-msgs">
      {/* DIAGNOSTIKA */}
      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA Messages</strong><br/>
          <div>channel: {channel}, subTab: {subTab}</div>
          <div>selected thread: {selected ? `${selected.id?.slice(-8)} (${selected.profiles?.full_name || '—'})` : 'žádný'}</div>
        </div>
      )}

      {/* Hlavní tabs */}
      {isMobile ? (
        <ChatMobileChannelTabs channels={CHANNELS} active={channel} onSelect={selectChannel} />
      ) : (
      <div className="flex gap-2 mb-4 flex-wrap">
        {CHANNELS.map(ch => (
          <button
            key={ch.key}
            onClick={() => { setChannel(ch.key); if (ch.key !== 'chat') setSubTab('log') }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '8px 18px',
              background: channel === ch.key ? '#74FB71' : '#f1faf7',
              color: '#1a2e22',
              border: 'none',
              boxShadow: channel === ch.key ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}
          >
            <span style={{ marginRight: 6 }}>{ch.icon}</span>
            {ch.label}
          </button>
        ))}
      </div>
      )}

      {/* Pod-tabs (jen pro SMS / Email / WhatsApp) */}
      {channel !== 'chat' && isMobile && (
        <ChatMobileSubTabs tabs={SUB_TABS} active={subTab} onSelect={setSubTab} />
      )}
      {channel !== 'chat' && !isMobile && (
        <div className="flex gap-1.5 mb-4">
          {SUB_TABS.map(st => (
            <button
              key={st.key}
              onClick={() => setSubTab(st.key)}
              className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
              style={{
                padding: '6px 14px',
                background: subTab === st.key ? '#e8fee7' : '#f1faf7',
                color: '#1a2e22',
                border: subTab === st.key ? '1px solid #74FB71' : '1px solid transparent',
                boxShadow: subTab === st.key ? '0 2px 8px rgba(116,251,113,.2)' : 'none',
              }}
            >
              {st.label}
            </button>
          ))}
        </div>
      )}

      {/* Obsah */}
      {channel === 'chat' ? (
        <>
          {isMobile ? (
            <>
              {/* Mobil: seznam konverzací přes celou šířku, otevřený chat = celoobrazovkový překryv */}
              <div className="bg-white rounded-card shadow-card overflow-hidden" style={{ height: `calc(${VH} - ${isTabletUp ? LIST_OFFSET_TABLET : LIST_OFFSET_PHONE}px)`, minHeight: 320 }}>
                <ThreadList mobile selectedId={selected?.id} onSelect={openThread} onNewThread={openNewThread} />
              </div>
              {selected && <ChatPanel mobile thread={selected} onThreadUpdate={handleThreadUpdate} onBack={closeThread} />}
            </>
          ) : (
          <div className="flex bg-white rounded-card shadow-card overflow-hidden" style={{ height: 'calc(100vh - 200px)' }}>
            <div className="flex-shrink-0" style={{ width: 320, borderRight: '1px solid #d4e8e0' }}>
              <ThreadList selectedId={selected?.id} onSelect={setSelected} onNewThread={openNewThread} />
            </div>
            {/* minWidth 0: na užším desktopu (1024–1200 px) se panel vejde vedle seznamu a Odeslat zůstane vidět */}
            <div className="flex-1" style={{ minWidth: 0 }}>
              <ChatPanel thread={selected} onThreadUpdate={handleThreadUpdate} />
            </div>
          </div>
          )}

          {/* New thread modal */}
          <Modal open={showNew} title="Nová konverzace" onClose={() => setShowNew(false)}>
            <div className="space-y-3">
              <div>
                <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                  Zákazník
                </label>
                <input
                  type="text"
                  placeholder="Hledat zákazníka…"
                  value={customerSearch}
                  onChange={e => setCustomerSearch(e.target.value)}
                  className="w-full rounded-btn text-sm outline-none mb-1"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
                />
                <select
                  value={newCustomerId}
                  onChange={e => setNewCustomerId(e.target.value)}
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
                  size={Math.min(filteredCustomers.length + 1, 6)}
                >
                  <option value="">— Vyberte zákazníka —</option>
                  {filteredCustomers.map(c => (
                    <option key={c.id} value={c.id}>{c.full_name || 'Bez jména'} ({c.email})</option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                  Předmět (volitelné)
                </label>
                <input
                  type="text"
                  value={newSubject}
                  onChange={e => setNewSubject(e.target.value)}
                  placeholder="Např. Rezervace #123"
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
                />
              </div>

              <div>
                <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                  Zpráva
                </label>
                <textarea
                  value={newMessage}
                  onChange={e => setNewMessage(e.target.value)}
                  placeholder="Napište první zprávu…"
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 80, resize: 'vertical' }}
                />
              </div>

              <div className="flex justify-end gap-2 pt-2">
                <Button onClick={() => setShowNew(false)}>Zrušit</Button>
                <Button green onClick={handleCreateThread} disabled={creating || !newCustomerId || !newMessage.trim()}>
                  {creating ? 'Vytvářím…' : 'Odeslat'}
                </Button>
              </div>
            </div>
          </Modal>
        </>
      ) : (
        renderSubTab()
      )}
    </div>
  )
}
