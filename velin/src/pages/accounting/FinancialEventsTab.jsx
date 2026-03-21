import { useState, useEffect } from 'react'
import { supabase, supabaseUrl } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'
import EventEditModal from './EventEditModal'

const PER_PAGE = 25

const STATUS_MAP = {
  pending:   { label: 'Čeká',        color: '#6b7280', bg: '#f3f4f6' },
  enriched:  { label: 'Ke schválení', color: '#b45309', bg: '#fef3c7' },
  validated: { label: 'Připraven',    color: '#2563eb', bg: '#dbeafe' },
  exported:  { label: 'Odesláno',     color: '#7c3aed', bg: '#ede9fe' },
  approved:  { label: 'Schváleno',    color: '#1a8a18', bg: '#dcfce7' },
  submitted: { label: 'Podáno FÚ',   color: '#059669', bg: '#d1fae5' },
  error:     { label: 'Chyba',        color: '#dc2626', bg: '#fee2e2' },
}

const TYPE_MAP = {
  revenue: { label: 'Příjem',  color: '#1a8a18', bg: '#dcfce7' },
  expense: { label: 'Výdaj',   color: '#dc2626', bg: '#fee2e2' },
  asset:   { label: 'Majetek', color: '#7c3aed', bg: '#ede9fe' },
  payroll: { label: 'Mzdy',    color: '#b45309', bg: '#fef3c7' },
}

const SOURCE_LABELS = { stripe: 'Stripe', ocr: 'OCR', system: 'Systém', manual: 'Ručně' }

const CATEGORY_LABELS = {
  phm: 'PHM', pojisteni: 'Pojištění', servis_opravy: 'Servis', najem: 'Nájem',
  energie: 'Energie', telekomunikace: 'Telekom', marketing: 'Marketing',
  kancelar: 'Kancelář', mzdy: 'Mzdy', dane_odvody: 'Daně', ostatni_naklady: 'Ostatní',
  pronajem_motorek: 'Pronájem', prodej_zbozi: 'E-shop', dlouhodoby_majetek: 'DM',
  kratkodoby_majetek: 'KM', zbozi: 'Zboží', drobna_rezie: 'Režie', material: 'Materiál',
  sluzba: 'Služba',
}

const ASSET_TYPE_LABELS = {
  dlouhodoby_majetek: 'Dlouhodobý majetek',
  kratkodoby_majetek: 'Krátkodobý majetek',
  zbozi: 'Zboží',
  material: 'Materiál',
  drobna_rezie: 'Drobná režie',
  sluzba: 'Služba',
}

const PAYMENT_LABELS = {
  bank_transfer: 'Bankovní převod',
  cash: 'Hotovost',
  card: 'Karta',
}

