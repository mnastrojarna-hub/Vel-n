import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import BookingCalendar from './BookingCalendar'
import BookingMotoSelector from './BookingMotoSelector'
import BookingMapPicker from './BookingMapPicker'
import BookingPriceCalc from './BookingPriceCalc'
import BookingDeliverySection from './BookingDeliverySection'
import { isoDate, toDate, fmtDate, fmtCZK, fmtTimeHM, countDays, calcDayBreakdown } from './bookingModifyHelpers'
import { findFeeExtra, feeAmount } from './DetailTabSections'

export default function BookingModifyModal({ booking, onClose, onSaved }) {
  const origStart = toDate(booking.start_date)
  const origEnd = toDate(booking.end_date)
  const [startDate, setStartDate] = useState(origStart)
  const [endDate, setEndDate] = useState(origEnd)
  const [calStep, setCalStep] = useState(0)
  const [calMonth, setCalMonth] = useState(() => ({ m: origStart.getMonth(), y: origStart.getFullYear() }))
  // Časy vyzvednutí/vrácení (HH:MM) — DB může mít i vteřiny ('11:00:00' z webu),
  // proto normalizace přes fmtTimeHM i pro detekci změny.
  const origPickupTime = fmtTimeHM(booking.pickup_time, '')
  const origReturnTime = fmtTimeHM(booking.return_time, '')
  const [pickupTime, setPickupTime] = useState(origPickupTime)
  const [returnTime, setReturnTime] = useState(origReturnTime)

  const [changingMoto, setChangingMoto] = useState(false)
  const [allMotos, setAllMotos] = useState([])
  const [motoPrices, setMotoPrices] = useState({})
  const [selectedMotoId, setSelectedMotoId] = useState(booking.moto_id)
  const [overlappingBookings, setOverlappingBookings] = useState([])
  const [branches, setBranches] = useState([])
  const [branchFilter, setBranchFilter] = useState('')

  // Přistavení/svoz se předvyplňuje podle SKUTEČNÉHO stavu rezervace. DB hodnoty
  // metod nejsou jednotné ('delivery' vs. 'rental'/'store'/'branch'/NULL u pobočky)
  // a poplatek může být místo bookings.delivery_fee v booking_extras (řádek
  // „Přistavení"/„Svoz") — ten se dočte async v load() níže.
  const rawDeliveryFee = Number(booking.delivery_fee) || 0
  const initPickupDelivery = booking.pickup_method === 'delivery' || (!!booking.pickup_address && rawDeliveryFee > 0)
  const initReturnDelivery = booking.return_method === 'delivery' || (!!booking.return_address && rawDeliveryFee > 0)
  const initOrigFee = (initPickupDelivery || initReturnDelivery) ? rawDeliveryFee : 0
  const [pickupMethod, setPickupMethod] = useState(initPickupDelivery ? 'delivery' : 'on_branch')
  const [pickupAddress, setPickupAddress] = useState(booking.pickup_address || '')
  const [returnMethod, setReturnMethod] = useState(initReturnDelivery ? 'delivery' : 'on_branch')
  const [returnAddress, setReturnAddress] = useState(booking.return_address || '')
  const [deliveryFee, setDeliveryFee] = useState(initOrigFee)
  // Normalizovaný původní stav doručení — proti němu se detekuje změna
  // a počítá cenový rozdíl (změna přistavného).
  const [origDelivery, setOrigDelivery] = useState({ pickup: initPickupDelivery ? 'delivery' : 'on_branch', ret: initReturnDelivery ? 'delivery' : 'on_branch', fee: initOrigFee })
  const [showMapPicker, setShowMapPicker] = useState(null)

  const [chargeCustomer, setChargeCustomer] = useState(true)
  const [notes, setNotes] = useState(booking.notes || '')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [loadingMotos, setLoadingMotos] = useState(false)

  useEffect(() => {
    async function load() {
      setLoadingMotos(true)
      const [motosRes, pricesRes, branchesRes, extrasRes] = await Promise.all([
        supabase.from('motorcycles').select('id, model, spz, category, image_url, status, branch_id, license_required, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun').order('model'),
        supabase.from('moto_day_prices').select('*'),
        supabase.from('branches').select('id, name').order('name'),
        supabase.from('booking_extras').select('*, extras_catalog(name, price_per_day)').eq('booking_id', booking.id),
      ])
      setAllMotos(motosRes.data || [])
      const pm = {}; (pricesRes.data || []).forEach(p => { pm[p.moto_id] = p })
      setMotoPrices(pm)
      setBranches(branchesRes.data || [])
      setLoadingMotos(false)
      // Přistavení/svoz účtované přes booking_extras (bookings.delivery_fee = 0):
      // dopředvyplní metody + poplatek podle reálného stavu rezervace.
      if (rawDeliveryFee === 0) {
        const extras = extrasRes.data || []
        const pFee = feeAmount(findFeeExtra(extras, 'pickup'))
        const rFee = feeAmount(findFeeExtra(extras, 'return'))
        if (pFee > 0 || rFee > 0) {
          const pd = initPickupDelivery || pFee > 0
          const rd = initReturnDelivery || rFee > 0
          setPickupMethod(pd ? 'delivery' : 'on_branch')
          setReturnMethod(rd ? 'delivery' : 'on_branch')
          setDeliveryFee(pFee + rFee)
          setOrigDelivery({ pickup: pd ? 'delivery' : 'on_branch', ret: rd ? 'delivery' : 'on_branch', fee: pFee + rFee })
        }
      }
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
  const origDeliveryFee = origDelivery.fee
  const newDeliveryFee = (pickupMethod === 'delivery' || returnMethod === 'delivery') ? deliveryFee : 0
  // Doplatek/vratka = ROZDÍL dle ceníku (nový termín/motorka − původní) + změna
  // přistavného. NE „nová cena − zaplaceno": zaplacená částka obsahuje i výbavu,
  // slevy apod., které se úpravou termínu nemění — ty v ceně zůstávají (extrasCarry).
  const priceDiff = (newCalcPrice - origCalcPrice) + (newDeliveryFee - origDeliveryFee)
  const extrasCarry = origPaidPrice - origCalcPrice - origDeliveryFee
  const newTotalPrice = origPaidPrice + priceDiff

  // Doplatkové flow (2026-07-27): je-li PŮVODNÍ rezervace zaplacená a úprava vyžaduje
  // doplatek, neposílá se hned booking_modified mail — zákazník dostane výzvu k platbě
  // (šablona booking_qr_payment_surcharge) a potvrzení úpravy odejde až po potvrzení
  // doplatku v detailu rezervace („Potvrdit doplatek"). Dlužný doplatek je kumulativní
  // (další úprava před zaplacením předchozího doplatku ho navyšuje/snižuje).
  const origPaid = ['paid', 'partial_refund'].includes(booking.payment_status)
  const pendingSurcharge = Number(booking.mod_surcharge_due) || 0

  const selectedMoto = allMotos.find(m => m.id === selectedMotoId)
  const motoChanged = selectedMotoId !== booking.moto_id
  const datesChanged = isoDate(startDate) !== isoDate(origStart) || isoDate(endDate) !== isoDate(origEnd)
  const deliveryChanged = pickupMethod !== origDelivery.pickup || returnMethod !== origDelivery.ret || pickupAddress !== (booking.pickup_address || '') || returnAddress !== (booking.return_address || '') || newDeliveryFee !== origDelivery.fee
  const timesChanged = pickupTime !== origPickupTime || returnTime !== origReturnTime
  const hasChanges = datesChanged || motoChanged || deliveryChanged || timesChanged || notes !== (booking.notes || '')

  const days = countDays(startDate, endDate)
  const origDays = countDays(origStart, origEnd)

  // Vyzvednuti u bezici rezervace uz je v minulosti (v kalendari nejde zakliknout) —
  // editace pak zacina rovnou vyberem data vraceni, OD zustava.
  const todayMid = new Date(); todayMid.setHours(0, 0, 0, 0)
  const startInPast = origStart < todayMid

  // Rozsah OD-DO se pri klikani nikdy nerozbije (DO se nenuluje) — termin jde
  // jednim klikem prodlouzit i zkratit a "Dni" nikdy neukaze zaporne cislo.
  // U bezici rezervace je OD zamcene (vyzvednuti uz probehlo) — kazdy klik
  // nastavuje jen vraceni, prodlouzeni se pocita od PUVODNIHO vyzvednuti.
  function handleCalClick(date) {
    if (calStep === 1 && !startInPast) {
      setStartDate(date)
      if (!endDate || date > endDate) setEndDate(date)
      setCalStep(2)
    } else {
      if (!startInPast && startDate && date < startDate) setStartDate(date)
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
        notes: notes || null,
      }
      // Doručovací pole se přepisují JEN při reálné změně doručení — DB drží
      // historické hodnoty metod ('rental'/'store'/…) a poplatek může být v
      // booking_extras; bezdůvodný přepis by trigger booking_modified vyhodnotil
      // jako změnu místa a poslal ji zákazníkovi v mailu.
      if (deliveryChanged) {
        saveData.pickup_method = pickupMethod; saveData.pickup_address = pickupAddress || null
        saveData.return_method = returnMethod; saveData.return_address = returnAddress || null
        saveData.delivery_fee = newDeliveryFee
      }
      if (timesChanged) {
        saveData.pickup_time = pickupTime || null
        saveData.return_time = returnTime || null
      }
      if (motoChanged) saveData.moto_id = selectedMotoId
      // Doplatek u zaplacené rezervace: dlužná částka = předchozí nezaplacený doplatek
      // + rozdíl této úpravy. mod_surcharge_due jde ve STEJNÉM UPDATE jako úprava —
      // DB trigger díky tomu booking_modified mail odloží (payload uschová) místo
      // okamžitého odeslání. Vyjde-li dluh <= 0, doplatek se ruší a zbytek se vrací.
      let surchargeDue = 0
      let refundAmount = chargeCustomer && priceDiff < 0 ? Math.abs(priceDiff) : 0
      if (chargeCustomer && origPaid) {
        const newDue = pendingSurcharge + priceDiff
        if (newDue > 0) {
          surchargeDue = newDue
          refundAmount = 0
          saveData.mod_surcharge_due = newDue
          saveData.mod_surcharge_requested_at = new Date().toISOString()
          saveData.mod_surcharge_paid_at = null
        } else {
          // Nezaplacený doplatek se touto úpravou vynuloval — vrací se jen to,
          // co zákazník skutečně zaplatil (částka pod původní zaplacenou cenu).
          // Odložený mail payload se uklidí; trigger pošle booking_modified hned.
          saveData.mod_surcharge_due = null
          if (pendingSurcharge > 0) saveData.mod_email_payload = null
          refundAmount = Math.abs(newDue)
        }
      }
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
      let { error: saveErr } = await supabase.from('bookings').update(saveData).eq('id', booking.id)
      if (saveErr && 'mod_surcharge_due' in saveData && /mod_surcharge|mod_email_payload/.test(saveErr.message || '')) {
        // Fallback: DB migrace doplatkových sloupců ještě neproběhla → ulož úpravu
        // postaru (mail odejde hned triggerem, bez QR výzvy k doplatku).
        delete saveData.mod_surcharge_due
        delete saveData.mod_surcharge_requested_at
        delete saveData.mod_surcharge_paid_at
        delete saveData.mod_email_payload
        surchargeDue = 0
        ;({ error: saveErr } = await supabase.from('bookings').update(saveData).eq('id', booking.id))
      }
      if (saveErr) throw saveErr
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({
          admin_id: user?.id, action: 'booking_modified',
          details: { booking_id: booking.id, dates_changed: datesChanged, times_changed: timesChanged, moto_changed: motoChanged, delivery_changed: deliveryChanged, price_diff: priceDiff, charged: chargeCustomer, new_total: chargeCustomer ? newTotalPrice : origPaidPrice }
        })
      } catch {}
      // Při zkrácení rezervace (záporný rozdíl) + placeno kartou → automatický Stripe refund + dobropis.
      // Proběhne jen pokud admin označil "naúčtovat zákazníkovi" (jinak je zkrácení bez vratky).
      // refundAmount je už očištěný o případný nezaplacený doplatek (nevrací se, co nepřišlo).
      if (chargeCustomer && refundAmount > 0 && booking.stripe_payment_intent_id) {
        try {
          await supabase.functions.invoke('process-refund', {
            body: { booking_id: booking.id, amount: refundAmount, reason: 'shortening' },
          })
        } catch (refundErr) {
          console.warn('[BookingModify] refund failed:', refundErr?.message)
        }
      }

      // Doplatek → výzva k platbě zákazníkovi (QR + účet + VS na částku doplatku,
      // šablona booking_qr_payment_surcharge) + upozornění na info@. Částku si edge fn
      // čte z bookings.mod_surcharge_due (uložené výše), VS přidělí RPC.
      if (surchargeDue > 0) {
        try {
          const { data: qr, error: qrErr } = await supabase.functions.invoke('qr-payment', {
            body: { booking_id: booking.id, surcharge: true, locale: booking.language || 'cs' },
          })
          if (qrErr || qr?.success === false) throw new Error(qr?.error || qrErr?.message || 'qr-payment failed')
        } catch (qrE) {
          console.warn('[BookingModify] surcharge payment mail failed:', qrE?.message)
          window.alert('Úprava je uložená, ale odeslání platebních údajů k doplatku selhalo (' + (qrE?.message || 'chyba') + '). Zkontrolujte doručení / pošlete údaje zákazníkovi ručně.')
        }
      }

      // booking_modified email se posílá automaticky DB triggerem trg_booking_modified_email
      // (po UPDATE bookings) — netřeba volat send-booking-email z Velinu.
      // Trigger detekuje změnu polí (moto, datumy, cena, místo, čas) a pošle mail s diff
      // tabulkou + autoGenerateAttachments fetchne již existující DP úpravy / dobropis.
      // VÝJIMKA: při nezaplaceném doplatku (mod_surcharge_due > 0) trigger mail ODLOŽÍ —
      // odejde až po „Potvrdit doplatek" v detailu rezervace (confirm_booking_surcharge).
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
              <button onClick={() => setCalStep(startInPast ? 2 : 1)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}>Zmenit termin</button>
            ) : (
              <div className="flex items-center gap-2">
                {startInPast ? (
                  <span className="text-sm font-bold" style={{ color: '#f59e0b' }}>Rezervace bezi — kliknete na nove datum vraceni</span>
                ) : (<>
                  <span className="text-sm font-bold" style={{ color: '#f59e0b' }}>{calStep === 1 ? 'Kliknete na datum vyzvednuti' : 'Kliknete na datum vraceni'}</span>
                  <button onClick={() => setCalStep(1)} className="text-xs font-bold cursor-pointer" title="Zmenit datum vyzvednuti"
                    style={{ padding: '3px 10px', borderRadius: 999, background: calStep === 1 ? '#74FB71' : '#f1faf7', border: calStep === 1 ? '2px solid #3dba3a' : '1px solid #d4e8e0', color: '#0f1a14' }}>OD</button>
                  <button onClick={() => setCalStep(2)} className="text-xs font-bold cursor-pointer" title="Zmenit datum vraceni"
                    style={{ padding: '3px 10px', borderRadius: 999, background: calStep === 2 ? '#74FB71' : '#f1faf7', border: calStep === 2 ? '2px solid #3dba3a' : '1px solid #d4e8e0', color: '#0f1a14' }}>DO</button>
                </>)}
              </div>
            )}
          </div>
          {calStep > 0 && <BookingCalendar calMonth={calMonth} setCalMonth={setCalMonth} calStep={calStep} startDate={startDate} endDate={endDate} origStart={origStart} origEnd={origEnd} onCalClick={handleCalClick} />}
          <div className="p-3 rounded-lg mt-2" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <div className="grid grid-cols-4 gap-4">
              <div>
                <div className="text-xs font-bold uppercase" style={{ color: '#1a2e22' }}>Od</div>
                <div className="text-sm font-extrabold" style={{ color: datesChanged ? '#2563eb' : '#0f1a14' }}>{fmtDate(startDate)}</div>
                {datesChanged && <div className="text-xs" style={{ color: '#9ca3af' }}>bylo: {fmtDate(origStart)}</div>}
                <input type="time" value={pickupTime} onChange={e => setPickupTime(e.target.value)} title="Cas vyzvednuti"
                  className="mt-1 text-xs font-bold rounded outline-none cursor-pointer" style={{ padding: '2px 6px', background: '#fff', border: `1px solid ${pickupTime !== origPickupTime ? '#2563eb' : '#d4e8e0'}`, color: pickupTime !== origPickupTime ? '#2563eb' : '#1a2e22' }} />
                {pickupTime !== origPickupTime && <div className="text-xs" style={{ color: '#9ca3af' }}>bylo: {origPickupTime || '\u2014'}</div>}
              </div>
              <div>
                <div className="text-xs font-bold uppercase" style={{ color: '#1a2e22' }}>Do</div>
                <div className="text-sm font-extrabold" style={{ color: datesChanged ? '#2563eb' : '#0f1a14' }}>{endDate ? fmtDate(endDate) : '\u2014'}</div>
                {datesChanged && <div className="text-xs" style={{ color: '#9ca3af' }}>bylo: {fmtDate(origEnd)}</div>}
                <input type="time" value={returnTime} onChange={e => setReturnTime(e.target.value)} title="Cas vraceni"
                  className="mt-1 text-xs font-bold rounded outline-none cursor-pointer" style={{ padding: '2px 6px', background: '#fff', border: `1px solid ${returnTime !== origReturnTime ? '#2563eb' : '#d4e8e0'}`, color: returnTime !== origReturnTime ? '#2563eb' : '#1a2e22' }} />
                {returnTime !== origReturnTime && <div className="text-xs" style={{ color: '#9ca3af' }}>bylo: {origReturnTime || '\u2014'}</div>}
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
        <BookingMotoSelector changingMoto={changingMoto} setChangingMoto={setChangingMoto} branchFilter={branchFilter} setBranchFilter={setBranchFilter} branches={branches} availableMotos={availableMotos} unavailableMotos={unavailableMotos} loadingMotos={loadingMotos} selectedMotoId={selectedMotoId} setSelectedMotoId={setSelectedMotoId} booking={booking} motoChanged={motoChanged} selectedMoto={selectedMoto} calcMotoPrice={calcMotoPrice} newDeliveryFee={newDeliveryFee} origCalcPrice={origCalcPrice} origDeliveryFee={origDeliveryFee} fmtCZK={fmtCZK} />

        {/* PICKUP & RETURN */}
        <BookingDeliverySection pickupMethod={pickupMethod} setPickupMethod={setPickupMethod} pickupAddress={pickupAddress} setPickupAddress={setPickupAddress} returnMethod={returnMethod} setReturnMethod={setReturnMethod} returnAddress={returnAddress} setReturnAddress={setReturnAddress} deliveryFee={deliveryFee} setDeliveryFee={setDeliveryFee} setShowMapPicker={setShowMapPicker} />

        {/* PRICE CALCULATION */}
        <BookingPriceCalc newBreakdown={newBreakdown} selectedMoto={selectedMoto} booking={booking} origCalcPrice={origCalcPrice} origPaidPrice={origPaidPrice} origDays={origDays} newCalcPrice={newCalcPrice} newDeliveryFee={newDeliveryFee} extrasCarry={extrasCarry} newTotalPrice={newTotalPrice} priceDiff={priceDiff} days={days} chargeCustomer={chargeCustomer} setChargeCustomer={setChargeCustomer} />

        {/* NOTES */}
        <div className="mb-5">
          <label className="block text-xs font-bold uppercase mb-1" style={{ color: '#1a2e22' }}>Poznamky</label>
          <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} className="w-full text-sm rounded-btn outline-none" style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }} placeholder="Interni poznamky k uprave..." />
        </div>

        {/* ACTIONS */}
        <div className="flex items-center justify-between pt-3" style={{ borderTop: '1px solid #e5e7eb' }}>
          <div className="text-xs" style={{ color: '#9ca3af' }}>
            {hasChanges ? (
              <span style={{ color: '#2563eb', fontWeight: 700 }}>Zmeny: {[datesChanged && 'termin', timesChanged && 'cas', motoChanged && 'motorka', deliveryChanged && 'doruceni', notes !== (booking.notes || '') && 'poznamky'].filter(Boolean).join(', ')}</span>
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
