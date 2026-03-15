import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import VykonPobocek from './analyza/VykonPobocek'
import VykonMotorek from './analyza/VykonMotorek'
import PoptavkaKategorii from './analyza/PoptavkaKategorii'
import OptimalniFlotila from './analyza/OptimalniFlotila'
import DoporuceniPresunu from './analyza/DoporuceniPresunu'
import DoporuceniLokaci from './analyza/DoporuceniLokaci'
import AnalyzaZakazniku from './analyza/AnalyzaZakazniku'

const TABS = ['Výkon poboček', 'Výkon motorek', 'Poptávka kategorií', 'Optimální flotila', 'Doporučení přesunů', 'Doporučení lokací', 'Zákazníci']

export default function Analyza() {
  const [tab, setTab] = useState(TABS[0])

  useEffect(() => { debugLog('page.mount', 'Analyza') }, [])

  return (
    <div>
      <h1 className="text-2xl font-extrabold mb-1" style={{ color: '#1a2e22' }}>Analýza</h1>
      <p className="text-sm mb-5" style={{ color: '#888' }}>Fleet & Customer Intelligence</p>

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

      {tab === 'Výkon poboček' && <VykonPobocek />}
      {tab === 'Výkon motorek' && <VykonMotorek />}
      {tab === 'Poptávka kategorií' && <PoptavkaKategorii />}
      {tab === 'Optimální flotila' && <OptimalniFlotila />}
      {tab === 'Doporučení přesunů' && <DoporuceniPresunu />}
      {tab === 'Doporučení lokací' && <DoporuceniLokaci />}
      {tab === 'Zákazníci' && <AnalyzaZakazniku />}
    </div>
  )
}
