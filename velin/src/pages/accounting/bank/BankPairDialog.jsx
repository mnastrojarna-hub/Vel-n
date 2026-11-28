import { useState } from 'react'
import Modal from '../../../components/ui/Modal'
import Button from '../../../components/ui/Button'
import { pairMovement } from './bankApi'
import { errorText, fmtMoney, reasonText, statusOf, MATCHED_STATUSES } from './bankFormat'

/** Co přesně spárování udělá — věta do potvrzovacího dialogu podle druhu cíle. */
export function pairEffect(t) {
  const label = t.label || 'vybraný záznam'
  if (t.target_type === 'surcharge' || t.kind === 'surcharge') {
    return `${label}: doplatek se označí jako zaplacený, vystaví se doklady a zákazníkovi odejde e-mail o úpravě rezervace.`
  }
  if (t.kind === 'booking_change' || (t.target_type === 'request' && !t.order_id)) {
    return `${label}: zaplacená úprava se zapíše do rezervace (termín / motorka / výbava podle požadavku zákazníka), vystaví se doklady a zákazníkovi odejde e-mail o úpravě.`
  }
  if (t.target_type === 'order' || t.kind === 'voucher' || t.kind === 'shop_order' || t.order_id) {
    return `${label}: objednávka se označí jako zaplacená, vystaví se doklady a zákazníkovi odejde potvrzovací e-mail${t.kind === 'shop_order' ? '' : ' (u dárkového poukazu i samotný poukaz)'}.`
  }
  return `${label}: rezervace se potvrdí jako zaplacená, vystaví se doklady a zákazníkovi odejde potvrzovací e-mail.`
}

const Line = ({ k, children }) => (
  <div className="flex justify-between gap-3 py-1" style={{ fontSize: 13, borderBottom: '1px solid #e2ece7' }}>
    <span className="font-extrabold uppercase tracking-wide" style={{ fontSize: 11, color: '#4a6357' }}>{k}</span>
    <span className="font-bold text-right" style={{ color: '#0f1a14', overflowWrap: 'anywhere' }}>{children}</span>
  </div>
)
const Box = ({ tone, children }) => {
  const c = tone === 'bad' ? ['#fee2e2', '#dc2626'] : tone === 'ok' ? ['#dcfce7', '#1a8a18'] : ['#fef3c7', '#92400e']
  return <div className="mb-4 p-3 rounded-card" style={{ background: c[0], color: c[1], fontSize: 13, lineHeight: 1.55 }}>{children}</div>
}

