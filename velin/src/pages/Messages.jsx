import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import ThreadList from './messages/ThreadList'
import ChatPanel from './messages/ChatPanel'
import Modal from '../components/ui/Modal'
import Button from '../components/ui/Button'

export default function Messages() {
  const [selected, setSelected] = useState(null)
  const [showNew, setShowNew] = useState(false)
  const [customers, setCustomers] = useState([])
  const [newCustomerId, setNewCustomerId] = useState('')
  const [newSubject, setNewSubject] = useState('')
  const [newMessage, setNewMessage] = useState('')
  const [creating, setCreating] = useState(false)
  const [customerSearch, setCustomerSearch] = useState('')

  async function loadCustomers() {
    const { data } = await supabase.from('profiles').select('id, full_name, email').order('full_name').limit(100)
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
      const { data: thread } = await supabase.from('message_threads').insert({
        customer_id: newCustomerId,
        channel: 'web',
        status: 'open',
        subject: newSubject || null,
        last_message_at: new Date().toISOString(),
      }).select('*, profiles(full_name, email)').single()

      if (thread) {
        await supabase.from('messages').insert({
          thread_id: thread.id,
          direction: 'admin',
          sender_name: 'Admin',
          content: newMessage.trim(),
          read_at: new Date().toISOString(),
        })
        // Bridge: notifikace pro zakaznickou appku
        await supabase.from('admin_messages').insert({
          user_id: newCustomerId,
          title: newSubject || 'Zprava z Moto Go',
          message: newMessage.trim(),
          type: 'info',
          read: false,
        }).catch(() => {})
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
              <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>
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
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}
                size={Math.min(filteredCustomers.length + 1, 6)}
              >
                <option value="">— Vyberte zákazníka —</option>
                {filteredCustomers.map(c => (
                  <option key={c.id} value={c.id}>{c.full_name || 'Bez jména'} ({c.email})</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>
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
              <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>
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
