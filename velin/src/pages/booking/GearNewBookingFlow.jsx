// Nová rezervace → „Jen výbava“ (výpůjčka výbavy bez motorky): krok 2 = pobočka + kusy/velikosti + nezávazná
// cena (quote_gear_booking), krok 3 = zákazník, časy, poznámka → admin_create_gear_booking (SECURITY DEFINER:
// otevření pobočky, ceník, velikosti, sklad = jen varování pro admina, booking_source 'velin'). Klient nic
// nevkládá do bookings přímo (RLS + guard gear řádku) a cenu nepočítá.
import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Button from '../../components/ui/Button'
import GearItemsPicker, { useGearPrices, useGearAvailability, useGearQuote } from './GearItemsPicker'
import { gearItemsPayload, gearErrorText, gearWarningText, GEAR_ADMIN_SOFT_ERRORS, GEAR_LABELS } from '../../lib/bookingKind'

const czk = n => `${(Number(n) || 0).toLocaleString('cs-CZ', { maximumFractionDigits: 2 })} Kč`
const fmt = d => (d ? d.toLocaleDateString('cs-CZ') : '—')
const inp = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
const lbl = 'block text-sm font-extrabold uppercase tracking-wide mb-1'
const errBox = { background: '#fee2e2', color: '#dc2626', fontSize: 13 }

