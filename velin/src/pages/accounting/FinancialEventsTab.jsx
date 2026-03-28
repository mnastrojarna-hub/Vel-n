import { useState, useEffect } from 'react'
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
  PER_PAGE, STATUS_MAP, TYPE_MAP, SOURCE_LABELS, DOC_TYPE_MAP, STORAGE_FOLDERS,
  CATEGORY_LABELS, ALL_STATUSES, ALL_TYPES, ALL_SOURCES, ALL_DOC_TYPES,
} from './financialEventsConstants'

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

  async function createLiabilityFromEvent(event) {
    const meta = event.metadata || {}; const ai = meta.ai_classification || {}
    await supabase.from('acc_liabilities').insert({ counterparty: meta.supplier_name || 'Neznamy dodavatel', type: 'supplier', amount: event.amount_czk || 0, paid_amount: 0, due_date: meta.due_date || null, description: ai.classification_note || meta.invoice_number || '', variable_symbol: meta.variable_symbol || null, invoice_number: meta.invoice_number || null, status: 'pending', financial_event_id: event.id })
  }

  async function ensureSupplier(event) {
    const meta = event.metadata || {}; if (!meta.supplier_name) return
    const normalized = meta.supplier_name.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim()
    const { data: existing } = await supabase.from('suppliers').select('id').eq('normalized_name', normalized).limit(1)
    if (existing && existing.length > 0) return
    await supabase.from('suppliers').insert({ name: meta.supplier_name, normalized_name: normalized, ico: meta.supplier_ico || null, bank_account: meta.supplier_bank_account || null })
  }

  async function backupPhotoToFolder(event, docType) {
    const meta = event.metadata || {}; const sourcePath = meta.storage_path; if (!sourcePath) return
    const folder = STORAGE_FOLDERS[docType] || STORAGE_FOLDERS.other
    const fileName = `${new Date().toISOString().slice(0, 10)}_${event.id.slice(0, 8)}_${sourcePath.split('/').pop()}`
    const targetPath = `${folder}/${fileName}`
    try {
      const { data: fileData } = await supabase.storage.from('invoices-received').download(sourcePath)
      if (fileData) {
        await supabase.storage.from('documents').upload(targetPath, fileData, { upsert: true })
        await supabase.from('financial_events').update({ metadata: { ...meta, backup_path: targetPath, backup_bucket: 'documents' } }).eq('id', event.id)
      }
    } catch (e) { console.error('[FE] Photo backup failed:', e.message) }
  }

  async function createDeliveryNoteFromEvent(event) {
    const meta = event.metadata || {}
    if (event.linked_entity_type === 'delivery_note' && event.linked_entity_id) return
    const { data: dl } = await supabase.from('delivery_notes').insert({ dl_number: meta.invoice_number || meta.dl_number || `DL-${event.id.slice(0, 8)}`, supplier_name: meta.supplier_name || null, supplier_ico: meta.supplier_ico || null, total_amount: event.amount_czk || 0, delivery_date: event.duzp || new Date().toISOString().slice(0, 10), variable_symbol: meta.variable_symbol || null, items: meta.items || null, notes: meta.notes || [meta.supplier_name, meta.invoice_number].filter(Boolean).join('\n'), storage_path: meta.backup_path || meta.storage_path || null, extracted_data: meta.ai_classification || meta, source: 'financial_event', financial_event_id: event.id }).select().single()
    if (dl) { await supabase.from('financial_events').update({ linked_entity_type: 'delivery_note', linked_entity_id: dl.id }).eq('id', event.id) }
  }

  async function createContractFromEvent(event, docType) {
    const meta = event.metadata || {}
    if (event.linked_entity_type === 'contract' && event.linked_entity_id) return
    const contractTypeMap = { smlouva: meta.contract_subtype || 'other', pracovni_smlouva: 'employment', zadost_dovolena: 'vacation_request' }
    const { data: contract } = await supabase.from('contracts').insert({ contract_number: meta.invoice_number || meta.contract_number || `SM-${event.id.slice(0, 8)}`, contract_type: contractTypeMap[docType] || 'other', title: meta.title || meta.supplier_name || `Smlouva ze skeneru`, counterparty: meta.supplier_name || null, counterparty_ico: meta.supplier_ico || null, amount: event.amount_czk || null, valid_from: event.duzp || new Date().toISOString().slice(0, 10), valid_until: meta.due_date || null, status: 'pending', notes: meta.notes || [meta.supplier_name, meta.invoice_number].filter(Boolean).join('\n'), storage_path: meta.backup_path || meta.storage_path || null, extracted_data: meta.ai_classification || meta, source: 'financial_event', financial_event_id: event.id, employee_id: meta.employee_id || null }).select().single()
    if (contract) { await supabase.from('financial_events').update({ linked_entity_type: 'contract', linked_entity_id: contract.id }).eq('id', event.id) }
  }

  async function createReceivedInvoiceFromEvent(event) {
    const meta = event.metadata || {}
    if (event.linked_entity_type === 'invoice' && event.linked_entity_id) return
    const ai = meta.ai_classification || {}
    const invNumber = meta.invoice_number || `FP-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}-${event.id.slice(0, 4)}`
    const noteParts = [meta.supplier_name, meta.supplier_ico ? `ICO: ${meta.supplier_ico}` : null, ai.category ? `Kategorie: ${ai.category}` : null, ai.classification_note, meta.payment_method ? `Platba: ${meta.payment_method}` : null, `FE: ${event.id.slice(0, 8)}`]
    const { data: inv } = await supabase.from('invoices').insert({ number: invNumber, type: 'received', total: event.amount_czk || 0, subtotal: event.amount_czk || 0, tax_amount: 0, issue_date: event.duzp || new Date().toISOString().slice(0, 10), due_date: meta.due_date || null, variable_symbol: meta.variable_symbol || null, notes: noteParts.filter(Boolean).join('\n'), status: 'issued', source: 'system' }).select().single()
    if (inv) { await supabase.from('financial_events').update({ linked_entity_type: 'invoice', linked_entity_id: inv.id }).eq('id', event.id) }
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
          <Table>
            <thead><TRow header><TH>Datum</TH><TH>Typ</TH><TH>Doklad</TH><TH>Dodavatel</TH><TH>Castka</TH><TH>AI kategorie</TH><TH>Status</TH><TH>Akce</TH></TRow></thead>
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
                    onEdit={() => setEditEvent(ev)} onDelete={() => setDeleteConfirm(ev)} />
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
