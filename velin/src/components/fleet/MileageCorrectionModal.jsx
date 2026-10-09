import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../ui/Modal'
import Button from '../ui/Button'
import { fmtKm } from '../../lib/motoMove'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }

// „Korigovat“ nájezd v detailu motorky (dřív window.prompt — při zablokovaných dialozích prohlížeče
// vracel tiše null a tlačítko „nic nedělalo“). RPC correct_motorcycle_mileage nedovolí jít pod
// purchase_mileage (tiše zvedne) → je-li nový stav nižší, sníží se po potvrzení i „Zakoupeno s KM“.
export default function MileageCorrectionModal({ moto, onClose, onDone }) {
  const unit = moto.tracking_unit === 'mh' ? 'mh' : 'km'
  const [val, setVal] = useState('')
  const [err, setErr] = useState(null)
  const [busy, setBusy] = useState(false)
  const purchase = Number(moto.purchase_mileage) || 0

  // mezery / tečky = oddělovače tisíců (27 500, 27.500); desetinná čísla odmítnout (ne 10× víc)
  const raw = String(val).replace(/\s/g, '')
  const s = /^\d{1,3}(\.\d{3})+$/.test(raw) ? raw.replace(/\./g, '') : raw
  const km = /^\d{1,7}$/.test(s) ? parseInt(s, 10) : null
  const belowPurchase = km != null && km < purchase

  async function handleConfirm() {
    if (busy) return
    if (km == null) { setErr('Zadejte celé číslo — stav, který ukazuje tachometr.'); return }
    setBusy(true); setErr(null)
    try {
      if (belowPurchase) {
        const { error } = await supabase.from('motorcycles').update({ purchase_mileage: km }).eq('id', moto.id)
        if (error) { setErr('Nepodařilo se snížit „Zakoupeno s KM“: ' + error.message); return }
      }
      const { data, error } = await supabase.rpc('correct_motorcycle_mileage', { p_moto_id: moto.id, p_km: km, p_note: 'Ruční korekce ve Flotile' })
      if (error) { setErr('Korekce selhala: ' + error.message); return }
      onDone({ mileage: data?.mileage ?? km, purchase_mileage: belowPurchase ? km : moto.purchase_mileage })
    } catch (ex) {
      setErr(ex?.message || String(ex))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal open title="Korekce nájezdu" onClose={() => !busy && onClose()}>
      <p className="text-sm mb-3" style={{ color: '#1a2e22' }}>
        Aktuální evidovaný stav: <b>{Number(moto.mileage) > 0 ? fmtKm(moto.mileage, unit) : '—'}</b>.
        Zadejte skutečný stav tachometru — smí být i nižší (oprava překlepu), změna se zapíše do auditu.
      </p>
      <input type="text" inputMode="numeric" autoFocus value={val}
        onChange={e => { setVal(e.target.value); setErr(null) }}
        onKeyDown={e => { if (e.key === 'Enter') handleConfirm() }}
        placeholder={unit === 'mh' ? 'MH' : 'km'} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
      {belowPurchase && (
        <p className="text-sm mt-2" style={{ color: '#b45309' }}>
          Stav je nižší než „Zakoupeno s KM“ ({fmtKm(purchase, unit)}) — sníží se i ten na {fmtKm(km, unit)}.
        </p>
      )}
      {err && <p className="text-sm mt-2" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose} disabled={busy}>Zrušit</Button>
        <Button green onClick={handleConfirm} disabled={busy}>{busy ? 'Ukládám…' : 'Korigovat'}</Button>
      </div>
    </Modal>
  )
}
