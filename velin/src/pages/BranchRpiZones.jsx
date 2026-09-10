import { useState } from 'react'
import { EmptyState } from './BranchHelpers'
import { RpiSection, Btn, Chip, formatUptime, ageSeconds, formatAge } from './BranchRpiUi'

// ─── Řídicí jednotka (Raspberry) — živý stav zón + příkazy ──────────────────
// Zdroj: kiosk_devices.status (snapshot z kontraktu §14, RPC kiosk_report_status),
// příkazy přes kiosk_commands (onCommand(device, command, params)).

const ONLINE_MS = 70 * 1000
const STALE_S = 90

const STATE_CZ = {
  SECURED: 'Zabezpečeno',
  WAITING_FOR_OPEN: 'Čeká na otevření',
  DOOR_OPEN: 'Dveře otevřené',
  CLOSED_CONFIRMATION: 'Zavírání',
  FAULT: 'Porucha',
}
const STATE_BG = {
  SECURED: '#f1faf7', WAITING_FOR_OPEN: '#fef3c7', DOOR_OPEN: '#dcfce7', CLOSED_CONFIRMATION: '#dbeafe', FAULT: '#fee2e2',
}
const FAULT_CZ = {
  io_offline: 'I/O modul nedostupný',
  forced_open: 'Násilné otevření',
  open_at_startup: 'Otevřeno při startu',
  lock_failed: 'Zámek nereagoval',
}
const SIGNALS = [
  { value: 'red', label: 'Červená' },
  { value: 'green', label: 'Zelená' },
  { value: 'off', label: 'Vypnuto' },
  { value: 'green_pulse', label: 'Zelená pulz' },
  { value: 'red_blink', label: 'Červená blik' },
  { value: 'both_blink', label: 'Obě blikají' },
]
const SIGNAL_CZ = Object.fromEntries(SIGNALS.map(s => [s.value, s.label]))

const KEYFRAMES = `
@keyframes rpiBlink { 0%,49% { opacity: 1 } 50%,100% { opacity: .15 } }
@keyframes rpiPulse { 0%,100% { opacity: 1 } 50% { opacity: .25 } }
`

function SignalDot({ signal }) {
  const s = String(signal || 'off').toLowerCase()
  const base = { width: 12, height: 12, borderRadius: 999, display: 'inline-block', border: '1px solid rgba(0,0,0,.08)' }
  let style = { ...base, background: '#d4e8e0' }
  if (s === 'red') style = { ...base, background: '#dc2626' }
  else if (s === 'green') style = { ...base, background: '#1a8a18' }
  else if (s === 'green_pulse') style = { ...base, background: '#1a8a18', animation: 'rpiPulse 1.5s ease-in-out infinite' }
  else if (s === 'red_blink') style = { ...base, background: '#dc2626', animation: 'rpiBlink 1s steps(1) infinite' }
  else if (s === 'both_blink') style = { ...base, background: 'linear-gradient(90deg,#dc2626 50%,#1a8a18 50%)', animation: 'rpiBlink 1s steps(1) infinite' }
  return <span style={style} title={SIGNAL_CZ[s] || s} />
}

function isRpi(dev) {
  const st = dev?.status
  return dev?.platform === 'rpi' || (st && typeof st === 'object' && Array.isArray(st.zones))
}

function RpiStatusBlock({ devices, doors, now, onCommand }) {
  const rpis = (devices || []).filter(isRpi)
  if (rpis.length === 0) return null
  return (
    <RpiSection title="Řídicí jednotka (Raspberry) — stav zón"
      hint="Živý stav z řídicí jednotky (Modbus relé + Shelly). Příkazy se doručí přes kiosk_commands — jednotka je vyzvedne do několika sekund.">
      <style>{KEYFRAMES}</style>
      <div className="space-y-3">
        {rpis.map(dev => <RpiDeviceCard key={dev.id} dev={dev} doors={doors} now={now} onCommand={onCommand} />)}
      </div>
    </RpiSection>
  )
}

