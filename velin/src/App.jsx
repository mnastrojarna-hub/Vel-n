import { Routes, Route } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import { useAdmin } from './hooks/useAdmin'
import Layout from './components/Layout'
import ProtectedRoute from './components/ProtectedRoute'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Placeholder from './pages/Placeholder'

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
        <Route path="/flotila" element={<Placeholder />} />
        <Route path="/rezervace" element={<Placeholder />} />
        <Route path="/zakaznici" element={<Placeholder />} />
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
