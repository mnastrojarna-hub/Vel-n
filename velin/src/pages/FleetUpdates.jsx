import { useState, useEffect, useCallback, useRef } from 'react'
import Card from '../components/ui/Card'
import { Spinner } from './BranchHelpers'
import { ErrorBoundary, Chip, Btn } from './BranchRpiUi'
import {
  DEFAULT_SETTINGS, ROLLOUT_STATUS_TONE, versionMatches, isOnline, fmtDT, phaseText, loadFleetData, sendDeviceCommand, fleetRpc,
  saveFleetSettings, deviceLabel,
} from './fleetUpdateHelpers'
import { ReleasesList, DevicesTable, RolloutPanel, SettingsForm, HistoryList, StartDialog } from './FleetUpdatesParts'

// ─── Aktualizace řídicích jednotek (všechny pobočky) — blok na stránce Pobočky ──
// Kontrakt §6: sbalená karta se souhrnem; po rozbalení releasy, tabulka jednotek (verze + OS), spuštění rolloutu
// (kanárek → soak → zbytek), průběh aktivního rolloutu (auto-refresh 15 s jen dokud běží), nastavení noční automatiky a historie.
// Pojistky: nikdy neaktualizuje samo při pushi; restart programu na jednotce jen když v boxu nikdo není.

const REFRESH_ACTIVE_MS = 15 * 1000

export default function FleetUpdatesBlock() {
  return (
    <ErrorBoundary title="Aktualizace řídicích jednotek">
      <FleetUpdatesInner />
    </ErrorBoundary>
  )
}

