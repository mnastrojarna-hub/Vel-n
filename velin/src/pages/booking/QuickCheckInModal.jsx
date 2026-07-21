import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { logAudit } from './bookingMessageHelpers'
import PickupReadiness from './PickupReadiness'

// Rychlé odbavení kódem motorky (záložka Velín): operátor nemusí hledat, kdo
// přijel — začne 6místným kódem k motorce, který zákazník nadiktuje. Podle kódu
// se dohledá čekající rezervace, doplní se chybějící údaje (čísla dokladů,
// skupiny ŘP) a odbavení končí elektronickým předávacím protokolem, který se
// zákazníkovi odešle e-mailem — stejné flow jako „Odbavit" v Rezervacích.
// Kód je zároveň ověřením identity, v protokolu se už znovu nezadává.

const fmtDay = (s) => {
  const d = (s || '').split('T')[0]
  return d ? new Date(`${d}T00:00:00`).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' }) : '—'
}
const bookingNo = (id) => (id ? '#' + String(id).slice(-8).toUpperCase() : '—')
const inputStyle = { width: '100%', padding: '10px 12px', borderRadius: 10, border: '1px solid #b6dccb', fontSize: 16, fontWeight: 700, letterSpacing: 2 }
const noteBox = (border, bg, color) => ({ border: `2px solid ${border}`, background: bg, color, borderRadius: 10, padding: 12, fontSize: 13 })

// Rezervace čekající na odjezd — ještě nevyzvednutá a neaktivovaná protokolem.
const eligible = (b) => !!b && ['pending', 'reserved'].includes(b.status)
  && !b.picked_up_at && !b.handover_protocol_filled_at

function BookingSummaryBox({ b }) {
  const br = b.motorcycles?.branches
  return (
    <div className="p-3 rounded-card" style={{ background: '#f1faf7', fontSize: 13, color: '#1a2e22' }}>
      <strong>{b.profiles?.full_name || 'Zákazník'}</strong> · {b.motorcycles?.model || '—'}{b.motorcycles?.spz ? ` (${b.motorcycles.spz})` : ''}
      <div className="mt-1" style={{ color: '#64748b' }}>
        {bookingNo(b.id)} · {fmtDay(b.start_date)} – {fmtDay(b.end_date)}
        {b.pickup_method === 'delivery' ? ` · 🚚 ${b.pickup_address || 'na adresu'}` : br?.name ? ` · 🏍️ ${br.name}` : ''}
        {br?.type ? ` (${br.type})` : ''}
      </div>
    </div>
  )
}

