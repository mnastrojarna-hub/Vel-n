import { useState } from 'react'
import Modal from '../components/ui/Modal'
import Button from '../components/ui/Button'
import { EmptyState } from './BranchHelpers'
import { RpiSection, Btn, Chip, Input, Select, Checkbox, txt } from './BranchRpiUi'
import {
  ROLLOUT_STATUS_CZ, ROLLOUT_STATUS_TONE, DEV_STATUS_CZ, DEV_STATUS_TONE, KIND_CZ, MODE_CZ,
  sha7, versionMatches, deviceSys, deviceUpdate, updateStateInfo, isOnline, fmtDT, fmtTime, deviceLabel, phaseText, rolloutErrorText,
  DEFAULT_SETTINGS, isIntInput, intInRange,
} from './fleetUpdateHelpers'

// ─── Části bloku „Aktualizace řídicích jednotek“ (FleetUpdates.jsx) ─────────

const thCls = 'text-left text-[11px] font-extrabold uppercase tracking-wide'
const thStyle = { padding: '6px 8px', color: '#6b8c7a', borderBottom: '1px solid #d4e8e0' }
const tdStyle = { padding: '6px 8px', fontSize: 12, color: '#0f1a14', borderBottom: '1px solid #eef6f2', verticalAlign: 'top' }
const TH = ({ children }) => <th className={thCls} style={thStyle}>{children}</th>
const TD = ({ children, mono, bold }) => <td style={{ ...tdStyle, fontFamily: mono ? 'monospace' : 'inherit', fontWeight: bold ? 700 : 500 }}>{children}</td>

// 1) Nejnovější verze
export function ReleasesList({ releases }) {
  return (
    <RpiSection title="Nejnovější verze programu"
      hint="Release = commit v main, který změnil raspberry/motogo-box (zapisuje GitHub Action release-motogo-box). Push do main NIKDY neaktualizuje jednotky sám — aktualizace se spouští vědomě tlačítkem níže nebo noční automatikou.">
      {releases.length === 0 ? <EmptyState text="Zatím žádný release v kiosk_releases." /> : (
        <div className="overflow-x-auto"><table className="w-full border-collapse">
          <thead><tr><TH>Verze</TH><TH>Commit</TH><TH>Zpráva</TH><TH>Datum</TH><TH>Autor</TH></tr></thead>
          <tbody>{releases.map((r, i) => (
            <tr key={r.id} style={{ background: i === 0 ? '#f1faf7' : 'transparent' }}>
              <TD bold>{txt(r.version)}{i === 0 && <Chip tone="green">nejnovější</Chip>}</TD>
              <TD mono>{sha7(r.commit)}</TD>
              <TD>{txt(r.message)}</TD>
              <TD>{fmtDT(r.committed_at || r.created_at)}</TD>
              <TD>{txt(r.author)}</TD>
            </tr>
          ))}</tbody>
        </table></div>
      )}
    </RpiSection>
  )
}

