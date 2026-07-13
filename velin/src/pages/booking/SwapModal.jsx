import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { logAudit } from './bookingMessageHelpers'
import ElectronicProtocolModal from './ElectronicProtocolModal'

// Výměna motorky bez přerušení (handoff / switch) — Model A.
// Zákazník má dvě NAVAZUJÍCÍ rezervace (A do X, B od X+1) na různé motorky.
// Na obslužné pobočce v jedné návštěvě: vrátí A (bez protokolu) a po podpisu
// PŘEDÁVACÍHO PROTOKOLU nové motorky B jede dál.
//
// Kroky:
//   1) Potvrzení vrácení A (jen info, protokol o vrácení se nevyplňuje).
//   2) Předávací protokol B (ElectronicProtocolModal, identita kódem + podpis)
//      → nastaví B.handover_protocol_filled_at.
//   3) Atomický switch swap_handoff_bookings(A, B): A completed, B active.
//
// Aktivaci B pustí DB strážce trg_gate_obsluzna_activation (protokol B vyplněn).

const noteBox = (border, bg, color) => ({ border: `2px solid ${border}`, background: bg, color, borderRadius: 10, padding: 12, fontSize: 13 })
const fmtDay = (s) => (s ? new Date(String(s).split('T')[0] + 'T00:00:00').toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' }) : '—')
const bookingNo = (id) => (id ? '#' + String(id).slice(-8).toUpperCase() : '—')

export default function SwapModal({ open, prev, next, onClose, onDone }) {
  // prev = rezervace A (vrací se), next = rezervace B (přebírá se)
  const [phase, setPhase] = useState('intro') // intro | protocol | swapping
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  if (!open || !prev || !next) return null

  // Po podpisu protokolu B: zamkni protokol (handover_protocol_filled_at),
  // pošli protokol e-mailem (best-effort) a proveď atomický switch.
  async function afterProtocol(info) {
    setPhase('swapping'); setBusy(true); setError(null)
    try {
      // Atomický switch: A completed, B active + vazba řetězu. RPC si sama nastaví
      // B.handover_protocol_filled_at (projde strážcem trg_gate_obsluzna_activation),
      // takže NEPOTŘEBUJEME křehký samostatný frontendový UPDATE před ní (ten mohl
      // při RLS tiše selhat / rozbít pořadí). Vše v jedné transakci RPC.
      const { data, error: e2 } = await supabase.rpc('swap_handoff_bookings', { p_prev: prev.id, p_next: next.id })
      if (e2) throw new Error(e2.message)
      if (data && data.success === false) throw new Error(data.error || 'swap_failed')
      // RPC vrací výsledné stavy — ověř, že se switch reálně provedl (stará→completed,
      // nová→active). Když ne, nahlas přesný stav místo tichého „hotovo".
      if (data && (data.prev_completed === false || data.next_active === false)) {
        throw new Error(
          `switch neproběhl (stará: ${data.prev_status || '?'}, nová: ${data.next_status || '?'})`
        )
      }

      await logAudit('booking_moto_handoff_switch', { prev_booking_id: prev.id, next_booking_id: next.id })

      // 3) Protokol B e-mailem zákazníkovi (best-effort — switch už proběhl).
      try { await sendProtocolEmail(info) } catch (_) { /* nekritické */ }

      setBusy(false)
      onDone?.()
    } catch (e) {
      setBusy(false); setPhase('intro'); setError('Výměna selhala: ' + (e.message || e))
    }
  }

  async function sendProtocolEmail(info) {
    if (!info?.customerEmail) return
    const template_vars = {
      customer_name: info.customerName || '', moto: info.moto || '', moto_model: info.moto || '',
      rental_period: info.rentalPeriod || '', booking_number: info.bookingNumber || '', doc_name: info.docName || '',
    }
    const ext = info.pdfPath && info.pdfPath.toLowerCase().endsWith('.html') ? '.html' : '.pdf'
    const filename = `${(info.docName || 'protokol').replace(/[^\wÀ-ſ]+/g, '_')}${ext}`
    const attachment_paths = info.pdfPath ? [{ filename, path: info.pdfPath }] : []
    const base = { to: info.customerEmail, customer_id: info.customerId || null, booking_id: info.bookingId || null, attachment_paths }
    let res = await supabase.functions.invoke('send-email', { body: { ...base, template_slug: 'handover_protocol_sent', template_vars } })
    const failed = res?.error || (res?.data && res.data.success === false)
    if (failed) {
      await supabase.functions.invoke('send-email', { body: { ...base, template_slug: 'handover_protocol_sent', subject: `${info.docName || 'Předávací protokol'} — MOTO GO 24`, raw_html: info.html } })
    }
  }

  if (phase === 'protocol') {
    return (
      <ElectronicProtocolModal
        open
        type="handover_protocol"
        bookingId={next.id}
        onClose={() => setPhase('intro')}
        onSaved={(info) => afterProtocol(info)}
      />
    )
  }

  return (
    <Modal open={open} title="Výměna motorky (bez přerušení)" onClose={busy ? undefined : onClose}>
      <div className="space-y-4">
        {error && <div style={noteBox('#dc2626', '#fee2e2', '#dc2626')}>{error}</div>}

        <div style={noteBox('#2563eb', '#eff6ff', '#1e3a8a')}>
          <strong>Obslužná pobočka — výměna motorky.</strong> Zákazník vrací jednu motorku a bez přerušení
          přebírá druhou. Po podpisu předávacího protokolu nové motorky proběhne switch automaticky
          (stará se uvolní, nová se aktivuje).
        </div>

        {/* Vrácená motorka A */}
        <div className="p-3 rounded-card" style={{ background: '#fff7ed', border: '1px solid #fed7aa' }}>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#b45309' }}>⬅️ Vrací se</div>
          <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{prev.motorcycles?.model || '—'}{prev.motorcycles?.spz ? ` · ${prev.motorcycles.spz}` : ''}</div>
          <div className="text-sm" style={{ color: '#64748b' }}>{bookingNo(prev.id)} · do {fmtDay(prev.end_date)}</div>
        </div>

        {/* Přebíraná motorka B */}
        <div className="p-3 rounded-card" style={{ background: '#f0fdf4', border: '1px solid #bbf7d0' }}>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#15803d' }}>➡️ Přebírá se</div>
          <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{next.motorcycles?.model || '—'}{next.motorcycles?.spz ? ` · ${next.motorcycles.spz}` : ''}</div>
          <div className="text-sm" style={{ color: '#64748b' }}>{bookingNo(next.id)} · od {fmtDay(next.start_date)}</div>
        </div>

        <div className="p-3 rounded-card" style={{ background: '#f8faf9', border: '1px solid #eef5f1', fontSize: 13, color: '#1a2e22' }}>
          Vrácení první motorky se protokolem nevyplňuje — stačí ji fyzicky převzít. Jediný podpisový úkon
          je <strong>předávací protokol nové motorky</strong>.
        </div>

        <div className="flex justify-end gap-3">
          <Button onClick={onClose} disabled={busy}>Zrušit</Button>
          <Button green disabled={busy} onClick={() => { setError(null); setPhase('protocol') }}>
            {busy ? 'Provádím…' : '✍️ Podepsat protokol nové motorky a vyměnit'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}