const ALL_STATUSES = ['pending', 'enriched', 'validated', 'exported', 'approved', 'submitted', 'error']
const ALL_TYPES = ['revenue', 'expense', 'asset', 'payroll']
const ALL_SOURCES = ['stripe', 'ocr', 'system', 'manual']

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
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [expandedId, setExpandedId] = useState(null)
  const [actionId, setActionId] = useState(null)
  const [editEvent, setEditEvent] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [bulkPushing, setBulkPushing] = useState(false)

  useEffect(() => { load() }, [page, statusFilter, typeFilter, sourceFilter, dateFrom, dateTo])

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
      const action = event.event_type === 'expense' ? 'pushExpense'
        : event.event_type === 'asset' ? 'pushAsset' : 'pushInvoice'
      const { data, error: err } = await supabase.functions.invoke('flexi-sync', {
        body: { action, id: event.id },
      })
      if (err) throw err
      setResultMsg(data?.ok ? `Odesláno do Flexi (ID: ${data.flexi_id})` : `Chyba Flexi: ${data?.error || 'neznámá'}`)
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    finally { setActionId(null) }
  }

  async function approveEvent(event) {
    setActionId(event.id); setResultMsg(null)
    try {
      const nextStatus = event.status === 'enriched' ? 'validated' : 'approved'
      const { error: err } = await supabase.from('financial_events')
        .update({ status: nextStatus, updated_at: new Date().toISOString() })
        .eq('id', event.id)
      if (err) throw err

      // When validated → create liability + ensure supplier + create received invoice
      if (nextStatus === 'validated') {
        await createLiabilityFromEvent(event)
        await ensureSupplier(event)
        await createReceivedInvoiceFromEvent(event)
      }

      // When approved → if cash payment, deduct from pokladna
      if (nextStatus === 'approved') {
        const meta = event.metadata || {}
        if (meta.payment_method === 'cash') {
          await supabase.from('cash_register').insert({
            type: 'expense',
            amount: event.amount_czk || 0,
            description: `Hotovostní platba: ${meta.supplier_name || ''} ${meta.invoice_number || ''}`.trim(),
            date: new Date().toISOString().slice(0, 10),
          })
        }
      }

      setResultMsg(nextStatus === 'validated' ? 'Schváleno — závazek + faktura přijatá vytvořeny' : 'Událost schválena' + ((event.metadata?.payment_method === 'cash' && nextStatus === 'approved') ? ' — odečteno z pokladny' : ''))
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    finally { setActionId(null) }
  }

  async function createLiabilityFromEvent(event) {
    const meta = event.metadata || {}
    const ai = meta.ai_classification || {}
    await supabase.from('acc_liabilities').insert({
      counterparty: meta.supplier_name || 'Neznámý dodavatel',
      type: 'supplier',
      amount: event.amount_czk || 0,
      paid_amount: 0,
      due_date: meta.due_date || null,
      description: ai.classification_note || meta.invoice_number || '',
      variable_symbol: meta.variable_symbol || null,
      invoice_number: meta.invoice_number || null,
      status: 'pending',
      financial_event_id: event.id,
    })
  }

  async function ensureSupplier(event) {
    const meta = event.metadata || {}
    if (!meta.supplier_name) return
    const normalized = meta.supplier_name.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim()
    const { data: existing } = await supabase.from('suppliers')
      .select('id').eq('normalized_name', normalized).limit(1)
    if (existing && existing.length > 0) return
    await supabase.from('suppliers').insert({
      name: meta.supplier_name,
      normalized_name: normalized,
      ico: meta.supplier_ico || null,
      bank_account: meta.supplier_bank_account || null,
    })
  }

  async function createReceivedInvoiceFromEvent(event) {
    const meta = event.metadata || {}
    // Check if received invoice already linked to this event
    if (event.linked_entity_type === 'invoice' && event.linked_entity_id) return
    const ai = meta.ai_classification || {}
    const invNumber = meta.invoice_number || `FP-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}-${event.id.slice(0, 4)}`
    const { data: inv } = await supabase.from('invoices').insert({
      number: invNumber,
      type: 'received',
      total: event.amount_czk || 0,
      subtotal: event.amount_czk || 0,
      tax_amount: 0,
      issue_date: event.duzp || new Date().toISOString().slice(0, 10),
      due_date: meta.due_date || null,
      variable_symbol: meta.variable_symbol || null,
      notes: [meta.supplier_name, ai.classification_note].filter(Boolean).join('\n'),
      status: 'issued',
      metadata: {
        supplier_name: meta.supplier_name,
        supplier_ico: meta.supplier_ico,
        supplier_bank_account: meta.supplier_bank_account,
        expense_category: ai.category || meta.category,
        payment_method: meta.payment_method,
        financial_event_id: event.id,
      },
    }).select().single()
    // Link event to invoice
    if (inv) {
      await supabase.from('financial_events').update({
        linked_entity_type: 'invoice',
        linked_entity_id: inv.id,
      }).eq('id', event.id)
    }
  }

  async function deleteEvent(event) {
    setActionId(event.id); setResultMsg(null)
    try {
      // Clean up related exceptions + linked received invoice + CASCADE deletes linked liability
      await supabase.from('accounting_exceptions').delete().eq('financial_event_id', event.id)
      if (event.linked_entity_type === 'invoice' && event.linked_entity_id) {
        await supabase.from('invoices').delete().eq('id', event.linked_entity_id)
      }
      const { error: err } = await supabase.from('financial_events')
        .delete().eq('id', event.id)
      if (err) throw err
      setResultMsg('Událost smazána (včetně závazku a faktury)')
      setDeleteConfirm(null)
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    finally { setActionId(null) }
  }

  async function pushAllApprovedToFlexi() {
    setBulkPushing(true); setResultMsg(null)
    try {
      const { data: approved } = await supabase.from('financial_events')
        .select('id, event_type').eq('status', 'approved')
      let ok = 0, fail = 0
      for (const ev of (approved || [])) {
        try {
          const action = ev.event_type === 'expense' ? 'pushExpense'
            : ev.event_type === 'asset' ? 'pushAsset' : 'pushInvoice'
          const { data, error: err } = await supabase.functions.invoke('flexi-sync', {
            body: { action, id: ev.id },
          })
          if (err || !data?.ok) fail++; else ok++
        } catch { fail++ }
      }
      setResultMsg(`Export do Flexi: ${ok} úspěšně, ${fail} chyb z ${(approved || []).length}`)
      await load()
    } catch (e) { setResultMsg(`Chyba: ${e.message}`) }
    finally { setBulkPushing(false) }
  }

  function toggleStatus(st) {
    setPage(1)
    setStatusFilter(prev => prev.includes(st) ? prev.filter(s => s !== st) : [...prev, st])
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      <div className="grid grid-cols-4 gap-3 mb-4">
        <StatCard label="Čekající ke schválení" value={stats.pending} color="#b45309" />
        <StatCard label="Připraveno k exportu" value={stats.validated} color="#2563eb" />
        <StatCard label="Schváleno" value={stats.approved} color="#1a8a18" />
        <StatCard label="Chyby" value={stats.error} color="#dc2626" />
      </div>

      {stats.approved > 0 && (
        <div className="mb-4">
          <Button green onClick={pushAllApprovedToFlexi} disabled={bulkPushing}>
            {bulkPushing ? 'Odesílám…' : `Poslat vše do Flexi (${stats.approved})`}
          </Button>
        </div>
      )}

      <div className="flex flex-wrap items-center gap-3 mb-4">
        <div className="flex items-center gap-1 flex-wrap rounded-btn" style={{ padding: '4px 10px', background: statusFilter.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
          <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>Status:</span>
          {ALL_STATUSES.map(st => {
            const m = STATUS_MAP[st]
            return (
              <label key={st} className="flex items-center gap-1 cursor-pointer" style={{ padding: '3px 6px', borderRadius: 6, background: statusFilter.includes(st) ? '#74FB71' : 'transparent' }}>
                <input type="checkbox" checked={statusFilter.includes(st)} onChange={() => toggleStatus(st)} className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
                <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{m.label}</span>
              </label>
            )
          })}
        </div>
        <select value={typeFilter} onChange={e => { setPage(1); setTypeFilter(e.target.value) }}
          className="rounded-btn text-sm outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Všechny typy</option>
          {ALL_TYPES.map(t => <option key={t} value={t}>{TYPE_MAP[t]?.label || t}</option>)}
        </select>
        <select value={sourceFilter} onChange={e => { setPage(1); setSourceFilter(e.target.value) }}
          className="rounded-btn text-sm outline-none" style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Všechny zdroje</option>
          {ALL_SOURCES.map(s => <option key={s} value={s}>{SOURCE_LABELS[s]}</option>)}
        </select>
        <input type="date" value={dateFrom} onChange={e => { setPage(1); setDateFrom(e.target.value) }}
          className="rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        <span className="text-sm font-bold" style={{ color: '#6b7280' }}>–</span>
        <input type="date" value={dateTo} onChange={e => { setPage(1); setDateTo(e.target.value) }}
          className="rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        {(statusFilter.length > 0 || typeFilter || sourceFilter || dateFrom || dateTo) && (
          <button onClick={() => { setPage(1); setStatusFilter([]); setTypeFilter(''); setSourceFilter(''); setDateFrom(''); setDateTo('') }}
            className="text-sm font-bold cursor-pointer rounded-btn"
            style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
            Reset
          </button>
        )}
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
                <TH>Datum</TH><TH>Typ</TH><TH>Dodavatel</TH><TH>Částka</TH>
                <TH>AI kategorie</TH><TH>Status</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {events.map(ev => {
                const st = STATUS_MAP[ev.status] || STATUS_MAP.pending
                const tp = TYPE_MAP[ev.event_type] || TYPE_MAP.expense
                const aiCat = ev.metadata?.ai_classification?.category || ev.metadata?.category || null
                const catLabel = aiCat ? (CATEGORY_LABELS[aiCat] || aiCat) : null
                const isExpanded = expandedId === ev.id
                const isActing = actionId === ev.id
                const supplierName = ev.metadata?.supplier_name || '—'

                return (
                  <EvRow key={ev.id} ev={ev} st={st} tp={tp} catLabel={catLabel}
                    supplierName={supplierName} isExpanded={isExpanded} isActing={isActing}
                    fmt={fmt} onExpand={() => setExpandedId(isExpanded ? null : ev.id)}
                    onApprove={() => approveEvent(ev)} onFlexi={() => pushToFlexi(ev)}
                    onEdit={() => setEditEvent(ev)} onDelete={() => setDeleteConfirm(ev)} />
                )
              })}
              {events.length === 0 && <TRow><TD>Žádné finanční události</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {editEvent && (
        <EventEditModal event={editEvent} onClose={() => setEditEvent(null)}
          onSave={async (updated) => {
            const { error: err } = await supabase.from('financial_events')
              .update({ ...updated, updated_at: new Date().toISOString() })
              .eq('id', editEvent.id)
            if (err) { setResultMsg(`Chyba: ${err.message}`); return }
            // Sync linked liability
            const meta = updated.metadata || {}
            await supabase.from('acc_liabilities')
              .update({
                counterparty: meta.supplier_name || null,
                amount: updated.amount_czk || 0,
                due_date: meta.due_date || null,
                variable_symbol: meta.variable_symbol || null,
                invoice_number: meta.invoice_number || null,
              })
              .eq('financial_event_id', editEvent.id)
            setResultMsg('Událost aktualizována (včetně závazku)')
            setEditEvent(null)
            await load()
          }} />
      )}

      {deleteConfirm && (
        <Modal open title="Smazat finanční událost?" onClose={() => setDeleteConfirm(null)}>
          <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
            Opravdu chcete smazat událost <strong>{deleteConfirm.metadata?.supplier_name || ''} {deleteConfirm.metadata?.invoice_number || ''}</strong> ({(deleteConfirm.amount_czk || 0).toLocaleString('cs-CZ')} Kč)?
            <br />Smaže se i propojený závazek.
          </p>
          <div className="flex justify-end gap-3">
            <button onClick={() => setDeleteConfirm(null)}
              className="text-sm font-bold cursor-pointer rounded"
              style={{ padding: '8px 20px', background: '#f3f4f6', border: '1px solid #d4d4d8', color: '#6b7280' }}>
              Zrušit
            </button>
            <button onClick={() => deleteEvent(deleteConfirm)}
              className="text-sm font-bold cursor-pointer rounded"
              style={{ padding: '8px 20px', background: '#dc2626', border: 'none', color: '#fff' }}>
              Smazat
            </button>
          </div>
        </Modal>
      )}
    </div>
  )
}

function EvRow({ ev, st, tp, catLabel, supplierName, isExpanded, isActing, fmt, onExpand, onApprove, onFlexi, onEdit, onDelete }) {
  const canApprove = ev.status === 'enriched' || ev.status === 'exported'
  const canFlexi = ev.status === 'validated'

  return (
    <>
      <TRow>
        <TD>{ev.duzp ? new Date(ev.duzp).toLocaleDateString('cs-CZ') : '—'}</TD>
        <TD><Badge label={tp.label} color={tp.color} bg={tp.bg} /></TD>
        <TD><span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{supplierName}</span></TD>
        <TD bold color={ev.event_type === 'revenue' ? '#1a8a18' : '#dc2626'}>{fmt(ev.amount_czk)}</TD>
        <TD>
          {catLabel ? <Badge label={catLabel} color="#7c3aed" bg="#ede9fe" /> : <span style={{ color: '#d4d4d8' }}>—</span>}
        </TD>
        <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
        <TD>
          <div className="flex gap-1 flex-wrap">
            {canApprove && (
              <button onClick={onApprove} disabled={isActing}
                className="text-sm font-bold cursor-pointer rounded"
                style={{ color: '#fff', background: '#1a8a18', border: 'none', padding: '4px 10px', opacity: isActing ? 0.5 : 1 }}>
                {isActing ? '…' : 'Schválit'}
              </button>
            )}
            {canFlexi && (
              <button onClick={onFlexi} disabled={isActing}
                className="text-sm font-bold cursor-pointer rounded"
                style={{ color: '#fff', background: '#2563eb', border: 'none', padding: '4px 10px', opacity: isActing ? 0.5 : 1 }}>
                {isActing ? '…' : '→ Flexi'}
              </button>
            )}
            <button onClick={onEdit}
              className="text-sm font-bold cursor-pointer rounded"
              style={{ color: '#b45309', background: '#fef3c7', border: '1px solid #fcd34d', padding: '4px 10px' }}>
              Upravit
            </button>
            <button onClick={onDelete} disabled={isActing}
              className="text-sm font-bold cursor-pointer rounded"
              style={{ color: '#dc2626', background: '#fee2e2', border: '1px solid #fca5a5', padding: '4px 10px', opacity: isActing ? 0.5 : 1 }}>
              Smazat
            </button>
            <button onClick={onExpand}
              className="text-sm font-bold cursor-pointer"
              style={{ color: '#6b7280', background: 'none', border: 'none', padding: '4px 6px' }}>
              {isExpanded ? 'Skrýt ▴' : 'Detail ▾'}
            </button>
          </div>
        </TD>
      </TRow>
      {isExpanded && (
        <tr style={{ background: '#f9fafb', borderBottom: '1px solid #d4e8e0' }}>
          <td colSpan={7} style={{ padding: '12px 16px' }}>
            <EventDetail event={ev} />
          </td>
        </tr>
      )}
    </>
  )
}

function EventDetail({ event }) {
  const ai = event.metadata?.ai_classification
  const meta = event.metadata || {}
  const assetCls = ai?.asset_type || meta.asset_classification?.type || null
  const deprGroup = ai?.depreciation_group || meta.asset_classification?.depreciation_group || null
  const deprYears = ai?.depreciation_years || meta.asset_classification?.depreciation_years || null
  const deprMethod = ai?.depreciation_method || meta.asset_classification?.depreciation_method || null
  const storagePath = meta.storage_path
  const [photoUrl, setPhotoUrl] = useState(null)
  const [photoLoading, setPhotoLoading] = useState(false)

  async function loadPhoto() {
    if (!storagePath || photoUrl) return
    setPhotoLoading(true)
    try {
      const { data } = await supabase.storage.from('invoices-received').createSignedUrl(storagePath, 600)
      if (data?.signedUrl) setPhotoUrl(data.signedUrl)
    } catch (_) {}
    setPhotoLoading(false)
  }

  useEffect(() => { if (storagePath) loadPhoto() }, [storagePath])

  return (
    <div className="flex flex-wrap gap-6">
      {/* Fotka dokladu */}
      {storagePath && (
        <div style={{ minWidth: 200, maxWidth: 300 }}>
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#2563eb' }}>Doklad</div>
          {photoLoading ? (
            <div className="text-sm" style={{ color: '#6b7280' }}>Načítám...</div>
          ) : photoUrl ? (
            <a href={photoUrl} target="_blank" rel="noopener noreferrer">
              <img src={photoUrl} alt="Doklad" style={{ maxWidth: '100%', borderRadius: 8, border: '1px solid #d4e8e0', cursor: 'zoom-in' }} />
            </a>
          ) : (
            <div className="text-sm" style={{ color: '#6b7280' }}>Nelze načíst</div>
          )}
        </div>
      )}

      {/* Extrahovaná data */}
      <div>
        <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Dokladová data</div>
        <div className="grid grid-cols-2 gap-x-6 gap-y-1">
          <MiniLabel label="Dodavatel" value={meta.supplier_name || '—'} />
          <MiniLabel label="IČO" value={meta.supplier_ico || '—'} mono />
          <MiniLabel label="Číslo faktury" value={meta.invoice_number || '—'} mono />
          <MiniLabel label="VS" value={meta.variable_symbol || '—'} mono />
          <MiniLabel label="Číslo účtu" value={meta.supplier_bank_account || '—'} mono />
          <MiniLabel label="Splatnost" value={meta.due_date ? new Date(meta.due_date).toLocaleDateString('cs-CZ') : '—'} />
          <MiniLabel label="Datum přijetí" value={meta.received_date ? new Date(meta.received_date).toLocaleDateString('cs-CZ') : '—'} />
          <MiniLabel label="Platba" value={PAYMENT_LABELS[meta.payment_method] || meta.payment_method || '—'} />
        </div>
      </div>

      {/* AI klasifikace */}
      {ai && (
        <div>
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#7c3aed' }}>AI klasifikace</div>
          <div className="grid grid-cols-2 gap-x-6 gap-y-1">
            <MiniLabel label="Kategorie" value={CATEGORY_LABELS[ai.category] || ai.category || '—'} />
            <MiniLabel label="Účet" value={ai.suggested_account || '—'} mono />
            <MiniLabel label="Opakující se" value={ai.is_recurring ? 'Ano' : 'Ne'} />
            <MiniLabel label="Poznámka" value={ai.classification_note || '—'} />
          </div>
        </div>
      )}

      {/* Majetek a odpisy */}
      {assetCls && (
        <div>
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#b45309' }}>Majetek a odpisy</div>
          <div className="grid grid-cols-2 gap-x-6 gap-y-1">
            <MiniLabel label="Typ majetku" value={ASSET_TYPE_LABELS[assetCls] || assetCls} />
            {ai?.asset_name && <MiniLabel label="Položka" value={ai.asset_name} />}
            {deprGroup && (
              <>
                <MiniLabel label="Odpis. skupina" value={deprGroup} mono />
                <MiniLabel label="Odpis. doba" value={deprYears ? `${deprYears} let` : '—'} />
                <MiniLabel label="Metoda" value={deprMethod === 'accelerated' ? 'Zrychlené' : deprMethod === 'linear' ? 'Rovnoměrné' : '—'} />
              </>
            )}
            {assetCls === 'dlouhodoby_majetek' && (
              <div className="col-span-2 mt-1 p-2 rounded" style={{ background: '#fef3c7', border: '1px solid #fcd34d' }}>
                <span className="text-xs font-bold" style={{ color: '#b45309' }}>
                  Doporučení: {deprMethod === 'accelerated' ? 'Zrychlený' : 'Rovnoměrný'} odpis, skupina {deprGroup || 'sk2'} ({deprYears || 5} let)
                </span>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Info */}
      <div>
        <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#6b7280' }}>Info</div>
        <div className="grid grid-cols-2 gap-x-6 gap-y-1">
          <MiniLabel label="ID" value={event.id?.slice(0, 8)} mono />
          <MiniLabel label="Confidence" value={event.confidence_score != null ? `${(event.confidence_score * 100).toFixed(0)}%` : '—'} />
          <MiniLabel label="Vytvořeno" value={event.created_at ? new Date(event.created_at).toLocaleString('cs-CZ') : '—'} />
          <MiniLabel label="Flexi ID" value={event.flexi_id || '—'} mono />
          <MiniLabel label="Linked" value={event.linked_entity_type ? `${event.linked_entity_type} ${event.linked_entity_id?.slice(0, 8) || ''}` : '—'} />
          <MiniLabel label="Zdroj" value={SOURCE_LABELS[event.source] || event.source} />
        </div>
      </div>
    </div>
  )
}

function MiniLabel({ label, value, mono }) {
  return (
    <div className="mb-1">
      <span className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>{label}: </span>
      <span className={`text-sm font-bold ${mono ? 'font-mono' : ''}`} style={{ color: '#1a2e22' }}>{value}</span>
    </div>
  )
}

function StatCard({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-lg font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}
