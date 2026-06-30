import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { Spinner, EmptyState } from './BranchHelpers'

// ─── Tab: Samoobsluha (kiosk) ─────────────────────────────────────────────
// Konfigurace samoobslužné pobočky pro kiosk appku:
//  - zařízení/tablety (kiosk_devices) — unikátní ID + token, online stav, vzdálené ovládání
//  - hudba + časování (branch_kiosk_config)
//  - mapování dveří na Shelly relé/světlo (branch_doors)
//  - servisní hesla (branch_service_codes)
const ONLINE_MS = 70 * 1000

function TabSelfService({ branchId, branchName, motos }) {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [cfg, setCfg] = useState(null)
  const [devices, setDevices] = useState([])
  const [doors, setDoors] = useState([])
  const [codes, setCodes] = useState([])
  const [events, setEvents] = useState([])
  const [cameras, setCameras] = useState([])
  const [power, setPower] = useState(null)
  const [logs, setLogs] = useState([])
  const [ota, setOta] = useState({})
  const [busy, setBusy] = useState(false)
  const [now, setNow] = useState(Date.now())

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 15000)
    return () => clearInterval(t)
  }, [])

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [c, dev, d, s, ev, cam, pw, lg, otaRow] = await Promise.all([
        supabase.from('branch_kiosk_config').select('*').eq('branch_id', branchId).maybeSingle(),
        supabase.from('kiosk_devices').select('*').eq('branch_id', branchId).order('created_at'),
        supabase.from('branch_doors').select('*').eq('branch_id', branchId).order('door_kind').order('box_number'),
        supabase.from('branch_service_codes').select('*').eq('branch_id', branchId).order('created_at'),
        supabase.from('branch_door_events').select('*').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(30),
        supabase.from('branch_cameras').select('*').eq('branch_id', branchId).order('sort_order').order('created_at'),
        supabase.from('branch_power_status').select('*').eq('branch_id', branchId).maybeSingle(),
        supabase.from('kiosk_logs').select('*').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(40),
        supabase.from('app_settings').select('value').eq('key', 'kiosk_app').maybeSingle(),
      ])
      setCfg(c.data || null)
      setDevices(dev.data || [])
      setDoors(d.data || [])
      setCodes(s.data || [])
      setEvents(ev.data || [])
      setCameras(cam.data || [])
      setPower(pw.data || null)
      setLogs(lg.data || [])
      setOta(otaRow.data?.value || {})
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }, [branchId])

  useEffect(() => { load() }, [load])

  async function ensureConfig() {
    setBusy(true)
    try {
      const { error } = await supabase.from('branch_kiosk_config').insert({ branch_id: branchId })
      if (error) throw error
      await load()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function saveCfg(patch) {
    setCfg(c => ({ ...c, ...patch }))
    try {
      const { error } = await supabase.from('branch_kiosk_config').update(patch).eq('branch_id', branchId)
      if (error) throw error
    } catch (e) { setError(e.message) }
  }

  // ── Zařízení ──
  async function addDevice(name) {
    setBusy(true)
    try {
      const { error } = await supabase.from('kiosk_devices').insert({ branch_id: branchId, name: name?.trim() || 'Nový tablet' })
      if (error) throw error
      await load()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }
  async function saveDevice(id, patch) {
    setDevices(ds => ds.map(d => d.id === id ? { ...d, ...patch } : d))
    try {
      const { error } = await supabase.from('kiosk_devices').update(patch).eq('id', id)
      if (error) throw error
    } catch (e) { setError(e.message) }
  }
  async function deleteDevice(id) {
    if (!window.confirm('Smazat zařízení? Tablet bude nutné znovu spárovat.')) return
    await supabase.from('kiosk_devices').delete().eq('id', id)
    await load()
  }
  async function sendCommand(device, command, params = {}) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const { error } = await supabase.from('kiosk_commands').insert({
        device_id: device.id, branch_id: branchId, command, params, created_by: user?.id || null,
      })
      if (error) throw error
    } catch (e) { setError(e.message) }
  }

  // ── Dveře ──
  async function ensureDoors() {
    setBusy(true)
    try {
      const existing = new Set(doors.filter(d => d.door_kind === 'motorcycle').map(d => d.box_number))
      const rows = []
      ;(motos || []).filter(m => m.box_number != null).forEach(m => {
        if (!existing.has(m.box_number)) {
          rows.push({ branch_id: branchId, door_kind: 'motorcycle', box_number: m.box_number, label: `Garáž #${m.box_number} — ${m.model || ''}`.trim() })
        }
      })
      if (!doors.some(d => d.door_kind === 'accessories')) {
        rows.push({ branch_id: branchId, door_kind: 'accessories', box_number: null, label: 'Skříň oblečení' })
      }
      if (rows.length) {
        const { error } = await supabase.from('branch_doors').insert(rows)
        if (error) throw error
      }
      await load()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }
  async function saveDoor(id, patch) {
    setDoors(ds => ds.map(d => d.id === id ? { ...d, ...patch } : d))
    try {
      const { error } = await supabase.from('branch_doors').update(patch).eq('id', id)
      if (error) throw error
    } catch (e) { setError(e.message) }
  }
  async function deleteDoor(id) {
    if (!window.confirm('Smazat tyto dveře?')) return
    await supabase.from('branch_doors').delete().eq('id', id)
    await load()
  }

  // ── OTA verze appky (globální, app_settings) ──
  async function saveOta(patch) {
    const next = { ...ota, ...patch }
    setOta(next)
    try {
      const { error } = await supabase.from('app_settings').upsert({ key: 'kiosk_app', value: next }, { onConflict: 'key' })
      if (error) throw error
    } catch (e) { setError(e.message) }
  }

  // ── Kamery ──
  async function addCamera() {
    setBusy(true)
    try {
      const { error } = await supabase.from('branch_cameras').insert({ branch_id: branchId, name: 'Nová kamera', kind: 'snapshot' })
      if (error) throw error
      await load()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }
  async function saveCamera(id, patch) {
    setCameras(cs => cs.map(c => c.id === id ? { ...c, ...patch } : c))
    try {
      const { error } = await supabase.from('branch_cameras').update(patch).eq('id', id)
      if (error) throw error
    } catch (e) { setError(e.message) }
  }
  async function deleteCamera(id) {
    if (!window.confirm('Smazat kameru?')) return
    await supabase.from('branch_cameras').delete().eq('id', id)
    await load()
  }

  // ── Servisní hesla ──
  async function addCode(code, label) {
    if (!code.trim()) return
    setBusy(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const { error } = await supabase.from('branch_service_codes').insert({
        branch_id: branchId, code: code.trim(), label: label.trim() || null, created_by: user?.id || null,
      })
      if (error) throw error
      await load()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }
  async function toggleCode(c) {
    await supabase.from('branch_service_codes').update({ is_active: !c.is_active }).eq('id', c.id)
    await load()
  }
  async function deleteCode(id) {
    if (!window.confirm('Smazat servisní heslo?')) return
    await supabase.from('branch_service_codes').delete().eq('id', id)
    await load()
  }

  // První online aktivní zařízení = přes něj se posílají vzdálené příkazy z panelu
  const onlineDevice = devices.find(d => d.is_active && d.last_seen_at && (now - new Date(d.last_seen_at).getTime()) < ONLINE_MS) || null
  async function remote(command, params = {}) {
    if (!onlineDevice) { setError('Žádný tablet na pobočce není online — vzdálené ovládání nedostupné.'); return }
    await sendCommand(onlineDevice, command, params)
  }

  if (loading) return <Spinner />

  return (
    <div className="space-y-5">
      {error && <div className="p-2 rounded-card text-sm" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>}

      {!cfg ? (
        <div className="p-4 rounded-card text-center" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <p className="text-sm mb-3" style={{ color: '#1a2e22' }}>Tato pobočka zatím nemá nastavený kiosk samoobsluhy.</p>
          <button onClick={ensureConfig} disabled={busy} className="rounded-btn text-sm font-bold cursor-pointer border-none"
            style={{ padding: '8px 16px', background: '#1a2e22', color: '#74FB71' }}>
            {busy ? 'Zakládám…' : 'Aktivovat samoobsluhu'}
          </button>
        </div>
      ) : (
        <>
          <ControlPanelBlock doors={doors} cfg={cfg} onlineDevice={onlineDevice} onRemote={remote} onRefresh={load} />
          <PowerBlock power={power} cfg={cfg} now={now} onSave={saveCfg} onRefresh={load} />
          <CamerasBlock cameras={cameras} onlineDevice={onlineDevice} busy={busy}
            onAdd={addCamera} onSave={saveCamera} onDelete={deleteCamera} onRemote={remote} />
          <DevicesBlock devices={devices} doors={doors} cfg={cfg} now={now} busy={busy}
            onAdd={addDevice} onSave={saveDevice} onDelete={deleteDevice} onCommand={sendCommand} />
          <KioskConfigBlock cfg={cfg} onSave={saveCfg} />
          <OtaBlock ota={ota} onSave={saveOta} />
          <DoorsBlock doors={doors} onEnsure={ensureDoors} onSave={saveDoor} onDelete={deleteDoor} busy={busy} />
          <ServiceCodesBlock codes={codes} onAdd={addCode} onToggle={toggleCode} onDelete={deleteCode} busy={busy} />
          <AuditBlock events={events} doors={doors} devices={devices} onRefresh={load} />
          <DiagnosticsBlock logs={logs} devices={devices} onRefresh={load} />
        </>
      )}
    </div>
  )
}

function Section({ title, hint, children, action }) {
  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <div>
          <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{title}</div>
          {hint && <div className="text-[12px]" style={{ color: '#6b8c7a' }}>{hint}</div>}
        </div>
        {action}
      </div>
      {children}
    </div>
  )
}

function Field({ label, value, onCommit, placeholder, type = 'text', width }) {
  const [v, setV] = useState(value ?? '')
  useEffect(() => { setV(value ?? '') }, [value])
  return (
    <label className="flex flex-col gap-0.5" style={{ width }}>
      <span className="text-[11px] font-bold" style={{ color: '#6b8c7a' }}>{label}</span>
      <input type={type} value={v} placeholder={placeholder}
        onChange={e => setV(e.target.value)}
        onBlur={() => { if ((v ?? '') !== (value ?? '')) onCommit(type === 'number' ? (parseInt(v) || 0) : v) }}
        className="rounded-btn text-sm outline-none"
        style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
    </label>
  )
}

function copy(text) { navigator.clipboard?.writeText(text) }

// ─── Ovládací panel pobočky (vzdálené ovládání přes online tablet) ────────────
function ControlPanelBlock({ doors, cfg, onlineDevice, onRemote, onRefresh }) {
  const motoDoors = doors.filter(d => d.door_kind === 'motorcycle')
  const accDoor = doors.find(d => d.door_kind === 'accessories')
  function open(d) {
    onRemote('open_door', { door_id: d.id, relay_url: d.relay_url, light_url: d.light_url, label: d.label })
  }
  return (
    <Section title="Ovládání pobočky"
      hint="Otevírání dveří a hudba na dálku — odešle se přes online tablet pobočky."
      action={
        <button onClick={onRefresh} className="rounded-btn text-sm font-bold cursor-pointer border-none"
          style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb' }}>Obnovit</button>
      }>
      <div className="p-3 rounded-card" style={{ background: onlineDevice ? '#f1faf7' : '#fef3c7', border: `1px solid ${onlineDevice ? '#d4e8e0' : '#fde68a'}` }}>
        <div className="flex items-center gap-2 mb-3 text-sm" style={{ color: '#1a2e22' }}>
          <span style={{ width: 10, height: 10, borderRadius: 999, background: onlineDevice ? '#1a8a18' : '#dc2626', display: 'inline-block' }} />
          {onlineDevice
            ? <span>Pobočka <strong>online</strong> — ovládá se přes „{onlineDevice.name || 'tablet'}“.</span>
            : <span><strong>Žádný tablet není online.</strong> Vzdálené ovládání je nedostupné.</span>}
          <div className="ml-auto flex gap-2">
            <button onClick={() => onRemote('music_on', { music_url: cfg.music_on_url })} disabled={!onlineDevice || !cfg.music_on_url}
              className="rounded-btn text-[12px] font-bold cursor-pointer border-none"
              style={{ padding: '5px 10px', background: '#dcfce7', color: '#1a8a18', opacity: (onlineDevice && cfg.music_on_url) ? 1 : 0.5 }}>Hudba ▶</button>
            <button onClick={() => onRemote('music_off', { music_url: cfg.music_off_url })} disabled={!onlineDevice || !cfg.music_off_url}
              className="rounded-btn text-[12px] font-bold cursor-pointer border-none"
              style={{ padding: '5px 10px', background: '#fee2e2', color: '#dc2626', opacity: (onlineDevice && cfg.music_off_url) ? 1 : 0.5 }}>Hudba ⏹</button>
          </div>
        </div>
        {doors.length === 0 ? (
          <EmptyState text="Nejsou nastavené dveře." />
        ) : (
          <div className="flex flex-wrap gap-2">
            {accDoor && <DoorOpenBtn door={accDoor} disabled={!onlineDevice} onClick={() => open(accDoor)} />}
            {motoDoors.map(d => <DoorOpenBtn key={d.id} door={d} disabled={!onlineDevice} onClick={() => open(d)} />)}
          </div>
        )}
      </div>
    </Section>
  )
}

function DoorOpenBtn({ door, disabled, onClick }) {
  const isAcc = door.door_kind === 'accessories'
  const configured = (door.relay_url || '').trim() !== ''
  const title = isAcc ? 'Oblečení' : `#${door.box_number}`
  return (
    <button onClick={onClick} disabled={disabled || !configured}
      title={!configured ? 'Dveře nemají nastavené relé' : (door.label || title)}
      className="rounded-card font-bold cursor-pointer border-none flex flex-col items-center"
      style={{
        padding: '10px 14px', minWidth: 84,
        background: isAcc ? '#dbeafe' : '#dcfce7',
        color: isAcc ? '#2563eb' : '#1a8a18',
        opacity: (disabled || !configured) ? 0.4 : 1,
        border: `1px solid ${configured ? 'transparent' : '#fca5a5'}`,
      }}>
      <span style={{ fontSize: 18 }}>{isAcc ? '🧥' : '🏍️'}</span>
      <span className="text-[13px] mt-0.5">{title}</span>
      <span className="text-[10px] font-extrabold uppercase mt-0.5">Otevřít</span>
    </button>
  )
}

// ─── Log otevření (audit) ─────────────────────────────────────────────────────
function AuditBlock({ events, doors, devices, onRefresh }) {
  const doorMap = Object.fromEntries(doors.map(d => [d.id, d]))
  const devMap = Object.fromEntries(devices.map(d => [d.id, d]))
  const kindLabel = { motorcycle: 'Motorka', accessories: 'Oblečení', service: 'Servis' }
  return (
    <Section title="Log otevření" hint="Posledních 30 událostí na pobočce."
      action={
        <button onClick={onRefresh} className="rounded-btn text-sm font-bold cursor-pointer border-none"
          style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb' }}>Obnovit</button>
      }>
      {events.length === 0 ? (
        <EmptyState text="Zatím žádné záznamy" />
      ) : (
        <div className="space-y-1 max-h-60 overflow-y-auto">
          {events.map(e => {
            const d = doorMap[e.door_id]
            const doorName = d ? (d.label || (d.door_kind === 'accessories' ? 'Oblečení' : `Koje #${d.box_number}`)) : '—'
            return (
              <div key={e.id} className="flex items-center gap-2 p-2 rounded-lg text-sm" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
                <span style={{ width: 8, height: 8, borderRadius: 999, background: e.success ? '#1a8a18' : '#dc2626', display: 'inline-block' }} />
                <span className="font-bold" style={{ color: '#0f1a14' }}>{doorName}</span>
                <span className="inline-block rounded-btn text-[9px] font-extrabold uppercase"
                  style={{ padding: '2px 6px', background: '#eef6f2', color: '#1a2e22' }}>{kindLabel[e.kind] || e.kind || '—'}</span>
                {devMap[e.device_id]?.name && <span className="text-[12px]" style={{ color: '#6b8c7a' }}>{devMap[e.device_id].name}</span>}
                {!e.success && <span className="text-[11px] font-bold" style={{ color: '#dc2626' }}>neúspěch</span>}
                <span className="ml-auto text-[12px]" style={{ color: '#6b8c7a' }}>{new Date(e.created_at).toLocaleString('cs-CZ')}</span>
              </div>
            )
          })}
        </div>
      )}
    </Section>
  )
}

// ─── Zařízení (tablety) + vzdálené ovládání ───────────────────────────────
function DevicesBlock({ devices, doors, cfg, now, busy, onAdd, onSave, onDelete, onCommand }) {
  const [name, setName] = useState('')
  return (
    <Section title="Zařízení (tablety)"
      hint="Každý tablet má unikátní ID + token (zadej je v appce při párování). Online = poslední ozvání < 70 s.">
      <div className="flex items-end gap-2 mb-3 flex-wrap">
        <label className="flex flex-col gap-0.5" style={{ width: 220 }}>
          <span className="text-[11px] font-bold" style={{ color: '#6b8c7a' }}>Název nového zařízení</span>
          <input value={name} onChange={e => setName(e.target.value)} placeholder="např. Brno — hlavní vchod"
            className="rounded-btn text-sm outline-none" style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </label>
        <button onClick={() => { onAdd(name); setName('') }} disabled={busy}
          className="rounded-btn text-sm font-bold cursor-pointer border-none"
          style={{ padding: '6px 12px', background: '#1a2e22', color: '#74FB71', opacity: busy ? 0.5 : 1 }}>Přidat zařízení</button>
      </div>
      {devices.length === 0 ? (
        <EmptyState text="Žádná zařízení. Přidej tablet a zadej jeho ID + token do appky." />
      ) : (
        <div className="space-y-2">
          {devices.map(dev => (
            <DeviceRow key={dev.id} dev={dev} doors={doors} cfg={cfg} now={now}
              onSave={onSave} onDelete={onDelete} onCommand={onCommand} />
          ))}
        </div>
      )}
    </Section>
  )
}

function DeviceRow({ dev, doors, cfg, now, onSave, onDelete, onCommand }) {
  const [doorId, setDoorId] = useState('')
  const online = dev.last_seen_at && (now - new Date(dev.last_seen_at).getTime()) < ONLINE_MS
  const lastSeen = dev.last_seen_at ? new Date(dev.last_seen_at).toLocaleString('cs-CZ') : 'nikdy'
  const selectedDoor = doors.find(d => d.id === doorId)

  function openRemote() {
    if (!selectedDoor) return
    onCommand(dev, 'open_door', {
      door_id: selectedDoor.id, relay_url: selectedDoor.relay_url,
      light_url: selectedDoor.light_url, label: selectedDoor.label,
    })
  }

  return (
    <div className="p-3 rounded-card" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
      <div className="flex items-center gap-2 flex-wrap mb-2">
        <span style={{ width: 10, height: 10, borderRadius: 999, background: online ? '#1a8a18' : '#dc2626', display: 'inline-block' }} />
        <Field label="Název" value={dev.name} onCommit={v => onSave(dev.id, { name: v })} width={200} />
        <span className="inline-block rounded-btn text-[9px] font-extrabold uppercase"
          style={{ padding: '2px 6px', background: online ? '#dcfce7' : '#fee2e2', color: online ? '#1a8a18' : '#dc2626' }}>
          {online ? 'Online' : 'Offline'}
        </span>
        <span className="text-[11px]" style={{ color: '#6b8c7a' }}>posl. {lastSeen}{dev.app_version ? ` · v${dev.app_version}` : ''}</span>
        <button onClick={() => onSave(dev.id, { is_active: !dev.is_active })}
          className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
          style={{ padding: '4px 8px', background: dev.is_active ? '#fef3c7' : '#dcfce7', color: dev.is_active ? '#b45309' : '#1a8a18' }}>
          {dev.is_active ? 'Deaktivovat' : 'Aktivovat'}
        </button>
        <button onClick={() => onDelete(dev.id)} className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
          style={{ padding: '4px 8px', background: '#fee2e2', color: '#dc2626' }}>Smazat</button>
      </div>

      {/* Párovací údaje */}
      <div className="flex items-center gap-2 flex-wrap mb-2 text-[12px]" style={{ color: '#1a2e22' }}>
        <span className="font-bold">ID:</span>
        <code style={{ background: '#eef6f2', padding: '2px 6px', borderRadius: 6 }}>{dev.id}</code>
        <button onClick={() => copy(dev.id)} className="rounded-btn text-[10px] font-bold cursor-pointer border-none" style={{ padding: '2px 6px', background: '#dbeafe', color: '#2563eb' }}>Kopírovat</button>
        <span className="font-bold ml-2">Token:</span>
        <code style={{ background: '#eef6f2', padding: '2px 6px', borderRadius: 6 }}>{dev.device_token}</code>
        <button onClick={() => copy(dev.device_token)} className="rounded-btn text-[10px] font-bold cursor-pointer border-none" style={{ padding: '2px 6px', background: '#dbeafe', color: '#2563eb' }}>Kopírovat</button>
      </div>

      {/* Vzdálené ovládání */}
      <div className="flex items-center gap-2 flex-wrap pt-2" style={{ borderTop: '1px dashed #d4e8e0' }}>
        <span className="text-[11px] font-extrabold uppercase" style={{ color: '#6b8c7a' }}>Na dálku:</span>
        <select value={doorId} onChange={e => setDoorId(e.target.value)}
          className="rounded-btn text-sm outline-none" style={{ padding: '5px 8px', background: '#fff', border: '1px solid #d4e8e0' }}>
          <option value="">— vyber dveře —</option>
          {doors.map(d => <option key={d.id} value={d.id}>{d.label || (d.door_kind === 'accessories' ? 'Oblečení' : `Koje #${d.box_number}`)}</option>)}
        </select>
        <button onClick={openRemote} disabled={!selectedDoor}
          className="rounded-btn text-[12px] font-bold cursor-pointer border-none"
          style={{ padding: '5px 10px', background: '#1a2e22', color: '#74FB71', opacity: selectedDoor ? 1 : 0.5 }}>Otevřít dveře</button>
        <button onClick={() => onCommand(dev, 'music_on', { music_url: cfg.music_on_url })} disabled={!cfg.music_on_url}
          className="rounded-btn text-[12px] font-bold cursor-pointer border-none" style={{ padding: '5px 10px', background: '#dcfce7', color: '#1a8a18', opacity: cfg.music_on_url ? 1 : 0.5 }}>Hudba ▶</button>
        <button onClick={() => onCommand(dev, 'music_off', { music_url: cfg.music_off_url })} disabled={!cfg.music_off_url}
          className="rounded-btn text-[12px] font-bold cursor-pointer border-none" style={{ padding: '5px 10px', background: '#fee2e2', color: '#dc2626', opacity: cfg.music_off_url ? 1 : 0.5 }}>Hudba ⏹</button>
        <button onClick={() => onCommand(dev, 'identify', { label: 'Velín' })}
          className="rounded-btn text-[12px] font-bold cursor-pointer border-none" style={{ padding: '5px 10px', background: '#dbeafe', color: '#2563eb' }}>Identifikuj</button>
        <button onClick={() => { if (window.confirm('Restartovat appku na tomto tabletu?')) onCommand(dev, 'restart', {}) }}
          className="rounded-btn text-[12px] font-bold cursor-pointer border-none" style={{ padding: '5px 10px', background: '#fef3c7', color: '#b45309' }}>Restart</button>
      </div>
    </div>
  )
}

function KioskConfigBlock({ cfg, onSave }) {
  return (
    <Section title="Hudba & časování" hint="Hudba se spustí na celé pobočce při zadání kódu; světlo se rozsvítí v dané garáži.">
      <div className="p-3 rounded-card space-y-3" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
        <div className="flex gap-3 flex-wrap">
          <Field label="Hudba — URL spuštění" value={cfg.music_on_url} onCommit={v => onSave({ music_on_url: v })} placeholder="http://192.168.1.50/relay/0?turn=on" width={300} />
          <Field label="Hudba — URL zastavení (volitelné)" value={cfg.music_off_url} onCommit={v => onSave({ music_off_url: v })} placeholder="http://192.168.1.50/relay/0?turn=off" width={300} />
        </div>
        <div className="flex gap-3 flex-wrap">
          <Field label="Otevření dveří (s)" type="number" value={cfg.door_open_seconds} onCommit={v => onSave({ door_open_seconds: v })} width={130} />
          <Field label="Světlo (s)" type="number" value={cfg.light_seconds} onCommit={v => onSave({ light_seconds: v })} width={130} />
          <Field label="Hudba (s)" type="number" value={cfg.music_seconds} onCommit={v => onSave({ music_seconds: v })} width={130} />
        </div>
        <div className="flex gap-3 flex-wrap pt-2" style={{ borderTop: '1px dashed #d4e8e0' }}>
          <Field label="FV elektrárna — URL stavu (JSON na LAN)" value={cfg.power_status_url} onCommit={v => onSave({ power_status_url: v })} placeholder="http://192.168.1.60/status" width={340} />
          <Field label="Interval čtení (s)" type="number" value={cfg.power_poll_seconds} onCommit={v => onSave({ power_poll_seconds: v })} width={130} />
        </div>
      </div>
    </Section>
  )
}

function DoorsBlock({ doors, onEnsure, onSave, onDelete, busy }) {
  return (
    <Section title="Dveře → relé & světlo (Shelly LAN)"
      hint="Pro každou kóji (dle čísla boxu motorky) a dveře oblečení nastavte URL relé a světla."
      action={
        <button onClick={onEnsure} disabled={busy} className="rounded-btn text-sm font-bold cursor-pointer border-none"
          style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', opacity: busy ? 0.5 : 1 }}>
          {busy ? 'Pracuji…' : 'Vytvořit dveře z kojí'}
        </button>
      }>
      {doors.length === 0 ? (
        <EmptyState text="Žádné dveře. Nejdřív přiřaďte čísla kojí (záložka Motorky & Koje), pak klikněte „Vytvořit dveře z kojí“." />
      ) : (
        <div className="space-y-1 max-h-72 overflow-y-auto">
          {doors.map(d => (
            <div key={d.id} className="flex items-end gap-2 p-2 rounded-lg flex-wrap"
              style={{ background: d.door_kind === 'accessories' ? '#eff6ff' : '#f1faf7', border: '1px solid #d4e8e0' }}>
              <span className="inline-block rounded-btn text-[9px] font-extrabold uppercase self-center"
                style={{ padding: '2px 6px', background: d.door_kind === 'accessories' ? '#dbeafe' : '#dcfce7', color: d.door_kind === 'accessories' ? '#2563eb' : '#1a8a18', minWidth: 64, textAlign: 'center' }}>
                {d.door_kind === 'accessories' ? 'Oblečení' : `Koje #${d.box_number}`}
              </span>
              <Field label="Popis" value={d.label} onCommit={v => onSave(d.id, { label: v })} width={150} />
              <Field label="URL relé (otevření)" value={d.relay_url} onCommit={v => onSave(d.id, { relay_url: v })} placeholder="http://192.168.1.51/relay/0?turn=on" width={240} />
              <Field label="URL světla" value={d.light_url} onCommit={v => onSave(d.id, { light_url: v })} placeholder="http://192.168.1.51/relay/1?turn=on" width={240} />
              <button onClick={() => onDelete(d.id)} className="rounded-btn text-[11px] font-bold cursor-pointer border-none self-center"
                style={{ padding: '6px 8px', background: '#fee2e2', color: '#dc2626' }}>Smazat</button>
            </div>
          ))}
        </div>
      )}
    </Section>
  )
}

function ServiceCodesBlock({ codes, onAdd, onToggle, onDelete, busy }) {
  const [code, setCode] = useState('')
  const [label, setLabel] = useState('')
  return (
    <Section title="Servisní hesla" hint="Otevírají všechny dveře. Appka se zeptá, které dveře otevřít.">
      <div className="flex items-end gap-2 mb-2 flex-wrap">
        <label className="flex flex-col gap-0.5" style={{ width: 160 }}>
          <span className="text-[11px] font-bold" style={{ color: '#6b8c7a' }}>Heslo</span>
          <input value={code} onChange={e => setCode(e.target.value)} placeholder="např. servis2026"
            className="rounded-btn text-sm outline-none" style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </label>
        <label className="flex flex-col gap-0.5" style={{ width: 200 }}>
          <span className="text-[11px] font-bold" style={{ color: '#6b8c7a' }}>Komu patří (volitelné)</span>
          <input value={label} onChange={e => setLabel(e.target.value)} placeholder="Technik Petr"
            className="rounded-btn text-sm outline-none" style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </label>
        <button onClick={() => { onAdd(code, label); setCode(''); setLabel('') }} disabled={busy || !code.trim()}
          className="rounded-btn text-sm font-bold cursor-pointer border-none"
          style={{ padding: '6px 12px', background: '#1a2e22', color: '#74FB71', opacity: (busy || !code.trim()) ? 0.5 : 1 }}>Přidat</button>
      </div>
      {codes.length === 0 ? (
        <EmptyState text="Žádná servisní hesla" />
      ) : (
        <div className="space-y-1">
          {codes.map(c => (
            <div key={c.id} className="flex items-center gap-2 p-2 rounded-lg" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
              <span className="font-mono font-extrabold text-sm" style={{ color: '#0f1a14' }}>{c.code}</span>
              {c.label && <span className="text-sm" style={{ color: '#1a2e22' }}>{c.label}</span>}
              <span className="inline-block rounded-btn text-[9px] font-extrabold uppercase"
                style={{ padding: '2px 6px', background: c.is_active ? '#dcfce7' : '#f3f4f6', color: c.is_active ? '#1a8a18' : '#6b8c7a' }}>
                {c.is_active ? 'Aktivní' : 'Vypnuté'}
              </span>
              <div className="ml-auto flex gap-1">
                <button onClick={() => onToggle(c)} className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
                  style={{ padding: '4px 8px', background: '#dbeafe', color: '#2563eb' }}>{c.is_active ? 'Vypnout' : 'Zapnout'}</button>
                <button onClick={() => onDelete(c.id)} className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
                  style={{ padding: '4px 8px', background: '#fee2e2', color: '#dc2626' }}>Smazat</button>
              </div>
            </div>
          ))}
        </div>
      )}
    </Section>
  )
}

// ─── Stav ostrovní FV elektrárny ──────────────────────────────────────────
function PowerBlock({ power, cfg, now, onSave, onRefresh }) {
  const ageMs = power?.updated_at ? (now - new Date(power.updated_at).getTime()) : null
  const stale = ageMs == null || ageMs > 5 * 60 * 1000
  const fmt = (v, unit) => (v == null ? '—' : `${Number(v).toLocaleString('cs-CZ')} ${unit}`)
  const soc = power?.battery_soc
  const socColor = soc == null ? '#6b8c7a' : (soc >= 50 ? '#1a8a18' : soc >= 20 ? '#b45309' : '#dc2626')
  return (
    <Section title="Solární elektrárna (ostrovní systém)"
      hint="Stav posílá tablet z měniče na pobočce. Nastav URL stavu v sekci „Hudba & časování“."
      action={
        <button onClick={onRefresh} className="rounded-btn text-sm font-bold cursor-pointer border-none"
          style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb' }}>Obnovit</button>
      }>
      {!power ? (
        <EmptyState text={cfg.power_status_url ? 'Zatím nedorazil žádný stav z tabletu.' : 'Není nastavená URL stavu elektrárny.'} />
      ) : (
        <div className="p-3 rounded-card" style={{ background: stale ? '#fef3c7' : '#f1faf7', border: `1px solid ${stale ? '#fde68a' : '#d4e8e0'}` }}>
          <div className="flex flex-wrap gap-4 items-center">
            <div className="flex flex-col items-center" style={{ minWidth: 110 }}>
              <span className="text-[11px] font-bold uppercase" style={{ color: '#6b8c7a' }}>Baterie</span>
              <span style={{ fontSize: 34, fontWeight: 900, color: socColor }}>{soc == null ? '—' : `${soc}%`}</span>
              <span className="text-[12px]" style={{ color: '#1a2e22' }}>{fmt(power.battery_voltage, 'V')}</span>
            </div>
            <Metric label="FV výroba" value={fmt(power.pv_power_w, 'W')} color="#1a8a18" />
            <Metric label="Spotřeba" value={fmt(power.load_power_w, 'W')} color="#2563eb" />
            <Metric label="Baterie tok" value={fmt(power.battery_power_w, 'W')} color="#1a2e22" />
            <div className="flex flex-col gap-1">
              <Flag on={power.grid_present} labelOn="Síť/gen připojeno" labelOff="Ostrovní provoz" />
              {power.generator_on != null && <Flag on={power.generator_on} labelOn="Generátor běží" labelOff="Generátor vypnutý" />}
            </div>
          </div>
          <div className="text-[12px] mt-2" style={{ color: stale ? '#b45309' : '#6b8c7a' }}>
            {stale ? '⚠ Data nejsou aktuální — ' : ''}poslední aktualizace: {power.updated_at ? new Date(power.updated_at).toLocaleString('cs-CZ') : '—'}
          </div>
        </div>
      )}
    </Section>
  )
}

function Metric({ label, value, color }) {
  return (
    <div className="flex flex-col items-center" style={{ minWidth: 100 }}>
      <span className="text-[11px] font-bold uppercase" style={{ color: '#6b8c7a' }}>{label}</span>
      <span style={{ fontSize: 22, fontWeight: 800, color }}>{value}</span>
    </div>
  )
}

function Flag({ on, labelOn, labelOff }) {
  if (on == null) return null
  return (
    <span className="inline-block rounded-btn text-[10px] font-extrabold uppercase"
      style={{ padding: '3px 8px', background: on ? '#dcfce7' : '#eef6f2', color: on ? '#1a8a18' : '#6b8c7a' }}>
      {on ? labelOn : labelOff}
    </span>
  )
}

// ─── Kamery (náhled + ovládání přes tablet) ───────────────────────────────
function CamerasBlock({ cameras, onlineDevice, busy, onAdd, onSave, onDelete, onRemote }) {
  return (
    <Section title="Kamerový systém" hint="Náhled (snapshot/HLS/iframe) a ovládání kamer. Ovládací akce se posílají přes tablet (LAN)."
      action={
        <button onClick={onAdd} disabled={busy} className="rounded-btn text-sm font-bold cursor-pointer border-none"
          style={{ padding: '4px 10px', background: '#1a2e22', color: '#74FB71', opacity: busy ? 0.5 : 1 }}>Přidat kameru</button>
      }>
      {cameras.length === 0 ? (
        <EmptyState text="Žádné kamery. Přidej kameru a zadej URL náhledu." />
      ) : (
        <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))' }}>
          {cameras.map(cam => (
            <CameraCard key={cam.id} cam={cam} onlineDevice={onlineDevice} onSave={onSave} onDelete={onDelete} onRemote={onRemote} />
          ))}
        </div>
      )}
    </Section>
  )
}

