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

export default function Bookings() {
  const navigate = useNavigate()
  const [bookings, setBookings] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState({ status: '', search: '', dateFrom: '', dateTo: '' })
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => { loadBookings() }, [page, filters])

  async function loadBookings() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase
        .from('bookings')
        .select('*, motorcycles(model, spz), profiles(full_name, email, phone)', { count: 'exact' })

      if (filters.status) query = query.eq('status', filters.status)
      if (filters.dateFrom) query = query.gte('start_date', filters.dateFrom)
      if (filters.dateTo) query = query.lte('end_date', filters.dateTo)
      if (filters.search) {
        query = query.or(`motorcycles.model.ilike.%${filters.search}%,profiles.full_name.ilike.%${filters.search}%`)
      }

      query = query.order('start_date', { ascending: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await query
      if (err) throw err
      setBookings(data || [])
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
          placeholder="Hledat zákazníka, motorku…"
        />
        <FilterSelect
          value={filters.status}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, status: v })) }}
          options={[
            { value: '', label: 'Všechny stavy' },
            { value: 'pending', label: 'Čekající' },
            { value: 'active', label: 'Aktivní' },
            { value: 'completed', label: 'Dokončeno' },
            { value: 'cancelled', label: 'Zrušeno' },
          ]}
        />
        <DateFilter
          label="Od"
          value={filters.dateFrom}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, dateFrom: v })) }}
        />
        <DateFilter
          label="Do"
          value={filters.dateTo}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, dateTo: v })) }}
        />
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová rezervace</Button>
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={loadBookings} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
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
                <TH>ID</TH><TH>Zákazník</TH><TH>Motorka</TH>
                <TH>Od</TH><TH>Do</TH><TH>Částka</TH><TH>Stav</TH>
              </TRow>
            </thead>
            <tbody>
              {bookings.map(b => (
                <tr
                  key={b.id}
                  onClick={() => navigate(`/rezervace/${b.id}`)}
                  className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                  style={{ borderBottom: '1px solid #d4e8e0' }}
                >
                  <TD mono>{b.id?.slice(0, 8)}</TD>
                  <TD bold>{b.profiles?.full_name || '—'}</TD>
                  <TD>{b.motorcycles?.model || '—'} <span className="text-xs font-mono" style={{ color: '#8aab99' }}>{b.motorcycles?.spz}</span></TD>
                  <TD>{b.start_date || '—'}</TD>
                  <TD>{b.end_date || '—'}</TD>
                  <TD bold>{b.total_price ? `${b.total_price.toLocaleString('cs-CZ')} Kč` : '—'}</TD>
                  <TD><StatusBadge status={b.status} /></TD>
                </tr>
              ))}
              {bookings.length === 0 && (
                <TRow><TD>Žádné rezervace</TD></TRow>
              )}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddBookingModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); loadBookings() }} />}
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

function DateFilter({ label, value, onChange }) {
  return (
    <div className="flex items-center gap-1">
      <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>{label}</span>
      <input
        type="date"
        value={value}
        onChange={e => onChange(e.target.value)}
        className="rounded-btn text-xs outline-none cursor-pointer"
        style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}
      />
    </div>
  )
}

function AddBookingModal({ onClose, onSaved }) {
  const [motos, setMotos] = useState([])
  const [customers, setCustomers] = useState([])
  const [form, setForm] = useState({ user_id: '', moto_id: '', start_date: '', end_date: '', total_price: '', status: 'pending' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('motorcycles').select('id, model, spz').eq('status', 'active').order('model')
      .then(({ data }) => setMotos(data || []))
    supabase.from('profiles').select('id, full_name, email').order('full_name')
      .then(({ data }) => setCustomers(data || []))
  }, [])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true)
    setErr(null)
    try {
      const { error } = await supabase.from('bookings').insert({
        ...form,
        total_price: Number(form.total_price) || 0,
      })
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'booking_created', details: { moto_id: form.moto_id },
      })
      onSaved()
    } catch (e) {
      setErr(e.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal open title="Nová rezervace" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2">
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Zákazník</label>
          <select value={form.user_id} onChange={e => set('user_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">— Vyberte zákazníka —</option>
            {customers.map(c => <option key={c.id} value={c.id}>{c.full_name} ({c.email})</option>)}
          </select>
        </div>
        <div className="col-span-2">
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Motorka</label>
          <select value={form.moto_id} onChange={e => set('moto_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">— Vyberte motorku —</option>
            {motos.map(m => <option key={m.id} value={m.id}>{m.model} ({m.spz})</option>)}
          </select>
        </div>
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Od</label>
          <input type="date" value={form.start_date} onChange={e => set('start_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Do</label>
          <input type="date" value={form.end_date} onChange={e => set('end_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Celková částka (Kč)</label>
          <input type="number" value={form.total_price} onChange={e => set('total_price', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.user_id || !form.moto_id}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}
