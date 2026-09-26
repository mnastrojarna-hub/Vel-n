import { useState } from 'react'
import { Btn, txt, num, arr } from './BranchRpiUi'

// ─── Historie sítě + logy z reportu diagnostiky (`report.netlog`, jednotka od 2026-09-26) ──────────
// Vzorky health (á 30 s, 7 dní na jednotce) → výpadky internetu za 24 h / 7 dní (kdy, jak dlouho, stav LTE/modemu/
// kabelu, akce obnovy), události INTERNET_DOWN/UP + LTE_RESET/REBOOT, časová osa 24 h a syrové logy (NetworkManager,
// ModemManager, jádro USB/QMI, health, profily nmcli, trasy, DNS). Vše defenzivně — JSON ze zařízení.

const obj = v => (v && typeof v === 'object' && !Array.isArray(v) ? v : {})
const dur = s => { const n = num(s) ?? 0; return n >= 3600 ? `${Math.floor(n / 3600)} h ${Math.floor(n % 3600 / 60)} min` : n >= 60 ? `${Math.floor(n / 60)} min ${n % 60} s` : `${n} s` }
const when = iso => { const d = iso ? new Date(iso) : null; return d && !Number.isNaN(d.getTime()) ? d.toLocaleString('cs-CZ') : txt(iso) }
const LOG_CZ = {
  nm_connections: 'NetworkManager — profily', nm_devices: 'NetworkManager — zařízení', nm_lan_profile: 'Profil motogo-lan (method, adresy, brána, DNS, never-default, metrika, dhcp-timeout)',
  nm_lte_profile: 'Profil motogo-lte (typ, APN, DNS, metrika, autoconnect)', ip_route: 'Směrovací tabulka', ip_addr: 'Adresy rozhraní', resolved: 'DNS (resolvectl)',
  mmcli: 'ModemManager — modemy', usb: 'USB zařízení', journal_nm: 'Log NetworkManager (60 řádků)', journal_mm: 'Log ModemManager (40 řádků)',
  journal_health: 'Log motogo-health (60 řádků)', journal_kernel_usb: 'Log jádra — USB / QMI / eth0 (filtr)',
  lte_mode_log: 'Log přepínání režimu modemu (QMI/RNDIS)', lte_rndis_log: 'Log AT příkazů RNDIS', lte_mode_status: 'Režim modemu — stav (config, USB, profil, trasa)',
  usbreset_log: 'Log USB resetů modemu',
}

function Timeline({ series }) {
  const pts = arr(series).map(obj)
  if (!pts.length) return null
  return (
    <div className="flex flex-wrap gap-px mt-1" title="Časová osa 24 h: zelená = internet OK, červená = výpadek, šedá = neznámo; tmavší = modem pryč z USB">
      {pts.map((p, i) => (
        <span key={i} style={{ width: 4, height: 14, background: p.i === true ? '#22c55e' : p.i === false ? '#ef4444' : '#cbd5e1', opacity: p.m ? 0.55 : 1 }}
          title={`${when(new Date((num(p.ts) ?? 0) * 1000).toISOString())} · internet ${p.i === true ? 'OK' : p.i === false ? 'VÝPADEK' : '?'} · LTE ${txt(p.l)} RSSI ${txt(p.r)} · brána ${txt(p.g)}${p.m ? ' · modem pryč' : ''}`} />
      ))}
    </div>
  )
}

function Outages({ title, rows }) {
  const list = arr(rows).map(obj)
  return (
    <div className="mt-2">
      <div className="text-[11px] font-extrabold uppercase" style={{ color: '#6b8c7a' }}>{title} ({list.length})</div>
      {list.length === 0 ? <div className="text-[12px]" style={{ color: '#1a8a18' }}>bez výpadku</div> : (
        <table className="text-[12px]" style={{ borderCollapse: 'collapse', minWidth: '100%' }}>
          <thead><tr>{['Začátek', 'Konec', 'Délka', 'LTE', 'Modem', 'Kabel', 'Brána', 'Obnova'].map(h => <th key={h} className="text-left uppercase" style={{ padding: '2px 8px', color: '#6b8c7a', fontSize: 10, borderBottom: '1px solid #d4e8e0' }}>{h}</th>)}</tr></thead>
          <tbody>{list.map((o, i) => (
            <tr key={i} style={{ background: o.open ? '#fee2e2' : undefined }}>
              {[when(o.start_iso), o.open ? 'TRVÁ' : when(o.end_iso), dur(o.duration_s), txt(o.lte), o.modem_gone ? 'pryč z USB' : 'vidět', txt(o.lan ?? 'OK'), txt(o.gw_dev ?? '—'), arr(o.actions).map(txt).join(', ') || '—']
                .map((c, j) => <td key={j} style={{ padding: '3px 8px', borderBottom: '1px solid #eef6f2', color: '#1a2e22' }}>{c}</td>)}
            </tr>))}</tbody>
        </table>
      )}
    </div>
  )
}

// `n` = report.netlog
function NetlogDetail({ n }) {
  const [openLog, setOpenLog] = useState(null)
  const d = obj(n)
  if (!Object.keys(d).length) return <div className="text-[12px] mt-2" style={{ color: '#6b8c7a' }}>Historie sítě není v reportu (starší software jednotky — Aktualizovat software).</div>
  const logs = obj(d.logs), gw = obj(d.gw_now)
  return (
    <div className="mt-2 p-2 rounded-lg" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
      <div className="text-[12px]" style={{ color: '#1a2e22' }}>
        Vzorky: <b>{txt(d.samples_24h)}</b> za 24 h, <b>{txt(d.samples_7d)}</b> za 7 dní · výpadky 24 h: <b>{arr(d.outages_24h).length}× / {dur(d.downtime_24h_s)}</b> · 7 dní: <b>{arr(d.outages_7d).length}× / {dur(d.downtime_7d_s)}</b>
        · modem pryč z USB: <b>{txt(d.modem_gone_24h)}</b> vzorků · internet teď přes <b>{txt(gw.dev ?? 'nic')}</b>, DNS {txt(gw.dns ?? '—')}
      </div>
      <Timeline series={d.series_24h} />
      <Outages title="Výpadky internetu za 24 h" rows={d.outages_24h} />
      <Outages title="Výpadky internetu za 7 dní" rows={d.outages_7d} />
      <div className="mt-2">
        <div className="text-[11px] font-extrabold uppercase" style={{ color: '#6b8c7a' }}>Události sítě za 7 dní ({arr(d.events).length})</div>
        {arr(d.events).length === 0 ? <div className="text-[12px]" style={{ color: '#6b8c7a' }}>—</div> : (
          <div className="text-[12px] max-h-48 overflow-auto" style={{ color: '#1a2e22' }}>
            {arr(d.events).map((ev, i) => { const e = obj(ev), x = obj(e.detail); return <div key={i}>{when(e.ts)} · <b>{txt(e.kind)}</b> · {txt(e.message)}{x.duration_s != null ? ` (${dur(x.duration_s)})` : ''}</div> })}
          </div>
        )}
      </div>
      <div className="mt-2 flex flex-wrap gap-1">
        {Object.keys(logs).map(k => <Btn key={k} tone={openLog === k ? 'dark' : 'gray'} small onClick={() => setOpenLog(openLog === k ? null : k)}>{LOG_CZ[k] || k}</Btn>)}
      </div>
      {openLog && <pre className="text-[10px] mt-1 p-2 rounded-lg overflow-auto whitespace-pre-wrap" style={{ background: '#f1faf7', maxHeight: 360 }}>{txt(logs[openLog]) || '—'}</pre>}
    </div>
  )
}

export { NetlogDetail }
