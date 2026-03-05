import { useState } from 'react'
import VariablesTab from './cms/VariablesTab'
import PagesTab from './cms/PagesTab'
import FeatureFlagsTab from './cms/FeatureFlagsTab'

const TABS = ['Proměnné', 'Stránky', 'Feature flags']

export default function CMS() {
  const [tab, setTab] = useState('Proměnné')

  return (
    <div>
      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '8px 18px',
              background: tab === t ? '#74FB71' : '#f1faf7',
              color: tab === t ? '#1a2e22' : '#4a6357',
              border: 'none',
              boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'Proměnné' && <VariablesTab />}
      {tab === 'Stránky' && <PagesTab />}
      {tab === 'Feature flags' && <FeatureFlagsTab />}
    </div>
  )
}
