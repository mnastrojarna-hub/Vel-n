import { useState, useEffect } from 'react'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import { CANCEL_REASONS } from './bookingConstants'
import RefundAmountPicker, { refundAmountValid } from './RefundAmountPicker'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

// Storno modal: u ZAPLACENÉ rezervace se NEJDŘÍV volí výše vratky (rychlé volby
// 100/50/0 % + ručně editovatelná % i částka v Kč, obousměrně provázané), pak
// důvod. onCancel dostane { amount } — storno se provede přesně dle zadané
// částky (plná / částečná / žádná vratka).
export default function BookingCancelModal({ open, onClose, cancelReason, setCancelReason, cancelReasonCustom, setCancelReasonCustom, onCancel, saving, error, paid, totalPrice }) {
  const total = Math.max(0, Math.round(Number(totalPrice) || 0))
  const [refund, setRefund] = useState({ pct: '100', amount: '0' })
  useEffect(() => { if (open) setRefund({ pct: '100', amount: String(total) }) }, [open, total])
  if (!open) return null

  const amountNum = Math.round(Number(refund.amount))
  const amountValid = !paid || refundAmountValid(refund.amount, total)

  return (
    <Modal open title="Zrušit rezervaci" onClose={onClose}>
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>Zákazník bude informován emailem.</p>
      {paid && (
        <>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>1. Vrácení platby (zaplaceno {total.toLocaleString('cs-CZ')} Kč)</label>
          <div className="rounded-btn mb-3" style={inputStyle}>
            <RefundAmountPicker total={total} pct={refund.pct} amount={refund.amount} onChange={setRefund} />
            {!amountValid && (
              <p className="text-sm mt-2" style={{ color: '#dc2626' }}>Částka musí být mezi 0 a {total.toLocaleString('cs-CZ')} Kč.</p>
            )}
            {amountValid && amountNum === 0 && (
              <p className="text-sm mt-2" style={{ color: '#b45309' }}>
                Storno bez vratky — platba zůstává u nás: neproběhne Stripe vratka, nevystaví se dobropis a rezervace nebude čekat na potvrzení vrácení. Zákazníkovi odejde storno email bez informace o vratce.
              </p>
            )}
            {amountValid && amountNum > 0 && amountNum < total && (
              <p className="text-sm mt-2" style={{ color: '#b45309' }}>
                Částečná vratka {amountNum.toLocaleString('cs-CZ')} Kč — u Stripe platby se vrátí na kartu, u QR/převodu/hotovosti se vystaví dobropis a vratku pošlete převodem na účet (tlačítko „Vratka odeslána" v detailu).
              </p>
            )}
          </div>
        </>
      )}
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{paid ? '2. ' : ''}Důvod zrušení</label>
      <select value={cancelReason} onChange={e => setCancelReason(e.target.value)} className="w-full rounded-btn text-sm outline-none mb-3" style={inputStyle}>
        <option value="">— Vyberte důvod —</option>
        {CANCEL_REASONS.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
      </select>
      {cancelReason === 'admin' && (
        <>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Vlastní důvod</label>
          <textarea value={cancelReasonCustom} onChange={e => setCancelReasonCustom(e.target.value)} rows={3} className="w-full rounded-btn text-sm outline-none mb-3" style={{ ...inputStyle, resize: 'vertical' }} placeholder="Popište důvod zrušení…" />
        </>
      )}
      {error && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{error}</p>}
      <div className="flex justify-end gap-3 mt-2">
        <Button onClick={onClose}>Zpět</Button>
        <Button onClick={() => onCancel(paid ? { amount: Math.min(total, Math.max(0, amountNum)) } : {})}
          disabled={saving || !cancelReason || (cancelReason === 'admin' && !cancelReasonCustom) || !amountValid}
          style={{ background: '#dc2626', color: '#fff', boxShadow: '0 4px 16px rgba(220,38,38,.25)' }}>
          {saving ? 'Ruším…' : paid ? (amountNum > 0 ? `Zrušit a vrátit ${Math.min(total, Math.max(0, amountNum)).toLocaleString('cs-CZ')} Kč` : 'Zrušit bez vratky') : 'Zrušit rezervaci'}
        </Button>
      </div>
    </Modal>
  )
}
