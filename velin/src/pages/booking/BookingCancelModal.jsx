import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import { CANCEL_REASONS } from './bookingConstants'

export default function BookingCancelModal({ open, onClose, cancelReason, setCancelReason, cancelReasonCustom, setCancelReasonCustom, onCancel, saving, error, paid, totalPrice, refundMode, setRefundMode }) {
  if (!open) return null
  return (
    <Modal open title="Zrušit rezervaci" onClose={onClose}>
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>Zákazník bude informován emailem. Vyberte důvod zrušení:</p>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Důvod zrušení</label>
      <select value={cancelReason} onChange={e => setCancelReason(e.target.value)} className="w-full rounded-btn text-sm outline-none mb-3" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <option value="">— Vyberte důvod —</option>
        {CANCEL_REASONS.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
      </select>
      {cancelReason === 'admin' && (
        <>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Vlastní důvod</label>
          <textarea value={cancelReasonCustom} onChange={e => setCancelReasonCustom(e.target.value)} rows={3} className="w-full rounded-btn text-sm outline-none mb-3" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }} placeholder="Popište důvod zrušení…" />
        </>
      )}
      {paid && setRefundMode && (
        <>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Vrácení platby</label>
          <div className="rounded-btn mb-3" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <label className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: '#1a2e22' }}>
              <input type="radio" name="cancel-refund-mode" checked={refundMode !== 'none'} onChange={() => setRefundMode('full')} />
              Vrátit platbu — 100 %{Number(totalPrice) > 0 ? ` (${Number(totalPrice).toLocaleString('cs-CZ')} Kč)` : ''}
            </label>
            <label className="flex items-center gap-2 text-sm cursor-pointer mt-1" style={{ color: '#1a2e22' }}>
              <input type="radio" name="cancel-refund-mode" checked={refundMode === 'none'} onChange={() => setRefundMode('none')} />
              Nevracet peníze — storno bez vratky
            </label>
            {refundMode === 'none' && (
              <p className="text-sm mt-2" style={{ color: '#b45309' }}>
                Platba zůstává u nás: neproběhne Stripe vratka, nevystaví se dobropis a rezervace nebude čekat na potvrzení vrácení. Zákazníkovi odejde storno email bez informace o vratce.
              </p>
            )}
          </div>
        </>
      )}
      {error && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{error}</p>}
      <div className="flex justify-end gap-3 mt-2">
        <Button onClick={onClose}>Zpět</Button>
        <Button onClick={onCancel} disabled={saving || !cancelReason || (cancelReason === 'admin' && !cancelReasonCustom)} style={{ background: '#dc2626', color: '#fff', boxShadow: '0 4px 16px rgba(220,38,38,.25)' }}>{saving ? 'Ruším…' : 'Zrušit rezervaci'}</Button>
      </div>
    </Modal>
  )
}
