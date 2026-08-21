import { useState, useEffect } from 'react'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import { CANCEL_REASONS } from './bookingConstants'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

// Storno modal: u ZAPLACENÉ rezervace se NEJDŘÍV volí výše vratky (rychlé volby
// 100/50/0 % + ručně editovatelná % i částka v Kč, obousměrně provázané), pak
// důvod. onCancel dostane { amount } — storno se provede přesně dle zadané
// částky (plná / částečná / žádná vratka).
export default function BookingCancelModal({ open, onClose, cancelReason, setCancelReason, cancelReasonCustom, setCancelReasonCustom, onCancel, saving, error, paid, totalPrice }) {
  const total = Math.max(0, Math.round(Number(totalPrice) || 0))
  const [pct, setPct] = useState('100')
  const [amount, setAmount] = useState('0')
  useEffect(() => { if (open) { setPct('100'); setAmount(String(total)) } }, [open, total])
  if (!open) return null

  const amountNum = Math.round(Number(amount))
  const amountValid = !paid || (Number.isFinite(amountNum) && amountNum >= 0 && amountNum <= total)

  const applyPct = (p) => {
    const pc = Math.min(100, Math.max(0, Math.round(Number(p) || 0)))
    setPct(String(pc))
    setAmount(String(Math.round(total * pc / 100)))
  }
  const applyAmount = (a) => {
    setAmount(a)
    const an = Number(a)
    if (total > 0 && Number.isFinite(an)) setPct(String(Math.round(Math.min(100, Math.max(0, an / total * 100)))))
  }

  return (
    <Modal open title="Zrušit rezervaci" onClose={onClose}>
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>Zákazník bude informován emailem.</p>
      {paid && (
        <>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>1. Vrácení platby (zaplaceno {total.toLocaleString('cs-CZ')} Kč)</label>
          <div className="rounded-btn mb-3" style={inputStyle}>
            <div className="flex gap-2 mb-2">
              {[100, 50, 0].map(p => (
                <button key={p} type="button" onClick={() => applyPct(p)}
                  className="rounded-btn text-sm font-extrabold cursor-pointer"
                  style={{ padding: '6px 14px', border: '1px solid #d4e8e0', background: Number(pct) === p && amountNum === Math.round(total * p / 100) ? '#74FB71' : '#fff', color: '#1a2e22' }}>
                  {p} %
                </button>
              ))}
            </div>
            <div className="flex items-center gap-3">
              <label className="flex items-center gap-1 text-sm" style={{ color: '#1a2e22' }}>
                <input type="number" min="0" max="100" step="1" value={pct} onChange={e => applyPct(e.target.value)}
                  className="rounded-btn text-sm outline-none" style={{ ...inputStyle, background: '#fff', width: 70, padding: '6px 8px' }} />
                %
              </label>
              <label className="flex items-center gap-1 text-sm" style={{ color: '#1a2e22' }}>
                <input type="number" min="0" max={total} step="1" value={amount} onChange={e => applyAmount(e.target.value)}
                  className="rounded-btn text-sm outline-none" style={{ ...inputStyle, background: '#fff', width: 110, padding: '6px 8px' }} />
                Kč
              </label>
            </div>
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
