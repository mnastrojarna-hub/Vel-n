// Upravit výpůjčku JEN výbavy (booking_kind 'gear') — místo BookingModifyModal (motorka, vozík, přistavení,
// „vlastní výbava“ tu nedávají smysl). Termín, pobočka, kusy/velikosti a časy → admin_update_gear_booking:
// dry-run = náhled {old_total, new_total, diff, lines, warnings}, uložení = přepočet gear_lines / gear_per_day /
// total_price + modification_history na serveru. Rozdíl ceny u ZAPLACENÉ výpůjčky řeší Velín stejně jako u motorky:
// doplatek → mod_surcharge_due + výzva k platbě (qr-payment), vratka → process-refund; „Zdarma“ = cena beze změny.
import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import GearItemsPicker, { useGearPrices, useGearAvailability } from './GearItemsPicker'
import { gearItemsPayload, gearSelectionFromBooking, gearErrorText, gearWarningText, gearLineSizes } from '../../lib/bookingKind'

const czk = n => `${(Number(n) || 0).toLocaleString('cs-CZ', { maximumFractionDigits: 2 })} Kč`
const ld = d => (d ? String(d).slice(0, 10) : '')
const hm = t => (t ? String(t).slice(0, 5) : '')
const inp = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, fontSize: 14, width: '100%' }
const lbl = 'block text-sm font-extrabold uppercase tracking-wide mb-1'

