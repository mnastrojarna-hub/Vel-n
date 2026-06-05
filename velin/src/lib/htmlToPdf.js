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

import { supabase } from './supabase'

let _h2p = null
let _h2pPromise = null
const H2P_CDN = 'https://cdn.jsdelivr.net/npm/html2pdf.js@0.10.2/dist/html2pdf.bundle.min.js'

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[data-h2p="1"]`)
    if (existing) {
      if (window.html2pdf) return resolve(window.html2pdf)
      existing.addEventListener('load', () => resolve(window.html2pdf))
      existing.addEventListener('error', reject)
      return
    }
    const s = document.createElement('script')
    s.src = src
    s.async = true
    s.dataset.h2p = '1'
    s.onload = () => resolve(window.html2pdf)
    s.onerror = reject
    document.head.appendChild(s)
  })
}

async function getHtml2Pdf() {
  if (_h2p) return _h2p
  if (_h2pPromise) return _h2pPromise
  _h2pPromise = (async () => {
    if (typeof window !== 'undefined' && window.html2pdf) {
      _h2p = window.html2pdf
      return _h2p
    }
    const fn = await loadScript(H2P_CDN)
    if (!fn) throw new Error('html2pdf.js se nepodařilo načíst z CDN')
    _h2p = fn
    return _h2p
  })()
  return _h2pPromise
}

/**
 * Konvertuje HTML string na PDF Blob.
 *
 * PRIMÁRNĚ přes serverovou edge funkci `render-pdf` (PDFShift / headless Chrome) —
 * stejný renderer jako e-shop/maily (generate-invoice), takže doklady vypadají 1:1.
 * Když server selže (chybí klíč, HTTP chyba, offline), spadne na klientský
 * html2pdf.js fallback, aby flow nikdy neselhal tvrdě.
 */
export async function htmlToPdfBlob(html, opts = {}) {
  try {
    const { data, error } = await supabase.functions.invoke('render-pdf', {
      body: { html, landscape: opts.orientation === 'landscape' },
    })
    if (error) throw error
    if (data instanceof Blob) {
      if (data.type === 'application/pdf') return data
      // supabase-js vrátí Blob i pro JSON chybu — přečti a vyhoď
      const txt = await data.text().catch(() => '')
      throw new Error(txt || 'render-pdf nevrátil PDF')
    }
    if (data?.error) throw new Error(data.error)
    throw new Error('render-pdf nevrátil PDF')
  } catch (e) {
    console.warn('[htmlToPdfBlob] server render-pdf selhal, fallback na html2pdf.js:', e?.message)
    return htmlToPdfBlobClient(html, opts)
  }
}

/**
 * Klientský fallback — html2pdf.js (html2canvas). Méně přesný (rasterizace),
 * používá se jen když serverový render-pdf není dostupný.
 */
async function htmlToPdfBlobClient(html, opts = {}) {
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
