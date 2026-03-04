import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { isDemoMode, INVENTORY } from '../lib/demoData'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Modal from '../components/ui/Modal'

const PER_PAGE = 25

export default function Inventory() {
  const navigate = useNavigate()
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState({ search: '', category: '', stock: '' })
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      if (isDemoMode()) {
        let filtered = [...INVENTORY]
        if (filters.search) {
          const s = filters.search.toLowerCase()
          filtered = filtered.filter(i => i.name.toLowerCase().includes(s) || i.sku.toLowerCase().includes(s))
        }
        if (filters.category) filtered = filtered.filter(i => i.category === filters.category)
        if (filters.stock === 'low') filtered = filtered.filter(i => i.stock <= i.min_stock)
        if (filters.stock === 'ok') filtered = filtered.filter(i => i.stock > i.min_stock)
        setTotal(filtered.length)
        setItems(filtered.slice((page - 1) * PER_PAGE, page * PER_PAGE))
        setLoading(false)
        return
      }

      let query = supabase
        .from('inventory')
        .select('*, suppliers(name)', { count: 'exact' })

      if (filters.search) query = query.or(`name.ilike.%${filters.search}%,sku.ilike.%${filters.search}%`)
      if (filters.category) query = query.eq('category', filters.category)

      query = query.order('name').range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await query
      if (err) throw err

      let filtered = data || []
      if (filters.stock === 'low') filtered = filtered.filter(i => i.stock <= i.min_stock)
      if (filters.stock === 'ok') filtered = filtered.filter(i => i.stock > i.min_stock)

      setItems(filtered)
      setTotal(count || 0)
    } catch (e) {
      setError(e.message)
      // Fallback to demo data
      setItems(INVENTORY.slice((page - 1) * PER_PAGE, page * PER_PAGE))
      setTotal(INVENTORY.length)
    } finally {
      setLoading(false)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput
          value={filters.search}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }}
          placeholder="Hledat SKU, název…"
        />
        <FilterSelect
          value={filters.stock}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, stock: v })) }}
          options={[
            { value: '', label: 'Všechny zásoby' },
            { value: 'low', label: 'Nízké zásoby' },
            { value: 'ok', label: 'Dostatečné' },
          ]}
        />
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová položka</Button>
        </div>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>SKU</TH><TH>Název</TH><TH>Kategorie</TH><TH>Sklad</TH>
                <TH>Minimum</TH><TH>Stav</TH><TH>Cena/ks</TH><TH>Dodavatel</TH>
              </TRow>
            </thead>
            <tbody>
              {items.map(item => {
                const isLow = item.stock <= item.min_stock
                return (
                  <tr
                    key={item.id}
                    onClick={() => navigate(`/sklady/${item.id}`)}
                    className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                    style={{ borderBottom: '1px solid #d4e8e0', background: isLow ? '#fff5f5' : 'transparent' }}
                  >
                    <TD mono bold>{item.sku || '—'}</TD>
                    <TD bold>{item.name}</TD>
                    <TD>{item.category || '—'}</TD>
                    <TD bold color={isLow ? '#dc2626' : '#0f1a14'}>{item.stock ?? 0}</TD>
                    <TD>{item.min_stock ?? 0}</TD>
                    <TD>
                      <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                        style={{ padding: '4px 10px', background: isLow ? '#fee2e2' : '#dcfce7', color: isLow ? '#dc2626' : '#1a8a18' }}>
                        {isLow ? 'Nízké' : 'OK'}
                      </span>
                    </TD>
                    <TD>{item.unit_price ? fmt(item.unit_price) : '—'}</TD>
                    <TD>{item.suppliers?.name || '—'}</TD>
                  </tr>
                )
              })}
              {items.length === 0 && <TRow><TD>Žádné položky</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddItemModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
    </div>
  )
}

function FilterSelect({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
      style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}

function AddItemModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ name: '', sku: '', category: '', stock: 0, min_stock: 0, unit_price: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('inventory').insert({
        ...form, stock: Number(form.stock) || 0, min_stock: Number(form.min_stock) || 0,
        unit_price: Number(form.unit_price) || 0,
      })
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'inventory_item_created', details: {} })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová skladová položka" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <FormField label="Název" value={form.name} onChange={v => set('name', v)} />
        <FormField label="SKU" value={form.sku} onChange={v => set('sku', v)} />
        <FormField label="Kategorie" value={form.category} onChange={v => set('category', v)} />
        <FormField label="Cena/ks (Kč)" value={form.unit_price} onChange={v => set('unit_price', v)} type="number" />
        <FormField label="Počáteční stav" value={form.stock} onChange={v => set('stock', v)} type="number" />
        <FormField label="Minimum" value={form.min_stock} onChange={v => set('min_stock', v)} type="number" />
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.name}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}

function FormField({ label, value, onChange, type = 'text' }) {
  return (
    <div>
      <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{label}</label>
      <input type={type} value={value} onChange={e => onChange(e.target.value)}
        className="w-full rounded-btn text-sm outline-none"
        style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}
