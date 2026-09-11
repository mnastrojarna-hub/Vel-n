import { useState } from 'react'
import { Btn, txt, num, arr } from './BranchRpiUi'

// ─── Technický detail sítě z reportu diagnostiky (Raspberry) ────────────────
// Vykresluje syrové síťové tabulky reportu (`kiosk_diagnostics.report`): systém, rozhraní, LTE, internet/DNS,
// Velín, konfigurované moduly, scan LAN, ARP, kroky. U nových reportů (s `protocol`) je sbalený pod protokolem,
// u starých reportů (bez `protocol`) je to jediný detail. Report je JSON ze zařízení — každá hodnota přes txt()/arr().

const ms = v => (num(v) == null ? '—' : `${num(v)} ms`)
const obj = v => (v && typeof v === 'object' && !Array.isArray(v) ? v : {})
const yn = v => (v === true ? 'ano' : v === false ? 'NE' : '—')

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

// `r` = už načtený objekt reportu (načítá BranchRpiDiagnostics.jsx)
function NetworkDetail({ r }) {
  const [raw, setRaw] = useState(false)
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

export { NetworkDetail, obj }
