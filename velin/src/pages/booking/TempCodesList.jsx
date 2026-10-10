import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'
import ConfirmDialog from '../../components/ui/ConfirmDialog'
import { doorLabel } from '../BranchRpiUi'
import { SELF_SERVICE_BRANCH_TYPE } from '../../lib/latePickup'
import { isMissingRelation, fmtPragueWhen } from './kioskReturnHelpers'
import TempCodeModal from './TempCodeModal'
import { effBranch, effBranchId } from '../../lib/bookingBranch'

const chip = { padding: '3px 10px' }
const CODE_COLS = 'id, door_id, code, valid_from, valid_until, note, created_at, revoked_at, use_count, last_used_at'

// Stav krátkodobého kódu pro zobrazení (čas = hodiny prohlížeče; autoritativně rozhoduje server/jednotka)
function codeState(c, now) {
  if (c.revoked_at) return { live: false, label: `Zrušen ${fmtPragueWhen(c.revoked_at)}`, bg: '#f3f4f6', color: '#6b7280' }
  const until = Date.parse(c.valid_until)
  if (Number.isFinite(until) && until < now) return { live: false, label: `Vypršel ${fmtPragueWhen(c.valid_until)}`, bg: '#f3f4f6', color: '#6b7280' }
  const from = Date.parse(c.valid_from)
  if (Number.isFinite(from) && from > now) return { live: true, label: `Platí od ${fmtPragueWhen(c.valid_from)}`, bg: '#fef3c7', color: '#b45309' }
  return { live: true, label: `Platí do ${fmtPragueWhen(c.valid_until)}`, bg: '#dcfce7', color: '#1a8a18' }
}

