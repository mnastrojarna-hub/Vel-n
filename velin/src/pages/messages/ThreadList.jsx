import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'

import SearchInput from '../../components/ui/SearchInput'
import Button from '../../components/ui/Button'

export default function ThreadList({ selectedId, onSelect, onNewThread }) {
  const [threads, setThreads] = useState([])
  const [unreadCounts, setUnreadCounts] = useState({})
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [sortBy, setSortBy] = useState('last_message_at')

  useEffect(() => { load() }, [search, sortBy])

  async function load() {
    setLoading(true)
    let query = supabase
      .from('message_threads')
      .select('*, profiles(full_name, email)')
      .order(sortBy === 'customer' ? 'customer_id' : 'last_message_at', { ascending: sortBy === 'customer' })
    if (search) query = query.or(`profiles.full_name.ilike.%${search}%,profiles.email.ilike.%${search}%`)
    const { data } = await query
    setThreads(data || [])
    setLoading(false)

    // Load unread counts per thread
    if (data && data.length > 0) {
      const ids = data.map(t => t.id)
      const { data: msgs } = await supabase
        .from('messages')
        .select('thread_id')
        .in('thread_id', ids)
        .is('read_at', null)
        .eq('direction', 'customer')
      const counts = {}
      ;(msgs || []).forEach(m => { counts[m.thread_id] = (counts[m.thread_id] || 0) + 1 })
      setUnreadCounts(counts)
    }
  }

  // Realtime subscription for new/updated threads
  useEffect(() => {
    const channel = supabase
      .channel('thread-list-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'message_threads' }, () => {
        load()
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, () => {
        load()
      })
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [search])

  return (
    <div className="flex flex-col h-full">
      <div className="p-3" style={{ borderBottom: '1px solid #d4e8e0' }}>
        <div className="flex items-center gap-2 mb-2">
          <span className="text-[10px] font-extrabold uppercase tracking-wide flex-1" style={{ color: '#8aab99' }}>
            Konverzace
          </span>
          <Button green small onClick={onNewThread}>+ Nová</Button>
        </div>
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat…" />
        <select value={sortBy} onChange={e => setSortBy(e.target.value)}
          className="w-full rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none mt-2"
          style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
          <option value="last_message_at">Dle poslední zprávy</option>
          <option value="customer">Dle zákazníka</option>
          <option value="created_at">Dle data vytvoření</option>
        </select>
      </div>
      <div className="flex-1 overflow-auto">
        {loading && threads.length === 0 ? (
          <div className="flex justify-center py-8">
            <div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" />
          </div>
        ) : threads.length === 0 ? (
          <div className="p-4 text-center" style={{ color: '#8aab99', fontSize: 13 }}>Žádné konverzace</div>
        ) : (
          threads.map(t => (
            <ThreadItem
              key={t.id}
              thread={t}
              selected={t.id === selectedId}
              unreadCount={unreadCounts[t.id] || 0}
              onClick={() => onSelect(t)}
            />
          ))
        )}
      </div>
    </div>
  )
}

function ThreadItem({ thread, selected, unreadCount, onClick }) {
  const hasUnread = unreadCount > 0
  const isClosed = thread.status === 'closed'
  return (
    <div
      onClick={onClick}
      className="cursor-pointer transition-colors"
      style={{
        padding: '12px 16px',
        background: selected ? '#f1faf7' : 'transparent',
        borderBottom: '1px solid #d4e8e0',
        borderLeft: selected ? '3px solid #74FB71' : '3px solid transparent',
        opacity: isClosed ? 0.6 : 1,
      }}
    >
      <div className="flex items-center gap-2">
        {hasUnread && <span className="inline-block w-2 h-2 rounded-full" style={{ background: '#74FB71' }} />}
        <span className="text-sm" style={{ fontWeight: hasUnread ? 700 : 500, color: '#0f1a14' }}>
          {thread.profiles?.full_name || 'Zákazník'}
        </span>
        {hasUnread && (
          <span className="flex items-center justify-center"
            style={{
              minWidth: 18, height: 18, borderRadius: 9,
              background: '#74FB71', color: '#1a2e22',
              fontSize: 9, fontWeight: 800, padding: '0 5px',
            }}>
            {unreadCount}
          </span>
        )}
        <span className="ml-auto text-[10px]" style={{ color: '#8aab99' }}>
          {thread.last_message_at ? new Date(thread.last_message_at).toLocaleDateString('cs-CZ') : ''}
        </span>
      </div>
      <div className="text-xs mt-1 truncate" style={{ color: '#8aab99' }}>
        {thread.profiles?.email || ''}
      </div>
      <div className="flex items-center gap-1.5 mt-1">
        {thread.subject && (
          <span className="text-xs truncate" style={{ color: '#4a6357', fontWeight: hasUnread ? 600 : 400 }}>
            {thread.subject}
          </span>
        )}
        {isClosed && (
          <span className="text-[9px] font-bold uppercase px-1.5 py-0.5 rounded"
            style={{ background: '#f3f4f6', color: '#8aab99' }}>
            uzavřeno
          </span>
        )}
      </div>
    </div>
  )
}
