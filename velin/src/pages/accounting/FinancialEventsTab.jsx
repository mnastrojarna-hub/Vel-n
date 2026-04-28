import { useState, useEffect } from 'react'
import BulkActionsBar, { SelectAllCheckbox } from '../../components/ui/BulkActionsBar'
import { exportToCsv, bulkUpdate, bulkDelete } from '../../lib/bulkActions'
import { supabase, supabaseUrl } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'
import EventEditModal from './EventEditModal'
import EvRow from './FinancialEventRow'
import { StatCard } from './FinancialEventDetail'
import {
  PER_PAGE, STATUS_MAP, TYPE_MAP, SOURCE_LABELS, DOC_TYPE_MAP,
  CATEGORY_LABELS, ALL_STATUSES, ALL_TYPES, ALL_SOURCES, ALL_DOC_TYPES,
} from './financialEventsConstants'
import { createLiabilityFromEvent, ensureSupplier, backupPhotoToFolder, createDeliveryNoteFromEvent, createContractFromEvent, createReceivedInvoiceFromEvent } from './financialEventsActions'

export default function FinancialEventsTab() {
  const [events, setEvents] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [resultMsg, setResultMsg] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [stats, setStats] = useState({ pending: 0, validated: 0, approved: 0, error: 0 })
  const [statusFilter, setStatusFilter] = useState([])
  const [typeFilter, setTypeFilter] = useState('')
  const [sourceFilter, setSourceFilter] = useState('')
  const [docTypeFilter, setDocTypeFilter] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [expandedId, setExpandedId] = useState(null)
  const [actionId, setActionId] = useState(null)
  const [editEvent, setEditEvent] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [bulkPushing, setBulkPushing] = useState(false)
  const [selectedIds, setSelectedIds] = useState(new Set())

  useEffect(() => { load() }, [page, statusFilter, typeFilter, sourceFilter, docTypeFilter, dateFrom, dateTo])

  async function load() {
    setLoading(true); setError(null)
    try {
      const { data: allEvents } = await supabase.from('financial_events').select('status')
      const s = { pending: 0, validated: 0, approved: 0, error: 0 }
      for (const e of (allEvents || [])) {
        if (e.status === 'pending' || e.status === 'enriched') s.pending++
        if (e.status === 'validated') s.validated++
        if (e.status === 'approved') s.approved++
        if (e.status === 'error') s.error++
      }
      setStats(s)

      let query = supabase.from('financial_events')
        .select('*', { count: 'exact' })
        .order('duzp', { ascending: false })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)

      if (statusFilter.length > 0) query = query.in('status', statusFilter)
      if (typeFilter) query = query.eq('event_type', typeFilter)
      if (sourceFilter) query = query.eq('source', sourceFilter)
      if (docTypeFilter) query = query.eq('document_type', docTypeFilter)
      if (dateFrom) query = query.gte('duzp', dateFrom)
      if (dateTo) query = query.lte('duzp', dateTo)

      const { data, count, error: err } = await query
      if (err) throw err
      setEvents(data || [])
      setTotal(count || 0)
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function pushToFlexi(event) {
    setActionId(event.id); setResultMsg(null)
    try {
      const action = event.event_type === 'expense' ? 'pushExpense' : event.event_type === 'asset' ? 'pushAsset' : 'pushInvoice'
      const { data, error: err } = await supabase.functions.invoke('flexi-sync', { body: { action, id: event.id } })
      if (err) throw err
      setResultMsg(data?.ok ? `Odeslano do Flexi (ID: ${data.flexi_id})` : `Chyba Flexi: ${data?.error || 'neznama'}`)
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    finally { setActionId(null) }
  }

  async function approveEvent(event) {
    setActionId(event.id); setResultMsg(null)
    try {
      const nextStatus = event.status === 'enriched' ? 'validated' : 'approved'
      const { error: err } = await supabase.from('financial_events')
        .update({ status: nextStatus, updated_at: new Date().toISOString() }).eq('id', event.id)
      if (err) throw err

      if (nextStatus === 'validated') {
        const docType = event.document_type || event.metadata?.document_type || null
        await backupPhotoToFolder(event, docType)
        if (docType === 'dodaci_list') { await createDeliveryNoteFromEvent(event) }
        else if (['smlouva', 'pracovni_smlouva', 'zadost_dovolena'].includes(docType)) { await createContractFromEvent(event, docType) }
        else { await createLiabilityFromEvent(event); await createReceivedInvoiceFromEvent(event) }
        await ensureSupplier(event)
      }
      if (nextStatus === 'approved') {
        const meta = event.metadata || {}
        if (meta.payment_method === 'cash') {
          await supabase.from('cash_register').insert({ type: 'expense', amount: event.amount_czk || 0, description: `Hotovostni platba: ${meta.supplier_name || ''} ${meta.invoice_number || ''}`.trim(), date: new Date().toISOString().slice(0, 10) })
        }
      }
      setResultMsg(nextStatus === 'validated' ? 'Schvaleno \u2014 zavazek + faktura prijata vytvoreny' : 'Udalost schvalena' + ((event.metadata?.payment_method === 'cash' && nextStatus === 'approved') ? ' \u2014 odecteno z pokladny' : ''))
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    finally { setActionId(null) }
  }


  async function deleteEvent(event) {
    setActionId(event.id); setResultMsg(null)
    try {
      await supabase.from('accounting_exceptions').delete().eq('financial_event_id', event.id)
      if (event.linked_entity_type === 'invoice' && event.linked_entity_id) { await supabase.from('invoices').delete().eq('id', event.linked_entity_id) }
      const { error: err } = await supabase.from('financial_events').delete().eq('id', event.id)
      if (err) throw err
      setResultMsg('Udalost smazana (vcetne zavazku a faktury)'); setDeleteConfirm(null); await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    finally { setActionId(null) }
  }

  async function pushAllApprovedToFlexi() {
    setBulkPushing(true); setResultMsg(null)
    try {
      const { data: approved } = await supabase.from('financial_events').select('id, event_type').eq('status', 'approved')
      let ok = 0, fail = 0
      for (const ev of (approved || [])) {
        try {
          const action = ev.event_type === 'expense' ? 'pushExpense' : ev.event_type === 'asset' ? 'pushAsset' : 'pushInvoice'
          const { data, error: err } = await supabase.functions.invoke('flexi-sync', { body: { action, id: ev.id } })
          if (err || !data?.ok) fail++; else ok++
        } catch { fail++ }
      }
      setResultMsg(`Export do Flexi: ${ok} uspesne, ${fail} chyb z ${(approved || []).length}`); await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    finally { setBulkPushing(false) }
  }

  function toggleStatus(st) { setPage(1); setStatusFilter(prev => prev.includes(st) ? prev.filter(s => s !== st) : [...prev, st]) }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => (n || 0).toLocaleString('cs-CZ') + ' Kc'

  return (
    <div>
      <div className="grid grid-cols-4 gap-3 mb-4">
        <StatCard label="Cekajici ke schvaleni" value={stats.pending} color="#b45309" />
        <StatCard label="Pripraveno k exportu" value={stats.validated} color="#2563eb" />
        <StatCard label="Schvaleno" value={stats.approved} color="#1a8a18" />
        <StatCard label="Chyby" value={stats.error} color="#dc2626" />
      </div>

      {stats.approved > 0 && <div className="mb-4"><Button green onClick={pushAllApprovedToFlexi} disabled={bulkPushing}>{bulkPushing ? 'Odesilam...' : `Poslat vse do Flexi (${stats.approved})`}</Button></div>}

      <div className="flex flex-wrap items-center gap-3 mb-4">
        <div className="flex items-center gap-1 flex-wrap rounded-btn" style={{ padding: '4px 10px', background: statusFilter.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
          <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>Status:</span>
          {ALL_STATUSES.map(st => { const m = STATUS_MAP[st]; return (
            <label key={st} className="flex items-center gap-1 cursor-pointer" style={{ padding: '3px 6px', borderRadius: 6, background: statusFilter.includes(st) ? '#74FB71' : 'transparent' }}>
              <input type="checkbox" checked={statusFilter.includes(st)} onChange={() => toggleStatus(st)} className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
              <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{m.label}</span>
            </label>
          ) })}
        </div>
        <select value={typeFilter} onChange={e => { setPage(1); setTypeFilter(e.target.value) }} className="rounded-btn text-sm outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Vsechny typy</option>
          {ALL_TYPES.map(t => <option key={t} value={t}>{TYPE_MAP[t]?.label || t}</option>)}
        </select>
        <select value={sourceFilter} onChange={e => { setPage(1); setSourceFilter(e.target.value) }} className="rounded-btn text-sm outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Vsechny zdroje</option>
          {ALL_SOURCES.map(s => <option key={s} value={s}>{SOURCE_LABELS[s]}</option>)}
        </select>
        <select value={docTypeFilter} onChange={e => { setPage(1); setDocTypeFilter(e.target.value) }} className="rounded-btn text-sm outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Vsechny doklady</option>
          {ALL_DOC_TYPES.map(dt => <option key={dt} value={dt}>{DOC_TYPE_MAP[dt].label}</option>)}
        </select>
        <input type="date" value={dateFrom} onChange={e => { setPage(1); setDateFrom(e.target.value) }} className="rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        <span className="text-sm font-bold" style={{ color: '#6b7280' }}>{'\u2013'}</span>
        <input type="date" value={dateTo} onChange={e => { setPage(1); setDateTo(e.target.value) }} className="rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        {(statusFilter.length > 0 || typeFilter || sourceFilter || docTypeFilter || dateFrom || dateTo) && (
          <button onClick={() => { setPage(1); setStatusFilter([]); setTypeFilter(''); setSourceFilter(''); setDocTypeFilter(''); setDateFrom(''); setDateTo('') }} className="text-sm font-bold cursor-pointer rounded-btn" style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>Reset</button>
        )}
      </div>

      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
      {resultMsg && <div className="mb-3 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>{resultMsg}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <BulkActionsBar count={selectedIds.size} onClear={() => setSelectedIds(new Set())} actions={[
            { label: 'Označit schválené', icon: '✓', onClick: async () => { await bulkUpdate('financial_events', [...selectedIds], { status: 'approved' }, 'fin_events_bulk_approved'); setSelectedIds(new Set()); load() } },
            { label: 'Export CSV', icon: '⬇', onClick: () => exportToCsv('financial-events', [
              { key: 'duzp', label: 'Datum' }, { key: 'event_type', label: 'Typ' },
              { key: 'document_type', label: 'Doklad' }, { key: 'metadata', label: 'Dodavatel', format: v => v?.supplier_name || '' },
              { key: 'amount_czk', label: 'Částka' }, { key: 'status', label: 'Stav' },
            ], events.filter(e => selectedIds.has(e.id))) },
            { label: 'Smazat', icon: '🗑', danger: true, confirm: 'Trvale smazat {count} finančních událostí (i navázané závazky)?', onClick: async () => { await bulkDelete('financial_events', [...selectedIds], 'fin_events_bulk_deleted'); setSelectedIds(new Set()); load() } },
          ]} />
          <Table>
            <thead><TRow header>
              <TH><SelectAllCheckbox items={events} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TH>
              <TH>Datum</TH><TH>Typ</TH><TH>Doklad</TH><TH>Dodavatel</TH><TH>Castka</TH><TH>AI kategorie</TH><TH>Status</TH><TH>Akce</TH>
            </TRow></thead>
            <tbody>
              {events.map(ev => {
                const st = STATUS_MAP[ev.status] || STATUS_MAP.pending
                const tp = TYPE_MAP[ev.event_type] || TYPE_MAP.expense
                const aiCat = ev.metadata?.ai_classification?.category || ev.metadata?.category || null
                const catLabel = aiCat ? (CATEGORY_LABELS[aiCat] || aiCat) : null
                const docType = ev.document_type || ev.metadata?.document_type || null
                const dt = docType ? (DOC_TYPE_MAP[docType] || DOC_TYPE_MAP.other) : null
                return (
                  <EvRow key={ev.id} ev={ev} st={st} tp={tp} dt={dt} catLabel={catLabel}
                    supplierName={ev.metadata?.supplier_name || '\u2014'} isExpanded={expandedId === ev.id} isActing={actionId === ev.id}
                    fmt={fmt} onExpand={() => setExpandedId(expandedId === ev.id ? null : ev.id)}
                    onApprove={() => approveEvent(ev)} onFlexi={() => pushToFlexi(ev)}
                    onEdit={() => setEditEvent(ev)} onDelete={() => setDeleteConfirm(ev)}
                    selectedIds={selectedIds} setSelectedIds={setSelectedIds} />
                )
              })}
              {events.length === 0 && <TRow><TD>Zadne financni udalosti</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {editEvent && (
        <EventEditModal event={editEvent} onClose={() => setEditEvent(null)}
          onSave={async (updated) => {
            const { error: err } = await supabase.from('financial_events').update({ ...updated, updated_at: new Date().toISOString() }).eq('id', editEvent.id)
            if (err) { setResultMsg(`Chyba: ${err.message}`); return }
            const meta = updated.metadata || {}
            await supabase.from('acc_liabilities').update({ counterparty: meta.supplier_name || null, amount: updated.amount_czk || 0, due_date: meta.due_date || null, variable_symbol: meta.variable_symbol || null, invoice_number: meta.invoice_number || null }).eq('financial_event_id', editEvent.id)
            setResultMsg('Udalost aktualizovana (vcetne zavazku)'); setEditEvent(null); await load()
          }} />
      )}

      {deleteConfirm && (
        <Modal open title="Smazat financni udalost?" onClose={() => setDeleteConfirm(null)}>
          <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
            Opravdu chcete smazat udalost <strong>{deleteConfirm.metadata?.supplier_name || ''} {deleteConfirm.metadata?.invoice_number || ''}</strong> ({(deleteConfirm.amount_czk || 0).toLocaleString('cs-CZ')} Kc)?<br />Smaze se i propojeny zavazek.
          </p>
          <div className="flex justify-end gap-3">
            <button onClick={() => setDeleteConfirm(null)} className="text-sm font-bold cursor-pointer rounded" style={{ padding: '8px 20px', background: '#f3f4f6', border: '1px solid #d4d4d8', color: '#6b7280' }}>Zrusit</button>
            <button onClick={() => deleteEvent(deleteConfirm)} className="text-sm font-bold cursor-pointer rounded" style={{ padding: '8px 20px', background: '#dc2626', border: 'none', color: '#fff' }}>Smazat</button>
          </div>
        </Modal>
      )}
    </div>
  )
}
