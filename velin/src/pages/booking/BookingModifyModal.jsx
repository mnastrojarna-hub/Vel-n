import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import BookingCalendar from './BookingCalendar'
import BookingMotoSelector from './BookingMotoSelector'
import BookingMapPicker from './BookingMapPicker'
import BookingPriceSection from './BookingPriceSection'

const DAY_KEYS_JS = { 0: 'price_sunday', 1: 'price_monday', 2: 'price_tuesday', 3: 'price_wednesday', 4: 'price_thursday', 5: 'price_friday', 6: 'price_saturday' }
const DAY_KEYS_MOTO = { 0: 'price_sun', 1: 'price_mon', 2: 'price_tue', 3: 'price_wed', 4: 'price_thu', 5: 'price_fri', 6: 'price_sat' }
const DOW_LABELS = ['Ne', 'Po', 'Ut', 'St', 'Ct', 'Pa', 'So']

function isoDate(d) {
  if (!d) return ''
  if (typeof d === 'string') return d.slice(0, 10)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}
function toDate(s) { if (!s) return null; const d = new Date(s); d.setHours(0, 0, 0, 0); return d }
function fmtDate(d) { return d ? (typeof d === 'string' ? new Date(d + 'T00:00:00') : d).toLocaleDateString('cs-CZ') : '\u2014' }
function fmtCZK(n) { return Number(n || 0).toLocaleString('cs-CZ') }
function countDays(start, end) {
  if (!start || !end) return 0
  const s = toDate(typeof start === 'string' ? start : isoDate(start))
  const e = toDate(typeof end === 'string' ? end : isoDate(end))
  return Math.max(1, Math.round((e - s) / 86400000) + 1)
}

