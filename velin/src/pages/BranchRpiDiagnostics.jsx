import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { EmptyState } from './BranchHelpers'
import { RpiSection, Btn, Chip, formatAge, ageSeconds } from './BranchRpiUi'

// ─── Diagnostika sítě řídicí jednotky (Raspberry) ───────────────────────────
// Spuštění: příkaz `diagnostics` (kiosk_commands) → RPi provede scan (rozhraní, LTE, internet,
// Velín, moduly, LAN, ARP) a uloží report přes RPC kiosk_report_diagnostics → tabulka kiosk_diagnostics.
// Stejný report se zobrazí i na displeji pobočky (kód z config.yaml / servisní heslo s účelem „diagnostika").

const WAIT_MAX_MS = 150 * 1000
const POLL_MS = 5000
const COLS = 'id, device_id, report_id, source, ok, problems, summary, app_version, started_at, finished_at, created_at'
const SOURCE_CZ = { local_code: 'kód na displeji', service_code: 'servisní heslo', service_panel: 'servisní panel', velin: 'Velín' }

function isRpi(dev) {
  const st = dev?.status
  return dev?.platform === 'rpi' || (st && typeof st === 'object' && Array.isArray(st.zones))
}

function Table({ head, rows }) {
  if (!rows.length) return <div className="text-[12px]" style={{ color: '#6b8c7a' }}>—</div>
  return (
    <div className="overflow-x-auto">
      <table className="text-[12px]" style={{ borderCollapse: 'collapse', minWidth: '100%' }}>
        <thead><tr>{head.map(h => <th key={h} className="text-left font-extrabold uppercase" style={{ padding: '2px 8px', color: '#6b8c7a', fontSize: 10, borderBottom: '1px solid #d4e8e0' }}>{h}</th>)}</tr></thead>
        <tbody>{rows.map((r, i) => <tr key={i}>{r.map((c, j) => <td key={j} style={{ padding: '3px 8px', borderBottom: '1px solid #eef6f2', color: '#1a2e22', verticalAlign: 'top' }}>{c ?? '—'}</td>)}</tr>)}</tbody>
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
      .then(({ data, error }) => { if (!alive) return; if (error) setErr(error.message); else setR(data?.report || {}) })
    return () => { alive = false }
  }, [row.id])
  if (err) return <div className="text-[12px]" style={{ color: '#dc2626' }}>{err}</div>
  if (!r) return <div className="text-[12px]" style={{ color: '#6b8c7a' }}>Načítám report…</div>
  const sys = r.system || {}, m = sys.metrics || {}, ifc = r.interfaces || {}, lte = r.lte || {}, inet = r.internet || {}, sb = r.supabase || {}, lan = r.lan || {}
  return (
    <div className="mt-2 p-2 rounded-lg" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
      <Sect title="Systém">
        <div className="text-[12px]" style={{ color: '#1a2e22' }}>
          {sys.hostname} · verze {r.version} · kernel {sys.kernel} · čas {sys.time} · NTP {yn(sys.ntp_synced)} · CPU {m.cpu_temp ?? '—'} °C · throttled {m.throttled ?? '—'} · disk {m.disk_free_pct ?? '—'} % volných · RAM {m.mem_free_pct ?? '—'} % · konfigurace {sys.config_source} · ready {yn(sys.ready)}
        </div>
      </Sect>
      <Sect title="Síťová rozhraní">
        <Table head={['Rozhraní', 'Stav', 'MAC', 'IPv4', 'IPv6']} rows={(ifc.interfaces || []).map(i => [i.name, i.state, i.mac, (i.ipv4 || []).map(a => `${a.addr}/${a.prefix}`).join(', '), (i.ipv6 || []).map(a => a.addr).join(', ')])} />
        <div className="text-[12px] mt-1" style={{ color: '#1a2e22' }}>Výchozí brány: {(ifc.default_routes || []).map(x => `${x.gateway} přes ${x.dev} (metrika ${x.metric ?? '—'})`).join('; ') || 'ŽÁDNÁ'} · DNS: {(ifc.dns || []).join(', ') || 'žádné'}</div>
      </Sect>
      <Sect title="LTE modem">
        <div className="text-[12px]" style={{ color: '#1a2e22' }}>stav {lte.state ?? '—'} · operátor {lte.operator ?? '—'} · {lte.access_tech ?? '—'} · registrace {lte.registration ?? '—'} · kvalita {lte.signal_quality ?? '—'} % · RSSI {lte.rssi ?? '—'} dBm · RSRP {lte.rsrp ?? '—'} dBm · RSRQ {lte.rsrq ?? '—'} dB · SNR {lte.snr ?? '—'} dB · NM {lte.nm_connection} {lte.nm_state ?? '—'} {lte.nm_device ? `(${lte.nm_device})` : ''}{lte.error ? ` · ${lte.error}` : ''}</div>
      </Sect>
      <Sect title="Internet a DNS">
        <Table head={['Test', 'Výsledek', 'Čas']} rows={[
          [`TCP ${inet.tcp?.host}:${inet.tcp?.port}`, inet.tcp?.open ? 'otevřeno' : `selhalo ${inet.tcp?.error || ''}`, `${inet.tcp?.ms ?? '—'} ms`],
          ...(inet.dns || []).map(d => [`DNS ${d.host}`, (d.addresses || []).join(', ') || d.error, `${d.ms} ms`]),
          ...(inet.http || []).map(h => [`HTTP ${h.url}`, h.status != null ? `HTTP ${h.status}` : h.error, `${h.ms} ms`]),
        ]} />
      </Sect>
      <Sect title="Spojení s Velínem">
        <div className="text-[12px]" style={{ color: '#1a2e22' }}>spárováno {yn(sb.paired)} · heartbeat {sb.ok == null ? '—' : sb.ok ? `OK ${sb.ms} ms` : `SELHAL (${sb.error})`} · čekající odeslání {sb.outbox_pending ?? '—'} · zařízení {sb.device_id ?? '—'}</div>
      </Sect>
      <Sect title="Konfigurovaná zařízení">
        <Table head={['Název', 'Typ', 'Adresa', 'TCP', 'Ping', 'Identifikace', 'V programu']} rows={(r.devices || []).map(d => {
          const id = d.identified || {}
          const ident = d.type === 'shelly_rgbww' ? (id.model ? `${id.model} ${id.id || ''} fw ${id.fw || '—'}` : '—') : (id.guess ? `${id.guess} (${id.coils} relé, ${id.inputs} DI)` : '—')
          return [d.name, d.type, `${d.host}:${d.port}`, d.reachable ? `dostupné ${d.ms} ms` : `NEDOSTUPNÉ ${d.error || ''}`, d.ping_ms != null ? `${d.ping_ms} ms` : '—', ident, d.online ? 'online' : 'offline']
        })} />
      </Sect>
      <Sect title={`Zařízení nalezená v LAN (${(lan.hosts || []).length}) — podsítě ${(lan.subnets || []).join(', ') || '—'}, porty ${(lan.ports || []).join(', ')}, prověřeno ${lan.scanned_hosts ?? '—'} adres${(lan.skipped_subnets || []).length ? `, přeskočeno ${lan.skipped_subnets.join(', ')}` : ''}`}>
        <Table head={['IP', 'MAC', 'Porty', 'Identifikace', 'V konfiguraci jako']} rows={(lan.hosts || []).map(h => {
          const ident = h.shelly ? `Shelly ${h.shelly.model || ''} ${h.shelly.id || ''}` : h.modbus ? `Modbus ${h.modbus.guess} (${h.modbus.coils} relé, ${h.modbus.inputs} DI)` : h.http ? `HTTP ${h.http.status} ${h.http.server || h.http.title || ''}` : '—'
          return [h.ip, h.mac, Object.keys(h.ports || {}).join(', '), ident, h.configured_as]
        })} />
      </Sect>
      <Sect title={`ARP (${(r.arp || []).length})`}>
        <Table head={['IP', 'MAC', 'Rozhraní', 'Stav']} rows={(r.arp || []).map(a => [a.ip, a.mac, a.dev, a.state])} />
      </Sect>
      <Sect title="Kroky">
        <Table head={['Krok', 'Výsledek', 'Trvání']} rows={Object.entries(r.steps || {}).map(([k, v]) => [k, v.ok ? 'OK' : `CHYBA ${v.error || ''}`, `${v.ms} ms`])} />
      </Sect>
      <div className="mt-2"><Btn tone="gray" small onClick={() => setRaw(x => !x)}>{raw ? 'Skrýt JSON' : 'Celý JSON'}</Btn></div>
      {raw && <pre className="text-[10px] mt-1 p-2 rounded-lg overflow-auto" style={{ background: '#f1faf7', maxHeight: 320 }}>{JSON.stringify(r, null, 2)}</pre>}
    </div>
  )
}

