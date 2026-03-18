import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import { generateInvoiceNumber, calculateTotals } from '../../lib/invoiceUtils'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

const TYPE_LABELS = {
  proforma: 'Zálohová (ZF)',
  advance: 'Zálohová (ZF)',
  issued: 'Vystavená',
  received: 'Přijatá',
  final: 'Konečná (KF)',
  payment_receipt: 'Doklad k platbě (DP)',
  shop_proforma: 'Shop zálohová',
  shop_final: 'Shop konečná',
}

const TYPE_OPTIONS = [
  { value: 'issued', label: 'Vystavené (FV)' },
  { value: 'advance', label: 'Zálohové (ZF)' },
  { value: 'payment_receipt', label: 'Doklady k platbě (DP)' },
  { value: 'final', label: 'Konečné (KF)' },
  { value: 'shop_proforma', label: 'Shop zálohové' },
  { value: 'shop_final', label: 'Shop konečné' },
]

export default function InvoicesTab() {
  const debugMode = useDebugMode()
  const [invoices, setInvoices] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = { search: '', types: [], sort: 'date_desc' }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_acc_invoices_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_acc_invoices_filters', JSON.stringify(filters)) }, [filters])
  const [showAdd, setShowAdd] = useState(false)
  const [detailInv, setDetailInv] = useState(null)

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      debugLog('AccInvoicesTab', 'load', { page, filters })
      let query = supabase
        .from('invoices')
        .select('*, profiles:customer_id(full_name), bookings:booking_id(modification_history, sos_incident_id)', { count: 'exact' })
      if (filters.types?.length > 0) {
        const expandedTypes = filters.types.includes('advance') ? [...filters.types, 'proforma'] : filters.types
        query = query.in('type', expandedTypes)
      }
      if (filters.search) query = query.or(`number.ilike.%${filters.search}%`)
      query = query.order(filters.sort.startsWith('amount') ? 'total' : 'issue_date', { ascending: filters.sort.endsWith('_asc'), nullsFirst: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('invoices.list', 'AccInvoicesTab', () => query)
      if (err) throw err
      setInvoices(data || [])
      setTotal(count || 0)
    } catch (e) {
      debugError('AccInvoicesTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function generatePdf(invoiceId) {
    try {
      debugLog('AccInvoicesTab', 'generatePdf', { invoiceId })
      const { loadInvoiceData } = await import('../../lib/invoiceUtils')
      const { generateInvoiceHtml } = await import('../../lib/invoiceTemplate')
      const fullInv = await loadInvoiceData(invoiceId)
      const html = generateInvoiceHtml({
        type: fullInv.type,
        number: fullInv.number,
        issue_date: fullInv.issue_date,
        due_date: fullInv.due_date,
        duzp: fullInv.issue_date,
        items: fullInv.items || [],
        subtotal: fullInv.subtotal,
        tax_amount: fullInv.tax_amount,
        total: fullInv.total,
        notes: fullInv.notes,
        variable_symbol: fullInv.number?.replace(/[^0-9]/g, ''),
        customer: {
          name: fullInv.profiles?.full_name,
          email: fullInv.profiles?.email,
          phone: fullInv.profiles?.phone,
          address: [fullInv.profiles?.street, fullInv.profiles?.city, fullInv.profiles?.zip].filter(Boolean).join(', ') || '',
          ico: fullInv.profiles?.ico,
          dic: fullInv.profiles?.dic,
        },
      })
      const { printInvoiceHtml } = await import('../../lib/invoiceUtils')
      printInvoiceHtml(html)
    } catch (e) {
      debugError('AccInvoicesTab', 'generatePdf', e)
      setError('Generování PDF selhalo: ' + e.message)
    }
  }

  async function sendEmail(invoiceId) {
    try {
      debugLog('AccInvoicesTab', 'sendEmail', { invoiceId })
      const { error } = await debugAction('functions.send-email', 'AccInvoicesTab', () =>
        supabase.functions.invoke('send-email', {
          body: { type: 'invoice', invoice_id: invoiceId },
        })
      )
      if (error) throw error
      alert('Email odeslán')
    } catch (e) {
      debugError('AccInvoicesTab', 'sendEmail', e)
      setError('Odeslání emailu selhalo: ' + e.message)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat číslo, zákazníka…" />
        <CheckboxFilterGroup label="Typ" values={filters.types || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, types: v })) }}
          options={TYPE_OPTIONS} />
        <select value={filters.sort} onChange={e => { setPage(1); setFilters(f => ({ ...f, sort: e.target.value })) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
          <option value="amount_desc">Částka ↓ nejvyšší</option>
          <option value="amount_asc">Částka ↑ nejnižší</option>
        </select>
        <button onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_acc_invoices_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
          Reset
        </button>
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová faktura</Button>
        </div>
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA AccInvoicesTab</strong><br/>
        <div>invoices: {invoices.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: types={filters.types?.length > 0 ? filters.types.join(',') : 'vše'}, sort={filters.sort}, search="{filters.search}"</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Číslo</TH><TH>Typ</TH><TH>Zákazník</TH><TH>Částka</TH><TH>DPH</TH>
                <TH>Vystavení</TH><TH>Splatnost</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {invoices.map(inv => {
                const isSOS = inv.source === 'sos' || !!inv.bookings?.sos_incident_id
                const isModified = inv.bookings?.modification_history && Array.isArray(inv.bookings.modification_history) && inv.bookings.modification_history.length > 0
                return (
                <tr key={inv.id} onClick={() => setDetailInv(inv)}
                  className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                  style={{ borderBottom: '1px solid #d4e8e0' }}>
                  <TD mono bold>
                    <div className="flex items-center gap-1">
                      {inv.number || '—'}
                      {isSOS && <span title="SOS faktura" style={{ color: '#dc2626', fontSize: 12, fontWeight: 800 }}>SOS</span>}
                      {isModified && <span title="Změna rezervace" style={{ color: '#b45309', fontSize: 12, fontWeight: 800 }}>MOD</span>}
                    </div>
                  </TD>
                  <TD><span className="text-sm font-bold uppercase px-1.5 py-0.5 rounded" style={{
                    background: inv.type === 'payment_receipt' ? '#cffafe' : inv.type === 'final' ? '#dcfce7' : '#dbeafe',
                    color: inv.type === 'payment_receipt' ? '#0891b2' : inv.type === 'final' ? '#1a8a18' : '#2563eb'
                  }}>{TYPE_LABELS[inv.type] || inv.type}</span></TD>
                  <TD>{inv.profiles?.full_name || '—'}</TD>
                  <TD bold>{fmt(inv.total)}</TD>
                  <TD>{fmt(inv.tax_amount)}</TD>
                  <TD>{inv.issue_date ? new Date(inv.issue_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>{inv.due_date ? new Date(inv.due_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD><StatusBadge status={inv.status || 'pending'} /></TD>
                  <TD>
                    <div className="flex gap-1">
                      <SmallBtn onClick={() => generatePdf(inv.id)}>PDF</SmallBtn>
                      <SmallBtn onClick={() => sendEmail(inv.id)}>Email</SmallBtn>
                    </div>
                  </TD>
                </tr>
              )})}
              {invoices.length === 0 && <TRow><TD>Žádné faktury</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <NewInvoiceModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}

      {detailInv && (
        <Modal open title={`Faktura ${detailInv.number || '—'}`} onClose={() => setDetailInv(null)}>
          <div className="grid grid-cols-2 gap-4">
            <DRow label="Číslo" value={detailInv.number} mono />
            <DRow label="Zákazník" value={detailInv.profiles?.full_name || '—'} />
            <DRow label="Částka" value={fmt(detailInv.total)} />
            <DRow label="DPH" value={fmt(detailInv.tax_amount)} />
            <DRow label="Základ" value={fmt(detailInv.subtotal)} />
            <DRow label="Stav" value={detailInv.status || '—'} />
            <DRow label="Vystavení" value={detailInv.issue_date ? new Date(detailInv.issue_date).toLocaleDateString('cs-CZ') : '—'} />
            <DRow label="Splatnost" value={detailInv.due_date ? new Date(detailInv.due_date).toLocaleDateString('cs-CZ') : '—'} />
            <DRow label="Typ" value={detailInv.type || '—'} />
            {detailInv.booking_id && <DRow label="ID rezervace" value={detailInv.booking_id.slice(-8).toUpperCase()} mono />}
          </div>
          <div className="flex justify-end gap-3 mt-5">
            <Button onClick={() => setDetailInv(null)}>Zavřít</Button>
            <SmallBtn onClick={() => generatePdf(detailInv.id)}>PDF</SmallBtn>
            <SmallBtn onClick={() => sendEmail(detailInv.id)}>Email</SmallBtn>
          </div>
        </Modal>
      )}
    </div>
  )
}

function DRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
    </div>
  )
}

function SmallBtn({ children, onClick }) {
  return (
    <button onClick={onClick} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
      style={{ padding: '3px 8px', background: '#f1faf7', color: '#1a2e22', border: 'none' }}>
      {children}
    </button>
  )
}

function NewInvoiceModal({ onClose, onSaved }) {
  const [customers, setCustomers] = useState([])
  const [bookings, setBookings] = useState([])
  const [form, setForm] = useState({ customer_id: '', booking_id: '', type: 'issued', total: '', tax_amount: '', due_date: '', description: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('profiles').select('id, full_name').order('full_name').then(({ data }) => setCustomers(data || []))
    supabase.from('bookings').select('id, start_date, motorcycles(model)').order('start_date', { ascending: false }).limit(50).then(({ data }) => setBookings(data || []))
  }, [])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const totalVal = Number(form.total) || 0
      const taxVal = Number(form.tax_amount) || 0
      const subtotalVal = totalVal - taxVal
      const number = await generateInvoiceNumber(form.type)
      const { error } = await supabase.from('invoices').insert({
        number,
        type: form.type,
        customer_id: form.customer_id || null,
        booking_id: form.booking_id || null,
        subtotal: subtotalVal,
        total: totalVal,
        tax_amount: taxVal,
        due_date: form.due_date || null,
        issue_date: new Date().toISOString().slice(0, 10),
        status: 'issued',
        notes: form.description || null,
      })
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'invoice_created', details: { number } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová faktura" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2">
          <Label>Typ faktury</Label>
          <select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="issued">Vystavená (FV)</option>
            <option value="advance">Zálohová (ZF)</option>
            <option value="final">Konečná (KF)</option>
            <option value="payment_receipt">Doklad k platbě (DP)</option>
            <option value="shop_proforma">Shop zálohová</option>
            <option value="shop_final">Shop konečná</option>
          </select>
        </div>
        <div className="col-span-2">
          <Label>Zákazník</Label>
          <select value={form.customer_id} onChange={e => set('customer_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">—</option>
            {customers.map(c => <option key={c.id} value={c.id}>{c.full_name}</option>)}
          </select>
        </div>
        <div className="col-span-2">
          <Label>Rezervace</Label>
          <select value={form.booking_id} onChange={e => set('booking_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">—</option>
            {bookings.map(b => <option key={b.id} value={b.id}>{b.motorcycles?.model} — {b.start_date}</option>)}
          </select>
        </div>
        <div className="col-span-2">
          <Label>Důvod / popis</Label>
          <input value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}
            placeholder="Oprava poškození, pozdní vrácení, tankování…" />
        </div>
        <div>
          <Label>Částka (Kč)</Label>
          <input type="number" value={form.total} onChange={e => set('total', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>DPH (Kč)</Label>
          <input type="number" value={form.tax_amount} onChange={e => set('tax_amount', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Splatnost</Label>
          <input type="date" value={form.due_date} onChange={e => set('due_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => {
    if (values.includes(val)) onChange(values.filter(v => v !== val))
    else onChange([...values, val])
  }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn"
      style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer"
          style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)}
            className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}
