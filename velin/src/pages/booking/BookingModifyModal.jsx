import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

const DAY_NAMES = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTH_NAMES = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const DAY_KEYS_JS = { 0: 'price_sunday', 1: 'price_monday', 2: 'price_tuesday', 3: 'price_wednesday', 4: 'price_thursday', 5: 'price_friday', 6: 'price_saturday' }
const DAY_KEYS_MOTO = { 0: 'price_sun', 1: 'price_mon', 2: 'price_tue', 3: 'price_wed', 4: 'price_thu', 5: 'price_fri', 6: 'price_sat' }
const DOW_LABELS = ['Ne', 'Po', 'Út', 'St', 'Čt', 'Pá', 'So']

function isoDate(d) {
  if (!d) return ''
  if (typeof d === 'string') return d.slice(0, 10)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}
function toDate(s) { if (!s) return null; const d = new Date(s); d.setHours(0, 0, 0, 0); return d }
function sameDay(a, b) { return a && b && isoDate(a) === isoDate(b) }
function fmtDate(d) { return d ? (typeof d === 'string' ? new Date(d + 'T00:00:00') : d).toLocaleDateString('cs-CZ') : '—' }
function fmtCZK(n) { return Number(n || 0).toLocaleString('cs-CZ') }
function countDays(start, end) {
  if (!start || !end) return 0
  const s = toDate(typeof start === 'string' ? start : isoDate(start))
  const e = toDate(typeof end === 'string' ? end : isoDate(end))
  return Math.max(1, Math.round((e - s) / 86400000) + 1)
}

