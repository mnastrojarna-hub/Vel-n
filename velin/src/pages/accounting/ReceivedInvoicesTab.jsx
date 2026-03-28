import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import { useDebugMode } from '../../hooks/useDebugMode'
import AddReceivedModal from './AddReceivedModal'

const PER_PAGE = 25
const LS_KEY = 'velin_received_invoices_filters'

const STATUS_MAP = {
  draft: { label: 'Koncept', color: '#1a2e22', bg: '#f3f4f6' },
  issued: { label: 'Přijata', color: '#b45309', bg: '#fef3c7' },
  paid: { label: 'Zaplacena', color: '#1a8a18', bg: '#dcfce7' },
  cancelled: { label: 'Stornována', color: '#dc2626', bg: '#fee2e2' },
}

const STATUS_OPTIONS = [
  { value: 'issued', label: 'Přijata' },
  { value: 'paid', label: 'Zaplacena' },
  { value: 'cancelled', label: 'Stornována' },
]

// Flexi pipeline status → badge mapping
const FLEXI_STATUS_MAP = {
  pending: { label: 'OCR čeká', color: '#6b7280', bg: '#f3f4f6' },
  enriched: { label: 'Ke klasifikaci', color: '#b45309', bg: '#fef3c7' },
  validated: { label: 'Připraven', color: '#2563eb', bg: '#dbeafe' },
  exported: { label: 'Odesláno', color: '#7c3aed', bg: '#ede9fe' },
  approved: { label: 'Schváleno', color: '#1a8a18', bg: '#dcfce7' },
  submitted: { label: 'Odesláno FÚ', color: '#059669', bg: '#d1fae5' },
  error: { label: 'Chyba', color: '#dc2626', bg: '#fee2e2' },
}

// AI category → Czech label
const CATEGORY_LABELS = {
  phm: 'PHM', pojisteni: 'Pojištění', servis_opravy: 'Servis/Opravy',
  najem: 'Nájem', energie: 'Energie', telekomunikace: 'Telekomunikace',
  marketing: 'Marketing', kancelar: 'Kancelář', mzdy: 'Mzdy',
  dane_odvody: 'Daně/Odvody', ostatni_naklady: 'Ostatní',
}

const defaultFilters = { search: '', statuses: [], sort: 'date_desc' }

function loadFilters() {
  try {
    const raw = localStorage.getItem(LS_KEY)
    if (raw) {
      const parsed = JSON.parse(raw)
      return { ...defaultFilters, ...parsed }
    }
  } catch { /* ignore */ }
  return { ...defaultFilters }
}

