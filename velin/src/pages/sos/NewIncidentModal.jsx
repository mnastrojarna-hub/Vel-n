import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'

// Spoluúčast (kauce) u zaviněné nehody / nezabezpečené krádeže — stejně jako
// placené SOS flow v aplikaci (které bylo z aplikace zrušeno a žije už jen tady).
const DEPOSIT = 30000

// Strom incidentů — zrcadlí výběr v aplikaci (sos_report_screen.dart).
//  flow: 'simple'            → jen založit incident
//        'decision_accident' → vina + akce (náhrada placená/zdarma | odtah)
//        'decision_theft'    → zabezpečení + náhrada (placená/zdarma)
//        'decision_breakdown'→ akce (náhrada zdarma | odtah)
const TREE = [
  {
    key: 'accident', icon: '💥', label: 'Nehoda',
    items: [
      { type: 'accident_minor', label: 'Drobná nehoda — pokračuje v jízdě', icon: '🎯', flow: 'simple' },
      { type: 'accident_major', label: 'Závažná nehoda — motorka nepojízdná', icon: '🚨', flow: 'decision_accident' },
      { type: 'theft', label: 'Krádež motorky', icon: '🔐', flow: 'decision_theft' },
    ],
  },
  {
    key: 'breakdown', icon: '🔧', label: 'Porucha',
    items: [
      { type: 'breakdown_minor', label: 'Drobná závada — pokračuje v jízdě', icon: '🔩', flow: 'simple' },
      { type: 'breakdown_major', label: 'Porucha — motorka nepojízdná', icon: '🚫', flow: 'decision_breakdown' },
      { type: 'defect_question', label: 'Nejbližší servis / faktura', icon: '🔧', flow: 'simple' },
    ],
  },
  {
    key: 'other', icon: '📍', label: 'Ostatní',
    items: [
      { type: 'location_share', label: 'Sdílení polohy', icon: '📍', flow: 'simple' },
    ],
  },
]

const czk = (n) => `${Number(n || 0).toLocaleString('cs-CZ')} Kč`