// 2) Tabulka jednotek — verze, online, aktuálnost, stav update, OS + akce
export function DevicesTable({ devices, latest, now, onDeviceCommand, busy }) {
  return (
    <RpiSection title="Řídicí jednotky (Raspberry) — verze a OS"
      hint="Každá jednotka hlásí svou verzi v heartbeatu; „aktuální“ = shoda s nejnovějším releasem. Bezpečnostní záplaty OS instaluje unattended-upgrades sám v noci ve 4:00 (bez restartu). Restart OS a plný apt full-upgrade se spouští jen odsud — jednotka je provede, až bude kóje volná.">
      {devices.length === 0 ? <EmptyState text="Žádná aktivní řídicí jednotka (Raspberry)." /> : (
        <div className="overflow-x-auto"><table className="w-full border-collapse">
          <thead><tr><TH>Pobočka</TH><TH>Jednotka</TH><TH>Verze</TH><TH>Stav</TH><TH>Aktualizace</TH><TH>OS</TH><TH>Akce</TH></tr></thead>
          <tbody>{devices.map(dev => {
            const online = isOnline(dev, now)
            const current = latest ? versionMatches(dev.app_version, latest.commit) : null
            const upd = updateStateInfo(deviceUpdate(dev))
            const sys = deviceSys(dev)
            return (
              <tr key={dev.id}>
                <TD bold>{txt(dev.branches?.name)}</TD>
                <TD>{txt(dev.name)}</TD>
                <TD mono>{txt(dev.app_version)}</TD>
                <TD>
                  <div className="flex gap-1 flex-wrap">
                    <Chip tone={online ? 'green' : dev.last_seen_at ? 'red' : 'amber'}>{online ? 'Online' : dev.last_seen_at ? 'Offline' : 'Nespárováno'}</Chip>
                    {current != null && dev.app_version && <Chip tone={current ? 'green' : 'amber'}>{current ? 'Aktuální' : 'Zastaralá'}</Chip>}
                  </div>
                </TD>
                <TD>{upd ? <span className="font-bold" style={{ color: upd.tone === 'red' ? '#dc2626' : upd.tone === 'green' ? '#1a8a18' : '#b45309' }}>{upd.text}</span> : <span style={{ color: '#6b8c7a' }}>—</span>}</TD>
                <TD>
                  <div>{txt(sys.os)}</div>
                  <div className="text-[11px]" style={{ color: '#6b8c7a' }}>
                    {sys.kernel ? `jádro ${txt(sys.kernel)}` : ''}{sys.last_unattended_at ? ` · záplaty ${fmtDT(sys.last_unattended_at)}` : ''}
                  </div>
                  {sys.reboot_required === true && <Chip tone="amber" title="OS má nainstalované nové jádro/knihovny — projeví se až po restartu OS">Restart OS potřebný</Chip>}
                </TD>
                <TD>
                  <div className="flex gap-1 flex-wrap">
                    <Btn tone="amber" small disabled={busy || !online} title={online ? 'Příkaz reboot — jednotka restartuje OS, až bude box volný (nikdo uprostřed relace)' : 'Jednotka je offline'}
                      onClick={() => { if (window.confirm(`Restartovat OS na „${deviceLabel(dev)}“? Provede se, až bude box volný (čeká nejdéle „čekání na klid“ z nastavení); pobočka pak bude cca 1 minutu nedostupná.`)) onDeviceCommand(dev, 'reboot', { wait_idle: true }, 'Restart OS') }}>Restart OS</Btn>
                    <Btn tone="blue" small disabled={busy || !online} title={online ? 'apt full-upgrade jen na této jednotce (až bude kóje volná)' : 'Jednotka je offline'}
                      onClick={() => { if (window.confirm(`Aktualizovat OS (apt full-upgrade) na „${deviceLabel(dev)}“? Naplánuje se a provede, až bude kóje volná. Restart OS po novém jádru se neprovede sám — spustíte ho tlačítkem „Restart OS“.`)) onDeviceCommand(dev, 'update_system', { auto_reboot: false }, 'Aktualizovat OS') }}>Aktualizovat OS</Btn>
                  </div>
                </TD>
              </tr>
            )
          })}</tbody>
        </table></div>
      )}
    </RpiSection>
  )
}

// 4) Probíhající rollout
export function RolloutPanel({ rollout, rows, devById, onCancel, onTick, busy }) {
  const canary = devById[rollout.canary_device_id]
  const sorted = [...rows].sort((a, b) => (a.role === 'canary' ? -1 : b.role === 'canary' ? 1 : deviceLabel(devById[a.device_id]).localeCompare(deviceLabel(devById[b.device_id]))))
  return (
    <div className="p-3 rounded-card" style={{ background: '#fef3c7', border: '1px solid #fde68a' }}>
      <div className="flex items-center gap-2 flex-wrap">
        <Chip tone={ROLLOUT_STATUS_TONE[rollout.status]}>{ROLLOUT_STATUS_CZ[rollout.status] || rollout.status}</Chip>
        <span className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>
          {KIND_CZ[rollout.kind] || rollout.kind}{rollout.kiosk_releases?.version ? ` ${rollout.kiosk_releases.version} (${sha7(rollout.target_commit)})` : ''} — {phaseText(rollout, rows, devById)}
        </span>
        <span className="text-[11px]" style={{ color: '#6b8c7a' }}>spuštěno {fmtDT(rollout.created_at)} ({MODE_CZ[rollout.mode] || rollout.mode})</span>
        <div className="ml-auto flex gap-1">
          <Btn tone="blue" disabled={busy} onClick={onTick} title="Ručně spustí vyhodnocení (jinak běží každých 5 min)">Zkontrolovat teď</Btn>
          <Btn tone="red" disabled={busy} onClick={onCancel}>Zrušit</Btn>
        </div>
      </div>
      <div className="text-[12px] mt-1" style={{ color: '#1a2e22' }}>
        Postup: kanárek „{canary ? deviceLabel(canary) : '?'}“ → sledování {rollout.soak_minutes} min bez chyb → zbytek poboček. Každá jednotka restartuje program až ve chvíli, kdy v boxu nikdo není (čeká max. {Math.round(rollout.wait_idle_s / 60)} min).
        {rollout.status === 'canary' && rollout.canary_started_at && ` Kanárek dostal příkaz ${fmtTime(rollout.canary_started_at)}.`}
      </div>
      <div className="overflow-x-auto mt-2"><table className="w-full border-collapse">
        <thead><tr><TH>Jednotka</TH><TH>Role</TH><TH>Stav</TH><TH>Verze před → po</TH><TH>Detail</TH></tr></thead>
        <tbody>{sorted.map(r => (
          <tr key={r.device_id}>
            <TD bold>{deviceLabel(devById[r.device_id])}</TD>
            <TD>{r.role === 'canary' ? 'kanárek' : 'flotila'}</TD>
            <TD><Chip tone={DEV_STATUS_TONE[r.status] || 'gray'}>{DEV_STATUS_CZ[r.status] || r.status}</Chip></TD>
            <TD mono>{txt(r.version_before)}{r.version_after ? ` → ${txt(r.version_after)}` : ''}</TD>
            <TD>{r.detail?.error ? <span style={{ color: '#dc2626' }}>{txt(r.detail.error)}</span> : r.detail?.reason === 'never_seen' ? 'nikdy se neozvala' : r.commanded_at ? `příkaz ${fmtTime(r.commanded_at)}` : '—'}</TD>
          </tr>
        ))}</tbody>
      </table></div>
    </div>
  )
}

