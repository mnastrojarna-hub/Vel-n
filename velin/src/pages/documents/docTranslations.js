// MotoGo24 — Velín: aktuálnost překladů smluvních textů (document_templates)
// a vlastních dokumentů (custom_documents).
//
// Překlad platí jen pro české znění, ze kterého vznikl. Edge `translate-document`
// ukládá otisk české předlohy do `translation_src` = { "<lang>": "<sha1 hex>" }
// (migrace 20261011_i18n_customer_language.sql §6). Otisk se MUSÍ počítat shodně s SQL:
//   document_templates: sha1(content_html)
//   custom_documents:   sha1(coalesce(content_html,'') || '|' || coalesce(pdf_path,''))
// Překlad bez shodného otisku je ZASTARALÝ — web, appka, PDF ani AI ho nepoužijí
// (ukážou závaznou českou verzi). Dokud sloupec v DB není, je zastaralý každý překlad.

import { useEffect, useState } from 'react'
import { translateDocument, TRANSLATE_TARGET_LANGS } from '../../lib/autoTranslate'

export const TR_LANGS = TRANSLATE_TARGET_LANGS

export function sourceText(table, row) {
  if (table === 'custom_documents') return `${row?.content_html ?? ''}|${row?.pdf_path ?? ''}`
  return row?.content_html ?? ''
}

export async function sha1Hex(str) {
  try {
    const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(String(str)))
    return Array.from(new Uint8Array(buf), b => b.toString(16).padStart(2, '0')).join('')
  } catch {
    return null
  }
}

function hasTranslation(table, row, lang) {
  if (table === 'custom_documents') {
    const t = row?.translations?.[lang]
    return !!(t && typeof t === 'object' && String(t.content_html || '').trim())
  }
  const v = row?.content_translations?.[lang]
  return typeof v === 'string' && v.trim().length > 0
}

/** 'fresh' | 'stale' | 'missing' | 'checking' (otisk se ještě počítá). */
export function translationStatus(table, row, lang, srcHash) {
  if (!hasTranslation(table, row, lang)) return 'missing'
  const src = row?.translation_src
  if (!src || typeof src !== 'object') return 'stale' // sloupec chybí (migrace neproběhla)
  if (srcHash === undefined) return 'checking'
  return srcHash && src[lang] === srcHash ? 'fresh' : 'stale'
}

/** Otisky české předlohy pro načtené řádky: { [id]: sha1 | null }. */
export function useSourceHashes(table, rows) {
  const [hashes, setHashes] = useState({})
  useEffect(() => {
    let alive = true
    Promise.all((rows || []).map(async r => [r.id, await sha1Hex(sourceText(table, r))]))
      .then(pairs => { if (alive) setHashes(Object.fromEntries(pairs)) })
    return () => { alive = false }
  }, [table, rows])
  return hashes
}

/** Jazyky k přeložení: zadané | force = všechny | jinak chybějící a zastaralé. */
export async function pickLangs(table, row, { force = false, langs } = {}) {
  if (langs?.length) return langs.filter(l => TR_LANGS.includes(l))
  if (force) return [...TR_LANGS]
  const hash = await sha1Hex(sourceText(table, row))
  return TR_LANGS.filter(l => translationStatus(table, row, l, hash) !== 'fresh')
}

/** Jeden jazyk přes edge fn, až 3 pokusy (transientní rate-limit / limit edge fn). */
export async function translateOneLang(table, id, lang) {
  let lastErr = ''
  for (let attempt = 1; attempt <= 3; attempt++) {
    if (attempt > 1) await new Promise(r => setTimeout(r, 2500))
    const res = await translateDocument({ table, id, target_langs: [lang] })
    if (res?.success && res.translations?.[lang]) return { ok: true }
    // Prázdný dokument (bez textu / bez PDF) — opakování nepomůže
    if (res?.success && res.skipped === 'no_content') return { ok: false, error: 'dokument nemá obsah (text ani PDF)' }
    lastErr = (res?.errors && Object.values(res.errors)[0]) || (res?.details && Object.values(res.details)[0]) || res?.error || 'neznámá chyba'
  }
  return { ok: false, error: lastErr }
}

/** Přeloží jeden dokument do `langs` po jednom jazyce; průběh hlásí přes setMsg({ ok, text }). */
export async function runDocTranslation(table, row, langs, setMsg) {
  const done = [], failed = []
  for (const lang of langs) {
    setMsg({ ok: true, text: `Překládám… ${lang} · hotovo: ${done.join(', ') || '–'}${failed.length ? ` · selhalo: ${failed.map(f => f.split(':')[0]).join(', ')}` : ''}` })
    const r = await translateOneLang(table, row.id, lang)
    if (r.ok) done.push(lang); else failed.push(`${lang}: ${r.error}`)
  }
  setMsg({ ok: failed.length === 0, text: failed.length ? `Přeloženo: ${done.join(', ') || '–'} · selhalo — ${failed.join('; ')} (klikni „Přeložit" znovu pro dokončení)` : `Hotovo — přeloženo do: ${done.join(', ')}` })
  return { done, failed }
}

/** Hromadně pro všechny řádky: force = vše znovu, jinak jen chybějící a zastaralé jazyky. */
export async function translateAllRows(table, rows, { force = false, labelOf = r => r.id, onText } = {}) {
  let done = 0, failed = 0
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i]
    for (const lang of await pickLangs(table, row, { force })) {
      onText?.(`(${i + 1}/${rows.length}) ${labelOf(row)} → ${lang} …  [hotovo ${done}, selhalo ${failed}]`)
      const r = await translateOneLang(table, row.id, lang)
      if (r.ok) done++; else failed++
    }
  }
  return { done, failed }
}

export function bulkResultText({ done, failed }, what) {
  if (failed) return `Hotovo s chybami — přeloženo ${done}, selhalo ${failed}. Klikni znovu „Přeložit chybějící a zastaralé" pro dokončení.`
  if (done) return `Hotovo — ${what}: přeloženo ${done} jazykových verzí.`
  return `${what}: všechny překlady jsou aktuální.`
}
