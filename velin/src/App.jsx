import { lazy, Suspense } from 'react'
import { Routes, Route } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import { useAdmin } from './hooks/useAdmin'
import Layout from './components/Layout'
import ProtectedRoute from './components/ProtectedRoute'
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
const Messages = lazy(() => import('./pages/Messages'))
const CMS = lazy(() => import('./pages/CMS'))
const Analyza = lazy(() => import('./pages/Analyza'))
const Purchases = lazy(() => import('./pages/Purchases'))
const Government = lazy(() => import('./pages/Government'))
const AICopilot = lazy(() => import('./pages/AICopilot'))
const SOSPanel = lazy(() => import('./pages/SOSPanel'))
const Branches = lazy(() => import('./pages/Branches'))
const Employees = lazy(() => import('./pages/Employees'))

function PageLoader() {
  return (
    <div className="flex items-center justify-center py-20">
      <div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} />
    </div>
  )
}

export default function App() {
  const { user, loading, signIn, signOut } = useAuth()
  const { admin, role, loading: adminLoading, error: adminError } = useAdmin(user)

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
          <Route path="/" element={<Dashboard />} />
          <Route path="/flotila" element={<Fleet />} />
          <Route path="/flotila/:id" element={<FleetDetail />} />
          <Route path="/rezervace" element={<Bookings />} />
          <Route path="/rezervace/:id" element={<BookingDetail />} />
          <Route path="/zakaznici" element={<Customers />} />
          <Route path="/zakaznici/:id" element={<CustomerDetail />} />
          <Route path="/finance" element={<Finance />} />
          <Route path="/dokumenty" element={<Documents />} />
          <Route path="/sklady" element={<Inventory />} />
          <Route path="/sklady/:id" element={<InventoryDetail />} />
          <Route path="/servis" element={<Service />} />
          <Route path="/zpravy" element={<Messages />} />
          <Route path="/cms" element={<CMS />} />
          <Route path="/analyza" element={<Analyza />} />
          <Route path="/e-shop" element={<Purchases />} />
          <Route path="/statni-sprava" element={<Government />} />
          <Route path="/ai-copilot" element={<AICopilot />} />
          <Route path="/slevove-kody" element={<DiscountCodes />} />
          <Route path="/pobocky" element={<Branches />} />
          <Route path="/sos" element={<SOSPanel />} />
          <Route path="/zamestnanci" element={<Employees />} />
        </Route>
      </Routes>
    </Suspense>
  )
}
