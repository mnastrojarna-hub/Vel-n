import { txt, num, arr } from './BranchRpiUi'

// ─── Předávací protokol na displeji pobočky (kiosk_devices.status.handover, kontrakt §22) ────────
// Jednotka hlásí (HandoverManager.status()):
//   active   = protokol právě zobrazený na displeji ({booking_id, stage 'protocol'|'done', zone, zone_label, kind,
//              then_open, needs_code, data:{customer_name, moto_model, …}, shown_at, expires_at}) | null
//   waiting[] = NEVYŘÍZENÉ protokoly (booking_id): zobrazily se, zákazník je nepodepsal (odešel / „Zpět“ / bez dotyku);
//              znovu se ukážou kódem motorky téže rezervace nebo dalším zavřením šatny
//   pending[] = PODEPSANÉ na displeji, čekají ve frontě jednotky na odeslání (protocol_queue — bez spojení);
//              jednotka je odešle sama po obnovení spojení, kóje se už otevřela
//   failed[]  = podpisy z displeje, které server trvale odmítl uložit (zůstávají ve frontě jednotky — dořešit ručně)
// Snapshot NIKDY nenese podpis ani formulář — jen metadata. Hodnoty se kreslí přes txt()/num() (JSON z jednotky).

function parseHandover(st) {
  const ho = st && typeof st.handover === 'object' && st.handover && !Array.isArray(st.handover) ? st.handover : null
  if (!ho) return null
  const active = ho.active && typeof ho.active === 'object' && !Array.isArray(ho.active) ? ho.active : null
  const data = active?.data && typeof active.data === 'object' ? active.data : {}
  return {
    active: active ? { ...active, data } : null,
    waiting: arr(ho.waiting).map(v => txt(v)),
    pending: arr(ho.pending).map(v => txt(v)),
    failed: arr(ho.failed).map(v => txt(v)),
  }
}

const shortId = id => `${String(id).slice(0, 8)}…`

// Za kolik sekund overlay na displeji zmizí bez dotyku (jediný zdroj odpočtu = expires_at)
function secondsLeft(active, now) {
  const t = active?.expires_at ? new Date(txt(active.expires_at)).getTime() : NaN
  return Number.isFinite(t) ? Math.max(0, Math.round((t - now) / 1000)) : null
}

const FAILED_TITLE = 'Zákazník podepsal protokol na displeji, ale server odeslání trvale odmítl (rezervace není samoobslužná / jiná pobočka / neplatný stav). '
  + 'Podpis zůstává uložený v jednotce (fronta protocol_queue) a rezervace je bez podepsaného protokolu — detail v Hlášení a chybách (zdroj protocol), dořešte ručně.'
const QUEUED_TITLE = 'Zákazník protokol podepsal na displeji, jednotka ho zatím neodeslala (bez spojení). Odešle ho sama po obnovení spojení — '
  + 'kóje se už otevřela, do té doby je rezervace v DB bez podepsaného protokolu (badge „Čeká na protokol“ zmizí až po odeslání).'
const WAITING_TITLE = 'Protokoly, které se na displeji zobrazily, ale zákazník je nepodepsal (odešel / „Zpět“ / bez dotyku). '
  + 'Znovu se ukážou kódem motorky téže rezervace nebo dalším zavřením šatny; do 24 h se z jednotky vyčistí.'

// Řádky pod hlavičkou karty jednotky: selhané podpisy (červeně), protokol právě na displeji,
// podepsané čekající na odeslání (modře), počet nevyřízených (bez podpisu)
function HandoverDeviceInfo({ handover, now }) {
  if (!handover) return null
  const { active, waiting, pending, failed } = handover
  const left = secondsLeft(active, now)
  const activeId = active ? txt(active.booking_id) : ''
  // Právě zobrazený protokol se do „nevyřízených“ nepočítá (řeší se teď)
  const unsigned = waiting.filter(b => b !== activeId)
  return (
    <>
      {failed.length > 0 && (
        <div className="mt-2 p-2 rounded-lg text-[12px] font-bold" style={{ background: '#fee2e2', color: '#dc2626' }} title={FAILED_TITLE}>
          Podpis z kiosku se nepodařilo uložit ({failed.length}): rezervace {failed.map(shortId).join(', ')}
        </div>
      )}
      {active && (
        <div className="mt-2 p-2 rounded-lg text-[12px]" style={{ background: '#ede9fe', color: '#6d28d9' }}
          title={`Rezervace ${txt(active.booking_id)}${active.needs_code ? ' · podpis se potvrzuje kódem motorky' : ''}`}>
          <span className="font-bold">📝 {active.stage === 'done' ? 'Protokol potvrzen' : 'Protokol k podpisu na displeji'}</span>
          {' — '}{txt(active.data.customer_name ?? '—')}
          {active.data.moto_model ? ` · ${txt(active.data.moto_model)}` : ''}
          {active.zone_label || active.zone != null ? ` · ${active.zone_label ? txt(active.zone_label) : `zóna ${txt(active.zone)}`}` : ''}
          {active.then_open === true ? ' · po podpisu se kóje otevře' : ''}
          {left != null && active.stage !== 'done' ? ` · bez dotyku zmizí za ${left} s` : ''}
        </div>
      )}
      {pending.length > 0 && (
        <div className="mt-2 p-2 rounded-lg text-[12px] font-bold" style={{ background: '#dbeafe', color: '#1d4ed8' }} title={QUEUED_TITLE}>
          Podepsáno na displeji, čeká na odeslání ({pending.length}): rezervace {pending.map(shortId).join(', ')} — jednotka odešle po obnovení spojení
        </div>
      )}
      {unsigned.length > 0 && (
        <div className="text-[11px] mt-1" style={{ color: '#b45309' }} title={WAITING_TITLE}>
          Nevyřízené protokoly na jednotce (bez podpisu): {unsigned.length}{unsigned.length <= 4 ? ` (${unsigned.map(shortId).join(', ')})` : ''}
        </div>
      )}
    </>
  )
}

// Řádek na dlaždici zóny: protokol právě zobrazený pro tuto zónu (šatna / kóje), nebo relace s nepodepsaným,
// podepsaným-neodeslaným či neuloženým protokolem (podle booking_id relace)
function ZoneHandoverInfo({ handover, zoneNo, bookingId }) {
  if (!handover) return null
  const { active, waiting, pending, failed } = handover
  const here = !!active && active.stage === 'protocol' && zoneNo != null && num(active.zone) === zoneNo
  const bid = bookingId ? txt(bookingId) : ''
  const isFailed = !!bid && failed.includes(bid)
  const isQueued = !!bid && !isFailed && pending.includes(bid)
  const isWaiting = !here && !!bid && !isQueued && !isFailed && waiting.includes(bid)
  return (
    <>
      {here && <div className="text-[11px] mt-0.5 font-bold" style={{ color: '#6d28d9' }}>📝 Protokol k podpisu — {txt(active.data.customer_name ?? '—')}</div>}
      {isWaiting && <div className="text-[11px] mt-0.5" style={{ color: '#b45309' }} title={WAITING_TITLE}>📝 protokol čeká na podpis</div>}
      {isQueued && <div className="text-[11px] mt-0.5" style={{ color: '#1d4ed8' }} title={QUEUED_TITLE}>📝 podepsáno na displeji, čeká na odeslání</div>}
      {isFailed && <div className="text-[11px] mt-0.5 font-bold" style={{ color: '#dc2626' }} title={FAILED_TITLE}>Podpis z kiosku se nepodařilo uložit</div>}
    </>
  )
}

export { parseHandover, HandoverDeviceInfo, ZoneHandoverInfo }
