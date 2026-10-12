// MotoGo24 — Velín: překlady horního banneru (app_settings.header_banner),
// který se zobrazuje v appce i nahoře na webu.
//
// Formát hodnoty (klíče enabled/text/bg/color beze změny, překlady navíc):
//   { enabled, text (CZ), bg, color,
//     translations:     { en: "…", de: "…", es, fr, nl, pl, uk },  // jen úspěšně přeložené
//     translations_src: "<sha1 hex>" }  // otisk CZ `text`, ze kterého překlady vznikly
// Otisk = SHA-1 (40 hex, malá písmena) nad UTF-8 bajty `text` přesně tak, jak je
// uložen (bez ořezu) — stejná konvence jako `translation_src` smluv. Web
// (motogo-web-php/layout-banner.php) i appka (lib/core/banner_provider.dart) použijí
// překlad jen když translations_src == sha1(text); jinak ukážou češtinu.
//
// Překládá se stejnou edge funkcí jako texty webu (`translate-content` přes
// autoTranslate). Ta umí jen tabulky se sloupcem `translations`, proto jde text
// přes nosný řádek `cms_variables` (klíč BANNER_CARRIER_KEY — mimo prefix `web.`,
// web ani appka ho nečtou; CMS „Texty webu“ ho nezobrazuje).

import { supabase } from '../lib/supabase'
import { autoTranslate, TRANSLATE_TARGET_LANGS } from '../lib/autoTranslate'
import { sha1Hex } from './documents/docTranslations'

export { sha1Hex }
export const BANNER_LANGS = TRANSLATE_TARGET_LANGS
export const BANNER_CARRIER_KEY = 'app.header_banner.text'

export function parseBannerValue(v) {
  if (!v) return null
  if (typeof v === 'string') { try { return JSON.parse(v) } catch { return null } }
  return typeof v === 'object' ? v : null
}

/** Čerstvé překlady ({lang: text}) — jen když translations_src odpovídá otisku `hash` CZ textu. */
export function freshTranslations(banner, hash) {
  const tr = banner?.translations
  const src = String(banner?.translations_src || '').toLowerCase()
  if (!hash || !src || src !== hash || !tr || typeof tr !== 'object') return {}
  const out = {}
  for (const l of BANNER_LANGS) {
    if (typeof tr[l] === 'string' && tr[l].trim()) out[l] = tr[l]
  }
  return out
}

/** Stav jazyka pro náhled: 'fresh' | 'stale' | 'missing' | 'checking'. */
export function bannerLangStatus(banner, hash, lang) {
  const v = banner?.translations?.[lang]
  if (typeof v !== 'string' || !v.trim()) return 'missing'
  if (hash === undefined) return 'checking'
  return freshTranslations(banner, hash)[lang] ? 'fresh' : 'stale'
}

/**
 * Přeloží CZ text banneru do `langs`. Nehází.
 * Vrací { translations: {lang: text}, failed: [lang], error? } — jazyk, který edge
 * funkce nevrátila jako úspěšný nebo vrátila beze změny (= nepřeloženo), je ve `failed`.
 */
export async function translateBannerText(text, langs = BANNER_LANGS) {
  const src = String(text ?? '')
  if (!src.trim() || !langs.length) return { translations: {}, failed: [] }
  const fail = error => ({ translations: {}, failed: [...langs], error })
  try {
    const { data: row, error } = await supabase.from('cms_variables').upsert({
      key: BANNER_CARRIER_KEY,
      value: src,
      category: 'general',
      description: 'Zdroj překladu banneru appky a webu (Dashboard → Banner). Needitovat — přepíše se při uložení banneru.',
    }, { onConflict: 'key' }).select('id').single()
    if (error || !row?.id) return fail(error?.message || 'nosný řádek cms_variables nelze uložit')

    const res = await autoTranslate({ table: 'cms_variables', id: row.id, fields: { value: src }, target_langs: langs })
    if (!res.success) return fail(res.error || 'překlad selhal')

    const { data: after, error: readErr } = await supabase.from('cms_variables')
      .select('value, translations').eq('id', row.id).maybeSingle()
    if (readErr || !after) return fail(readErr?.message || 'překlad nelze načíst')
    if (after.value !== src) return fail('text se mezitím změnil (jiné uložení) — ulož banner znovu')

    const ok = new Set(res.languages || [])
    const translations = {}
    const failed = []
    for (const l of langs) {
      const v = after.translations?.[l]?.value
      const t = typeof v === 'string' ? v.trim() : ''
      if (ok.has(l) && t && t !== src.trim()) translations[l] = t
      else failed.push(l)
    }
    return { translations, failed, error: failed.length ? 'jazyk nebyl přeložen' : undefined }
  } catch (e) {
    return fail(e?.message || String(e))
  }
}
