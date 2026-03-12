import { Navigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

export default function ProtectedRoute({ user, loading, adminLoading, adminError, children }) {
  if (loading || adminLoading) {
    return (
      <div
        className="flex items-center justify-center h-screen font-montserrat"
        style={{ background: '#dff0ec' }}
      >
        <div className="text-center">
          <div
            className="inline-block w-10 h-10 rounded-full animate-spin mb-4"
            style={{
              border: '3px solid #d4e8e0',
              borderTopColor: '#74FB71',
            }}
          />
          <div className="text-sm font-semibold" style={{ color: '#1a2e22' }}>
            Načítání...
          </div>
        </div>
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" replace />
  }

  if (adminError) {
    return (
      <div
        className="flex items-center justify-center h-screen font-montserrat"
        style={{ background: '#dff0ec' }}
      >
        <div
          className="bg-white rounded-card shadow-card text-center"
          style={{ padding: '40px 48px', maxWidth: 420 }}
        >
          <div className="text-5xl mb-4">🚫</div>
          <h2 className="text-lg font-black mb-2" style={{ color: '#0f1a14' }}>
            Přístup odepřen
          </h2>
          <p className="text-sm font-medium mb-4" style={{ color: '#1a2e22' }}>
            {adminError}
          </p>
          <button
            onClick={() => supabase.auth.signOut()}
            className="text-sm font-semibold px-4 py-2 rounded-lg"
            style={{ background: '#74FB71', color: '#0f1a14' }}
          >
            Odhlásit se
          </button>
        </div>
      </div>
    )
  }

  return children
}
