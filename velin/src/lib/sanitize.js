import DOMPurify from 'dompurify'

// Centrální XSS sanitizace — VŠECHNY dangerouslySetInnerHTML a document.write
// sinky ve Velíně musí jít přes tyto helpery (security fix 2026-06-10).

// HTML fragmenty vykreslované v UI (e-maily, šablony, AI odpovědi, FAQ, náhledy)
export function sanitizeHtml(html) {
  if (!html) return ''
  return DOMPurify.sanitize(String(html), {
    USE_PROFILES: { html: true },
    ADD_TAGS: ['style'],
    ADD_ATTR: ['target'],
  })
}

// Celé HTML dokumenty (faktury, smlouvy, reporty) pro náhled / tiskové okno —
// zachovává <html>/<head>/<style>, odstraňuje skripty a event handlery
export function sanitizeDocHtml(html) {
  if (!html) return ''
  return DOMPurify.sanitize(String(html), {
    WHOLE_DOCUMENT: true,
    ADD_TAGS: ['style', 'meta', 'title'],
    ADD_ATTR: ['target', 'http-equiv', 'content', 'charset', 'media'],
  })
}

// Bezpečné otevření tiskového okna s dokumentem
export function openPrintWindow(html, { autoPrint = true } = {}) {
  const win = window.open('', '_blank')
  if (!win) return null
  win.document.write(sanitizeDocHtml(html))
  win.document.close()
  if (autoPrint) win.onload = () => win.print()
  return win
}