function RpiDiagnosticsBlock({ branchId, devices, diags, now, onCommand }) {
  const rpis = (devices || []).filter(isRpi)
  const [waiting, setWaiting] = useState(null)   // { deviceId, since }
  const [open, setOpen] = useState(null)
  const [rows, setRows] = useState(diags || [])
  const devMap = Object.fromEntries((devices || []).map(d => [d.id, d]))
  useEffect(() => { setRows(diags || []) }, [diags])

  // Vlastní lehké obnovení (bez spinneru celé záložky) — polling po spuštění z Velína
  const fetchRows = useCallback(async () => {
    const { data, error } = await supabase.from('kiosk_diagnostics').select(COLS).eq('branch_id', branchId)
      .order('created_at', { ascending: false }).limit(15)
    if (!error) setRows(data || [])
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
    await onCommand(dev, 'diagnostics', { reason: 'velin' })
    setWaiting({ deviceId: dev.id, since: Date.now() })
  }
  return (
    <RpiSection title="Diagnostika sítě (Raspberry)"
      hint="Kompletní scan: rozhraní, LTE, internet/DNS, spojení s Velínem, dostupnost Waveshare/Shelly, TCP scan LAN s identifikací zařízení, ARP. Stejný report se zobrazí i na displeji pobočky (kód z config.yaml nebo servisní heslo s účelem „diagnostika“)."
      action={<Btn tone="blue" small onClick={fetchRows}>Obnovit</Btn>}>
      <div className="flex items-center gap-2 flex-wrap mb-2">
        {rpis.map(dev => {
          const online = !!(dev.last_seen_at && (now - new Date(dev.last_seen_at).getTime()) < 70000)
          return (
            <Btn key={dev.id} tone="dark" disabled={!online || (waiting && waiting.deviceId === dev.id)} onClick={() => run(dev)}
              title={online ? 'Spustí diagnostiku na řídicí jednotce (trvá 10–60 s)' : 'Zařízení je offline'}>
              🔍 Spustit diagnostiku — {dev.name || 'Raspberry'}
            </Btn>
          )
        })}
        {waiting && <span className="text-[12px] font-bold" style={{ color: '#b45309' }}>⏳ Diagnostika běží, čekám na report… ({Math.round((now - waiting.since) / 1000)} s)</span>}
      </div>
      {rows.length === 0 ? <EmptyState text="Zatím žádný report diagnostiky." /> : (
        <div className="space-y-1">
          {rows.map(r => {
            const s = r.summary || {}
            const age = ageSeconds(r.created_at, now)
            return (
              <div key={r.id} className="p-2 rounded-lg" style={{ background: r.ok ? '#f8fcfa' : '#fff7f7', border: `1px solid ${r.ok ? '#d4e8e0' : '#fca5a5'}` }}>
                <div className="flex items-center gap-2 flex-wrap text-sm" style={{ color: '#1a2e22' }}>
                  <Chip tone={r.ok ? 'green' : 'red'}>{r.ok ? 'OK' : `${(r.problems || []).length} problémů`}</Chip>
                  <span className="font-bold">{new Date(r.created_at).toLocaleString('cs-CZ')}</span>
                  <span className="text-[11px]" style={{ color: '#6b8c7a' }}>({formatAge(age)})</span>
                  <span className="text-[12px]">{devMap[r.device_id]?.name || 'Raspberry'} · {SOURCE_CZ[r.source] || r.source || '—'} · v{r.app_version || '?'}</span>
                  <Chip tone={s.internet ? 'green' : 'red'}>{s.internet ? 'internet OK' : 'bez internetu'}</Chip>
                  {s.lte && <Chip tone={s.lte === 'connected' ? 'blue' : 'amber'}>LTE {s.lte}</Chip>}
                  <Chip tone={s.devices_ok === s.devices_total ? 'green' : 'amber'}>moduly {s.devices_ok ?? '?'}/{s.devices_total ?? '?'}</Chip>
                  <Chip tone="gray">LAN {s.hosts ?? '?'} zařízení</Chip>
                  <span className="ml-auto"><Btn tone="blue" small onClick={() => setOpen(open === r.id ? null : r.id)}>{open === r.id ? 'Skrýt' : 'Detail'}</Btn></span>
                </div>
                {(r.problems || []).length > 0 && (
                  <ul className="text-[12px] mt-1 ml-4" style={{ color: '#dc2626', listStyle: 'disc' }}>{r.problems.map((p, i) => <li key={i}>{String(p)}</li>)}</ul>
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
