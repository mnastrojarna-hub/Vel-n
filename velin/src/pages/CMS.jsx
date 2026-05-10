import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import WebTextsTab from './cms/WebTextsTab'
import PagesTab from './cms/PagesTab'
import VariablesTab from './cms/VariablesTab'
import FeatureFlagsTab from './cms/FeatureFlagsTab'
import AiTrafficTab from './cms/AiTrafficTab'
import SeoHealthTab from './cms/SeoHealthTab'

const TABS = ['SEO Health', 'Texty webu', 'AI návštěvnost', 'Stránky CMS', 'Proměnné', 'Feature flags']

export default function CMS() {
  const [tab, setTab] = useState('SEO Health')
  // Klic stranky pro 'Texty webu' tab — kdyz uzivatel klikne 'Opravit' v
  // SEO Health, prepne se sem a otevre konkretni stranku
  const [textsPageJump, setTextsPageJump] = useState(null)

  useEffect(() => { debugLog('page.mount', 'CMS') }, [])

  const handleJumpToText = (pageId) => {
    setTextsPageJump(pageId)
    setTab('Texty webu')
    debugLog('seo.jumpToText', 'CMS', { pageId })
  }

  return (
    <div>
      <div className="flex gap-2 mb-5" style={{ flexWrap: 'wrap' }}>
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => { debugLog('tab.switch', 'CMS', { tab: t }); setTab(t); setTextsPageJump(null) }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '8px 18px',
              background: tab === t ? '#74FB71' : '#f1faf7',
              color: tab === t ? '#1a2e22' : '#1a2e22',
              border: 'none',
              boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'SEO Health' && <SeoHealthTab onJumpToText={handleJumpToText} />}
      {tab === 'Texty webu' && <WebTextsTab initialPageId={textsPageJump} />}
      {tab === 'AI návštěvnost' && <AiTrafficTab />}
      {tab === 'Stránky CMS' && <PagesTab />}
      {tab === 'Proměnné' && <VariablesTab />}
      {tab === 'Feature flags' && <FeatureFlagsTab />}
    </div>
  )
}
