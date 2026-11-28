import { useState, useEffect, useCallback, useRef } from 'react'
import Modal from '../../../components/ui/Modal'
import Badge from '../../../components/ui/Badge'
import Button from '../../../components/ui/Button'
import { loadMovement, loadTargets, loadHistory, loadAdminName } from './bankApi'
import { TODO_STATUSES, statusOf, reasonText, needsStaff, followupOpen, FOLLOWUP, fmtMoney, fmtDate } from './bankFormat'
import { MovementFields, MovementTarget, MovementHistory, MovementRaw } from './BankDetailInfo'
import BankSuggestions from './BankSuggestions'
import BankDetailActions from './BankDetailActions'
import BankPairDialog from './BankPairDialog'

// Detail bankovního pohybu: všechna pole + surová data, k čemu je přiřazený, historie a akce obsluhy.
// Nevyřešená příchozí platba: návrhy ke spárování (jedno tlačítko + potvrzení), ruční hledání, ignorovat.
export default function BankMovementDetail({ fioId, tick, orderNumbers, notify, onClose, onChanged }) {
  const [tx, setTx] = useState(null)
  const [state, setState] = useState('loading') // loading | ready | error | gone
  const [targets, setTargets] = useState({ booking: null, order: null, request: null })
  const [history, setHistory] = useState([])
  const [resolver, setResolver] = useState('')
  const [pair, setPair] = useState(null) // { target, accept }
  const seq = useRef(0)

  const load = useCallback(async () => {
    const my = ++seq.current
    const r = await loadMovement(fioId)
    if (my !== seq.current) return
    if (!r.ok) { setState(s => (s === 'ready' ? s : 'error')); return }
    if (!r.row) { setState('gone'); return }
    setTx(r.row); setState('ready')
    const [t, h, who] = await Promise.all([loadTargets(r.row), loadHistory(fioId), loadAdminName(r.row.resolved_by)])
    if (my !== seq.current) return
    setTargets(t); setHistory(h); setResolver(who)
  }, [fioId])

  useEffect(() => { load() }, [load])
  useEffect(() => { if (tick && !pair) load() }, [tick]) // eslint-disable-line react-hooks/exhaustive-deps

  const incoming = tx && Number(tx.amount) > 0
  const st = statusOf(tx?.status)
  const canPair = tx && incoming && TODO_STATUSES.includes(tx.status)

  function afterAction({ close, text }) {
    notify('ok', text)
    onChanged()
    if (close) onClose(); else load()
  }

  return (
    <>
    <Modal open wide stickyHeader onClose={onClose} title={tx ? `Pohyb na účtu · ${fmtDate(tx.tx_date)}` : 'Pohyb na účtu'}>
      {state === 'loading' && <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>}
      {state === 'error' && <p style={{ fontSize: 13, color: '#b45309' }}>Pohyb se nepodařilo načíst — zavřete okno a zkuste to znovu.</p>}
      {state === 'gone' && <p style={{ fontSize: 13, color: '#1a2e22' }}>Pohyb už v seznamu není.</p>}

      {state === 'ready' && tx && (
        <div data-bank="detail" data-status={tx.status}>
          <div className="flex flex-wrap items-center gap-3 mb-3">
            <span className="text-2xl font-black tracking-tight" style={{ color: incoming ? '#1a8a18' : '#4a6357' }}>
              {incoming ? '+' : ''}{fmtMoney(tx.amount, tx.currency)}
            </span>
            <Badge label={st.label} color={st.color} bg={st.bg} />
            {followupOpen(tx) && <Badge label={FOLLOWUP[tx.followup] || 'Úkol'} color="#b45309" bg="#fef3c7" />}
          </div>
          {needsStaff(tx) && reasonText(tx) && (
            <div className="mb-4 p-3 rounded-card" style={{ background: '#fef3c7', color: '#92400e', fontSize: 13, lineHeight: 1.55 }} data-bank="reason">
              <b>Co s tím:</b> {reasonText(tx)}
            </div>
          )}
          {tx.status === 'new' && (
            <div className="mb-4 p-3 rounded-card" style={{ background: '#dbeafe', color: '#1e40af', fontSize: 13 }}>
              Pohyb čeká na zpracování — automat ho vyhodnotí při nejbližší synchronizaci (do minuty).
            </div>
          )}

          <MovementFields tx={tx} />
          <MovementTarget tx={tx} targets={targets} orderNumbers={orderNumbers} />

          {canPair && (
            <div className="mt-5 pt-4" style={{ borderTop: '1px solid #d4e8e0' }}>
              <BankSuggestions tx={tx} onPair={(target) => setPair({ target, accept: false })} />
            </div>
          )}

          <BankDetailActions tx={tx} targets={targets} orderNumbers={orderNumbers}
            onPair={(target, accept) => setPair({ target, accept })} onDone={afterAction} />

          <MovementHistory tx={tx} history={history} resolver={resolver} />
          <MovementRaw raw={tx.raw} />

          <div className="flex justify-end mt-5">
            <Button onClick={onClose}>Zavřít</Button>
          </div>
        </div>
      )}
    </Modal>
    {pair && tx && (
      <BankPairDialog tx={tx} target={pair.target} startAccept={pair.accept}
        onClose={(touched) => { setPair(null); if (touched) { onChanged(); load() } }}
        onDone={({ text }) => { setPair(null); afterAction({ close: true, text }) }} />
    )}
    </>
  )
}
