import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { EmptyState } from './BranchHelpers'
import { RpiSection, Btn, Chip, ErrorBoundary, formatAge, ageSeconds, txt, num, arr, isRpiDevice } from './BranchRpiUi'

// ─── Diagnostika sítě řídicí jednotky (Raspberry) ───────────────────────────
// Spuštění: příkaz `diagnostics` (kiosk_commands) → RPi provede scan (rozhraní, LTE, internet,
// Velín, moduly, LAN, ARP) a uloží report přes RPC kiosk_report_diagnostics → tabulka kiosk_diagnostics.
// Stejný report se zobrazí i na displeji pobočky (kód z config.yaml / servisní heslo s účelem „diagnostika").
// Report je JSON ze zařízení — každá hodnota se vykresluje přes txt()/arr() (nevěřit tvaru).

const WAIT_MAX_MS = 150 * 1000
const POLL_MS = 5000
const COLS = 'id, device_id, report_id, source, ok, problems, summary, app_version, started_at, finished_at, created_at'
// `source` ukládá jednotka: velin (příkaz z Velína), service_panel, ui / diag_ui (kód zadaný na displeji —
// hlavní klávesnice / setup obrazovka), local_code, service_code (dokumentovaný enum)
const SOURCE_CZ = {
  local_code: 'kód na displeji', service_code: 'servisní heslo', service_panel: 'servisní panel', velin: 'Velín',
  ui: 'kód na displeji', diag_ui: 'kód na displeji (setup)',
}
const ms = v => (num(v) == null ? '—' : `${num(v)} ms`)
const obj = v => (v && typeof v === 'object' && !Array.isArray(v) ? v : {})

function Table({ head, rows }) {
  if (!rows.length) return <div className="text-[12px]" style={{ color: '#6b8c7a' }}>—</div>
  return (
    <div className="overflow-x-auto">
      <table className="text-[12px]" style={{ borderCollapse: 'collapse', minWidth: '100%' }}>
        <thead><tr>{head.map(h => <th key={h} className="text-left font-extrabold uppercase" style={{ padding: '2px 8px', color: '#6b8c7a', fontSize: 10, borderBottom: '1px solid #d4e8e0' }}>{h}</th>)}</tr></thead>
        <tbody>{rows.map((r, i) => <tr key={i}>{r.map((c, j) => <td key={j} style={{ padding: '3px 8px', borderBottom: '1px solid #eef6f2', color: '#1a2e22', verticalAlign: 'top' }}>{c === '' ? '—' : txt(c)}</td>)}</tr>)}</tbody>
      </table>
    </div>
  )
}

function Sect({ title, children }) {
  return (
    <div className="mt-2">
      <div className="text-[11px] font-extrabold uppercase" style={{ color: '#6b8c7a' }}>{title}</div>
      {children}
    </div>
  )
}

const yn = v => (v === true ? 'ano' : v === false ? 'NE' : '—')

