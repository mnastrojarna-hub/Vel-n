import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'
import { findBestMatch, StatCard, MiniField, DeliveryNoteDetailModal, MatchModal } from './DeliveryNotesHelpers'

const PER_PAGE = 25

const MATCH_STATUS = {
  matched: { label: 'Napárováno', color: '#1a8a18', bg: '#dcfce7' },
  unmatched: { label: 'Čeká na FA', color: '#b45309', bg: '#fef3c7' },
  missing_dl: { label: 'Chybí DL', color: '#dc2626', bg: '#fee2e2' },
  manual: { label: 'Ručně', color: '#6b7280', bg: '#f3f4f6' },
}

export default function DeliveryNotesTab() {
  const [notes, setNotes] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [stats, setStats] = useState({ total: 0, matched: 0, unmatched: 0, missingDl: 0 })
  const [filter, setFilter] = useState('all') // all | unmatched | matched | missing_dl
  const [search, setSearch] = useState('')
  const [detail, setDetail] = useState(null)
  const [resultMsg, setResultMsg] = useState(null)
  const [matchModal, setMatchModal] = useState(null)
  const [invoices, setInvoices] = useState([])
  const [matchSearch, setMatchSearch] = useState('')

  useEffect(() => { load() }, [page, filter, search])

  async function load() {
    setLoading(true); setError(null)
    try {
      // Load stats
      const { data: allDl } = await supabase.from('delivery_notes').select('id, matched_invoice_id')
      const matched = (allDl || []).filter(d => d.matched_invoice_id).length
      const unmatched = (allDl || []).filter(d => !d.matched_invoice_id).length

      // Count received invoices without DL
      const { data: invoicesNoDl } = await supabase.from('invoices')
        .select('id')
        .eq('type', 'received')
        .is('matched_delivery_note_id', null)
      const missingDl = (invoicesNoDl || []).length

      setStats({ total: (allDl || []).length, matched, unmatched, missingDl })

      // Build query
      let query = supabase.from('delivery_notes')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)

      if (filter === 'matched') query = query.not('matched_invoice_id', 'is', null)
      if (filter === 'unmatched') query = query.is('matched_invoice_id', null)
      if (search) query = query.or(`supplier_name.ilike.%${search}%,dl_number.ilike.%${search}%,notes.ilike.%${search}%`)

      const { data, count, error: err } = await query
      if (err) throw err

      // If filter is missing_dl, load invoices without DL instead
      if (filter === 'missing_dl') {
        let invQuery = supabase.from('invoices')
          .select('*', { count: 'exact' })
          .eq('type', 'received')
          .is('matched_delivery_note_id', null)
          .order('issue_date', { ascending: false })
          .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
        if (search) invQuery = invQuery.or(`number.ilike.%${search}%,notes.ilike.%${search}%`)
        const { data: invData, count: invCount, error: invErr } = await invQuery
        if (invErr) throw invErr
        // Map invoices to DL-like structure for display
        setNotes((invData || []).map(inv => ({
          id: inv.id,
          _isInvoice: true,
          dl_number: inv.number,
          supplier_name: inv.notes?.split('\n')[0] || '—',
          total_amount: inv.total,
          issue_date: inv.issue_date,
          matched_invoice_id: null,
          items: inv.items,
          notes: inv.notes,
        })))
        setTotal(invCount || 0)
      } else {
        setNotes(data || [])
        setTotal(count || 0)
      }
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function openMatchModal(dl) {
    setMatchModal(dl)
    setMatchSearch('')
    // Load unmatched received invoices
    const { data } = await supabase.from('invoices')
      .select('*')
      .eq('type', 'received')
      .is('matched_delivery_note_id', null)
      .order('issue_date', { ascending: false })
      .limit(50)
    setInvoices(data || [])
  }

  async function matchDlToInvoice(dl, invoiceId) {
    setResultMsg(null)
    try {
      // Update DL
      await supabase.from('delivery_notes')
        .update({ matched_invoice_id: invoiceId, match_method: 'manual', matched_at: new Date().toISOString() })
        .eq('id', dl.id)
      // Update Invoice
      await supabase.from('invoices')
        .update({ matched_delivery_note_id: dl.id })
        .eq('id', invoiceId)
      setResultMsg('Dodací list napárován k faktuře')
      setMatchModal(null)
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
  }

  async function unmatchDl(dl) {
    try {
      if (dl.matched_invoice_id) {
        await supabase.from('invoices')
          .update({ matched_delivery_note_id: null })
          .eq('id', dl.matched_invoice_id)
      }
      await supabase.from('delivery_notes')
        .update({ matched_invoice_id: null, match_method: null, matched_at: null })
        .eq('id', dl.id)
      setResultMsg('Párování zrušeno')
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
  }

  async function runAiMatching() {
    setResultMsg(null); setLoading(true)
    try {
      // Get all unmatched DLs
      const { data: unmatchedDls } = await supabase.from('delivery_notes')
        .select('*')
        .is('matched_invoice_id', null)

      // Get all unmatched received invoices
      const { data: unmatchedInvs } = await supabase.from('invoices')
        .select('*')
        .eq('type', 'received')
        .is('matched_delivery_note_id', null)

      let matchCount = 0
      for (const dl of (unmatchedDls || [])) {
        const match = findBestMatch(dl, unmatchedInvs || [])
        if (match) {
          await supabase.from('delivery_notes')
            .update({ matched_invoice_id: match.id, match_method: 'ai', match_confidence: match.confidence, matched_at: new Date().toISOString() })
            .eq('id', dl.id)
          await supabase.from('invoices')
            .update({ matched_delivery_note_id: dl.id })
            .eq('id', match.id)
          // Remove matched invoice from pool
          const idx = unmatchedInvs.indexOf(match)
          if (idx >= 0) unmatchedInvs.splice(idx, 1)
          matchCount++
        }
      }
      setResultMsg(`AI párování: ${matchCount} dodacích listů napárováno`)
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    setLoading(false)
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      {/* Stats */}
      <div className="grid grid-cols-4 gap-3 mb-4">
        <StatCard label="Celkem DL" value={stats.total} color="#1a2e22" />
        <StatCard label="Napárováno" value={stats.matched} color="#1a8a18" />
        <StatCard label="DL čeká na FA" value={stats.unmatched} color="#b45309" />
        <StatCard label="FA bez DL" value={stats.missingDl} color="#dc2626" />
      </div>

      {/* AI matching button */}
      {(stats.unmatched > 0 || stats.missingDl > 0) && (
        <div className="mb-4">
          <Button green onClick={runAiMatching}>
            AI párování ({stats.unmatched} DL + {stats.missingDl} FA)
          </Button>
        </div>
      )}

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 mb-4">
        {[
          { value: 'all', label: 'Vše' },
          { value: 'unmatched', label: 'DL bez FA' },
          { value: 'matched', label: 'Napárováno' },
          { value: 'missing_dl', label: 'FA bez DL' },
        ].map(f => (
          <button key={f.value} onClick={() => { setPage(1); setFilter(f.value) }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '6px 14px',
              background: filter === f.value ? '#1a2e22' : '#f1faf7',
              color: filter === f.value ? '#74FB71' : '#1a2e22',
              border: 'none',
              boxShadow: filter === f.value ? '0 2px 8px rgba(26,46,34,.25)' : 'none',
            }}>
            {f.label}
          </button>
        ))}
        <input type="text" value={search} onChange={e => { setPage(1); setSearch(e.target.value) }}
          placeholder="Hledat dodavatel, číslo…"
          className="rounded-btn text-sm outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', minWidth: 180 }} />
      </div>

      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
      {resultMsg && <div className="mb-3 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>{resultMsg}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>{filter === 'missing_dl' ? 'Č. faktury' : 'Č. DL'}</TH>
                <TH>Dodavatel</TH>
                <TH>Částka</TH>
                <TH>Datum</TH>
                <TH>Položky</TH>
                <TH>Status</TH>
                <TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {notes.map(dl => {
                const isInvoice = dl._isInvoice
                const status = isInvoice ? 'missing_dl'
                  : dl.matched_invoice_id ? 'matched' : 'unmatched'
                const st = MATCH_STATUS[status]
                const itemCount = Array.isArray(dl.items) ? dl.items.length : 0

                return (
                  <TRow key={dl.id}>
                    <TD mono bold>{dl.dl_number || '—'}</TD>
                    <TD><span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{dl.supplier_name || '—'}</span></TD>
                    <TD bold>{fmt(dl.total_amount)}</TD>
                    <TD>{(dl.issue_date || dl.delivery_date) ? new Date(dl.issue_date || dl.delivery_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                    <TD>{itemCount > 0 ? `${itemCount} pol.` : '—'}</TD>
                    <TD>
                      <Badge label={st.label} color={st.color} bg={st.bg} />
                      {dl.match_method === 'ai' && (
                        <span className="ml-1 text-[9px] font-bold" style={{ color: '#7c3aed' }}>
                          AI {dl.match_confidence ? `${(dl.match_confidence * 100).toFixed(0)}%` : ''}
                        </span>
                      )}
                    </TD>
                    <TD>
                      <div className="flex gap-1 flex-wrap">
                        <button onClick={() => setDetail(dl)}
                          className="text-sm font-bold cursor-pointer rounded"
                          style={{ color: '#2563eb', background: '#dbeafe', border: 'none', padding: '4px 10px' }}>
                          Detail
                        </button>
                        {!isInvoice && !dl.matched_invoice_id && (
                          <button onClick={() => openMatchModal(dl)}
                            className="text-sm font-bold cursor-pointer rounded"
                            style={{ color: '#fff', background: '#1a8a18', border: 'none', padding: '4px 10px' }}>
                            Párovat
                          </button>
                        )}
                        {!isInvoice && dl.matched_invoice_id && (
                          <button onClick={() => unmatchDl(dl)}
                            className="text-sm font-bold cursor-pointer rounded"
                            style={{ color: '#dc2626', background: '#fee2e2', border: '1px solid #fca5a5', padding: '4px 10px' }}>
                            Zrušit
                          </button>
                        )}
                      </div>
                    </TD>
                  </TRow>
                )
              })}
              {notes.length === 0 && <TRow><TD>{filter === 'missing_dl' ? 'Žádné faktury bez DL' : 'Žádné dodací listy'}</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      <DeliveryNoteDetailModal detail={detail} setDetail={setDetail} fmt={fmt} />

      <MatchModal matchModal={matchModal} setMatchModal={setMatchModal} matchSearch={matchSearch} setMatchSearch={setMatchSearch} invoices={invoices} matchDlToInvoice={matchDlToInvoice} fmt={fmt} />
    </div>
  )
}
