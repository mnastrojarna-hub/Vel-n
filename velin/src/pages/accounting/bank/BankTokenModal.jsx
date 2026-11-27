import { useState } from 'react'
import Modal from '../../../components/ui/Modal'
import Button from '../../../components/ui/Button'
import { setTokenExpiry } from './bankApi'
import { errorText, daysUntil, isoDate } from './bankFormat'

const MAX_DAYS = 180 // Fio: token platí nejdéle 180 dní

/** Kontrola dat platnosti tokenů; vrací pole českých hlášek (prázdné = v pořádku). */
export function validateTokenDates(valid, pay, now = new Date()) {
  const errs = []
  const check = (v, what) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(v) || daysUntil(v, now) === null) { errs.push(`Datum platnosti ${what} není platné datum.`); return }
    const d = daysUntil(v, now)
    if (d < 0) errs.push(`Datum platnosti ${what} je v minulosti.`)
    else if (d > MAX_DAYS) errs.push(`Token Fio banky platí nejdéle ${MAX_DAYS} dní — zkontrolujte datum ${what}.`)
  }
  if (!valid) errs.push('Vyplňte, do kdy platí token pro čtení pohybů.')
  else check(valid, 'tokenu pro čtení')
  if (pay) check(pay, 'tokenu pro příkazy')
  return errs
}

// Platnost API tokenů zadává obsluha — banka ji přes API nesděluje. Ukládá RPC admin_fio_set_token_expiry (audit).
export default function BankTokenModal({ state, onClose, onSaved }) {
  const [valid, setValid] = useState(state?.token_valid_until || '')
  const [pay, setPay] = useState(state?.pay_token_valid_until || '')
  const [auto, setAuto] = useState(state?.token_auto_prolong === true)
  const [errs, setErrs] = useState([])
  const [saving, setSaving] = useState(false)

  const today = new Date()
  const max = new Date(today.getFullYear(), today.getMonth(), today.getDate() + MAX_DAYS)
  const inp = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 10, outline: 'none', fontSize: 14, color: '#1a2e22', width: '100%' }
  const lbl = 'block text-sm font-extrabold uppercase tracking-wide mb-1'

  async function save() {
    const e = validateTokenDates(valid, pay)
    setErrs(e)
    if (e.length) return
    setSaving(true)
    const r = await setTokenExpiry(valid, pay || null, auto)
    setSaving(false)
    if (r.ok) { onSaved(); return }
    setErrs([r.missing ? 'Uložení bude dostupné po nasazení databázové části.'
      : r.lost ? 'Uložení se nezdařilo — zkontrolujte připojení a zkuste to znovu.' : errorText(r.code)])
  }

  return (
    <Modal open title="Platnost API tokenů banky" onClose={onClose}>
      <p className="mb-4" style={{ fontSize: 13, color: '#1a2e22', lineHeight: 1.6 }}>
        Banka neumí platnost tokenu sdělit přes API — datum najdete v internetovém bankovnictví Fio u daného tokenu.
        Token platí nejdéle {MAX_DAYS} dní. Velín vás na blížící se konec platnosti upozorní tady i e-mailem.
      </p>
      <div className="mb-3">
        <label className={lbl} style={{ color: '#1a2e22' }} htmlFor="bank-token-valid">Token pro čtení pohybů — platí do</label>
        <input id="bank-token-valid" type="date" value={valid} min={isoDate(today)} max={isoDate(max)} onChange={e => setValid(e.target.value)} style={inp} />
      </div>
      <div className="mb-3">
        <label className={lbl} style={{ color: '#1a2e22' }} htmlFor="bank-token-pay">Token pro platební příkazy (vratky) — platí do</label>
        <input id="bank-token-pay" type="date" value={pay} min={isoDate(today)} max={isoDate(max)} onChange={e => setPay(e.target.value)} style={inp} />
        <div className="mt-1" style={{ fontSize: 12, color: '#4a6357' }}>Nechte prázdné, pokud se pro příkazy používá stejný token.</div>
      </div>
      <label className="flex items-start gap-2 cursor-pointer mb-4" style={{ fontSize: 13, color: '#1a2e22' }}>
        <input type="checkbox" checked={auto} onChange={e => setAuto(e.target.checked)} className="accent-[#1a8a18]" style={{ width: 16, height: 16, marginTop: 2 }} />
        <span>V bance je zapnuté <b>automatické prodlužování</b> (platnost se posune při každém přihlášení do bankovnictví — datum pak stačí tady občas opravit).</span>
      </label>
      {errs.length > 0 && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {errs.map(e => <div key={e}>{e}</div>)}
        </div>
      )}
      <div className="flex justify-end gap-3">
        <Button onClick={onClose} disabled={saving}>Zrušit</Button>
        <Button green onClick={save} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}
