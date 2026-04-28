// MotoGo24 — Velín auto-překlad textů pro veřejný web (motogo24.cz)
//
// Helper, který po uložení textů v administraci spustí překlad přes
// edge funkci `translate-content` (Anthropic Claude API). Český text
// zůstává v původním sloupci jako fallback; překlady se ukládají do
// JSONB sloupce `translations` cílové tabulky.
//
// Použití:
//   import { autoTranslate } from '../lib/autoTranslate'
//   await autoTranslate({ table: 'cms_pages', id, fields: { title, excerpt, content } })
//
// `fire-and-forget`: chybu pouze loguje, neblokuje ukládání. UI ukáže
// volitelný toast skrz parametr `onStatus`.

import { supabase, supabaseUrl, supabaseAnonKey } from './supabase'

export const TRANSLATE_TARGET_LANGS = ['en', 'de', 'es', 'fr', 'nl', 'pl']

const FIELD_MAP = {
  cms_pages: ['title', 'excerpt', 'content'],
  cms_variables: ['value'],
  products: ['name', 'description', 'color', 'material'],
  motorcycles: ['description'],
  branches: ['notes'],
  faq_items: ['question', 'answer'],
}

/**
 * Vyfiltruje z `row` jen překládaná pole pro danou tabulku.
 * Vrací jen pole, která mají nenulovou délku (po trim).
 */
export function pickTranslatableFields(table, row) {
  const allowed = FIELD_MAP[table]
  if (!allowed || !row) return {}
  const out = {}
  for (const f of allowed) {
    const v = row[f]
    if (typeof v === 'string' && v.trim().length > 0) out[f] = v
  }
  return out
}

/**
 * Volá edge funkci `translate-content`. Vrací { success, languages?, error? }.
 * Nehází výjimky — vše loguje a vrací stav.
 */
export async function autoTranslate({ table, id, fields, target_langs, onStatus }) {
  if (!table || !id) {
    onStatus?.({ status: 'skipped', reason: 'missing_table_or_id' })
    return { success: false, error: 'missing_table_or_id' }
  }

  const cleanFields = {}
  for (const [k, v] of Object.entries(fields || {})) {
    if (typeof v === 'string' && v.trim().length > 0) cleanFields[k] = v
  }
  if (Object.keys(cleanFields).length === 0) {
    onStatus?.({ status: 'skipped', reason: 'empty_fields' })
    return { success: true, skipped: true }
  }

  onStatus?.({ status: 'translating', langs: target_langs || TRANSLATE_TARGET_LANGS })
  try {
    const { data: { session } } = await supabase.auth.getSession()
    const accessToken = session?.access_token || supabaseAnonKey
    const response = await fetch(`${supabaseUrl}/functions/v1/translate-content`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'apikey': supabaseAnonKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ table, id, fields: cleanFields, target_langs }),
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok || !data?.success) {
      console.warn('[autoTranslate] failed:', response.status, data)
      onStatus?.({ status: 'error', error: data?.error || `HTTP ${response.status}` })
      return { success: false, error: data?.error || `HTTP ${response.status}` }
    }
    onStatus?.({ status: 'done', languages: data.languages || [] })
    return { success: true, languages: data.languages || [] }
  } catch (e) {
    const msg = e?.message || String(e)
    console.warn('[autoTranslate] exception:', msg)
    onStatus?.({ status: 'error', error: msg })
    return { success: false, error: msg }
  }
}

/**
 * Pohodlnější varianta — vyfiltruje fields podle tabulky a zavolá autoTranslate.
 * Vrací promise, můžete await nebo nechat běžet na pozadí.
 */
export async function autoTranslateRow({ table, id, row, target_langs, onStatus }) {
  const fields = pickTranslatableFields(table, row)
  if (Object.keys(fields).length === 0) {
    onStatus?.({ status: 'skipped', reason: 'no_translatable_fields' })
    return { success: true, skipped: true }
  }
  return autoTranslate({ table, id, fields, target_langs, onStatus })
}
