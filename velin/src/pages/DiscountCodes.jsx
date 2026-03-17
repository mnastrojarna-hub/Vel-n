import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import PromoCodes from './PromoCodes'
import GiftVouchers from './GiftVouchers'

const TABS = ['Promo kódy', 'Dárkové poukazy']

export default function DiscountCodes() {
  const [tab, setTab] = useState(TABS[0])

  useEffect(() => { debugLog('page.mount', 'DiscountCodes') }, [])

  return (
    <div>
      <h1 className="text-2xl font-extrabold mb-1" style={{ color: '#1a2e22' }}>Slevové kódy</h1>
      <p className="text-sm mb-5" style={{ color: '#888' }}>Promo kódy & Dárkové poukazy</p>

      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => { debugLog('tab.switch', 'DiscountCodes', { tab: t }); setTab(t) }}
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

      {tab === 'Promo kódy' && <PromoCodes />}
      {tab === 'Dárkové poukazy' && <GiftVouchers />}
    </div>
  )
}
