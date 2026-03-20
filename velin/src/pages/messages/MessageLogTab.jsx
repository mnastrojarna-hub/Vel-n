import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

const PAGE_SIZE = 20

const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }

export default function MessageLogTab({ channel }) {
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)

  useEffect(() => { setPage(1) }, [channel, search])
  useEffect(() => { load() }, [channel, search, page])

  async function load() {
    setLoading(true)
    try {
      let query = supabase
        .from('notification_log')
        .select('*, profiles:user_id(full_name, email)', { count: 'exact' })
        .eq('channel', channel)
        .order('created_at', { ascending: false })
        .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1)

      if (search) {
        query = query.or(`profiles.full_name.ilike.%${search}%,profiles.email.ilike.%${search}%,subject.ilike.%${search}%`)
      }

      const { data, count, error } = await debugAction('messageLog.load', 'MessageLogTab', () => query)
      if (error) throw error
      setLogs(data || [])
      setTotal(count || 0)
    } catch {
      setLogs([])
      setTotal(0)
    }
    setLoading(false)
  }

  const totalPages = Math.ceil(total / PAGE_SIZE)

  function statusBadge(status) {
    switch (status) {
      case 'sent': return <Badge label="Odesláno" color="#1a6a18" bg="#dcfce7" />
      case 'delivered': return <Badge label="Doručeno" color="#1a6a18" bg="#dcfce7" />
      case 'failed': return <Badge label="Chyba" color="#991b1b" bg="#fee2e2" />
      case 'pending': return <Badge label="Čeká" color="#92400e" bg="#fef3c7" />
      default: return <Badge label={status || '—'} color="#1a2e22" bg="#f1faf7" />
    }
  }

  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
          Automatické {CHANNEL_LABELS[channel]} zprávy
        </h2>
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat příjemce, předmět…" />
      </div>

      {loading && logs.length === 0 ? (
        <div className="flex justify-center py-8">
          <div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" />
        </div>
      ) : logs.length === 0 ? (
        <div className="text-center py-8" style={{ color: '#1a2e22', fontSize: 13 }}>
          Žádné automatické {CHANNEL_LABELS[channel]} zprávy
        </div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Datum</TH>
                <TH>Příjemce</TH>
                <TH>Předmět / Typ</TH>
                <TH>Stav</TH>
              </TRow>
            </thead>
            <tbody>
              {logs.map(log => (
                <TRow key={log.id}>
                  <TD mono>{log.created_at ? new Date(log.created_at).toLocaleString('cs-CZ') : '—'}</TD>
                  <TD>
                    <div style={{ fontWeight: 600 }}>{log.profiles?.full_name || '—'}</div>
                    <div style={{ fontSize: 11, color: '#1a2e22' }}>{log.profiles?.email || ''}</div>
                  </TD>
                  <TD>{log.subject || log.type || '—'}</TD>
                  <TD>{statusBadge(log.status)}</TD>
                </TRow>
              ))}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      <div className="mt-3 text-right" style={{ fontSize: 11, color: '#1a2e22' }}>
        Celkem: {total} záznamů
      </div>
    </Card>
  )
}
