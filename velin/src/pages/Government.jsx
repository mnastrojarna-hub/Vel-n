import { useState, useEffect, lazy, Suspense } from 'react'
import { debugLog } from '../lib/debugLog'
import ErrorBoundary from '../components/ErrorBoundary'
import InsuranceTab from './government/InsuranceTab'
import DataBoxTab from './government/DataBoxTab'
import CompanyTab from './government/CompanyTab'

const VATReturnsTab = lazy(() => import('./accounting/VATReturnsTab'))
const TaxReturnsTab = lazy(() => import('./accounting/TaxReturnsTab'))
const ReportsTab = lazy(() => import('./accounting/ReportsTab'))

const TABS = ['Pojistky', 'Datová schránka', 'IČO / DIČ', 'Výkazy a přiznání', 'Daňové přiznání', 'Přiznání k DPH']

export default function Government() {
  const [tab, setTab] = useState('Pojistky')

  useEffect(() => { debugLog('page.mount', 'Government') }, [])

  return (
    <div>
      <div className="flex gap-2 mb-5 flex-wrap">
        {TABS.map(t => (
          <button key={t} onClick={() => { debugLog('tab.switch', 'Government', { tab: t }); setTab(t) }}
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

      {tab === 'Pojistky' && <InsuranceTab />}
      {tab === 'Datová schránka' && <DataBoxTab />}
      {tab === 'IČO / DIČ' && <CompanyTab />}
      <Suspense fallback={<div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>}>
        <ErrorBoundary>
          {tab === 'Výkazy a přiznání' && <ReportsTab />}
          {tab === 'Daňové přiznání' && <TaxReturnsTab />}
          {tab === 'Přiznání k DPH' && <VATReturnsTab />}
        </ErrorBoundary>
      </Suspense>
    </div>
  )
}
