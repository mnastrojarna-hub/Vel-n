import { Component } from 'react'

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
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: 24, background: '#fee2e2', borderRadius: 12, margin: 16 }}>
          <h3 style={{ color: '#dc2626', fontWeight: 800, fontSize: 14, textTransform: 'uppercase', marginBottom: 8 }}>
            Chyba pri zobrazeni stranky
          </h3>
          <pre style={{ color: '#991b1b', fontSize: 12, whiteSpace: 'pre-wrap', wordBreak: 'break-all', fontFamily: 'monospace' }}>
            {this.state.error?.message || String(this.state.error)}
          </pre>
          <button
            onClick={() => this.setState({ hasError: false, error: null })}
            style={{ marginTop: 12, padding: '8px 16px', background: '#dc2626', color: '#fff', border: 'none', borderRadius: 8, fontWeight: 700, cursor: 'pointer', fontSize: 13 }}>
            Zkusit znovu
          </button>
        </div>
      )
    }
    return this.props.children
  }
}
