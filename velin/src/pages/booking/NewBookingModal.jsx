import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import BookingStep3 from './BookingStep3'

const STEP_LABELS = ['Termín', 'Motorka', 'Zákazník & shrnutí']
const DAY_NAMES = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTH_NAMES = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const DAY_KEYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']

function fmtDate(d) { return d ? d.toLocaleDateString('cs-CZ') : '—' }
function isoDate(d) {
  if (!d) return ''
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}
function sameDay(a, b) { return a && b && isoDate(a) === isoDate(b) }
function inRange(d, from, to) { return d >= from && d <= to }

export default function NewBookingModal({ onClose, onSaved }) {
  const [step, setStep] = useState(1)
  const [err, setErr] = useState(null)
  const [saving, setSaving] = useState(false)

  const [calMonth, setCalMonth] = useState(() => { const n = new Date(); return { m: n.getMonth(), y: n.getFullYear() } })
  const [startDate, setStartDate] = useState(null)
  const [endDate, setEndDate] = useState(null)
  const [calStep, setCalStep] = useState(1)

  const [allMotos, setAllMotos] = useState([])
  const [motoPrices, setMotoPrices] = useState({})
  const [bookings, setBookings] = useState([])
  const [selectedMoto, setSelectedMoto] = useState(null)
  const [loadingMotos, setLoadingMotos] = useState(true)
  const [loadingBookings, setLoadingBookings] = useState(false)
  const [queryError, setQueryError] = useState(null)
  const [branches, setBranches] = useState([])
  const [branchFilter, setBranchFilter] = useState('')
  const [customers, setCustomers] = useState([])
  const [noPayment, setNoPayment] = useState(false)

  // Load motorcycles, prices, branches, customers on mount
  useEffect(() => {
    supabase.from('profiles').select('id, full_name, email, phone').order('full_name').then(({ data }) => setCustomers(data || []))
    supabase.from('branches').select('id, name').order('name').then(({ data }) => setBranches(data || []))

    async function loadMotos() {
      try {
        const [motosRes, pricesRes, branchesRes] = await Promise.all([
          supabase.from('motorcycles').select('id, model, spz, category, image_url, status, branch_id, license_required, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun').order('model'),
          supabase.from('moto_day_prices').select('*'),
          supabase.from('branches').select('id, name'),
        ])
        if (motosRes.error) {
          console.error('[NewBooking] motorcycles error:', motosRes.error)
          setQueryError('Chyba načítání motorek: ' + motosRes.error.message)
        }
        const motoList = motosRes.data || []
        const branchMap = {}; (branchesRes.data || []).forEach(b => { branchMap[b.id] = b.name })
        const motosWithBranch = motoList.map(m => ({ ...m, branch_name: branchMap[m.branch_id] || null }))
        setAllMotos(motosWithBranch)
        console.log('[NewBooking] loaded', motoList.length, 'motorcycles, statuses:', [...new Set(motoList.map(m => m.status))])
        const pm = {}; (pricesRes.data || []).forEach(p => { pm[p.moto_id] = p })
        setMotoPrices(pm)
      } catch (e) {
        console.error('[NewBooking] init failed:', e)
        setQueryError('Chyba: ' + e.message)
      }
      setLoadingMotos(false)
    }
    loadMotos()
  }, [])

  // Load overlapping bookings when dates change
  useEffect(() => {
    if (!startDate || !endDate) { setBookings([]); return }
    setLoadingBookings(true)
    supabase.from('bookings')
      .select('id, moto_id, start_date, end_date, status')
      .in('status', ['reserved', 'active', 'pending'])
      .lte('start_date', isoDate(endDate))
      .gte('end_date', isoDate(startDate))
      .then(({ data, error }) => {
        if (error) console.error('[NewBooking] bookings error:', error)
        setBookings(data || [])
        setLoadingBookings(false)
      })
  }, [startDate, endDate])

  const motos = useMemo(() => allMotos.filter(m => m.status === 'active'), [allMotos])
  const occupiedMotoIds = useMemo(() => new Set(bookings.map(b => b.moto_id)), [bookings])

  const MOTO_DAY_MAP = { 0: 'price_sun', 1: 'price_mon', 2: 'price_tue', 3: 'price_wed', 4: 'price_thu', 5: 'price_fri', 6: 'price_sat' }
  const PRICES_DAY_MAP = { 0: 'price_sunday', 1: 'price_monday', 2: 'price_tuesday', 3: 'price_wednesday', 4: 'price_thursday', 5: 'price_friday', 6: 'price_saturday' }

  function calcPrice(motoId) {
    if (!startDate || !endDate) return null
    const dp = motoPrices[motoId]
    const moto = allMotos.find(m => m.id === motoId)
    let total = 0; const cur = new Date(startDate); const end = new Date(endDate)
    while (cur <= end) {
      const dow = cur.getDay()
      const price = (dp && Number(dp[PRICES_DAY_MAP[dow]])) || (moto && Number(moto[MOTO_DAY_MAP[dow]])) || 0
      total += price
      cur.setDate(cur.getDate() + 1)
    }
    return total
  }

  const days = startDate && endDate ? Math.max(1, Math.round((endDate - startDate) / 86400000) + 1) : 0
  const totalPrice = selectedMoto ? calcPrice(selectedMoto.id) : null
  const filteredMotos = branchFilter ? motos.filter(m => m.branch_id === branchFilter) : motos
  const availableMotos = filteredMotos.filter(m => !occupiedMotoIds.has(m.id))
  const unavailableMotos = filteredMotos.filter(m => occupiedMotoIds.has(m.id))
  const statusCounts = useMemo(() => {
    const counts = {}
    allMotos.forEach(m => { counts[m.status] = (counts[m.status] || 0) + 1 })
    return counts
  }, [allMotos])

  function handleCalClick(date) {
    if (calStep === 1) { setStartDate(date); setEndDate(null); setCalStep(2); setSelectedMoto(null) }
    else if (date < startDate) { setStartDate(date); setEndDate(null); setCalStep(2); setSelectedMoto(null) }
    else { setEndDate(date); setCalStep(1); setSelectedMoto(null) }
  }

  function renderCalendar() {
    const { m, y } = calMonth; const firstDay = new Date(y, m, 1)
    let startIdx = firstDay.getDay() - 1; if (startIdx < 0) startIdx = 6
    const daysInMonth = new Date(y, m + 1, 0).getDate()
    const today = new Date(); today.setHours(0, 0, 0, 0)
    const cells = []; for (let i = 0; i < startIdx; i++) cells.push(null)
    for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(y, m, d))
    return (
      <div>
        <div className="flex items-center justify-between mb-3">
          <button onClick={() => setCalMonth(p => p.m === 0 ? { m: 11, y: p.y - 1 } : { m: p.m - 1, y: p.y })} className="cursor-pointer text-sm font-bold" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 10px', color: '#1a2e22' }}>←</button>
          <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{MONTH_NAMES[m]} {y}</span>
          <button onClick={() => setCalMonth(p => p.m === 11 ? { m: 0, y: p.y + 1 } : { m: p.m + 1, y: p.y })} className="cursor-pointer text-sm font-bold" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 10px', color: '#1a2e22' }}>→</button>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 3 }}>
          {DAY_NAMES.map(n => <div key={n} className="text-sm font-bold text-center" style={{ color: '#1a2e22', padding: 4 }}>{n}</div>)}
          {cells.map((date, i) => {
            if (!date) return <div key={`e${i}`} />
            const past = date < today; const isStart = sameDay(date, startDate); const isEnd = sameDay(date, endDate)
            const isInRange = startDate && endDate && inRange(date, startDate, endDate); const isSelected = isStart || isEnd
            let bg = '#fff', color = '#0f1a14', border = '1px solid #e5e7eb', fontWeight = 500
            if (past) { color = '#d1d5db'; border = '1px solid #f3f4f6' }
            else if (isSelected) { bg = '#74FB71'; color = '#0f1a14'; border = '1px solid #3dba3a'; fontWeight = 800 }
            else if (isInRange) { bg = '#d1fae5'; border = '1px solid #a7f3d0' }
            return (<button key={i} disabled={past} onClick={() => handleCalClick(date)} className="cursor-pointer text-sm text-center" style={{ background: bg, color, border, borderRadius: 6, padding: '7px 0', fontWeight, opacity: past ? 0.4 : 1 }}>{date.getDate()}</button>)
          })}
        </div>
      </div>
    )
  }

  async function handleCreate({ selectedCustomer, pickupTime, notes }) {
    setErr(null); if (!selectedCustomer || !selectedMoto || !startDate || !endDate) { setErr('Vyplňte všechna pole'); return }
    setSaving(true)
    try {
      if (selectedMoto.license_required !== 'N') {
        const { data: overlapping } = await supabase.from('bookings').select('id, start_date, end_date, motorcycles(model, license_required)').eq('user_id', selectedCustomer.id).in('status', ['pending', 'reserved', 'active']).lte('start_date', isoDate(endDate)).gte('end_date', isoDate(startDate))
        const nonKids = (overlapping || []).filter(b => b.motorcycles?.license_required !== 'N')
        if (nonKids.length > 0) throw new Error(`Zákazník má překrývající se rezervaci: ${nonKids[0].motorcycles?.model || ''} (${nonKids[0].start_date} – ${nonKids[0].end_date})`)
      }
      const bookingData = { user_id: selectedCustomer.id, moto_id: selectedMoto.id, start_date: isoDate(startDate), end_date: isoDate(endDate), pickup_time: pickupTime, total_price: totalPrice || 0, status: 'reserved', payment_status: noPayment ? 'paid' : 'pending', notes: notes || null }
      const result = await debugAction('bookings.create', 'NewBookingModal', () => supabase.from('bookings').insert(bookingData).select().single(), bookingData)
      if (result?.error) throw result.error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'booking_created_admin', details: { booking_id: result.data?.id, moto: selectedMoto.model, customer: selectedCustomer.full_name, no_payment: noPayment } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová rezervace" onClose={onClose} wide>
      <div className="flex items-center gap-2 mb-5">
        {STEP_LABELS.map((label, i) => (
          <div key={i} className="flex items-center gap-2">
            <div className="flex items-center gap-1 cursor-pointer" onClick={() => { if (i + 1 < step) setStep(i + 1) }}>
              <div className="text-sm font-extrabold rounded-full flex items-center justify-center" style={{ width: 22, height: 22, background: step > i + 1 ? '#74FB71' : step === i + 1 ? '#0f1a14' : '#e5e7eb', color: step === i + 1 ? '#fff' : step > i + 1 ? '#0f1a14' : '#9ca3af' }}>{step > i + 1 ? '✓' : i + 1}</div>
              <span className="text-sm font-bold uppercase tracking-wide" style={{ color: step === i + 1 ? '#0f1a14' : '#1a2e22' }}>{label}</span>
            </div>
            {i < STEP_LABELS.length - 1 && <div style={{ width: 24, height: 1, background: '#d4e8e0' }} />}
          </div>
        ))}
      </div>
      {err && <div className="p-3 rounded-lg mb-4" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{err}</div>}

      {step === 1 && (
        <div>
          <p className="text-sm mb-3" style={{ color: '#1a2e22' }}>{calStep === 1 ? 'Vyberte datum vyzvednutí:' : 'Vyberte datum vrácení:'}</p>
          {renderCalendar()}
          {startDate && (
            <div className="mt-4 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <div className="flex gap-6">
                <div><span className="text-sm font-bold uppercase" style={{ color: '#1a2e22' }}>Vyzvednutí</span><div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{fmtDate(startDate)}</div></div>
                <div><span className="text-sm font-bold uppercase" style={{ color: '#1a2e22' }}>Vrácení</span><div className="text-sm font-bold" style={{ color: endDate ? '#0f1a14' : '#d1d5db' }}>{endDate ? fmtDate(endDate) : 'Vyberte…'}</div></div>
                {days > 0 && <div><span className="text-sm font-bold uppercase" style={{ color: '#1a2e22' }}>Dní</span><div className="text-sm font-bold" style={{ color: '#1a8a18' }}>{days}</div></div>}
              </div>
            </div>
          )}
          <div className="flex justify-end mt-4"><Button green onClick={() => { setErr(null); setStep(2) }} disabled={!startDate || !endDate}>Pokračovat →</Button></div>
        </div>
      )}

      {step === 2 && (
        <div>
          <div className="flex items-center justify-between mb-3 flex-wrap gap-2">
            <p className="text-sm font-bold" style={{ color: '#1a2e22' }}>Volné motorky pro {fmtDate(startDate)} – {fmtDate(endDate)} ({days} dní)</p>
            <div className="flex items-center gap-3">
              <select value={branchFilter} onChange={e => setBranchFilter(e.target.value)} className="text-sm font-bold cursor-pointer" style={{ padding: '5px 10px', borderRadius: 8, border: '1px solid #d4e8e0', background: '#f1faf7', color: '#1a2e22' }}>
                <option value="">Všechny pobočky</option>
                {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
              <span className="text-sm font-bold" style={{ color: '#1a8a18' }}>{availableMotos.length} volných</span>
            </div>
          </div>
          {(loadingMotos || loadingBookings) ? (
            <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
          ) : (
            <div style={{ maxHeight: 380, overflowY: 'auto' }}>
              {availableMotos.length === 0 && (
                <div className="py-6 text-center">
                  <p className="text-sm" style={{ color: '#1a2e22' }}>Žádná motorka není volná v tomto termínu</p>
                  {queryError && <p className="text-xs mt-2" style={{ color: '#dc2626' }}>Chyba: {queryError}</p>}
                  {!queryError && allMotos.length === 0 && <p className="text-xs mt-2" style={{ color: '#888' }}>Dotaz vrátil 0 motorek</p>}
                  {!queryError && allMotos.length > 0 && motos.length === 0 && (
                    <p className="text-xs mt-2" style={{ color: '#888' }}>
                      Nalezeno {allMotos.length} motorek, ale žádná nemá status active.
                      Stavy: {Object.entries(statusCounts).map(([s, c]) => `${s}: ${c}`).join(', ')}
                    </p>
                  )}
                  {!queryError && motos.length > 0 && <p className="text-xs mt-2" style={{ color: '#888' }}>{motos.length} motorek, {bookings.length} překrývajících rezervací</p>}
                </div>
              )}
              {availableMotos.map(m => {
                const price = calcPrice(m.id); const isSelected = selectedMoto?.id === m.id
                return (
                  <div key={m.id} className="flex items-center gap-4 p-3 rounded-lg mb-2 cursor-pointer" onClick={() => setSelectedMoto(m)} style={{ background: isSelected ? '#eafbe9' : '#f8faf9', border: isSelected ? '2px solid #74FB71' : '1px solid #e5e7eb' }}>
                    {m.image_url ? <img src={m.image_url} alt={m.model} style={{ width: 72, height: 48, objectFit: 'cover', borderRadius: 8 }} /> : <div style={{ width: 72, height: 48, borderRadius: 8, background: '#f1faf7', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22 }}>🏍️</div>}
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{m.model}</div>
                      <div className="text-sm" style={{ color: '#1a2e22' }}>{m.spz || '—'} · {m.category || '—'} · ŘP: {m.license_required || '—'}</div>
                      {m.branch_name && <div className="text-xs" style={{ color: '#888' }}>{m.branch_name}</div>}
                    </div>
                    <div className="text-right">
                      <div className="text-sm font-extrabold" style={{ color: '#1a8a18' }}>{price ? price.toLocaleString('cs-CZ') + ' Kč' : '—'}</div>
                      <div className="text-sm" style={{ color: '#1a2e22' }}>{days} dní</div>
                    </div>
                    {isSelected && <div style={{ fontSize: 16, color: '#1a8a18' }}>✓</div>}
                  </div>
                )
              })}
              {unavailableMotos.length > 0 && (
                <>
                  <div className="text-sm font-bold uppercase tracking-wide mt-4 mb-2" style={{ color: '#dc2626' }}>Obsazené v tomto termínu ({unavailableMotos.length})</div>
                  {unavailableMotos.map(m => (
                    <div key={m.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#fafafa', border: '1px solid #f3f4f6', opacity: 0.5 }}>
                      <div style={{ width: 72, height: 48, borderRadius: 8, background: '#f3f4f6', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22 }}>🏍️</div>
                      <div className="flex-1"><div className="text-sm font-bold" style={{ color: '#1a2e22' }}>{m.model}</div><div className="text-sm" style={{ color: '#1a2e22' }}>{m.spz || '—'} · Obsazená</div></div>
                    </div>
                  ))}
                </>
              )}
            </div>
          )}
          <div className="flex justify-between mt-4">
            <Button onClick={() => setStep(1)}>← Zpět</Button>
            <Button green onClick={() => { setErr(null); setStep(3) }} disabled={!selectedMoto}>Pokračovat →</Button>
          </div>
        </div>
      )}

      {step === 3 && <BookingStep3 selectedMoto={selectedMoto} startDate={startDate} endDate={endDate} days={days} totalPrice={totalPrice} customers={customers} onBack={() => setStep(2)} onCreate={handleCreate} saving={saving} noPayment={noPayment} setNoPayment={setNoPayment} />}
    </Modal>
  )
}
