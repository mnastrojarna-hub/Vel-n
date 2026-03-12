import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import StatusBadge from '../components/ui/StatusBadge'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Modal from '../components/ui/Modal'
import MotoActionModal from '../components/fleet/MotoActionModal'

const PER_PAGE = 25

const CATEGORIES = [
  { value: 'cestovni', label: 'Cestovní' },
  { value: 'sportovni', label: 'Sportovní' },
  { value: 'naked', label: 'Naked' },
  { value: 'chopper', label: 'Chopper' },
  { value: 'detske', label: 'Dětské' },
]

const CAT_LABELS = { cestovni: 'Cestovní', sportovni: 'Sportovní', naked: 'Naked', chopper: 'Chopper', detske: 'Dětské' }

export default function Fleet() {
  const navigate = useNavigate()
  const [motos, setMotos] = useState([])
  const [branches, setBranches] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState({ status: '', branch: '', category: '', search: '', sort: 'model', occupiedToday: false, occupiedFrom: '', occupiedTo: '' })
  const [showAdd, setShowAdd] = useState(false)
  const [actionMoto, setActionMoto] = useState(null)
  const [bookingCounts, setBookingCounts] = useState({})
  const [todayOccupied, setTodayOccupied] = useState(new Set())
  const [dateOccupied, setDateOccupied] = useState(new Set())

  useEffect(() => {
    loadBranches()
    loadBookingStats()
  }, [])

  useEffect(() => {
    loadMotos()
  }, [page, filters])

  useEffect(() => {
    if (filters.occupiedFrom && filters.occupiedTo) loadDateOccupied()
    else setDateOccupied(new Set())
  }, [filters.occupiedFrom, filters.occupiedTo])

  async function loadBranches() {
    try {
      const { data } = await supabase.from('branches').select('id, name').order('name')
      if (data) setBranches(data)
    } catch {
    }
  }

  async function loadBookingStats() {
    try {
      const today = new Date().toISOString().slice(0, 10)
      const { data: allBookings } = await supabase
        .from('bookings').select('moto_id, start_date, end_date')
        .in('status', ['pending', 'active', 'reserved'])
      const counts = {}
      const todaySet = new Set()
      ;(allBookings || []).forEach(b => {
        if (!b.moto_id) return
        counts[b.moto_id] = (counts[b.moto_id] || 0) + 1
        const s = b.start_date?.split('T')[0], e = b.end_date?.split('T')[0]
        if (s && e && today >= s && today <= e) todaySet.add(b.moto_id)
      })
      setBookingCounts(counts)
      setTodayOccupied(todaySet)
    } catch {}
  }

  async function loadDateOccupied() {
    try {
      const { data } = await supabase
        .from('bookings').select('moto_id')
        .in('status', ['pending', 'active', 'reserved'])
        .lte('start_date', filters.occupiedTo)
        .gte('end_date', filters.occupiedFrom)
      setDateOccupied(new Set((data || []).map(b => b.moto_id)))
    } catch {}
  }

  async function loadMotos() {
    setLoading(true)
    setError(null)
    try {
      const result = await debugAction('fleet.load', 'Fleet', () => {
        let query = supabase.from('motorcycles').select('*, branches(name), image_url, images', { count: 'exact' })
        if (filters.status) query = query.eq('status', filters.status)
        if (filters.branch) query = query.eq('branch_id', filters.branch)
        if (filters.category) query = query.eq('category', filters.category)
        if (filters.search) query = query.or(`model.ilike.%${filters.search}%,spz.ilike.%${filters.search}%`)
        const sortMap = { model: 'model', acquired_desc: 'acquired_at', acquired_asc: 'acquired_at', mileage_desc: 'mileage', mileage_asc: 'mileage' }
        const sortCol = sortMap[filters.sort] || 'model'
        const sortAsc = filters.sort === 'mileage_asc' || filters.sort === 'acquired_asc' || filters.sort === 'model'
        return query.order(sortCol, { ascending: sortAsc }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      }, { page, filters })
      if (result?.error) throw result.error
      let data = result?.data || []
      if (filters.occupiedToday) data = data.filter(m => todayOccupied.has(m.id))
      if (filters.occupiedFrom && filters.occupiedTo) data = data.filter(m => dateOccupied.has(m.id))
      if (filters.sort === 'utilization') data.sort((a, b) => (bookingCounts[b.id] || 0) - (bookingCounts[a.id] || 0))
      setMotos(data)
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
            ...CATEGORIES,
          ]}
        />
        <FilterSelect
          value={filters.sort}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, sort: v })) }}
          options={[
            { value: 'model', label: 'Dle názvu' },
            { value: 'utilization', label: 'Nejvíce vytížené' },
            { value: 'acquired_desc', label: 'Datum ↓ nejnovější' },
            { value: 'acquired_asc', label: 'Datum ↑ nejstarší' },
            { value: 'mileage_desc', label: 'Km ↓ nejvyšší' },
            { value: 'mileage_asc', label: 'Km ↑ nejnižší' },
          ]}
        />
        <label className="flex items-center gap-1.5 cursor-pointer rounded-btn text-sm font-extrabold uppercase tracking-wide"
          style={{ padding: '8px 14px', background: filters.occupiedToday ? '#74FB71' : '#f1faf7', border: '1px solid #d4e8e0', color: filters.occupiedToday ? '#1a2e22' : '#1a2e22' }}>
          <input type="checkbox" checked={filters.occupiedToday} onChange={e => { setPage(1); setFilters(f => ({ ...f, occupiedToday: e.target.checked })) }} className="accent-[#1a8a18]" />
          Dnes obsazené
        </label>
        <div className="flex items-center gap-1">
          <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Od</span>
          <input type="date" value={filters.occupiedFrom} onChange={e => { setPage(1); setFilters(f => ({ ...f, occupiedFrom: e.target.value })) }}
            className="rounded-btn text-sm outline-none cursor-pointer"
            style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }} />
          <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Do</span>
          <input type="date" value={filters.occupiedTo} onChange={e => { setPage(1); setFilters(f => ({ ...f, occupiedTo: e.target.value })) }}
            className="rounded-btn text-sm outline-none cursor-pointer"
            style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }} />
        </div>
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

      {/* DIAGNOSTIKA */}
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA Fleet</strong><br/>
        <div>motorcycles: {motos.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: status={filters.status || 'vše'}, branch={filters.branch || 'vše'}, category={filters.category || 'vše'}, search="{filters.search}", sort={filters.sort}</div>
        <div>branches: {branches.length}, todayOccupied: {todayOccupied.size}, bookingCounts: {Object.keys(bookingCounts).length} motorek</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" />
        </div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Foto</TH><TH>Model</TH><TH>SPZ</TH><TH>Kategorie</TH><TH>Pobočka</TH>
                <TH>Status</TH><TH>Km</TH><TH>Pořízeno</TH><TH>Další servis</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {motos.map(m => {
                const thumb = m.image_url || (m.images && m.images[0]) || null
                return (
                <tr
                  key={m.id}
                  onClick={() => navigate(`/flotila/${m.id}`)}
                  className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                  style={{ borderBottom: '1px solid #d4e8e0' }}
                >
                  <TD>
                    {thumb ? (
                      <img src={thumb} alt={m.model} style={{ width: 48, height: 36, objectFit: 'cover', borderRadius: 6, background: '#f1faf7' }} onError={e => { e.target.style.display = 'none'; e.target.parentElement.innerHTML = '<div style="width:48px;height:36px;border-radius:6px;background:#f1faf7;display:flex;align-items:center;justify-content:center;font-size:16px;color:#1a2e22">🏍️</div>' }} />
                    ) : (
                      <div style={{ width: 48, height: 36, borderRadius: 6, background: '#f1faf7', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, color: '#1a2e22' }}>🏍️</div>
                    )}
                  </TD>
                  <TD bold>{m.model}</TD>
                  <TD mono>{m.spz}</TD>
                  <TD>{CAT_LABELS[m.category] || m.category || '—'}</TD>
                  <TD>{m.branches?.name || '—'}</TD>
                  <TD><StatusBadge status={m.status} /></TD>
                  <TD mono>{m.mileage?.toLocaleString('cs-CZ') || '—'}</TD>
                  <TD>{m.acquired_at ? new Date(m.acquired_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>{m.next_service_date || '—'}</TD>
                  <TD>
                    <button
                      onClick={e => { e.stopPropagation(); setActionMoto(m) }}
                      className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
                      style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
                      Správa
                    </button>
                  </TD>
                </tr>
                )
              })}
              {motos.length === 0 && (
                <TRow><TD>Žádné motorky</TD></TRow>
              )}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddMotoModal branches={branches} onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); loadMotos() }} />}
      <MotoActionModal open={!!actionMoto} moto={actionMoto} onClose={() => setActionMoto(null)} onUpdated={() => { loadMotos(); setActionMoto(null) }} />
    </div>
  )
}

