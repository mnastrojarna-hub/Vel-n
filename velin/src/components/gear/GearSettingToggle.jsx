import { useState, useEffect } from 'react'
import ConfirmDialog from '../ui/ConfirmDialog'
import { readAppSetting, saveAppSettingFields } from './gearSettingsApi'

// Jeden boolean přepínač v app_settings.<settingKey>.<field> (merge-uložení, audit, purge webu).
// Použití: GearSettingsCard („Kontrolovat sklad“, „Zobrazit v aplikaci“) a hlavička Logistiky.
// confirmOn = {title, message} → před ZAPNUTÍM potvrzovací dialog (vypnutí bez potvrzení).
// compact = jedno tlačítko „<title>: ● Zapnuto“ (hlavička stránky) — celá nápověda `help` v title
// (hover), pod tlačítkem viditelná jednořádková `hint` (dotyková zařízení title nezobrazí);
// na mobilu se text tlačítka zalamuje (žádný vodorovný posuv ani na 320 px).

export default function GearSettingToggle({
  settingKey, field, defaults = {}, title, help, hint, confirmOn, auditAction, compact = false, component = 'GearSettingToggle',
}) {
  const [on, setOn] = useState(null)
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const [ask, setAsk] = useState(false)

  useEffect(() => { load() }, [settingKey, field])

  async function load() {
    setErr(null)
    try {
      const v = { ...defaults, ...(await readAppSetting(settingKey) || {}) }
      setOn(v[field] === true)
    } catch (e) {
      setErr(`Načtení selhalo: ${e.message}`)
      setOn(defaults[field] === true)
    }
  }

  async function apply(next) {
    setAsk(false); setErr(null); setSaving(true)
    try {
      const value = await saveAppSettingFields(settingKey, { [field]: next }, { defaults, component, auditAction })
      setOn(value[field] === true)
    } catch (e) {
      setErr(`Uložení selhalo: ${e.message}`)
    } finally {
      setSaving(false)
    }
  }

  function click() {
    if (saving || on === null) return
    if (!on && confirmOn) { setAsk(true); return }
    apply(!on)
  }

  if (on === null && !err) return null
  const label = on ? '● Zapnuto' : '○ Vypnuto'
  const btnStyle = {
    padding: compact ? '8px 12px' : '8px 14px',
    background: on ? '#74FB71' : '#f3f4f6', color: on ? '#1a2e22' : '#6b7a72', opacity: saving ? 0.6 : 1,
  }
  const dialog = confirmOn && (
    <ConfirmDialog open={ask} title={confirmOn.title} message={confirmOn.message}
      onConfirm={() => apply(true)} onCancel={() => setAsk(false)} />
  )

  if (compact) {
    return (
      <div className="flex flex-col items-start lg:items-end min-w-0 max-w-full">
        <button type="button" disabled={saving} onClick={click} title={help || ''}
          className="rounded-btn text-sm font-extrabold cursor-pointer border-none text-left lg:whitespace-nowrap max-lg:min-h-[40px]" style={btnStyle}>
          {title}: <span className="whitespace-nowrap">{label}</span>
        </button>
        {hint && <span className="text-xs mt-1 lg:text-right" style={{ color: '#6b7a72', lineHeight: 1.4, maxWidth: 340 }}>{hint}</span>}
        {err && <span className="text-xs mt-1" style={{ color: '#dc2626' }}>{err}</span>}
        {dialog}
      </div>
    )
  }

  return (
    <div style={{ maxWidth: 560 }}>
      <div className="text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>{title}</div>
      <button type="button" disabled={saving} onClick={click}
        className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none max-lg:min-h-[40px]" style={btnStyle}>
        {label}
      </button>
      {help && <p className="text-xs mt-1" style={{ color: '#6b7a72', lineHeight: 1.5 }}>{help}</p>}
      {err && <p className="text-sm mt-1" style={{ color: '#dc2626' }}>{err}</p>}
      {dialog}
    </div>
  )
}
