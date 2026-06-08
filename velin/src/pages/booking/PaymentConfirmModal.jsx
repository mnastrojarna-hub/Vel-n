import { useState } from 'react'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import { MANUAL_PAYMENT_METHODS } from './bookingConstants'

/**
 * Ruční potvrzení platby ve Velínu (QR kód, převod, hotově, krypto…).
 * Po potvrzení projde STEJNÉ flow jako Stripe (confirm_payment + booking_reserved mail),
 * jen platební údaje (způsob, VS, datum úhrady, č. transakce) se doplní ručně a zapíšou
 * do rezervace i do DP / faktur.
 */
export default function PaymentConfirmModal({ open, onClose, onConfirm, saving, error, total }) {
  const today = new Date().toISOString().slice(0, 10)
  const [method, setMethod] = useState('bank_transfer')
  const [vs, setVs] = useState('')
  const [paidDate, setPaidDate] = useState(today)
  const [txRef, setTxRef] = useState('')

  if (!open) return null

  const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
  const labelCls = 'block text-sm font-extrabold uppercase tracking-wide mb-1'

  function submit() {
    onConfirm({
      method,
      vs: vs.trim() || null,
      paid_date: paidDate || today,
      transaction_ref: txRef.trim() || null,
    })
  }

  return (
    <Modal open title="Potvrdit platbu" onClose={onClose}>
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
        Rezervace se označí jako <strong>zaplacená</strong> a přejde do stavu <strong>Nadcházející / Aktivní</strong> (dle data) —
        proběhne stejné flow jako u platby kartou (doklady, e-mail, přístupové kódy).
        {total != null && <> Částka: <strong>{Number(total).toLocaleString('cs-CZ')} Kč</strong>.</>}
      </p>

      <label className={labelCls} style={{ color: '#1a2e22' }}>Způsob platby</label>
      <select value={method} onChange={e => setMethod(e.target.value)}
        className="w-full rounded-btn text-sm outline-none mb-3" style={inputStyle}>
        {MANUAL_PAYMENT_METHODS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
      </select>

      <div className="grid grid-cols-2 gap-3 mb-3">
        <div>
          <label className={labelCls} style={{ color: '#1a2e22' }}>Variabilní symbol</label>
          <input type="text" value={vs} onChange={e => setVs(e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle}
            placeholder="Výchozí = č. dokladu" />
        </div>
        <div>
          <label className={labelCls} style={{ color: '#1a2e22' }}>Datum úhrady</label>
          <input type="date" value={paidDate} onChange={e => setPaidDate(e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>

      <label className={labelCls} style={{ color: '#1a2e22' }}>Číslo transakce <span style={{ fontWeight: 400, textTransform: 'none' }}>(volitelné)</span></label>
      <input type="text" value={txRef} onChange={e => setTxRef(e.target.value)}
        className="w-full rounded-btn text-sm outline-none mb-3" style={inputStyle}
        placeholder="Reference / ID transakce" />

      {error && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{error}</p>}

      <div className="flex justify-end gap-3 mt-2">
        <Button onClick={onClose} disabled={saving}>Zpět</Button>
        <Button onClick={submit} green disabled={saving || !paidDate}>
          {saving ? 'Potvrzuji…' : 'Potvrdit platbu'}
        </Button>
      </div>
    </Modal>
  )
}
