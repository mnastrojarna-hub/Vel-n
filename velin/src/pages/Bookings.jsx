import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import StatusBadge, { getDisplayStatus } from '../components/ui/StatusBadge'
import { generateFinalInvoice } from '../lib/invoiceUtils'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Modal from '../components/ui/Modal'
import Card from '../components/ui/Card'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import NewBookingModal from './booking/NewBookingModal'

function localIso(d) {
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

const PER_PAGE = 25
const VIEWS = ['Seznam', 'Kalendář']

export default function Bookings() {
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

  // Auto-cancel unpaid PENDING bookings older than 10 minutes
  useEffect(() => {
    async function autoCancelStale() {
      try {
        const tenMinAgo = new Date(Date.now() - 10 * 60 * 1000).toISOString()
        const { data: stale } = await supabase
          .from('bookings').select('id')
          .eq('status', 'pending').eq('payment_status', 'unpaid')
          .lt('created_at', tenMinAgo)
        if (stale && stale.length > 0) {
          await supabase.from('bookings')
            .update({ status: 'cancelled', cancellation_reason: 'Automaticky zrušeno — nezaplaceno do 10 minut' })
            .in('id', stale.map(b => b.id))
        }
      } catch (e) { console.error('[AutoCancel]', e) }
    }
    autoCancelStale()
    // Auto-activate: reserved + paid + start_date <= today → active
    async function autoActivateReserved() {
      try {
        const today = localIso(new Date())
        const { data: ready } = await supabase.from('bookings').select('id')
          .eq('status', 'reserved').eq('payment_status', 'paid')
          .lte('start_date', today)
        if (ready && ready.length > 0) {
          await supabase.from('bookings')
            .update({ status: 'active', picked_up_at: new Date().toISOString() })
            .in('id', ready.map(b => b.id))
          console.log('[AutoActivate]', ready.length, 'bookings activated')
        }
      } catch (e) { console.error('[AutoActivate]', e) }
    }
    autoActivateReserved()
    // Auto-fix: pending + paid → reserved (or active if start_date <= today)
    async function autoFixPendingPaid() {
      try {
        const today = localIso(new Date())
        const { data: stuck } = await supabase.from('bookings').select('id, start_date')
          .eq('status', 'pending').eq('payment_status', 'paid')
        if (stuck && stuck.length > 0) {
          for (const b of stuck) {
            const startLocal = b.start_date ? b.start_date.slice(0, 10) : ''
            if (startLocal <= today) {
              await supabase.from('bookings').update({ status: 'active', picked_up_at: new Date().toISOString() }).eq('id', b.id)
            } else {
              await supabase.from('bookings').update({ status: 'reserved', confirmed_at: new Date().toISOString() }).eq('id', b.id)
            }
          }
          console.log('[AutoFixPendingPaid]', stuck.length, 'bookings fixed')
        }
      } catch (e) { console.error('[AutoFixPendingPaid]', e) }
    }
    autoFixPendingPaid()
    // Auto-generate KF for completed bookings without final invoice
    async function autoGenerateKF() {
      try {
        const today = localIso(new Date())
        const { data: expired } = await supabase.from('bookings').select('id, status, end_date')
          .in('status', ['active', 'reserved', 'completed']).eq('payment_status', 'paid')
          .lt('end_date', today)
        if (!expired || expired.length === 0) return
        for (const b of expired) {
          const { data: kf } = await supabase.from('invoices').select('id')
            .eq('booking_id', b.id).eq('type', 'final').limit(1)
          if (kf && kf.length > 0) continue
          try { await generateFinalInvoice(b.id) } catch (e) { console.error('[AutoKF]', b.id, e.message) }
        }
      } catch (e) { console.error('[AutoKF]', e) }
    }
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
      // Client-side filters for joined fields
      // Client-side: filter out non-upcoming when "upcoming" is checked alongside other statuses
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
          // Normalize to local midnight to avoid timezone-caused fractional days
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
      // Load DP totals per booking (sum of all payment_receipt invoices)
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
        <div className="mb-5 p-4 rounded-card" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Rozšířené filtry rezervací</span>
            <button onClick={resetFilters} className="text-sm font-bold cursor-pointer underline" style={{ color: '#1a2e22' }}>Resetovat</button>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <FField label="Zákazník" value={filters.customer} onChange={v => setF('customer', v)} />
            <FField label="Model motorky" value={filters.motoModel} onChange={v => setF('motoModel', v)} />
            <div><FLabel>Pobočka</FLabel>
              <FSelWrap value={filters.branch} onChange={v => setF('branch', v)}
                options={[{ value: '', label: 'Všechny' }, ...branches.map(b => ({ value: b.id, label: b.name }))]} />
            </div>
            <div><FLabel>Země zákazníka</FLabel>
              <FSelWrap value={filters.country} onChange={v => setF('country', v)}
                options={[{ value: '', label: 'Všechny' }, { value: 'CZ', label: 'Česko' }, { value: 'SK', label: 'Slovensko' }, { value: 'DE', label: 'Německo' }, { value: 'AT', label: 'Rakousko' }]} />
            </div>
            <FField label="Datum od" value={filters.dateFrom} onChange={v => setF('dateFrom', v)} type="date" />
            <FField label="Datum do" value={filters.dateTo} onChange={v => setF('dateTo', v)} type="date" />
            <FField label="Cena od (Kč)" value={filters.priceMin} onChange={v => setF('priceMin', v)} type="number" />
            <FField label="Cena do (Kč)" value={filters.priceMax} onChange={v => setF('priceMax', v)} type="number" />
            <FField label="Min. dní" value={filters.durationMin} onChange={v => setF('durationMin', v)} type="number" />
            <FField label="Max. dní" value={filters.durationMax} onChange={v => setF('durationMax', v)} type="number" />
            <div><FLabel>Skupina ŘP</FLabel>
              <FSelWrap value={filters.licenseGroup} onChange={v => setF('licenseGroup', v)}
                options={[{ value: '', label: 'Všechny' }, ...['A', 'A1', 'A2', 'AM', 'B'].map(g => ({ value: g, label: g }))]} />
            </div>
            <div><FLabel>Řadit dle</FLabel>
              <FSelWrap value={filters.sortBy} onChange={v => setF('sortBy', v)}
                options={[{ value: 'start_date', label: 'Datum začátku' }, { value: 'end_date', label: 'Datum konce' }, { value: 'total_price', label: 'Částka' }, { value: 'created_at', label: 'Vytvořeno' }]} />
            </div>
          </div>
        </div>
      )}

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={loadBookings} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
        </div>
      )}

      {/* DIAGNOSTIKA */}
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA Bookings</strong><br/>
        <div>bookings: {bookings.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: status={filters.statuses.length > 0 ? filters.statuses.join(',') : 'vše'}, payment={filters.paymentStatuses.length > 0 ? filters.paymentStatuses.join(',') : 'vše'}, search="{filters.search}", future={filters.futureOnly ? 'ano' : 'ne'}</div>
        <div>branches: {branches.length}, motos: {motos.length}</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>

      {view === 'Kalendář' ? (
        <GlobalCalendar />
      ) : loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>ID</TH><TH>Zákazník</TH><TH>Motorka</TH>
                <TH>Od</TH><TH>Do</TH><TH>Dní</TH><TH>Částka</TH><TH>Platba</TH><TH>Stav</TH><TH>Vytvořeno</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {bookings.map(b => {
                const toLocalDate = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
                // Normalize to local midnight to avoid timezone fractional days
                const _nm = d => { const dt = new Date(d); dt.setHours(0,0,0,0); return dt }
                const days = b.start_date && b.end_date ? Math.max(1, Math.round((_nm(b.end_date) - _nm(b.start_date)) / 86400000) + 1) : '—'
                // Only show delta when dates actually changed (compare in local timezone to avoid date vs timestamptz mismatch)
                const hasDateChange = b.original_start_date && b.original_end_date &&
                  (toLocalDate(b.start_date) !== toLocalDate(b.original_start_date) || toLocalDate(b.end_date) !== toLocalDate(b.original_end_date))
                const origDays = hasDateChange ? Math.max(1, Math.round((_nm(b.original_end_date) - _nm(b.original_start_date)) / 86400000) + 1) : null
                const daysDelta = origDays !== null && typeof days === 'number' ? days - origDays : null
                const startShift = hasDateChange ? Math.round((_nm(b.start_date) - _nm(b.original_start_date)) / 86400000) : 0
                return (
                  <tr key={b.id} onClick={() => navigate(`/rezervace/${b.id}`)}
                    className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                    style={{ borderBottom: '1px solid #d4e8e0' }}>
                    <TD mono>{b.id?.slice(-8).toUpperCase()}</TD>
                    <TD bold>{b.profiles?.full_name || '—'}</TD>
                    <TD>{b.motorcycles?.model || '—'} <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>{b.motorcycles?.spz}</span></TD>
                    <TD>{fmtDateRange(b.start_date)}</TD>
                    <TD>{fmtDateRange(b.end_date)}</TD>
                    <TD>{days}{hasDateChange && daysDelta !== 0 && (() => {
                      const lbl = daysDelta > 0 ? `+${daysDelta}d` : `${daysDelta}d`
                      const lbg = daysDelta > 0 ? '#dbeafe' : '#fee2e2'
                      const lcol = daysDelta > 0 ? '#2563eb' : '#dc2626'
                      return <span className="ml-1 text-[9px] font-extrabold px-1 py-0.5 rounded-btn" style={{ background: lbg, color: lcol }}>{lbl}</span>
                    })()}</TD>
                    <TD bold>{(dpTotals[b.id] || b.total_price) ? `${Number(dpTotals[b.id] || b.total_price).toLocaleString('cs-CZ')} Kč` : '—'}</TD>
                    <TD>
                      <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                        style={{ padding: '3px 8px', background: b.payment_status === 'paid' ? '#dcfce7' : '#fee2e2', color: b.payment_status === 'paid' ? '#1a8a18' : '#dc2626' }}>
                        {b.payment_status === 'paid' ? 'Zaplaceno' : 'Nezaplaceno'}
                      </span>
                    </TD>
                    <TD>
                      <StatusBadge status={getDisplayStatus(b)} />
                      {b.sos_replacement && <span className="ml-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded-btn" style={{ background: '#dcfce7', color: '#1a8a18' }}>SOS</span>}
                      {b.ended_by_sos && <span className="ml-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded-btn" style={{ background: '#fee2e2', color: '#b91c1c' }}>SOS</span>}
                      {b.complaint_status && <span className="ml-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded-btn" style={{ background: '#fef3c7', color: '#92400e' }}>RKL</span>}
                    </TD>
                    <TD><span className="text-sm" style={{ color: '#1a2e22' }}>{b.created_at ? new Date(b.created_at).toLocaleString('cs-CZ') : '—'}</span></TD>
                    <TD>
                      <button onClick={e => { e.stopPropagation(); setDeleteConfirm(b) }}
                        className="text-sm font-bold cursor-pointer"
                        style={{ color: '#dc2626', background: 'none', border: 'none', padding: '4px 6px' }}>
                        Smazat
                      </button>
                    </TD>
                  </tr>
                )
              })}
              {bookings.length === 0 && <TRow><TD>Žádné rezervace</TD></TRow>}
            </tbody>
          </Table>
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

/* ═══ FILTER HELPERS ═══ */
function FLabel({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
function FSelWrap({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="w-full rounded-btn text-sm outline-none cursor-pointer"
      style={{ padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}
function FField({ label, value, onChange, type = 'text' }) {
  return (
    <div>
      <FLabel>{label}</FLabel>
      <input type={type} value={value} onChange={e => onChange(e.target.value)}
        className="w-full rounded-btn text-sm outline-none"
        style={{ padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }} />
    </div>
  )
}

/* ═══ GLOBÁLNÍ KALENDÁŘ REZERVACÍ ═══ */
const DAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTHS_FULL = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const navBtnStyle = { background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 12px', cursor: 'pointer', fontWeight: 800 }

function GlobalCalendar() {
  const navigate = useNavigate()
  const [bookings, setBookings] = useState([])
  const [motos, setMotos] = useState([])
  const [month, setMonth] = useState(new Date())
  const [loading, setLoading] = useState(true)
  const [selectedDay, setSelectedDay] = useState(null)
  const [showFree, setShowFree] = useState(false)

  useEffect(() => { loadData() }, [month])

  async function loadData() {
    setLoading(true)
    const start = new Date(month.getFullYear(), month.getMonth(), 1)
    const end = new Date(month.getFullYear(), month.getMonth() + 1, 0)
    const startStr = localIso(start)
    const endStr = localIso(end)

    const [bRes, mRes] = await Promise.all([
      supabase.from('bookings')
        .select('id, start_date, end_date, status, moto_id, profiles(full_name), motorcycles(model, spz), total_price')
        .in('status', ['pending', 'active', 'reserved', 'completed'])
        .gte('end_date', startStr).lte('start_date', endStr),
      supabase.from('motorcycles').select('id, model, spz, branch_id, branches(name)').eq('status', 'active'),
    ])
    setBookings(bRes.data || [])
    setMotos(mRes.data || [])
    setLoading(false)
  }

  const year = month.getFullYear()
  const mon = month.getMonth()
  const daysInMonth = new Date(year, mon + 1, 0).getDate()
  const firstDayOfWeek = (new Date(year, mon, 1).getDay() + 6) % 7
  const todayStr = localIso(new Date())
  const totalMotos = motos.length || 1

  function getDayBookings(day) {
    const dateStr = `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    return bookings.filter(b => dateStr >= b.start_date.split('T')[0] && dateStr <= b.end_date.split('T')[0])
  }

  function getDayInfo(day) {
    const dateStr = `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    const dayBookings = getDayBookings(day)
    const occupiedCount = new Set(dayBookings.map(b => b.moto_id)).size
    const isToday = dateStr === todayStr
    const ratio = occupiedCount / totalMotos
    if (occupiedCount === 0) return { bg: isToday ? '#bbf7d0' : '#dcfce7', color: '#15803d', label: 'Vše volné', count: 0 }
    if (ratio >= 1) return { bg: '#166534', color: '#fff', label: `Plně obsazeno (${occupiedCount}/${totalMotos})`, count: occupiedCount }
    if (ratio >= 0.5) return { bg: '#15803d', color: '#fff', label: `${occupiedCount}/${totalMotos} obsazeno`, count: occupiedCount }
    return { bg: '#4ade80', color: '#0f1a14', label: `${occupiedCount}/${totalMotos} obsazeno`, count: occupiedCount }
  }

  const prevMonth = () => setMonth(new Date(year, mon - 1, 1))
  const nextMonth = () => setMonth(new Date(year, mon + 1, 1))

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  const dayDetail = selectedDay ? getDayBookings(selectedDay) : []

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
      <div className="lg:col-span-2">
        <Card>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
            <button onClick={prevMonth} style={navBtnStyle}>←</button>
            <span style={{ fontWeight: 800, fontSize: 15 }}>{MONTHS_FULL[mon]} {year}</span>
            <button onClick={nextMonth} style={navBtnStyle}>→</button>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 3 }}>
            {DAYS.map(d => (
              <div key={d} style={{ textAlign: 'center', fontSize: 13, fontWeight: 800, color: '#1a2e22', padding: 4 }}>{d}</div>
            ))}
            {Array.from({ length: firstDayOfWeek }).map((_, i) => <div key={`e${i}`} />)}
            {Array.from({ length: daysInMonth }).map((_, i) => {
              const day = i + 1
              const info = getDayInfo(day)
              return (
                <div key={day} title={info.label} onClick={() => setSelectedDay(day)}
                  style={{ textAlign: 'center', padding: '10px 2px', borderRadius: 8, background: info.bg, color: info.color, fontSize: 12, fontWeight: 800, cursor: 'pointer', outline: selectedDay === day ? '2px solid #0f1a14' : 'none' }}>
                  <div>{day}</div>
                  {info.count > 0 && <div style={{ fontSize: 9, marginTop: 2, opacity: 0.8 }}>{info.count}/{totalMotos}</div>}
                </div>
              )
            })}
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginTop: 14, fontSize: 13, fontWeight: 700 }}>
            <LegendItem bg="#dcfce7" color="#15803d" label="Vše volné" />
            <LegendItem bg="#4ade80" color="#0f1a14" label="Částečně" />
            <LegendItem bg="#15803d" color="#fff" label=">50% obsazeno" />
            <LegendItem bg="#166534" color="#fff" label="Plně obsazeno" />
          </div>
        </Card>
      </div>
      <div>
        <Card>
          {selectedDay ? (
            <>
              <h3 className="text-sm font-extrabold mb-3" style={{ color: '#0f1a14' }}>{selectedDay}. {MONTHS_FULL[mon]} {year}</h3>
              <label className="flex items-center gap-2 cursor-pointer mb-3 pb-3" style={{ borderBottom: '1px solid #d4e8e0' }}>
                <input type="checkbox" checked={showFree} onChange={e => setShowFree(e.target.checked)} className="accent-[#1a8a18]" />
                <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: showFree ? '#1a8a18' : '#1a2e22' }}>Zobrazit volné motorky</span>
              </label>
              {dayDetail.length === 0 && !showFree ? (
                <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné rezervace v tento den</p>
              ) : (
                <div className="space-y-2">
                  {dayDetail.map(b => (
                    <div key={b.id} className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-bold text-sm">{b.motorcycles?.model || '—'}</span>
                        <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>{b.motorcycles?.spz}</span>
                        <StatusBadge status={getDisplayStatus(b)} />
                      </div>
                      <div className="text-sm" style={{ color: '#1a2e22' }}>
                        {b.profiles?.full_name || 'Zákazník'}
                        <span className="ml-2" style={{ color: '#1a2e22' }}>{b.start_date ? new Date(b.start_date).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric' }) : ''} → {b.end_date ? new Date(b.end_date).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' }) : ''}</span>
                      </div>
                      {(dpTotals[b.id] || b.total_price) && <div className="text-sm font-bold mt-1" style={{ color: '#3dba3a' }}>{Number(dpTotals[b.id] || b.total_price).toLocaleString('cs-CZ')} Kč</div>}
                    </div>
                  ))}
                  {showFree && (() => {
                    const occupiedMotoIds = new Set(dayDetail.map(b => b.moto_id))
                    const freeMotos = motos.filter(m => !occupiedMotoIds.has(m.id))
                    if (freeMotos.length === 0) return <p style={{ color: '#1a2e22', fontSize: 12, marginTop: 8 }}>Žádné volné motorky</p>
                    return (
                      <>
                        <div className="text-sm font-extrabold uppercase tracking-wide mt-3 mb-1" style={{ color: '#1a8a18' }}>Volné motorky ({freeMotos.length})</div>
                        {freeMotos.map(m => (
                          <div key={m.id} onClick={() => navigate(`/flotila/${m.id}`)}
                            className="p-3 rounded-lg cursor-pointer hover:ring-2 hover:ring-[#74FB71] transition-all"
                            style={{ background: '#f0fdf4', border: '1px solid #bbf7d0' }}>
                            <div className="flex items-center gap-2">
                              <span className="font-bold text-sm">{m.model}</span>
                              <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>{m.spz}</span>
                            </div>
                            <div className="flex items-center gap-2 mt-1">
                              <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase" style={{ padding: '2px 6px', background: '#dcfce7', color: '#15803d' }}>Volná</span>
                              {m.branches?.name && <span className="text-sm" style={{ color: '#1a2e22' }}>{m.branches.name}</span>}
                              <span className="text-sm ml-auto" style={{ color: '#3dba3a' }}>Detail flotily →</span>
                            </div>
                          </div>
                        ))}
                      </>
                    )
                  })()}
                </div>
              )}
            </>
          ) : (
            <p style={{ color: '#1a2e22', fontSize: 13 }}>Klikněte na den pro zobrazení detailu</p>
          )}
        </Card>
      </div>
    </div>
  )
}

function LegendItem({ bg, color, label }) {
  return <span className="flex items-center gap-1"><span style={{ display: 'inline-block', width: 12, height: 12, borderRadius: 3, background: bg }} /><span style={{ color: '#1a2e22' }}>{label}</span></span>
}

/* ═══ HELPER COMPONENTS ═══ */
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

function FilterSelect({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
      style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}

function DateFilter({ label, value, onChange }) {
  return (
    <div className="flex items-center gap-1">
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{label}</span>
      <input type="date" value={value} onChange={e => onChange(e.target.value)}
        className="rounded-btn text-sm outline-none cursor-pointer"
        style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }} />
    </div>
  )
}