function FleetUpdatesInner() {
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [notice, setNotice] = useState(null)
  const [busy, setBusy] = useState(false)
  const [data, setData] = useState({ releases: [], devices: [], settings: DEFAULT_SETTINGS, active: null, activeRows: [], history: [] })
  const [form, setForm] = useState(DEFAULT_SETTINGS)
  const [dialog, setDialog] = useState(null)   // 'software' | 'system' | null
  const [now, setNow] = useState(Date.now())
  const formDirty = useRef(false)

  const load = useCallback(async () => {
    try {
      const d = await loadFleetData()
      setData(d)
      if (!formDirty.current) setForm(d.settings)
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
      setNow(Date.now())
    }
  }, [])

  // Načtení při mountu a při každém rozbalení; jinak jen po akcích a tlačítkem „Obnovit“ (žádný trvalý polling)
  useEffect(() => { if (open) load() }, [load, open])
  useEffect(() => { load() }, [load])
  // Auto-refresh 15 s POUZE dokud běží rollout (kontrakt §6.4) — i ve sbaleném stavu kvůli chipu fáze v hlavičce
  useEffect(() => {
    if (!data.active) return undefined
    const t = setInterval(load, REFRESH_ACTIVE_MS)
    return () => clearInterval(t)
  }, [load, data.active])
  useEffect(() => {
    if (!notice) return
    const t = setTimeout(() => setNotice(null), 8000)
    return () => clearTimeout(t)
  }, [notice])

  async function run(label, fn) {
    setBusy(true)
    try {
      await fn()
      if (label) setNotice(label)
      await load()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  const { releases, devices, settings, active, activeRows, history } = data
  const latest = releases[0] || null
  const devById = Object.fromEntries(devices.map(d => [d.id, d]))
  const seen = devices.filter(d => d.last_seen_at)
  const upToDate = latest ? seen.filter(d => versionMatches(d.app_version, latest.commit)).length : 0
  const onlineDevices = devices.filter(d => isOnline(d, now))

  function onDeviceCommand(dev, command, params, label) {
    const p = (command === 'update_system' || command === 'reboot') ? { wait_idle_s: settings.wait_idle_s, ...params } : params
    run(`Odesláno: ${label} → ${deviceLabel(dev)}`, () => sendDeviceCommand(dev, command, p))
  }
  function startRollout({ kind, canary, soak, wait, autoReboot }) {
    setDialog(null)
    run('Hromadná aktualizace spuštěna — kanárek dostal příkaz.', () => fleetRpc('kiosk_rollout_start', {
      p_kind: kind, p_release_id: kind === 'software' ? latest?.id : null, p_canary_device_id: canary || null,
      p_soak_minutes: soak, p_wait_idle_s: wait, p_auto_reboot: kind === 'system' ? !!autoReboot : false, p_mode: 'manual',
    }))
  }
  function cancelRollout() {
    if (!active || !window.confirm('Zrušit probíhající hromadnou aktualizaci? Jednotky, které už příkaz dostaly, ho dokončí; ostatní se netknou.')) return
    run('Rollout zrušen.', () => fleetRpc('kiosk_rollout_cancel', { p_id: active.id }))
  }
  function tickRollout() { run('Vyhodnoceno.', () => fleetRpc('kiosk_rollout_tick', {})) }
  function saveSettings() {
    run('Nastavení uloženo.', async () => { await saveFleetSettings(form); formDirty.current = false })
  }
  function updateForm(fn) { formDirty.current = true; setForm(fn) }

  // Souhrn na jednom řádku (i ve sbaleném stavu)
  const summary = loading ? 'Načítám…' : [
    latest ? `nejnovější ${latest.version} (${fmtDT(latest.committed_at || latest.created_at)})` : 'zatím žádný release',
    `${upToDate} z ${seen.length} jednotek aktuálních`,
    `noční automatika ${settings.nightly_enabled ? `zap. (${String(settings.nightly_hour).padStart(2, '0')}:00)` : 'vyp.'}`,
  ].join(' · ')

  return (
    <Card className="mb-5" style={{ padding: 0 }}>
      <button type="button" onClick={() => setOpen(o => !o)}
        className="w-full flex items-center gap-3 flex-wrap text-left cursor-pointer border-none bg-transparent"
        style={{ padding: '14px 20px' }}>
        <span style={{ color: '#1a2e22', fontSize: 14 }}>{open ? '▾' : '▸'}</span>
        <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Aktualizace řídicích jednotek (všechny pobočky)</span>
        <span className="text-[12px]" style={{ color: '#6b8c7a' }}>{summary}</span>
        {active && <Chip tone={ROLLOUT_STATUS_TONE[active.status]}>{phaseText(active, activeRows, devById)}</Chip>}
        {error && !open && <Chip tone="red">chyba načtení</Chip>}
      </button>

      {open && (
        <div className="space-y-5" style={{ padding: '0 20px 20px', borderTop: '1px solid #d4e8e0', paddingTop: 16 }}>
          {error && (
            <div className="p-3 rounded-card text-[12px] flex items-center gap-2 flex-wrap" style={{ background: '#fee2e2', color: '#dc2626' }}>
              <span>{error}</span>
              <button type="button" onClick={() => { setError(null); load() }} className="underline cursor-pointer font-bold" style={{ background: 'none', border: 'none', color: '#dc2626' }}>Zkusit znovu</button>
            </div>
          )}
          {notice && <div className="p-2 rounded-lg text-[12px] font-bold" style={{ background: '#dcfce7', color: '#1a8a18' }}>{notice}</div>}
          {loading ? <Spinner /> : (
            <>
              <div className="p-3 rounded-card text-[12px]" style={{ background: '#f1faf7', color: '#1a2e22' }}>
                <b>Pojistky:</b> aktualizace se NIKDY nespouští slepě při každém pushi — jen vědomě tlačítkem zde, nebo noční automatikou
                (výchozí 03:00, kdy v boxu nikdo není). Vždy nejdřív JEDNA pobočka (kanárek), po nastavené době sledování bez chyb zbytek.
                Program na jednotce se restartuje až ve chvíli, kdy v boxu nikdo není (nejdéle „čekání na klid“). Bezpečnostní záplaty OS
                instaluje unattended-upgrades v noci ve 4:00; restart OS jen odsud, nebo automaticky po novém jádru, když je box volný.
                Vrácení zpět = revert commitu v main a nový rollout.
              </div>
              <ReleasesList releases={releases} />
              <DevicesTable devices={devices} latest={latest} now={now} onDeviceCommand={onDeviceCommand} busy={busy} />
              <div className="flex items-center gap-2 flex-wrap">
                <Btn tone="dark" disabled={busy || !!active || !latest || onlineDevices.length === 0} onClick={() => setDialog('software')}
                  title={active ? 'Už běží hromadná aktualizace' : !latest ? 'Není žádný release' : onlineDevices.length === 0 ? 'Žádná jednotka online' : 'Kanárek → sledování → zbytek poboček'}>
                  Aktualizovat všechny pobočky
                </Btn>
                <Btn tone="blue" disabled={busy || !!active || onlineDevices.length === 0} onClick={() => setDialog('system')}
                  title={active ? 'Už běží hromadná aktualizace' : 'apt full-upgrade na všech jednotkách (kanárek → sledování → zbytek)'}>
                  Aktualizovat OS na všech pobočkách
                </Btn>
                <button type="button" onClick={load} disabled={busy} className="ml-auto text-[11px] font-bold cursor-pointer underline" style={{ background: 'none', border: 'none', color: '#6b8c7a' }}>
                  Obnovit (naposledy {new Date(now).toLocaleTimeString('cs-CZ')})
                </button>
              </div>
              {active && <RolloutPanel rollout={active} rows={activeRows} devById={devById} onCancel={cancelRollout} onTick={tickRollout} busy={busy} />}
              <SettingsForm form={form} setForm={updateForm} devices={devices} onSave={saveSettings} busy={busy} />
              <HistoryList history={history} />
            </>
          )}
        </div>
      )}

      {dialog && (
        <StartDialog kind={dialog} latest={latest} onlineDevices={onlineDevices} settings={settings} busy={busy}
          onClose={() => setDialog(null)} onStart={startRollout} />
      )}
    </Card>
  )
}
