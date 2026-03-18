import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Modal from '../components/ui/Modal'

const PER_PAGE = 25

const COUNTRY_OPTS = [
  { value: '', label: 'Všechny země' },
  { value: 'CZ', label: 'Česko' }, { value: 'SK', label: 'Slovensko' },
  { value: 'DE', label: 'Německo' }, { value: 'AT', label: 'Rakousko' },
  { value: 'PL', label: 'Polsko' },
]
const LICENSE_GROUPS = ['A', 'A1', 'A2', 'AM', 'B']

export default function Customers() {
  const debugMode = useDebugMode()
  const navigate = useNavigate()
  const [customers, setCustomers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [showFilters, setShowFilters] = useState(false)
  const defaultFilters = {
    search: '', city: '', country: '', licenseGroups: [],
    regFrom: '', regTo: '', minBookings: '', maxBookings: '',
    sortBy: 'full_name', sortDir: 'asc'
  }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_customers_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_customers_filters', JSON.stringify(filters)) }, [filters])
  const search = filters.search || ''
  const [stats, setStats] = useState({})

  useEffect(() => { loadCustomers() }, [page, search, filters])

  async function loadCustomers() {
    setLoading(true)
    setError(null)
    try {
      const result = await debugAction('customers.load', 'Customers', () => {
        let query = supabase.from('profiles').select('*, bookings(count)', { count: 'exact' })
        if (search) query = query.or(`full_name.ilike.%${search}%,email.ilike.%${search}%,phone.ilike.%${search}%`)
        if (filters.city) query = query.ilike('city', `%${filters.city}%`)
        if (filters.country) query = query.eq('country', filters.country)
        if (filters.licenseGroups?.length > 0) query = query.overlaps('license_group', filters.licenseGroups)
        else if (filters.licenseGroup) query = query.contains('license_group', [filters.licenseGroup])
        if (filters.regFrom) query = query.gte('created_at', filters.regFrom)
        if (filters.regTo) query = query.lte('created_at', filters.regTo + 'T23:59:59')
        return query.order(filters.sortBy, { ascending: filters.sortDir === 'asc' })
          .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      }, { page, search, filters })
      if (result?.error) throw result.error
      let data = result?.data || []
      // Client-side filter by booking count (aggregated)
      if (filters.minBookings) data = data.filter(c => (c.bookings?.[0]?.count ?? 0) >= Number(filters.minBookings))
      if (filters.maxBookings) data = data.filter(c => (c.bookings?.[0]?.count ?? 0) <= Number(filters.maxBookings))
      setCustomers(data)
      setTotal(result?.count || 0)
      // Load aggregated stats for active filters
      loadStats(data)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function loadStats(custs) {
    try {
      const ids = custs.map(c => c.id)
      if (!ids.length) { setStats({}); return }
      const { data: bks } = await supabase.from('bookings')
        .select('user_id, total_price, start_date, end_date, status, moto_id, motorcycles(model, branches(name))')
        .in('user_id', ids.slice(0, 50))
      if (!bks) return
      const map = {}
      bks.forEach(b => {
        if (!map[b.user_id]) map[b.user_id] = { total: 0, sum: 0, days: 0, motos: {}, branches: {}, incidents: 0 }
        const s = map[b.user_id]
        s.total++
        s.sum += b.total_price || 0
        const d = Math.max(1, Math.ceil((new Date(b.end_date) - new Date(b.start_date)) / 86400000))
        s.days += d
        if (b.motorcycles?.model) s.motos[b.motorcycles.model] = (s.motos[b.motorcycles.model] || 0) + 1
        if (b.motorcycles?.branches?.name) s.branches[b.motorcycles.branches.name] = (s.branches[b.motorcycles.branches.name] || 0) + 1
        if (b.status === 'incident') s.incidents++
      })
      setStats(map)
    } catch (e) { console.error('stats err', e) }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const activeFilterCount = Object.entries(filters).filter(([k, v]) => {
    if (['search', 'sortBy', 'sortDir'].includes(k)) return false
    if (Array.isArray(v)) return v.length > 0
    return !!v
  }).length
  const setF = (k, v) => { setPage(1); setFilters(f => ({ ...f, [k]: v })) }
  const resetFilters = () => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_customers_filters') }

  const topMoto = (uid) => { const s = stats[uid]; if (!s || !Object.keys(s.motos).length) return '—'; return Object.entries(s.motos).sort((a, b) => b[1] - a[1])[0][0] }
  const topBranch = (uid) => { const s = stats[uid]; if (!s || !Object.keys(s.branches).length) return '—'; return Object.entries(s.branches).sort((a, b) => b[1] - a[1])[0][0] }
  const avgPrice = (uid) => { const s = stats[uid]; if (!s || !s.total) return '—'; return Math.round(s.sum / s.total).toLocaleString('cs-CZ') + ' Kč' }
  const avgDays = (uid) => { const s = stats[uid]; if (!s || !s.total) return '—'; return Math.round(s.days / s.total) + ' d' }

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat jméno, email, telefon…" />
        <CheckboxFilterGroup label="ŘP" values={filters.licenseGroups || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, licenseGroups: v })) }}
          options={LICENSE_GROUPS.map(g => ({ value: g, label: g }))} />
        <select value={filters.sortBy} onChange={e => setF('sortBy', e.target.value)}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="full_name">Dle jména</option>
          <option value="created_at">Dle registrace</option>
          <option value="city">Dle města</option>
          <option value="country">Dle země</option>
        </select>
        <select value={filters.sortDir} onChange={e => setF('sortDir', e.target.value)}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="asc">↑ Vzestupně</option>
          <option value="desc">↓ Sestupně</option>
        </select>
        <button onClick={() => setShowFilters(!showFilters)}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: showFilters ? '#74FB71' : '#f1faf7', border: '1px solid #d4e8e0', color: showFilters ? '#1a2e22' : '#1a2e22' }}>
          ☰ Filtry {activeFilterCount > 0 && <span className="ml-1 inline-block rounded-full text-sm" style={{ background: '#74FB71', color: '#1a2e22', padding: '1px 6px' }}>{activeFilterCount}</span>}
        </button>
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nový zákazník</Button>
        </div>
      </div>

      {showFilters && (
        <div className="mb-5 p-4 rounded-card" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Rozšířené filtry</span>
            <button onClick={resetFilters} className="text-sm font-bold cursor-pointer underline" style={{ color: '#1a2e22' }}>Resetovat</button>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <FilterField label="Město" value={filters.city} onChange={v => setF('city', v)} />
            <div>
              <FLabel>Země</FLabel>
              <FSelect value={filters.country} onChange={v => setF('country', v)} options={COUNTRY_OPTS} />
            </div>
            <div>
              <FLabel>Skupina ŘP</FLabel>
              <FSelect value={filters.licenseGroup} onChange={v => setF('licenseGroup', v)}
                options={[{ value: '', label: 'Všechny' }, ...LICENSE_GROUPS.map(g => ({ value: g, label: g }))]} />
            </div>
            <FilterField label="Registrace od" value={filters.regFrom} onChange={v => setF('regFrom', v)} type="date" />
            <FilterField label="Registrace do" value={filters.regTo} onChange={v => setF('regTo', v)} type="date" />
            <FilterField label="Min. rezervací" value={filters.minBookings} onChange={v => setF('minBookings', v)} type="number" />
            <FilterField label="Max. rezervací" value={filters.maxBookings} onChange={v => setF('maxBookings', v)} type="number" />
            <div>
              <FLabel>Řadit dle</FLabel>
              <FSelect value={filters.sortBy} onChange={v => setF('sortBy', v)}
                options={[{ value: 'full_name', label: 'Jméno' }, { value: 'created_at', label: 'Registrace' }, { value: 'city', label: 'Město' }, { value: 'country', label: 'Země' }]} />
            </div>
          </div>
        </div>
      )}

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={loadCustomers} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
        </div>
      )}

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA Customers</strong><br/>
        <div>profiles: {customers.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: search="{search}", city="{filters.city}", country={filters.country || 'vše'}, licenseGroups={filters.licenseGroups?.length > 0 ? filters.licenseGroups.join(',') : 'vše'}</div>
        <div>sort: {filters.sortBy} {filters.sortDir}, stats loaded: {Object.keys(stats).length} zákazníků</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
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
                <TH>Skupiny</TH><TH>Město</TH><TH>Země</TH><TH>Registrace</TH><TH>Rezervací</TH>
                <TH>Ø částka</TH><TH>Ø délka</TH><TH>Top motorka</TH><TH>Top pobočka</TH>
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
                  <TD>{c.country || '—'}</TD>
                  <TD>{c.created_at?.slice(0, 10) || '—'}</TD>
                  <TD bold>{c.bookings?.[0]?.count ?? 0}</TD>
                  <TD>{avgPrice(c.id)}</TD>
                  <TD>{avgDays(c.id)}</TD>
                  <TD>{topMoto(c.id)}</TD>
                  <TD>{topBranch(c.id)}</TD>
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

function FLabel({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
function FSelect({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="w-full rounded-btn text-sm outline-none cursor-pointer"
      style={{ padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}
function FilterField({ label, value, onChange, type = 'text' }) {
  return (
    <div>
      <FLabel>{label}</FLabel>
      <input type={type} value={value} onChange={e => onChange(e.target.value)}
        className="w-full rounded-btn text-sm outline-none"
        style={{ padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }} />
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
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
      <input value={value} onChange={e => onChange(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}
