import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import './index.css'

// Po nasazení nové verze na Vercel přestanou existovat staré hashované chunky —
// dlouho otevřená záložka Velína pak při lazy-loadu stránky/modalu dostane 404
// a část appky přestane fungovat (např. uložení faktury). Jediná náprava je
// reload, který natáhne novou verzi.
window.addEventListener('vite:preloadError', () => { window.location.reload() })

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>
)