function ReportDetail({ row }) {
  const [r, setR] = useState(null)
  const [err, setErr] = useState(null)
  const [raw, setRaw] = useState(false)
  useEffect(() => {
    let alive = true
    supabase.from('kiosk_diagnostics').select('report').eq('id', row.id).single()
      .then(({ data, error }) => { if (!alive) return; if (error) setErr(error.message); else setR(obj(data?.report)) })
    return () => { alive = false }
  }, [row.id])
  if (err) return <div className="text-[12px]" style={{ color: '#dc2626' }}>{err}</div>
  if (!r) return <div className="text-[12px]" style={{ color: '#6b8c7a' }}>Načítám report…</div>
  // Každý krok může chybět (timeout/chyba kroku → null) — všechny sekce se berou přes obj()/arr()
  const sys = obj(r.system), m = obj(sys.metrics), ifc = obj(r.interfaces), lte = obj(r.lte), inet = obj(r.internet), sb = obj(r.supabase), lan = obj(r.lan)
  const tcp = inet.tcp ? obj(inet.tcp) : null
  return (
    <div className="mt-2 p-2 rounded-lg" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
      <Sect title="Systém">
        <div className="text-[12px]" style={{ color: '#1a2e22' }}>
          {txt(sys.hostname)} · verze {txt(r.version)} · kernel {txt(sys.kernel)} · čas {txt(sys.time)} · NTP {yn(sys.ntp_synced)} · CPU {txt(m.cpu_temp)} °C · throttled {txt(m.throttled)} · disk {txt(m.disk_free_pct)} % volných · RAM {txt(m.mem_free_pct)} % · konfigurace {txt(sys.config_source)} · ready {yn(sys.ready)}
        </div>
      </Sect>
      <Sect title="Síťová rozhraní">
        <Table head={['Rozhraní', 'Stav', 'MAC', 'IPv4', 'IPv6']} rows={arr(ifc.interfaces).map(i => { const x = obj(i); return [x.name, x.state, x.mac, arr(x.ipv4).map(a => `${txt(obj(a).addr)}/${txt(obj(a).prefix)}`).join(', '), arr(x.ipv6).map(a => txt(obj(a).addr)).join(', ')] })} />
        <div className="text-[12px] mt-1" style={{ color: '#1a2e22' }}>Výchozí brány: {arr(ifc.default_routes).map(x => `${txt(obj(x).gateway)} přes ${txt(obj(x).dev)} (metrika ${txt(obj(x).metric)})`).join('; ') || 'ŽÁDNÁ'} · DNS: {arr(ifc.dns).map(txt).join(', ') || 'žádné'}</div>
      </Sect>
      <Sect title="LTE modem">
        <div className="text-[12px]" style={{ color: '#1a2e22' }}>stav {txt(lte.state)} · operátor {txt(lte.operator)} · {txt(lte.access_tech)} · registrace {txt(lte.registration)} · kvalita {txt(lte.signal_quality)} % · RSSI {txt(lte.rssi)} dBm · RSRP {txt(lte.rsrp)} dBm · RSRQ {txt(lte.rsrq)} dB · SNR {txt(lte.snr)} dB · NM {txt(lte.nm_connection)} {txt(lte.nm_state)} {lte.nm_device ? `(${txt(lte.nm_device)})` : ''}{lte.error ? ` · ${txt(lte.error)}` : ''}</div>
      </Sect>
      <Sect title="Internet a DNS">
        <Table head={['Test', 'Výsledek', 'Čas']} rows={[
          ...(tcp ? [[`TCP ${txt(tcp.host)}:${txt(tcp.port)}`, tcp.open ? 'otevřeno' : `selhalo ${txt(tcp.error ?? '')}`, ms(tcp.ms)]] : []),
          ...arr(inet.dns).map(d => { const x = obj(d); return [`DNS ${txt(x.host)}`, arr(x.addresses).map(txt).join(', ') || txt(x.error), ms(x.ms)] }),
          ...arr(inet.http).map(h => { const x = obj(h); return [`HTTP ${txt(x.url)}`, x.status != null ? `HTTP ${txt(x.status)}` : txt(x.error), ms(x.ms)] }),
        ]} />
        {!tcp && arr(inet.dns).length === 0 && arr(inet.http).length === 0 && <div className="text-[12px]" style={{ color: '#b45309' }}>Krok „internet“ neproběhl (timeout / chyba kroku — viz Kroky).</div>}
      </Sect>
      <Sect title="Spojení s Velínem">
        <div className="text-[12px]" style={{ color: '#1a2e22' }}>spárováno {yn(sb.paired)} · heartbeat {sb.ok == null ? '—' : sb.ok ? `OK ${ms(sb.ms)}` : `SELHAL (${txt(sb.error)})`} · čekající odeslání {txt(sb.outbox_pending)} · zařízení {txt(sb.device_id)}</div>
      </Sect>
      <Sect title="Konfigurovaná zařízení">
        <Table head={['Název', 'Typ', 'Adresa', 'TCP', 'Ping', 'Identifikace', 'V programu']} rows={arr(r.devices).map(dv => {
          const d = obj(dv), id = obj(d.identified)
          const ident = d.type === 'shelly_rgbww' ? (id.model ? `${txt(id.model)} ${txt(id.id ?? '')} fw ${txt(id.fw)}` : '—') : (id.guess ? `${txt(id.guess)} (${txt(id.coils)} relé, ${txt(id.inputs)} DI)` : '—')
          return [d.name, d.type, `${txt(d.host)}:${txt(d.port)}`, d.reachable ? `dostupné ${ms(d.ms)}` : `NEDOSTUPNÉ ${txt(d.error ?? '')}`, d.ping_ms != null ? ms(d.ping_ms) : '—', ident, d.online ? 'online' : 'offline']
        })} />
      </Sect>
      <Sect title={`Zařízení nalezená v LAN (${arr(lan.hosts).length}) — podsítě ${arr(lan.subnets).map(txt).join(', ') || '—'}, porty ${arr(lan.ports).map(txt).join(', ')}, prověřeno ${txt(lan.scanned_hosts)} adres${arr(lan.skipped_subnets).length ? `, přeskočeno ${arr(lan.skipped_subnets).map(txt).join(', ')}` : ''}`}>
        <Table head={['IP', 'MAC', 'Porty', 'Identifikace', 'V konfiguraci jako']} rows={arr(lan.hosts).map(hv => {
          const h = obj(hv), sh = obj(h.shelly), mb = obj(h.modbus), ht = obj(h.http)
          const ident = h.shelly ? `Shelly ${txt(sh.model ?? '')} ${txt(sh.id ?? '')}` : h.modbus ? `Modbus ${txt(mb.guess)} (${txt(mb.coils)} relé, ${txt(mb.inputs)} DI)` : h.http ? `HTTP ${txt(ht.status)} ${txt(ht.server ?? ht.title ?? '')}` : '—'
          return [h.ip, h.mac, Object.keys(obj(h.ports)).join(', '), ident, h.configured_as]
        })} />
      </Sect>
      <Sect title={`ARP (${arr(r.arp).length})`}>
        <Table head={['IP', 'MAC', 'Rozhraní', 'Stav']} rows={arr(r.arp).map(av => { const a = obj(av); return [a.ip, a.mac, a.dev, a.state] })} />
      </Sect>
      <Sect title="Kroky">
        <Table head={['Krok', 'Výsledek', 'Trvání']} rows={Object.entries(obj(r.steps)).map(([k, v]) => { const s = obj(v); return [k, s.ok ? 'OK' : `CHYBA ${txt(s.error ?? '')}`, ms(s.ms)] })} />
      </Sect>
      <div className="mt-2"><Btn tone="gray" small onClick={() => setRaw(x => !x)}>{raw ? 'Skrýt JSON' : 'Celý JSON'}</Btn></div>
      {raw && <pre className="text-[10px] mt-1 p-2 rounded-lg overflow-auto" style={{ background: '#f1faf7', maxHeight: 320 }}>{JSON.stringify(r, null, 2)}</pre>}
    </div>
  )
}