// 5) Nastavení
export function SettingsForm({ form, setForm, devices, onSave, busy }) {
  const devOpts = [{ value: '', label: '— automaticky (první online) —' }, ...devices.map(d => ({ value: d.id, label: deviceLabel(d) }))]
  const hours = Array.from({ length: 24 }, (_, h) => ({ value: String(h), label: `${String(h).padStart(2, '0')}:00` }))
  const set = k => v => setForm(f => ({ ...f, [k]: v }))
  return (
    <RpiSection title="Nastavení automatiky"
      hint="Noční automatika: v nastavenou hodinu (výchozí 03:00, kdy v boxu nikdo není) se sama spustí aktualizace na nejnovější release, pokud nějaká jednotka zaostává — vždy přes kanárka a sledování. OS aktualizace (apt full-upgrade) běží jednou za N dní stejnou nocí; restart OS po novém jádru jen když je zapnutý a box je volný."
      action={<Btn tone="dark" disabled={busy} onClick={onSave}>Uložit nastavení</Btn>}>
      <div className="flex items-end gap-3 flex-wrap">
        <Checkbox label="Noční automatika software" checked={form.nightly_enabled} onChange={set('nightly_enabled')} />
        <Select label="Hodina (Praha)" value={String(form.nightly_hour ?? 3)} onChange={set('nightly_hour')} options={hours} width={110} />
        <Select label="Výchozí kanárek" value={form.canary_device_id || ''} onChange={set('canary_device_id')} options={devOpts} width={260} />
        <Input label="Sledování kanárka (min)" type="number" min={5} step={1} value={form.soak_minutes} onChange={set('soak_minutes')} width={150} invalid={!isIntInput(form.soak_minutes)} />
        <Input label="Čekání na klid (s)" type="number" min={0} step={1} value={form.wait_idle_s} onChange={set('wait_idle_s')} width={130} invalid={!isIntInput(form.wait_idle_s)}
          title="Jak dlouho jednotka nejdéle čeká, než v boxu nikdo nebude; potom aktualizaci provede i tak (prázdné = výchozí 1800 s)" />
      </div>
      <div className="flex items-end gap-3 flex-wrap mt-2">
        <Checkbox label="OS aktualizace automaticky" checked={form.system_enabled} onChange={set('system_enabled')} />
        <Input label="Každých N dní" type="number" min={1} step={1} value={form.system_every_days} onChange={set('system_every_days')} width={110} invalid={!isIntInput(form.system_every_days)} />
        <Checkbox label="Automatický restart OS po novém jádru (až bude box volný)" checked={form.system_auto_reboot} onChange={set('system_auto_reboot')} />
      </div>
      <div className="text-[11px] mt-2" style={{ color: '#6b8c7a' }}>
        Poslední noční běh: {form.last_nightly_date || '—'} · poslední OS aktualizace: {form.last_system_date || '—'}
      </div>
    </RpiSection>
  )
}

