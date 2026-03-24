import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'

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

      {/* Detail modal */}
      {detail && (
        <Modal open title={detail._isInvoice ? 'Detail faktury bez DL' : 'Detail dodacího listu'} onClose={() => setDetail(null)}>
          <div className="grid grid-cols-2 gap-4 mb-4">
            <MiniField label={detail._isInvoice ? 'Číslo faktury' : 'Číslo DL'} value={detail.dl_number || detail.number || '—'} mono />
            <MiniField label="Dodavatel" value={detail.supplier_name || '—'} />
            <MiniField label="IČO" value={detail.supplier_ico || '—'} mono />
            <MiniField label="Částka" value={fmt(detail.total_amount)} />
            <MiniField label="Datum" value={(detail.issue_date || detail.delivery_date) ? new Date(detail.issue_date || detail.delivery_date).toLocaleDateString('cs-CZ') : '—'} />
            <MiniField label="VS" value={detail.variable_symbol || '—'} mono />
          </div>

          {/* Extracted items */}
          {Array.isArray(detail.items) && detail.items.length > 0 && (
            <div className="mb-4">
              <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Položky</div>
              <Table>
                <thead>
                  <TRow header><TH>Popis</TH><TH>Množství</TH><TH>Cena/ks</TH><TH>Celkem</TH></TRow>
                </thead>
                <tbody>
                  {detail.items.map((item, i) => (
                    <TRow key={i}>
                      <TD>{item.description || item.name || '—'}</TD>
                      <TD>{item.quantity || '—'}</TD>
                      <TD>{item.unit_price ? fmt(item.unit_price) : '—'}</TD>
                      <TD bold>{item.total ? fmt(item.total) : '—'}</TD>
                    </TRow>
                  ))}
                </tbody>
              </Table>
            </div>
          )}

          {/* All extracted data */}
          {detail.extracted_data && (
            <div className="mb-4">
              <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#7c3aed' }}>AI extrahovaná data</div>
              <pre className="text-xs p-3 rounded" style={{ background: '#f1faf7', color: '#1a2e22', whiteSpace: 'pre-wrap', maxHeight: 200, overflow: 'auto' }}>
                {JSON.stringify(detail.extracted_data, null, 2)}
              </pre>
            </div>
          )}

          {/* Photo */}
          {detail.photo_url && (
            <div className="mb-4">
              <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#2563eb' }}>Sken dokladu</div>
              <a href={detail.photo_url} target="_blank" rel="noopener noreferrer">
                <img src={detail.photo_url} alt="DL sken" style={{ maxWidth: '100%', maxHeight: 300, borderRadius: 8, border: '1px solid #d4e8e0' }} />
              </a>
            </div>
          )}

          {detail.notes && (
            <div className="mb-4">
              <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#6b7280' }}>Poznámky</div>
              <p className="text-sm" style={{ color: '#1a2e22', whiteSpace: 'pre-wrap' }}>{detail.notes}</p>
            </div>
          )}

          <div className="flex justify-end">
            <Button onClick={() => setDetail(null)}>Zavřít</Button>
          </div>
        </Modal>
      )}

      {/* Match modal */}
      {matchModal && (
        <Modal open title={`Párovat DL ${matchModal.dl_number || ''} s fakturou`} onClose={() => setMatchModal(null)}>
          <div className="mb-3 p-3 rounded" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>
              DL: {matchModal.dl_number || '—'} | {matchModal.supplier_name || '—'} | {fmt(matchModal.total_amount)}
            </div>
          </div>

          <input type="text" value={matchSearch} onChange={e => setMatchSearch(e.target.value)}
            placeholder="Hledat fakturu…"
            className="rounded-btn text-sm outline-none w-full mb-3"
            style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />

          <div style={{ maxHeight: 300, overflow: 'auto' }}>
            {invoices
              .filter(inv => {
                if (!matchSearch) return true
                const s = matchSearch.toLowerCase()
                return (inv.number || '').toLowerCase().includes(s) ||
                  (inv.notes || '').toLowerCase().includes(s)
              })
              .map(inv => {
                const amountMatch = Math.abs((inv.total || 0) - (matchModal.total_amount || 0)) < 1
                const supplierMatch = matchModal.supplier_name &&
                  (inv.notes || '').toLowerCase().includes((matchModal.supplier_name || '').toLowerCase())
                return (
                  <div key={inv.id} className="flex items-center justify-between p-2 rounded mb-1 cursor-pointer hover:bg-[#e8fde8]"
                    style={{ background: amountMatch && supplierMatch ? '#dcfce7' : amountMatch ? '#fef3c7' : '#f9fafb', border: '1px solid #d4e8e0' }}
                    onClick={() => matchDlToInvoice(matchModal, inv.id)}>
                    <div>
                      <span className="text-sm font-mono font-bold" style={{ color: '#1a2e22' }}>{inv.number || '—'}</span>
                      <span className="ml-2 text-sm" style={{ color: '#6b7280' }}>{inv.notes?.split('\n')[0]?.slice(0, 40) || ''}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-bold" style={{ color: amountMatch ? '#1a8a18' : '#b45309' }}>{fmt(inv.total)}</span>
                      {amountMatch && <Badge label="Částka OK" color="#1a8a18" bg="#dcfce7" />}
                      {supplierMatch && <Badge label="Dodavatel OK" color="#2563eb" bg="#dbeafe" />}
                    </div>
                  </div>
                )
              })}
            {invoices.length === 0 && (
              <div className="text-sm p-3" style={{ color: '#6b7280' }}>Žádné nenapárované faktury přijaté</div>
            )}
          </div>

          <div className="flex justify-end mt-3">
            <button onClick={() => setMatchModal(null)}
              className="text-sm font-bold cursor-pointer rounded"
              style={{ padding: '8px 20px', background: '#f3f4f6', border: '1px solid #d4d4d8', color: '#6b7280' }}>
              Zavřít
            </button>
          </div>
        </Modal>
      )}
    </div>
  )
}

