import { useState, useEffect, useMemo } from 'react'
import { EmptyState } from './BranchHelpers'
import { RpiSection, Btn, Chip, Input, Select, Checkbox } from './BranchRpiUi'
import { DoorHwEditor } from './BranchRpiDoorHw'
import {
  BRNO_DEFAULT_HARDWARE, BRNO_DEFAULT_ZONES, DEVICE_TYPES, HW_SECTIONS,
  fieldToText, textToField, sectionWithDefaults, pickAccessoriesZone,
} from './BranchRpiHardwareDefaults'

// ─── Řídicí jednotka (Raspberry) — hardware ──────────────────────────────────
// Editor `branch_kiosk_config.hardware` (zařízení + časování/polling/kontakty/
// bezpečnost/audio/signál) a `branch_doors.hw` (mapování zón). Uložení tlačítky;
// řídicí jednotka si změny stáhne při dalším syncu (nebo příkazem sync_config).
// onSaveCfg/onSaveDoor aktualizují stav záložky optimisticky a vrací true/false.

const clone = v => JSON.parse(JSON.stringify(v))
const NOTE_STYLE = { green: { background: '#dcfce7', color: '#1a8a18' }, amber: { background: '#fef3c7', color: '#b45309' }, red: { background: '#fee2e2', color: '#dc2626' } }

function RpiHardwareBlock({ cfg, doors, busy, onSaveCfg, onSaveDoor, onRefresh }) {
  const hardware = (cfg?.hardware && typeof cfg.hardware === 'object') ? cfg.hardware : {}
  const [loadingDefaults, setLoadingDefaults] = useState(false)
  const [note, setNote] = useState(null)   // { tone, text }

  async function loadBrnoDefaults() {
    const zonesN = BRNO_DEFAULT_ZONES.length
    const targets = (doors || []).filter(d => d.door_kind === 'motorcycle' && d.box_number >= 1 && d.box_number <= zonesN)
    // Skříň oblečení (box_number NULL) = nejvyšší zóna šablony, kterou nezabírá žádná kóje
    const accDoor = (doors || []).find(d => d.door_kind === 'accessories')
    const accZone = accDoor ? pickAccessoriesZone(targets.map(d => d.box_number)) : null
    const accText = !accDoor ? 'Dveře oblečení neexistují (blok „Dveře“ → Vytvořit dveře z kojí) — namapují se jen kóje.'
      : accZone ? `Skříň oblečení dostane zónu ${accZone} (nejvyšší volná zóna šablony).`
        : `POZOR: pro skříň oblečení nezbyla volná zóna (kóje obsadily všech ${zonesN} zón) — kód k oblečení nebude fungovat, dokud jí nenastavíte zónu ručně.`
    const ok = window.confirm(
      `Načíst výchozí mapu (šablona Brno, ${zonesN} zón)?\n\nPřepíše zařízení a všechna nastavení hardwaru pobočky a HW mapu ${targets.length} dveří (kóje 1–${zonesN}). ${accText}\n\nPro jinou pobočku pak upravte adresy zařízení a počet zón.`,
    )
    if (!ok) return
    setLoadingDefaults(true)
    setNote(null)
    try {
      let failed = 0
      if ((await onSaveCfg({ hardware: clone(BRNO_DEFAULT_HARDWARE) })) === false) failed++
      for (const d of targets) {
        if ((await onSaveDoor(d.id, { hw: clone(BRNO_DEFAULT_ZONES[d.box_number - 1]) })) === false) failed++
      }
      if (accDoor && accZone && (await onSaveDoor(accDoor.id, { hw: clone(BRNO_DEFAULT_ZONES[accZone - 1]) })) === false) failed++
      const summary = `${Object.keys(BRNO_DEFAULT_HARDWARE.devices).length} zařízení, ${targets.length} kójí${accDoor && accZone ? `, oblečení = zóna ${accZone}` : ''}`
      // Stav záložky je už aktualizovaný optimisticky — bez onRefresh (spinner celé záložky by blok odmontoval a poznámku ztratil)
      if (failed) setNote({ tone: 'red', text: `Výchozí mapa: ${failed}× uložení selhalo (viz chyba nahoře). Uloženo: ${summary}.` })
      else if (accDoor && !accZone) setNote({ tone: 'amber', text: `Výchozí mapa (šablona Brno) načtena (${summary}). Skříň oblečení NEMÁ zónu — všech ${zonesN} zón obsadily kóje; nastavte ji ručně v mapování níže.` })
      else setNote({ tone: 'green', text: `Výchozí mapa (šablona Brno) načtena (${summary}). Jednotka si ji stáhne do 60 s nebo příkazem „Synchronizovat konfiguraci“.` })
    } finally {
      setLoadingDefaults(false)
    }
  }

  const disabled = busy || loadingDefaults
  return (
    <RpiSection title="Řídicí jednotka (Raspberry) — hardware"
      hint="Modbus relé Waveshare + Shelly signalizace. Časování, audio, PIN bezpečnost i signalizaci řídicí jednotky nastavíte ZDE (blok „Hudba & časování“ výše platí jen pro tablet). Změny se do jednotky propíší při synchronizaci konfigurace (do 60 s nebo příkazem „Synchronizovat konfiguraci“)."
      action={
        <div className="flex gap-2">
          <Btn tone="blue" onClick={onRefresh} disabled={disabled}>Obnovit</Btn>
          <Btn tone="dark" onClick={loadBrnoDefaults} disabled={disabled}>{loadingDefaults ? 'Načítám…' : 'Načíst výchozí mapu (šablona Brno, 9 zón)'}</Btn>
        </div>
      }>
      <div className="space-y-3">
        {note && <div className="p-2 rounded-lg text-[12px] font-bold" style={NOTE_STYLE[note.tone] || NOTE_STYLE.green}>{note.text}</div>}
        <DevicesEditor hardware={hardware} disabled={disabled} onSave={devices => onSaveCfg({ hardware: { ...hardware, devices } })} />
        <SettingsEditor hardware={hardware} disabled={disabled} onSave={patch => onSaveCfg({ hardware: { ...hardware, ...patch } })} />
        <SubBlock title="Mapování dveří → zóny (branch_doors.hw)"
          hint="Zóna = číslo kóje (skříň oblečení = volné číslo). Zámek = coil VÝHRADNĚ na WAV645 (HW flash-on), kontakt = vstup WAV617 (input), světlo/audio = coil WAV645/WAV617, červená/zelená = Shelly light id (0–4). Zámek a kontakt jsou povinné; čísla zón i kanály musí být unikátní — jinak jednotka celou mapu odmítne.">
          {(doors || []).length === 0
            ? <EmptyState text="Žádné dveře. Nejdřív vytvořte dveře z kojí (blok „Dveře“ výše)." />
            : <DoorHwEditor doors={doors} devices={hardware.devices || {}} busy={disabled} onSaveDoor={onSaveDoor} />}
        </SubBlock>
      </div>
    </RpiSection>
  )
}

