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
        <Route path="/finance" element={<Placeholder />} />
        <Route path="/ucetnictvi" element={<Placeholder />} />
        <Route path="/dokumenty" element={<Placeholder />} />
        <Route path="/sklady" element={<Placeholder />} />
        <Route path="/servis" element={<Placeholder />} />
        <Route path="/zpravy" element={<Placeholder />} />
        <Route path="/cms" element={<Placeholder />} />
        <Route path="/statistiky" element={<Placeholder />} />
        <Route path="/nakupy" element={<Placeholder />} />
        <Route path="/statni-sprava" element={<Placeholder />} />
        <Route path="/ai-copilot" element={<Placeholder />} />
      </Route>
    </Routes>
  )
}
