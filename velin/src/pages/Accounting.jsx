import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import InvoicesTab from './accounting/InvoicesTab'
import TaxTab from './accounting/TaxTab'
import CashRegisterTab from './accounting/CashRegisterTab'

const TABS = ['Faktury', 'Daňové podklady', 'Pokladna']

export default function Accounting() {
  const [tab, setTab] = useState('Faktury')

  useEffect(() => { debugLog('page.mount', 'Accounting') }, [])

  return (
    <div>
      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => { debugLog('tab.switch', 'Accounting', { tab: t }); setTab(t) }}
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

      {tab === 'Faktury' && <InvoicesTab />}
      {tab === 'Daňové podklady' && <TaxTab />}
      {tab === 'Pokladna' && <CashRegisterTab />}
    </div>
  )
}
