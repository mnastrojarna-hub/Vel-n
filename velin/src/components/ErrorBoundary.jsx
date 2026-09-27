import { Component } from 'react'
import { debugError } from '../lib/debugLog'

// Selhání načtení lazy chunku (po nasazení nové verze na Vercel staré hashované
// soubory neexistují) — viz i `vite:preloadError` v main.jsx.
export function isChunkLoadError(error) {
  const msg = String(error?.message || error || '')
  return /dynamically imported module|Importing a module script failed|Failed to fetch dynamically|Loading chunk|Loading CSS chunk/i.test(msg)
}

export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props)
    this.state = { hasError: false, error: null }
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error }
  }

  componentDidCatch(error, errorInfo) {
    console.error('[ErrorBoundary]', error, errorInfo)
    // Pád vykreslení dřív skončil bílou obrazovkou bez jediné stopy — zapíšeme ho do
    // debug_log (DebugPanel „LOG" + tabulka), aby šel dohledat i z cizího telefonu.
    try {
      const err = error instanceof Error ? error : new Error(String(error))
      if (errorInfo?.componentStack && !err.stack?.includes('\n    in ')) {
        err.stack = `${err.stack || err.message}\n${String(errorInfo.componentStack).split('\n').slice(0, 4).join('\n')}`
      }
      debugError('render.crash', this.props.title || this.props.scope || 'ErrorBoundary', err, {
        path: typeof window !== 'undefined' ? window.location.pathname : null,
        ua: typeof navigator !== 'undefined' ? navigator.userAgent : null,
      })
    } catch { /* logování nesmí shodit fallback */ }
  }

  render() {
    if (this.state.hasError) {
      const chunk = isChunkLoadError(this.state.error)
      return (
        <div style={{ padding: 24, background: '#fee2e2', borderRadius: 12, margin: 16 }}>
          <h3 style={{ color: '#dc2626', fontWeight: 800, fontSize: 14, textTransform: 'uppercase', marginBottom: 8 }}>
            {chunk ? 'Nová verze Velína — obnovte stránku' : `Chyba při zobrazení${this.props.title ? `: ${this.props.title}` : ' stránky'}`}
          </h3>
          <pre style={{ color: '#991b1b', fontSize: 12, whiteSpace: 'pre-wrap', wordBreak: 'break-all', fontFamily: 'monospace' }}>
            {this.state.error?.message || String(this.state.error)}
          </pre>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 12 }}>
            {!chunk && (
              <button
                onClick={() => this.setState({ hasError: false, error: null })}
                style={{ padding: '8px 16px', background: '#dc2626', color: '#fff', border: 'none', borderRadius: 8, fontWeight: 700, cursor: 'pointer', fontSize: 13 }}>
                Zkusit znovu
              </button>
            )}
            <button
              onClick={() => window.location.reload()}
              style={{ padding: '8px 16px', background: chunk ? '#dc2626' : '#fff', color: chunk ? '#fff' : '#991b1b', border: '1px solid #dc2626', borderRadius: 8, fontWeight: 700, cursor: 'pointer', fontSize: 13 }}>
              Obnovit stránku
            </button>
          </div>
        </div>
      )
    }
    return this.props.children
  }
}
