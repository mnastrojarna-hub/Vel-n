import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import './index.css'

// Po nasazení nové verze na Vercel přestanou existovat staré hashované chunky —
// dlouho otevřená záložka Velína pak při lazy-loadu stránky/modalu dostane 404
// a část appky přestane fungovat (např. uložení faktury). Jediná náprava je
// reload, který natáhne novou verzi.
// POJISTKA (2026-09-11): když po reloadu chunk stále chybí (CDN/browser drží
// starý index.html, rozjetý deploy), reload se NESMÍ opakovat do nekonečna —
// stránka pak jen „bliká" a nejde použít. Max. 1 automatický reload za minutu;
// další selhání se nechá vyhodit jako chyba (ErrorBoundary / konzole).
window.addEventListener('vite:preloadError', () => {
  let last = 0
  try { last = Number(sessionStorage.getItem('velin_chunk_reload_at') || 0) } catch { /* private mode */ }
  if (Date.now() - last < 60_000) return
  try { sessionStorage.setItem('velin_chunk_reload_at', String(Date.now())) } catch { /* ignore */ }
  window.location.reload()
})

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>
)
