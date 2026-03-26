import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import WebTextsTab from './cms/WebTextsTab'
import PagesTab from './cms/PagesTab'
import VariablesTab from './cms/VariablesTab'
import FeatureFlagsTab from './cms/FeatureFlagsTab'

const TABS = ['Texty webu', 'Stránky CMS', 'Proměnné', 'Feature flags']

export default function CMS() {
  const [tab, setTab] = useState('Texty webu')

  useEffect(() => { debugLog('page.mount', 'CMS') }, [])

  return (
    <div>
      <div className="flex gap-2 mb-5">
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

      {tab === 'Texty webu' && <WebTextsTab />}
      {tab === 'Stránky CMS' && <PagesTab />}
      {tab === 'Proměnné' && <VariablesTab />}
      {tab === 'Feature flags' && <FeatureFlagsTab />}
    </div>
  )
}