export default function NewIncidentModal({ onClose, onCreated }) {
  const [screen, setScreen] = useState('customer') // customer|type|decision|replacement|payment|result
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState('')

  // Zákazník + jeho aktivní rezervace (k té se váže výměna motorky)
  const [q, setQ] = useState('')
  const [results, setResults] = useState([])
  const [customer, setCustomer] = useState(null)
  const [activeBooking, setActiveBooking] = useState(null)

  // Typ incidentu
  const [category, setCategory] = useState(null)
  const [picked, setPicked] = useState(null) // { type, label, flow }

  // Rozhodnutí
  const [fault, setFault] = useState(null)     // nehoda: true=zákazník platí, false=cizí
  const [secured, setSecured] = useState(null) // krádež: true=zabezpečená, false=ne
  const [action, setAction] = useState(null)   // 'replacement' | 'end_ride'

  // Náhradní motorka
  const [motos, setMotos] = useState([])
  const [moto, setMoto] = useState(null)
  const [addr, setAddr] = useState('')
  const [city, setCity] = useState('')
  const [deliveryFee, setDeliveryFee] = useState('')

  // Platba
  const [payMethod, setPayMethod] = useState('stripe') // 'stripe' | 'manual'
  const [manualMethod, setManualMethod] = useState('bank_transfer')
  const [reference, setReference] = useState('')

  // Výsledek
  const [result, setResult] = useState(null) // { incidentId, replBookingId, checkoutUrl }

  // ── odvozené hodnoty ────────────────────────────────────────────────
  const isFree = picked?.flow === 'decision_breakdown'
    ? true
    : picked?.flow === 'decision_theft'
      ? secured === true
      : fault === false // accident: cizí zavinění = zdarma

  const remainingDays = (() => {
    if (!activeBooking?.end_date) return 3
    const today = new Date(); today.setHours(0, 0, 0, 0)
    const end = new Date(activeBooking.end_date)
    const d = Math.floor((end - today) / 86400000) + 1
    return d < 1 ? 1 : d
  })()
  const dailyPrice = Number(moto?.price_weekday) || 0
  const motoTotal = dailyPrice * remainingDays
  const depositVal = isFree ? 0 : DEPOSIT
  const feeVal = isFree ? 0 : (Number(deliveryFee) || 0)
  const total = isFree ? 0 : (motoTotal + feeVal + depositVal)

  // ── data ────────────────────────────────────────────────────────────
  async function searchCustomers(text) {
    setQ(text)
    if (text.trim().length < 2) { setResults([]); return }
    const like = `%${text.trim()}%`
    const { data } = await supabase.from('profiles')
      .select('id, full_name, phone, email')
      .or(`full_name.ilike.${like},phone.ilike.${like},email.ilike.${like}`)
      .limit(8)
    setResults(data || [])
  }

  async function chooseCustomer(c) {
    setCustomer(c); setResults([]); setQ(c.full_name || c.email || '')
    const { data } = await supabase.from('bookings')
      .select('id, moto_id, start_date, end_date, status, payment_status, motorcycles(model, spz, branch_id, branches(name))')
      .eq('user_id', c.id)
      .in('status', ['active', 'reserved'])
      .eq('payment_status', 'paid')
      .order('start_date', { ascending: false })
      .limit(1)
    setActiveBooking(data?.[0] || null)
  }

  async function loadMotos() {
    const { data } = await supabase.from('motorcycles')
      .select('id, model, spz, price_weekday, branch_id, branches(name), status')
      .eq('status', 'active')
    setMotos((data || []).filter(m => m.id !== activeBooking?.moto_id))
  }

  async function createIncident(extra = {}) {
    const description = picked.label
    const payload = {
      user_id: customer.id,
      type: picked.type,
      status: 'reported',
      title: picked.label,
      description,
      contact_phone: customer.phone || null,
      ...(activeBooking?.id ? { booking_id: activeBooking.id } : {}),
      ...(activeBooking?.moto_id ? { moto_id: activeBooking.moto_id } : {}),
      ...(fault != null ? { customer_fault: fault } : {}),
      ...(picked.type === 'theft' && secured != null ? { customer_fault: !secured } : {}),
      ...extra,
    }
    const { data, error } = await supabase.from('sos_incidents').insert(payload).select('id').single()
    if (error) throw error
    const incId = data.id
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('sos_timeline').insert({
      incident_id: incId,
      action: `Incident založen operátorem (Velín): ${picked.label}`,
      performed_by: user?.email || 'Operátor', admin_id: user?.id,
    })
    return incId
  }

  // ── finalizace větví ────────────────────────────────────────────────
  async function finalizeReportOnly() {
    setLoading(true); setErr('')
    try {
      const incId = await createIncident()
      setResult({ incidentId: incId }); setScreen('result'); onCreated?.()
    } catch (e) { setErr(e.message || String(e)) }
    setLoading(false)
  }

  async function finalizeEndRide() {
    setLoading(true); setErr('')
    try {
      const incId = await createIncident({
        customer_decision: 'end_ride',
        moto_rideable: false,
        tow_requested: true,
      })
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('sos_timeline').insert({
        incident_id: incId,
        action: `Zákazník ukončuje jízdu — žádá odtah (${fault ? 'zaviněná' : 'nezaviněná / porucha'})`,
        performed_by: user?.email || 'Operátor', admin_id: user?.id,
      })
      setResult({ incidentId: incId }); setScreen('result'); onCreated?.()
    } catch (e) { setErr(e.message || String(e)) }
    setLoading(false)
  }

  async function finalizeReplacement() {
    if (!moto) { setErr('Vyberte náhradní motorku.'); return }
    if (!activeBooking) { setErr('Zákazník nemá aktivní zaplacenou rezervaci — výměnu nelze provést.'); return }
    setLoading(true); setErr('')
    try {
      const incId = await createIncident({ customer_decision: 'replacement_moto' })

      const swapRes = await supabase.rpc('sos_swap_bookings', {
        p_incident_id: incId,
        p_replacement_moto_id: moto.id,
        p_replacement_model: moto.model,
        p_delivery_fee: feeVal,
        p_daily_price: isFree ? 0 : dailyPrice,
        p_is_free: isFree,
      })
      const sr = typeof swapRes.data === 'string' ? JSON.parse(swapRes.data) : swapRes.data
      if (swapRes.error || !sr?.success) {
        throw new Error('Výměna rezervace selhala: ' + (swapRes.error?.message || sr?.error || 'neznámá chyba'))
      }
      const replBookingId = sr.replacement_booking_id

      const rd = {
        replacement_moto_id: moto.id,
        replacement_model: moto.model,
        daily_price: isFree ? 0 : dailyPrice,
        delivery_fee: feeVal,
        delivery_address: addr || null,
        delivery_city: city || null,
        deposit: depositVal,
        payment_status: isFree ? 'free' : 'pending',
        payment_amount: total,
        customer_fault: !isFree,
        original_booking_id: sr.original_booking_id,
        replacement_booking_id: replBookingId,
        original_end_date: sr.original_end_date,
        remaining_days: sr.remaining_days,
        admin_initiated: true,
        customer_confirmed_at: new Date().toISOString(),
      }
      await supabase.from('sos_incidents').update({
        replacement_data: rd,
        replacement_moto_id: moto.id,
        replacement_status: isFree ? 'approved' : 'pending_payment',
        customer_decision: 'replacement_moto',
      }).eq('id', incId)

      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('sos_timeline').insert({
        incident_id: incId,
        action: `Operátor přiřadil náhradní motorku: ${moto.model} (${moto.spz}) — ${isFree ? 'zdarma' : czk(total)}`,
        performed_by: user?.email || 'Operátor', admin_id: user?.id,
      })

      if (isFree) {
        setResult({ incidentId: incId, replBookingId }); setScreen('result'); onCreated?.()
      } else {
        // Placená náhrada → krok platby (Stripe odkaz / ruční potvrzení)
        setResult({ incidentId: incId, replBookingId })
        setScreen('payment'); onCreated?.()
      }
    } catch (e) { setErr(e.message || String(e)) }
    setLoading(false)
  }

  async function payStripe() {
    setLoading(true); setErr('')
    try {
      const { data, error } = await supabase.functions.invoke('process-payment', {
        body: { action: 'create_sos_payment_link', booking_id: result.replBookingId, incident_id: result.incidentId, amount: total },
      })
      if (error) throw error
      const url = data?.checkout_url
      if (!url) throw new Error(data?.error || 'Odkaz se nepodařilo vytvořit.')

      const rd = await refreshReplacementData()
      await supabase.from('sos_incidents').update({
        replacement_data: { ...rd, payment_link: url },
      }).eq('id', result.incidentId)
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('sos_timeline').insert({
        incident_id: result.incidentId,
        action: `Vytvořen platební odkaz (Stripe) na ${czk(total)} — čeká na úhradu zákazníkem`,
        performed_by: user?.email || 'Operátor', admin_id: user?.id,
      })
      if (customer?.id) {
        await supabase.from('admin_messages').insert({
          user_id: customer.id,
          title: 'Platba za náhradní motorku',
          message: `Pro objednání náhradní motorky prosím uhraďte ${czk(total)} přes tento odkaz: ${url}`,
          type: 'sos_response',
        })
      }
      setResult(r => ({ ...r, checkoutUrl: url })); setScreen('result')
    } catch (e) { setErr(e.message || String(e)) }
    setLoading(false)
  }

  async function payManual() {
    setLoading(true); setErr('')
    try {
      await supabase.rpc('confirm_payment', { p_booking_id: result.replBookingId, p_method: manualMethod })
      await supabase.from('bookings').update({
        payment_method: manualMethod,
        payment_reference: reference || null,
      }).eq('id', result.replBookingId)

      const rd = await refreshReplacementData()
      await supabase.from('sos_incidents').update({
        replacement_data: { ...rd, payment_status: 'paid', paid_at: new Date().toISOString(), payment_method: manualMethod, payment_reference: reference || null },
        replacement_status: 'approved',
      }).eq('id', result.incidentId)
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('sos_timeline').insert({
        incident_id: result.incidentId,
        action: `Platba ${czk(total)} potvrzena ručně (${MANUAL_LABELS[manualMethod] || manualMethod})${reference ? ' · ' + reference : ''}`,
        performed_by: user?.email || 'Operátor', admin_id: user?.id,
      })
      setResult(r => ({ ...r, paid: true })); setScreen('result')
    } catch (e) { setErr(e.message || String(e)) }
    setLoading(false)
  }

  async function refreshReplacementData() {
    const { data } = await supabase.from('sos_incidents').select('replacement_data').eq('id', result.incidentId).single()
    return data?.replacement_data || {}
  }

  // ── render ──────────────────────────────────────────────────────────
  return (
    <Modal open onClose={onClose} title="Nový incident" wide>
      {/* Breadcrumb zákazníka */}
      {customer && (
        <div className="mb-3 text-sm" style={{ color: '#1a2e22' }}>
          <span className="font-extrabold">{customer.full_name || customer.email}</span>
          {customer.phone ? ` · ${customer.phone}` : ''}
          {activeBooking
            ? <span className="ml-2" style={{ color: '#1a8a18' }}>· rezervace {activeBooking.motorcycles?.model || ''} #{activeBooking.id.slice(-6).toUpperCase()}</span>
            : <span className="ml-2" style={{ color: '#b45309' }}>· bez aktivní rezervace</span>}
        </div>
      )}

      {err && (
        <div className="mb-3 rounded-lg text-sm font-bold" style={{ padding: '8px 12px', background: '#fee2e2', color: '#b91c1c' }}>
          {err}
        </div>
      )}

      {/* STEP: zákazník */}
      {screen === 'customer' && (
        <div>
          <label className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Zákazník</label>
          <input autoFocus value={q} onChange={e => searchCustomers(e.target.value)}
            placeholder="Hledat jméno / telefon / e-mail…"
            className="w-full mt-1 mb-2 rounded-btn text-sm outline-none"
            style={{ padding: '9px 12px', border: '1px solid #d4e8e0' }} />
          {results.map(c => (
            <div key={c.id} onClick={() => chooseCustomer(c)}
              className="flex items-center justify-between rounded-lg cursor-pointer mb-1"
              style={{ padding: '8px 12px', background: '#f8fcfa', border: '1px solid #e2f0ea' }}>
              <div>
                <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{c.full_name || '—'}</div>
                <div className="text-sm" style={{ color: '#1a2e22' }}>{c.phone || ''} {c.email ? '· ' + c.email : ''}</div>
              </div>
              <span style={{ color: '#2563eb' }}>Vybrat →</span>
            </div>
          ))}
          <div className="flex justify-end mt-4">
            <button disabled={!customer} onClick={() => setScreen('type')}
              className="rounded-btn text-sm font-extrabold cursor-pointer border-none disabled:opacity-40"
              style={{ padding: '9px 18px', background: '#1a2e22', color: '#74FB71' }}>
              Pokračovat →
            </button>
          </div>
        </div>
      )}

      {/* STEP: typ incidentu (strom) */}
      {screen === 'type' && (
        <div>
          {!category ? (
            <div className="space-y-2">
              {TREE.map(cat => (
                <button key={cat.key} onClick={() => setCategory(cat)}
                  className="w-full flex items-center gap-3 rounded-lg cursor-pointer border-none text-left"
                  style={{ padding: '12px 14px', background: '#f1faf7' }}>
                  <span style={{ fontSize: 22 }}>{cat.icon}</span>
                  <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{cat.label}</span>
                </button>
              ))}
            </div>
          ) : (
            <div className="space-y-2">
              <button onClick={() => setCategory(null)} className="text-sm font-extrabold cursor-pointer border-none mb-1"
                style={{ background: 'transparent', color: '#1a2e22' }}>← {category.label}</button>
              {category.items.map(it => (
                <button key={it.type} onClick={() => {
                  setPicked(it); setFault(null); setSecured(null); setAction(null); setMoto(null)
                  if (it.flow === 'simple') finalizeSimpleFor(it)
                  else setScreen('decision')
                }}
                  className="w-full flex items-center gap-3 rounded-lg cursor-pointer border-none text-left"
                  style={{ padding: '12px 14px', background: '#f8fcfa', border: '1px solid #e2f0ea' }}>
                  <span style={{ fontSize: 18 }}>{it.icon}</span>
                  <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{it.label}</span>
                </button>
              ))}
            </div>
          )}
          <div className="flex justify-start mt-4">
            <button onClick={() => setScreen('customer')} className="text-sm font-extrabold cursor-pointer border-none"
              style={{ padding: '8px 14px', background: '#f1faf7', color: '#1a2e22', borderRadius: 10 }}>← Zpět</button>
          </div>
        </div>
      )}

      {/* STEP: rozhodnutí (vina / zabezpečení / akce) */}
      {screen === 'decision' && picked && (
        <div className="space-y-4">
          <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{picked.label}</div>

          {picked.flow === 'decision_accident' && (
            <div>
              <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Zavinění</div>
              <div className="flex gap-2">
                <ChoiceBtn active={fault === true} danger onClick={() => setFault(true)}>Zákazník (platí)</ChoiceBtn>
                <ChoiceBtn active={fault === false} onClick={() => setFault(false)}>Cizí zavinění (zdarma)</ChoiceBtn>
              </div>
            </div>
          )}

          {picked.flow === 'decision_theft' && (
            <div>
              <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Byla motorka zabezpečená?</div>
              <div className="flex gap-2">
                <ChoiceBtn active={secured === true} onClick={() => setSecured(true)}>Ano — zabezpečená (zdarma)</ChoiceBtn>
                <ChoiceBtn active={secured === false} danger onClick={() => setSecured(false)}>Ne (placená náhrada)</ChoiceBtn>
              </div>
            </div>
          )}

          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Co dál?</div>
            <div className="flex flex-col gap-2">
              <ActionCard icon="🏍️" title={isFree ? 'Náhradní motorka — zdarma' : `Náhradní motorka — placená (${czk(DEPOSIT)} spoluúčast)`}
                desc="Vybrat motorku, adresu přistavení a vyřešit platbu"
                disabled={picked.flow === 'decision_accident' && fault === null || picked.flow === 'decision_theft' && secured === null}
                onClick={async () => { setAction('replacement'); await loadMotos(); setScreen('replacement') }} />
              {picked.flow !== 'decision_theft' && (
                <ActionCard icon="🚛" title="Ukončit jízdu + zavolat odtah"
                  desc="Původní rezervace se ukončí, objedná se odtah"
                  disabled={picked.flow === 'decision_accident' && fault === null}
                  onClick={finalizeEndRide} />
              )}
              {picked.flow === 'decision_theft' && (
                <ActionCard icon="📋" title="Jen nahlásit krádež (bez náhrady)"
                  desc="Založí incident bez náhradní motorky"
                  disabled={secured === null}
                  onClick={finalizeReportOnly} />
              )}
            </div>
          </div>

          <div className="flex justify-start">
            <button onClick={() => setScreen('type')} className="text-sm font-extrabold cursor-pointer border-none"
              style={{ padding: '8px 14px', background: '#f1faf7', color: '#1a2e22', borderRadius: 10 }}>← Zpět</button>
          </div>
        </div>
      )}

      {/* STEP: náhradní motorka */}
      {screen === 'replacement' && (
        <div className="space-y-3">
          {!activeBooking && (
            <div className="rounded-lg text-sm font-bold" style={{ padding: '8px 12px', background: '#fef3c7', color: '#b45309' }}>
              Zákazník nemá aktivní zaplacenou rezervaci — výměnu nelze provést. Vraťte se a zvolte „Ukončit jízdu".
            </div>
          )}
          <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Náhradní motorka</div>
          <div className="space-y-1" style={{ maxHeight: 220, overflowY: 'auto' }}>
            {motos.map(m => (
              <div key={m.id} onClick={() => setMoto(m)}
                className="flex items-center justify-between rounded-lg cursor-pointer"
                style={{ padding: '8px 12px', background: moto?.id === m.id ? '#e2f5ec' : '#f8fcfa', border: `1px solid ${moto?.id === m.id ? '#1a8a18' : '#e2f0ea'}` }}>
                <div>
                  <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{m.model}</div>
                  <div className="text-sm" style={{ color: '#1a2e22' }}>{m.spz} · {m.branches?.name || '—'} · {m.price_weekday || '?'} Kč/den</div>
                </div>
                {moto?.id === m.id && <span style={{ color: '#1a8a18' }}>✓</span>}
              </div>
            ))}
            {motos.length === 0 && <div className="text-sm" style={{ color: '#b45309' }}>Žádné dostupné motorky.</div>}
          </div>

          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Adresa přistavení</label>
              <input value={addr} onChange={e => setAddr(e.target.value)} className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 10px', border: '1px solid #d4e8e0' }} />
            </div>
            <div>
              <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Město</label>
              <input value={city} onChange={e => setCity(e.target.value)} className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 10px', border: '1px solid #d4e8e0' }} />
            </div>
          </div>
          {!isFree && (
            <div>
              <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Přistavení (Kč)</label>
              <input type="number" value={deliveryFee} onChange={e => setDeliveryFee(e.target.value)} placeholder="0"
                className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 10px', border: '1px solid #d4e8e0' }} />
            </div>
          )}

          {/* Souhrn ceny */}
          <div className="rounded-lg text-sm" style={{ padding: '10px 12px', background: isFree ? '#dcfce7' : '#fef2f2', border: `1px solid ${isFree ? '#86efac' : '#fecaca'}` }}>
            {isFree ? (
              <div className="font-extrabold" style={{ color: '#1a8a18' }}>💚 Náhradní motorka i přistavení ZDARMA</div>
            ) : (
              <div style={{ color: '#b91c1c' }}>
                <Row label={`🏍️ Nájem (${remainingDays} dní × ${czk(dailyPrice)})`} value={czk(motoTotal)} />
                <Row label="🚛 Přistavení" value={czk(feeVal)} />
                <Row label="🛡️ Spoluúčast (kauce)" value={czk(depositVal)} />
                <div className="flex justify-between font-extrabold mt-1 pt-1" style={{ borderTop: '1px solid #fecaca' }}>
                  <span>Celkem k úhradě</span><span>{czk(total)}</span>
                </div>
              </div>
            )}
          </div>

          <div className="flex justify-between">
            <button onClick={() => setScreen('decision')} className="text-sm font-extrabold cursor-pointer border-none"
              style={{ padding: '8px 14px', background: '#f1faf7', color: '#1a2e22', borderRadius: 10 }}>← Zpět</button>
            <button disabled={loading || !moto || !activeBooking} onClick={finalizeReplacement}
              className="rounded-btn text-sm font-extrabold cursor-pointer border-none disabled:opacity-40"
              style={{ padding: '9px 18px', background: '#1a2e22', color: '#74FB71' }}>
              {loading ? '⏳' : isFree ? 'Objednat zdarma →' : 'Pokračovat k platbě →'}
            </button>
          </div>
        </div>
      )}

      {/* STEP: platba (jen placená náhrada) */}
      {screen === 'payment' && (
        <div className="space-y-3">
          <div className="rounded-lg text-sm font-extrabold" style={{ padding: '10px 12px', background: '#fef2f2', color: '#b91c1c' }}>
            K úhradě: {czk(total)} {moto ? `· ${moto.model}` : ''}
          </div>
          <div className="flex gap-2">
            <ChoiceBtn active={payMethod === 'stripe'} onClick={() => setPayMethod('stripe')}>Stripe odkaz</ChoiceBtn>
            <ChoiceBtn active={payMethod === 'manual'} onClick={() => setPayMethod('manual')}>Ruční potvrzení</ChoiceBtn>
          </div>

          {payMethod === 'stripe' ? (
            <div className="text-sm" style={{ color: '#1a2e22' }}>
              Vytvoří se platební odkaz (karta / Apple&nbsp;Pay / Google&nbsp;Pay). Pošlete ho zákazníkovi —
              po zaplacení se náhradní rezervace automaticky označí jako uhrazená.
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Způsob platby</label>
                <select value={manualMethod} onChange={e => setManualMethod(e.target.value)} className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 10px', border: '1px solid #d4e8e0' }}>
                  {Object.entries(MANUAL_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </div>
              <div>
                <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Č. transakce / reference</label>
                <input value={reference} onChange={e => setReference(e.target.value)} className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 10px', border: '1px solid #d4e8e0' }} />
              </div>
            </div>
          )}

          <div className="flex justify-end">
            <button disabled={loading} onClick={payMethod === 'stripe' ? payStripe : payManual}
              className="rounded-btn text-sm font-extrabold cursor-pointer border-none disabled:opacity-40"
              style={{ padding: '9px 18px', background: '#1a2e22', color: '#74FB71' }}>
              {loading ? '⏳' : payMethod === 'stripe' ? 'Vytvořit platební odkaz' : 'Potvrdit platbu'}
            </button>
          </div>
        </div>
      )}

      {/* STEP: výsledek */}
      {screen === 'result' && (
        <div className="space-y-3">
          <div className="rounded-lg text-sm font-extrabold" style={{ padding: '12px 14px', background: '#dcfce7', color: '#1a8a18' }}>
            ✅ Incident založen{result?.replBookingId ? ' · náhradní rezervace vytvořena' : ''}
            {result?.paid ? ' · zaplaceno' : ''}
          </div>
          {result?.checkoutUrl && (
            <div>
              <div className="text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Platební odkaz (pošlete zákazníkovi):</div>
              <div className="flex gap-2">
                <input readOnly value={result.checkoutUrl} className="flex-1 rounded-btn text-sm outline-none"
                  style={{ padding: '8px 10px', border: '1px solid #d4e8e0', background: '#f8fcfa' }} />
                <button onClick={() => navigator.clipboard?.writeText(result.checkoutUrl)}
                  className="rounded-btn text-sm font-extrabold cursor-pointer border-none"
                  style={{ padding: '8px 14px', background: '#2563eb', color: '#fff' }}>Kopírovat</button>
              </div>
              <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>Odkaz byl také odeslán zákazníkovi do aplikace.</div>
            </div>
          )}
          <div className="flex justify-end">
            <button onClick={onClose} className="rounded-btn text-sm font-extrabold cursor-pointer border-none"
              style={{ padding: '9px 18px', background: '#1a2e22', color: '#74FB71' }}>Hotovo</button>
          </div>
        </div>
      )}
    </Modal>
  )

  // simple flow helper — uses the just-picked item (state setter is async)
  async function finalizeSimpleFor(it) {
    setLoading(true); setErr('')
    try {
      const description = it.label
      const { data: { user } } = await supabase.auth.getUser()
      const { data, error } = await supabase.from('sos_incidents').insert({
        user_id: customer.id, type: it.type, status: 'reported', title: it.label,
        description, contact_phone: customer.phone || null,
        ...(activeBooking?.id ? { booking_id: activeBooking.id } : {}),
        ...(activeBooking?.moto_id ? { moto_id: activeBooking.moto_id } : {}),
      }).select('id').single()
      if (error) throw error
      await supabase.from('sos_timeline').insert({
        incident_id: data.id, action: `Incident založen operátorem (Velín): ${it.label}`,
        performed_by: user?.email || 'Operátor', admin_id: user?.id,
      })
      setResult({ incidentId: data.id }); setScreen('result'); onCreated?.()
    } catch (e) { setErr(e.message || String(e)) }
    setLoading(false)
  }
}

const MANUAL_LABELS = {
  bank_transfer: 'Bankovní převod',
  qr: 'QR platba',
  cash: 'Hotově',
  card: 'Kartou (terminál)',
  crypto: 'Kryptoměna',
}

function ChoiceBtn({ active, danger, onClick, children }) {
  return (
    <button onClick={onClick}
      className="rounded-btn text-sm font-extrabold cursor-pointer border-none"
      style={{
        padding: '8px 14px',
        background: active ? (danger ? '#dc2626' : '#1a8a18') : '#f1faf7',
        color: active ? '#fff' : '#1a2e22',
      }}>
      {children}
    </button>
  )
}

function ActionCard({ icon, title, desc, onClick, disabled }) {
  return (
    <button onClick={onClick} disabled={disabled}
      className="w-full flex items-center gap-3 rounded-lg cursor-pointer border-none text-left disabled:opacity-40"
      style={{ padding: '12px 14px', background: '#f8fcfa', border: '1px solid #e2f0ea' }}>
      <span style={{ fontSize: 20 }}>{icon}</span>
      <span>
        <span className="block text-sm font-extrabold" style={{ color: '#0f1a14' }}>{title}</span>
        <span className="block text-sm" style={{ color: '#1a2e22' }}>{desc}</span>
      </span>
    </button>
  )
}

function Row({ label, value }) {
  return (
    <div className="flex justify-between"><span>{label}</span><span className="font-bold">{value}</span></div>
  )
}