/** AI matching logic - compares all numbers, amounts, supplier names, dates */
function findBestMatch(dl, invoices) {
  let bestMatch = null
  let bestScore = 0

  for (const inv of invoices) {
    let score = 0
    const invNotes = (inv.notes || '').toLowerCase()
    const invNumber = (inv.number || '').toLowerCase()

    // Amount match (strongest signal)
    if (inv.total && dl.total_amount && Math.abs(inv.total - dl.total_amount) < 1) {
      score += 40
    } else if (inv.total && dl.total_amount && Math.abs(inv.total - dl.total_amount) < inv.total * 0.05) {
      score += 20
    }

    // Supplier name match
    if (dl.supplier_name && invNotes.includes(dl.supplier_name.toLowerCase())) {
      score += 30
    } else if (dl.supplier_name) {
      const words = dl.supplier_name.toLowerCase().split(/\s+/).filter(w => w.length > 2)
      const wordMatches = words.filter(w => invNotes.includes(w)).length
      if (wordMatches > 0) score += Math.min(wordMatches * 10, 25)
    }

    // IČO match
    if (dl.supplier_ico && invNotes.includes(dl.supplier_ico)) {
      score += 25
    }

    // Variable symbol match
    if (dl.variable_symbol && (inv.variable_symbol === dl.variable_symbol || invNotes.includes(dl.variable_symbol))) {
      score += 20
    }

    // DL number referenced in invoice
    if (dl.dl_number && (invNotes.includes(dl.dl_number.toLowerCase()) || invNumber.includes(dl.dl_number.toLowerCase()))) {
      score += 15
    }

    // Date proximity (within 30 days)
    if (dl.delivery_date && inv.issue_date) {
      const daysDiff = Math.abs(new Date(dl.delivery_date) - new Date(inv.issue_date)) / (1000 * 60 * 60 * 24)
      if (daysDiff <= 7) score += 10
      else if (daysDiff <= 30) score += 5
    }

    // Item count match
    if (Array.isArray(dl.items) && Array.isArray(inv.items)) {
      if (dl.items.length === inv.items.length) score += 5
    }

    if (score > bestScore && score >= 50) {
      bestScore = score
      bestMatch = { ...inv, confidence: Math.min(score / 100, 1.0) }
    }
  }

  return bestMatch
}

function StatCard({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-lg font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}

function MiniField({ label, value, mono }) {
  return (
    <div>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#6b7280' }}>{label}</div>
      <div className={`text-sm font-bold ${mono ? 'font-mono' : ''}`} style={{ color: '#1a2e22' }}>{value}</div>
    </div>
  )
}