function CameraCard({ cam, onlineDevice, onSave, onDelete, onRemote }) {
  const [edit, setEdit] = useState(false)
  const [tick, setTick] = useState(Date.now())
  // snapshot auto-refresh á 5 s
  useEffect(() => {
    if (cam.kind !== 'snapshot' || !cam.snapshot_url) return
    const t = setInterval(() => setTick(Date.now()), 5000)
    return () => clearInterval(t)
  }, [cam.kind, cam.snapshot_url])

  const sep = (cam.snapshot_url || '').includes('?') ? '&' : '?'
  return (
    <div className="rounded-card overflow-hidden" style={{ background: '#0f1a14', border: '1px solid #d4e8e0' }}>
      <div style={{ aspectRatio: '16 / 9', background: '#000', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        {cam.kind === 'snapshot' && cam.snapshot_url ? (
          <img src={`${cam.snapshot_url}${sep}_t=${tick}`} alt={cam.name || 'kamera'} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        ) : cam.kind === 'mjpeg' && cam.stream_url ? (
          <img src={cam.stream_url} alt={cam.name || 'kamera'} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        ) : (cam.kind === 'hls' || cam.kind === 'iframe') && cam.stream_url ? (
          <iframe src={cam.stream_url} title={cam.name || 'kamera'} style={{ width: '100%', height: '100%', border: 'none' }} allow="autoplay; fullscreen" />
        ) : (
          <span style={{ color: '#6b8c7a', fontSize: 13 }}>Bez náhledu — nastav URL</span>
        )}
      </div>
      <div className="p-2">
        <div className="flex items-center gap-2 mb-1">
          <span className="font-bold text-sm" style={{ color: '#fff' }}>{cam.name || 'Kamera'}</span>
          <span className="inline-block rounded-btn text-[9px] font-extrabold uppercase" style={{ padding: '2px 6px', background: '#1a2e22', color: '#74FB71' }}>{cam.kind}</span>
          <div className="ml-auto flex gap-1">
            {cam.control_url && (
              <button onClick={() => onRemote('camera_control', { url: cam.control_url })} disabled={!onlineDevice}
                title={!onlineDevice ? 'Žádný tablet online' : 'Spustit akci kamery přes tablet'}
                className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
                style={{ padding: '3px 8px', background: '#dbeafe', color: '#2563eb', opacity: onlineDevice ? 1 : 0.5 }}>Akce</button>
            )}
            <button onClick={() => setEdit(e => !e)} className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
              style={{ padding: '3px 8px', background: '#eef6f2', color: '#1a2e22' }}>{edit ? 'Hotovo' : 'Upravit'}</button>
          </div>
        </div>
        {edit && (
          <div className="space-y-2 pt-1">
            <div className="flex gap-2 flex-wrap">
              <Field label="Název" value={cam.name} onCommit={v => onSave(cam.id, { name: v })} width={150} />
              <label className="flex flex-col gap-0.5" style={{ width: 120 }}>
                <span className="text-[11px] font-bold" style={{ color: '#9fb8ac' }}>Typ náhledu</span>
                <select value={cam.kind} onChange={e => onSave(cam.id, { kind: e.target.value })}
                  className="rounded-btn text-sm outline-none" style={{ padding: '6px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                  <option value="snapshot">snapshot (JPEG)</option>
                  <option value="mjpeg">mjpeg</option>
                  <option value="hls">hls (iframe)</option>
                  <option value="iframe">iframe</option>
                </select>
              </label>
            </div>
            <Field label="Snapshot URL (JPEG)" value={cam.snapshot_url} onCommit={v => onSave(cam.id, { snapshot_url: v })} placeholder="http://nvr/cam1/snapshot.jpg" width="100%" />
            <Field label="Stream URL (HLS/MJPEG/iframe)" value={cam.stream_url} onCommit={v => onSave(cam.id, { stream_url: v })} placeholder="https://nvr/cam1/index.m3u8" width="100%" />
            <Field label="Ovládací URL (PTZ/relé — přes tablet)" value={cam.control_url} onCommit={v => onSave(cam.id, { control_url: v })} placeholder="http://nvr/cam1/preset?n=1" width="100%" />
            <button onClick={() => onDelete(cam.id)} className="rounded-btn text-[11px] font-bold cursor-pointer border-none"
              style={{ padding: '4px 10px', background: '#fee2e2', color: '#dc2626' }}>Smazat kameru</button>
          </div>
        )}
      </div>
    </div>
  )
}

// ─── OTA — nejnovější verze appky (globální pro všechny kiosky) ───────────────
function OtaBlock({ ota, onSave }) {
  return (
    <Section title="Aktualizace appky (OTA)"
      hint="Globální pro všechny kiosky. Po zvýšení version_code si tablety appku samy stáhnou a nainstalují (tichá instalace přes MDM/device owner).">
      <div className="p-3 rounded-card flex gap-3 flex-wrap" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
        <Field label="version_code (číslo, rostoucí)" type="number" value={ota.version_code} onCommit={v => onSave({ version_code: v })} width={170} />
        <Field label="version_name" value={ota.version_name} onCommit={v => onSave({ version_name: v })} placeholder="1.0.1" width={130} />
        <Field label="URL APK ke stažení" value={ota.apk_url} onCommit={v => onSave({ apk_url: v })} placeholder="https://…/motogo_kiosk.apk" width={340} />
        <Field label="Poznámka" value={ota.notes} onCommit={v => onSave({ notes: v })} width={200} />
      </div>
    </Section>
  )
}

// ─── Diagnostika — logy/chyby/pády z kiosků ──────────────────────────────────
function DiagnosticsBlock({ logs, devices, onRefresh }) {
  const devMap = Object.fromEntries(devices.map(d => [d.id, d]))
  const color = { info: '#6b8c7a', warn: '#b45309', error: '#dc2626', crash: '#dc2626' }
  return (
    <Section title="Diagnostika (chyby & události)" hint="Posledních 40 hlášení z tabletů pobočky."
      action={
        <button onClick={onRefresh} className="rounded-btn text-sm font-bold cursor-pointer border-none"
          style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb' }}>Obnovit</button>
      }>
      {logs.length === 0 ? (
        <EmptyState text="Žádné záznamy — vše běží bez chyb." />
      ) : (
        <div className="space-y-1 max-h-72 overflow-y-auto">
          {logs.map(l => (
            <div key={l.id} className="flex items-center gap-2 p-2 rounded-lg text-sm" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
              <span className="inline-block rounded-btn text-[9px] font-extrabold uppercase"
                style={{ padding: '2px 6px', background: (l.level === 'info' ? '#eef6f2' : '#fee2e2'), color: color[l.level] || '#1a2e22' }}>
                {l.level}
              </span>
              {l.source && <span className="text-[11px] font-bold" style={{ color: '#6b8c7a' }}>{l.source}</span>}
              <span style={{ color: '#0f1a14' }}>{l.message}</span>
              {devMap[l.device_id]?.name && <span className="text-[11px]" style={{ color: '#6b8c7a' }}>· {devMap[l.device_id].name}</span>}
              <span className="ml-auto text-[12px]" style={{ color: '#6b8c7a' }}>{new Date(l.created_at).toLocaleString('cs-CZ')}</span>
            </div>
          ))}
        </div>
      )}
    </Section>
  )
}

export { TabSelfService }
