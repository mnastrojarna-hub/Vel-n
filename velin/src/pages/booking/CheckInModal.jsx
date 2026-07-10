import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { logAudit } from './bookingMessageHelpers'
import PickupReadiness from './PickupReadiness'

// Odbavení odjezdu (vyzvednutí) a návratu (vrácení) přímo z přehledu „Odjezdy a návraty".
// Pravidla:
//  • Odjezd na OBSLUŽNÉ pobočce → zákazník podepíše předávací protokol (ElectronicProtocolModal).
//  • Odjezd na SAMOOBSLUŽNÉ pobočce → zadání kódu k motorce do systému (ověření identity).
//  • Návrat na SAMOOBSLUŽNÉ pobočce → zadání kódu, nejdříve však 2 hodiny od vyzvednutí.
//  • Ostatní návraty (obslužná pobočka / svoz) → jen ruční potvrzení vrácení (např. zapomenutý mobil apod.).

const TWO_HOURS_MS = 2 * 60 * 60 * 1000
const fmtDT = (s) => (s ? new Date(s).toLocaleString('cs-CZ', { day: 'numeric', month: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—')

// Plánovaný čas vyzvednutí (start_date + pickup_time) — fallback pro 2h pravidlo,
// když neznáme reálný picked_up_at (např. odjezd odbaven jen protokolem).
function schedPickupMs(b) {
  const d = (b?.start_date || '').split('T')[0]
  if (!d) return null
  const t = (b?.pickup_time || '09:00').slice(0, 5)
  const dt = new Date(`${d}T${t}:00`)
  return isNaN(dt.getTime()) ? null : dt.getTime()
}

const inputStyle = { width: '100%', padding: '10px 12px', borderRadius: 10, border: '1px solid #b6dccb', fontSize: 14 }
const noteBox = (border, bg, color) => ({ border: `2px solid ${border}`, background: bg, color, borderRadius: 10, padding: 12, fontSize: 13 })

export default function CheckInModal({ open, event, onClose, onDone }) {
  const booking = event?.booking
  const isPickup = event?.type === 'pickup'
  const branchType = event?.branchType || null
  const selfService = branchType === 'samoobslužná'

  const [motoCode, setMotoCode] = useState('')
  const [loadingCode, setLoadingCode] = useState(true)
  const [codeInput, setCodeInput] = useState('')
  const [codeChecked, setCodeChecked] = useState(false)
  const [codeOk, setCodeOk] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => {
    if (!open || !booking?.id) return
    setCodeInput(''); setCodeChecked(false); setCodeOk(false); setError(null)
    setLoadingCode(true)
    supabase.from('branch_door_codes').select('door_code')
      .eq('booking_id', booking.id).eq('code_type', 'motorcycle')
      .order('created_at', { ascending: false }).limit(1)
      .then(({ data }) => { setMotoCode(data?.[0]?.door_code || ''); setLoadingCode(false) })
  }, [open, booking?.id])

  // Odjezd je vyřízen, když má rezervace picked_up_at / aktivní stav / protokol
  // (event.pickupDone). 2h pravidlo měří od reálného vyzvednutí (event.pickupAt),
  // při neznámém čase od plánovaného vyzvednutí.
  const pickupRefMs = event?.pickupAt ? new Date(event.pickupAt).getTime() : schedPickupMs(booking)
  const earliestReturn = pickupRefMs ? pickupRefMs + TWO_HOURS_MS : null
  const returnTooEarly = !isPickup && selfService && !!earliestReturn && Date.now() < earliestReturn
  const notPickedUp = !isPickup && !event?.pickupDone

  function verifyCode() {
    const ok = !!motoCode && codeInput.trim() === String(motoCode).trim()
    setCodeOk(ok); setCodeChecked(true)
  }

  async function markPickedUp(via) {
    setSaving(true); setError(null)
    const now = new Date().toISOString()
    const upd = { status: 'active', picked_up_at: now }
    // Na OBSLUŽNÉ pobočce je aktivace vázaná na předávací protokol — označíme ho
    // jako vyplněný, aby přechod prošel strážcem trg_gate_obsluzna_activation.
    // Samoobslužná (kód) se strážcem neřídí a protokol si plní zákazník v appce.
    if (!selfService) upd.handover_protocol_filled_at = now
    const { error: err } = await supabase.from('bookings')
      .update(upd).eq('id', booking.id)
    if (err) { setError(err.message); setSaving(false); return }
    await logAudit('booking_checkin_pickup', { booking_id: booking.id, method: via, branch_type: branchType })
    setSaving(false)
    onDone?.()
  }

  async function markReturned(via) {
    setSaving(true); setError(null)
    const now = new Date().toISOString()
    const { error: err } = await supabase.from('bookings')
      .update({ status: 'completed', returned_at: now, actual_return_date: now.slice(0, 10) }).eq('id', booking.id)
    if (err) { setError(err.message); setSaving(false); return }
    await logAudit('booking_checkin_return', { booking_id: booking.id, method: via, branch_type: branchType })
    setSaving(false)
    onDone?.()
  }

  if (!open || !event) return null

  const title = isPickup ? 'Odbavit odjezd (vyzvednutí)' : 'Odbavit návrat (vrácení)'

  // Blok pro zadání/ověření kódu k motorce (samoobslužná pobočka).
  const codeBlock = (actionLabel, onConfirm) => (
    <div className="space-y-3">
      {loadingCode ? (
        <p className="text-sm" style={{ color: '#64748b' }}>Načítám kód…</p>
      ) : motoCode ? (
        <>
          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: '#1a2e22', display: 'block', marginBottom: 6 }}>
              Kód k motorce zadaný zákazníkem do systému
            </label>
            <div className="flex items-center gap-2">
              <input type="text" inputMode="numeric" value={codeInput}
                onChange={e => { setCodeInput(e.target.value); setCodeOk(false); setCodeChecked(false) }}
                onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); verifyCode() } }}
                style={inputStyle} placeholder="6místný kód" />
              <Button onClick={verifyCode}>Ověřit</Button>
            </div>
            {codeChecked && (codeOk
              ? <p style={{ fontSize: 12, fontWeight: 700, color: '#15803d', marginTop: 6 }}>✓ Kód souhlasí.</p>
              : <p style={{ fontSize: 12, fontWeight: 700, color: '#dc2626', marginTop: 6 }}>✗ Kód nesouhlasí.</p>)}
          </div>
          <div className="flex justify-end gap-3 pt-1">
            <Button onClick={onClose} disabled={saving}>Zrušit</Button>
            <Button green disabled={!codeOk || saving} onClick={onConfirm}>{saving ? 'Ukládám…' : actionLabel}</Button>
          </div>
        </>
      ) : (
        <>
          <div style={noteBox('#b45309', '#fffbeb', '#92400e')}>
            Pro tuto rezervaci není vygenerován kód k motorce (např. dětská motorka nebo zadržený kód kvůli chybějícím dokladům).
            Odbavte ručně až po ověření zákazníka.
          </div>
          <div className="flex justify-end gap-3 pt-1">
            <Button onClick={onClose} disabled={saving}>Zrušit</Button>
            <Button green disabled={saving} onClick={onConfirm}>{saving ? 'Ukládám…' : actionLabel + ' (ručně)'}</Button>
          </div>
        </>
      )}
    </div>
  )

  return (
    <Modal open={open} title={title} onClose={onClose}>
      <div className="space-y-4">
        {error && <div style={noteBox('#dc2626', '#fee2e2', '#dc2626')}>{error}</div>}

        <div className="p-3 rounded-card" style={{ background: '#f1faf7', fontSize: 13, color: '#1a2e22' }}>
          <strong>{event.customer}</strong> · {event.moto}{event.spz ? ` (${event.spz})` : ''}
          <div className="mt-1" style={{ color: '#64748b' }}>
            {event.delivery ? '🚚 ' + (event.address || 'na adresu') : '🏍️ ' + (event.branch || 'pobočka')}
            {branchType ? ` · ${selfService ? 'samoobslužná' : 'obslužná'} pobočka` : ''}
          </div>
        </div>

        {/* ── ODJEZD ── */}
        {isPickup && (selfService ? (
          <>
            <div style={noteBox('#2563eb', '#eff6ff', '#1e3a8a')}>
              <strong>Samoobslužná pobočka.</strong> Zákazník zadá svůj kód k motorce do systému — ověřte jej a odbavte odjezd.
            </div>
            {codeBlock('Odbavit odjezd', () => markPickedUp('self_service_code'))}
          </>
        ) : (
          <PickupReadiness booking={booking} onClose={onClose} onProtocolDone={() => markPickedUp('protocol')} />
        ))}

        {/* ── NÁVRAT ── */}
        {!isPickup && (notPickedUp ? (
          <>
            <div style={noteBox('#b45309', '#fffbeb', '#92400e')}>
              Rezervace zatím nebyla vyzvednuta — návrat nelze odbavit. Nejprve odbavte odjezd.
            </div>
            <div className="flex justify-end"><Button onClick={onClose}>Zavřít</Button></div>
          </>
        ) : selfService ? (
          returnTooEarly ? (
            <>
              <div style={noteBox('#b45309', '#fffbeb', '#92400e')}>
                Návrat lze na samoobslužné pobočce odbavit <strong>nejdříve 2 hodiny od vyzvednutí</strong>.
                <div className="mt-1">Vyzvednuto: {fmtDT(event?.pickupAt) === '—' ? 'dle plánu' : fmtDT(event?.pickupAt)} · nejdříve lze odbavit: <strong>{fmtDT(new Date(earliestReturn).toISOString())}</strong>.</div>
              </div>
              <div className="flex justify-end"><Button onClick={onClose}>Zavřít</Button></div>
            </>
          ) : (
            <>
              <div style={noteBox('#2563eb', '#eff6ff', '#1e3a8a')}>
                <strong>Samoobslužná pobočka.</strong> Zákazník zadá kód k motorce — ověřte jej a odbavte návrat.
              </div>
              {codeBlock('Odbavit návrat', () => markReturned('self_service_code'))}
            </>
          )
        ) : (
          <>
            <div style={noteBox('#64748b', '#f8fafc', '#334155')}>
              Návrat na obslužné pobočce (nebo svoz) se kódem neodbavuje — řeší se osobně. Potvrďte vrácení ručně.
            </div>
            <div className="flex justify-end gap-3">
              <Button onClick={onClose} disabled={saving}>Zrušit</Button>
              <Button green disabled={saving} onClick={() => markReturned('manual')}>{saving ? 'Ukládám…' : 'Označit jako vrácené'}</Button>
            </div>
          </>
        ))}
      </div>
    </Modal>
  )
}
