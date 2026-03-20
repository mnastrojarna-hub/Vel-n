import { useState } from 'react'
import { useDebugMode } from '../hooks/useDebugMode'
import ThreadList from './messages/ThreadList'
import ChatPanel from './messages/ChatPanel'
import MessageLogTab from './messages/MessageLogTab'
import ManualSendTab from './messages/ManualSendTab'
import CampaignsTab from './messages/CampaignsTab'
import MessageTemplatesTab from './messages/MessageTemplatesTab'
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
  { key: 'log', label: 'Automatické' },
  { key: 'manual', label: 'Ruční' },
  { key: 'campaigns', label: 'Kampaně' },
  { key: 'templates', label: 'Šablony' },
]

export default function Messages() {
  const debugMode = useDebugMode()
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
        setSelected(thread)
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
      case 'manual': return <ManualSendTab channel={channel} />
      case 'campaigns': return <CampaignsTab channel={channel} />
      case 'templates': return <MessageTemplatesTab channel={channel} />
      default: return null
    }
  }

  return (
    <>
      {/* DIAGNOSTIKA */}
      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA Messages</strong><br/>
          <div>channel: {channel}, subTab: {subTab}</div>
          <div>selected thread: {selected ? `${selected.id?.slice(-8)} (${selected.profiles?.full_name || '—'})` : 'žádný'}</div>
        </div>
      )}

      {/* Hlavní tabs */}
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

      {/* Pod-tabs (jen pro SMS / Email / WhatsApp) */}
      {channel !== 'chat' && (
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
          <div className="flex bg-white rounded-card shadow-card overflow-hidden" style={{ height: 'calc(100vh - 200px)' }}>
            <div className="flex-shrink-0" style={{ width: 320, borderRight: '1px solid #d4e8e0' }}>
              <ThreadList selectedId={selected?.id} onSelect={setSelected} onNewThread={openNewThread} />
            </div>
            <div className="flex-1">
              <ChatPanel thread={selected} onThreadUpdate={handleThreadUpdate} />
            </div>
          </div>

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
    </>
  )
}
