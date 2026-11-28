import { useState } from 'react'
import Button from '../../../components/ui/Button'
import { ignoreMovement, reopenMovement, processMovement, ackFollowup } from './bankApi'
import { TODO_STATUSES, errorText, followupOpen, fmtMoney, shortId, statusOf } from './bankFormat'

/** Cíl, ke kterému už server pohyb přiřadil (nižší částka, úprava po lhůtě…) — pro opakované spárování. */
export function knownTarget(tx, targets = {}, orderNumbers = {}) {
  const type = tx.target_type || (tx.request_id ? 'request' : tx.order_id ? 'order' : tx.booking_id ? 'booking' : null)
  const id = type === 'request' ? tx.request_id : type === 'order' ? tx.order_id : tx.booking_id
  if (!type || !id) return null
  const b = targets.booking
  const o = targets.order
  const r = targets.request
  const num = shortId(tx.booking_id)
  const base = { target_type: type, target_id: id, booking_id: tx.booking_id || null, order_id: tx.order_id || null, request_id: tx.request_id || null,
    amount: tx.expected_amount ?? null, source: 'known' }
  if (type === 'order') return { ...base, kind: 'shop_order', label: `Objednávka ${o?.order_number || orderNumbers[tx.order_id] || ''}`.trim(), customer_name: o?.customer_name || null, amount: base.amount ?? o?.total ?? null }
  if (type === 'request') {
    const state = tx.reason_code === 'request_expired' ? 'expired' : tx.reason_code === 'request_cancelled' ? 'cancelled' : 'waiting'
    if (r?.kind === 'shop_order' || (!tx.booking_id && tx.order_id)) return { ...base, kind: 'voucher', label: `Objednávka ${o?.order_number || orderNumbers[tx.order_id] || ''}`.trim(), amount: base.amount ?? r?.amount ?? null, state }
    return { ...base, kind: 'booking_change', label: `Úprava rezervace #${num}`, customer_name: b?.profiles?.full_name || null, amount: base.amount ?? r?.amount ?? null, vs: r?.vs || null, state }
  }
  if (type === 'surcharge') return { ...base, kind: 'surcharge', label: `Doplatek rezervace #${num}`, customer_name: b?.profiles?.full_name || null }
  return { ...base, kind: b?.booking_kind === 'gear' ? 'gear' : 'booking', label: `${b?.booking_kind === 'gear' ? 'Výpůjčka výbavy' : 'Rezervace'} #${num}`,
    customer_name: b?.profiles?.full_name || null, amount: base.amount ?? b?.total_price ?? null }
}

