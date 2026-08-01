// MotoGo24 — Velín: import smluvního textu z PDF
//
// Nahrané PDF pošle edge funkci `pdf-to-html` (Claude document block), která
// vrátí obsah jako čisté sémantické HTML se 100% zachovaným textem. HTML se
// pak ukládá STÁVAJÍCÍ cestou do document_templates.content_html — překlady,
// generování dokumentů i mailové přílohy fungují beze změny.

import { supabase, supabaseUrl, supabaseAnonKey } from './supabase'

export const PDF_IMPORT_MAX_BYTES = 10 * 1024 * 1024 // musí odpovídat limitu edge fn

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result).replace(/^data:[^;]+;base64,/, ''))
    reader.onerror = () => reject(new Error('Soubor se nepodařilo přečíst.'))
    reader.readAsDataURL(file)
  })
}

/**
 * Převede PDF soubor na HTML přes edge funkci `pdf-to-html`.
 * Vrací { success, html?, error? }. Nehází výjimky.
 */
export async function convertPdfToHtml(file) {
  if (!file) return { success: false, error: 'Nebyl vybrán žádný soubor.' }
  const isPdf = file.type === 'application/pdf' || /\.pdf$/i.test(file.name || '')
  if (!isPdf) return { success: false, error: 'Soubor musí být PDF.' }
  if (file.size > PDF_IMPORT_MAX_BYTES) return { success: false, error: 'PDF je příliš velké (max 10 MB).' }
  try {
    const pdf_base64 = await fileToBase64(file)
    const { data: { session } } = await supabase.auth.getSession()
    const accessToken = session?.access_token || supabaseAnonKey
    const response = await fetch(`${supabaseUrl}/functions/v1/pdf-to-html`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'apikey': supabaseAnonKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ pdf_base64 }),
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok || !data?.success || !data?.html) {
      return { success: false, error: data?.error || `HTTP ${response.status}` }
    }
    return { success: true, html: data.html }
  } catch (e) {
    return { success: false, error: e?.message || String(e) }
  }
}
