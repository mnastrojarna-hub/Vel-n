import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'

const TABS = ['Výkon poboček', 'Výkon motorek', 'Poptávka kategorií', 'Optimální flotila', 'Doporučení přesunů']

export default function Analyza() {
  const [tab, setTab] = useState(TABS[0])

  useEffect(() => { debugLog('page.mount', 'Analyza') }, [])

  return (
    <div>
      <h1 className="text-2xl font-extrabold mb-1" style={{ color: '#1a2e22' }}>Analýza flotily</h1>
      <p className="text-sm mb-5" style={{ color: '#888' }}>Fleet Intelligence Dashboard</p>

      <div className="flex gap-2 mb-5 flex-wrap">
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '8px 18px',
              background: tab === t ? '#74FB71' : '#f1faf7',
              color: '#1a2e22',
              border: 'none',
              boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}
          >
            {t}
          </button>
        ))}
      </div>

      <div className="p-8 text-center" style={{ color: '#888' }}>
        <div style={{ fontSize: 48 }}>📊</div>
        <div className="font-bold mt-2">Sekce se připravuje</div>
      </div>
    </div>
  )
}
