import { useState, useEffect } from 'react'
import BulkActionsBar, { SelectAllCheckbox, RowCheckbox } from '../../components/ui/BulkActionsBar'
import { exportToCsv, bulkDelete } from '../../lib/bulkActions'
import { supabase } from '../../lib/supabase'
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
  const [editSupplier, setEditSupplier] = useState(null)
  const [showAdd, setShowAdd] = useState(false)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [selectedIds, setSelectedIds] = useState(new Set())

  useEffect(() => { load() }, [page, search])

  async function load() {
    setLoading(true); setError(null)
    try {
      let query = supabase.from('suppliers')
        .select('*', { count: 'exact' })
        .order('name', { ascending: true })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      if (search) query = query.or(`name.ilike.%${search}%,ico.ilike.%${search}%`)
      const { data, count, error: err } = await query
      if (err) throw err
      setSuppliers(data || [])
      setTotal(count || 0)
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function handleDelete(supplier) {
    try {
      const { error: err } = await supabase.from('suppliers').delete().eq('id', supplier.id)
      if (err) throw err
      setDeleteConfirm(null)
      load()
    } catch (e) { setError(e.message) }
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={search} onChange={v => { setPage(1); setSearch(v) }} placeholder="Hledat dodavatele, IČO…" />
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nový dodavatel</Button>
        </div>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <BulkActionsBar count={selectedIds.size} onClear={() => setSelectedIds(new Set())} actions={[
            { label: 'Kopírovat e-maily', icon: '📧', onClick: () => {
              const emails = suppliers.filter(s => selectedIds.has(s.id)).map(s => s.contact_email).filter(Boolean).join(', ')
              if (emails) navigator.clipboard.writeText(emails)
            } },
            { label: 'Export CSV', icon: '⬇', onClick: () => exportToCsv('suppliers-acc', [
              { key: 'name', label: 'Název' }, { key: 'ico', label: 'IČO' }, { key: 'dic', label: 'DIČ' },
              { key: 'bank_account', label: 'Bankovní účet' }, { key: 'default_category', label: 'Kategorie' },
              { key: 'contact_email', label: 'Email' }, { key: 'address', label: 'Adresa' },
            ], suppliers.filter(s => selectedIds.has(s.id))) },
            { label: 'Smazat', icon: '🗑', danger: true, confirm: 'Trvale smazat {count} dodavatelů?', onClick: async () => { await bulkDelete('suppliers', [...selectedIds], 'suppliers_acc_bulk_deleted'); setSelectedIds(new Set()); load() } },
          ]} />
          <Table>
            <thead>
              <TRow header>
                <TH><SelectAllCheckbox items={suppliers} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TH>
                <TH>Název</TH><TH>IČO</TH><TH>DIČ</TH><TH>Bankovní účet</TH>
                <TH>Kategorie</TH><TH>Kontakt</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {suppliers.map(s => (
                <TRow key={s.id}>
                  <TD><RowCheckbox id={s.id} selectedIds={selectedIds} setSelectedIds={setSelectedIds} stopPropagation={false} /></TD>
                  <TD bold>{s.name || '—'}</TD>
                  <TD mono>{s.ico || '—'}</TD>
                  <TD mono>{s.dic || '—'}</TD>
                  <TD mono>{s.bank_account || '—'}</TD>
                  <TD>{s.default_category || '—'}</TD>
                  <TD>{s.contact_email || '—'}</TD>
                  <TD>
                    <div className="flex gap-1">
                      <button onClick={() => setEditSupplier(s)}
                        className="text-sm font-bold cursor-pointer"
                        style={{ color: '#2563eb', background: 'none', border: 'none', padding: '4px 6px' }}>
                        Upravit
                      </button>
                      <button onClick={() => setDeleteConfirm(s)}
                        className="text-sm font-bold cursor-pointer"
                        style={{ color: '#dc2626', background: 'none', border: 'none', padding: '4px 6px' }}>
                        Smazat
                      </button>
                    </div>
                  </TD>
                </TRow>
              ))}
              {suppliers.length === 0 && <TRow><TD>Žádní dodavatelé</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {(showAdd || editSupplier) && (
        <SupplierModal
          supplier={editSupplier}
          onClose={() => { setShowAdd(false); setEditSupplier(null) }}
          onSaved={() => { setShowAdd(false); setEditSupplier(null); load() }}
        />
      )}

      {deleteConfirm && (
        <Modal open title="Smazat dodavatele?" onClose={() => setDeleteConfirm(null)}>
          <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
            Opravdu chcete smazat dodavatele <strong>{deleteConfirm.name}</strong>?
          </p>
          <div className="flex justify-end gap-3">
            <Button onClick={() => setDeleteConfirm(null)}>Zrušit</Button>
            <button onClick={() => handleDelete(deleteConfirm)}
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

function SupplierModal({ supplier, onClose, onSaved }) {
  const isEdit = !!supplier
  const [form, setForm] = useState({
    name: supplier?.name || '',
    ico: supplier?.ico || '',
    dic: supplier?.dic || '',
    address: supplier?.address || '',
    bank_account: supplier?.bank_account || '',
    default_category: supplier?.default_category || '',
    default_account: supplier?.default_account || '',
    contact_email: supplier?.contact_email || '',
    notes: supplier?.notes || '',
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    if (!form.name) return setErr('Vyplňte název dodavatele.')
    setSaving(true); setErr(null)
    try {
      const normalized = form.name.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim()
      const payload = { ...form, normalized_name: normalized }
      if (isEdit) {
        const { error } = await supabase.from('suppliers').update(payload).eq('id', supplier.id)
        if (error) throw error
      } else {
        const { error } = await supabase.from('suppliers').insert(payload)
        if (error) throw error
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  const CATEGORIES = [
    '', 'phm', 'pojisteni', 'servis_opravy', 'najem', 'energie',
    'telekomunikace', 'marketing', 'kancelar', 'ostatni_naklady',
  ]
  const CAT_LABELS = {
    '': '— Neurčeno —', phm: 'PHM', pojisteni: 'Pojištění', servis_opravy: 'Servis/Opravy',
    najem: 'Nájem', energie: 'Energie', telekomunikace: 'Telekomunikace',
    marketing: 'Marketing', kancelar: 'Kancelář', ostatni_naklady: 'Ostatní',
  }

  return (
    <Modal open title={isEdit ? 'Upravit dodavatele' : 'Nový dodavatel'} onClose={onClose}>
      <div className="space-y-3">
        <div><Label>Název *</Label><input value={form.name} onChange={e => set('name', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div className="grid grid-cols-2 gap-3">
          <div><Label>IČO</Label><input value={form.ico} onChange={e => set('ico', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
          <div><Label>DIČ</Label><input value={form.dic} onChange={e => set('dic', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        </div>
        <div><Label>Adresa</Label><input value={form.address} onChange={e => set('address', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Bankovní účet</Label><input value={form.bank_account} onChange={e => set('bank_account', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label>Výchozí kategorie</Label>
            <select value={form.default_category} onChange={e => set('default_category', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
              {CATEGORIES.map(c => <option key={c} value={c}>{CAT_LABELS[c] || c}</option>)}
            </select>
          </div>
          <div><Label>Výchozí účet</Label><input value={form.default_account} onChange={e => set('default_account', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        </div>
        <div><Label>Kontaktní email</Label><input type="email" value={form.contact_email} onChange={e => set('contact_email', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Poznámka</Label><textarea value={form.notes} onChange={e => set('notes', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60 }} /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
