import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Button from '../ui/Button'
import Modal from '../ui/Modal'

const DAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTHS = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const DAY_KEYS = { 0: 'price_sun', 1: 'price_mon', 2: 'price_tue', 3: 'price_wed', 4: 'price_thu', 5: 'price_fri', 6: 'price_sat' }
const PRICES_DAY_MAP = { 0: 'price_sunday', 1: 'price_monday', 2: 'price_tuesday', 3: 'price_wednesday', 4: 'price_thursday', 5: 'price_friday', 6: 'price_saturday' }

function isoDate(d) {
  if (!d) return ''
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}
function fmtDate(d) { return d ? d.toLocaleDateString('cs-CZ') : '—' }
function sameDay(a, b) { return a && b && isoDate(a) === isoDate(b) }

function NewBookingFromCalendar({ motoId, defaultDate, onClose, onSaved }) {
  const [step, setStep] = useState(1)
  const [err, setErr] = useState(null)
  const [saving, setSaving] = useState(false)

  // Moto info
  const [moto, setMoto] = useState(null)
  const [motoPrices, setMotoPrices] = useState(null)

  // Step 1 — date picker
  const [calMonth, setCalMonth] = useState(() => {
    if (defaultDate) { const d = new Date(defaultDate); return { m: d.getMonth(), y: d.getFullYear() } }
    const n = new Date(); return { m: n.getMonth(), y: n.getFullYear() }
  })
  const [startDate, setStartDate] = useState(() => defaultDate ? new Date(defaultDate + 'T00:00:00') : null)
  const [endDate, setEndDate] = useState(null)
  const [calStep, setCalStep] = useState(() => defaultDate ? 2 : 1)
  const [existingBookings, setExistingBookings] = useState([])

  // Step 2 — customer
  const [customers, setCustomers] = useState([])
  const [customerSearch, setCustomerSearch] = useState('')
  const [selectedCustomer, setSelectedCustomer] = useState(null)
  const [pickupTime, setPickupTime] = useState('09:00')
  const [notes, setNotes] = useState('')
  const [noPayment, setNoPayment] = useState(false)

  useEffect(() => {
    supabase.from('motorcycles').select('id, model, spz, category, license_required, image_url, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun')
      .eq('id', motoId).single().then(({ data }) => setMoto(data))
    supabase.from('moto_day_prices').select('*').eq('moto_id', motoId).single()
      .then(({ data }) => setMotoPrices(data))
    supabase.from('profiles').select('id, full_name, email, phone').order('full_name')
      .then(({ data }) => setCustomers(data || []))
  }, [motoId])

  // Load existing bookings for calendar highlighting
  useEffect(() => {
    const { m, y } = calMonth
    const start = new Date(y, m, 1).toISOString().split('T')[0]
    const end = new Date(y, m + 1, 0).toISOString().split('T')[0]
    supabase.from('bookings').select('id, start_date, end_date, status')
      .eq('moto_id', motoId).in('status', ['pending', 'active', 'reserved', 'completed'])
      .gte('end_date', start).lte('start_date', end)
      .then(({ data }) => setExistingBookings(data || []))
  }, [motoId, calMonth])

  function calcPrice() {
    if (!startDate || !endDate || !moto) return null
    let total = 0; const cur = new Date(startDate); const edt = new Date(endDate)
    while (cur <= edt) {
      const dow = cur.getDay()
      const price = (motoPrices && Number(motoPrices[PRICES_DAY_MAP[dow]])) || Number(moto[DAY_KEYS[dow]]) || 0
      total += price
      cur.setDate(cur.getDate() + 1)
    }
    return total
  }

  const days = startDate && endDate ? Math.max(1, Math.round((endDate - startDate) / 86400000) + 1) : 0
  const totalPrice = calcPrice()

  function handleCalClick(date) {
    // Check if this date is already booked
    const dateStr = isoDate(date)
    const isBooked = existingBookings.some(b => dateStr >= b.start_date.split('T')[0] && dateStr <= b.end_date.split('T')[0] && ['active', 'reserved'].includes(b.status))
    if (isBooked) return

    if (calStep === 1) { setStartDate(date); setEndDate(null); setCalStep(2); }
    else if (date < startDate) { setStartDate(date); setEndDate(null); setCalStep(2); }
    else { setEndDate(date); setCalStep(1); }
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
          <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{MONTHS[m]} {y}</span>
          <button onClick={() => setCalMonth(p => p.m === 11 ? { m: 0, y: p.y + 1 } : { m: p.m + 1, y: p.y })} className="cursor-pointer text-sm font-bold" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 10px', color: '#1a2e22' }}>→</button>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 3 }}>
          {DAYS.map(n => <div key={n} className="text-sm font-bold text-center" style={{ color: '#1a2e22', padding: 4 }}>{n}</div>)}
          {cells.map((date, i) => {
            if (!date) return <div key={`e${i}`} />
            const past = date < today
            const dateStr = isoDate(date)
            const isBooked = existingBookings.some(b => dateStr >= b.start_date.split('T')[0] && dateStr <= b.end_date.split('T')[0] && ['active', 'reserved'].includes(b.status))
            const isStart = sameDay(date, startDate); const isEnd = sameDay(date, endDate)
            const isInRange = startDate && endDate && date >= startDate && date <= endDate
            const isSelected = isStart || isEnd

            let bg = '#fff', color = '#0f1a14', border = '1px solid #e5e7eb', fontWeight = 500
            if (past) { color = '#d1d5db'; border = '1px solid #f3f4f6' }
            else if (isBooked) { bg = '#15803d'; color = '#fff'; border = '1px solid #15803d'; fontWeight = 700 }
            else if (isSelected) { bg = '#74FB71'; color = '#0f1a14'; border = '1px solid #3dba3a'; fontWeight = 800 }
            else if (isInRange) { bg = '#d1fae5'; border = '1px solid #a7f3d0' }

            return (
              <button key={i} disabled={past || isBooked} onClick={() => handleCalClick(date)}
                className="cursor-pointer text-sm text-center"
                style={{ background: bg, color, border, borderRadius: 6, padding: '7px 0', fontWeight, opacity: past ? 0.4 : 1 }}>
                {date.getDate()}
              </button>
            )
          })}
        </div>
      </div>
    )
  }

  const filteredCustomers = customerSearch.length > 1
    ? customers.filter(c =>
      (c.full_name || '').toLowerCase().includes(customerSearch.toLowerCase()) ||
      (c.email || '').toLowerCase().includes(customerSearch.toLowerCase()) ||
      (c.phone || '').includes(customerSearch)
    ).slice(0, 8)
    : []

  async function handleCreate() {
    setErr(null)
    if (!selectedCustomer || !startDate || !endDate) { setErr('Vyplňte všechna pole'); return }
    setSaving(true)
    try {
      if (moto?.license_required !== 'N') {
        const { data: overlapping } = await supabase.from('bookings')
          .select('id, start_date, end_date, motorcycles(model, license_required)')
          .eq('user_id', selectedCustomer.id).in('status', ['pending', 'reserved', 'active'])
          .lte('start_date', isoDate(endDate)).gte('end_date', isoDate(startDate))
        const nonKids = (overlapping || []).filter(b => b.motorcycles?.license_required !== 'N')
        if (nonKids.length > 0) throw new Error(`Zákazník má překrývající se rezervaci: ${nonKids[0].motorcycles?.model || ''} (${nonKids[0].start_date} – ${nonKids[0].end_date})`)
      }
      const bookingData = {
        user_id: selectedCustomer.id, moto_id: motoId,
        start_date: isoDate(startDate), end_date: isoDate(endDate),
        pickup_time: pickupTime,
        total_price: totalPrice || 0,
        status: 'reserved',
        payment_status: noPayment ? 'paid' : 'pending',
        notes: notes || null,
      }
      const result = await debugAction('bookings.create', 'BookingsCalendar', () =>
        supabase.from('bookings').insert(bookingData).select().single(), bookingData)
      if (result?.error) throw result.error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'booking_created_admin',
        details: { booking_id: result.data?.id, moto: moto?.model, customer: selectedCustomer.full_name, no_payment: noPayment },
      })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  const STEP_LABELS = ['Termín', 'Zákazník & shrnutí']

  return (
    <Modal open title="Nová rezervace" onClose={onClose} wide>
      {/* Stepper */}
      <div className="flex items-center gap-2 mb-5">
        {STEP_LABELS.map((label, i) => (
          <div key={i} className="flex items-center gap-2">
            <div className="flex items-center gap-1 cursor-pointer" onClick={() => { if (i + 1 < step) setStep(i + 1) }}>
              <div className="text-sm font-extrabold rounded-full flex items-center justify-center"
                style={{ width: 22, height: 22, background: step > i + 1 ? '#74FB71' : step === i + 1 ? '#0f1a14' : '#e5e7eb', color: step === i + 1 ? '#fff' : step > i + 1 ? '#0f1a14' : '#9ca3af' }}>
                {step > i + 1 ? '✓' : i + 1}
              </div>
              <span className="text-sm font-bold uppercase tracking-wide" style={{ color: step === i + 1 ? '#0f1a14' : '#1a2e22' }}>{label}</span>
            </div>
            {i < STEP_LABELS.length - 1 && <div style={{ width: 24, height: 1, background: '#d4e8e0' }} />}
          </div>
        ))}
      </div>

      {/* Motorka info strip */}
      {moto && (
        <div className="flex items-center gap-3 p-3 rounded-lg mb-4" style={{ background: '#eafbe9', border: '1px solid #74FB71' }}>
          {moto.image_url
            ? <img src={moto.image_url} alt={moto.model} style={{ width: 56, height: 38, objectFit: 'cover', borderRadius: 8 }} />
            : <div style={{ width: 56, height: 38, borderRadius: 8, background: '#f1faf7', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18 }}>🏍</div>
          }
          <div>
            <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{moto.model}</div>
            <div className="text-sm" style={{ color: '#1a2e22' }}>{moto.spz || '—'} · {moto.category || '—'} · ŘP: {moto.license_required || '—'}</div>
          </div>
        </div>
      )}

      {err && <div className="p-3 rounded-lg mb-4" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{err}</div>}

      {/* Step 1: Date selection */}
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
                {days > 0 && totalPrice != null && <div><span className="text-sm font-bold uppercase" style={{ color: '#1a2e22' }}>Cena</span><div className="text-sm font-bold" style={{ color: '#1a8a18' }}>{totalPrice.toLocaleString('cs-CZ')} Kč</div></div>}
              </div>
            </div>
          )}
          <div className="flex justify-end mt-4"><Button green onClick={() => { setErr(null); setStep(2) }} disabled={!startDate || !endDate}>Pokračovat →</Button></div>
        </div>
      )}

      {/* Step 2: Customer & Summary */}
      {step === 2 && (
        <div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Zákazník</label>
              {selectedCustomer ? (
                <div className="p-3 rounded-lg" style={{ background: '#eafbe9', border: '1px solid #74FB71' }}>
                  <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{selectedCustomer.full_name}</div>
                  <div className="text-sm" style={{ color: '#1a2e22' }}>{selectedCustomer.email}</div>
                  {selectedCustomer.phone && <div className="text-sm" style={{ color: '#1a2e22' }}>{selectedCustomer.phone}</div>}
                  <button onClick={() => { setSelectedCustomer(null); setCustomerSearch('') }}
                    className="text-sm font-bold cursor-pointer mt-1" style={{ color: '#dc2626', background: 'none', border: 'none' }}>Změnit</button>
                </div>
              ) : (
                <div>
                  <input type="text" value={customerSearch} onChange={e => setCustomerSearch(e.target.value)}
                    placeholder="Hledat jméno, email, telefon…"
                    className="w-full rounded-btn text-sm outline-none"
                    style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
                  {filteredCustomers.length > 0 && (
                    <div className="mt-1 rounded-lg" style={{ border: '1px solid #d4e8e0', maxHeight: 180, overflowY: 'auto' }}>
                      {filteredCustomers.map(c => (
                        <div key={c.id} className="p-2 cursor-pointer text-sm hover:bg-green-50"
                          style={{ borderBottom: '1px solid #f1faf7' }}
                          onClick={() => { setSelectedCustomer(c); setCustomerSearch('') }}>
                          <span className="font-bold">{c.full_name}</span>
                          <span className="ml-2" style={{ color: '#1a2e22' }}>{c.email}</span>
                        </div>
                      ))}
                    </div>
                  )}
                  {customerSearch.length > 1 && filteredCustomers.length === 0 && (
                    <p className="text-sm mt-1" style={{ color: '#1a2e22' }}>Žádný zákazník nenalezen</p>
                  )}
                </div>
              )}

              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1 mt-4" style={{ color: '#1a2e22' }}>Čas vyzvednutí</label>
              <input type="time" value={pickupTime} onChange={e => setPickupTime(e.target.value)}
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />

              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1 mt-4" style={{ color: '#1a2e22' }}>Poznámka</label>
              <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2}
                placeholder="Interní poznámka (volitelné)"
                className="w-full rounded-btn text-sm outline-none resize-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            </div>

            <div>
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Shrnutí rezervace</label>
              <div className="rounded-lg p-4" style={{ background: '#f8faf9', border: '1px solid #e5e7eb' }}>
                <div className="text-sm font-bold mb-2" style={{ color: '#0f1a14' }}>{moto?.model}</div>
                <div className="text-sm mb-3" style={{ color: '#1a2e22' }}>{moto?.spz || '—'}</div>
                <div className="flex justify-between text-sm mb-1"><span style={{ color: '#1a2e22' }}>Vyzvednutí</span><span className="font-bold" style={{ color: '#0f1a14' }}>{fmtDate(startDate)}</span></div>
                <div className="flex justify-between text-sm mb-1"><span style={{ color: '#1a2e22' }}>Vrácení</span><span className="font-bold" style={{ color: '#0f1a14' }}>{fmtDate(endDate)}</span></div>
                <div className="flex justify-between text-sm mb-3"><span style={{ color: '#1a2e22' }}>Počet dní</span><span className="font-bold" style={{ color: '#0f1a14' }}>{days}</span></div>
                <div style={{ borderTop: '1px solid #d4e8e0', paddingTop: 8 }}>
                  <div className="flex justify-between">
                    <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Celkem</span>
                    <span className="text-sm font-extrabold" style={{ color: '#1a8a18' }}>{totalPrice ? totalPrice.toLocaleString('cs-CZ') + ' Kč' : '—'}</span>
                  </div>
                </div>
              </div>

              <label className="flex items-center gap-2 mt-4 cursor-pointer p-3 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fbbf24' }}>
                <input type="checkbox" checked={noPayment} onChange={e => setNoPayment(e.target.checked)}
                  style={{ width: 16, height: 16, accentColor: '#1a8a18' }} />
                <div>
                  <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>Bez platby</div>
                  <div className="text-sm" style={{ color: '#1a2e22' }}>
                    {noPayment ? 'Rezervace bude označena jako zaplacená' : 'Zákazníkovi se v appce zobrazí výzva k platbě'}
                  </div>
                </div>
              </label>
            </div>
          </div>

          <div className="flex justify-between mt-5">
            <Button onClick={() => setStep(1)}>← Zpět</Button>
            <Button green onClick={handleCreate} disabled={saving || !selectedCustomer}>
              {saving ? 'Vytvářím…' : noPayment ? 'Vytvořit (zaplaceno)' : 'Vytvořit a odeslat k platbě'}
            </Button>
          </div>
        </div>
      )}
    </Modal>
  )
}

export default NewBookingFromCalendar