function FilterSelect({ value, onChange, options }) {
  return (
    <select
      value={value}
      onChange={e => onChange(e.target.value)}
      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
      style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
    >
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}

function AddMotoModal({ branches, onClose, onSaved }) {
  const [form, setForm] = useState({
    model: '', spz: '', vin: '', category: '', branch_id: '',
    acquired_at: '', mileage: 0, status: 'active',
    oil_interval_km: '', oil_interval_days: '',
    tire_interval_km: '', full_service_interval_km: '',
    full_service_interval_days: '', stk_valid_until: '',
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true)
    setErr(null)
    try {
      const motoData = {
        model: form.model, spz: form.spz, vin: form.vin,
        category: form.category, status: form.status,
        acquired_at: form.acquired_at || null,
        mileage: Number(form.mileage) || 0,
        branch_id: form.branch_id || null,
        stk_valid_until: form.stk_valid_until || null,
      }
      const result = await debugAction('fleet.create', 'AddMotoModal', () =>
        supabase.from('motorcycles').insert(motoData).select().single()
      , motoData)
      if (result?.error) throw result.error
      const newMoto = result?.data

      // 2. Automaticky vytvoř servisní plány
      if (newMoto && form.oil_interval_km) {
        const schedules = [
          {
            moto_id: newMoto.id,
            schedule_type: form.oil_interval_days ? 'both' : 'mileage',
            interval_km: Number(form.oil_interval_km) || 10000,
            interval_days: Number(form.oil_interval_days) || 365,
            description: 'Výměna oleje',
            active: true,
          },
        ]
        if (form.tire_interval_km) {
          schedules.push({
            moto_id: newMoto.id,
            schedule_type: 'mileage',
            interval_km: Number(form.tire_interval_km) || 15000,
            description: 'Výměna pneumatik',
            active: true,
          })
        }
        if (form.full_service_interval_km) {
          schedules.push({
            moto_id: newMoto.id,
            schedule_type: form.full_service_interval_days ? 'both' : 'mileage',
            interval_km: Number(form.full_service_interval_km) || 20000,
            interval_days: Number(form.full_service_interval_days) || 730,
            description: 'Kompletní servis',
            active: true,
          })
        }
        await supabase.from('maintenance_schedules').insert(schedules)
      }

      // 3. Audit log
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'motorcycle_created', details: { moto_id: newMoto.id },
      })

      onSaved()
    } catch (e) {
      setErr(e.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal open wide title="Nová motorka" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <FormField label="Model" value={form.model} onChange={v => set('model', v)} />
        <FormField label="SPZ" value={form.spz} onChange={v => set('spz', v)} />
        <FormField label="VIN" value={form.vin} onChange={v => set('vin', v)} />
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Kategorie</label>
          <select value={form.category} onChange={e => set('category', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">—</option>
            {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Pobočka</label>
          <select value={form.branch_id} onChange={e => set('branch_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">—</option>
            {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        </div>
        <FormField label="Datum pořízení" value={form.acquired_at} onChange={v => set('acquired_at', v)} type="date" />
        <FormField label="Nájezd (km)" value={form.mileage} onChange={v => set('mileage', v)} type="number" />
      </div>

      {/* Servisní intervaly */}
      <h4 className="text-sm font-extrabold uppercase tracking-widest mt-5 mb-3" style={{ color: '#1a2e22' }}>Servisní intervaly</h4>
      <div className="grid grid-cols-2 gap-3">
        <FormField label="Olej — interval (km)" value={form.oil_interval_km} onChange={v => set('oil_interval_km', v)} type="number" />
        <FormField label="Olej — interval (dní)" value={form.oil_interval_days} onChange={v => set('oil_interval_days', v)} type="number" />
        <FormField label="Pneumatiky — interval (km)" value={form.tire_interval_km} onChange={v => set('tire_interval_km', v)} type="number" />
        <FormField label="Kompletní servis (km)" value={form.full_service_interval_km} onChange={v => set('full_service_interval_km', v)} type="number" />
        <FormField label="Kompletní servis (dní)" value={form.full_service_interval_days} onChange={v => set('full_service_interval_days', v)} type="number" />
        <FormField label="STK platné do" value={form.stk_valid_until} onChange={v => set('stk_valid_until', v)} type="date" />
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
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
      <input type={type} value={value} onChange={e => onChange(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}
