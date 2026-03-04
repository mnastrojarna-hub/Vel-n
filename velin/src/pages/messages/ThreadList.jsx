import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import SearchInput from '../../components/ui/SearchInput'

export default function ThreadList({ selectedId, onSelect }) {
  const [threads, setThreads] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')

  useEffect(() => { load() }, [search])

  async function load() {
    setLoading(true)
    let query = supabase
      .from('message_threads')
      .select('*, profiles(full_name, email)')
      .order('updated_at', { ascending: false })
    if (search) query = query.or(`profiles.full_name.ilike.%${search}%,profiles.email.ilike.%${search}%`)
    const { data } = await query
    setThreads(data || [])
    setLoading(false)
  }

  // Polling for new threads every 10s
  useEffect(() => {
    const interval = setInterval(load, 10000)
    return () => clearInterval(interval)
  }, [search])

  return (
    <div className="flex flex-col h-full">
      <div className="p-3" style={{ borderBottom: '1px solid #d4e8e0' }}>
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat…" />
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
              onClick={() => onSelect(t)}
            />
          ))
        )}
      </div>
    </div>
  )
}

function ThreadItem({ thread, selected, onClick }) {
  const unread = thread.unread_count > 0
  return (
    <div
      onClick={onClick}
      className="cursor-pointer transition-colors"
      style={{
        padding: '12px 16px',
        background: selected ? '#f1faf7' : 'transparent',
        borderBottom: '1px solid #d4e8e0',
        borderLeft: selected ? '3px solid #74FB71' : '3px solid transparent',
      }}
    >
      <div className="flex items-center gap-2">
        {unread && <span className="inline-block w-2 h-2 rounded-full" style={{ background: '#74FB71' }} />}
        <span className="text-sm" style={{ fontWeight: unread ? 700 : 500, color: '#0f1a14' }}>
          {thread.profiles?.full_name || 'Zákazník'}
        </span>
        <span className="ml-auto text-[10px]" style={{ color: '#8aab99' }}>
          {thread.updated_at ? new Date(thread.updated_at).toLocaleDateString('cs-CZ') : ''}
        </span>
      </div>
      <div className="text-xs mt-1 truncate" style={{ color: '#8aab99' }}>
        {thread.profiles?.email || ''}
      </div>
      {thread.subject && (
        <div className="text-xs mt-1 truncate" style={{ color: '#4a6357', fontWeight: unread ? 600 : 400 }}>
          {thread.subject}
        </div>
      )}
    </div>
  )
}
