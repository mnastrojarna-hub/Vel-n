import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import WebTextsTab from './cms/WebTextsTab'
import FeatureFlagsTab from './cms/FeatureFlagsTab'
import AiTrafficTab from './cms/AiTrafficTab'
import SeoHealthTab from './cms/SeoHealthTab'

// Pozn.: Záložky „Proměnné" (PagesTab → cms_variables) a „Stránky CMS"
// (PagesTab → cms_pages) byly odebrány jako duplicity:
//  - Proměnné = stejná tabulka cms_variables co Texty webu; ne-web klíče
//    (company_*, datove_schranky_id) mají vlastní editor v sekci Government.
//  - Stránky CMS = stejná tabulka cms_pages co Blog; web ji jako „stránky"
//    nečte (legacy /cms/<slug> → 301 na /dokumenty z document_templates).
const TABS = ['SEO Health', 'Texty webu', 'AI návštěvnost', 'Feature flags']

export default function CMS() {
  const [tab, setTab] = useState('SEO Health')
  // Jump z SEO Health do Texty webu — predame pageId + konkretni klic pole
  // (pro auto-scroll + highlight) + sectionId (pro otevreni spravne sekce).
  const [textsJump, setTextsJump] = useState({ pageId: null, fieldKey: null, sectionId: null, ts: 0 })

  useEffect(() => { debugLog('page.mount', 'CMS') }, [])

  const handleJumpToText = (pageId, fieldKey, sectionId) => {
    // ts = timestamp aby re-trigger fungoval i kdyz se klikne 2x na stejne pole
    setTextsJump({ pageId, fieldKey, sectionId, ts: Date.now() })
    setTab('Texty webu')
    debugLog('seo.jumpToText', 'CMS', { pageId, fieldKey, sectionId })
  }

  return (
    <div>
      <div className="flex gap-2 mb-5" style={{ flexWrap: 'wrap' }}>
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => { debugLog('tab.switch', 'CMS', { tab: t }); setTab(t) }}
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
      {tab === 'Texty webu' && (
        <WebTextsTab
          initialPageId={textsJump.pageId}
          initialFieldKey={textsJump.fieldKey}
          initialSectionId={textsJump.sectionId}
          jumpTimestamp={textsJump.ts}
        />
      )}
      {tab === 'AI návštěvnost' && <AiTrafficTab />}
      {tab === 'Feature flags' && <FeatureFlagsTab />}
    </div>
  )
}