function RpiDeviceCard({ dev, doors, now, onCommand }) {
  const [sent, setSent] = useState(null)
  const st = (dev.status && typeof dev.status === 'object') ? dev.status : {}
  const online = !!(dev.last_seen_at && (now - new Date(dev.last_seen_at).getTime()) < ONLINE_MS)
  const statusAge = ageSeconds(dev.status_at, now)
  const stale = statusAge == null || statusAge > STALE_S
  const zones = Array.isArray(st.zones) ? [...st.zones].sort((a, b) => (a.zone ?? 0) - (b.zone ?? 0)) : []
  const modules = st.modules && typeof st.modules === 'object' ? Object.entries(st.modules) : []
  const lte = st.health?.lte || {}
  const sys = st.health?.sys || {}
  const problems = Array.isArray(st.config_problems) ? st.config_problems : []
  const doorMap = Object.fromEntries((doors || []).map(d => [d.id, d]))

  async function send(command, params = {}, label) {
    await onCommand(dev, command, params)
    setSent({ text: `Odesláno: ${label || command}`, ts: Date.now() })
  }
  function confirmSend(question, command, params, label) {
    if (window.confirm(question)) send(command, params, label)
  }

  const hasStatus = Object.keys(st).length > 0
  return (
    <div className="p-3 rounded-card" style={{ background: online ? '#f8fcfa' : '#fef3c7', border: `1px solid ${online ? '#d4e8e0' : '#fde68a'}` }}>
      {/* Hlavička */}
      <div className="flex items-center gap-2 flex-wrap text-sm" style={{ color: '#1a2e22' }}>
        <span style={{ width: 10, height: 10, borderRadius: 999, background: online ? '#1a8a18' : '#dc2626', display: 'inline-block' }} />
        <span className="font-bold">{dev.name || 'Raspberry'}</span>
        <Chip tone={online ? 'green' : 'red'}>{online ? 'Online' : 'Offline'}</Chip>
        <span className="text-[11px]" style={{ color: '#6b8c7a' }}>v{st.version || dev.app_version || '?'} · běží {formatUptime(st.uptime_s)}</span>
        {st.ready === false && <Chip tone="amber">Nepřipraveno</Chip>}
        <Chip tone={st.internet ? 'green' : 'red'} title="Připojení k internetu (LTE)">{st.internet ? 'Internet OK' : 'Bez internetu'}</Chip>
        {lte.state && (
          <Chip tone={lte.state === 'connected' ? 'blue' : 'amber'} title={`LTE ${lte.state} · RSRP ${lte.rsrp ?? '—'} dBm · reconnectů ${lte.reconnects ?? 0} · USB resetů ${lte.usb_resets ?? 0}`}>
            LTE {lte.operator || lte.state}{lte.rssi != null ? ` ${lte.rssi} dBm` : ''}
          </Chip>
        )}
        {sys.cpu_temp != null && <Chip tone={sys.cpu_temp > 75 ? 'red' : sys.cpu_temp > 65 ? 'amber' : 'gray'} title={`Throttled ${sys.throttled ?? '—'} · load ${sys.load1 ?? '—'}`}>CPU {Math.round(sys.cpu_temp)} °C</Chip>}
        {sys.disk_free_pct != null && <Chip tone={sys.disk_free_pct < 10 ? 'red' : 'gray'} title={`Volná RAM ${sys.mem_free_pct ?? '—'} %`}>Disk {Math.round(sys.disk_free_pct)} % volné</Chip>}
        <span className="ml-auto text-[11px] font-bold" style={{ color: stale ? '#b45309' : '#6b8c7a' }}>
          {stale ? '⚠ ' : ''}stav {formatAge(statusAge)}{stale && statusAge != null ? ' — nemusí být aktuální' : ''}
        </span>
      </div>

      {/* Moduly + konfigurace */}
      {hasStatus && (
        <div className="flex items-center gap-1.5 flex-wrap mt-2">
          <span className="text-[11px] font-extrabold uppercase" style={{ color: '#6b8c7a' }}>Moduly:</span>
          {modules.length === 0 && <span className="text-[11px]" style={{ color: '#6b8c7a' }}>—</span>}
          {modules.map(([name, ok]) => <Chip key={name} tone={ok ? 'green' : 'red'}>{name}</Chip>)}
          <span className="text-[11px] font-extrabold uppercase ml-2" style={{ color: '#6b8c7a' }}>Konfigurace:</span>
          <Chip tone={st.config_source === 'remote' ? 'blue' : 'amber'}>{st.config_source === 'remote' ? 'Velín' : st.config_source === 'local' ? 'lokální YAML' : '—'}</Chip>
          {st.audio?.playing_zone != null && <Chip tone="green">♪ hraje zóna {st.audio.playing_zone}</Chip>}
        </div>
      )}
      {problems.length > 0 && (
        <div className="mt-2 p-2 rounded-lg text-[12px]" style={{ background: '#fee2e2', color: '#dc2626' }}>
          <div className="font-bold">Problémy konfigurace ({problems.length}):</div>
          {problems.map((p, i) => <div key={i}>• {String(p)}</div>)}
        </div>
      )}

      {/* Globální příkazy */}
      <div className="flex items-center gap-2 flex-wrap mt-2 pt-2" style={{ borderTop: '1px dashed #d4e8e0' }}>
        <Btn tone="red" onClick={() => confirmSend('Vypnout vše (zámky, světla, hudba, signalizace) na řídicí jednotce?', 'all_off', {}, 'Vše vypnout')}>Vše vypnout</Btn>
        <Btn tone="blue" onClick={() => send('sync_config', {}, 'Synchronizovat konfiguraci')}>Synchronizovat konfiguraci</Btn>
        <Btn tone="blue" onClick={() => send('identify', { label: 'Velín' }, 'Identifikuj')}>Identifikuj</Btn>
        <Btn tone="amber" onClick={() => confirmSend('Restartovat službu řídicí jednotky? Zóny se na pár sekund vypnou a znovu inicializují.', 'restart', {}, 'Restart služby')}>Restart služby</Btn>
        <Btn tone="amber" onClick={() => confirmSend('Aktualizovat software řídicí jednotky (git pull + restart)?', 'update_software', {}, 'Aktualizovat software')}>Aktualizovat software</Btn>
        <Btn tone="red" onClick={() => confirmSend('Rebootovat Raspberry Pi? Pobočka bude cca 1 minutu nedostupná.', 'reboot', {}, 'Reboot RPi')}>Reboot RPi</Btn>
        {sent && (now - sent.ts) < 60000 && <span className="text-[11px] font-bold" style={{ color: '#1a8a18' }}>{sent.text}</span>}
      </div>

      {/* Zóny */}
      <div className="mt-3">
        {!hasStatus ? (
          <EmptyState text="Zatím nedorazil žádný stav z řídicí jednotky." />
        ) : zones.length === 0 ? (
          <EmptyState text="Jednotka nehlásí žádné zóny — zkontrolujte mapování dveří (blok Hardware níže)." />
        ) : (
          <div className="grid gap-2" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))' }}>
            {zones.map(z => <ZoneTile key={z.zone ?? z.door_id} z={z} door={doorMap[z.door_id]} onSend={send} onConfirm={confirmSend} />)}
          </div>
        )}
      </div>
    </div>
  )
}