export default function GearModifyModal({ booking, onClose, onSaved }) {
  const started = booking.status === 'active'   // převzato → začátek a pobočka se nemění
  const [start, setStart] = useState(ld(booking.start_date))
  const [end, setEnd] = useState(ld(booking.end_date))
  const [branchId, setBranchId] = useState(booking.branch_id || '')
  const [selection, setSelection] = useState(() => gearSelectionFromBooking(booking))
  const [pickupTime, setPickupTime] = useState(hm(booking.pickup_time))
  const [returnTime, setReturnTime] = useState(hm(booking.return_time))
  const [charge, setCharge] = useState(true)
  const [branches, setBranches] = useState([])
  const [preview, setPreview] = useState(null)
  const [loadingPrev, setLoadingPrev] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => { supabase.from('branches').select('id, name, type').order('name').then(({ data }) => setBranches(data || []), () => {}) }, [])
  const branch = branches.find(b => b.id === branchId)
  const prices = useGearPrices()
  const free = useGearAvailability(branchId, start, end)
  const items = gearItemsPayload(selection)
  const params = dry => ({ p_booking_id: booking.id, p_start: start, p_end: end, p_items: items, p_branch_id: branchId || null,
    p_pickup_time: pickupTime || null, p_return_time: returnTime || null, p_dry_run: dry })
  const key = JSON.stringify(params(true))

  // Náhled ceny ze serveru při každé změně (se zpožděním)
  useEffect(() => {
    if (!start || !end || !items.length || end < start) { setPreview(null); return }
    let alive = true
    setLoadingPrev(true)
    const t = setTimeout(async () => {
      const { data, error: e } = await supabase.rpc('admin_update_gear_booking', params(true))
      if (!alive) return
      setPreview(e ? { error: e.message } : data)
      setLoadingPrev(false)
    }, 350)
    return () => { alive = false; clearTimeout(t) }
  }, [key]) // eslint-disable-line react-hooks/exhaustive-deps

  const diff = Number(preview?.diff) || 0
  const origPaid = ['paid', 'partial_refund', 'refund_pending'].includes(booking.payment_status)
  const pending = Number(booking.mod_surcharge_due) || 0

  async function save() {
    setError(null)
    if (!items.length) { setError('Výpůjčka musí mít aspoň jeden kus výbavy (jinak ji zrušte — Storno).'); return }
    if (!start || !end || end < start) { setError('Neplatný termín'); return }
    setSaving(true)
    try {
      const res = await debugAction('booking.modify_gear', 'GearModifyModal', () => supabase.rpc('admin_update_gear_booking', params(false)), params(false))
      if (res?.error) throw res.error
      const d = res?.data
      if (!d || d.error || d.success === false) throw new Error(gearErrorText(d || 'Uložení selhalo'))
      const realDiff = Number(d.diff ?? diff) || 0
      const oldTotal = Number(d.old_total ?? booking.total_price) || 0
      if (!charge && realDiff !== 0) {
        // „Zdarma“: změna bez doplatku/vratky — cena zůstává (rozdíl řádků vyrovná korekce na dokladu)
        await supabase.from('bookings').update({ total_price: oldTotal }).eq('id', booking.id)
      } else if (charge && origPaid && realDiff !== 0) {
        const newDue = pending + realDiff
        if (newDue > 0) {
          await supabase.from('bookings').update({ mod_surcharge_due: newDue, mod_surcharge_requested_at: new Date().toISOString(), mod_surcharge_paid_at: null }).eq('id', booking.id)
          const { data: qr, error: qrErr } = await supabase.functions.invoke('qr-payment', { body: { booking_id: booking.id, surcharge: true, locale: booking.language || 'cs' } })
          if (qrErr || qr?.success === false) window.alert('Úprava je uložená, ale výzva k doplatku se neodeslala (' + (qr?.error || qrErr?.message || 'chyba') + '). Pošlete platební údaje zákazníkovi ručně.')
        } else {
          if (pending > 0) await supabase.from('bookings').update({ mod_surcharge_due: null, mod_email_payload: null }).eq('id', booking.id)
          const refund = Math.abs(newDue)
          if (refund > 0) {
            const { data: rfd, error: rfe } = await supabase.functions.invoke('process-refund', { body: { booking_id: booking.id, amount: refund, reason: 'shortening' } })
            if (rfe || rfd?.success !== true) window.alert('Úprava je uložená, ale vratka ' + czk(refund) + ' se nepodařila (' + (rfe?.message || rfd?.error || 'chyba') + '). Vyřiďte vrácení ručně z detailu rezervace.')
            else if (rfd?.manual === true) window.alert('Výpůjčka nemá Stripe platbu — dobropis je vystaven, vratku ' + czk(refund) + ' pošlete PŘEVODEM na účet zákazníka a potvrďte „Vratka odeslána“.')
          }
        }
      }
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'booking_modified', new_data: { booking_id: booking.id, kind: 'gear', price_diff: realDiff, charged: charge, items, branch_id: branchId, start, end } })
      } catch { /* audit nesmí shodit akci */ }
      const warns = (Array.isArray(d.warnings) ? d.warnings : []).filter(w => w !== 'paid_total_changed')   // ten řeší doplatek/vratka výše
      if (warns.length) window.alert('Uloženo s upozorněním:\n• ' + warns.map(w => gearWarningText(w, d.stock_short)).join('\n• '))
      onSaved()
    } catch (e) { setError(e.message || String(e)) } finally { setSaving(false) }
  }

  return (
    <Modal open title={`Upravit výpůjčku výbavy #${booking.id?.slice(-8).toUpperCase()}`} onClose={onClose} wide>
      <div className="space-y-4">
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <div><label className={lbl} style={{ color: '#1a2e22' }}>Od</label><input type="date" value={start} disabled={started} onChange={e => setStart(e.target.value)} style={inp} /></div>
          <div><label className={lbl} style={{ color: '#1a2e22' }}>Do</label><input type="date" value={end} min={start} onChange={e => setEnd(e.target.value)} style={inp} /></div>
          <div><label className={lbl} style={{ color: '#1a2e22' }}>Vyzvednutí</label><input type="time" value={pickupTime} disabled={started} onChange={e => setPickupTime(e.target.value)} style={inp} /></div>
          <div><label className={lbl} style={{ color: '#1a2e22' }}>Vrácení</label><input type="time" value={returnTime} onChange={e => setReturnTime(e.target.value)} style={inp} /></div>
        </div>
        <div>
          <label className={lbl} style={{ color: '#1a2e22' }}>Pobočka</label>
          <select value={branchId} disabled={started} onChange={e => setBranchId(e.target.value)} style={inp}>
            {branches.map(b => <option key={b.id} value={b.id}>{b.name}{b.type ? ` (${b.type})` : ''}</option>)}
          </select>
          {started && <p className="text-xs mt-1" style={{ color: '#4a6357' }}>Výbava je převzatá — začátek a pobočku už měnit nelze.</p>}
        </div>
        <div>
          <label className={lbl} style={{ color: '#1a2e22' }}>Výbava</label>
          <GearItemsPicker prices={prices} selection={selection} onChange={setSelection} selfService={branch?.type === 'samoobslužná'} free={free} />
        </div>

        <div className="p-3 rounded-lg text-sm" style={{ background: '#f8faf9', border: '1px solid #e5e7eb', color: '#1a2e22' }}>
          {loadingPrev ? 'Počítám změnu ceny…' : preview?.error ? <span style={{ color: '#dc2626', fontWeight: 700 }}>{gearErrorText(preview)}</span> : preview ? (
            <>
              <div className="flex flex-wrap gap-x-6 gap-y-1">
                <span>Původně <b>{czk(preview.old_total)}</b></span>
                <span>Nově <b>{czk(preview.new_total)}</b></span>
                <span style={{ color: diff > 0 ? '#2563eb' : diff < 0 ? '#dc2626' : '#1a2e22', fontWeight: 800 }}>{diff > 0 ? `doplatek +${czk(diff)}` : diff < 0 ? `rozdíl −${czk(-diff)}` : 'beze změny ceny'}</span>
              </div>
              {Array.isArray(preview.lines) && preview.lines.length > 0 && (
                <div className="mt-2 text-xs" style={{ color: '#4a5a52' }}>{preview.lines.map(l => `${l.label || l.key}${gearLineSizes(l) ? ` (${gearLineSizes(l)})` : ''} ${czk(l.price_per_day)}/den`).join(' · ')}</div>
              )}
              {Array.isArray(preview.warnings) && preview.warnings.length > 0 && (
                <div className="mt-2 text-xs font-bold" style={{ color: '#b45309' }}>⚠ {preview.warnings.map(w => gearWarningText(w, preview.stock_short)).join(' · ')}</div>
              )}
            </>
          ) : 'Upravte termín nebo výbavu — změna ceny se spočítá na serveru.'}
        </div>

        {diff !== 0 && (
          <label className="flex items-start gap-2 cursor-pointer p-3 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fbbf24' }}>
            <input type="checkbox" checked={charge} onChange={e => setCharge(e.target.checked)} style={{ width: 16, height: 16, accentColor: '#1a8a18', marginTop: 2 }} />
            <span className="text-sm" style={{ color: '#1a2e22' }}>
              <b>Účtovat změnu ceny</b> — {origPaid
                ? (diff > 0 ? 'zákazník dostane výzvu k doplatku; potvrzení úpravy pak „Potvrdit doplatek“.' : 'rozdíl se zákazníkovi vrátí (Stripe / dobropis na účet).')
                : 'nezaplacená výpůjčka — zákazník zaplatí novou cenu.'}
              {!charge && ' Bez zaškrtnutí zůstává původní cena (zdarma).'}
            </span>
          </label>
        )}

        {error && <div role="alert" className="p-3 rounded-lg" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
        <div className="flex justify-end gap-3 max-sm:flex-col-reverse">
          <Button onClick={onClose} disabled={saving}>Zrušit</Button>
          <Button green onClick={save} disabled={saving || loadingPrev || !items.length || !!preview?.error}>{saving ? 'Ukládám…' : 'Uložit úpravu'}</Button>
        </div>
      </div>
    </Modal>
  )
}