export default function ReceivedInvoicesTab() {
  const debugMode = useDebugMode()
  const [invoices, setInvoices] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState(loadFilters)
  const [showAdd, setShowAdd] = useState(false)
  const [detail, setDetail] = useState(null)

  // Financial events map: invoiceId → financial_event
  const [feMap, setFeMap] = useState({})
  // Selected invoices for bulk action
  const [selected, setSelected] = useState(new Set())
  // Bulk push state
  const [bulkPushing, setBulkPushing] = useState(false)
  const [bulkResult, setBulkResult] = useState(null)
  // Per-row push state
  const [pushingId, setPushingId] = useState(null)
  // AI detail expand
  const [expandedAI, setExpandedAI] = useState(null)
  // Result message
  const [resultMsg, setResultMsg] = useState(null)
  // Confirm dialog for bulk
  const [showBulkConfirm, setShowBulkConfirm] = useState(false)

  useEffect(() => {
    try { localStorage.setItem(LS_KEY, JSON.stringify(filters)) } catch { /* ignore */ }
  }, [filters])

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true); setError(null); setResultMsg(null)
    try {
      debugLog('ReceivedInvoicesTab', 'load', { page, filters })
      let query = supabase
        .from('invoices')
        .select('*, profiles:customer_id(full_name)', { count: 'exact' })
        .eq('type', 'received')
      if (filters.search) query = query.or(`number.ilike.%${filters.search}%,notes.ilike.%${filters.search}%`)
      if (filters.statuses?.length > 0) query = query.in('status', filters.statuses)
      query = query.order(filters.sort.startsWith('amount') ? 'total' : 'issue_date', { ascending: filters.sort.endsWith('_asc'), nullsFirst: false })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('invoices.received.list', 'ReceivedInvoicesTab', () => query)
      if (err) throw err
      setInvoices(data || [])
      setTotal(count || 0)

      // Fetch financial_events for expense/ocr/manual to match with invoices
      await loadFinancialEvents(data || [])
    } catch (e) { debugError('ReceivedInvoicesTab', 'load', e); setError(e.message) }
    setLoading(false)
  }

  async function loadFinancialEvents(invs) {
    if (!invs.length) { setFeMap({}); return }
    try {
      const { data: events } = await supabase
        .from('financial_events')
        .select('id, status, flexi_id, metadata, confidence_score, linked_entity_id')
        .in('source', ['ocr', 'manual'])
        .eq('event_type', 'expense')

      const map = {}
      for (const fe of (events || [])) {
        // Match by linked_entity_id
        if (fe.linked_entity_id) {
          map[fe.linked_entity_id] = fe
        }
        // Match by metadata.financial_event_id stored in invoice metadata
        // (reverse: invoice has fe id in its metadata)
      }
      // Also match invoices that have financial_event_id in their metadata
      for (const inv of invs) {
        if (inv.metadata?.financial_event_id && !map[inv.id]) {
          const fe = (events || []).find(e => e.id === inv.metadata.financial_event_id)
          if (fe) map[inv.id] = fe
        }
      }
      setFeMap(map)
    } catch (e) {
      console.error('Failed to load financial_events:', e)
    }
  }

  async function markPaid(inv) {
    try {
      const { error: err } = await supabase.from('invoices')
        .update({ status: 'paid', paid_date: new Date().toISOString().slice(0, 10) })
        .eq('id', inv.id)
      if (err) throw err
      load()
    } catch (e) { setError(e.message) }
  }

  // ── Push single invoice to Flexi ──
  async function pushToFlexi(invoiceId) {
    const fe = feMap[invoiceId]
    if (!fe) return
    setPushingId(invoiceId); setResultMsg(null)
    try {
      const { data, error: err } = await supabase.functions.invoke('flexi-sync', {
        body: { action: 'pushExpense', id: fe.id },
      })
      if (err) throw err
      if (data?.ok) {
        setResultMsg(`Faktura odeslána do Flexi (ID: ${data.flexi_id})`)
      } else {
        setResultMsg(`Chyba Flexi: ${data?.error || 'neznámá chyba'}`)
      }
      await load()
    } catch (e) {
      setResultMsg(`Chyba: ${e.message}`)
    } finally { setPushingId(null) }
  }

  // ── Bulk push selected invoices to Flexi ──
  async function bulkPushToFlexi() {
    setShowBulkConfirm(false)
    setBulkPushing(true); setBulkResult(null); setResultMsg(null)
    let ok = 0, fail = 0
    const ids = [...selected]
    for (const invId of ids) {
      const fe = feMap[invId]
      if (!fe) { fail++; continue }
      try {
        const { data, error: err } = await supabase.functions.invoke('flexi-sync', {
          body: { action: 'pushExpense', id: fe.id },
        })
        if (err || !data?.ok) { fail++ } else { ok++ }
      } catch { fail++ }
    }
    setBulkResult({ ok, fail, total: ids.length })
    setResultMsg(`Hromadný export: ${ok} úspěšně, ${fail} chyb z ${ids.length}`)
    setSelected(new Set())
    setBulkPushing(false)
    await load()
  }

  // ── Accept AI classification ──
  async function acceptClassification(invoiceId) {
    const fe = feMap[invoiceId]
    if (!fe) return
    try {
      await supabase.from('financial_events').update({
        status: fe.status === 'enriched' ? 'validated' : fe.status,
      }).eq('id', fe.id)
      setResultMsg('AI klasifikace přijata')
      await load()
    } catch (e) { setError(e.message) }
  }

  // ── Reject AI classification ──
  async function rejectClassification(invoiceId) {
    const fe = feMap[invoiceId]
    if (!fe) return
    try {
      const currentMeta = fe.metadata || {}
      await supabase.from('financial_events').update({
        metadata: { ...currentMeta, ai_classification: null, ai_rejected: true },
        status: 'pending',
      }).eq('id', fe.id)
      setResultMsg('AI klasifikace odmítnuta — vyžaduje ruční klasifikaci')
      await load()
    } catch (e) { setError(e.message) }
  }

  // ── Select/deselect ──
  function toggleSelect(id) {
    setSelected(prev => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id); else next.add(id)
      return next
    })
  }
  function toggleSelectAll() {
    const validatable = invoices.filter(inv => feMap[inv.id]?.status === 'validated')
    if (selected.size === validatable.length && validatable.length > 0) {
      setSelected(new Set())
    } else {
      setSelected(new Set(validatable.map(i => i.id)))
    }
  }

  function handleReset() {
    setPage(1)
    setFilters({ ...defaultFilters })
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'
  const hasActiveFilters = filters.search || filters.statuses.length > 0 || filters.sort !== 'date_desc'
  const validatedCount = invoices.filter(inv => feMap[inv.id]?.status === 'validated').length
  const selectedValidated = [...selected].filter(id => feMap[id]?.status === 'validated').length

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat číslo, dodavatele…" />
        <select value={filters.sort} onChange={e => { setPage(1); setFilters(f => ({ ...f, sort: e.target.value })) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
          <option value="amount_desc">Částka ↓ nejvyšší</option>
          <option value="amount_asc">Částka ↑ nejnižší</option>
        </select>
        {hasActiveFilters && (
          <button onClick={handleReset}
            className="text-sm font-bold cursor-pointer rounded-btn"
            style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
            Resetovat filtry
          </button>
        )}
        {/* Bulk action button */}
        {selectedValidated > 0 && (
          <Button green onClick={() => setShowBulkConfirm(true)} disabled={bulkPushing}>
            {bulkPushing ? 'Odesílám…' : `Schválit vybrané (${selectedValidated}) → Flexi`}
          </Button>
        )}
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová přijatá faktura</Button>
        </div>
      </div>

      <CheckboxFilterGroup
        label="Stav"
        options={STATUS_OPTIONS}
        selected={filters.statuses}
        onChange={statuses => { setPage(1); setFilters(f => ({ ...f, statuses })) }}
      />

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <details className="mb-4">
        <summary className="text-xs font-bold uppercase tracking-wide cursor-pointer" style={{ color: '#6b7280' }}>Diagnostika filtrů</summary>
        <div className="mt-1 p-3 rounded-card text-xs font-mono" style={{ background: '#f9fafb', border: '1px solid #e5e7eb', color: '#374151' }}>
          <div><strong>search:</strong> {JSON.stringify(filters.search)}</div>
          <div><strong>statuses:</strong> {JSON.stringify(filters.statuses)}</div>
          <div><strong>sort:</strong> {JSON.stringify(filters.sort)}</div>
          <div><strong>feMap keys:</strong> {Object.keys(feMap).length}</div>
          <div><strong>selected:</strong> {selected.size}</div>
        </div>
      </details>
      )}

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
      {resultMsg && <div className="mb-4 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>{resultMsg}</div>}

      {/* Bulk progress */}
      {bulkPushing && (
        <div className="mb-4 p-3 rounded-card flex items-center gap-3" style={{ background: '#dbeafe', color: '#2563eb', fontSize: 13 }}>
          <div className="animate-spin rounded-full h-4 w-4 border-t-2" style={{ borderColor: '#2563eb' }} />
          Odesílám faktury do Abra Flexi…
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>
                  <input type="checkbox" checked={selected.size > 0 && selected.size === validatedCount && validatedCount > 0}
                    onChange={toggleSelectAll} className="cursor-pointer" style={{ accentColor: '#1a8a18' }} />
                </TH>
                <TH>Číslo</TH><TH>Dodavatel</TH><TH>Popis</TH><TH>Kategorie</TH><TH>Částka</TH>
                <TH>Datum</TH><TH>Splatnost</TH><TH>Stav</TH><TH>Flexi</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {invoices.map(inv => {
                const st = STATUS_MAP[inv.status] || STATUS_MAP.draft
                const fe = feMap[inv.id]
                const aiClass = fe?.metadata?.ai_classification
                const flexiSt = fe ? (FLEXI_STATUS_MAP[fe.status] || null) : null
                const canPush = fe?.status === 'validated'
                const isExpanded = expandedAI === inv.id
                const isPushing = pushingId === inv.id
                const catLabel = aiClass?.category ? (CATEGORY_LABELS[aiClass.category] || aiClass.category) : null

                return (
                  <>
                    <TRow key={inv.id}>
                      <TD>
                        {canPush ? (
                          <input type="checkbox" checked={selected.has(inv.id)}
                            onChange={() => toggleSelect(inv.id)} className="cursor-pointer" style={{ accentColor: '#1a8a18' }} />
                        ) : <span style={{ width: 14, display: 'inline-block' }} />}
                      </TD>
                      <TD mono bold>{inv.number || '—'}</TD>
                      <TD>{inv.notes?.split('\n')[0] || inv.profiles?.full_name || '—'}</TD>
                      <TD>{inv.notes || '—'}</TD>
                      <TD>
                        {catLabel ? (
                          <span className="cursor-pointer" onClick={() => setExpandedAI(isExpanded ? null : inv.id)}
                            title={aiClass?.classification_note || ''}>
                            <Badge label={catLabel} color="#7c3aed" bg="#ede9fe" />
                          </span>
                        ) : fe ? (
                          <span className="text-sm" style={{ color: '#6b7280' }}>—</span>
                        ) : (
                          <span className="text-sm" style={{ color: '#d4d4d8' }}>—</span>
                        )}
                      </TD>
                      <TD bold>{fmt(inv.total)}</TD>
                      <TD>{inv.issue_date ? new Date(inv.issue_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                      <TD>{inv.due_date ? new Date(inv.due_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                      <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
                      <TD>
                        {flexiSt ? (
                          <Badge label={flexiSt.label} color={flexiSt.color} bg={flexiSt.bg} />
                        ) : (
                          <span className="text-sm" style={{ color: '#d4d4d8' }}>—</span>
                        )}
                      </TD>
                      <TD>
                        <div className="flex gap-1 flex-wrap">
                          {inv.status !== 'paid' && (
                            <button onClick={() => markPaid(inv)} className="text-sm font-bold cursor-pointer"
                              style={{ color: '#1a8a18', background: 'none', border: 'none', padding: '4px 6px' }}>Zaplatit</button>
                          )}
                          {canPush && (
                            <button onClick={() => pushToFlexi(inv.id)}
                              disabled={isPushing}
                              className="text-sm font-bold cursor-pointer"
                              style={{ color: '#2563eb', background: 'none', border: 'none', padding: '4px 6px', opacity: isPushing ? 0.5 : 1 }}>
                              {isPushing ? '…' : '→ Flexi'}
                            </button>
                          )}
                        </div>
                      </TD>
                    </TRow>
                    {/* AI classification expanded row */}
                    {isExpanded && aiClass && (
                      <tr key={inv.id + '-ai'} style={{ background: '#faf5ff', borderBottom: '1px solid #d4e8e0' }}>
                        <td colSpan={11} style={{ padding: '12px 16px' }}>
                          <div className="flex flex-wrap items-start gap-6">
                            <AIDetail label="AI návrh kategorie" value={catLabel} />
                            <AIDetail label="Navrhovaný účet" value={aiClass.suggested_account} mono />
                            <AIDetail label="Opakující se" value={aiClass.is_recurring ? 'Ano' : 'Ne'} />
                            <AIDetail label="Poznámka" value={aiClass.classification_note} />
                            <div className="flex gap-2 ml-auto">
                              <button onClick={() => { acceptClassification(inv.id); setExpandedAI(null) }}
                                className="text-sm font-bold cursor-pointer rounded-btn"
                                style={{ padding: '6px 14px', background: '#dcfce7', border: '1px solid #86efac', color: '#1a8a18' }}>
                                Přijmout klasifikaci
                              </button>
                              <button onClick={() => { rejectClassification(inv.id); setExpandedAI(null) }}
                                className="text-sm font-bold cursor-pointer rounded-btn"
                                style={{ padding: '6px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
                                Odmítnout a upravit
                              </button>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </>
                )
              })}
              {invoices.length === 0 && <TRow><TD>Žádné přijaté faktury</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddReceivedModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}

      {/* Bulk confirm dialog */}
      {showBulkConfirm && (
        <Modal open title="Hromadný export do Flexi" onClose={() => setShowBulkConfirm(false)}>
          <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
            Odeslat <strong>{selectedValidated}</strong> faktur do Abra Flexi?
          </p>
          <div className="flex justify-end gap-3">
            <Button onClick={() => setShowBulkConfirm(false)}>Zrušit</Button>
            <Button green onClick={bulkPushToFlexi}>Odeslat do Flexi</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}

function AIDetail({ label, value, mono }) {
  return (
    <div>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#7c3aed' }}>{label}</div>
      <div className={`text-sm font-bold ${mono ? 'font-mono' : ''}`} style={{ color: '#1a2e22' }}>{value || '\u2014'}</div>
    </div>
  )
}

function CheckboxFilterGroup({ label, options, selected, onChange }) {
  function toggle(value) {
    if (selected.includes(value)) onChange(selected.filter(v => v !== value))
    else onChange([...selected, value])
  }
  return (
    <div className="flex flex-wrap items-center gap-3 mb-4">
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(opt => (
        <label key={opt.value} className="flex items-center gap-1.5 cursor-pointer text-sm" style={{ color: '#1a2e22' }}>
          <input type="checkbox" checked={selected.includes(opt.value)} onChange={() => toggle(opt.value)} className="cursor-pointer" style={{ accentColor: '#1a8a18' }} />
          {opt.label}
        </label>
      ))}
    </div>
  )
}
