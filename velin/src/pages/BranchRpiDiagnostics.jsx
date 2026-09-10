import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { EmptyState } from './BranchHelpers'
import { RpiSection, Btn, Chip, ErrorBoundary, formatAge, ageSeconds, txt, num, arr, isRpiDevice } from './BranchRpiUi'
import { NetworkDetail, obj } from './BranchRpiDiagNetwork'
import { ProtocolView } from './BranchRpiDiagProtocol'

// ─── Kompletní diagnostika pobočky — řídicí jednotka (Raspberry) ─────────────
// Spuštění: příkaz `diagnostics` (kiosk_commands) s params {mode: 'full'|'network', cameras, reason}. RPi provede
// síť (rozhraní, LTE, internet, Velín, moduly, LAN, ARP) a v režimu full navíc software, konfiguraci, HW test zón
// (světlo/zelená/tón — jen v prázdných kójích, zámek se NIKDY nespíná), napájení (FV) a kamery; report + `protocol`
// uloží přes RPC kiosk_report_diagnostics → tabulka kiosk_diagnostics. Stejný protokol se zobrazí i na displeji.
// Report je JSON ze zařízení — každá hodnota se vykresluje přes txt()/num()/arr() (nevěřit tvaru).
// Staré reporty (bez `protocol`) se zobrazí jako dřív: jen technický detail sítě (BranchRpiDiagNetwork).

const WAIT_MAX_MS = 300 * 1000   // full běh trvá 1–4 min (limit na jednotce 240 s) + doručení reportu
const POLL_MS = 5000
const COLS = 'id, device_id, report_id, source, ok, problems, summary, app_version, started_at, finished_at, created_at'
// `source` ukládá jednotka: velin (příkaz z Velína), service_panel, ui / diag_ui (kód zadaný na displeji —
// hlavní klávesnice / setup obrazovka), local_code, service_code (dokumentovaný enum)
const SOURCE_CZ = {
  local_code: 'kód na displeji', service_code: 'servisní heslo', service_panel: 'servisní panel', velin: 'Velín',
  ui: 'kód na displeji', diag_ui: 'kód na displeji (setup)',
}
const MODE_CZ = { full: 'kompletní', network: 'jen síť' }

// Kamery pro test na jednotce (kontrakt §1): jen názvy/URL, nic dalšího (control_url je akce — netestuje se)
const camerasParam = cameras => arr(cameras).map(c => {
  const cam = obj(c)
  return { name: txt(cam.name), kind: txt(cam.kind), snapshot_url: cam.snapshot_url ? String(cam.snapshot_url) : null, stream_url: cam.stream_url ? String(cam.stream_url) : null }
})

// Průběh běhu z kiosk_devices.status.diagnostics ({running, step_title, done[], steps[]}) — status se hlásí á 30 s;
// `diag` = čerstvě načtený status.diagnostics (prop `devices` se během čekání neobnovuje)
function progressText(diag) {
  const d = obj(diag)
  if (d.running !== true) return null
  const total = arr(d.steps).length, done = arr(d.done).length
  const step = txt(d.step_title ?? d.step)   // mezi kroky je step null → „?“
  return `krok ${step === '—' || step === '' ? '?' : step}${total ? ` (${Math.min(done + 1, total)}/${total})` : ''}`
}

// Trvání běhu v sekundách (started_at/finished_at řádku) — null = neznámé
function durationOf(r) {
  const a = new Date(r.started_at).getTime(), b = new Date(r.finished_at).getTime()
  return Number.isFinite(a) && Number.isFinite(b) && b >= a ? Math.round((b - a) / 1000) : null
}

// Načte celý report (sloupec `report` se v seznamu nečte — může mít stovky KiB) a vybere zobrazení
function ReportView({ row, deviceName }) {
  const [r, setR] = useState(null)
  const [err, setErr] = useState(null)
  useEffect(() => {
    let alive = true
    supabase.from('kiosk_diagnostics').select('report').eq('id', row.id).single()
      .then(({ data, error }) => { if (!alive) return; if (error) setErr(error.message); else setR(obj(data?.report)) })
    return () => { alive = false }
  }, [row.id])
  if (err) return <div className="text-[12px]" style={{ color: '#dc2626' }}>{err}</div>
  if (!r) return <div className="text-[12px]" style={{ color: '#6b8c7a' }}>Načítám report…</div>
  if (arr(r.protocol).length > 0) return <ProtocolView r={r} row={row} deviceName={deviceName} />
  return (
    <div>
      <div className="text-[11px] mt-2" style={{ color: '#6b8c7a' }}>Starší report bez protokolu — zobrazen jen technický detail sítě.</div>
      <NetworkDetail r={r} />
    </div>
  )
}

