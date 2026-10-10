import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import VykonPobocek from './analyza/VykonPobocek'
import VykonMotorek from './analyza/VykonMotorek'
import VykonNajezd from './analyza/VykonNajezd'
import PoptavkaKategorii from './analyza/PoptavkaKategorii'
import OptimalniFlotila from './analyza/OptimalniFlotila'
import DoporuceniPresunu from './analyza/DoporuceniPresunu'
import DoporuceniLokaci from './analyza/DoporuceniLokaci'
import AnalyzaZakazniku from './analyza/AnalyzaZakazniku'
import WebRezervacniFunnel from './analyza/WebRezervacniFunnel'
import AppRezervacniFunnel from './analyza/AppRezervacniFunnel'
import Navstevnost from './analyza/Navstevnost'
import AplikaceStats from './analyza/AplikaceStats'
import AiTraffic from './analyza/AiTraffic'
import AiConversations from './analyza/AiConversations'
import KalkulaceCen from './analyza/KalkulaceCen'
import Statistics from './Statistics'

const TABS = ['Výkon poboček', 'Výkon motorek', 'Nájezd km', 'Kalkulace cen', 'Poptávka kategorií', 'Optimální flotila', 'Doporučení přesunů', 'Doporučení lokací', 'Zákazníci', 'Web funnel', 'App funnel', 'Návštěvnost', 'Aplikace', 'AI traffic', 'AI konverzace', 'Statistiky']

export default function Analyza() {
  const [tab, setTab] = useState(TABS[0])

  useEffect(() => { debugLog('page.mount', 'Analyza') }, [])

  return (
    <div>
      <h1 className="text-2xl font-extrabold mb-1" style={{ color: '#1a2e22' }}>Analýza</h1>
      <p className="text-sm mb-5" style={{ color: '#888' }}>Fleet & Customer Intelligence</p>

      {/* 16 záložek se zalamuje (všechny vidět); na dotyku min. výška 40 px.
          Telefon: kompaktnější čipy (menší odsazení a písmo), ať lišta nezabere celou obrazovku. */}
      <div className="flex gap-2 max-md:gap-1.5 mb-5 flex-wrap">
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer max-lg:min-h-[40px] max-md:!px-3 max-md:!py-1 max-md:text-xs max-md:tracking-normal"
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
      {tab === 'Nájezd km' && <VykonNajezd />}
      {tab === 'Kalkulace cen' && <KalkulaceCen />}
      {tab === 'Poptávka kategorií' && <PoptavkaKategorii />}
      {tab === 'Optimální flotila' && <OptimalniFlotila />}
      {tab === 'Doporučení přesunů' && <DoporuceniPresunu />}
      {tab === 'Doporučení lokací' && <DoporuceniLokaci />}
      {tab === 'Zákazníci' && <AnalyzaZakazniku />}
      {tab === 'Web funnel' && <WebRezervacniFunnel />}
      {tab === 'App funnel' && <AppRezervacniFunnel />}
      {tab === 'Návštěvnost' && <Navstevnost />}
      {tab === 'Aplikace' && <AplikaceStats />}
      {tab === 'AI traffic' && <AiTraffic />}
      {tab === 'AI konverzace' && <AiConversations />}
      {tab === 'Statistiky' && <Statistics />}
    </div>
  )
}
