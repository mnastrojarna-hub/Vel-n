import { lazy, Suspense } from 'react'
import { Routes, Route } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import { useAdmin } from './hooks/useAdmin'
import Layout from './components/Layout'
import ProtectedRoute from './components/ProtectedRoute'
import SectionGuard from './components/SectionGuard'
import Login from './pages/Login'

// Lazy-loaded pages
const Dashboard = lazy(() => import('./pages/Dashboard'))
const Fleet = lazy(() => import('./pages/Fleet'))
const FleetDetail = lazy(() => import('./pages/FleetDetail'))
const Bookings = lazy(() => import('./pages/Bookings'))
const BookingDetail = lazy(() => import('./pages/BookingDetail'))
const Customers = lazy(() => import('./pages/Customers'))
const CustomerDetail = lazy(() => import('./pages/CustomerDetail'))
const Finance = lazy(() => import('./pages/Finance'))
const DiscountCodes = lazy(() => import('./pages/DiscountCodes'))
const Documents = lazy(() => import('./pages/Documents'))
const Inventory = lazy(() => import('./pages/Inventory'))
const InventoryDetail = lazy(() => import('./pages/InventoryDetail'))
const Service = lazy(() => import('./pages/Service'))
const ServiceMotoBook = lazy(() => import('./pages/service/ServiceMotoBook'))
const Messages = lazy(() => import('./pages/Messages'))
const CMS = lazy(() => import('./pages/CMS'))
const Analyza = lazy(() => import('./pages/Analyza'))
const Purchases = lazy(() => import('./pages/Purchases'))
const Government = lazy(() => import('./pages/Government'))
const AICopilot = lazy(() => import('./pages/AICopilot'))
const SOSPanel = lazy(() => import('./pages/SOSPanel'))
const Branches = lazy(() => import('./pages/Branches'))
const Logistika = lazy(() => import('./pages/Logistika'))
const Trasy = lazy(() => import('./pages/Trasy'))
const Employees = lazy(() => import('./pages/Employees'))
const AiOrchestrator = lazy(() => import('./pages/AiOrchestrator'))
const VelinUsers = lazy(() => import('./pages/VelinUsers'))

function PageLoader() {
  return (
    <div className="flex items-center justify-center py-20">
      <div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} />
    </div>
  )
}

export default function App() {
  const { user, loading, signIn, signOut } = useAuth()
  const { admin, loading: adminLoading, error: adminError } = useAdmin(user)

  // Každá route patří do sekce menu (lib/velinSections.js); účet s omezením
  // (admin_users.permissions.sections) se na cizí sekci nedostane ani přímým URL.
  const G = (section, element) => (
    <SectionGuard admin={admin} section={section}>{element}</SectionGuard>
  )

  return (
    <Suspense fallback={<PageLoader />}>
      <Routes>
        <Route path="/login" element={<Login user={user} onSignIn={signIn} />} />
        <Route
          element={
            <ProtectedRoute
              user={user}
              loading={loading}
              adminLoading={adminLoading}
              adminError={adminError}
            >
              <Layout admin={admin} onSignOut={signOut} />
            </ProtectedRoute>
          }
        >
          <Route path="/" element={G('dashboard', <Dashboard />)} />
          <Route path="/flotila" element={G('fleet', <Fleet />)} />
          <Route path="/flotila/:id" element={G('fleet', <FleetDetail />)} />
          <Route path="/rezervace" element={G('bookings', <Bookings />)} />
          <Route path="/rezervace/:id" element={G('bookings', <BookingDetail />)} />
          <Route path="/zakaznici" element={G('customers', <Customers />)} />
          <Route path="/zakaznici/:id" element={G('customers', <CustomerDetail />)} />
          <Route path="/finance" element={G('finance', <Finance />)} />
          <Route path="/dokumenty" element={G('documents', <Documents />)} />
          <Route path="/sklady" element={G('logistics', <Inventory />)} />
          <Route path="/sklady/:id" element={G('logistics', <InventoryDetail />)} />
          <Route path="/servis" element={G('service', <Service />)} />
          <Route path="/servis/motorka/:id" element={G('service', <ServiceMotoBook admin={admin} />)} />
          <Route path="/zpravy" element={G('messages', <Messages />)} />
          <Route path="/cms" element={G('cms', <CMS />)} />
          <Route path="/analyza" element={G('analyza', <Analyza />)} />
          <Route path="/e-shop" element={G('eshop', <Purchases />)} />
          <Route path="/statni-sprava" element={G('government', <Government />)} />
          <Route path="/ai-copilot" element={G('ai', <AICopilot />)} />
          <Route path="/slevove-kody" element={G('discount-codes', <DiscountCodes />)} />
          <Route path="/pobocky" element={G('branches', <Branches />)} />
          <Route path="/logistika" element={G('logistics', <Logistika />)} />
          <Route path="/trasy" element={G('trasy', <Trasy />)} />
          <Route path="/sos" element={G('sos', <SOSPanel />)} />
          <Route path="/zamestnanci" element={G('employees', <Employees />)} />
          <Route path="/orchestrator" element={G('orchestrator', <AiOrchestrator />)} />
          <Route path="/uzivatele" element={G('users', <VelinUsers admin={admin} />)} />
        </Route>
      </Routes>
    </Suspense>
  )
}
