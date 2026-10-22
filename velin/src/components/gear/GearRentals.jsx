import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { useIsMobile } from '../../hooks/useIsMobile'
import { Table, TRow, TH } from '../ui/Table'
import Button from '../ui/Button'
import { RentalRow, RentalCard } from './GearRentalParts'
import { RENTAL_STATUS, INPUT, czk, pragueToday, audit } from './gearShared'

// Záložka „Výpůjčky“: gear_rentals + shop_orders (platba, zákazník) + branches (název).
// Dva/tři dotazy a spojení v klientu (bez embedu → nezávislé na schema cache FK).

const LIMIT = 500
const PERIODS = [{ v: 'upcoming', l: 'Nadcházející a probíhající' }, { v: 'past', l: 'Proběhlé' }, { v: 'all', l: 'Vše' }]
const ORDER_COLS = 'id, order_number, customer_name, customer_email, customer_phone, total, payment_status, status, created_at, notes'

async function fetchOrders(ids) {
  const out = {}
  for (let i = 0; i < ids.length; i += 100) {
    const { data, error } = await supabase.from('shop_orders').select(ORDER_COLS).in('id', ids.slice(i, i + 100))
    if (error) throw error
    ;(data || []).forEach(o => { out[o.id] = o })
  }
  return out
}

function Chip({ on, children, onClick }) {
  return (
    <button type="button" onClick={onClick}
      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer whitespace-nowrap max-lg:min-h-[40px]"
      style={{ padding: '7px 14px', border: 'none', background: on ? '#74FB71' : '#f1faf7', color: '#1a2e22' }}>
      {children}
    </button>
  )
}

export default function GearRentals({ prices }) {
  const isMobile = useIsMobile()
  const [period, setPeriod] = useState('upcoming')
  const [paidOnly, setPaidOnly] = useState(true)
  const [branchId, setBranchId] = useState('')
  const [rows, setRows] = useState([])
  const [branches, setBranches] = useState([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState(null)
  const [busy, setBusy] = useState(null)
  const today = pragueToday()

  useEffect(() => { load() }, [period])

  async function load() {
    setLoading(true); setErr(null)
    try {
      let q = supabase.from('gear_rentals').select('*')
      if (period === 'upcoming') q = q.gte('end_date', today).order('start_date', { ascending: true })
      else if (period === 'past') q = q.lt('end_date', today).order('start_date', { ascending: false })
      else q = q.order('start_date', { ascending: false })
      const [rentRes, brRes] = await Promise.all([q.limit(LIMIT), supabase.from('branches').select('id, name, type')])
      if (rentRes.error) throw rentRes.error
      if (brRes.error) throw brRes.error
      const rentals = rentRes.data || []
      const orders = await fetchOrders(rentals.map(r => r.order_id))
      const brMap = Object.fromEntries((brRes.data || []).map(b => [b.id, b]))
      setBranches(brRes.data || [])
      setRows(rentals.map(r => ({ ...r, order: orders[r.order_id] || null, branch: brMap[r.branch_id] || null })))
    } catch (e) {
      setErr(`Načtení výpůjček selhalo: ${e.message}`)
      setRows([])
    }
    setLoading(false)
  }

  async function update(r, patch, action) {
    setBusy(r.order_id); setErr(null)
    try {
      const result = await debugAction('gear_rentals.update', 'GearRentals', () =>
        supabase.from('gear_rentals').update(patch).eq('order_id', r.order_id).select('order_id, status, admin_note, updated_at').single(),
      { order_id: r.order_id, ...patch })
      if (result?.error) throw new Error(result.error.message)
      const old = Object.fromEntries(Object.keys(patch).map(k => [k, r[k] ?? null]))
      await audit(action, 'gear_rentals', r.order_id, old, { order_number: r.order?.order_number || null, ...patch })
      setRows(rs => rs.map(x => (x.order_id === r.order_id ? { ...x, ...result.data } : x)))
    } catch (e) {
      setErr(`Uložení selhalo: ${e.message}`)
    }
    setBusy(null)
  }

  const onStatus = (r, status) => { if (status !== r.status) update(r, { status }, 'gear_rental_status_changed') }
  const onNote = (r, text) => update(r, { admin_note: text.trim() || null }, 'gear_rental_note_updated')

  const shown = rows.filter(r => (!paidOnly || r.order?.payment_status === 'paid') && (!branchId || r.branch_id === branchId))
  const hiddenUnpaid = paidOnly ? rows.filter(r => r.order?.payment_status !== 'paid' && (!branchId || r.branch_id === branchId)).length : 0
  const paidSum = shown.filter(r => r.order?.payment_status === 'paid' && r.status !== 'cancelled').reduce((a, r) => a + (Number(r.order?.total) || 0), 0)
  const props = r => ({ r, prices, today, busy: busy === r.order_id, onStatus, onNote })

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        {PERIODS.map(p => <Chip key={p.v} on={period === p.v} onClick={() => setPeriod(p.v)}>{p.l}</Chip>)}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <Chip on={paidOnly} onClick={() => setPaidOnly(true)}>Jen zaplacené</Chip>
        <Chip on={!paidOnly} onClick={() => setPaidOnly(false)}>Vč. nezaplacených</Chip>
        <select value={branchId} onChange={e => setBranchId(e.target.value)} className="cursor-pointer max-lg:min-h-[40px]" style={INPUT}>
          <option value="">Všechny pobočky</option>
          {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
        </select>
        <Button small onClick={load} disabled={loading} className="max-lg:min-h-[40px]">↻ Obnovit</Button>
      </div>

      <div className="text-sm" style={{ color: '#1a2e22' }}>
        {shown.length} výpůjček{paidSum > 0 ? ` · zaplaceno ${czk(paidSum)}` : ''}
        {hiddenUnpaid > 0 && <span style={{ color: '#6b7a72' }}> · skryto {hiddenUnpaid} bez platby (nedokončené nebo vrácené objednávky)</span>}
        {rows.length >= LIMIT && <span style={{ color: '#b45309' }}> · zobrazeno prvních {LIMIT}</span>}
      </div>
      <p className="text-xs" style={{ color: '#6b7a72' }}>
        Stav vede obsluha: {RENTAL_STATUS.reserved.label} → {RENTAL_STATUS.picked_up.label} → {RENTAL_STATUS.returned.label}
        (případně {RENTAL_STATUS.cancelled.label}). Zrušení tady platbu automaticky nevrací.
      </p>

      {err && <p className="text-sm" style={{ color: '#dc2626' }}>{err}</p>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : shown.length === 0 ? (
        <div className="bg-white rounded-card shadow-card text-sm text-center" style={{ padding: 24, color: '#1a2e22' }}>Žádné výpůjčky pro zvolený filtr.</div>
      ) : isMobile ? (
        <div className="space-y-2">{shown.map(r => <RentalCard key={r.order_id} {...props(r)} />)}</div>
      ) : (
        <Table>
          <thead>
            <TRow header><TH>Termín</TH><TH>Pobočka</TH><TH>Zákazník</TH><TH>Výbava</TH><TH>Cena</TH><TH>Stav</TH><TH>Interní poznámka</TH></TRow>
          </thead>
          <tbody>{shown.map(r => <RentalRow key={r.order_id} {...props(r)} />)}</tbody>
        </Table>
      )}
    </div>
  )
}
