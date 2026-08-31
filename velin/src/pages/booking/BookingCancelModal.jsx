import { useState, useEffect } from 'react'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import { CANCEL_REASONS } from './bookingConstants'
import RefundAmountPicker, { refundAmountValid } from './RefundAmountPicker'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

// Storno modal: u ZAPLACENÉ rezervace se NEJDŘÍV povinně volí režim vratky —
// „S vratkou peněz a dobropisem" vs. „Bez vratky a dobropisu". Volba NENÍ
// předvyplněná: admin ji musí udělat vědomě u KAŽDÉHO storna, bez ohledu na
// zvolený důvod. U režimu s vratkou se pak volí výše (rychlé volby 100/50 % +
// ručně editovatelná % i částka v Kč, obousměrně provázané, musí být > 0).
// Pak důvod. onCancel dostane { amount } — storno se provede přesně dle zadané
// částky (plná / částečná vratka, 0 = bez vratky a dobropisu).
export default function BookingCancelModal({ open, onClose, cancelReason, setCancelReason, cancelReasonCustom, setCancelReasonCustom, onCancel, saving, error, paid, totalPrice }) {
  const total = Math.max(0, Math.round(Number(totalPrice) || 0))
  // refundMode: null = zatím nevybráno (nutná vědomá volba), 'refund' = s vratkou
  // a dobropisem, 'none' = bez vratky i dobropisu.
  const [refundMode, setRefundMode] = useState(null)
  const [refund, setRefund] = useState({ pct: '100', amount: '0' })
  useEffect(() => { if (open) { setRefundMode(null); setRefund({ pct: '100', amount: String(total) }) } }, [open, total])
  if (!open) return null

  const amountNum = Math.round(Number(refund.amount))
  // V režimu 's vratkou' musí být částka > 0 — nulová vratka se volí výhradně
  // tlačítkem „Bez vratky a dobropisu", aby volba nešla obejít omylem.
  const amountValid = !paid || refundMode === 'none' || (refundAmountValid(refund.amount, total) && amountNum > 0)
  const modeChosen = !paid || refundMode !== null
  const finalAmount = refundMode === 'none' ? 0 : Math.min(total, Math.max(0, amountNum))

  const modeBtnStyle = (active, activeBg) => ({
    padding: '10px 14px', border: active ? '2px solid #1a2e22' : '1px solid #d4e8e0',
    background: active ? activeBg : '#fff', color: '#1a2e22', textAlign: 'left', flex: 1,
  })

  return (
    <Modal open title="Zrušit rezervaci" onClose={onClose}>
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>Zákazník bude informován emailem.</p>
      {paid && (
        <>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>1. Vrácení platby (zaplaceno {total.toLocaleString('cs-CZ')} Kč)</label>
          <div className="flex gap-2 mb-3">
            <button type="button" onClick={() => { setRefundMode('refund'); setRefund({ pct: '100', amount: String(total) }) }}
              className="rounded-btn text-sm font-extrabold cursor-pointer" style={modeBtnStyle(refundMode === 'refund', '#74FB71')}>
              S vratkou peněz a dobropisem
            </button>
            <button type="button" onClick={() => setRefundMode('none')}
              className="rounded-btn text-sm font-extrabold cursor-pointer" style={modeBtnStyle(refundMode === 'none', '#fde68a')}>
              Bez vratky a dobropisu
            </button>
          </div>
          {!modeChosen && (
            <p className="text-sm mb-3" style={{ color: '#b45309' }}>Vyberte, zda rezervaci zrušit s vratkou peněz a dobropisem, nebo bez — bez této volby nelze storno provést.</p>
          )}
          {refundMode === 'refund' && (
            <div className="rounded-btn mb-3" style={inputStyle}>
              <RefundAmountPicker total={total} pct={refund.pct} amount={refund.amount} onChange={setRefund} />
              {!amountValid && (
                <p className="text-sm mt-2" style={{ color: '#dc2626' }}>Částka vratky musí být mezi 1 a {total.toLocaleString('cs-CZ')} Kč. Pro storno bez vratky použijte volbu „Bez vratky a dobropisu".</p>
              )}
              {amountValid && amountNum > 0 && amountNum < total && (
                <p className="text-sm mt-2" style={{ color: '#b45309' }}>
                  Částečná vratka {amountNum.toLocaleString('cs-CZ')} Kč — u Stripe platby se vrátí na kartu, u QR/převodu na Fio účet se odešle automaticky převodem přes Fio API; u ostatních (hotovost, platba mimo Fio) se vystaví dobropis a vratku pošlete převodem na účet (tlačítko „Vratka odeslána" v detailu).
                </p>
              )}
            </div>
          )}
          {refundMode === 'none' && (
            <p className="text-sm mb-3" style={{ color: '#b45309' }}>
              Storno bez vratky — platba zůstává u nás: neproběhne Stripe vratka, nevystaví se dobropis a rezervace nebude čekat na potvrzení vrácení. Zákazníkovi odejde storno email bez informace o vratce.
            </p>
          )}
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
        <Button onClick={() => onCancel(paid ? { amount: finalAmount } : {})}
          disabled={saving || !cancelReason || (cancelReason === 'admin' && !cancelReasonCustom) || !modeChosen || !amountValid}
          style={{ background: '#dc2626', color: '#fff', boxShadow: '0 4px 16px rgba(220,38,38,.25)' }}>
          {saving ? 'Ruším…' : paid && modeChosen ? (refundMode === 'none' ? 'Zrušit bez vratky' : `Zrušit a vrátit ${finalAmount.toLocaleString('cs-CZ')} Kč`) : 'Zrušit rezervaci'}
        </Button>
      </div>
    </Modal>
  )
}
