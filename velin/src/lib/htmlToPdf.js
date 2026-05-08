/**
 * Klient-side HTML → PDF konvertor.
 *
 * Lazy-load html2pdf.js (vendor bundle ~600 KB), aby se neřezalo do main chunků
 * pro stránky které PDF negenerují.
 *
 * Použití:
 *   import { htmlToPdfBlob, uploadHtmlAsPdf } from './htmlToPdf'
 *   const blob = await htmlToPdfBlob(html)
 *   await uploadHtmlAsPdf(supabase, 'invoices/abc.pdf', html)
 */

let _h2p = null
async function getHtml2Pdf() {
  if (_h2p) return _h2p
  const mod = await import('html2pdf.js')
  _h2p = mod.default || mod
  return _h2p
}

/**
 * Konvertuje HTML string na PDF Blob.
 * Renderuje do skrytého off-screen elementu, aby se uživateli nic neblesklo.
 */
export async function htmlToPdfBlob(html, opts = {}) {
  const html2pdf = await getHtml2Pdf()

  // Off-screen kontejner s pevnou šířkou A4 (794 px @ 96 DPI)
  const host = document.createElement('div')
  host.style.position = 'fixed'
  host.style.left = '-10000px'
  host.style.top = '0'
  host.style.width = '794px'
  host.style.background = '#ffffff'
  host.innerHTML = html
  document.body.appendChild(host)

  try {
    const filename = opts.filename || 'document.pdf'
    const blob = await html2pdf()
      .set({
        margin: opts.margin ?? [10, 10, 10, 10],
        filename,
        image: { type: 'jpeg', quality: 0.95 },
        html2canvas: { scale: 2, useCORS: true, backgroundColor: '#ffffff', logging: false },
        jsPDF: { unit: 'mm', format: 'a4', orientation: opts.orientation || 'portrait', compress: true },
        pagebreak: { mode: ['css', 'legacy'] },
      })
      .from(host)
      .outputPdf('blob')
    return blob
  } finally {
    try { document.body.removeChild(host) } catch {}
  }
}

/**
 * Konvertuje HTML na PDF a nahraje do Supabase Storage (bucket `documents`).
 * Cesta `path` musí končit `.pdf`.
 *
 * Pokud konverze selže (např. CORS na obrázek), zkusí fallback upload jako HTML
 * se stejnou cestou (jen `.pdf` → `.html`) — aby flow nikdy nespadl tvrdě.
 *
 * Vrací finální path (s odpovídající příponou).
 */
export async function uploadHtmlAsPdf(supabase, path, html, opts = {}) {
  if (!path.endsWith('.pdf')) throw new Error('uploadHtmlAsPdf: path must end with .pdf')
  try {
    const blob = await htmlToPdfBlob(html, opts)
    const { error } = await supabase.storage
      .from('documents')
      .upload(path, blob, { upsert: true, contentType: 'application/pdf' })
    if (error) throw error
    return path
  } catch (e) {
    // Fallback — uložíme jako HTML, ať uživatel nepřijde o dokument
    const fallbackPath = path.replace(/\.pdf$/i, '.html')
    const blob = new Blob([html], { type: 'text/html' })
    const { error } = await supabase.storage
      .from('documents')
      .upload(fallbackPath, blob, { upsert: true, contentType: 'text/html' })
    if (error) throw e // hodíme původní chybu, ne fallback
    console.warn('[uploadHtmlAsPdf] PDF konverze selhala, uloženo jako HTML:', e?.message)
    return fallbackPath
  }
}
