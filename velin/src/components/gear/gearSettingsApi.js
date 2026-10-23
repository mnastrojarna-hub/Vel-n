// MotoGo24 — Velín: čtení a merge-uložení přepínačů výpůjčky výbavy v `app_settings`.
//   gear_rental      = {enabled, max_days, max_ahead_days, app_visible}
//   gear_stock_check = {gear_rental, moto_booking, keep_free}   (migrace 20261023a)
// Ukládá se VŽDY merge s aktuální hodnotou v DB (ostatní klíče zůstanou) — stejně jako
// GearSettingsCard. Po uložení purge cache webu (web čte nastavení přes RPC i file-cache).
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { purgeWebCache } from '../../lib/webCache'
import { audit } from './gearShared'

export const STOCK_KEY = 'gear_stock_check'
export const STOCK_DEFAULTS = { gear_rental: false, moto_booking: false, keep_free: 0 }

export async function readAppSetting(key) {
  const { data, error } = await supabase.from('app_settings').select('value').eq('key', key).maybeSingle()
  if (error) throw error
  return data?.value && typeof data.value === 'object' ? data.value : null
}

// patch = jen měněná pole; defaults doplní chybějící klíče, když řádek v DB ještě není.
export async function saveAppSettingFields(key, patch, { defaults = {}, component = 'GearSettings', auditAction } = {}) {
  const current = await readAppSetting(key)
  const value = { ...defaults, ...(current || {}), ...patch }
  const result = await debugAction(`app_settings.${key}`, component, () =>
    supabase.from('app_settings').upsert({ key, value }, { onConflict: 'key' }), value)
  if (result?.error) throw new Error(result.error.message)
  await audit(auditAction || `${key}_updated`, 'app_settings', null, current, { key, ...value })
  purgeWebCache()
  return value
}