export default function BookingModifyModal({ booking, onClose, onSaved }) {
  // Dates
  const origStart = toDate(booking.start_date)
  const origEnd = toDate(booking.end_date)
  const [startDate, setStartDate] = useState(origStart)
  const [endDate, setEndDate] = useState(origEnd)
  const [calStep, setCalStep] = useState(0) // 0=not selecting, 1=picking start, 2=picking end
  const [calMonth, setCalMonth] = useState(() => ({ m: origStart.getMonth(), y: origStart.getFullYear() }))

  // Motorcycle
  const [changingMoto, setChangingMoto] = useState(false)
  const [allMotos, setAllMotos] = useState([])
  const [motoPrices, setMotoPrices] = useState({})
  const [selectedMotoId, setSelectedMotoId] = useState(booking.moto_id)
  const [overlappingBookings, setOverlappingBookings] = useState([])
  const [branches, setBranches] = useState([])
  const [branchFilter, setBranchFilter] = useState('')

  // Pickup/Return
  const [pickupMethod, setPickupMethod] = useState(booking.pickup_method || 'on_branch')
  const [pickupAddress, setPickupAddress] = useState(booking.pickup_address || '')
  const [returnMethod, setReturnMethod] = useState(booking.return_method || 'on_branch')
  const [returnAddress, setReturnAddress] = useState(booking.return_address || '')
  const [deliveryFee, setDeliveryFee] = useState(Number(booking.delivery_fee) || 0)

  // Payment
  const [chargeCustomer, setChargeCustomer] = useState(true)
  const [notes, setNotes] = useState(booking.notes || '')

  // State
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [loadingMotos, setLoadingMotos] = useState(false)

  // Load motorcycles + prices + branches
  useEffect(() => {
    async function load() {
      setLoadingMotos(true)
      const [motosRes, pricesRes, branchesRes] = await Promise.all([
        supabase.from('motorcycles').select('id, model, spz, category, image_url, status, branch_id, license_required, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun').order('model'),
        supabase.from('moto_day_prices').select('*'),
        supabase.from('branches').select('id, name').order('name'),
      ])
      setAllMotos(motosRes.data || [])
      const pm = {}; (pricesRes.data || []).forEach(p => { pm[p.moto_id] = p })
      setMotoPrices(pm)
      setBranches(branchesRes.data || [])
      setLoadingMotos(false)
    }
    load()
  }, [])

  // Load overlapping bookings when dates change
  useEffect(() => {
    if (!startDate || !endDate) return
    supabase.from('bookings')
      .select('id, moto_id, start_date, end_date, status')
      .in('status', ['reserved', 'active', 'pending'])
      .neq('id', booking.id)
      .lte('start_date', isoDate(endDate))
      .gte('end_date', isoDate(startDate))
      .then(({ data }) => setOverlappingBookings(data || []))
  }, [startDate, endDate])

  const occupiedMotoIds = useMemo(() => new Set(overlappingBookings.map(b => b.moto_id)), [overlappingBookings])

  // Price calculation
  function calcDayBreakdown(motoId, start, end) {
    if (!motoId || !start || !end) return []
    const dp = motoPrices[motoId]
    const moto = allMotos.find(m => m.id === motoId)
    const days = []
    const cur = new Date(start)
    const endD = new Date(end)
    while (cur <= endD) {
      const dow = cur.getDay()
      const price = (dp && Number(dp[DAY_KEYS_JS[dow]])) || (moto && Number(moto[DAY_KEYS_MOTO[dow]])) || 0
      days.push({ date: new Date(cur), dow, dowLabel: DOW_LABELS[dow], price })
      cur.setDate(cur.getDate() + 1)
    }
    return days
  }

  const origBreakdown = useMemo(() => calcDayBreakdown(booking.moto_id, origStart, origEnd), [motoPrices, allMotos])
  const newBreakdown = useMemo(() => calcDayBreakdown(selectedMotoId, startDate, endDate), [selectedMotoId, startDate, endDate, motoPrices, allMotos])

  const origCalcPrice = origBreakdown.reduce((s, d) => s + d.price, 0)
  const newCalcPrice = newBreakdown.reduce((s, d) => s + d.price, 0)
  const origPaidPrice = Number(booking.total_price) || 0
  const newDeliveryFee = (pickupMethod === 'delivery' || returnMethod === 'delivery') ? deliveryFee : 0
  const newTotalPrice = newCalcPrice + newDeliveryFee
  const priceDiff = newTotalPrice - origPaidPrice

  const selectedMoto = allMotos.find(m => m.id === selectedMotoId)
  const motoChanged = selectedMotoId !== booking.moto_id
  const datesChanged = isoDate(startDate) !== isoDate(origStart) || isoDate(endDate) !== isoDate(origEnd)
  const deliveryChanged = pickupMethod !== (booking.pickup_method || 'on_branch') || returnMethod !== (booking.return_method || 'on_branch') || pickupAddress !== (booking.pickup_address || '') || returnAddress !== (booking.return_address || '')
  const hasChanges = datesChanged || motoChanged || deliveryChanged || notes !== (booking.notes || '')

  const days = countDays(startDate, endDate)
  const origDays = countDays(origStart, origEnd)

  // Calendar
  function handleCalClick(date) {
    if (calStep === 1) {
      setStartDate(date)
      setEndDate(null)
      setCalStep(2)
    } else if (calStep === 2) {
      if (date < startDate) {
        setStartDate(date)
        setEndDate(null)
        setCalStep(2)
      } else {
        setEndDate(date)
        setCalStep(0)
      }
    }
  }

  function renderCalendar() {
    const { m, y } = calMonth
    const firstDay = new Date(y, m, 1)
    let startIdx = firstDay.getDay() - 1; if (startIdx < 0) startIdx = 6
    const daysInMonth = new Date(y, m + 1, 0).getDate()
    const today = new Date(); today.setHours(0, 0, 0, 0)
    const cells = []
    for (let i = 0; i < startIdx; i++) cells.push(null)
    for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(y, m, d))

    return (
      <div>
        <div className="flex items-center justify-between mb-2">
          <button onClick={() => setCalMonth(p => p.m === 0 ? { m: 11, y: p.y - 1 } : { m: p.m - 1, y: p.y })}
            className="cursor-pointer text-sm font-bold" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 10px', color: '#1a2e22' }}>←</button>
          <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{MONTH_NAMES[m]} {y}</span>
          <button onClick={() => setCalMonth(p => p.m === 11 ? { m: 0, y: p.y + 1 } : { m: p.m + 1, y: p.y })}
            className="cursor-pointer text-sm font-bold" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 10px', color: '#1a2e22' }}>→</button>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2 }}>
          {DAY_NAMES.map(n => <div key={n} className="text-sm font-bold text-center" style={{ color: '#1a2e22', padding: 3 }}>{n}</div>)}
          {cells.map((date, i) => {
            if (!date) return <div key={`e${i}`} />
            const past = date < today
            const isStart = sameDay(date, startDate)
            const isEnd = sameDay(date, endDate)
            const isInRange = startDate && endDate && date >= startDate && date <= endDate
            const isSelected = isStart || isEnd
            const isOrigStart = sameDay(date, origStart)
            const isOrigEnd = sameDay(date, origEnd)
            const isOrigRange = date >= origStart && date <= origEnd && !isInRange

            let bg = '#fff', color = '#0f1a14', border = '1px solid #e5e7eb', fontWeight = 500
            if (past) { color = '#d1d5db'; border = '1px solid #f3f4f6' }
            else if (isSelected) { bg = '#74FB71'; color = '#0f1a14'; border = '2px solid #3dba3a'; fontWeight = 800 }
            else if (isInRange) { bg = '#d1fae5'; border = '1px solid #a7f3d0' }
            else if (isOrigRange) { bg = '#fef3c7'; border = '1px solid #fde68a' }

            return (
              <button key={i} disabled={past || calStep === 0}
                onClick={() => !past && calStep > 0 && handleCalClick(date)}
                className="text-sm text-center" style={{
                  background: bg, color, border, borderRadius: 6, padding: '6px 0', fontWeight,
                  opacity: past ? 0.35 : calStep === 0 ? 0.7 : 1,
                  cursor: past || calStep === 0 ? 'default' : 'pointer',
                  position: 'relative',
                }}>
                {date.getDate()}
                {(isOrigStart || isOrigEnd) && !isSelected && (
                  <div style={{ position: 'absolute', bottom: 1, left: '50%', transform: 'translateX(-50%)', width: 4, height: 4, borderRadius: '50%', background: '#f59e0b' }} />
                )}
              </button>
            )
          })}
        </div>
        <div className="flex items-center gap-4 mt-2 text-xs" style={{ color: '#1a2e22' }}>
          <span><span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 2, background: '#fef3c7', border: '1px solid #fde68a', verticalAlign: 'middle', marginRight: 3 }} />Původní termín</span>
          <span><span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 2, background: '#d1fae5', border: '1px solid #a7f3d0', verticalAlign: 'middle', marginRight: 3 }} />Nový termín</span>
        </div>
      </div>
    )
  }

  // Save
  async function handleSave() {
    if (!startDate || !endDate) { setError('Vyberte termín'); return }
    if (selectedMotoId && occupiedMotoIds.has(selectedMotoId)) { setError('Vybraná motorka je v termínu obsazená'); return }

    setSaving(true); setError(null)
    try {
      const saveData = {
        start_date: isoDate(startDate),
        end_date: isoDate(endDate),
        total_price: chargeCustomer ? newTotalPrice : origPaidPrice,
        notes: notes || null,
        pickup_method: pickupMethod,
        pickup_address: pickupAddress || null,
        return_method: returnMethod,
        return_address: returnAddress || null,
        delivery_fee: newDeliveryFee,
      }

      if (motoChanged) {
        saveData.moto_id = selectedMotoId
      }

      // Track date modifications
      if (datesChanged) {
        const { data: dbBooking } = await supabase.from('bookings')
          .select('start_date, end_date, original_start_date, original_end_date, modification_history')
          .eq('id', booking.id).single()

        if (dbBooking) {
          const toLD = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
          if (!dbBooking.original_start_date) {
            saveData.original_start_date = toLD(dbBooking.start_date)
            saveData.original_end_date = toLD(dbBooking.end_date)
          }
          const history = Array.isArray(dbBooking.modification_history) ? [...dbBooking.modification_history] : []
          history.push({
            at: new Date().toISOString(),
            from_start: toLD(dbBooking.start_date),
            from_end: toLD(dbBooking.end_date),
            to_start: isoDate(startDate),
            to_end: isoDate(endDate),
            source: 'admin',
            ...(motoChanged ? { moto_changed: true, from_moto: booking.motorcycles?.model, to_moto: selectedMoto?.model } : {}),
            ...(priceDiff !== 0 ? { price_diff: priceDiff, charged: chargeCustomer } : {}),
          })
          saveData.modification_history = history
        }
      }

      const { error: saveErr } = await supabase.from('bookings').update(saveData).eq('id', booking.id)
      if (saveErr) throw saveErr

      // Audit log
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({
          admin_id: user?.id, action: 'booking_modified',
          details: {
            booking_id: booking.id,
            dates_changed: datesChanged,
            moto_changed: motoChanged,
            delivery_changed: deliveryChanged,
            price_diff: priceDiff,
            charged: chargeCustomer,
            new_total: chargeCustomer ? newTotalPrice : origPaidPrice,
          }
        })
      } catch {}

      // Send modification email
      if (['reserved', 'active'].includes(booking.status) && booking.profiles?.email) {
        try {
          await supabase.functions.invoke('send-booking-email', {
            body: {
              type: 'booking_modified', booking_id: booking.id,
              customer_email: booking.profiles.email,
              customer_name: booking.profiles.full_name,
              motorcycle: motoChanged ? selectedMoto?.model : booking.motorcycles?.model,
              start_date: isoDate(startDate), end_date: isoDate(endDate),
              total_price: chargeCustomer ? newTotalPrice : origPaidPrice,
            },
          })
        } catch {}
      }

      onSaved()
    } catch (e) {
      setError(e.message)
    } finally {
      setSaving(false)
    }
  }

  // Motorcycle list for changing
  const filteredMotos = useMemo(() => {
    let list = allMotos.filter(m => m.status === 'active' || m.id === booking.moto_id)
    if (branchFilter) list = list.filter(m => m.branch_id === branchFilter)
    return list
  }, [allMotos, branchFilter, booking.moto_id])

  const availableMotos = filteredMotos.filter(m => !occupiedMotoIds.has(m.id) || m.id === booking.moto_id)
  const unavailableMotos = filteredMotos.filter(m => occupiedMotoIds.has(m.id) && m.id !== booking.moto_id)

  function calcMotoPrice(motoId) {
    if (!startDate || !endDate) return null
    const bd = calcDayBreakdown(motoId, startDate, endDate)
    return bd.reduce((s, d) => s + d.price, 0)
  }

  return (
    <Modal open title={`Upravit rezervaci #${booking.id?.slice(-8).toUpperCase()}`} onClose={onClose} wide>
      <div style={{ maxHeight: 'calc(100vh - 160px)', overflowY: 'auto' }}>
        {error && <div className="p-3 rounded-lg mb-4" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13, fontWeight: 600 }}>{error}</div>}

        {/* === SECTION: DATES === */}
        <div className="mb-5">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Termín</h3>
            {calStep === 0 ? (
              <button onClick={() => setCalStep(1)}
                className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}>
                Změnit termín
              </button>
            ) : (
              <span className="text-sm font-bold" style={{ color: '#f59e0b' }}>
                {calStep === 1 ? 'Klikněte na datum vyzvednutí' : 'Klikněte na datum vrácení'}
              </span>
            )}
          </div>

          {calStep > 0 && renderCalendar()}

          <div className="p-3 rounded-lg mt-2" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <div className="grid grid-cols-4 gap-4">
              <div>
                <div className="text-xs font-bold uppercase" style={{ color: '#1a2e22' }}>Od</div>
                <div className="text-sm font-extrabold" style={{ color: datesChanged ? '#2563eb' : '#0f1a14' }}>
                  {fmtDate(startDate)}
                </div>
                {datesChanged && <div className="text-xs" style={{ color: '#9ca3af' }}>bylo: {fmtDate(origStart)}</div>}
              </div>
              <div>
                <div className="text-xs font-bold uppercase" style={{ color: '#1a2e22' }}>Do</div>
                <div className="text-sm font-extrabold" style={{ color: datesChanged ? '#2563eb' : '#0f1a14' }}>
                  {endDate ? fmtDate(endDate) : '—'}
                </div>
                {datesChanged && <div className="text-xs" style={{ color: '#9ca3af' }}>bylo: {fmtDate(origEnd)}</div>}
              </div>
              <div>
                <div className="text-xs font-bold uppercase" style={{ color: '#1a2e22' }}>Dní</div>
                <div className="text-sm font-extrabold" style={{ color: days !== origDays ? '#2563eb' : '#0f1a14' }}>
                  {days} {days === 1 ? 'den' : days < 5 ? 'dny' : 'dní'}
                </div>
                {days !== origDays && <div className="text-xs" style={{ color: days > origDays ? '#1a8a18' : '#dc2626' }}>{days > origDays ? '+' : ''}{days - origDays} d</div>}
              </div>
              {calStep > 0 && (
                <div className="flex items-end">
                  <button onClick={() => { setStartDate(origStart); setEndDate(origEnd); setCalStep(0) }}
                    className="text-sm font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none', padding: 0 }}>
                    Zrušit změnu
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* === SECTION: MOTORCYCLE === */}
        <div className="mb-5">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Motorka</h3>
            <button onClick={() => setChangingMoto(!changingMoto)}
              className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}>
              {changingMoto ? 'Skrýt výběr' : 'Změnit motorku'}
            </button>
          </div>

          <div className="p-3 rounded-lg" style={{ background: motoChanged ? '#dbeafe' : '#f1faf7', border: `1px solid ${motoChanged ? '#93c5fd' : '#d4e8e0'}` }}>
            <div className="flex items-center gap-3">
              <div className="flex-1">
                <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>
                  {selectedMoto?.model || booking.motorcycles?.model || '—'}
                </div>
                <div className="text-xs" style={{ color: '#1a2e22' }}>
                  {selectedMoto?.spz || booking.motorcycles?.spz || '—'} · {selectedMoto?.category || '—'}
                </div>
              </div>
              {motoChanged && (
                <div className="text-right">
                  <div className="text-xs" style={{ color: '#9ca3af' }}>bylo: {booking.motorcycles?.model}</div>
                  <button onClick={() => { setSelectedMotoId(booking.moto_id); setChangingMoto(false) }}
                    className="text-xs font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none', padding: 0 }}>
                    Vrátit původní
                  </button>
                </div>
              )}
            </div>
          </div>

          {changingMoto && (
            <div className="mt-3">
              <div className="flex items-center gap-3 mb-2">
                <select value={branchFilter} onChange={e => setBranchFilter(e.target.value)}
                  className="text-sm font-bold cursor-pointer" style={{ padding: '4px 8px', borderRadius: 8, border: '1px solid #d4e8e0', background: '#f1faf7', color: '#1a2e22' }}>
                  <option value="">Všechny pobočky</option>
                  {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
                </select>
                <span className="text-xs font-bold" style={{ color: '#1a8a18' }}>{availableMotos.length} volných</span>
              </div>
              {loadingMotos ? (
                <div className="py-4 text-center"><div className="animate-spin inline-block rounded-full h-5 w-5 border-t-2 border-brand-gd" /></div>
              ) : (
                <div style={{ maxHeight: 260, overflowY: 'auto' }}>
                  {availableMotos.map(m => {
                    const price = calcMotoPrice(m.id)
                    const isSelected = m.id === selectedMotoId
                    const isCurrent = m.id === booking.moto_id
                    const pDiff = price !== null ? price + newDeliveryFee - origPaidPrice : null
                    return (
                      <div key={m.id} onClick={() => setSelectedMotoId(m.id)}
                        className="flex items-center gap-3 p-2 rounded-lg mb-1 cursor-pointer" style={{
                          background: isSelected ? '#eafbe9' : '#f8faf9',
                          border: isSelected ? '2px solid #74FB71' : '1px solid #e5e7eb',
                        }}>
                        {m.image_url ? (
                          <img src={m.image_url} alt={m.model} style={{ width: 56, height: 38, objectFit: 'cover', borderRadius: 6 }} />
                        ) : (
                          <div style={{ width: 56, height: 38, borderRadius: 6, background: '#f1faf7', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18 }}>🏍️</div>
                        )}
                        <div className="flex-1 min-w-0">
                          <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>
                            {m.model} {isCurrent && <span className="text-xs font-bold" style={{ color: '#1a8a18' }}>(aktuální)</span>}
                          </div>
                          <div className="text-xs" style={{ color: '#1a2e22' }}>{m.spz || '—'} · {m.category || '—'}</div>
                        </div>
                        <div className="text-right">
                          <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{price !== null ? fmtCZK(price) + ' Kč' : '—'}</div>
                          {pDiff !== null && pDiff !== 0 && (
                            <div className="text-xs font-bold" style={{ color: pDiff > 0 ? '#dc2626' : '#1a8a18' }}>
                              {pDiff > 0 ? '+' : ''}{fmtCZK(pDiff)} Kč
                            </div>
                          )}
                        </div>
                        {isSelected && <span style={{ color: '#1a8a18', fontWeight: 800 }}>✓</span>}
                      </div>
                    )
                  })}
                  {unavailableMotos.length > 0 && (
                    <>
                      <div className="text-xs font-bold uppercase tracking-wide mt-3 mb-1" style={{ color: '#dc2626' }}>Obsazené ({unavailableMotos.length})</div>
                      {unavailableMotos.map(m => (
                        <div key={m.id} className="flex items-center gap-3 p-2 rounded-lg mb-1" style={{ background: '#fafafa', border: '1px solid #f3f4f6', opacity: 0.4 }}>
                          <div style={{ width: 56, height: 38, borderRadius: 6, background: '#f3f4f6', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18 }}>🏍️</div>
                          <div className="flex-1"><div className="text-sm font-bold" style={{ color: '#1a2e22' }}>{m.model}</div><div className="text-xs" style={{ color: '#1a2e22' }}>{m.spz || '—'} · Obsazená</div></div>
                        </div>
                      ))}
                    </>
                  )}
                </div>
              )}
            </div>
          )}
        </div>

        {/* === SECTION: PICKUP & RETURN === */}
        <div className="mb-5">
          <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Přistavení a vrácení</h3>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Vyzvednutí</label>
              <select value={pickupMethod} onChange={e => setPickupMethod(e.target.value)}
                className="w-full text-sm font-bold cursor-pointer" style={{ padding: '7px 10px', borderRadius: 8, border: '1px solid #d4e8e0', background: '#f1faf7', color: '#1a2e22' }}>
                <option value="on_branch">Na pobočce</option>
                <option value="delivery">Přistavení na adresu</option>
              </select>
              {pickupMethod === 'delivery' && (
                <input value={pickupAddress} onChange={e => setPickupAddress(e.target.value)}
                  placeholder="Obec, ulice a č.p. / č.o." className="w-full mt-2 text-sm rounded-btn outline-none"
                  style={{ padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
              )}
              {pickupMethod === 'on_branch' && pickupAddress && (
                <div className="mt-1 text-xs" style={{ color: '#6b7280' }}>Původní adresa: {pickupAddress}</div>
              )}
            </div>
            <div>
              <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Vrácení</label>
              <select value={returnMethod} onChange={e => setReturnMethod(e.target.value)}
                className="w-full text-sm font-bold cursor-pointer" style={{ padding: '7px 10px', borderRadius: 8, border: '1px solid #d4e8e0', background: '#f1faf7', color: '#1a2e22' }}>
                <option value="on_branch">Na pobočce</option>
                <option value="delivery">Svoz z adresy</option>
              </select>
              {returnMethod === 'delivery' && (
                <input value={returnAddress} onChange={e => setReturnAddress(e.target.value)}
                  placeholder="Obec, ulice a č.p. / č.o." className="w-full mt-2 text-sm rounded-btn outline-none"
                  style={{ padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
              )}
              {returnMethod === 'on_branch' && returnAddress && (
                <div className="mt-1 text-xs" style={{ color: '#6b7280' }}>Původní adresa: {returnAddress}</div>
              )}
            </div>
          </div>
          {(pickupMethod === 'delivery' || returnMethod === 'delivery') && (
            <div className="mt-3">
              <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Poplatek za doručení (Kč)</label>
              <input type="number" value={deliveryFee} onChange={e => setDeliveryFee(Number(e.target.value) || 0)}
                className="text-sm rounded-btn outline-none" style={{ padding: '7px 10px', width: 140, background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            </div>
          )}
        </div>

        {/* === SECTION: PRICE CALCULATION === */}
        <div className="mb-5">
          <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Kalkulace ceny</h3>

          {/* Day-by-day breakdown */}
          {newBreakdown.length > 0 && (
            <div className="mb-3 p-3 rounded-lg" style={{ background: '#f8faf9', border: '1px solid #e5e7eb' }}>
              <div className="text-xs font-bold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Rozpad po dnech — {selectedMoto?.model || booking.motorcycles?.model}</div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(130px, 1fr))', gap: 4 }}>
                {newBreakdown.map((d, i) => (
                  <div key={i} className="flex items-center justify-between text-xs px-2 py-1 rounded" style={{ background: d.dow === 0 || d.dow === 6 ? '#fef3c7' : '#fff', border: '1px solid #f3f4f6' }}>
                    <span style={{ color: '#1a2e22' }}>{d.dowLabel} {d.date.getDate()}.{d.date.getMonth() + 1}.</span>
                    <span className="font-extrabold" style={{ color: '#0f1a14' }}>{fmtCZK(d.price)} Kč</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Price summary */}
          <div className="p-4 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span style={{ color: '#1a2e22' }}>Původní cena (zaplaceno)</span>
                <span className="font-bold" style={{ color: '#0f1a14' }}>{fmtCZK(origPaidPrice)} Kč</span>
              </div>
              {origCalcPrice > 0 && origCalcPrice !== origPaidPrice && (
                <div className="flex justify-between text-xs">
                  <span style={{ color: '#9ca3af' }}>Dle ceníku (původní motorka × {origDays}d)</span>
                  <span style={{ color: '#9ca3af' }}>{fmtCZK(origCalcPrice)} Kč</span>
                </div>
              )}
              <div className="flex justify-between text-sm">
                <span style={{ color: '#1a2e22' }}>Nová cena dle ceníku ({days}d)</span>
                <span className="font-bold" style={{ color: '#0f1a14' }}>{fmtCZK(newCalcPrice)} Kč</span>
              </div>
              {newDeliveryFee > 0 && (
                <div className="flex justify-between text-sm">
                  <span style={{ color: '#1a2e22' }}>Doručení</span>
                  <span className="font-bold">{fmtCZK(newDeliveryFee)} Kč</span>
                </div>
              )}
              <div style={{ borderTop: '2px solid #d4e8e0', paddingTop: 8, marginTop: 4 }}>
                <div className="flex justify-between text-sm font-extrabold">
                  <span style={{ color: '#1a2e22' }}>Nová celková cena</span>
                  <span style={{ color: '#0f1a14' }}>{fmtCZK(newTotalPrice)} Kč</span>
                </div>
              </div>
              {priceDiff !== 0 && (
                <div className="flex justify-between text-sm font-extrabold mt-1 p-2 rounded"
                  style={{ background: priceDiff > 0 ? '#fee2e2' : '#dcfce7', border: `1px solid ${priceDiff > 0 ? '#fca5a5' : '#86efac'}` }}>
                  <span style={{ color: priceDiff > 0 ? '#dc2626' : '#1a8a18' }}>
                    {priceDiff > 0 ? 'Doplatek' : 'Přeplatek'}
                  </span>
                  <span style={{ color: priceDiff > 0 ? '#dc2626' : '#1a8a18' }}>
                    {priceDiff > 0 ? '+' : ''}{fmtCZK(priceDiff)} Kč
                  </span>
                </div>
              )}
            </div>

            {/* Payment decision */}
            {priceDiff !== 0 && (
              <div className="mt-4 space-y-2">
                <div className="text-xs font-bold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Řešení cenového rozdílu</div>
                <label className="flex items-center gap-2 cursor-pointer p-2 rounded-lg" style={{ background: chargeCustomer ? '#eafbe9' : '#fff', border: `1px solid ${chargeCustomer ? '#74FB71' : '#e5e7eb'}` }}>
                  <input type="radio" checked={chargeCustomer} onChange={() => setChargeCustomer(true)} style={{ accentColor: '#1a8a18' }} />
                  <div>
                    <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>
                      {priceDiff > 0 ? `Zákazník doplatí (+${fmtCZK(priceDiff)} Kč)` : `Vrátit zákazníkovi (${fmtCZK(Math.abs(priceDiff))} Kč)`}
                    </div>
                    <div className="text-xs" style={{ color: '#1a2e22' }}>Celkem bude {fmtCZK(newTotalPrice)} Kč</div>
                  </div>
                </label>
                <label className="flex items-center gap-2 cursor-pointer p-2 rounded-lg" style={{ background: !chargeCustomer ? '#eafbe9' : '#fff', border: `1px solid ${!chargeCustomer ? '#74FB71' : '#e5e7eb'}` }}>
                  <input type="radio" checked={!chargeCustomer} onChange={() => setChargeCustomer(false)} style={{ accentColor: '#1a8a18' }} />
                  <div>
                    <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>Zdarma (bez doplatku)</div>
                    <div className="text-xs" style={{ color: '#1a2e22' }}>Cena zůstane {fmtCZK(origPaidPrice)} Kč</div>
                  </div>
                </label>
              </div>
            )}
          </div>
        </div>

        {/* === SECTION: NOTES === */}
        <div className="mb-5">
          <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Poznámky</label>
          <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2}
            className="w-full text-sm rounded-btn outline-none"
            style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
            placeholder="Interní poznámky k úpravě…" />
        </div>

        {/* === ACTIONS === */}
        <div className="flex items-center justify-between pt-3" style={{ borderTop: '1px solid #e5e7eb' }}>
          <div className="text-xs" style={{ color: '#9ca3af' }}>
            {hasChanges ? (
              <span style={{ color: '#2563eb', fontWeight: 700 }}>
                Změny: {[datesChanged && 'termín', motoChanged && 'motorka', deliveryChanged && 'doručení', notes !== (booking.notes || '') && 'poznámky'].filter(Boolean).join(', ')}
              </span>
            ) : (
              'Žádné změny'
            )}
          </div>
          <div className="flex gap-3">
            <Button onClick={onClose}>Zrušit</Button>
            <Button green onClick={handleSave} disabled={saving || !hasChanges || !startDate || !endDate}>
              {saving ? 'Ukládám…' : 'Uložit změny'}
            </Button>
          </div>
        </div>
      </div>
    </Modal>
  )
}