// Akce obsluhy nad pohybem: ignorovat (povinná poznámka), vrátit k vyřešení, přijmout nižší částku,
// provést úpravu po lhůtě, odškrtnout vrácený přeplatek. Vše přes auditované RPC / akce fio-sync.
export default function BankDetailActions({ tx, targets, orderNumbers, onPair, onDone }) {
  const [mode, setMode] = useState(null) // null | ignore | ack
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(null)
  const [error, setError] = useState(null)

  const todo = TODO_STATUSES.includes(tx.status)
  const known = knownTarget(tx, targets, orderNumbers)
  const fail = (r) => setError(r.missing ? 'Akce bude dostupná po nasazení databázové části.' : r.lost ? 'Akce se nezdařila — zkontrolujte připojení a zkuste to znovu.' : errorText(r.code))
  const open = (m) => { setMode(m); setNote(''); setError(null) }

  async function doIgnore() {
    if (!note.trim()) { setError('Napište poznámku, proč se pohyb ignoruje (např. úrok, vlastní převod, vráceno ručně).'); return }
    setBusy('ignore'); setError(null)
    const r = await ignoreMovement(tx.fio_id, note.trim())
    setBusy(null)
    if (!r.ok) { fail(r); return }
    onDone({ close: true, text: 'Pohyb je označený jako ignorovaný.' })
  }
  async function doAck() {
    setBusy('ack'); setError(null)
    const r = await ackFollowup(tx.fio_id, note.trim() || null)
    setBusy(null)
    if (!r.ok) { fail(r); return }
    onDone({ close: true, text: 'Přeplatek je označený jako vrácený.' })
  }
  async function doReopen() {
    setBusy('reopen'); setError(null)
    const r = await reopenMovement(tx.fio_id)
    if (!r.ok) { setBusy(null); fail(r); return }
    const p = await processMovement(tx.fio_id) // hned zpracovat; když to nejde, dokončí to nejbližší synchronizace
    setBusy(null)
    const st = p.ok ? p.data.result?.status : null
    onDone({ close: false, text: st && st !== 'new' ? `Pohyb byl znovu zpracován — výsledek: ${statusOf(st).label}.`
      : 'Pohyb je vrácený ke zpracování — automat ho zkusí znovu spárovat při nejbližší synchronizaci (do minuty).' })
  }

  if (!todo && tx.status !== 'ignored' && !followupOpen(tx)) return null
  const ta = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 10, outline: 'none', fontSize: 14, color: '#1a2e22', width: '100%', minHeight: 70 }
  const amber = { background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }

  return (
    <div className="mt-4 pt-4" style={{ borderTop: '1px solid #d4e8e0' }} data-bank="actions">
      {mode === null && (
        <div className="flex flex-wrap gap-2">
          {todo && tx.status === 'amount_mismatch' && known && (
            <Button small style={amber} onClick={() => onPair(known, true)} className="max-lg:min-h-[36px]">Přijmout nižší částku…</Button>
          )}
          {todo && ['request_expired', 'request_cancelled'].includes(tx.reason_code) && known?.target_type === 'request' && (
            <Button small style={amber} onClick={() => onPair(known, false)} className="max-lg:min-h-[36px]">Přesto provést úpravu…</Button>
          )}
          {followupOpen(tx) && <Button small green onClick={() => open('ack')} className="max-lg:min-h-[36px]">Přeplatek vrácen…</Button>}
          {todo && <Button small onClick={() => open('ignore')} className="max-lg:min-h-[36px]">Ignorovat…</Button>}
          {todo && (
            <Button small onClick={doReopen} disabled={busy === 'reopen'} className="max-lg:min-h-[36px]">
              {busy === 'reopen' ? 'Zpracovávám…' : 'Zkusit spárovat znovu'}
            </Button>
          )}
          {tx.status === 'ignored' && (
            <Button small green onClick={doReopen} disabled={busy === 'reopen'} className="max-lg:min-h-[36px]">
              {busy === 'reopen' ? 'Vracím…' : 'Vrátit k vyřešení'}
            </Button>
          )}
        </div>
      )}

      {mode === 'ignore' && (
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }} htmlFor="bank-ignore-note">Poznámka (povinná) — proč se pohyb ignoruje</label>
          <textarea id="bank-ignore-note" value={note} onChange={e => setNote(e.target.value)} maxLength={500} style={ta}
            placeholder="Např. připsaný úrok, vlastní převod mezi účty, platba vrácena ručně 27. 11. …" />
          <div className="flex flex-wrap justify-end gap-2 mt-2">
            <Button small onClick={() => open(null)} disabled={!!busy}>Zrušit</Button>
            <Button small onClick={doIgnore} disabled={!!busy} style={{ background: '#1a2e22', color: '#74FB71', border: 'none' }}>{busy ? 'Ukládám…' : 'Ignorovat pohyb'}</Button>
          </div>
        </div>
      )}

      {mode === 'ack' && (
        <div>
          <p className="mb-2" style={{ fontSize: 13, color: '#1a2e22', lineHeight: 1.55 }}>
            Potvrďte až po vrácení rozdílu zákazníkovi{tx.expected_amount != null ? ` (${fmtMoney(Number(tx.amount) - Number(tx.expected_amount))})` : ''} — pohyb pak zmizí ze seznamu „K vyřešení“.
          </p>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }} htmlFor="bank-ack-note">Poznámka (nepovinná)</label>
          <textarea id="bank-ack-note" value={note} onChange={e => setNote(e.target.value)} maxLength={500} style={ta} placeholder="Např. vráceno převodem 27. 11." />
          <div className="flex flex-wrap justify-end gap-2 mt-2">
            <Button small onClick={() => open(null)} disabled={!!busy}>Zrušit</Button>
            <Button small green onClick={doAck} disabled={!!busy}>{busy ? 'Ukládám…' : 'Přeplatek je vrácený'}</Button>
          </div>
        </div>
      )}

      {error && <div className="mt-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
    </div>
  )
}
