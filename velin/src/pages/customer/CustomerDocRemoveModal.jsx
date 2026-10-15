// Potvrzení „Odebrat doklad“ z Profilu zákazníka — ukáže, co přesně se smaže (fotky
// v archivu + údaje dokladu v profilu), a u OP / pasu nechá obsluhu zvolit číslo
// dokladu totožnosti, které v profilu zůstane (OP i pas sdílí jedno pole id_number).
import { useState } from 'react'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { DOC_KINDS, ocrDocNumber, removeCustomerDoc, suggestIdNumber } from '../../lib/customerDocs'
import { docSide, isMarkerPath } from '../../lib/docVerification'
import { C, fmtDate, Field } from './profileUi'

const SIDE = { front: 'líc', back: 'rub' }
const SIDE_ORDER = ['líc', 'rub', 'záznam bez fotky']

// Platnost ŘP je text (ISO nebo DD.MM.YYYY) — ISO zobrazíme česky, jinak jak je
const fmtAny = (v) => (/^\d{4}-\d{2}-\d{2}/.test(String(v || '')) ? fmtDate(v) : v) || null

function photosText(docs) {
  if (!docs.length) return 'žádné'
  const sides = docs.map(d => (isMarkerPath(d.file_path) ? 'záznam bez fotky' : SIDE[docSide(d)])).filter(Boolean)
    .sort((a, b) => SIDE_ORDER.indexOf(a) - SIDE_ORDER.indexOf(b))
  return `${docs.length}${sides.length ? ` (${sides.join(', ')})` : ''}`
}

export default function CustomerDocRemoveModal({ kind, customer, docsByKind, onClose, onRemoved }) {
  const k = DOC_KINDS[kind]
  const own = docsByKind[kind] || []
  const identity = kind !== 'dl'
  const other = kind === 'id' ? 'passport' : 'id'
  const otherDocs = identity ? docsByKind[other] || [] : []
  const otherVerified = kind === 'id' ? !!customer.passport_verified_at : !!customer.id_verified_at
  const [idNumber, setIdNumber] = useState(() =>
    (identity ? suggestIdNumber(customer.id_number, own, otherDocs, otherVerified) : ''))
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)

  const rows = [['Fotky v archivu', photosText(own)]]
  const add = (label, v) => { if (v) rows.push([label, v]) }
  if (kind === 'dl') {
    add('Číslo ŘP', customer.license_number)
    add('Platnost ŘP', fmtAny(customer.license_expiry))
    add('Platnost z OCR', fmtDate(customer.license_verified_until))
    add('Ověřeno', fmtDate(customer.license_verified_at))
  } else {
    const p = kind === 'id' ? 'id' : 'passport'
    add('Platnost', fmtDate(customer[`${p}_verified_until`]))
    add('Ověřeno', fmtDate(customer[`${p}_verified_at`]))
  }
  const ocrHints = identity ? [
    ...own.map(ocrDocNumber).filter(Boolean).map(n => `${kind === 'id' ? 'OP' : 'pas'} ${n}`),
    ...otherDocs.map(ocrDocNumber).filter(Boolean).map(n => `${other === 'id' ? 'OP' : 'pas'} ${n}`),
  ].filter((v, i, a) => a.indexOf(v) === i) : []

  async function confirm() {
    setBusy(true); setError(null)
    try {
      const { patch } = await removeCustomerDoc({ userId: customer.id, kind, idNumber, before: customer })
      await onRemoved(patch)
    } catch (e) {
      setError(e.message || String(e))
      setBusy(false)
    }
  }

  return (
    <Modal open title={`Odebrat doklad — ${k.label}`} onClose={() => !busy && onClose()}>
      {error && <div className="p-2 mb-3 rounded-lg text-[13px]" style={{ background: '#fee2e2', color: C.red }}>{error}</div>}
      <div className="text-sm mb-2 font-bold" style={{ color: C.text }}>Trvale se smaže:</div>
      <div className="rounded-lg p-3 mb-3 space-y-1" style={{ background: C.g100, border: `1px solid ${C.g200}` }}>
        {rows.map(([label, v]) => (
          <div key={label} className="flex justify-between gap-3 text-sm max-sm:flex-wrap">
            <span style={{ color: C.muted }}>{label}</span>
            <span className="font-semibold text-right break-words min-w-0" style={{ color: C.text }}>{v}</span>
          </div>
        ))}
      </div>
      {kind === 'dl' && (customer.license_group || []).length > 0 && (
        <div className="text-xs mb-3" style={{ color: C.muted }}>Skupiny ŘP ({customer.license_group.join(', ')}) v profilu zůstávají.</div>
      )}
      {identity && (
        <div className="mb-3">
          <Field label="Číslo dokladu totožnosti, které v profilu zůstane" value={idNumber} onChange={setIdNumber} />
          <div className="text-xs mt-1" style={{ color: C.muted }}>
            OP i pas sdílí v profilu jedno číslo dokladu (tiskne se do smlouvy). Prázdné pole = číslo smazat.
            {ocrHints.length > 0 && <> Přečteno z fotek: {ocrHints.join(' · ')}.</>}
          </div>
        </div>
      )}
      <p className="text-xs mb-4" style={{ color: '#92400e' }}>
        Akce je nevratná. Kódy k boxu, které už zákazník dostal, zůstávají; nové se vydají jen s kompletními
        doklady (OP líc + rub nebo pas, ŘP líc + rub).
      </p>
      <div className="flex justify-end gap-2 max-sm:flex-wrap">
        <Button onClick={onClose} disabled={busy}>Zrušit</Button>
        <Button onClick={confirm} disabled={busy} style={{ background: C.red, color: '#fff' }}>
          {busy ? 'Odebírám…' : 'Odebrat doklad'}
        </Button>
      </div>
    </Modal>
  )
}
