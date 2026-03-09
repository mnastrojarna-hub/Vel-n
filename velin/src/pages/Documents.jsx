import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import TemplatesTab from './documents/TemplatesTab'
import GeneratedTab from './documents/GeneratedTab'
import UploadedTab from './documents/UploadedTab'
import EmailTemplatesTab from './documents/EmailTemplatesTab'
import InvoicesTab from './documents/InvoicesTab'

const TABS = ['Šablony', 'Vygenerované', 'Nahrané doklady', 'E-mailové šablony', 'Faktury']

export default function Documents() {
  const [tab, setTab] = useState('Šablony')

  useEffect(() => { debugLog('page.mount', 'Documents') }, [])

  return (
    <div>
      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => { debugLog('tab.switch', 'Documents', { tab: t }); setTab(t) }}
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
      {tab === 'E-mailové šablony' && <EmailTemplatesTab />}
      {tab === 'Faktury' && <InvoicesTab />}
    </div>
  )
}