function RpiDiagnosticsBlock(props) {
  return (
    <ErrorBoundary title="Diagnostika sítě (Raspberry)">
      <RpiDiagnosticsInner {...props} />
    </ErrorBoundary>
  )
}

function RpiDiagnosticsInner({ branchId, devices, diags, now, onCommand }) {
  const rpis = arr(devices).filter(isRpiDevice)
  const [waiting, setWaiting] = useState(null)   // { deviceId, since }
  const [open, setOpen] = useState(null)
  const [rows, setRows] = useState(arr(diags))
  const devMap = Object.fromEntries(arr(devices).map(d => [d.id, d]))
  useEffect(() => { setRows(arr(diags)) }, [diags])

  // Vlastní lehké obnovení (bez spinneru celé záložky) — polling po spuštění z Velína
  const fetchRows = useCallback(async () => {
    const { data, error } = await supabase.from('kiosk_diagnostics').select(COLS).eq('branch_id', branchId)
      .order('created_at', { ascending: false }).limit(15)
    if (!error) setRows(arr(data))
  }, [branchId])

  useEffect(() => {
    if (!waiting) return undefined
    const arrived = rows.some(r => r.device_id === waiting.deviceId && new Date(r.created_at).getTime() > waiting.since)
    if (arrived || Date.now() - waiting.since > WAIT_MAX_MS) { setWaiting(null); return undefined }
    const t = setTimeout(fetchRows, POLL_MS)
    return () => clearTimeout(t)
  }, [waiting, rows, fetchRows])

  if (rpis.length === 0) return null
  async function run(dev) {
    const ok = await onCommand(dev, 'diagnostics', { reason: 'velin' })
    if (ok) setWaiting({ deviceId: dev.id, since: Date.now() })   // příkaz se nezařadil → nečekat na report
  }
  return (
    <RpiSection title="Diagnostika sítě (Raspberry)"
      hint="Kompletní scan řídicí jednotky: rozhraní, LTE, internet/DNS, spojení s Velínem, dostupnost Waveshare/Shelly, TCP scan LAN s identifikací zařízení, ARP. Stejný report se zobrazí i na displeji pobočky (diagnostický kód z config.yaml nebo servisní heslo s účelem „jen diagnostika sítě“)."
      action={<Btn tone="blue" small onClick={fetchRows}>Obnovit</Btn>}>
      <div className="flex items-center gap-2 flex-wrap mb-2">
        {rpis.map(dev => {
          const online = !!(dev.last_seen_at && (now - new Date(dev.last_seen_at).getTime()) < 70000)
          const title = online ? 'Spustí diagnostiku na řídicí jednotce (trvá 10–60 s)'
            : dev.last_seen_at ? 'Jednotka je offline' : 'Jednotka se ještě neozvala — spárujte ji (ID + token) na displeji'
          return (
            <Btn key={dev.id} tone="dark" disabled={!online || (waiting && waiting.deviceId === dev.id)} onClick={() => run(dev)} title={title}>
              🔍 Spustit diagnostiku — {txt(dev.name || 'Raspberry')}
            </Btn>
          )
        })}
        {waiting && <span className="text-[12px] font-bold" style={{ color: '#b45309' }}>⏳ Diagnostika běží, čekám na report… ({Math.round((now - waiting.since) / 1000)} s)</span>}
      </div>
      {rows.length === 0 ? <EmptyState text="Zatím žádný report diagnostiky. Spusťte ji tlačítkem výše (jednotka musí být online) nebo kódem na displeji." /> : (
        <div className="space-y-1">
          {rows.map(r => {
            const s = obj(r.summary), problems = arr(r.problems)
            const age = ageSeconds(r.created_at, now)
            const devOk = num(s.devices_ok), devTotal = num(s.devices_total)
            return (
              <div key={r.id} className="p-2 rounded-lg" style={{ background: r.ok ? '#f8fcfa' : '#fff7f7', border: `1px solid ${r.ok ? '#d4e8e0' : '#fca5a5'}` }}>
                <div className="flex items-center gap-2 flex-wrap text-sm" style={{ color: '#1a2e22' }}>
                  <Chip tone={r.ok ? 'green' : 'red'}>{r.ok ? 'OK' : `${problems.length} problémů`}</Chip>
                  <span className="font-bold">{new Date(r.created_at).toLocaleString('cs-CZ')}</span>
                  <span className="text-[11px]" style={{ color: '#6b8c7a' }}>({formatAge(age)})</span>
                  <span className="text-[12px]">{txt(devMap[r.device_id]?.name || 'Raspberry')} · {SOURCE_CZ[r.source] || txt(r.source)} · v{txt(r.app_version ?? '?')}</span>
                  <Chip tone={s.internet ? 'green' : 'red'}>{s.internet ? 'internet OK' : 'bez internetu'}</Chip>
                  {s.lte != null && <Chip tone={s.lte === 'connected' ? 'blue' : 'amber'}>LTE {txt(s.lte)}</Chip>}
                  <Chip tone={devOk != null && devOk === devTotal ? 'green' : 'amber'}>moduly {devOk ?? '?'}/{devTotal ?? '?'}</Chip>
                  <Chip tone="gray">LAN {num(s.hosts) ?? '?'} zařízení</Chip>
                  <span className="ml-auto"><Btn tone="blue" small onClick={() => setOpen(open === r.id ? null : r.id)}>{open === r.id ? 'Skrýt' : 'Detail'}</Btn></span>
                </div>
                {problems.length > 0 && (
                  <ul className="text-[12px] mt-1 ml-4" style={{ color: '#dc2626', listStyle: 'disc' }}>{problems.map((p, i) => <li key={i}>{txt(p)}</li>)}</ul>
                )}
                {open === r.id && <ReportDetail row={r} />}
              </div>
            )
          })}
        </div>
      )}
    </RpiSection>
  )
}

export { RpiDiagnosticsBlock }
