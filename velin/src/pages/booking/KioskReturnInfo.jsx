import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import { SumRow } from './BookingUIHelpers'
import { boxLabel } from '../BranchRpiUi'
import { SELF_SERVICE_BRANCH_TYPE } from '../../lib/latePickup'
import { isMissingRelation, fmtPragueWhen, kioskReturnView, kioskClockNote } from './kioskReturnHelpers'
import { effBranch } from '../../lib/bookingBranch'

// Blok „Vrácení na kiosku“ v detailu rezervace (2026-10-06): aktuální stav vrácení na samoobslužné pobočce
// z `booking_kiosk_returns` (1 řádek na rezervaci, zapisuje jen server). Časy kóje a šatny jsou podle hodin
// jednotky (≥ 1.2.8, detail.unit_ts); starší jednotka = čas doručení na server — popisek to rozliší.
// Bez řádku / bez nasazené tabulky se nic nezobrazí.
// `hasLockerCode` = rezervace má aktivní kód šatny (DetailTab z branch_door_codes).
export default function KioskReturnInfo({ booking, hasLockerCode = false }) {
  const id = booking?.id
  // Pobočka rezervace (bookings.branch_id = kde převzal), u NULL pobočka motorky — přesun motorky po vrácení nemění
  const selfService = effBranch(booking)?.type === SELF_SERVICE_BRANCH_TYPE
  const [row, setRow] = useState(null)
  const [err, setErr] = useState(null)

  // Načíst při otevření a průběžně přes realtime (tabulka je v publikaci supabase_realtime). Kanál jen u
  // samoobslužné pobočky — jinde vrácení na kiosku neprobíhá a případný řádek je jen historie.
  useEffect(() => {
    setRow(null); setErr(null)
    if (!id) return
    let alive = true
    const load = () => supabase.from('booking_kiosk_returns').select('*').eq('booking_id', id).maybeSingle()
      .then(({ data, error }) => {
        if (!alive) return
        if (error) { if (!isMissingRelation(error)) setErr(error.message); return }
        setErr(null); setRow(data || null)
      }, e => { if (alive) setErr(e?.message || String(e)) })
    load()
    if (!selfService) return () => { alive = false }
    const channel = supabase.channel(`booking-kiosk-return-${id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'booking_kiosk_returns', filter: `booking_id=eq.${id}` }, () => load())
      .subscribe()
    return () => { alive = false; supabase.removeChannel(channel) }
  }, [id, selfService])

  if (!row) {
    if (!err || !selfService) return null
    return (
      <Card className="md:col-span-2">
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Vrácení na kiosku</h3>
        <p className="text-sm" style={{ color: '#dc2626' }}>Stav vrácení se nepodařilo načíst: {err}</p>
      </Card>
    )
  }

  const v = kioskReturnView(row, booking)
  const u = booking?.motorcycles?.tracking_unit === 'mh' ? 'MH' : 'km'
  const box = row.box_number != null ? boxLabel(row.box_number) : 'Kóje'
  // Dokončeno automaticky a obsluha to nevrátila zpět (reverted → řádek zůstává 'completed', rezervace ne)
  const done = row.state === 'completed' && booking?.status === 'completed'
  const clk = kioskClockNote(row)
  const foreign = row.detail?.last_event === 'FOREIGN_GRANT'
  // Kód šatny po automatickém dokončení: zavřel-li zákazník šatnu, dobíhá 15 min; jinak drží běžnou platnost
  // (nikdy nezaniká dřív, než šatnu zavře — výbava by zůstala venku).
  const lockerTxt = row.locker_code_until
    ? fmtPragueWhen(row.locker_code_until)
    : (done && hasLockerCode && !row.codes_closed_at ? 'do konce termínu — šatna po vrácení zatím nezavřena' : null)

  return (
    <Card className="md:col-span-2">
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#1a2e22' }}>Vrácení na kiosku</h3>
      <div className="p-4 rounded-lg mb-3" style={{ background: v.tone.bg, border: `1px solid ${v.tone.border}` }}>
        <div className="text-sm font-extrabold" style={{ color: v.tone.color }}>{v.title}</div>
        {v.hint && <div className="text-xs mt-1" style={{ color: '#4a5a52' }}>{v.hint}</div>}
      </div>
      <div className="space-y-1">
        {row.grant_at && <SumRow label="Kód motorky zadán" value={`${fmtPragueWhen(row.grant_at)}${row.km != null ? ` · stav ${row.km} ${u}` : ''}${clk}`} />}
        {row.closed_at && <SumRow label={`${box} zavřena`} value={`${fmtPragueWhen(row.closed_at)}${clk}`} strong />}
        {row.locker_closed_at && <SumRow label="Šatna zavřena" value={`${fmtPragueWhen(row.locker_closed_at)}${clk}`} />}
        {row.state === 'out' && row.out_at && <SumRow label={foreign ? 'Otevřeno krátkodobým kódem' : 'Znovu vyjeto'} value={`${fmtPragueWhen(row.out_at)}${clk}`} />}
        {done && row.completed_at && <SumRow label="Dokončeno serverem" value={fmtPragueWhen(row.completed_at)} />}
        {row.moto_code_until && <SumRow label="Kód motorky platí do" value={fmtPragueWhen(row.moto_code_until)} />}
        {lockerTxt && <SumRow label="Kód šatny platí do" value={lockerTxt} />}
        {row.codes_closed_at && <SumRow label="Kódy uzavřeny" value={fmtPragueWhen(row.codes_closed_at)} />}
      </div>
    </Card>
  )
}