function SubBlock({ title, hint, action, children }) {
  return (
    <div className="p-3 rounded-card" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
      <div className="flex items-center justify-between gap-2 mb-2 flex-wrap">
        <div>
          <div className="text-[12px] font-extrabold uppercase" style={{ color: '#1a2e22' }}>{title}</div>
          {hint && <div className="text-[11px]" style={{ color: '#6b8c7a' }}>{hint}</div>}
        </div>
        {action}
      </div>
      {children}
    </div>
  )
}

// ── Zařízení (hardware.devices) ─────────────────────────────────────────────
function devicesToRows(devices) {
  return Object.entries(devices || {}).map(([name, d], i) => ({
    _k: `${name}-${i}`, name, type: d?.type || 'wav645', host: d?.host || '', port: d?.port ?? '', unit_id: d?.unit_id ?? '',
  }))
}

function DevicesEditor({ hardware, disabled, onSave }) {
  const [rows, setRows] = useState(() => devicesToRows(hardware.devices))
  const [dirty, setDirty] = useState(false)
  const [err, setErr] = useState(null)
  useEffect(() => { if (!dirty) setRows(devicesToRows(hardware.devices)) }, [hardware.devices, dirty])

  const nameCounts = useMemo(() => rows.reduce((m, r) => { m[r.name] = (m[r.name] || 0) + 1; return m }, {}), [rows])
  const NAME_RE = /^[a-z0-9_-]+$/

  function edit(i, patch) {
    setRows(rs => rs.map((r, j) => j === i ? { ...r, ...patch } : r))
    setDirty(true)
  }
  function add() {
    setRows(rs => [...rs, { _k: `new-${Date.now()}`, name: '', type: 'wav645', host: '', port: 502, unit_id: 1 }])
    setDirty(true)
  }
  function remove(i) { setRows(rs => rs.filter((_, j) => j !== i)); setDirty(true) }

  async function save() {
    const devices = {}
    for (const r of rows) {
      const name = r.name.trim()
      if (!NAME_RE.test(name)) { setErr(`Název „${r.name}“ musí být malá písmena, číslice, - nebo _.`); return }
      if (devices[name]) { setErr(`Duplicitní název zařízení „${name}“.`); return }
      if (!r.host.trim()) { setErr(`Zařízení „${name}“ nemá adresu (host).`); return }
      const dev = { type: r.type, host: r.host.trim() }
      if (r.type !== 'shelly_rgbww') {
        dev.port = parseInt(r.port, 10) || 502
        dev.unit_id = parseInt(r.unit_id, 10) || 1
      }
      devices[name] = dev
    }
    setErr(null)
    await onSave(devices)
    setDirty(false)
  }

  return (
    <SubBlock title="Zařízení (Modbus TCP / Shelly)" hint="Název je odkaz z mapování dveří — po přejmenování upravte i zóny."
      action={
        <div className="flex gap-2">
          <Btn tone="blue" onClick={add} disabled={disabled}>Přidat zařízení</Btn>
          <Btn tone="dark" onClick={save} disabled={disabled || !dirty}>{dirty ? 'Uložit zařízení' : 'Uloženo'}</Btn>
        </div>
      }>
      {rows.length === 0 ? <EmptyState text="Žádná zařízení — přidejte ručně nebo načtěte výchozí mapu (šablona Brno)." /> : (
        <div className="space-y-1">
          {rows.map((r, i) => {
            const isShelly = r.type === 'shelly_rgbww'
            const badName = !NAME_RE.test(r.name.trim()) || nameCounts[r.name] > 1
            return (
              <div key={r._k} className="flex items-end gap-2 flex-wrap p-2 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                <Input label="Název" width={110} value={r.name} placeholder="wav645" invalid={badName}
                  title={badName ? 'Název musí být unikátní, malá písmena/číslice/-/_' : ''}
                  onChange={v => edit(i, { name: v })} />
                <Select label="Typ" width={200} value={r.type} options={DEVICE_TYPES} onChange={v => edit(i, { type: v })} />
                <Input label="Host (IP)" width={140} value={r.host} placeholder="192.168.50.20" invalid={!r.host.trim()} onChange={v => edit(i, { host: v })} />
                {!isShelly && <Input label="Port" type="number" width={70} value={r.port} onChange={v => edit(i, { port: v })} />}
                {!isShelly && <Input label="Unit ID" type="number" width={70} value={r.unit_id} onChange={v => edit(i, { unit_id: v })} />}
                {isShelly && <Chip tone="blue" title="HTTP RPC, port 80">HTTP /rpc</Chip>}
                <Btn tone="red" small onClick={() => remove(i)} disabled={disabled} style={{ alignSelf: 'center', marginLeft: 'auto' }}>Smazat</Btn>
              </div>
            )
          })}
        </div>
      )}
      {err && <div className="text-[12px] font-bold mt-2" style={{ color: '#dc2626' }}>{err}</div>}
    </SubBlock>
  )
}

