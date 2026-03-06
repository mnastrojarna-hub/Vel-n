import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Modal from '../components/ui/Modal'

const PER_PAGE = 25

export default function Customers() {
  const navigate = useNavigate()
  const [customers, setCustomers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => { loadCustomers() }, [page, search])

  async function loadCustomers() {
    setLoading(true)
    setError(null)
    try {
      const result = await debugAction('customers.load', 'Customers', () => {
        let query = supabase.from('profiles').select('*, bookings(count)', { count: 'exact' })
        if (search) query = query.or(`full_name.ilike.%${search}%,email.ilike.%${search}%,phone.ilike.%${search}%`)
        return query.order('full_name').range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      }, { page, search })
      if (result?.error) throw result.error
      setCustomers(result?.data || [])
      setTotal(result?.count || 0)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput value={search} onChange={v => { setPage(1); setSearch(v) }} placeholder="Hledat jméno, email, telefon…" />
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nový zákazník</Button>
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={loadCustomers} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Jméno</TH><TH>Email</TH><TH>Telefon</TH>
                <TH>Skupiny</TH><TH>Město</TH><TH>Registrace</TH><TH>Rezervací</TH>
              </TRow>
            </thead>
            <tbody>
              {customers.map(c => (
                <tr key={c.id} onClick={() => navigate(`/zakaznici/${c.id}`)}
                  className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                  style={{ borderBottom: '1px solid #d4e8e0' }}>
                  <TD bold>{c.full_name || '—'}</TD>
                  <TD>{c.email || '—'}</TD>
                  <TD mono>{c.phone || '—'}</TD>
                  <TD>
                    {c.license_group?.length > 0
                      ? c.license_group.map(g => <Badge key={g} label={g} color="#1a8a18" bg="#dcfce7" />)
                      : '—'
                    }
                  </TD>
                  <TD>{c.city || '—'}</TD>
                  <TD>{c.created_at?.slice(0, 10) || '—'}</TD>
                  <TD bold>{c.bookings?.[0]?.count ?? 0}</TD>
                </tr>
              ))}
              {customers.length === 0 && <TRow><TD>Žádní zákazníci</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddCustomerModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); loadCustomers() }} />}
    </div>
  )
}

function AddCustomerModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ full_name: '', email: '', phone: '', street: '', city: '', zip: '', country: 'CZ' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true)
    setErr(null)
    try {
      const result = await debugAction('customers.create', 'AddCustomerModal', () =>
        supabase.from('profiles').insert({ ...form, id: crypto.randomUUID() })
      , form)
      if (result?.error) throw result.error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'customer_created', details: { email: form.email } })
      onSaved()
    } catch (e) {
      setErr(e.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal open title="Nový zákazník" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Jméno" value={form.full_name} onChange={v => set('full_name', v)} />
        <Field label="Email" value={form.email} onChange={v => set('email', v)} />
        <Field label="Telefon" value={form.phone} onChange={v => set('phone', v)} />
        <Field label="Ulice" value={form.street} onChange={v => set('street', v)} />
        <Field label="Město" value={form.city} onChange={v => set('city', v)} />
        <Field label="PSČ" value={form.zip} onChange={v => set('zip', v)} />
        <Field label="Země" value={form.country} onChange={v => set('country', v)} />
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.full_name}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}

function Field({ label, value, onChange }) {
  return (
    <div>
      <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{label}</label>
      <input value={value} onChange={e => onChange(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}
