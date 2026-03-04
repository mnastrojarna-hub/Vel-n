import { useState } from 'react'
import TemplatesTab from './documents/TemplatesTab'
import GeneratedTab from './documents/GeneratedTab'
import UploadedTab from './documents/UploadedTab'

const TABS = ['Šablony', 'Vygenerované', 'Nahrané doklady']

export default function Documents() {
  const [tab, setTab] = useState('Šablony')

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

      {tab === 'Šablony' && <TemplatesTab />}
      {tab === 'Vygenerované' && <GeneratedTab />}
      {tab === 'Nahrané doklady' && <UploadedTab />}
    </div>
  )
}
