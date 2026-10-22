import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { purgeWebCache } from '../../lib/webCache'
import Button from '../ui/Button'
import { SETTINGS_KEY, DEFAULT_SETTINGS, INPUT, audit } from './gearShared'
import GearSettingToggle from './GearSettingToggle'
import { STOCK_TOGGLE, APP_VISIBLE_TOGGLE } from './gearToggleConfigs'

// app_settings.gear_rental = {enabled, max_days, max_ahead_days, app_visible}. Ukládá se merge
// s aktuální hodnotou v DB (jiné klíče zůstanou). Server meze stejně ořízne
// (max_days 1–366, max_ahead_days 1–800 — create_web_gear_booking).
// Pod formulářem přepínače „Kontrolovat sklad“ (gear_stock_check.gear_rental, stejný jako
// v Logistice) a „Zobrazit v aplikaci“ (gear_rental.app_visible) — ukládají se samostatně.

async function readSettings() {
  const { data, error } = await supabase.from('app_settings').select('value').eq('key', SETTINGS_KEY).maybeSingle()
  if (error) throw error
  return data?.value && typeof data.value === 'object' ? data.value : null
}

export default function GearSettingsCard() {
  const [form, setForm] = useState(null)
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState(null)
  const [err, setErr] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setErr(null)
    try {
      const v = { ...DEFAULT_SETTINGS, ...(await readSettings() || {}) }
      setForm({ enabled: v.enabled !== false, max_days: String(v.max_days), max_ahead_days: String(v.max_ahead_days) })
    } catch (e) {
      setErr(`Načtení nastavení selhalo: ${e.message}`)
      setForm({ enabled: true, max_days: String(DEFAULT_SETTINGS.max_days), max_ahead_days: String(DEFAULT_SETTINGS.max_ahead_days) })
    }
  }

  async function save(next = form) {
    const maxDays = parseInt(next.max_days, 10)
    const ahead = parseInt(next.max_ahead_days, 10)
    if (!(maxDays >= 1 && maxDays <= 366)) { setErr('Max. délka výpůjčky musí být 1–366 dní.'); return }
    if (!(ahead >= 1 && ahead <= 800)) { setErr('Rezervace dopředu musí být 1–800 dní.'); return }
    setErr(null); setMsg(null); setSaving(true)
    try {
      const current = await readSettings()
      const value = { ...(current || {}), enabled: !!next.enabled, max_days: maxDays, max_ahead_days: ahead }
      const result = await debugAction('app_settings.gear_rental', 'GearSettingsCard', () =>
        supabase.from('app_settings').upsert({ key: SETTINGS_KEY, value }, { onConflict: 'key' }), value)
      if (result?.error) throw new Error(result.error.message)
      await audit('gear_rental_settings_updated', 'app_settings', null, current, { key: SETTINGS_KEY, ...value })
      purgeWebCache()
      setForm({ enabled: value.enabled, max_days: String(maxDays), max_ahead_days: String(ahead) })
      setMsg('Uloženo')
      setTimeout(() => setMsg(null), 2500)
    } catch (e) {
      setErr(`Uložení selhalo: ${e.message}`)
    } finally {
      setSaving(false)
    }
  }

  if (!form) return null
  const on = form.enabled

  return (
    <div className="bg-white rounded-card shadow-card" style={{ padding: 16 }}>
      <div className="font-extrabold uppercase tracking-wide text-sm mb-3" style={{ color: '#1a2e22' }}>Nastavení výpůjček výbavy</div>
      <div className="flex flex-wrap items-end gap-4">
        <div>
          <div className="text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Objednávání</div>
          <button type="button" disabled={saving} onClick={() => save({ ...form, enabled: !on })}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer border-none max-lg:min-h-[40px]"
            style={{ padding: '8px 14px', background: on ? '#74FB71' : '#fee2e2', color: on ? '#1a2e22' : '#dc2626' }}>
            {on ? '● Zapnuto' : '○ Vypnuto'}
          </button>
        </div>
        <label className="block">
          <div className="text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Max. délka (dní)</div>
          <input type="number" min="1" max="366" value={form.max_days} onChange={e => setForm(f => ({ ...f, max_days: e.target.value }))}
            style={{ ...INPUT, width: 110 }} className="max-lg:min-h-[40px]" />
        </label>
        <label className="block">
          <div className="text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Rezervace dopředu (dní)</div>
          <input type="number" min="1" max="800" value={form.max_ahead_days} onChange={e => setForm(f => ({ ...f, max_ahead_days: e.target.value }))}
            style={{ ...INPUT, width: 110 }} className="max-lg:min-h-[40px]" />
        </label>
        <Button green small onClick={() => save()} disabled={saving} className="max-lg:min-h-[40px]">{saving ? 'Ukládám…' : 'Uložit'}</Button>
        {msg && <span className="text-sm font-bold" style={{ color: '#1a8a18' }}>✓ {msg}</span>}
      </div>
      <p className="text-xs mt-2" style={{ color: '#6b7a72' }}>
        Vypnuto = web stránku „Půjčení oblečení“ nenabízí a nové výpůjčky odmítne i databáze. Už zaplacené výpůjčky platí dál.
      </p>
      {err && <p className="text-sm mt-2" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4 pt-3" style={{ borderTop: '1px solid #e2ece7' }}>
        <GearSettingToggle {...STOCK_TOGGLE} component="GearSettingsCard" />
        <GearSettingToggle {...APP_VISIBLE_TOGGLE} component="GearSettingsCard" />
      </div>
    </div>
  )
}
