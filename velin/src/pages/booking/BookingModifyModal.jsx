import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import BookingCalendar from './BookingCalendar'
import BookingMotoSelector from './BookingMotoSelector'
import BookingMapPicker from './BookingMapPicker'
import BookingPriceCalc from './BookingPriceCalc'
import BookingDeliverySection from './BookingDeliverySection'
import { isoDate, toDate, fmtDate, fmtCZK, countDays, calcDayBreakdown } from './bookingModifyHelpers'

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

  const origBreakdown = useMemo(() => calcDayBreakdown(booking.moto_id, origStart, origEnd, motoPrices, allMotos), [motoPrices, allMotos])
  const newBreakdown = useMemo(() => calcDayBreakdown(selectedMotoId, startDate, endDate, motoPrices, allMotos), [selectedMotoId, startDate, endDate, motoPrices, allMotos])

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
      // Při zkrácení rezervace (záporný rozdíl) + placeno kartou → automatický Stripe refund + dobropis
      // Proběhne jen pokud admin označil "naúčtovat zákazníkovi" (jinak je zkrácení bez vratky).
      if (chargeCustomer && priceDiff < 0 && booking.stripe_payment_intent_id) {
        try {
          await supabase.functions.invoke('process-refund', {
            body: { booking_id: booking.id, amount: Math.abs(priceDiff), reason: 'shortening' },
          })
        } catch (refundErr) {
          console.warn('[BookingModify] refund failed:', refundErr?.message)
        }
      }

      if (['reserved', 'active'].includes(booking.status) && booking.profiles?.email) {
        try {
          await supabase.functions.invoke('send-booking-email', {
            body: { type: 'booking_modified', booking_id: booking.id, customer_email: booking.profiles.email, customer_name: booking.profiles.full_name, motorcycle: motoChanged ? selectedMoto?.model : booking.motorcycles?.model, start_date: isoDate(startDate), end_date: isoDate(endDate), total_price: chargeCustomer ? newTotalPrice : origPaidPrice, price_difference: chargeCustomer ? priceDiff : 0, source: booking.booking_source || 'app' },
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
    return calcDayBreakdown(motoId, startDate, endDate, motoPrices, allMotos).reduce((s, d) => s + d.price, 0)
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
        <BookingDeliverySection pickupMethod={pickupMethod} setPickupMethod={setPickupMethod} pickupAddress={pickupAddress} setPickupAddress={setPickupAddress} returnMethod={returnMethod} setReturnMethod={setReturnMethod} returnAddress={returnAddress} setReturnAddress={setReturnAddress} deliveryFee={deliveryFee} setDeliveryFee={setDeliveryFee} setShowMapPicker={setShowMapPicker} />

        {/* PRICE CALCULATION */}
        <BookingPriceCalc newBreakdown={newBreakdown} selectedMoto={selectedMoto} booking={booking} origCalcPrice={origCalcPrice} origPaidPrice={origPaidPrice} origDays={origDays} newCalcPrice={newCalcPrice} newDeliveryFee={newDeliveryFee} newTotalPrice={newTotalPrice} priceDiff={priceDiff} days={days} chargeCustomer={chargeCustomer} setChargeCustomer={setChargeCustomer} />

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
