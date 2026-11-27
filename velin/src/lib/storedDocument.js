/**
 * Uložená podoba vygenerovaného dokumentu (smlouva, VOP, GDPR, protokol).
 *
 * Dokument vystavený PŘED dnešním provozovatelem (`company_info.valid_from`) se ve Velínu
 * NIKDY neskládá z dnešní šablony — šablona už nese nového provozovatele a náhled by tak
 * přepsal obsah dávno vystaveného dokumentu. Otevírá se to, co je uložené: podepsané HTML
 * (`filled_data._signed_html`) nebo soubor ve Storage (`pdf_path` / `file_path`).
 * Novější dokumenty jdou beze změny původní cestou (volající dostane null).
 */
import { supabase } from './supabase.js'
import { loadCompanyInfo, issuedBeforeSwitch } from './company.js'

export const STORED_MISSING_NOTE = 'Dokument byl vystaven před změnou provozovatele a jeho uložený soubor není k dispozici — náhled je sestaven z dnešní šablony a nemusí odpovídat původnímu znění.'

/** Podepsané HTML → soubor ve Storage. Vrací { kind:'html', html } | { kind:'pdf', url, blob } | null.
 *  U PDF vzniká blob URL — volající ho po zavření náhledu uvolní (URL.revokeObjectURL). */
export async function loadStoredDocument(doc) {
  const signed = doc?.filled_data?._signed_html
  if (signed) return { kind: 'html', html: signed }
  const path = doc?.pdf_path || doc?.file_path
  if (!path) return null
  try {
    const { data, error } = await supabase.storage.from('documents').download(path)
    if (error || !data) return null
    if (data.type === 'application/pdf' || /\.pdf$/i.test(path)) {
      const blob = data.type === 'application/pdf' ? data : new Blob([data], { type: 'application/pdf' })
      return { kind: 'pdf', url: URL.createObjectURL(blob), blob, path }
    }
    if (/\.html?$/i.test(path) || /^text\//.test(data.type || '')) return { kind: 'html', html: await data.text(), path }
    return null // jiný typ souboru (sken, obrázek…) — řeší volající původní cestou
  } catch {
    return null
  }
}

/**
 * Dokument vystavený před změnou provozovatele → jeho uložená podoba
 * ({ kind:'missing' }, když soubor ani podepsané HTML neexistuje); jinak null.
 */
export async function storedIfIssuedBeforeSwitch(doc) {
  const company = await loadCompanyInfo()
  if (!issuedBeforeSwitch(doc?.created_at, company)) return null
  return (await loadStoredDocument(doc)) || { kind: 'missing' }
}

/** Stáhne uloženou podobu jako soubor (PDF / HTML). */
export function downloadStored(stored, baseName = 'dokument') {
  if (!stored || stored.kind === 'missing') return false
  const name = String(baseName).replace(/\.(pdf|html?)$/i, '')
  const blob = stored.kind === 'pdf' ? stored.blob : new Blob([stored.html], { type: 'text/html' })
  const url = stored.kind === 'pdf' ? stored.url : URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url; a.download = `${name}.${stored.kind === 'pdf' ? 'pdf' : 'html'}`; a.click()
  URL.revokeObjectURL(url)
  return true
}
