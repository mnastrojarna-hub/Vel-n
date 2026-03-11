import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'

import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

export default function SuppliersTab() {
  const [suppliers, setSuppliers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [showAdd, setShowAdd] = useState(false)
  const [editing, setEditing] = useState(null)

  useEffect(() => { load() }, [page, search])

  async function load() {
    setLoading(true)
    let query = supabase.from('suppliers').select('*', { count: 'exact' })
    if (search) query = query.or(`name.ilike.%${search}%,ico.ilike.%${search}%,email.ilike.%${search}%`)
    query = query.order('name').range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
    const { data, count, error: err } = await query
    if (err) setError(err.message)
    else { setSuppliers(data || []); setTotal(count || 0) }
    setLoading(false)
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={search} onChange={v => { setPage(1); setSearch(v) }} placeholder="Hledat dodavatele…" />
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nový dodavatel</Button>
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
                <TH>Název</TH><TH>IČO</TH><TH>Kontakt</TH><TH>Email</TH><TH>Kategorie</TH>
              </TRow>
            </thead>
            <tbody>
              {suppliers.map(s => (
                <tr key={s.id} onClick={() => setEditing(s)} className="cursor-pointer hover:bg-[#f1faf7] transition-colors" style={{ borderBottom: '1px solid #d4e8e0' }}>
                  <TD bold>{s.name}</TD>
                  <TD mono>{s.ico || '—'}</TD>
                  <TD>{s.contact_person || '—'}</TD>
                  <TD>{s.email || '—'}</TD>
                  <TD>
                    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase" style={{ padding: '3px 8px', background: '#f1faf7', color: '#1a2e22' }}>
                      {s.category || '—'}
                    </span>
                  </TD>
                </tr>
              ))}
              {suppliers.length === 0 && <TRow><TD>Žádní dodavatelé</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {(showAdd || editing) && (
        <SupplierModal entry={editing} onClose={() => { setShowAdd(false); setEditing(null) }} onSaved={() => { setShowAdd(false); setEditing(null); load() }} />
      )}
    </div>
  )
}

function SupplierModal({ entry, onClose, onSaved }) {
  const [form, setForm] = useState(entry ? {
    name: entry.name || '', ico: entry.ico || '', contact_person: entry.contact_person || '',
    email: entry.email || '', phone: entry.phone || '', category: entry.category || '',
  } : { name: '', ico: '', contact_person: '', email: '', phone: '', category: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      if (entry) {
        const result = await debugAction('supplier.update', 'SupplierModal', () =>
          supabase.from('suppliers').update(form).eq('id', entry.id)
        , form)
        if (result?.error) throw result.error
      } else {
        const result = await debugAction('supplier.create', 'SupplierModal', () =>
          supabase.from('suppliers').insert(form)
        , form)
        if (result?.error) throw result.error
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={entry ? 'Upravit dodavatele' : 'Nový dodavatel'} onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2"><Label>Název</Label><input value={form.name} onChange={e => set('name', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>IČO</Label><input value={form.ico} onChange={e => set('ico', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Kategorie</Label><input value={form.category} onChange={e => set('category', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Kontaktní osoba</Label><input value={form.contact_person} onChange={e => set('contact_person', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Telefon</Label><input value={form.phone} onChange={e => set('phone', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div className="col-span-2"><Label>Email</Label><input type="email" value={form.email} onChange={e => set('email', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.name}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
