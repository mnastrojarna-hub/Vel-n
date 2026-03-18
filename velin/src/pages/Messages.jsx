import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import ThreadList from './messages/ThreadList'
import ChatPanel from './messages/ChatPanel'
import Modal from '../components/ui/Modal'
import Button from '../components/ui/Button'

export default function Messages() {
  const debugMode = useDebugMode()
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
        // admin_messages is handled by bridge trigger (trg_bridge_admin_message)
        // on messages table insert — no direct insert needed here
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

  return (
    <>
      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA Messages</strong><br/>
        <div>selected thread: {selected ? `${selected.id?.slice(-8)} (${selected.profiles?.full_name || selected.customer_id?.slice(-8) || '—'})` : 'žádný'}</div>
        <div>customers loaded: {customers.length}, newThread modal: {String(showNew)}</div>
      </div>
      )}

      <div className="flex bg-white rounded-card shadow-card overflow-hidden" style={{ height: 'calc(100vh - 140px)' }}>
        {/* Thread list — left panel */}
        <div className="flex-shrink-0" style={{ width: 320, borderRight: '1px solid #d4e8e0' }}>
          <ThreadList selectedId={selected?.id} onSelect={setSelected} onNewThread={openNewThread} />
        </div>

        {/* Chat — right panel */}
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
  )
}
