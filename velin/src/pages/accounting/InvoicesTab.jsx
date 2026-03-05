import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

export default function InvoicesTab() {
  const [invoices, setInvoices] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => { load() }, [page, search])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase
        .from('invoices')
        .select('*, profiles(full_name)', { count: 'exact' })
      if (search) query = query.or(`number.ilike.%${search}%`)
      query = query.order('issue_date', { ascending: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await query
      if (err) throw err
      setInvoices(data || [])
      setTotal(count || 0)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function generatePdf(invoiceId) {
    try {
      const { data, error } = await supabase.functions.invoke('generate-document', {
        body: { type: 'invoice', invoice_id: invoiceId },
      })
      if (error) throw error
      if (data?.url) window.open(data.url, '_blank')
    } catch (e) {
      setError('Generování PDF selhalo: ' + e.message)
    }
  }

  async function sendEmail(invoiceId) {
    try {
      const { error } = await supabase.functions.invoke('send-email', {
        body: { type: 'invoice', invoice_id: invoiceId },
      })
      if (error) throw error
      alert('Email odeslán')
    } catch (e) {
      setError('Odeslání emailu selhalo: ' + e.message)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <SearchInput value={search} onChange={v => { setPage(1); setSearch(v) }} placeholder="Hledat číslo, zákazníka…" />
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová faktura</Button>
        </div>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Číslo</TH><TH>Zákazník</TH><TH>Částka</TH><TH>DPH</TH>
                <TH>Vystavení</TH><TH>Splatnost</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {invoices.map(inv => (
                <TRow key={inv.id}>
                  <TD mono bold>{inv.number || '—'}</TD>
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
                </TRow>
              ))}
              {invoices.length === 0 && <TRow><TD>Žádné faktury</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <NewInvoiceModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
    </div>
  )
}

function SmallBtn({ children, onClick }) {
  return (
    <button onClick={onClick} className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer"
      style={{ padding: '3px 8px', background: '#f1faf7', color: '#4a6357', border: 'none' }}>
      {children}
    </button>
  )
}

function NewInvoiceModal({ onClose, onSaved }) {
  const [customers, setCustomers] = useState([])
  const [bookings, setBookings] = useState([])
  const [form, setForm] = useState({ customer_id: '', booking_id: '', total: '', tax_amount: '', due_date: '' })
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
      const { error } = await supabase.from('invoices').insert({
        customer_id: form.customer_id || null,
        booking_id: form.booking_id || null,
        total: Number(form.total) || 0,
        tax_amount: Number(form.tax_amount) || 0,
        due_date: form.due_date || null,
        issue_date: new Date().toISOString().slice(0, 10),
        status: 'unpaid',
      })
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'invoice_created', details: {} })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová faktura" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
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
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
