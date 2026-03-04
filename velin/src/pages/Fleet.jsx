import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import StatusBadge from '../components/ui/StatusBadge'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Modal from '../components/ui/Modal'

const PER_PAGE = 25

const CATEGORIES = ['Naked', 'Sport', 'Adventure', 'Cruiser', 'Scooter', 'Enduro', 'Custom']

export default function Fleet() {
  const navigate = useNavigate()
  const [motos, setMotos] = useState([])
  const [branches, setBranches] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState({ status: '', branch: '', category: '', search: '' })
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => {
    loadBranches()
  }, [])

  useEffect(() => {
    loadMotos()
  }, [page, filters])

  async function loadBranches() {
    const { data } = await supabase.from('branches').select('id, name').order('name')
    if (data) setBranches(data)
  }

  async function loadMotos() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase
        .from('motorcycles')
        .select('*, branches(name)', { count: 'exact' })

      if (filters.status) query = query.eq('status', filters.status)
      if (filters.branch) query = query.eq('branch_id', filters.branch)
      if (filters.category) query = query.eq('category', filters.category)
      if (filters.search) query = query.or(`model.ilike.%${filters.search}%,spz.ilike.%${filters.search}%`)

      query = query.order('model').range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await query
      if (err) throw err
      setMotos(data || [])
      setTotal(count || 0)
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
        <SearchInput
          value={filters.search}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }}
          placeholder="Hledat model, SPZ…"
        />
        <FilterSelect
          value={filters.status}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, status: v })) }}
          options={[
            { value: '', label: 'Všechny stavy' },
            { value: 'active', label: 'Aktivní' },
            { value: 'maintenance', label: 'Servis' },
            { value: 'out_of_service', label: 'Vyřazeno' },
          ]}
        />
        <FilterSelect
          value={filters.branch}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, branch: v })) }}
          options={[
            { value: '', label: 'Všechny pobočky' },
            ...branches.map(b => ({ value: b.id, label: b.name })),
          ]}
        />
        <FilterSelect
          value={filters.category}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, category: v })) }}
          options={[
            { value: '', label: 'Všechny kategorie' },
            ...CATEGORIES.map(c => ({ value: c, label: c })),
          ]}
        />
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová motorka</Button>
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={loadMotos} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" />
        </div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Model</TH><TH>SPZ</TH><TH>Kategorie</TH><TH>Pobočka</TH>
                <TH>Status</TH><TH>Km</TH><TH>Kč/den</TH><TH>Další servis</TH>
              </TRow>
            </thead>
            <tbody>
              {motos.map(m => (
                <tr
                  key={m.id}
                  onClick={() => navigate(`/flotila/${m.id}`)}
                  className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                  style={{ borderBottom: '1px solid #d4e8e0' }}
                >
                  <TD bold>{m.model}</TD>
                  <TD mono>{m.spz}</TD>
                  <TD>{m.category || '—'}</TD>
                  <TD>{m.branches?.name || '—'}</TD>
                  <TD><StatusBadge status={m.status} /></TD>
                  <TD mono>{m.km?.toLocaleString('cs-CZ') || '—'}</TD>
                  <TD bold>{m.price_per_day ? `${m.price_per_day.toLocaleString('cs-CZ')} Kč` : '—'}</TD>
                  <TD>{m.next_service_date || '—'}</TD>
                </tr>
              ))}
              {motos.length === 0 && (
                <TRow><TD>Žádné motorky</TD></TRow>
              )}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddMotoModal branches={branches} onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); loadMotos() }} />}
    </div>
  )
}

function FilterSelect({ value, onChange, options }) {
  return (
    <select
      value={value}
      onChange={e => onChange(e.target.value)}
      className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
      style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}
    >
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}

function AddMotoModal({ branches, onClose, onSaved }) {
  const [form, setForm] = useState({ model: '', spz: '', vin: '', category: '', branch_id: '', price_per_day: '', km: 0, status: 'active' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true)
    setErr(null)
    try {
      const { error } = await supabase.from('motorcycles').insert({
        ...form,
        price_per_day: Number(form.price_per_day) || 0,
        km: Number(form.km) || 0,
        branch_id: form.branch_id || null,
      })
      if (error) throw error
      onSaved()
    } catch (e) {
      setErr(e.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal open title="Nová motorka" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <FormField label="Model" value={form.model} onChange={v => set('model', v)} />
        <FormField label="SPZ" value={form.spz} onChange={v => set('spz', v)} />
        <FormField label="VIN" value={form.vin} onChange={v => set('vin', v)} />
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Kategorie</label>
          <select value={form.category} onChange={e => set('category', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">—</option>
            {['Naked','Sport','Adventure','Cruiser','Scooter','Enduro','Custom'].map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Pobočka</label>
          <select value={form.branch_id} onChange={e => set('branch_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">—</option>
            {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        </div>
        <FormField label="Cena/den (Kč)" value={form.price_per_day} onChange={v => set('price_per_day', v)} type="number" />
        <FormField label="Km" value={form.km} onChange={v => set('km', v)} type="number" />
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.model}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}

function FormField({ label, value, onChange, type = 'text' }) {
  return (
    <div>
      <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{label}</label>
      <input type={type} value={value} onChange={e => onChange(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}