export default function QuickCheckInModal({ open, onClose, onDone }) {
  const [codeInput, setCodeInput] = useState('')
  const [searching, setSearching] = useState(false)
  const [error, setError] = useState(null)
  const [candidates, setCandidates] = useState(null) // víc rezervací se stejným kódem — výběr
  const [booking, setBooking] = useState(null)
  const [verifiedCode, setVerifiedCode] = useState('') // kód, kterým byla rezervace nalezena — jde předvyplněný do protokolu
  const [saving, setSaving] = useState(false)

  async function search() {
    const code = codeInput.trim()
    if (!code) return
    setSearching(true); setError(null); setCandidates(null); setBooking(null)
    const { data, error: err } = await supabase.from('branch_door_codes')
      .select('booking_id, created_at, bookings!booking_id(id, user_id, moto_id, status, payment_status, start_date, end_date, pickup_time, picked_up_at, handover_protocol_filled_at, pickup_method, pickup_address, profiles(full_name), motorcycles!moto_id(model, spz, branches(name, type)))')
      .eq('door_code', code).eq('code_type', 'motorcycle')
      .order('created_at', { ascending: false })
    if (err) { setError('Vyhledání selhalo: ' + err.message); setSearching(false); return }
    // Dedup na rezervaci (víc řádků kódů k jedné rezervaci) + jen čekající na odjezd.
    const seen = new Set()
    const found = []
    for (const r of data || []) {
      const b = r.bookings
      if (!b || seen.has(b.id)) continue
      seen.add(b.id)
      found.push(b)
    }
    const waiting = found.filter(eligible)
    setVerifiedCode(code)
    if (waiting.length === 1) setBooking(waiting[0])
    else if (waiting.length > 1) setCandidates(waiting)
    else if (found.length > 0) setError('Rezervace s tímto kódem už je odbavená nebo ukončená. Zkontrolujte ji v Rezervacích.')
    else setError('Kód nenalezen — zkontrolujte ho u zákazníka (6místný kód k motorce z aplikace / e-mailu).')
    setSearching(false)
  }

  // Po podpisu protokolu: aktivace rezervace (vyzvednutí) — stejně jako CheckInModal.
  async function markPickedUp() {
    setSaving(true); setError(null)
    const now = new Date().toISOString()
    const { error: err } = await supabase.from('bookings')
      .update({ status: 'active', picked_up_at: now, handover_protocol_filled_at: now })
      .eq('id', booking.id)
    if (err) { setError('Aktivace rezervace selhala: ' + err.message); setSaving(false); return }
    await logAudit('booking_checkin_pickup', {
      booking_id: booking.id, method: 'moto_code',
      branch_type: booking.motorcycles?.branches?.type || null,
    })
    setSaving(false)
    onDone?.()
  }

  if (!open) return null

  return (
    <Modal open={open} title="Odbavit — kódem motorky" onClose={onClose}>
      <div className="space-y-4">
        {error && <div style={noteBox('#dc2626', '#fee2e2', '#dc2626')}>{error}</div>}

        {!booking && (
          <>
            <div style={noteBox('#2563eb', '#eff6ff', '#1e3a8a')}>
              Požádejte zákazníka o jeho <strong>kód k motorce</strong> (z aplikace / e-mailu).
              Podle kódu se najde rezervace a ověří identita — pak už jen doplníte
              chybějící údaje a podepíšete předávací protokol.
            </div>
            <div>
              <label style={{ fontSize: 12, fontWeight: 700, color: '#1a2e22', display: 'block', marginBottom: 6 }}>
                Kód k motorce od zákazníka
              </label>
              <div className="flex items-center gap-2">
                <input type="text" inputMode="numeric" autoFocus value={codeInput}
                  onChange={e => setCodeInput(e.target.value)}
                  onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); search() } }}
                  style={inputStyle} placeholder="6místný kód" />
                <Button green disabled={searching || !codeInput.trim()} onClick={search}>
                  {searching ? 'Hledám…' : 'Vyhledat'}
                </Button>
              </div>
            </div>
            {candidates && (
              <div className="space-y-2">
                <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>Kódu odpovídá více rezervací — vyberte:</div>
                {candidates.map(b => (
                  <div key={b.id} className="cursor-pointer hover:opacity-80" onClick={() => { setCandidates(null); setBooking(b) }}>
                    <BookingSummaryBox b={b} />
                  </div>
                ))}
              </div>
            )}
            <div className="flex justify-end"><Button onClick={onClose}>Zavřít</Button></div>
          </>
        )}

        {booking && (
          <>
            <div className="flex items-start gap-2">
              <div className="flex-1"><BookingSummaryBox b={booking} /></div>
              <button onClick={() => { setBooking(null); setCodeInput('') }} disabled={saving}
                title="Vyhledat jiný kód" className="cursor-pointer"
                style={{ background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '6px 10px', fontSize: 12, fontWeight: 800, color: '#1a2e22', whiteSpace: 'nowrap' }}>
                ↩ Jiný kód
              </button>
            </div>
            <div className="text-sm font-bold" style={{ color: '#15803d' }}>✓ Kód souhlasí — identita ověřena, v protokolu bude předvyplněný.</div>
            <PickupReadiness booking={booking} verifiedCode={verifiedCode} onClose={onClose} onProtocolDone={markPickedUp} />
          </>
        )}
      </div>
    </Modal>
  )
}
