import { Routes, Route } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import { useAdmin } from './hooks/useAdmin'
import Layout from './components/Layout'
import ProtectedRoute from './components/ProtectedRoute'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Placeholder from './pages/Placeholder'
import Fleet from './pages/Fleet'
import FleetDetail from './pages/FleetDetail'
import Bookings from './pages/Bookings'
import BookingDetail from './pages/BookingDetail'
import Customers from './pages/Customers'
import CustomerDetail from './pages/CustomerDetail'
import Finance from './pages/Finance'
import Accounting from './pages/Accounting'
import Documents from './pages/Documents'
import Inventory from './pages/Inventory'
import InventoryDetail from './pages/InventoryDetail'
import Service from './pages/Service'
import Messages from './pages/Messages'
import CMS from './pages/CMS'
import Statistics from './pages/Statistics'
import Purchases from './pages/Purchases'
import Government from './pages/Government'
import AICopilot from './pages/AICopilot'
import SOSPanel from './pages/SOSPanel'
import PromoCodes from './pages/PromoCodes'
import GiftVouchers from './pages/GiftVouchers'

export default function App() {
  const { user, loading, signIn, signOut } = useAuth()
  const { admin, role, loading: adminLoading, error: adminError } = useAdmin(user)

  return (
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
        <Route path="/ucetnictvi" element={<Accounting />} />
        <Route path="/dokumenty" element={<Documents />} />
        <Route path="/sklady" element={<Inventory />} />
        <Route path="/sklady/:id" element={<InventoryDetail />} />
        <Route path="/servis" element={<Service />} />
        <Route path="/zpravy" element={<Messages />} />
        <Route path="/cms" element={<CMS />} />
        <Route path="/statistiky" element={<Statistics />} />
        <Route path="/nakupy" element={<Purchases />} />
        <Route path="/statni-sprava" element={<Government />} />
        <Route path="/ai-copilot" element={<AICopilot />} />
        <Route path="/promo-kody" element={<PromoCodes />} />
        <Route path="/poukazy" element={<GiftVouchers />} />
        <Route path="/sos" element={<SOSPanel />} />
      </Route>
    </Routes>
  )
}
