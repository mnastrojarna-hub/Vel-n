import { useState } from 'react'
import { EmptyState } from './BranchHelpers'
import { RpiSection, Btn, Chip, ErrorBoundary, formatUptime, ageSeconds, formatAge, txt, num, arr, isRpiDevice, ACCESSORIES_LABEL, boxLabel, isGeneratedZoneLabel } from './BranchRpiUi'
import { OutdoorTile } from './BranchRpiOutdoorTile'

// ─── Řídicí jednotka (Raspberry) — živý stav zón + příkazy ──────────────────
// Zdroj: kiosk_devices.status (snapshot z kontraktu §14, RPC kiosk_report_status),
// příkazy přes kiosk_commands (onCommand(device, command, params) → true/false).
// Hodnoty ze zařízení se vykreslují přes txt()/num() — JSON z jednotky nesmí shodit stránku.

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
// Stav I/O sítě (eth0) z health monitoru jednotky — `status.health.lan` (kontrakt §17).
// Bez tohohle bylo ve Velíně vidět jen „moduly červené" a nešlo poznat, jestli je vadný modul,
// nebo celá síťová cesta k nim (mrtvý kabel / vypnutý switch) — viz Pohořelice 2026-09-19.
const LAN_PROBLEM = {
  no_link: { text: 'I/O síť: eth0 bez linku', title: 'Raspberry nemá na ethernetu link — moduly Waveshare a Shelly jsou proto nedostupné VŠECHNY naráz. Zkontrolujte kabel z Raspberry do switche a napájení switche; tohle není závada modulů ani softwaru.' },
  no_address: { text: 'I/O síť: eth0 bez adresy', title: 'Ethernet má link, ale rozhraní nemá IP adresu (profil motogo-lan nenaskočil). Jednotka se ho sama pokouší nahodit; když to nepomůže, na Raspberry: sudo nmcli con up motogo-lan.' },
  missing: { text: 'I/O síť: eth0 chybí', title: 'Rozhraní eth0 na systému vůbec není (přejmenované nebo mrtvý ethernetový port). Bez něj se pobočka neovládá — je potřeba servisní zásah.' },
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

// Hlásí jednotka vůbec název pobočky? (starší software / první start ho nemá — pak nemá smysl porovnávat)
function hasStatusName(st) { return st && typeof st === 'object' && st.branch_name != null && st.branch_name !== '' }

// Řádek „Aktualizace: …“ ze status.update (kontrakt §14) — jen když není idle; null = nic nezobrazit
function updateLineOf(upd) {
  if (!upd || typeof upd !== 'object') return null
  const state = txt(upd.state ?? 'idle')
  const kind = upd.kind === 'system' ? 'OS' : 'software'
  const since = upd.since ? ` od ${new Date(txt(upd.since)).toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' })}` : ''
  if (state === 'waiting') return { text: `čeká na klid (${kind}${since}) — provede se, až v boxu nikdo nebude`, bg: '#fef3c7', color: '#b45309' }
  if (state === 'running') return { text: `probíhá (${kind}${since})`, bg: '#dbeafe', color: '#2563eb' }
  if (state === 'rebooting') return { text: 'restart OS', bg: '#fef3c7', color: '#b45309' }
  if (state === 'failed') return { text: `selhalo (${kind}) — ${txt(upd.error ?? 'neznámá chyba')}`, bg: '#fee2e2', color: '#dc2626' }
  if (state === 'done') return { text: `hotovo (${kind})`, bg: '#dcfce7', color: '#1a8a18' }
  return null
}

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

function RpiStatusBlock(props) {
  return (
    <ErrorBoundary title="Řídicí jednotka (Raspberry) — stav zón">
      <RpiStatusInner {...props} />
    </ErrorBoundary>
  )
}

function RpiStatusInner({ devices, doors, now, onCommand, branchName }) {
  const rpis = arr(devices).filter(isRpiDevice)
  if (rpis.length === 0) return null
  return (
    <RpiSection title="Řídicí jednotka (Raspberry) — stav zón"
      hint="Živý stav z řídicí jednotky (Modbus relé Waveshare + Shelly), hlásí se každých 30 s. Příkazy se doručí přes kiosk_commands — jednotka je vyzvedne do několika sekund.">
      <style>{KEYFRAMES}</style>
      <div className="space-y-3">
        {rpis.map(dev => <RpiDeviceCard key={dev.id} dev={dev} doors={doors} now={now} onCommand={onCommand} branchName={branchName} />)}
      </div>
    </RpiSection>
  )
}

function RpiDeviceCard({ dev, doors, now, onCommand, branchName }) {
  const [sent, setSent] = useState(null)
  const st = (dev.status && typeof dev.status === 'object' && !Array.isArray(dev.status)) ? dev.status : {}
  const online = !!(dev.last_seen_at && (now - new Date(dev.last_seen_at).getTime()) < ONLINE_MS)
  const neverSeen = !dev.last_seen_at
  const statusAge = ageSeconds(dev.status_at, now)
  const stale = statusAge == null || statusAge > STALE_S
  const zones = arr(st.zones).filter(z => z && typeof z === 'object').sort((a, b) => (num(a.zone) ?? 0) - (num(b.zone) ?? 0))
  const outdoor = st.outdoor && typeof st.outdoor === 'object' && !Array.isArray(st.outdoor) && st.outdoor.configured === true ? st.outdoor : null   // venek (zóna bez dveří)
  const modules = st.modules && typeof st.modules === 'object' && !Array.isArray(st.modules) ? Object.entries(st.modules) : []
  const health = st.health && typeof st.health === 'object' ? st.health : {}
  const lte = health.lte && typeof health.lte === 'object' ? health.lte : {}
  const lan = health.lan && typeof health.lan === 'object' ? health.lan : {}
  const lanBad = lan.ok === false ? (LAN_PROBLEM[txt(lan.problem)] || LAN_PROBLEM.no_link) : null
  const sys = health.sys && typeof health.sys === 'object' ? health.sys : {}
  const problems = arr(st.config_problems)
  const doorMap = Object.fromEntries(arr(doors).map(d => [d.id, d]))
  const cpuTemp = num(sys.cpu_temp), diskFree = num(sys.disk_free_pct)
  const playingZone = st.audio && typeof st.audio === 'object' ? num(st.audio.playing_zone) : null
  // Servisní terminál na displeji (kontrakt §27): připravená tlačítka má technik vždy, VOLNÉ psaní
  // příkazů jen dokud ho odsud nepovolíme (pak se samo zamkne) — displej si ho zapnout nemůže.
  const shellFree = st.shell && typeof st.shell === 'object' && st.shell.free === true
  const shellMin = shellFree ? Math.max(1, Math.ceil((num(st.shell.free_s) ?? 0) / 60)) : 0
  const updateLine = updateLineOf(st.update)
  // Název pobočky na DISPLEJI jednotky (status.branch_name) — jednotka ho bere výhradně z Velína (branches.name)
  // přes kiosk_heartbeat. Po přejmenování pobočky se propíše do 30 s; do té doby (nebo když je jednotka offline)
  // na displeji svítí starý název. Tady je vidět, co zákazník na pobočce právě čte, a jestli to sedí s Velínem.
  const shownName = st.branch_name == null || st.branch_name === '' ? '' : String(st.branch_name)
  const nameMismatch = !!(hasStatusName(st) && branchName && shownName !== String(branchName))

  async function send(command, params = {}, label) {
    const ok = await onCommand(dev, command, params)
    if (ok) setSent({ text: `Odesláno: ${label || command}`, ts: Date.now() })
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
        <span className="font-bold">{txt(dev.name || 'Raspberry')}</span>
        <Chip tone={online ? 'green' : neverSeen ? 'amber' : 'red'}>{online ? 'Online' : neverSeen ? 'Nespárováno' : 'Offline'}</Chip>
        {hasStatus && <span className="text-[11px]" style={{ color: '#6b8c7a' }}>v{txt(st.version ?? dev.app_version ?? '?')} · běží {formatUptime(st.uptime_s)}</span>}
        {st.ready === false && <Chip tone="amber">Nepřipraveno</Chip>}
        {hasStatus && <Chip tone={st.internet ? 'green' : 'red'} title="Připojení k internetu (LTE)">{st.internet ? 'Internet OK' : 'Bez internetu'}</Chip>}
        {lanBad && <Chip tone="red" title={lanBad.title}>{lanBad.text}{lan.state ? ` (${txt(lan.state)})` : ''}</Chip>}
        {lte.state != null && (
          <Chip tone={lte.state === 'connected' ? 'blue' : 'amber'} title={`LTE ${txt(lte.state)} · RSRP ${txt(lte.rsrp)} dBm · reconnectů ${txt(lte.reconnects ?? 0)} · USB resetů ${txt(lte.usb_resets ?? 0)}`}>
            LTE {txt(lte.operator ?? lte.state)}{num(lte.rssi) != null ? ` ${num(lte.rssi)} dBm` : ''}
          </Chip>
        )}
        {cpuTemp != null && <Chip tone={cpuTemp > 75 ? 'red' : cpuTemp > 65 ? 'amber' : 'gray'} title={`Throttled ${txt(sys.throttled)} · load ${txt(sys.load1)}`}>CPU {Math.round(cpuTemp)} °C</Chip>}
        {diskFree != null && <Chip tone={diskFree < 10 ? 'red' : 'gray'} title={`Volná RAM ${txt(sys.mem_free_pct)} %`}>Disk {Math.round(diskFree)} % volné</Chip>}
        <span className="ml-auto text-[11px] font-bold" style={{ color: stale ? '#b45309' : '#6b8c7a' }}>
          {stale && hasStatus ? '⚠ ' : ''}stav {formatAge(statusAge)}{stale && statusAge != null ? ' — nemusí být aktuální' : ''}
        </span>
      </div>

      {/* Název pobočky na displeji — musí být 1:1 s názvem pobočky ve Velíně */}
      {hasStatus && (
        <div className="text-[11px] mt-1" style={{ color: nameMismatch ? '#b45309' : '#6b8c7a' }}
          title="Název, který zákazník vidí v záhlaví displeje na pobočce. Jednotka ho bere VÝHRADNĚ z názvu pobočky ve Velíně — po přejmenování se propíše do 30 s (nebo hned tlačítkem „Synchronizovat konfiguraci“).">
          Na displeji pobočky: <b style={{ color: nameMismatch ? '#b45309' : '#1a2e22' }}>{shownName || '—'}</b>
          {nameMismatch && <> — ve Velíně je <b>{String(branchName)}</b>; jednotka si nový název stáhne do 30 s, jinak dejte „Synchronizovat konfiguraci“.</>}
        </div>
      )}

      {/* Moduly + konfigurace */}
      {hasStatus && (
        <div className="flex items-center gap-1.5 flex-wrap mt-2">
          <span className="text-[11px] font-extrabold uppercase" style={{ color: '#6b8c7a' }}>Moduly:</span>
          {modules.length === 0 && <span className="text-[11px]" style={{ color: '#6b8c7a' }}>—</span>}
          {modules.map(([name, ok]) => <Chip key={name} tone={ok ? 'green' : 'red'}>{txt(name)}</Chip>)}
          <span className="text-[11px] font-extrabold uppercase ml-2" style={{ color: '#6b8c7a' }}>Konfigurace:</span>
          <Chip tone={st.config_source === 'remote' ? 'blue' : 'amber'}>{st.config_source === 'remote' ? 'Velín' : st.config_source === 'local' ? 'lokální YAML' : '—'}</Chip>
          {playingZone != null && <Chip tone="green">♪ hraje zóna {playingZone}</Chip>}
        {shellFree && <Chip tone="amber" title="Na displeji pobočky jde teď psát libovolné příkazy (servisní terminál). Každý příkaz se zapisuje do Hlášení a chyb.">
          ⌨ Terminál odemčen ({shellMin} min)</Chip>}
        </div>
      )}
      {updateLine && (
        <div className="mt-2 p-2 rounded-lg text-[12px] font-bold" style={{ background: updateLine.bg, color: updateLine.color }}>
          Aktualizace: {updateLine.text}
        </div>
      )}
      {problems.length > 0 && (
        <div className="mt-2 p-2 rounded-lg text-[12px]" style={{ background: '#fee2e2', color: '#dc2626' }}>
          <div className="font-bold">Problémy konfigurace ({problems.length}):</div>
          {problems.map((p, i) => <div key={i}>• {txt(p)}</div>)}
        </div>
      )}

      {/* Globální příkazy */}
      <div className="flex items-center gap-2 flex-wrap mt-2 pt-2" style={{ borderTop: '1px dashed #d4e8e0' }}>
        <Btn tone="red" title="Nouzové vypnutí: zhasne světla ve všech kójích i venku, zastaví hudbu, vypne signalizaci a odjistí relé. Dveře NEODEMYKÁ ani nezamyká. Použijte, když něco svítí nebo hraje a nemá."
          onClick={() => confirmSend('Vypnout vše (zámky, světla, hudba, signalizace) na řídicí jednotce?', 'all_off', {}, 'Vše vypnout')}>Vše vypnout</Btn>
        <Btn tone="blue" title="Jednotka si HNED stáhne aktuální nastavení z Velína (hardware, dveře, kódy, hudbu) — jinak to udělá sama do 60 s. Použijte po úpravě nastavení, když nechcete čekat."
          onClick={() => send('sync_config', {}, 'Synchronizovat konfiguraci')}>Synchronizovat konfiguraci</Btn>
        <Btn tone="blue" title="Kterou pobočku mám před sebou? Na displeji této jednotky se zobrazí „Tady jsem 👋“ a signalizace VŠECH kójí 3× blikne zeleně. Slouží k rozpoznání, který řádek ve Velíně patří které fyzické jednotce — nic neotevírá, zákazníka to neomezí."
          onClick={() => send('identify', { label: 'Velín' }, 'Identifikuj')}>Identifikuj</Btn>
        <Btn tone="amber" title="Restartuje jen program jednotky (ne celý Raspberry). Trvá pár sekund, zóny se znovu načtou. První pomoc, když se něco zaseklo."
          onClick={() => confirmSend('Restartovat službu řídicí jednotky? Zóny se na pár sekund vypnou a znovu inicializují.', 'restart', {}, 'Restart služby')}>Restart služby</Btn>
        <Btn tone="amber" onClick={() => confirmSend('Aktualizovat software řídicí jednotky (git pull + restart)? Naplánuje se a provede se, až bude kóje volná (nikdo uprostřed relace). Výsledek poznáte podle hlášené verze a řádku „Aktualizace“ níže.', 'update_software', {}, 'Aktualizovat software')}>Aktualizovat software</Btn>
        <Btn tone="red" title="Restartuje celý počítač na pobočce. Cca minutu nejde zadat kód ani otevřít dveře — nedělejte, když je někdo v kóji."
          onClick={() => confirmSend('Rebootovat Raspberry Pi? Pobočka bude cca 1 minutu nedostupná.', 'reboot', {}, 'Reboot RPi')}>Reboot RPi</Btn>
        <Btn tone={shellFree ? 'red' : 'gray'}
          title={shellFree
            ? 'Zamkne volné psaní příkazů na displeji pobočky (připravená tlačítka terminálu zůstanou).'
            : 'Povolí na 30 minut psaní libovolných příkazů v servisním terminálu na displeji pobočky — pro technika, který je u skříně a řeší závadu. Terminál se otevře po zadání diagnostického kódu nebo servisního hesla, běží pod uživatelem motogo (ne root) a každý příkaz jde do Hlášení a chyb. Po 30 minutách se sám zamkne.'}
          onClick={() => confirmSend(shellFree
            ? 'Zamknout volné psaní příkazů na displeji pobočky?'
            : 'Povolit na 30 minut psaní libovolných příkazů na displeji pobočky? Kdo zná diagnostický kód, dostane na místě příkazovou řádku jednotky.',
            'shell_unlock', { minutes: shellFree ? 0 : 30 }, shellFree ? 'Zamknout terminál' : 'Odemknout terminál')}>
          {shellFree ? 'Zamknout terminál' : '⌨ Terminál na displeji'}</Btn>
        {sent && (now - sent.ts) < 60000 && <span className="text-[11px] font-bold" style={{ color: '#1a8a18' }}>{sent.text}</span>}
      </div>

      {/* Zóny */}
      <div className="mt-3">
        {!hasStatus ? (
          <EmptyState text={neverSeen
            ? 'Zatím nedorazil žádný stav — spárujte jednotku (ID + token) na displeji (setup obrazovka nebo servisní panel → Přepárovat).'
            : 'Zatím nedorazil žádný stav z řídicí jednotky (hlásí se každých 30 s po startu).'} />
        ) : zones.length === 0 ? (
          <EmptyState text="Jednotka nehlásí žádné zóny — zkontrolujte „Mapování dveří → zóny“ v bloku Řídicí jednotka (Raspberry) — hardware níže." />
        ) : (
          <div className="grid gap-2" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))' }}>
            {zones.map((z, i) => <ZoneTile key={`${txt(z.zone)}-${txt(z.door_id)}-${i}`} z={z} door={doorMap[z.door_id]} onSend={send} onConfirm={confirmSend} />)}
          </div>
        )}
        {/* Venek (zóna bez dveří) — za mřížkou zón, jen když je v HW mapě nastaven */}
        {hasStatus && outdoor && (
          <div className="grid gap-2 mt-2" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))' }}>
            <OutdoorTile o={outdoor} onSend={send} />
          </div>
        )}
      </div>
    </div>
  )
}

