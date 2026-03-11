import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

const STEP_LABELS = ['Termín', 'Motorka', 'Zákazník & shrnutí']
const DAY_NAMES = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTH_NAMES = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const DAY_KEYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']

function fmtDate(d) { return d ? d.toLocaleDateString('cs-CZ') : '—' }
function isoDate(d) { return d ? d.toISOString().slice(0, 10) : '' }
function sameDay(a, b) { return a && b && isoDate(a) === isoDate(b) }
function inRange(d, from, to) { return d >= from && d <= to }

export default function NewBookingModal({ onClose, onSaved }) {
  const [step, setStep] = useState(1)
  const [err, setErr] = useState(null)
  const [saving, setSaving] = useState(false)

  // Step 1: calendar
  const [calMonth, setCalMonth] = useState(() => { const n = new Date(); return { m: n.getMonth(), y: n.getFullYear() } })
  const [startDate, setStartDate] = useState(null)
  const [endDate, setEndDate] = useState(null)
  const [calStep, setCalStep] = useState(1) // 1 = picking start, 2 = picking end

  // Step 2: motorcycles
  const [motos, setMotos] = useState([])
  const [motoPrices, setMotoPrices] = useState({})
  const [bookings, setBookings] = useState([])
  const [selectedMoto, setSelectedMoto] = useState(null)
  const [loadingMotos, setLoadingMotos] = useState(false)

  // Step 3: customer
  const [customers, setCustomers] = useState([])
  const [customerSearch, setCustomerSearch] = useState('')
  const [selectedCustomer, setSelectedCustomer] = useState(null)
  const [noPayment, setNoPayment] = useState(false)
  const [pickupTime, setPickupTime] = useState('09:00')
  const [notes, setNotes] = useState('')

  // Load customers once
  useEffect(() => {
    supabase.from('profiles').select('id, full_name, email, phone').order('full_name')
      .then(({ data }) => setCustomers(data || []))
  }, [])

  // Load motorcycles + bookings when dates are set
  useEffect(() => {
    if (!startDate || !endDate) return
    setLoadingMotos(true)
    Promise.all([
      supabase.from('motorcycles').select('id, model, spz, category, image_url, status, branch_id, license_group').eq('status', 'active').order('model'),
      supabase.from('moto_day_prices').select('*'),
      supabase.from('bookings').select('id, moto_id, start_date, end_date, status')
        .in('status', ['reserved', 'active', 'pending'])
        .lte('start_date', isoDate(endDate))
        .gte('end_date', isoDate(startDate)),
    ]).then(([motosRes, pricesRes, bookingsRes]) => {
      setMotos(motosRes.data || [])
      const pm = {}
      ;(pricesRes.data || []).forEach(p => { pm[p.moto_id] = p })
      setMotoPrices(pm)
      setBookings(bookingsRes.data || [])
      setLoadingMotos(false)
    }).catch(() => setLoadingMotos(false))
  }, [startDate, endDate])

  // Occupied moto IDs for selected range
  const occupiedMotoIds = useMemo(() => {
    return new Set(bookings.map(b => b.moto_id))
  }, [bookings])

  // Calculate price for a moto
  function calcPrice(motoId) {
    const dp = motoPrices[motoId]
    if (!dp || !startDate || !endDate) return null
    let total = 0
    const cur = new Date(startDate)
    const end = new Date(endDate)
    while (cur <= end) {
      const key = `price_${DAY_KEYS[cur.getDay()]}`
      total += Number(dp[key]) || 0
      cur.setDate(cur.getDate() + 1)
    }
    return total
  }

  const days = startDate && endDate ? Math.max(1, Math.round((endDate - startDate) / 86400000) + 1) : 0
  const totalPrice = selectedMoto ? calcPrice(selectedMoto.id) : null

  // Available motos (not occupied)
  const availableMotos = motos.filter(m => !occupiedMotoIds.has(m.id))
  const unavailableMotos = motos.filter(m => occupiedMotoIds.has(m.id))

  // Calendar grid
  function renderCalendar() {
    const { m, y } = calMonth
    const firstDay = new Date(y, m, 1)
    let startIdx = firstDay.getDay() - 1
    if (startIdx < 0) startIdx = 6
    const daysInMonth = new Date(y, m + 1, 0).getDate()
    const today = new Date(); today.setHours(0, 0, 0, 0)
    const cells = []
    for (let i = 0; i < startIdx; i++) cells.push(null)
    for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(y, m, d))

    return (
      <div>
        <div className="flex items-center justify-between mb-3">
          <button onClick={() => setCalMonth(p => p.m === 0 ? { m: 11, y: p.y - 1 } : { m: p.m - 1, y: p.y })}
            className="cursor-pointer text-sm font-bold" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 10px', color: '#1a2e22' }}>←</button>
          <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{MONTH_NAMES[m]} {y}</span>
          <button onClick={() => setCalMonth(p => p.m === 11 ? { m: 0, y: p.y + 1 } : { m: p.m + 1, y: p.y })}
            className="cursor-pointer text-sm font-bold" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 10px', color: '#1a2e22' }}>→</button>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 3 }}>
          {DAY_NAMES.map(n => <div key={n} className="text-sm font-bold text-center" style={{ color: '#1a2e22', padding: 4 }}>{n}</div>)}
          {cells.map((date, i) => {
            if (!date) return <div key={`e${i}`} />
            const past = date < today
            const isStart = sameDay(date, startDate)
            const isEnd = sameDay(date, endDate)
            const isInRange = startDate && endDate && inRange(date, startDate, endDate)
            const isSelected = isStart || isEnd

            let bg = '#fff'
            let color = '#0f1a14'
            let border = '1px solid #e5e7eb'
            let fontWeight = 500

            if (past) { color = '#d1d5db'; border = '1px solid #f3f4f6' }
            else if (isSelected) { bg = '#74FB71'; color = '#0f1a14'; border = '1px solid #3dba3a'; fontWeight = 800 }
            else if (isInRange) { bg = '#d1fae5'; border = '1px solid #a7f3d0' }

            return (
              <button key={i} disabled={past}
                onClick={() => handleCalClick(date)}
                className="cursor-pointer text-sm text-center"
                style={{ background: bg, color, border, borderRadius: 6, padding: '7px 0', fontWeight, opacity: past ? 0.4 : 1 }}>
                {date.getDate()}
              </button>
            )
          })}
        </div>
        <div className="flex items-center gap-4 mt-3 text-sm" style={{ color: '#1a2e22' }}>
          <span><span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 3, background: '#74FB71', marginRight: 4, verticalAlign: 'middle' }} />Vybraný</span>
          <span><span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 3, background: '#d1fae5', marginRight: 4, verticalAlign: 'middle' }} />Rozsah</span>
        </div>
      </div>
    )
  }

  function handleCalClick(date) {
    if (calStep === 1) {
      setStartDate(date)
      setEndDate(null)
      setCalStep(2)
      setSelectedMoto(null)
    } else {
      if (date < startDate) {
        setStartDate(date)
        setEndDate(null)
        setCalStep(2)
      } else {
        setEndDate(date)
        setCalStep(1)
      }
      setSelectedMoto(null)
    }
  }

  // Filtered customers
  const filteredCustomers = customerSearch.length > 1
    ? customers.filter(c =>
      (c.full_name || '').toLowerCase().includes(customerSearch.toLowerCase()) ||
      (c.email || '').toLowerCase().includes(customerSearch.toLowerCase()) ||
      (c.phone || '').includes(customerSearch)
    ).slice(0, 8)
    : []

  async function handleCreate() {
    setErr(null)
    if (!selectedCustomer) { setErr('Vyberte zákazníka'); return }
    if (!selectedMoto) { setErr('Vyberte motorku'); return }
    if (!startDate || !endDate) { setErr('Vyberte termín'); return }

    setSaving(true)
    try {
      const bookingData = {
        user_id: selectedCustomer.id,
        moto_id: selectedMoto.id,
        start_date: isoDate(startDate),
        end_date: isoDate(endDate),
        pickup_time: pickupTime,
        total_price: totalPrice || 0,
        status: 'reserved',
        payment_status: noPayment ? 'paid' : 'pending',
        notes: notes || null,
      }

      const result = await debugAction('bookings.create', 'NewBookingModal', () =>
        supabase.from('bookings').insert(bookingData).select().single()
      , bookingData)
      if (result?.error) throw result.error

      // Audit log
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'booking_created_admin',
        details: { booking_id: result.data?.id, moto: selectedMoto.model, customer: selectedCustomer.full_name, no_payment: noPayment }
      })

      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová rezervace" onClose={onClose} wide>
      {/* Progress steps */}
      <div className="flex items-center gap-2 mb-5">
        {STEP_LABELS.map((label, i) => (
          <div key={i} className="flex items-center gap-2">
            <div className="flex items-center gap-1 cursor-pointer" onClick={() => {
              if (i + 1 < step) setStep(i + 1)
            }}>
              <div className="text-sm font-extrabold rounded-full flex items-center justify-center"
                style={{
                  width: 22, height: 22,
                  background: step > i + 1 ? '#74FB71' : step === i + 1 ? '#0f1a14' : '#e5e7eb',
                  color: step === i + 1 ? '#fff' : step > i + 1 ? '#0f1a14' : '#9ca3af',
                }}>
                {step > i + 1 ? '✓' : i + 1}
              </div>
              <span className="text-sm font-bold uppercase tracking-wide"
                style={{ color: step === i + 1 ? '#0f1a14' : '#1a2e22' }}>{label}</span>
            </div>
            {i < STEP_LABELS.length - 1 && <div style={{ width: 24, height: 1, background: '#d4e8e0' }} />}
          </div>
        ))}
      </div>

      {err && <div className="p-3 rounded-lg mb-4" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{err}</div>}

      {/* STEP 1: Calendar */}
      {step === 1 && (
        <div>
          <p className="text-sm mb-3" style={{ color: '#1a2e22' }}>
            {calStep === 1 ? 'Vyberte datum vyzvednutí:' : 'Vyberte datum vrácení:'}
          </p>
          {renderCalendar()}
          {startDate && (
            <div className="mt-4 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <div className="flex gap-6">
                <div>
                  <span className="text-sm font-bold uppercase" style={{ color: '#1a2e22' }}>Vyzvednutí</span>
                  <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{fmtDate(startDate)}</div>
                </div>
                <div>
                  <span className="text-sm font-bold uppercase" style={{ color: '#1a2e22' }}>Vrácení</span>
                  <div className="text-sm font-bold" style={{ color: endDate ? '#0f1a14' : '#d1d5db' }}>{endDate ? fmtDate(endDate) : 'Vyberte…'}</div>
                </div>
                {days > 0 && <div>
                  <span className="text-sm font-bold uppercase" style={{ color: '#1a2e22' }}>Dní</span>
                  <div className="text-sm font-bold" style={{ color: '#1a8a18' }}>{days}</div>
                </div>}
              </div>
            </div>
          )}
          <div className="flex justify-end mt-4">
            <Button green onClick={() => { setErr(null); setStep(2) }} disabled={!startDate || !endDate}>
              Pokračovat →
            </Button>
          </div>
        </div>
      )}

      {/* STEP 2: Motorcycle selection */}
      {step === 2 && (
        <div>
          <div className="flex items-center justify-between mb-3">
            <p className="text-sm font-bold" style={{ color: '#1a2e22' }}>
              Volné motorky pro {fmtDate(startDate)} – {fmtDate(endDate)} ({days} dní)
            </p>
            <span className="text-sm font-bold" style={{ color: '#1a8a18' }}>{availableMotos.length} volných</span>
          </div>

          {loadingMotos ? (
            <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
          ) : (
            <div style={{ maxHeight: 380, overflowY: 'auto' }}>
              {availableMotos.length === 0 && (
                <p className="text-sm py-6 text-center" style={{ color: '#1a2e22' }}>Žádná motorka není volná v tomto termínu</p>
              )}
              {availableMotos.map(m => {
                const price = calcPrice(m.id)
                const isSelected = selectedMoto?.id === m.id
                return (
                  <div key={m.id}
                    className="flex items-center gap-4 p-3 rounded-lg mb-2 cursor-pointer transition-shadow"
                    onClick={() => setSelectedMoto(m)}
                    style={{
                      background: isSelected ? '#eafbe9' : '#f8faf9',
                      border: isSelected ? '2px solid #74FB71' : '1px solid #e5e7eb',
                    }}>
                    {m.image_url ? (
                      <img src={m.image_url} alt={m.model} style={{ width: 72, height: 48, objectFit: 'cover', borderRadius: 8 }} />
                    ) : (
                      <div style={{ width: 72, height: 48, borderRadius: 8, background: '#f1faf7', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22 }}>🏍️</div>
                    )}
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{m.model}</div>
                      <div className="text-sm" style={{ color: '#1a2e22' }}>
                        {m.spz || '—'} · {m.category || '—'} · ŘP: {m.license_group || '—'}
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="text-sm font-extrabold" style={{ color: '#1a8a18' }}>
                        {price ? price.toLocaleString('cs-CZ') + ' Kč' : '—'}
                      </div>
                      <div className="text-sm" style={{ color: '#1a2e22' }}>{days} dní</div>
                    </div>
                    {isSelected && <div style={{ fontSize: 16, color: '#1a8a18' }}>✓</div>}
                  </div>
                )
              })}

              {unavailableMotos.length > 0 && (
                <>
                  <div className="text-sm font-bold uppercase tracking-wide mt-4 mb-2" style={{ color: '#dc2626' }}>
                    Obsazené v tomto termínu ({unavailableMotos.length})
                  </div>
                  {unavailableMotos.map(m => (
                    <div key={m.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#fafafa', border: '1px solid #f3f4f6', opacity: 0.5 }}>
                      <div style={{ width: 72, height: 48, borderRadius: 8, background: '#f3f4f6', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22 }}>🏍️</div>
                      <div className="flex-1">
                        <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>{m.model}</div>
                        <div className="text-sm" style={{ color: '#1a2e22' }}>{m.spz || '—'} · Obsazená</div>
                      </div>
                    </div>
                  ))}
                </>
              )}
            </div>
          )}

          <div className="flex justify-between mt-4">
            <Button onClick={() => setStep(1)}>← Zpět</Button>
            <Button green onClick={() => { setErr(null); setStep(3) }} disabled={!selectedMoto}>
              Pokračovat →
            </Button>
          </div>
        </div>
      )}

      {/* STEP 3: Customer + summary */}
      {step === 3 && (
        <div>
          <div className="grid grid-cols-2 gap-4">
            {/* Customer selection */}
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

              {/* Pickup time */}
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1 mt-4" style={{ color: '#1a2e22' }}>Čas vyzvednutí</label>
              <input type="time" value={pickupTime} onChange={e => setPickupTime(e.target.value)}
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />

              {/* Notes */}
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1 mt-4" style={{ color: '#1a2e22' }}>Poznámka</label>
              <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2}
                placeholder="Interní poznámka (volitelné)"
                className="w-full rounded-btn text-sm outline-none resize-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            </div>

            {/* Summary */}
            <div>
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Shrnutí rezervace</label>
              <div className="rounded-lg p-4" style={{ background: '#f8faf9', border: '1px solid #e5e7eb' }}>
                <div className="text-sm font-bold mb-2" style={{ color: '#0f1a14' }}>{selectedMoto?.model}</div>
                <div className="text-sm mb-3" style={{ color: '#1a2e22' }}>{selectedMoto?.spz || '—'}</div>

                <div className="flex justify-between text-sm mb-1">
                  <span style={{ color: '#1a2e22' }}>Vyzvednutí</span>
                  <span className="font-bold" style={{ color: '#0f1a14' }}>{fmtDate(startDate)}</span>
                </div>
                <div className="flex justify-between text-sm mb-1">
                  <span style={{ color: '#1a2e22' }}>Vrácení</span>
                  <span className="font-bold" style={{ color: '#0f1a14' }}>{fmtDate(endDate)}</span>
                </div>
                <div className="flex justify-between text-sm mb-3">
                  <span style={{ color: '#1a2e22' }}>Počet dní</span>
                  <span className="font-bold" style={{ color: '#0f1a14' }}>{days}</span>
                </div>

                <div style={{ borderTop: '1px solid #d4e8e0', paddingTop: 8 }}>
                  <div className="flex justify-between">
                    <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Celkem</span>
                    <span className="text-sm font-extrabold" style={{ color: '#1a8a18' }}>
                      {totalPrice ? totalPrice.toLocaleString('cs-CZ') + ' Kč' : '—'}
                    </span>
                  </div>
                </div>
              </div>

              {/* No payment checkbox */}
              <label className="flex items-center gap-2 mt-4 cursor-pointer p-3 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fbbf24' }}>
                <input type="checkbox" checked={noPayment} onChange={e => setNoPayment(e.target.checked)}
                  style={{ width: 16, height: 16, accentColor: '#1a8a18' }} />
                <div>
                  <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>Bez platby</div>
                  <div className="text-sm" style={{ color: '#1a2e22' }}>
                    {noPayment
                      ? 'Rezervace bude označena jako zaplacená'
                      : 'Zákazníkovi se v appce zobrazí výzva k platbě'}
                  </div>
                </div>
              </label>
            </div>
          </div>

          <div className="flex justify-between mt-5">
            <Button onClick={() => setStep(2)}>← Zpět</Button>
            <Button green onClick={handleCreate} disabled={saving || !selectedCustomer || !selectedMoto}>
              {saving ? 'Vytvářím…' : noPayment ? 'Vytvořit (zaplaceno)' : 'Vytvořit a odeslat k platbě'}
            </Button>
          </div>
        </div>
      )}
    </Modal>
  )
}
