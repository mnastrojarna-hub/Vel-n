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
  win.document.open()
  win.document.write(sanitizeDocHtml(html))
  win.document.close()
  if (autoPrint) triggerPrintWhenReady(win)
  return win
}

// Tisk až po úplném načtení dokumentu VČETNĚ obrázků (logo a QR se stahují
// z externích URL). Dřívější `win.onload = () => win.print()` závodilo
// s document.close(): load mohl proběhnout dřív, než se handler pověsil
// (tisk nikdy nespustil), nebo se tisklo uprostřed stahování obrázků —
// spooler pak dostal vadnou úlohu, která zablokovala tiskovou frontu
// („tiskárna vyžaduje vaši pozornost").
function triggerPrintWhenReady(win, { imageTimeoutMs = 4000, readyTimeoutMs = 15000 } = {}) {
  let printed = false
  let waiting = false
  const doPrint = () => {
    if (printed || win.closed) return
    printed = true
    try { win.focus(); win.print() } catch { /* okno mezitím zavřené */ }
  }
  const waitForImages = () => {
    if (waiting || printed) return
    waiting = true
    // img.complete platí i pro selhané obrázky — nečekáme na ně znovu
    const pending = Array.from(win.document.images || []).filter(img => !img.complete)
    if (pending.length === 0) { doPrint(); return }
    let left = pending.length
    const done = () => { if (--left <= 0) doPrint() }
    pending.forEach(img => {
      img.addEventListener('load', done, { once: true })
      img.addEventListener('error', done, { once: true })
    })
    setTimeout(doPrint, imageTimeoutMs) // pomalé externí QR/logo tisk neblokuje
  }
  if (win.document.readyState === 'complete') { waitForImages(); return }
  win.addEventListener('load', waitForImages, { once: true })
  // Pojistka: po document.write nemusí load event spolehlivě přijít
  const poll = setInterval(() => {
    if (printed || win.closed) { clearInterval(poll); return }
    if (win.document.readyState === 'complete') { clearInterval(poll); waitForImages() }
  }, 200)
  setTimeout(() => clearInterval(poll), readyTimeoutMs)
}