// Potvrzení spárování jedním kliknutím (edge fio-sync, akce pair). Nic se nespáruje bez výslovného potvrzení;
// nižší částku lze přijmout až po odpovědi serveru „přišlo méně“ a druhým výslovným potvrzením (accept_amount).
export default function BankPairDialog({ tx, target, startAccept = false, onClose, onDone }) {
  const [step, setStep] = useState(startAccept ? 'accept' : 'confirm') // confirm | mismatch | accept | problem
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [result, setResult] = useState(null)
  const [touched, setTouched] = useState(false)

  const received = Number(tx.amount)
  const expected = result?.expected_amount ?? target.amount ?? tx.expected_amount ?? null
  const diff = expected !== null && expected !== undefined ? Math.round((received - Number(expected)) * 100) / 100 : null
  const close = () => { if (!busy) onClose(touched) }

  async function run(accept) {
    setBusy(true); setError(null)
    const r = await pairMovement({
      fioId: tx.fio_id, targetType: target.target_type, targetId: target.target_id, acceptAmount: accept,
      note: accept ? 'Velín: přijata nižší částka' : target.source === 'suggest' ? 'Velín: spárováno z návrhu' : 'Velín: spárováno ručním výběrem',
    })
    setBusy(false)
    if (!r.ok) {
      if (r.lost) { setTouched(true); setError('Odpověď serveru nedorazila. Pokud se spárování stihlo zapsat, dokončí se samo při nejbližší synchronizaci (do minuty) — zkontrolujte pohyb v seznamu.'); return }
      setError(r.missing ? 'Spárování bude dostupné po nasazení serverové části.' : errorText(r.code))
      return
    }
    setTouched(true)
    const res = r.data.result || {}
    setResult(res)
    if (MATCHED_STATUSES.includes(res.status)) {
      const over = res.followup === 'overpaid' || res.reason_code === 'overpaid'
      onDone({ text: `Platba ${fmtMoney(tx.amount, tx.currency)} spárována — ${target.label || 'cíl'} potvrzen, doklady a e-mail zákazníkovi se odesílají.${over ? ' Přišlo víc, než se čekalo — rozdíl vraťte zákazníkovi.' : ''}` })
    } else if (res.status === 'new') {
      onDone({ text: 'Spárování je zapsané — potvrzení doběhne při nejbližší synchronizaci (do minuty).' })
    } else if (res.status === 'amount_mismatch') setStep('mismatch')
    else setStep('problem')
  }

  const amounts = (
    <div className="mb-4">
      <Line k="Přišlo">{fmtMoney(tx.amount, tx.currency)}{tx.counter_name ? ` · ${tx.counter_name}` : ''}</Line>
      <Line k="Spárovat s">{target.label || '—'}{target.customer_name ? ` · ${target.customer_name}` : ''}</Line>
      {expected !== null && expected !== undefined && <Line k="Čeká se">{fmtMoney(expected)}</Line>}
      {target.vs && <Line k="VS čekající platby">{target.vs}</Line>}
    </div>
  )

  return (
    <Modal open onClose={close} title={step === 'accept' ? 'Přijmout nižší částku?' : step === 'mismatch' ? 'Přišlo méně, než se čekalo' : step === 'problem' ? 'Platbu nešlo potvrdit' : 'Spárovat platbu?'}>
      {step === 'confirm' && (
        <>
          {amounts}
          <p className="mb-4" style={{ fontSize: 13, color: '#1a2e22', lineHeight: 1.6 }}><b>Co se stane:</b> {pairEffect(target)}</p>
          {(target.state === 'expired' || target.state === 'cancelled') && (
            <Box>{target.state === 'expired' ? 'Lhůta této čekající platby už vypršela' : 'Tato čekající platba byla mezitím zrušena'} — spárováním ji přesto provedete (pokud je termín stále volný).</Box>
          )}
          {diff !== null && diff < 0 && <Box>Pozor: přišlo o {fmtMoney(-diff)} méně, než cíl čeká. Server platbu nepotvrdí a Velín vám nabídne přijetí nižší částky.</Box>}
          {diff !== null && diff > 0 && <Box>Přišlo o {fmtMoney(diff)} víc, než cíl čeká — platba se potvrdí a přeplatek zůstane v seznamu k vrácení zákazníkovi.</Box>}
        </>
      )}
      {step === 'mismatch' && (
        <>
          {amounts}
          <Box>{result?.note ? `Odpověď serveru: ${result.note}. ` : ''}{reasonText({ status: 'amount_mismatch', reason_code: result?.reason_code })}</Box>
          <p className="mb-4" style={{ fontSize: 13, color: '#1a2e22', lineHeight: 1.6 }}>
            Pohyb zůstává přiřazený k cíli jako „Nižší částka“. Když zákazník doplatí, další platba se k němu přičte sama.
          </p>
        </>
      )}
      {step === 'accept' && (
        <>
          {amounts}
          <Box tone="bad">
            Opravdu přijmout <b>{fmtMoney(tx.amount, tx.currency)}</b> jako plnou úhradu{diff !== null && diff < 0 ? <> (chybí {fmtMoney(-diff)})</> : null}? Rozdíl se už nebude čekat ani vymáhat automaticky.
          </Box>
          <p className="mb-4" style={{ fontSize: 13, color: '#1a2e22', lineHeight: 1.6 }}><b>Co se stane:</b> {pairEffect(target)}</p>
        </>
      )}
      {step === 'problem' && (
        <>
          {amounts}
          <Box tone="bad">
            <b>{statusOf(result?.status).label}.</b> {reasonText(result)}{result?.note ? ` (${result.note})` : ''}
          </Box>
        </>
      )}

      {error && <Box tone="bad">{error}</Box>}

      <div className="flex flex-wrap justify-end gap-3">
        {step === 'confirm' && <>
          <Button onClick={close} disabled={busy}>Zrušit</Button>
          <Button green onClick={() => run(false)} disabled={busy}>{busy ? 'Páruji…' : 'Spárovat a potvrdit'}</Button>
        </>}
        {step === 'mismatch' && <>
          <Button onClick={close}>Počkat na doplatek</Button>
          <Button onClick={() => { setError(null); setStep('accept') }} style={{ background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}>Přijmout nižší částku…</Button>
        </>}
        {step === 'accept' && <>
          <Button onClick={close} disabled={busy}>Zrušit</Button>
          <Button onClick={() => run(true)} disabled={busy} style={{ background: '#dc2626', color: '#fff', border: 'none', boxShadow: '0 4px 16px rgba(220,38,38,.25)' }}>
            {busy ? 'Potvrzuji…' : `Ano, přijmout ${fmtMoney(tx.amount, tx.currency)}`}
          </Button>
        </>}
        {step === 'problem' && <Button onClick={close}>Zavřít</Button>}
      </div>
    </Modal>
  )
}
