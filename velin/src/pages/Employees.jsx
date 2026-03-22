import { useState, lazy, Suspense } from 'react'
import ErrorBoundary from '../components/ErrorBoundary'

const EmployeeListTab = lazy(() => import('./employees/EmployeeListTab'))
const AttendanceTab = lazy(() => import('./employees/AttendanceTab'))
const VacationTab = lazy(() => import('./employees/VacationTab'))
const ShiftsTab = lazy(() => import('./employees/ShiftsTab'))
const DocumentsTab = lazy(() => import('./employees/DocumentsTab'))
const PayrollTab = lazy(() => import('./employees/PayrollTab'))

const TABS = [
  { id: 'list', label: 'Prehled' },
  { id: 'attendance', label: 'Dochazka' },
  { id: 'vacation', label: 'Dovolena' },
  { id: 'shifts', label: 'Smeny' },
  { id: 'documents', label: 'Dokumenty' },
  { id: 'payroll', label: 'Mzdy' },
]

const Loader = () => (
  <div className="flex justify-center py-12">
    <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" />
  </div>
)

export default function Employees() {
  const [tab, setTab] = useState('list')

  return (
    <div>
      <div className="flex gap-2 mb-5 flex-wrap">
        {TABS.map(t => (
          <button key={t.id} onClick={() => setTab(t.id)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '8px 18px', border: 'none',
              background: tab === t.id ? '#74FB71' : '#f1faf7',
              color: '#1a2e22',
              boxShadow: tab === t.id ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}>
            {t.label}
          </button>
        ))}
      </div>
      <Suspense fallback={<Loader />}>
        <ErrorBoundary>
          {tab === 'list' && <EmployeeListTab />}
          {tab === 'attendance' && <AttendanceTab />}
          {tab === 'vacation' && <VacationTab />}
          {tab === 'shifts' && <ShiftsTab />}
          {tab === 'documents' && <DocumentsTab />}
          {tab === 'payroll' && <PayrollTab />}
        </ErrorBoundary>
      </Suspense>
    </div>
  )
}