export default function GearNewBookingFlow({ step, setStep, startDate, endDate, isoDate, customers, onSaved }) {
  const [branches, setBranches] = useState([])
  const [branchId, setBranchId] = useState('')
  const [selection, setSelection] = useState({})
  const [search, setSearch] = useState('')
  const [customer, setCustomer] = useState(null)
  const [pickupTime, setPickupTime] = useState('09:00')
  const [returnTime, setReturnTime] = useState('')
  const [notes, setNotes] = useState('')
  const [markPaid, setMarkPaid] = useState(false)
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('branches').select('id, name, type').order('name').then(({ data }) => setBranches(data || []), () => setBranches([]))
  }, [])

  const start = isoDate(startDate), end = isoDate(endDate)
  const branch = branches.find(b => b.id === branchId)
  const selfService = branch?.type === 'samoobslužná'
  const prices = useGearPrices()
  const free = useGearAvailability(branchId, start, end)
  const quote = useGearQuote(branchId, start, end, selection)
  const items = gearItemsPayload(selection)
  const q = quote.data
  // quote_gear_booking je nacenění pro zákazníka — co admin RPC jen varuje (sklad, nastavení, termín), neblokuje
  const qBlocking = q?.error && !GEAR_ADMIN_SOFT_ERRORS.includes(q.error)
  const total = q && !q.error ? (q.total ?? q.amount) : null

  const matches = search.length > 1
    ? customers.filter(c => [c.full_name, c.email].some(v => (v || '').toLowerCase().includes(search.toLowerCase())) || (c.phone || '').includes(search)).slice(0, 8)
    : []

  async function create() {
    setErr(null)
    if (!customer || !branchId || !items.length) { setErr('Vyplňte pobočku, výbavu a zákazníka'); return }
    setSaving(true)
    try {
      const params = {
        p_user_id: customer.id, p_branch_id: branchId, p_start: start, p_end: end, p_items: items,
        p_pickup_time: pickupTime || null, p_return_time: returnTime || null, p_note: notes || null,
        p_mark_paid: markPaid, p_lang: customer.language || 'cs',
      }
      const res = await debugAction('bookings.create_gear', 'GearNewBookingFlow', () => supabase.rpc('admin_create_gear_booking', params), params)
      if (res?.error) throw res.error
      const d = res?.data
      if (!d || d.error || d.success === false) throw new Error(gearErrorText(d || 'Vytvoření selhalo'))
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'booking_created_admin', new_data: { booking_id: d.booking_id, kind: 'gear', branch_id: branchId, items, customer: customer.full_name, no_payment: markPaid } })
      } catch { /* audit nesmí shodit akci */ }
      if (Array.isArray(d.warnings) && d.warnings.length) window.alert('Výpůjčka vytvořena s upozorněním:\n• ' + d.warnings.map(w => gearWarningText(w, d.stock_short)).join('\n• '))
      onSaved()
    } catch (e) { setErr(e.message || String(e)) } finally { setSaving(false) }
  }

  if (step === 2) {
    return (
      <div>
        <div className="mb-3">
          <label className={lbl} style={{ color: '#1a2e22' }}>Pobočka vyzvednutí</label>
          <select value={branchId} onChange={e => setBranchId(e.target.value)} className="w-full rounded-btn text-sm font-bold cursor-pointer" style={inp}>
            <option value="">Vyberte pobočku…</option>
            {branches.map(b => <option key={b.id} value={b.id}>{b.name}{b.type ? ` (${b.type})` : ''}</option>)}
          </select>
        </div>
        <label className={lbl} style={{ color: '#1a2e22' }}>Výbava ({fmt(startDate)} – {fmt(endDate)})</label>
        <GearItemsPicker prices={prices} selection={selection} onChange={setSelection} selfService={selfService} free={free} disabled={!branchId} />
        {!branchId && <p className="text-sm mt-2" style={{ color: '#4a6357' }}>Nejdřív vyberte pobočku (určuje sklad, otevírací dobu a rozsah velikostí).</p>}
        {items.length > 0 && branchId && (
          <div className="mt-3 p-3 rounded-lg text-sm" style={{ background: '#f8faf9', border: '1px solid #e5e7eb' }}>
            {quote.loading ? 'Počítám cenu…' : q?.error
              ? <span style={{ color: qBlocking ? '#dc2626' : '#b45309', fontWeight: 700 }}>{gearErrorText(q)}{qBlocking ? '' : ' — admin může vytvořit i tak (zobrazí se upozornění).'}</span>
              : q ? <span><b>{czk(total)}</b>{q.per_day != null ? ` · ${czk(q.per_day)}/den` : ''}{q.days ? ` · ${q.days} dní` : ''}</span> : null}
          </div>
        )}
        <div className="flex justify-between mt-4">
          <Button onClick={() => setStep(1)}>← Zpět</Button>
          <Button green onClick={() => { setErr(null); setStep(3) }} disabled={!branchId || !items.length || quote.loading || !!qBlocking}>Pokračovat →</Button>
        </div>
      </div>
    )
  }

  return (
    <div>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <label className={lbl} style={{ color: '#1a2e22' }}>Zákazník</label>
          {customer ? (
            <div className="p-3 rounded-lg" style={{ background: '#eafbe9', border: '1px solid #74FB71' }}>
              <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{customer.full_name}</div>
              <div className="text-sm" style={{ color: '#1a2e22' }}>{customer.email}</div>
              <button onClick={() => { setCustomer(null); setSearch('') }} className="text-sm font-bold cursor-pointer mt-1 max-lg:min-h-[36px]" style={{ color: '#dc2626', background: 'none', border: 'none' }}>Změnit</button>
            </div>
          ) : (
            <div>
              <input type="text" value={search} onChange={e => setSearch(e.target.value)} placeholder="Hledat jméno, email, telefon…" className="w-full rounded-btn text-sm outline-none" style={inp} />
              {matches.length > 0 && (
                <div className="mt-1 rounded-lg" style={{ border: '1px solid #d4e8e0', maxHeight: 180, overflowY: 'auto' }}>
                  {matches.map(c => (
                    <div key={c.id} className="p-2 cursor-pointer text-sm hover:bg-green-50" style={{ borderBottom: '1px solid #f1faf7' }} onClick={() => { setCustomer(c); setSearch('') }}>
                      <span className="font-bold">{c.full_name}</span><span className="ml-2" style={{ color: '#1a2e22' }}>{c.email}</span>
                    </div>
                  ))}
                </div>
              )}
              {search.length > 1 && matches.length === 0 && <p className="text-sm mt-1" style={{ color: '#1a2e22' }}>Žádný zákazník nenalezen</p>}
            </div>
          )}
          <div className="grid grid-cols-2 gap-3 mt-4">
            <div><label className={lbl} style={{ color: '#1a2e22' }}>Vyzvednutí</label><input type="time" value={pickupTime} onChange={e => setPickupTime(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inp} /></div>
            <div><label className={lbl} style={{ color: '#1a2e22' }}>Vrácení</label><input type="time" value={returnTime} onChange={e => setReturnTime(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inp} /></div>
          </div>
          <label className={`${lbl} mt-4`} style={{ color: '#1a2e22' }}>Poznámka</label>
          <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} placeholder="Interní poznámka (volitelné)" className="w-full rounded-btn text-sm outline-none resize-none" style={inp} />
        </div>
        <div>
          <label className={lbl} style={{ color: '#1a2e22' }}>Shrnutí výpůjčky výbavy</label>
          <div className="rounded-lg p-4 text-sm" style={{ background: '#f8faf9', border: '1px solid #e5e7eb', color: '#1a2e22' }}>
            <div className="font-bold mb-1" style={{ color: '#0f1a14' }}>{branch?.name || '—'}</div>
            <div className="mb-2">{items.map(i => `${GEAR_LABELS[i.key] || i.key} ${i.size}`).join(', ')}</div>
            <div className="flex justify-between mb-1"><span>Termín</span><b>{fmt(startDate)} – {fmt(endDate)}</b></div>
            <div className="flex justify-between pt-2" style={{ borderTop: '1px solid #d4e8e0' }}><b>Celkem</b><b style={{ color: '#1a8a18' }}>{total != null ? czk(total) : '—'}</b></div>
          </div>
          <label className="flex items-center gap-2 mt-4 cursor-pointer p-3 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fbbf24' }}>
            <input type="checkbox" checked={markPaid} onChange={e => setMarkPaid(e.target.checked)} style={{ width: 16, height: 16, accentColor: '#1a8a18' }} />
            <div>
              <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>Bez platby</div>
              <div className="text-sm" style={{ color: '#1a2e22' }}>{markPaid ? 'Výpůjčka bude označena jako zaplacená' : 'Výpůjčka čeká na platbu (potvrdíte v detailu)'}</div>
            </div>
          </label>
        </div>
      </div>
      {err && <div role="alert" className="p-3 rounded-lg mt-4" style={errBox}>{err}</div>}
      <div className="flex justify-between mt-5 max-sm:flex-col-reverse max-sm:gap-2">
        <Button onClick={() => setStep(2)} className="max-sm:justify-center">← Zpět</Button>
        <Button green className="max-sm:justify-center" onClick={create} disabled={saving || !customer}>{saving ? 'Vytvářím…' : markPaid ? 'Vytvořit (zaplaceno)' : 'Vytvořit výpůjčku'}</Button>
      </div>
    </div>
  )
}