export default function BookingModifyModal({ booking, onClose, onSaved }) {
  const origStart = toDate(booking.start_date)
  const origEnd = toDate(booking.end_date)
  const [startDate, setStartDate] = useState(origStart)
  const [endDate, setEndDate] = useState(origEnd)
  const [calStep, setCalStep] = useState(0)
  const [calMonth, setCalMonth] = useState(() => ({ m: origStart.getMonth(), y: origStart.getFullYear() }))

  const [changingMoto, setChangingMoto] = useState(false)
  const [allMotos, setAllMotos] = useState([])
  const [motoPrices, setMotoPrices] = useState({})
  const [selectedMotoId, setSelectedMotoId] = useState(booking.moto_id)
  const [overlappingBookings, setOverlappingBookings] = useState([])
  const [branches, setBranches] = useState([])
  const [branchFilter, setBranchFilter] = useState('')

  const [pickupMethod, setPickupMethod] = useState(booking.pickup_method || 'on_branch')
  const [pickupAddress, setPickupAddress] = useState(booking.pickup_address || '')
  const [returnMethod, setReturnMethod] = useState(booking.return_method || 'on_branch')
  const [returnAddress, setReturnAddress] = useState(booking.return_address || '')
  const [deliveryFee, setDeliveryFee] = useState(Number(booking.delivery_fee) || 0)
  const [showMapPicker, setShowMapPicker] = useState(null)

  const [chargeCustomer, setChargeCustomer] = useState(true)
  const [notes, setNotes] = useState(booking.notes || '')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [loadingMotos, setLoadingMotos] = useState(false)

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

  function handleCalClick(date) {
    if (calStep === 1) { setStartDate(date); setEndDate(null); setCalStep(2) }
    else if (calStep === 2) {
      if (date < startDate) { setStartDate(date); setEndDate(null); setCalStep(2) }
      else { setEndDate(date); setCalStep(0) }
    }
  }

  async function handleSave() {
    if (!startDate || !endDate) { setError('Vyberte termin'); return }
    if (selectedMotoId && occupiedMotoIds.has(selectedMotoId)) { setError('Vybrana motorka je v terminu obsazena'); return }
    setSaving(true); setError(null)
    try {
      const saveData = {
        start_date: isoDate(startDate), end_date: isoDate(endDate),
        total_price: chargeCustomer ? newTotalPrice : origPaidPrice,
        notes: notes || null, pickup_method: pickupMethod, pickup_address: pickupAddress || null,
        return_method: returnMethod, return_address: returnAddress || null, delivery_fee: newDeliveryFee,
      }
      if (motoChanged) saveData.moto_id = selectedMotoId
      if (datesChanged) {
        const { data: dbBooking } = await supabase.from('bookings')
          .select('start_date, end_date, original_start_date, original_end_date, modification_history')
          .eq('id', booking.id).single()
        if (dbBooking) {
          const toLD = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
          if (!dbBooking.original_start_date) { saveData.original_start_date = toLD(dbBooking.start_date); saveData.original_end_date = toLD(dbBooking.end_date) }
          const history = Array.isArray(dbBooking.modification_history) ? [...dbBooking.modification_history] : []
          history.push({
            at: new Date().toISOString(), from_start: toLD(dbBooking.start_date), from_end: toLD(dbBooking.end_date),
            to_start: isoDate(startDate), to_end: isoDate(endDate), source: 'admin',
            ...(motoChanged ? { moto_changed: true, from_moto: booking.motorcycles?.model, to_moto: selectedMoto?.model } : {}),
            ...(priceDiff !== 0 ? { price_diff: priceDiff, charged: chargeCustomer } : {}),
          })
          saveData.modification_history = history
        }
      }
      const { error: saveErr } = await supabase.from('bookings').update(saveData).eq('id', booking.id)
      if (saveErr) throw saveErr
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({
          admin_id: user?.id, action: 'booking_modified',
          details: { booking_id: booking.id, dates_changed: datesChanged, moto_changed: motoChanged, delivery_changed: deliveryChanged, price_diff: priceDiff, charged: chargeCustomer, new_total: chargeCustomer ? newTotalPrice : origPaidPrice }
        })
      } catch {}
      if (['reserved', 'active'].includes(booking.status) && booking.profiles?.email) {
        try {
          await supabase.functions.invoke('send-booking-email', {
            body: { type: 'booking_modified', booking_id: booking.id, customer_email: booking.profiles.email, customer_name: booking.profiles.full_name, motorcycle: motoChanged ? selectedMoto?.model : booking.motorcycles?.model, start_date: isoDate(startDate), end_date: isoDate(endDate), total_price: chargeCustomer ? newTotalPrice : origPaidPrice },
          })
        } catch {}
      }
      onSaved()
    } catch (e) { setError(e.message) }
    finally { setSaving(false) }
  }

  const filteredMotos = useMemo(() => {
    let list = allMotos.filter(m => m.status === 'active' || m.id === booking.moto_id)
    if (branchFilter) list = list.filter(m => m.branch_id === branchFilter)
    return list
  }, [allMotos, branchFilter, booking.moto_id])

  const availableMotos = filteredMotos.filter(m => !occupiedMotoIds.has(m.id) || m.id === booking.moto_id)
  const unavailableMotos = filteredMotos.filter(m => occupiedMotoIds.has(m.id) && m.id !== booking.moto_id)

  function calcMotoPrice(motoId) {
    if (!startDate || !endDate) return null
    return calcDayBreakdown(motoId, startDate, endDate).reduce((s, d) => s + d.price, 0)
  }

  return (<>
    <Modal open title={`Upravit rezervaci #${booking.id?.slice(-8).toUpperCase()}`} onClose={onClose} wide>
      <div style={{ maxHeight: 'calc(100vh - 160px)', overflowY: 'auto' }}>
        {error && <div className="p-3 rounded-lg mb-4" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13, fontWeight: 600 }}>{error}</div>}

        {/* DATES */}
        <div className="mb-5">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Termin</h3>
            {calStep === 0 ? (
              <button onClick={() => setCalStep(1)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}>Zmenit termin</button>
            ) : (
              <span className="text-sm font-bold" style={{ color: '#f59e0b' }}>{calStep === 1 ? 'Kliknete na datum vyzvednuti' : 'Kliknete na datum vraceni'}</span>
            )}
          </div>
          {calStep > 0 && <BookingCalendar calMonth={calMonth} setCalMonth={setCalMonth} calStep={calStep} startDate={startDate} endDate={endDate} origStart={origStart} origEnd={origEnd} onCalClick={handleCalClick} />}
          <div className="p-3 rounded-lg mt-2" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <div className="grid grid-cols-4 gap-4">
              <div>
                <div className="text-xs font-bold uppercase" style={{ color: '#1a2e22' }}>Od</div>
                <div className="text-sm font-extrabold" style={{ color: datesChanged ? '#2563eb' : '#0f1a14' }}>{fmtDate(startDate)}</div>
                {datesChanged && <div className="text-xs" style={{ color: '#9ca3af' }}>bylo: {fmtDate(origStart)}</div>}
              </div>
              <div>
                <div className="text-xs font-bold uppercase" style={{ color: '#1a2e22' }}>Do</div>
                <div className="text-sm font-extrabold" style={{ color: datesChanged ? '#2563eb' : '#0f1a14' }}>{endDate ? fmtDate(endDate) : '\u2014'}</div>
                {datesChanged && <div className="text-xs" style={{ color: '#9ca3af' }}>bylo: {fmtDate(origEnd)}</div>}
              </div>
              <div>
                <div className="text-xs font-bold uppercase" style={{ color: '#1a2e22' }}>Dni</div>
                <div className="text-sm font-extrabold" style={{ color: days !== origDays ? '#2563eb' : '#0f1a14' }}>{days} {days === 1 ? 'den' : days < 5 ? 'dny' : 'dni'}</div>
                {days !== origDays && <div className="text-xs" style={{ color: days > origDays ? '#1a8a18' : '#dc2626' }}>{days > origDays ? '+' : ''}{days - origDays} d</div>}
              </div>
              {calStep > 0 && (
                <div className="flex items-end">
                  <button onClick={() => { setStartDate(origStart); setEndDate(origEnd); setCalStep(0) }}
                    className="text-sm font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none', padding: 0 }}>Zrusit zmenu</button>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* MOTORCYCLE */}
        <BookingMotoSelector changingMoto={changingMoto} setChangingMoto={setChangingMoto} branchFilter={branchFilter} setBranchFilter={setBranchFilter} branches={branches} availableMotos={availableMotos} unavailableMotos={unavailableMotos} loadingMotos={loadingMotos} selectedMotoId={selectedMotoId} setSelectedMotoId={setSelectedMotoId} booking={booking} motoChanged={motoChanged} selectedMoto={selectedMoto} calcMotoPrice={calcMotoPrice} newDeliveryFee={newDeliveryFee} origPaidPrice={origPaidPrice} fmtCZK={fmtCZK} />

        {/* PICKUP & RETURN */}
        <div className="mb-5">
          <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Pristaveni a vraceni</h3>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Vyzvednuti</label>
              <select value={pickupMethod} onChange={e => setPickupMethod(e.target.value)} className="w-full text-sm font-bold cursor-pointer" style={{ padding: '7px 10px', borderRadius: 8, border: '1px solid #d4e8e0', background: '#f1faf7', color: '#1a2e22' }}>
                <option value="on_branch">Na pobocce</option><option value="delivery">Pristaveni na adresu</option>
              </select>
              {pickupMethod === 'delivery' && (<>
                <input value={pickupAddress} onChange={e => setPickupAddress(e.target.value)} placeholder="Obec, ulice a c.p. / c.o." className="w-full mt-2 text-sm rounded-btn outline-none" style={{ padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
                <button type="button" onClick={() => setShowMapPicker('pickup')} className="mt-1 text-xs font-bold cursor-pointer" style={{ padding: '4px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 6, color: '#1a2e22' }}>{'\ud83d\uddfa\ufe0f'} Vybrat na mape</button>
              </>)}
              {pickupMethod === 'on_branch' && pickupAddress && <div className="mt-1 text-xs" style={{ color: '#6b7280' }}>Puvodni adresa: {pickupAddress}</div>}
            </div>
            <div>
              <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Vraceni</label>
              <select value={returnMethod} onChange={e => setReturnMethod(e.target.value)} className="w-full text-sm font-bold cursor-pointer" style={{ padding: '7px 10px', borderRadius: 8, border: '1px solid #d4e8e0', background: '#f1faf7', color: '#1a2e22' }}>
                <option value="on_branch">Na pobocce</option><option value="delivery">Svoz z adresy</option>
              </select>
              {returnMethod === 'delivery' && (<>
                <input value={returnAddress} onChange={e => setReturnAddress(e.target.value)} placeholder="Obec, ulice a c.p. / c.o." className="w-full mt-2 text-sm rounded-btn outline-none" style={{ padding: '7px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
                <button type="button" onClick={() => setShowMapPicker('return')} className="mt-1 text-xs font-bold cursor-pointer" style={{ padding: '4px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 6, color: '#1a2e22' }}>{'\ud83d\uddfa\ufe0f'} Vybrat na mape</button>
              </>)}
              {returnMethod === 'on_branch' && returnAddress && <div className="mt-1 text-xs" style={{ color: '#6b7280' }}>Puvodni adresa: {returnAddress}</div>}
            </div>
          </div>
          {(pickupMethod === 'delivery' || returnMethod === 'delivery') && (
            <div className="mt-3">
              <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Poplatek za doruceni (Kc)</label>
              <input type="number" value={deliveryFee} onChange={e => setDeliveryFee(Number(e.target.value) || 0)} className="text-sm rounded-btn outline-none" style={{ padding: '7px 10px', width: 140, background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            </div>
          )}
        </div>

        <BookingPriceSection newBreakdown={newBreakdown} selectedMoto={selectedMoto} booking={booking} origCalcPrice={origCalcPrice} origPaidPrice={origPaidPrice} origDays={origDays} newCalcPrice={newCalcPrice} newDeliveryFee={newDeliveryFee} newTotalPrice={newTotalPrice} priceDiff={priceDiff} days={days} chargeCustomer={chargeCustomer} setChargeCustomer={setChargeCustomer} />

        {/* NOTES */}
        <div className="mb-5">
          <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Poznamky</label>
          <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} className="w-full text-sm rounded-btn outline-none" style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }} placeholder="Interni poznamky k uprave..." />
        </div>

        {/* ACTIONS */}
        <div className="flex items-center justify-between pt-3" style={{ borderTop: '1px solid #e5e7eb' }}>
          <div className="text-xs" style={{ color: '#9ca3af' }}>
            {hasChanges ? (
              <span style={{ color: '#2563eb', fontWeight: 700 }}>Zmeny: {[datesChanged && 'termin', motoChanged && 'motorka', deliveryChanged && 'doruceni', notes !== (booking.notes || '') && 'poznamky'].filter(Boolean).join(', ')}</span>
            ) : 'Zadne zmeny'}
          </div>
          <div className="flex gap-3">
            <Button onClick={onClose}>Zrusit</Button>
            <Button green onClick={handleSave} disabled={saving || !hasChanges || !startDate || !endDate}>{saving ? 'Ukladam...' : 'Ulozit zmeny'}</Button>
          </div>
        </div>
      </div>
    </Modal>

    <BookingMapPicker showMapPicker={showMapPicker} setShowMapPicker={setShowMapPicker} setPickupAddress={setPickupAddress} setReturnAddress={setReturnAddress} />
  </>)
}
