import { useState, useCallback, useRef } from 'react'
import Modal from '../ui/Modal'
import Button from '../ui/Button'
import { moveErrorText, fmtKm, unitLabel } from '../../lib/motoMove'

// Stav tachometru při přesunu motorky mezi obslužnou ↔ samoobslužnou pobočkou (zadání majitele 2026-09-29).
// Okno samo volá `submit(readings)` (lib/motoMove.callMove) a řeší odpovědi DB:
//  • km_below_last / km_jump (needs_confirm) → „Opravdu?“ → znovu s force pro tu motorku,
//  • km_below_purchase / invalid_km → chyba u řádku, přesun neproběhne (tvrdá zastávka),
//  • km_required u motorky mimo seznam → doplní řádek. „Zrušit“ = nic se nepřesune (resolve null).
// Nápověda (placeholder) = poslední známý stav motorky (motorcycles.mileage) + jednotka.
export function useOdometerPrompt() {
  const [req, setReq] = useState(null)
  const seq = useRef(0)   // key = nový dotaz vždy s čistým stavem okna (řádky, hodnoty, potvrzení)
  const ask = useCallback(opts => new Promise(resolve => setReq({ ...opts, resolve, seq: ++seq.current })), [])
  const node = req ? (
    <OdometerReadingModal key={req.seq} motos={req.motos} branchName={req.branchName} submit={req.submit}
      onDone={res => { setReq(null); req.resolve(res) }} />
  ) : null
  return [node, ask]
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }

export default function OdometerReadingModal({ motos, branchName, submit, onDone }) {
  const [rows, setRows] = useState(motos)
  const [vals, setVals] = useState({})
  const [force, setForce] = useState({})   // potvrzené „Opravdu?“ pro právě zadanou hodnotu
  const [errs, setErrs] = useState({})
  const [err, setErr] = useState(null)
  const [busy, setBusy] = useState(false)

  const setVal = (id, v) => {
    setVals(s => ({ ...s, [id]: v }))
    setForce(f => ({ ...f, [id]: false })); setErrs(e => ({ ...e, [id]: null }))
  }
  const label = id => { const m = rows.find(r => r.id === id); return m ? `${m.model || ''} ${m.spz || ''}`.trim() : 'Motorka' }

  async function handleConfirm() {
    if (busy) return
    const readings = {}, e = {}
    for (const m of rows) {
      // mezery = oddělovače tisíců; tečka JEN jako oddělovač tisíců (12.500) — desetinné „1234.5“ neslepovat
      // v 12345 (10× víc), ale odmítnout: stav se zadává celým číslem
      const raw = String(vals[m.id] ?? '').replace(/\s/g, '')
      const s = /^\d{1,3}(\.\d{3})+$/.test(raw) ? raw.replace(/\./g, '') : raw
      if (!/^\d{1,7}$/.test(s)) { e[m.id] = 'Zadejte celé číslo — stav, který ukazuje tachometr.'; continue }
      readings[m.id] = { km: parseInt(s, 10), force: !!force[m.id] }
    }
    setErrs(e); setErr(null)
    if (Object.keys(e).length) return
    setBusy(true)
    try {
      for (;;) {
        const res = await submit(readings)
        if (res.ok) { onDone(res.data); return }
        const id = res.moto_id
        if (res.needs_confirm && readings[id] && !readings[id].force) {
          const msg = moveErrorText(res)
          if (!window.confirm(`${label(id)}: ${msg}\n\nOpravdu tachometr ukazuje ${fmtKm(readings[id].km, res.unit)}?`)) {
            setErrs({ [id]: msg + ' Opravte hodnotu.' }); return
          }
          readings[id].force = true
          setForce(f => ({ ...f, [id]: true }))
          continue
        }
        if (res.error === 'km_required' && id && !rows.some(m => m.id === id)) {
          setRows(r => [...r, { id, model: res.model, spz: res.spz, mileage: res.last, tracking_unit: res.unit }])
          setErr('Stav tachometru je potřeba i u další motorky — doplňte ho.')
          return
        }
        if (id && rows.some(m => m.id === id)) setErrs({ [id]: moveErrorText(res) })
        else setErr(moveErrorText(res))
        return
      }
    } catch (ex) {
      setErr(ex?.message || String(ex))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal open title="Aktuální stav tachometru" onClose={() => !busy && onDone(null)}>
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
        Přesun {rows.length > 1 ? 'motorek' : 'motorky'}{branchName ? ` na „${branchName}“` : ''} mezi obslužnou a samoobslužnou
        pobočkou vyžaduje aktuální stav tachometru — odečtěte ho přímo z motorky. Ze samoobslužné pobočky se předvyplní
        dalšímu zákazníkovi do předávacího protokolu. Bez stavu se motorka nepřesune.
      </p>
      {rows.map((m, i) => (
        <div key={m.id} className="mb-3">
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
            {m.model} <span className="font-mono" style={{ color: '#6b7280' }}>{m.spz}</span>
          </label>
          <input type="text" inputMode="numeric" autoFocus={i === 0} value={vals[m.id] ?? ''}
            onChange={ev => setVal(m.id, ev.target.value)} onKeyDown={ev => { if (ev.key === 'Enter') handleConfirm() }}
            placeholder={Number(m.mileage) > 0 ? fmtKm(m.mileage, m.tracking_unit) : unitLabel(m.tracking_unit)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          <p className="text-xs mt-1" style={{ color: '#5b7065' }}>
            {Number(m.mileage) > 0 ? `Poslední známý stav: ${fmtKm(m.mileage, m.tracking_unit)}` : 'Poslední stav není evidován.'}
          </p>
          {errs[m.id] && <p className="text-sm mt-1" style={{ color: '#dc2626' }}>{errs[m.id]}</p>}
        </div>
      ))}
      {err && <p className="text-sm mt-2" style={{ color: '#dc2626', whiteSpace: 'pre-line' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={() => onDone(null)} disabled={busy}>Zrušit</Button>
        <Button green onClick={handleConfirm} disabled={busy}>{busy ? 'Přesouvám…' : 'Potvrdit a přesunout'}</Button>
      </div>
    </Modal>
  )
}