function zoneName(z, door) {
  if (z.label) return z.label
  if (door?.label) return door.label
  if (z.kind === 'accessories') return 'Oblečení'
  if (z.box_number != null) return `Kóje ${z.box_number}`
  return `Zóna ${z.zone}`
}

function ZoneTile({ z, door, onSend, onConfirm }) {
  const [sig, setSig] = useState('')
  const state = String(z.state || '').toUpperCase()
  const bg = STATE_BG[state] || '#f1faf7'
  const doorTxt = z.door_closed === true ? 'zavřené' : z.door_closed === false ? 'otevřené' : 'neznámé'
  const doorColor = z.door_closed === true ? '#1a8a18' : z.door_closed === false ? '#b45309' : '#6b8c7a'
  const name = zoneName(z, door)
  const zoneParams = { zone: z.zone }
  const started = z.session_started_at ? new Date(z.session_started_at) : null

  function pickSignal(v) {
    setSig('')
    if (!v) return
    onSend('set_signal', { zone: z.zone, signal: v }, `signál ${SIGNAL_CZ[v] || v} (zóna ${z.zone})`)
  }

  return (
    <div className="p-2 rounded-card" style={{ background: bg, border: `1px solid ${state === 'FAULT' ? '#fca5a5' : '#d4e8e0'}` }}>
      <div className="flex items-center gap-2">
        <span className="font-extrabold" style={{ color: '#0f1a14', fontSize: 15 }}>{z.zone}</span>
        <span className="font-bold text-sm truncate" style={{ color: '#1a2e22' }} title={name}>{name}</span>
        <span className="ml-auto"><SignalDot signal={z.signal} /></span>
      </div>
      <div className="text-[12px] mt-1" style={{ color: state === 'FAULT' ? '#dc2626' : '#1a2e22' }}>
        <span className="font-bold">{STATE_CZ[state] || state || '—'}</span>
        {state === 'FAULT' && z.fault && <span> — {FAULT_CZ[z.fault] || z.fault}</span>}
      </div>
      <div className="flex items-center gap-1.5 flex-wrap mt-1 text-[11px]" style={{ color: '#6b8c7a' }}>
        <span>dveře <b style={{ color: doorColor }}>{doorTxt}</b></span>
        <span>· světlo <b style={{ color: z.light ? '#b45309' : '#6b8c7a' }}>{z.light ? 'svítí' : 'zhasnuto'}</b></span>
        <span>· hudba <b style={{ color: z.music ? '#1a8a18' : '#6b8c7a' }}>{z.music ? 'hraje' : 'ne'}</b></span>
        <span>· signál {SIGNAL_CZ[String(z.signal || '').toLowerCase()] || z.signal || '—'}</span>
      </div>
      {(z.booking_id || started) && (
        <div className="text-[11px] mt-0.5" style={{ color: '#2563eb' }} title={z.booking_id || ''}>
          {z.booking_id ? `rezervace ${String(z.booking_id).slice(0, 8)}…` : 'relace'}{started ? ` od ${started.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' })}` : ''}
        </div>
      )}
      {z.last_event && <div className="text-[10px] mt-0.5" style={{ color: '#6b8c7a' }}>posl. událost: {z.last_event}</div>}
      <div className="flex items-center gap-1 flex-wrap mt-2 pt-2" style={{ borderTop: '1px dashed #d4e8e0' }}>
        <Btn tone="dark" small
          onClick={() => onConfirm(`Otevřít ${name} (zóna ${z.zone})? Zámek dostane impulz a spustí se plná přístupová sekvence.`, 'open_door',
            { door_id: z.door_id ?? null, zone: z.zone, box_number: z.box_number ?? null, label: name }, `Otevřít ${name}`)}>Otevřít</Btn>
        <Btn tone={z.light ? 'amber' : 'gray'} small title={z.light ? 'Zhasnout světlo' : 'Rozsvítit světlo'}
          onClick={() => onSend(z.light ? 'light_off' : 'light_on', zoneParams, `světlo ${z.light ? '⏹' : '▶'} (zóna ${z.zone})`)}>
          Světlo {z.light ? '⏹' : '▶'}
        </Btn>
        <Btn tone={z.music ? 'red' : 'green'} small title={z.music ? 'Zastavit hudbu' : 'Spustit hudbu v této zóně'}
          onClick={() => onSend(z.music ? 'music_off' : 'music_on', zoneParams, `hudba ${z.music ? '⏹' : '▶'} (zóna ${z.zone})`)}>
          Hudba {z.music ? '⏹' : '▶'}
        </Btn>
        <select value={sig} onChange={e => pickSignal(e.target.value)} title="Ruční nastavení signalizace"
          className="rounded-btn text-[11px] font-bold outline-none cursor-pointer" style={{ padding: '4px 6px', background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="">Signál…</option>
          {SIGNALS.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
        </select>
        <Btn tone="blue" small title="Test světla, signalizace a audia (bez zámku)"
          onClick={() => onSend('zone_test', zoneParams, `test zóny ${z.zone}`)}>Test zóny</Btn>
      </div>
    </div>
  )
}

export { RpiStatusBlock }
