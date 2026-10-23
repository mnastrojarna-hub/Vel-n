// Upravit výpůjčku JEN výbavy (booking_kind 'gear') — místo BookingModifyModal (motorka, vozík, přistavení,
// „vlastní výbava“ tu nedávají smysl). Termín, pobočka, kusy/velikosti a časy → admin_update_gear_booking:
// dry-run = náhled {old_total, new_total, diff, lines, warnings}, uložení = přepočet gear_lines / gear_per_day /
// total_price + modification_history na serveru. Rozdíl ceny u ZAPLACENÉ výpůjčky řeší Velín stejně jako u motorky:
// doplatek → mod_surcharge_due + výzva k platbě (qr-payment), vratka → process-refund; „Zdarma“ = cena beze změny.
// Pořadí zápisů (kvůli mailu triggeru úprav) a větev „Zdarma“ jsou v gearModifyApply.js.
import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import GearItemsPicker, { useGearPrices, useGearAvailability } from './GearItemsPicker'
import { gearItemsPayload, gearSelectionFromBooking, gearErrorText, gearWarningText, gearLineSizes } from '../../lib/bookingKind'
import { planGearCharge, applyGearModify, freeWithOwnItems } from './gearModifyApply'
import { pragueDay } from './protocolGearOnly'

const czk = n => `${(Number(n) || 0).toLocaleString('cs-CZ', { maximumFractionDigits: 2 })} Kč`
const ld = d => pragueDay(d)   // den v Praze (web ukládá UTC půlnoc, RPC porovnává pražské dny)
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

  // aktivní pobočky + aktuální pobočka výpůjčky (i kdyby mezitím byla deaktivovaná)
  useEffect(() => {
    supabase.from('branches').select('id, name, type, active').order('name')
      .then(({ data }) => setBranches((data || []).filter(b => b.active !== false || b.id === booking.branch_id)), () => {})
  }, [booking.branch_id])
  const branch = branches.find(b => b.id === branchId)
  const prices = useGearPrices()
  const rawFree = useGearAvailability(branchId, start, end)
  // vlastní kusy upravované výpůjčky nejsou „obsazené“ (dostupnost je nevyjímá, server dry-run ano)
  const free = useMemo(() => freeWithOwnItems(rawFree, booking, { branchId, start, end }), [rawFree, booking, branchId, start, end])
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
      // čerstvý dry-run těsně před uložením — podle něj se volí doplatek / vratka / „Zdarma“
      const { data: dry, error: dErr } = await supabase.rpc('admin_update_gear_booking', params(true))
      if (dErr) throw dErr
      if (!dry || dry.error || dry.success === false) throw new Error(gearErrorText(dry || 'Náhled změny selhal'))
      const plan = planGearCharge({ charge, origPaid, pending, diff: Number(dry.diff) || 0 })
      const form = { start, end, branchId, pickupTime, returnTime }
      const out = await applyGearModify({ booking, rpcParams: params(false), dry, plan, form })
      const alerts = [...out.alerts]
      if (out.surchargeDue > 0) {
        try {
          const { data: qr, error: qrErr } = await supabase.functions.invoke('qr-payment', { body: { booking_id: booking.id, surcharge: true, locale: booking.language || 'cs' } })
          if (qrErr || qr?.success === false) throw new Error(qr?.error || qrErr?.message || 'qr-payment failed')
        } catch (e) { alerts.push('Úprava je uložená, ale výzva k doplatku se neodeslala (' + (e.message || 'chyba') + '). Pošlete platební údaje zákazníkovi ručně.') }
      }
      if (out.refund > 0) {
        // dobropis nese „Úprava výbavy“, když se termín neměnil (jen kusy / velikosti / pobočka)
        const reason = start === ld(booking.start_date) && end === ld(booking.end_date) ? 'gear_edit' : 'shortening'
        try {
          const { data: rfd, error: rfe } = await supabase.functions.invoke('process-refund', { body: { booking_id: booking.id, amount: out.refund, reason } })
          if (rfe || rfd?.success !== true) alerts.push('Úprava je uložená, ale vratka ' + czk(out.refund) + ' se nepodařila (' + (rfe?.message || rfd?.error || 'chyba') + '). Vyřiďte vrácení ručně z detailu rezervace.')
          else if (rfd?.fio_sent === true) alerts.push('Vratka ' + czk(out.refund) + ' byla odeslána AUTOMATICKY převodem přes Fio API (dávka ' + (rfd?.fio_instruction_id || '—') + '). Dobropis je vystaven — není potřeba nic posílat ručně.')
          else if (rfd?.manual === true) alerts.push('Výpůjčka nemá Stripe platbu — dobropis je vystaven, vratku ' + czk(out.refund) + ' pošlete PŘEVODEM na účet zákazníka a potvrďte „Vratka odeslána“.')
        } catch (e) { alerts.push('Úprava je uložená, ale vratka ' + czk(out.refund) + ' se nepodařila (' + (e.message || 'chyba') + '). Vyřiďte vrácení ručně z detailu rezervace.') }
      }
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'booking_modified', new_data: { booking_id: booking.id, kind: 'gear', price_diff: Number(dry.diff) || 0, charged: plan.mode !== 'free', mode: plan.mode, items, branch_id: branchId, start, end } })
      } catch { /* audit nesmí shodit akci */ }
      const res = out.result || {}
      const warns = (Array.isArray(res.warnings) ? res.warnings : []).filter(w => w !== 'paid_total_changed')   // ten řeší doplatek/vratka výše
      if (warns.length) alerts.unshift('Uloženo s upozorněním:\n• ' + warns.map(w => gearWarningText(w, res.stock_short)).join('\n• '))
      if (alerts.length) window.alert(alerts.join('\n\n'))
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