function RunRow({ r, deviceName, now, open, onToggle }) {
  const s = obj(r.summary), problems = arr(r.problems), warnings = arr(s.warnings)
  const age = ageSeconds(r.created_at, now)
  const devOk = num(s.devices_ok), devTotal = num(s.devices_total)
  const zOk = num(s.zones_ok), zTotal = num(s.zones_total)
  const mode = MODE_CZ[txt(s.mode)] || (s.checks ? 'kompletní' : 'jen síť')
  const dur = durationOf(r)
  const hasProtocol = !!s.checks   // summary.checks vyplňuje jen nová jednotka (report s `protocol`)
  return (
    <div className="p-2 rounded-lg" style={{ background: r.ok ? '#f8fcfa' : '#fff7f7', border: `1px solid ${r.ok ? '#d4e8e0' : '#fca5a5'}` }}>
      <div className="flex items-center gap-2 flex-wrap text-sm" style={{ color: '#1a2e22' }}>
        <Chip tone={r.ok ? 'green' : 'red'}>{r.ok ? 'OK' : `${problems.length} problémů`}</Chip>
        {warnings.length > 0 && <Chip tone="amber">{warnings.length} varování</Chip>}
        <span className="font-bold">{new Date(r.created_at).toLocaleString('cs-CZ')}</span>
        <span className="text-[11px]" style={{ color: '#6b8c7a' }}>({formatAge(age)})</span>
        <span className="text-[12px]">{deviceName} · {SOURCE_CZ[r.source] || txt(r.source)} · v{txt(r.app_version ?? '?')}</span>
        <Chip tone={mode === 'kompletní' ? 'blue' : 'gray'}>{mode}</Chip>
        {mode === 'kompletní' && zTotal != null && <Chip tone={zTotal > 0 && zOk === zTotal ? 'green' : 'amber'} title="Zóny bez problému / celkem (0 = nespárováno / bez HW mapy)">zóny {zOk ?? '?'}/{zTotal}</Chip>}
        <Chip tone={s.internet ? 'green' : 'red'}>{s.internet ? 'internet OK' : 'bez internetu'}</Chip>
        {s.lte != null && <Chip tone={s.lte === 'connected' ? 'blue' : 'amber'}>LTE {txt(s.lte)}</Chip>}
        <Chip tone={devOk != null && devOk === devTotal ? 'green' : 'amber'}>moduly {devOk ?? '?'}/{devTotal ?? '?'}</Chip>
        <Chip tone="gray">LAN {num(s.hosts) ?? '?'} zařízení</Chip>
        {dur != null && <Chip tone="gray">{dur} s</Chip>}
        <span className="ml-auto"><Btn tone="blue" small onClick={onToggle}>{open ? 'Skrýt' : hasProtocol ? 'Protokol' : 'Detail'}</Btn></span>
      </div>
      {problems.length > 0 && (
        <ul className="text-[12px] mt-1 ml-4" style={{ color: '#dc2626', listStyle: 'disc' }}>{problems.map((p, i) => <li key={i}>{txt(p)}</li>)}</ul>
      )}
      {open && <ReportView row={r} deviceName={deviceName} />}
    </div>
  )
}

function RpiDiagnosticsBlock(props) {
  return (
    <ErrorBoundary title="Kompletní diagnostika pobočky (Raspberry)">
      <RpiDiagnosticsInner {...props} />
    </ErrorBoundary>
  )
}