// Krátkodobé kódy rezervace (2026-10-06, D4) — část karty „Přístupové kódy“ v detailu rezervace: tlačítko
// „Vydat krátkodobý kód“ (dveře pobočky, kde byla motorka vrácena na kiosku — booking_kiosk_returns.branch_id;
// bez vrácení samoobslužná pobočka rezervace; jen aktivní dveře) + seznam vydaných kódů (platí / vypršel / zrušen,
// počet použití) s „Zrušit“ — seznam VŽDY, i když motorka mezitím přejela na pobočku s obsluhou (živý kód musí jít
// zrušit). Bez nasazené tabulky `branch_temp_codes` se skryje.
export default function TempCodesList({ booking }) {
  const b = booking || {}
  const selfService = effBranch(b)?.type === SELF_SERVICE_BRANCH_TYPE
  const branchId = b.motorcycles?.branch_id   // AKTUÁLNÍ umístění motorky (kóje, „motorka je teď jinde“)
  const [retBranchId, setRetBranchId] = useState(undefined)   // undefined = ještě nenačteno
  const [doors, setDoors] = useState([])
  const [motoBox, setMotoBox] = useState(null)
  const [codes, setCodes] = useState([])
  const [available, setAvailable] = useState(true)
  const [err, setErr] = useState(null)
  const [open, setOpen] = useState(false)
  const [revoke, setRevoke] = useState(null)
  const [busy, setBusy] = useState(false)
  const [now, setNow] = useState(() => Date.now())

  const loadCodes = useCallback(async () => {
    if (!b.id) return
    const q = cols => supabase.from('branch_temp_codes').select(cols)
      .eq('booking_id', b.id).order('created_at', { ascending: false }).limit(20)
    try {
      let { data, error } = await q(`${CODE_COLS}, branch_doors(door_kind, box_number, label)`)
      // Vazba na branch_doors ještě není ve schema cache PostgRESTu → bez názvu dveří z vazby (doplní se z `doors`)
      if (error?.code === 'PGRST200') ({ data, error } = await q(CODE_COLS))
      setNow(Date.now())
      if (error) { if (isMissingRelation(error)) setAvailable(false); else setErr(`Krátkodobé kódy se nepodařilo načíst: ${error.message}`); return }
      setAvailable(true); setErr(null); setCodes(data || [])
    } catch (e) { setErr(e?.message || String(e)) }
  }, [b.id])

  // Vydané kódy + pobočka vrácení na kiosku (řádek existuje jen u samoobslužné pobočky; tabulka nenasazena → null)
  useEffect(() => {
    setCodes([]); setRetBranchId(undefined); setErr(null)
    if (!b.id) return
    let alive = true
    loadCodes()
    supabase.from('booking_kiosk_returns').select('branch_id').eq('booking_id', b.id).maybeSingle()
      .then(({ data }) => { if (alive) setRetBranchId(data?.branch_id ?? null) }, () => { if (alive) setRetBranchId(null) })
    return () => { alive = false }
  }, [b.id, loadCodes])

  // Dveře: pobočka vrácení (tam zůstala zapomenutá věc), jinak samoobslužná pobočka rezervace — až po načtení
  // řádku vrácení (jinak by se nejdřív nabídly dveře pobočky, kam motorka mezitím přejela)
  const doorBranchId = retBranchId === undefined ? null : (retBranchId || (selfService ? effBranchId(b) : null))
  useEffect(() => {
    setDoors([]); setMotoBox(null)
    if (!doorBranchId) return
    let alive = true
    supabase.from('branch_doors').select('id, door_kind, box_number, label, sort_order')
      .eq('branch_id', doorBranchId).eq('is_active', true)
      .then(({ data }) => { if (alive) setDoors(data || []) }, () => {})
    // Kóje motorky = výchozí volba v modalu, jen když motorka pořád stojí na této pobočce
    if (b.moto_id && doorBranchId === branchId) {
      supabase.from('motorcycles').select('box_number, branch_id').eq('id', b.moto_id).maybeSingle()
        .then(({ data }) => { if (alive && data?.branch_id === doorBranchId) setMotoBox(data?.box_number ?? null) }, () => {})
    }
    return () => { alive = false }
  }, [doorBranchId, branchId, b.moto_id])

  // Platný kód → po 30 s obnovit stav a počet použití (tabulka není v realtime publikaci)
  const anyLive = codes.some(c => codeState(c, now).live)
  useEffect(() => {
    if (!anyLive) return
    const t = setInterval(() => loadCodes(), 30000)
    return () => clearInterval(t)
  }, [anyLive, loadCodes])

  async function doRevoke() {
    const c = revoke
    if (!c || busy) return
    setBusy(true); setErr(null)
    try {
      const { data, error } = await supabase.rpc('admin_revoke_temp_door_code', { p_id: c.id })
      if (error) setErr(`Zrušení selhalo: ${error.message}`)
      else if (!data?.ok) setErr(data?.error === 'forbidden' ? 'Nemáte oprávnění rušit kódy.' : data?.error === 'not_found' ? 'Kód nenalezen.' : `Zrušení selhalo (${data?.error || 'neznámá chyba'}).`)
    } catch (e) { setErr(`Zrušení selhalo: ${e?.message || e}`) }
    setRevoke(null); setBusy(false)
    loadCodes()
  }

  if (!available) return null
  const canIssue = doors.length > 0
  if (!canIssue && codes.length === 0 && !err) return null
  const movedAway = canIssue && doorBranchId !== branchId
  const defaultDoor = (motoBox == null || doorBranchId !== branchId) ? null
    : doors.find(d => d.door_kind === 'motorcycle' && Number(d.box_number) === Number(motoBox))
  const nameOf = c => {
    const d = c.branch_doors || doors.find(x => x.id === c.door_id)
    return d ? doorLabel(d) : 'Dveře'
  }

  return (
    <div className="mt-3 pt-3" style={{ borderTop: '1px solid #d4e8e0' }}>
      <div className="flex items-start justify-between gap-3 flex-wrap mb-2">
        <div>
          <div className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Krátkodobé kódy</div>
          <div className="text-xs" style={{ color: '#4a5a52' }}>Jednorázová pomoc (např. zapomenutá věc po vrácení) — otevře jen vybrané dveře na 15–120 min, bez km a protokolu, rezervaci nemění.</div>
          {movedAway && <div className="text-xs" style={{ color: '#b45309' }}>Dveře pobočky, kde byla motorka vrácena na kiosku — motorka je teď jinde.</div>}
        </div>
        {canIssue && <Button small green onClick={() => setOpen(true)}>Vydat krátkodobý kód</Button>}
      </div>
      {err && <p className="text-sm mb-2" style={{ color: '#dc2626' }}>{err}</p>}
      {codes.map(c => {
        const st = codeState(c, now)
        return (
          <div key={c.id} className="flex items-center gap-3 flex-wrap py-1" style={{ borderBottom: '1px solid #e8f1ec', fontSize: 13 }}>
            <span className="font-black tracking-widest" style={{ fontFamily: 'monospace', fontSize: 16, color: st.live ? '#0f1a14' : '#9ca3af', textDecoration: st.live ? 'none' : 'line-through' }}>{c.code}</span>
            <span className="font-bold" style={{ color: '#1a2e22' }}>{nameOf(c)}</span>
            <span className="inline-block rounded-btn text-xs font-bold" style={{ ...chip, background: st.bg, color: st.color }}>{st.label}</span>
            <span className="text-xs" style={{ color: '#4a5a52' }} title={c.last_used_at ? `Naposledy použit ${fmtPragueWhen(c.last_used_at)}` : 'Na displeji pobočky zatím nepoužit'}>
              použito {Number(c.use_count) || 0}×{c.last_used_at ? ` (naposledy ${fmtPragueWhen(c.last_used_at)})` : ''}
            </span>
            <span className="text-xs" style={{ color: '#6b7280' }}>vydán {fmtPragueWhen(c.created_at)}</span>
            {c.note && <span className="text-xs italic" style={{ color: '#4a5a52' }}>„{c.note}“</span>}
            {st.live && (
              <button onClick={() => setRevoke(c)} disabled={busy} className="ml-auto rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer max-lg:min-h-[36px]"
                style={{ padding: '3px 10px', background: '#fee2e2', color: '#dc2626', border: 'none' }}>Zrušit</button>
            )}
          </div>
        )
      })}
      <TempCodeModal open={open} onClose={() => setOpen(false)} booking={b} doors={doors} defaultDoorId={defaultDoor?.id} onIssued={loadCodes} />
      <ConfirmDialog open={!!revoke} danger title={`Zrušit kód ${revoke?.code || ''}?`}
        message="Kód přestane platit okamžitě (jednotka ho zahodí po synchronizaci). Je-li pobočka právě bez internetu, může ho jednotka přijímat až do obnovení spojení, nejdéle do konce platnosti."
        onConfirm={doRevoke} onCancel={() => setRevoke(null)} />
    </div>
  )
}
