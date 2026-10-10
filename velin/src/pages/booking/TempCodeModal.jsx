import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import { doorLabel } from '../BranchRpiUi'
import { isMissingRelation, fmtPragueWhen } from './kioskReturnHelpers'

const MINUTES = [15, 30, 60, 120]
const boxStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

// Chybové kódy RPC admin_issue_temp_door_code → česky
const ISSUE_ERRORS = {
  forbidden: 'Nemáte oprávnění vydávat kódy.',
  door_not_found: 'Dveře neexistují nebo nejsou aktivní.',
  invalid_minutes: 'Neplatná délka platnosti (povoleno 5–240 min).',
  booking_not_found: 'Rezervace nenalezena.',
}

// Pořadí v nabídce: kóje motorky rezervace (výchozí) → šatna → ostatní kóje podle čísla
function orderDoors(doors, defaultDoorId) {
  const rank = d => d.id === defaultDoorId ? -2 : d.door_kind === 'accessories' ? -1 : (Number(d.box_number) || 0)
  return (doors || []).slice().sort((a, b) => rank(a) - rank(b) || (Number(a.sort_order) || 0) - (Number(b.sort_order) || 0))
}

// „Vydat krátkodobý kód“ (2026-10-06, D4): obsluha vybere dveře, platnost a poznámku → RPC vrátí 6místný kód,
// který nadiktuje zákazníkovi do telefonu. Kód otevře jen vybrané dveře (online i offline z cache jednotky),
// bez km / protokolu / hradel, rezervaci NEMĚNÍ; audit zapisuje RPC. `onIssued` = znovunačíst seznam.
export default function TempCodeModal({ open, onClose, booking, doors, defaultDoorId, onIssued }) {
  const [doorId, setDoorId] = useState('')
  const [minutes, setMinutes] = useState(30)
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  const [issued, setIssued] = useState(null)

  // Každé otevření = čistý formulář s výchozí kójí motorky rezervace (není-li známá, obsluha vybere sama)
  useEffect(() => {
    if (!open) return
    setDoorId(defaultDoorId || ''); setMinutes(30); setNote(''); setErr(null); setIssued(null); setBusy(false)
  }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  if (!open) return null
  const list = orderDoors(doors, defaultDoorId)

  async function submit() {
    if (!doorId || busy) return
    setBusy(true); setErr(null)
    try {
      const { data, error } = await supabase.rpc('admin_issue_temp_door_code', {
        p_door_id: doorId, p_minutes: minutes, p_booking_id: booking?.id || null, p_note: note.trim() || null,
      })
      if (error) setErr(isMissingRelation(error) ? 'Funkce ještě není v databázi nasazená (čeká na migraci).' : error.message)
      else if (!data?.ok) setErr(ISSUE_ERRORS[data?.error] || `Kód se nepodařilo vydat (${data?.error || 'neznámá chyba'}).`)
      else { setIssued(data); onIssued?.() }
    } catch (e) { setErr(e?.message || String(e)) }
    setBusy(false)
  }

  if (issued) {
    const door = issued.door || list.find(d => d.id === doorId)
    const name = door ? doorLabel(door) : 'vybrané dveře'
    return (
      <Modal open title="Krátkodobý kód vydán" onClose={onClose}>
        <div className="text-center p-5 rounded-lg mb-4" style={{ background: '#dcfce7', border: '1px solid #86efac' }}>
          <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{name}</div>
          <div style={{ fontSize: 44, fontWeight: 900, letterSpacing: '0.18em', fontFamily: 'monospace', color: '#0f1a14' }}>{issued.code}</div>
          <div className="text-sm font-extrabold mt-1" style={{ color: '#1a8a18' }}>platí do {fmtPragueWhen(issued.valid_until)}</div>
        </div>
        <p className="text-sm mb-2" style={{ color: '#1a2e22' }}>
          <strong>Nadiktujte kód zákazníkovi do telefonu.</strong> Na displeji pobočky ho zadá jako běžný kód a otevře se jen {name} — bez zadávání km a bez předávacího protokolu. Rezervace se nemění.
        </p>
        <p className="text-xs mb-4" style={{ color: '#4a5a52' }}>
          Kód platí hned. Při výpadku internetu pobočky funguje jen tehdy, když si ho jednotka stihla stáhnout (synchronizace se spouští po vydání). Zrušit ho lze v seznamu krátkodobých kódů.
        </p>
        <div className="flex justify-end"><Button green onClick={onClose}>Hotovo</Button></div>
      </Modal>
    )
  }

  return (
    <Modal open title="Vydat krátkodobý kód" onClose={onClose}>
      <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
        Jednorázová pomoc zákazníkovi (např. zapomenutá věc po vrácení): 6místný kód otevře jen vybrané dveře pobočky po zvolenou dobu. Nevyžaduje km ani protokol a rezervaci nemění.
      </p>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Dveře</label>
      <select value={doorId} onChange={e => setDoorId(e.target.value)} className="w-full rounded-btn text-sm outline-none mb-3" style={boxStyle}>
        {!doorId && <option value="">— vyberte dveře —</option>}
        {list.map(d => <option key={d.id} value={d.id}>{doorLabel(d)}{d.id === defaultDoorId ? ' — motorka rezervace' : ''}</option>)}
      </select>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Platnost</label>
      <div className="flex gap-2 mb-3 flex-wrap">
        {MINUTES.map(m => (
          <button key={m} type="button" onClick={() => setMinutes(m)} className="rounded-btn text-sm font-extrabold cursor-pointer max-lg:min-h-[40px]"
            style={{ padding: '6px 14px', background: minutes === m ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: minutes === m ? 'none' : '1px solid #d4e8e0' }}>
            {m} min
          </button>
        ))}
      </div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Poznámka (nepovinná)</label>
      <input type="text" value={note} maxLength={200} onChange={e => setNote(e.target.value)} placeholder="např. zapomenutá bunda v šatně"
        className="w-full rounded-btn text-sm outline-none mb-3" style={boxStyle} />
      {err && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-2">
        <Button onClick={onClose}>Zpět</Button>
        <Button green onClick={submit} disabled={busy || !doorId}>{busy ? 'Vydávám…' : `Vydat kód na ${minutes} min`}</Button>
      </div>
    </Modal>
  )
}