function RpiDiagnosticsInner({ branchId, devices, diags, cameras, now, onCommand }) {
  const rpis = arr(devices).filter(isRpiDevice)
  const [waiting, setWaiting] = useState(null)   // { deviceId, since, mode }
  const [open, setOpen] = useState(null)
  const [rows, setRows] = useState(arr(diags))
  const [prog, setProg] = useState(null)   // kiosk_devices.status.diagnostics jednotky, na kterou se čeká
  const devMap = Object.fromEntries(arr(devices).map(d => [d.id, d]))
  useEffect(() => { setRows(arr(diags)) }, [diags])

  // Vlastní lehké obnovení (bez spinneru celé záložky) — polling po spuštění z Velína
  const fetchRows = useCallback(async () => {
    const { data, error } = await supabase.from('kiosk_diagnostics').select(COLS).eq('branch_id', branchId)
      .order('created_at', { ascending: false }).limit(15)
    if (!error) setRows(arr(data))
  }, [branchId])

  // Průběh (krok X (n/m)) — status jednotky se čte zvlášť, `devices` z nadřazené záložky se během čekání nemění
  const fetchProgress = useCallback(async deviceId => {
    const { data, error } = await supabase.from('kiosk_devices').select('status').eq('id', deviceId).maybeSingle()
    if (!error) setProg(obj(obj(data?.status).diagnostics))
  }, [])

  useEffect(() => {
    if (!waiting) { setProg(null); return undefined }
    const arrived = rows.some(r => r.device_id === waiting.deviceId && new Date(r.created_at).getTime() > waiting.since)
    if (arrived || Date.now() - waiting.since > WAIT_MAX_MS) { setWaiting(null); return undefined }
    const t = setTimeout(() => { fetchRows(); fetchProgress(waiting.deviceId) }, POLL_MS)
    return () => clearTimeout(t)
  }, [waiting, rows, fetchRows, fetchProgress])

  if (rpis.length === 0) return null
  async function run(dev, mode) {
    const params = mode === 'network' ? { mode: 'network', reason: 'velin' } : { mode: 'full', cameras: camerasParam(cameras), reason: 'velin' }
    const ok = await onCommand(dev, 'diagnostics', params)
    if (ok) setWaiting({ deviceId: dev.id, since: Date.now(), mode })   // příkaz se nezařadil → nečekat na report
  }
  const progress = waiting ? progressText(prog) : null
  return (
    <RpiSection title="Kompletní diagnostika pobočky (Raspberry)"
      hint="Jedním tlačítkem prověří celou pobočku: řídicí jednotku (verze, teplota, disk, služby, health), síť (rozhraní, LTE, internet/DNS, spojení s Velínem), moduly Waveshare/Shelly, konfiguraci zón, HW každé zóny (světlo, zelená signalizace, tón, dveřní kontakt, klidový stav zámku, Shelly), napájení (FV), kamery a cizí zařízení v LAN. Výsledkem je protokol „kde je problém a co s tím“. HW test zón (světlo/zelená/tón) běží JEN v prázdných kójích bez aktivní relace — zámky se nikdy nespínají. Trvá 1–4 min; „jen síť“ = rychlý síťový běh (10–60 s)."
      action={<Btn tone="blue" small onClick={fetchRows}>Obnovit</Btn>}>
      <div className="flex items-center gap-2 flex-wrap mb-2">
        {rpis.map(dev => {
          const online = !!(dev.last_seen_at && (now - new Date(dev.last_seen_at).getTime()) < 70000)
          const busy = !!(waiting && waiting.deviceId === dev.id)
          const title = online ? 'Spustí kompletní diagnostiku na řídicí jednotce (trvá 1–4 min; zámky se nespínají)'
            : dev.last_seen_at ? 'Jednotka je offline' : 'Jednotka se ještě neozvala — spárujte ji (ID + token) na displeji'
          return (
            <span key={dev.id} className="inline-flex items-center gap-1">
              <Btn tone="dark" disabled={!online || busy} onClick={() => run(dev, 'full')} title={title}>
                🔍 Kompletní diagnostika — {txt(dev.name || 'Raspberry')}
              </Btn>
              <Btn tone="gray" small disabled={!online || busy} onClick={() => run(dev, 'network')} title="Jen síťové kroky (rozhraní, LTE, internet, Velín, moduly, LAN, ARP) — bez testu zón, 10–60 s">jen síť</Btn>
            </span>
          )
        })}
        {waiting && (
          <span className="text-[12px] font-bold" style={{ color: '#b45309' }}>
            ⏳ {waiting.mode === 'network' ? 'Diagnostika sítě běží' : 'Kompletní diagnostika běží (1–4 min)'}, čekám na report… ({Math.round((now - waiting.since) / 1000)} s){progress ? ` · ${progress}` : ''}
          </span>
        )}
      </div>
      {rows.length === 0 ? <EmptyState text="Zatím žádný report diagnostiky. Spusťte ji tlačítkem výše (jednotka musí být online) nebo kódem na displeji." /> : (
        <div className="space-y-1">
          {rows.map(r => (
            <RunRow key={r.id} r={r} now={now} deviceName={txt(devMap[r.device_id]?.name || 'Raspberry')}
              open={open === r.id} onToggle={() => setOpen(open === r.id ? null : r.id)} />
          ))}
        </div>
      )}
    </RpiSection>
  )
}

export { RpiDiagnosticsBlock }