// Název zóny: vlastní popis (z jednotky / dveří) má přednost, jinak jednotné „Šatna" / „Kóje N".
// Automaticky složené popisy („Garáž #3 — Honda“, „Skříň oblečení“) se za vlastní NEPOVAŽUJÍ —
// stejné pravidlo má displej pobočky (ui/i18n.js), takže Velín i displej ukazují stejný název.
function zoneName(z, door) {
  const meta = { kind: z.kind ?? door?.door_kind, boxNumber: num(z.box_number) ?? door?.box_number ?? null, zone: z.zone }
  const custom = [z.label, door?.label].find(l => l != null && l !== '' && !isGeneratedZoneLabel(l, meta))
  if (custom) return txt(custom)
  if (meta.kind === 'accessories') return ACCESSORIES_LABEL
  if (meta.boxNumber != null) return boxLabel(meta.boxNumber)
  return `Zóna ${txt(z.zone)}`
}

function ZoneTile({ z, door, onSend, onConfirm }) {
  const [sig, setSig] = useState('')
  const state = txt(z.state ?? '').toUpperCase()
  const bg = STATE_BG[state] || '#f1faf7'
  const doorTxt = z.door_closed === true ? 'zavřené' : z.door_closed === false ? 'otevřené' : 'neznámé'
  const doorColor = z.door_closed === true ? '#1a8a18' : z.door_closed === false ? '#b45309' : '#6b8c7a'
  const name = zoneName(z, door)
  const zoneNo = num(z.zone)
  const zoneParams = { zone: zoneNo }
  const startedMs = z.session_started_at ? new Date(txt(z.session_started_at)).getTime() : NaN
  const started = Number.isFinite(startedMs) ? new Date(startedMs) : null
  const signalKey = txt(z.signal ?? '').toLowerCase()

  function pickSignal(v) {
    setSig('')
    if (!v) return
    onSend('set_signal', { zone: zoneNo, signal: v }, `signál ${SIGNAL_CZ[v] || v} (zóna ${txt(zoneNo)})`)
  }

  return (
    <div className="p-2 rounded-card" style={{ background: bg, border: `1px solid ${state === 'FAULT' ? '#fca5a5' : '#d4e8e0'}` }}>
      <div className="flex items-center gap-2">
        <span className="font-extrabold" style={{ color: '#0f1a14', fontSize: 15 }}>{txt(z.zone)}</span>
        <span className="font-bold text-sm truncate" style={{ color: '#1a2e22' }} title={name}>{name}</span>
        <span className="ml-auto"><SignalDot signal={signalKey} /></span>
      </div>
      <div className="text-[12px] mt-1" style={{ color: state === 'FAULT' ? '#dc2626' : '#1a2e22' }}>
        <span className="font-bold">{STATE_CZ[state] || state || '—'}</span>
        {state === 'FAULT' && z.fault != null && <span> — {FAULT_CZ[txt(z.fault)] || txt(z.fault)}</span>}
      </div>
      <div className="flex items-center gap-1.5 flex-wrap mt-1 text-[11px]" style={{ color: '#6b8c7a' }}>
        <span>dveře <b style={{ color: doorColor }}>{doorTxt}</b></span>
        <span>· světlo <b style={{ color: z.light ? '#b45309' : '#6b8c7a' }}>{z.light ? 'svítí' : 'zhasnuto'}</b></span>
        <span title={z.music_enabled === false ? 'Hudba je v této zóně vypnutá — po zadání kódu se nespustí (nastavení „Hudba“ u dveří nebo hlavní vypínač v sekci Audio)' : undefined}>
          · hudba <b style={{ color: z.music ? '#1a8a18' : z.music_enabled === false ? '#b45309' : '#6b8c7a' }}>
            {z.music ? 'hraje' : z.music_enabled === false ? 'vypnuta' : 'ne'}</b>
        </span>
        <span>· signál {SIGNAL_CZ[signalKey] || (signalKey ? signalKey : '—')}</span>
      </div>
      {(z.booking_id || started) && (
        <div className="text-[11px] mt-0.5" style={{ color: '#2563eb' }} title={txt(z.booking_id ?? '')}>
          {z.booking_id ? `rezervace ${txt(z.booking_id).slice(0, 8)}…` : 'relace'}{started ? ` od ${started.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' })}` : ''}
        </div>
      )}
      {z.last_event != null && <div className="text-[10px] mt-0.5" style={{ color: '#6b8c7a' }}>posl. událost: {txt(z.last_event)}</div>}
      <div className="flex items-center gap-1 flex-wrap mt-2 pt-2" style={{ borderTop: '1px dashed #d4e8e0' }}>
        <Btn tone="dark" small
          onClick={() => onConfirm(`Otevřít ${name} (zóna ${txt(zoneNo)})? Zámek dostane impulz a spustí se plná přístupová sekvence.`, 'open_door',
            { door_id: z.door_id ?? null, zone: zoneNo, box_number: num(z.box_number), label: name }, `Otevřít ${name}`)}>Otevřít</Btn>
        <Btn tone={z.light ? 'amber' : 'gray'} small title={z.light ? 'Zhasnout světlo' : 'Rozsvítit světlo'}
          onClick={() => onSend(z.light ? 'light_off' : 'light_on', zoneParams, `světlo ${z.light ? '⏹' : '▶'} (zóna ${txt(zoneNo)})`)}>
          Světlo {z.light ? '⏹' : '▶'}
        </Btn>
        <Btn tone={z.music ? 'red' : 'green'} small
          title={z.music ? 'Zastavit hudbu, která teď v této zóně hraje.'
            : z.music_enabled === false ? 'Ruční zkušební spuštění. Hudba je v této zóně vypnutá, takže po zadání kódu se sama nespustí.'
              : 'Spustit hudbu v této zóně (ručně, mimo relaci).'}
          onClick={() => onSend(z.music ? 'music_off' : 'music_on', zoneParams, `hudba ${z.music ? '⏹' : '▶'} (zóna ${txt(zoneNo)})`)}>
          Hudba {z.music ? '⏹' : '▶'}
        </Btn>
        <select value={sig} onChange={e => pickSignal(e.target.value)} title="Ruční nastavení signalizace"
          className="rounded-btn text-[11px] font-bold outline-none cursor-pointer" style={{ padding: '4px 6px', background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="">Signál…</option>
          {SIGNALS.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
        </select>
        <Btn tone="blue" small title="Zkontroluje, že v této kóji funguje světlo, barevná signalizace a reproduktor — postupně je na chvíli zapne. Zámek se NESEPNE, takže se dveře neotevřou. Dělejte na prázdné kóji."
          onClick={() => onSend('zone_test', zoneParams, `test zóny ${txt(zoneNo)}`)}>Test zóny</Btn>
      </div>
    </div>
  )
}

export { RpiStatusBlock }
