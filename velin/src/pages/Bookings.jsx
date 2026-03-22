import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import Button from '../components/ui/Button'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import NewBookingModal from './booking/NewBookingModal'
import GlobalCalendar from './booking/GlobalCalendar'
import BookingsTable from './booking/BookingsTable'
import BookingsExtendedFilters from './booking/BookingsExtendedFilters'
import { CheckboxFilterGroup, FilterSelect } from './booking/BookingsFilters'
import { autoCancelStale, autoActivateReserved, autoFixPendingPaid, autoGenerateKF } from './booking/bookingsAutoFix'

function localIso(d) {
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

const PER_PAGE = 25
const VIEWS = ['Seznam', 'Kalendář']

export default function Bookings() {
  const debugMode = useDebugMode()
  const navigate = useNavigate()
  const [bookings, setBookings] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = {
    statuses: [], search: '', dateFrom: '', dateTo: '',
    paymentStatuses: [], customer: '', motoModel: '', branch: '',
    priceMin: '', priceMax: '', durationMin: '', durationMax: '',
    hasInvoice: '', hasContract: '', country: '', licenseGroup: '',
    sortBy: 'start_date', sortDir: 'desc', futureOnly: false
  }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_bookings_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_bookings_filters', JSON.stringify(filters)) }, [filters])
  const [showAdd, setShowAdd] = useState(false)
  const [view, setView] = useState('Seznam')
  const [showFilters, setShowFilters] = useState(false)
  const [branches, setBranches] = useState([])
  const [motos, setMotos] = useState([])
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [dpTotals, setDpTotals] = useState({})

  useEffect(() => { if (view === 'Seznam') loadBookings() }, [page, filters, view])
  useEffect(() => {
    supabase.from('branches').select('id, name').order('name').then(({ data }) => setBranches(data || []))
    supabase.from('motorcycles').select('id, model').eq('status', 'active').order('model').then(({ data }) => setMotos(data || []))
  }, [])

  useEffect(() => {
    autoCancelStale()
    autoActivateReserved()
    autoFixPendingPaid()
    autoGenerateKF()
  }, [])

  async function loadBookings() {
    setLoading(true)
    setError(null)
    try {
      const result = await debugAction('bookings.load', 'Bookings', () => {
        let query = supabase
          .from('bookings')
          .select('*, motorcycles(model, spz, branch_id), profiles(full_name, email, phone, country, license_group)', { count: 'exact' })
        if (filters.statuses.length > 0) {
          const hasUpcoming = filters.statuses.includes('upcoming')
          const dbStatuses = filters.statuses.filter(s => s !== 'upcoming')
          if (hasUpcoming) dbStatuses.push('active', 'reserved')
          const unique = [...new Set(dbStatuses)]
          if (unique.length > 0) query = query.in('status', unique)
        }
        if (filters.paymentStatuses.length > 0) query = query.in('payment_status', filters.paymentStatuses)
        if (filters.dateFrom) query = query.gte('start_date', filters.dateFrom)
        if (filters.dateTo) query = query.lte('end_date', filters.dateTo)
        if (filters.priceMin) query = query.gte('total_price', Number(filters.priceMin))
        if (filters.priceMax) query = query.lte('total_price', Number(filters.priceMax))
        if (filters.futureOnly) query = query.gte('start_date', localIso(new Date()))
        if (filters.search) {
          query = query.or(`motorcycles.model.ilike.%${filters.search}%,profiles.full_name.ilike.%${filters.search}%`)
        }
        return query.order(filters.sortBy, { ascending: filters.sortDir === 'asc' })
          .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      }, { page, filters })
      if (result?.error) throw result.error
      let data = result?.data || []
      if (filters.statuses.includes('upcoming') && filters.statuses.length > 0) {
        const todayStr = localIso(new Date())
        data = data.filter(b => {
          if (filters.statuses.includes(b.status)) return true
          if (['active', 'reserved'].includes(b.status) && b.start_date?.split('T')[0] > todayStr) return true
          return false
        })
      }
      if (filters.customer) data = data.filter(b => b.profiles?.full_name?.toLowerCase().includes(filters.customer.toLowerCase()))
      if (filters.motoModel) data = data.filter(b => b.motorcycles?.model?.toLowerCase().includes(filters.motoModel.toLowerCase()))
      if (filters.country) data = data.filter(b => b.profiles?.country === filters.country)
      if (filters.licenseGroup) data = data.filter(b => b.profiles?.license_group?.includes?.(filters.licenseGroup))
      if (filters.branch) data = data.filter(b => b.motorcycles?.branch_id === filters.branch)
      if (filters.durationMin || filters.durationMax) {
        data = data.filter(b => {
          const _s = new Date(b.start_date); _s.setHours(0,0,0,0)
          const _e = new Date(b.end_date); _e.setHours(0,0,0,0)
          const d = Math.max(1, Math.round((_e - _s) / 86400000) + 1)
          if (filters.durationMin && d < Number(filters.durationMin)) return false
          if (filters.durationMax && d > Number(filters.durationMax)) return false
          return true
        })
      }
      setBookings(data)
      setTotal(result?.count || 0)
      const bookingIds = data.map(b => b.id).filter(Boolean)
      if (bookingIds.length > 0) {
        const { data: dpInvoices } = await supabase.from('invoices')
          .select('booking_id, total').eq('type', 'payment_receipt').neq('status', 'cancelled')
          .in('booking_id', bookingIds)
        if (dpInvoices) {
          const map = {}
          dpInvoices.forEach(i => { map[i.booking_id] = (map[i.booking_id] || 0) + Number(i.total || 0) })
          setDpTotals(map)
        }
      }
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmtDateRange = d => d ? new Date(d).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' }) : '—'
  const setF = (k, v) => { setPage(1); setFilters(f => ({ ...f, [k]: v })) }
  const activeFilterCount = Object.entries(filters).filter(([k, v]) => {
    if (['search', 'sortBy', 'sortDir', 'futureOnly'].includes(k)) return false
    if (Array.isArray(v)) return v.length > 0
    return !!v
  }).length
  const resetFilters = () => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_bookings_filters') }

  async function handleDeleteBooking(booking) {
    try {
      const { error: err } = await supabase.from('bookings').delete().eq('id', booking.id)
      if (err) throw err
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'booking_deleted', details: { booking_id: booking.id } })
      setDeleteConfirm(null)
      loadBookings()
    } catch (e) { setError(e.message) }
  }

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-5">
        {VIEWS.map(v => (
          <button key={v} onClick={() => setView(v)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 16px', background: view === v ? '#74FB71' : '#f1faf7', color: view === v ? '#1a2e22' : '#1a2e22', border: 'none', boxShadow: view === v ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {v}
          </button>
        ))}
        {view === 'Seznam' && (
          <>
            <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat zákazníka, motorku…" />
            <CheckboxFilterGroup label="Stav" values={filters.statuses}
              onChange={v => { setPage(1); setFilters(f => ({ ...f, statuses: v })) }}
              options={[{ value: 'pending', label: 'Čekající' }, { value: 'upcoming', label: 'Nadcházející' }, { value: 'active', label: 'Aktivní' }, { value: 'completed', label: 'Dokončeno' }, { value: 'cancelled', label: 'Zrušeno' }]} />
            <CheckboxFilterGroup label="Platba" values={filters.paymentStatuses}
              onChange={v => { setPage(1); setFilters(f => ({ ...f, paymentStatuses: v })) }}
              options={[{ value: 'paid', label: 'Zaplaceno' }, { value: 'unpaid', label: 'Nezaplaceno' }]} />
            <FilterSelect value={filters.sortBy} onChange={v => setF('sortBy', v)}
              options={[{ value: 'start_date', label: 'Datum začátku' }, { value: 'end_date', label: 'Datum konce' }, { value: 'total_price', label: 'Částka' }, { value: 'created_at', label: 'Vytvořeno' }]} />
            <FilterSelect value={filters.sortDir} onChange={v => setF('sortDir', v)}
              options={[{ value: 'desc', label: '↓ Sestupně' }, { value: 'asc', label: '↑ Vzestupně' }]} />
            <label className="flex items-center gap-1.5 cursor-pointer rounded-btn text-sm font-extrabold uppercase tracking-wide"
              style={{ padding: '8px 14px', background: filters.futureOnly ? '#74FB71' : '#f1faf7', border: '1px solid #d4e8e0', color: filters.futureOnly ? '#1a2e22' : '#1a2e22' }}>
              <input type="checkbox" checked={filters.futureOnly} onChange={e => setF('futureOnly', e.target.checked)} className="accent-[#1a8a18]" />
              Jen budoucí
            </label>
            <button onClick={() => setShowFilters(!showFilters)}
              className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
              style={{ padding: '8px 14px', background: showFilters ? '#74FB71' : '#f1faf7', border: '1px solid #d4e8e0', color: showFilters ? '#1a2e22' : '#1a2e22' }}>
              ☰ Filtry {activeFilterCount > 0 && <span className="ml-1 inline-block rounded-full text-sm" style={{ background: '#74FB71', color: '#1a2e22', padding: '1px 6px' }}>{activeFilterCount}</span>}
            </button>
          </>
        )}
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová rezervace</Button>
        </div>
      </div>

      {showFilters && view === 'Seznam' && (
        <BookingsExtendedFilters filters={filters} setF={setF} branches={branches} resetFilters={resetFilters} />
      )}

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={loadBookings} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
        </div>
      )}

      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA Bookings</strong><br/>
        <div>bookings: {bookings.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: status={filters.statuses.length > 0 ? filters.statuses.join(',') : 'vše'}, payment={filters.paymentStatuses.length > 0 ? filters.paymentStatuses.join(',') : 'vše'}, search="{filters.search}", future={filters.futureOnly ? 'ano' : 'ne'}</div>
        <div>branches: {branches.length}, motos: {motos.length}</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

      {view === 'Kalendář' ? (
        <GlobalCalendar />
      ) : loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <BookingsTable bookings={bookings} navigate={navigate} fmtDateRange={fmtDateRange} dpTotals={dpTotals} setDeleteConfirm={setDeleteConfirm} />
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <NewBookingModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); loadBookings() }} />}

      {deleteConfirm && (
        <ConfirmDialog
          open title="Smazat rezervaci?"
          message={`Opravdu chcete TRVALE smazat rezervaci #${deleteConfirm.id?.slice(-8).toUpperCase()} (${deleteConfirm.profiles?.full_name || 'zákazník'})? Tato akce je nevratná a smaže rezervaci ze Supabase.`}
          danger onConfirm={() => handleDeleteBooking(deleteConfirm)}
          onCancel={() => setDeleteConfirm(null)}
        />
      )}
    </div>
  )
}
