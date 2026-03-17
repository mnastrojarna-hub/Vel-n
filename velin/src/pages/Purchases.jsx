import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import SuppliersTab from './purchases/SuppliersTab'
import OrdersTab from './purchases/OrdersTab'
import ShopOrdersTab from './purchases/ShopOrdersTab'
import ProductsTab from './purchases/ProductsTab'

const TABS = ['Objednávky', 'Produkty', 'Nákupy', 'Dodavatelé']

export default function Purchases() {
  const [tab, setTab] = useState('Objednávky')

  useEffect(() => { debugLog('page.mount', 'Purchases') }, [])

  return (
    <div>
      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button key={t} onClick={() => { debugLog('tab.switch', 'Purchases', { tab: t }); setTab(t) }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '8px 18px',
              background: tab === t ? '#74FB71' : '#f1faf7',
              color: tab === t ? '#1a2e22' : '#1a2e22',
              border: 'none',
              boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}>
            {t}
          </button>
        ))}
      </div>
      {tab === 'Objednávky' && <ShopOrdersTab />}
      {tab === 'Produkty' && <ProductsTab />}
      {tab === 'Nákupy' && <OrdersTab />}
      {tab === 'Dodavatelé' && <SuppliersTab />}
    </div>
  )
}
