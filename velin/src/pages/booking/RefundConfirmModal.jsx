import { useState, useEffect } from 'react'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import RefundAmountPicker, { refundAmountValid } from './RefundAmountPicker'

const boxStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

// Potvrzení vrácení platby u ZRUŠENÉ rezervace (Čeká na vrácení / Částečně
// vráceno) — tlačítko vedle „Obnovit". Admin zvolí výši vratky (100/50/0 % nebo
// ručně % / Kč), potvrzením se: u Stripe platby vratka reálně provede, u
// QR/převodu/hotovosti vystaví dobropis (peníze posílá admin převodem) a
// zákazníkovi odejde storno email ze šablony s přiloženým dobropisem.
// onConfirm dostane { amount }.
export default function RefundConfirmModal({ open, onClose, totalPrice, defaultAmount, saving, error, onConfirm }) {
  const total = Math.max(0, Math.round(Number(totalPrice) || 0))
  const [refund, setRefund] = useState({ pct: '100', amount: '0' })
  useEffect(() => {
    if (!open) return
    const def = Math.min(total, Math.max(0, Math.round(Number(defaultAmount) || 0))) || total
    setRefund({ pct: total > 0 ? String(Math.round(def / total * 100)) : '0', amount: String(def) })
  }, [open, total, defaultAmount])
  if (!open) return null

  const amountNum = Math.round(Number(refund.amount))
  const amountValid = refundAmountValid(refund.amount, total)
  const clamped = Math.min(total, Math.max(0, amountNum))

  return (
    <Modal open title="Potvrdit vrácení platby" onClose={onClose}>
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
        Zvolte výši vratky ke zrušené rezervaci. U platby kartou (Stripe) se částka vrátí na kartu automaticky; u QR / převodu / hotovosti se vystaví dobropis a částku pošlete převodem na účet zákazníka. Zákazníkovi odejde storno email s přiloženým dobropisem. Částka se automaticky omezí na dosud nevrácenou část platby.
      </p>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Výše vratky (zaplaceno {total.toLocaleString('cs-CZ')} Kč)</label>
      <div className="rounded-btn mb-3" style={boxStyle}>
        <RefundAmountPicker total={total} pct={refund.pct} amount={refund.amount} onChange={setRefund} />
        {!amountValid && (
          <p className="text-sm mt-2" style={{ color: '#dc2626' }}>Částka musí být mezi 0 a {total.toLocaleString('cs-CZ')} Kč.</p>
        )}
        {amountValid && amountNum === 0 && (
          <p className="text-sm mt-2" style={{ color: '#b45309' }}>
            Potvrzení BEZ vratky — peníze zůstávají u nás, rezervace se označí „Zaplaceno · bez vratky" a zákazníkovi odejde storno email bez dobropisu.
          </p>
        )}
      </div>
      {error && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{error}</p>}
      <div className="flex justify-end gap-3 mt-2">
        <Button onClick={onClose}>Zpět</Button>
        <Button onClick={() => onConfirm({ amount: clamped })} disabled={saving || !amountValid}
          style={{ background: '#1a8a18', color: '#fff', boxShadow: '0 4px 16px rgba(26,138,24,.25)' }}>
          {saving ? 'Potvrzuji…' : amountNum > 0 ? `Potvrdit vrácení ${clamped.toLocaleString('cs-CZ')} Kč (${refund.pct} %)` : 'Potvrdit storno bez vratky'}
        </Button>
      </div>
    </Modal>
  )
}