// 6) Historie
export function HistoryList({ history }) {
  return (
    <RpiSection title="Historie" hint="Posledních 10 dokončených hromadných aktualizací.">
      {history.length === 0 ? <EmptyState text="Zatím žádná hromadná aktualizace." /> : (
        <div className="overflow-x-auto"><table className="w-full border-collapse">
          <thead><tr><TH>Datum</TH><TH>Typ</TH><TH>Režim</TH><TH>Verze</TH><TH>Výsledek</TH><TH>Chyba</TH></tr></thead>
          <tbody>{history.map(r => {
            const res = r.result || {}
            return (
              <tr key={r.id}>
                <TD>{fmtDT(r.finished_at || r.created_at)}</TD>
                <TD>{KIND_CZ[r.kind] || r.kind}</TD>
                <TD>{MODE_CZ[r.mode] || r.mode}</TD>
                <TD mono>{r.kiosk_releases?.version ? `${r.kiosk_releases.version} (${sha7(r.target_commit)})` : '—'}</TD>
                <TD><Chip tone={ROLLOUT_STATUS_TONE[r.status]}>{ROLLOUT_STATUS_CZ[r.status]}</Chip> {res.total != null ? `${res.updated ?? 0}/${res.total} ok, ${res.failed ?? 0} chyb, ${res.offline ?? 0} offline` : ''}</TD>
                <TD>{r.error ? <span style={{ color: '#dc2626' }}>{rolloutErrorText(r.error)}</span> : '—'}</TD>
              </tr>
            )
          })}</tbody>
        </table></div>
      )}
    </RpiSection>
  )
}

// 3) Dialog spuštění rolloutu (software / OS)
export function StartDialog({ kind, latest, onlineDevices, settings, onClose, onStart, busy }) {
  const defaultCanary = onlineDevices.some(d => d.id === settings.canary_device_id) ? settings.canary_device_id : (onlineDevices[0]?.id || '')
  const [canary, setCanary] = useState(defaultCanary)
  const [soak, setSoak] = useState(settings.soak_minutes ?? 180)
  const [wait, setWait] = useState(settings.wait_idle_s ?? 1800)
  const [autoReboot, setAutoReboot] = useState(!!settings.system_auto_reboot)
  const isSw = kind === 'software'
  const numsOk = isIntInput(soak) && isIntInput(wait)   // prázdné pole NESMÍ znamenat 0 (pojistka 1 — čekání na klid)
  return (
    <Modal open title={isSw ? 'Aktualizovat software na všech pobočkách' : 'Aktualizovat OS na všech pobočkách'} onClose={onClose}>
      <div className="space-y-3 text-sm" style={{ color: '#1a2e22' }}>
        {isSw && <div className="p-2 rounded-lg" style={{ background: '#f1faf7' }}>
          Cíl: <b>{txt(latest?.version)}</b> ({sha7(latest?.commit)}) — {txt(latest?.message)}
        </div>}
        <div className="text-[12px]" style={{ color: '#6b8c7a' }}>
          Postup: 1) kanárek dostane příkaz a aktualizuje se, až bude kóje volná (čeká nejdéle „čekání na klid“); 2) sledování — bez chyb v logu po celou dobu soak; 3) zbytek poboček. Chyba nebo výpadek kanárka rollout zastaví, ostatní jednotky se netknou.
          {!isSw && ' OS: apt full-upgrade s bezpečnostními i běžnými balíky; restart po novém jádru jen s volbou níže (a jen když je box volný).'}
        </div>
        <Select label="Kanárek (první pobočka)" value={canary} onChange={setCanary} width="100%"
          options={onlineDevices.length ? onlineDevices.map(d => ({ value: d.id, label: deviceLabel(d) })) : [{ value: '', label: '— žádná jednotka online —' }]} />
        <div className="flex gap-3 flex-wrap">
          <Input label="Sledování kanárka (min)" type="number" min={5} step={1} value={soak} onChange={setSoak} width={170} invalid={!isIntInput(soak)} />
          <Input label="Čekání na klid (s)" type="number" min={0} step={1} value={wait} onChange={setWait} width={150} invalid={!isIntInput(wait)} />
        </div>
        {!isSw && <Checkbox label="Automatický restart OS po novém jádru (až bude box volný)" checked={autoReboot} onChange={setAutoReboot} />}
        <div className="flex gap-2 justify-end pt-2">
          <Button onClick={onClose}>Zrušit</Button>
          <Button green disabled={busy || !canary || !numsOk || (isSw && !latest)} title={numsOk ? undefined : 'Vyplňte celé číslo minut a sekund'}
            onClick={() => onStart({
              kind, canary, autoReboot,
              soak: intInRange(soak, 5, 1440, settings.soak_minutes ?? DEFAULT_SETTINGS.soak_minutes),
              wait: intInRange(wait, 0, 14400, settings.wait_idle_s ?? DEFAULT_SETTINGS.wait_idle_s),
            })}>Spustit</Button>
        </div>
      </div>
    </Modal>
  )
}