// ── Časování / polling / kontakty / bezpečnost / audio / signál ─────────────
function settingsToText(hardware) {
  const out = {}
  HW_SECTIONS.forEach(sec => {
    const vals = sectionWithDefaults(hardware, sec.key)
    out[sec.key] = {}
    sec.fields.forEach(f => { out[sec.key][f.key] = f.type === 'bool' ? !!vals[f.key] : fieldToText(f, vals[f.key]) })
  })
  return out
}

function SettingsEditor({ hardware, disabled, onSave }) {
  const [text, setText] = useState(() => settingsToText(hardware))
  const [dirty, setDirty] = useState(false)
  const [err, setErr] = useState(null)
  useEffect(() => { if (!dirty) setText(settingsToText(hardware)) }, [hardware, dirty])

  function edit(sec, key, v) {
    setText(t => ({ ...t, [sec]: { ...t[sec], [key]: v } }))
    setDirty(true)
  }

  async function save() {
    const patch = {}
    for (const sec of HW_SECTIONS) {
      patch[sec.key] = { ...sectionWithDefaults(hardware, sec.key) }
      for (const f of sec.fields) {
        const raw = text[sec.key]?.[f.key]
        if (f.type === 'bool') { patch[sec.key][f.key] = !!raw; continue }
        const v = textToField(f, raw)
        if (v == null && f.type !== 'text') { setErr(`${sec.title} → ${f.label}: neplatná hodnota.`); return }
        if (f.key === 'closed_level' && v !== 0 && v !== 1) { setErr('Dveřní kontakty → úroveň zavřeno musí být 0 nebo 1.'); return }
        patch[sec.key][f.key] = v
      }
    }
    setErr(null)
    await onSave(patch)
    setDirty(false)
  }

  return (
    <SubBlock title="Časování, polling, kontakty, bezpečnost, audio, signalizace"
      hint="Hodnoty dle specifikace §6–§10. Uloží se celý blok hardware najednou."
      action={<Btn tone="dark" onClick={save} disabled={disabled || !dirty}>{dirty ? 'Uložit nastavení' : 'Uloženo'}</Btn>}>
      <div className="space-y-2">
        {HW_SECTIONS.map(sec => (
          <div key={sec.key} className="pt-2" style={{ borderTop: '1px dashed #d4e8e0' }}>
            <div className="text-[11px] font-extrabold uppercase mb-1" style={{ color: '#6b8c7a' }}>{sec.title}</div>
            <div className="flex gap-2 flex-wrap items-end">
              {sec.fields.map(f => {
                const v = text[sec.key]?.[f.key]
                if (f.type === 'bool') return <Checkbox key={f.key} label={f.label} checked={v} onChange={c => edit(sec.key, f.key, c)} />
                const invalid = f.type !== 'text' && textToField(f, v) == null
                const label = f.unit ? `${f.label} (${f.unit})` : f.label
                return (
                  <Input key={f.key} label={label} value={v} invalid={invalid}
                    width={f.type === 'list' || f.type === 'text' ? 190 : 150}
                    type={f.type === 'int' ? 'number' : 'text'} step={f.type === 'float' ? '0.1' : undefined}
                    onChange={val => edit(sec.key, f.key, val)} />
                )
              })}
            </div>
          </div>
        ))}
      </div>
      {err && <div className="text-[12px] font-bold mt-2" style={{ color: '#dc2626' }}>{err}</div>}
    </SubBlock>
  )
}

export { RpiHardwareBlock }
