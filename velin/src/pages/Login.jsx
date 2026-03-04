import { useState } from 'react'
import { Navigate } from 'react-router-dom'
import Button from '../components/ui/Button'

const Logo = ({ size = 64 }) => (
  <svg width={size} height={size} viewBox="0 0 100 100" fill="none">
    <circle cx="50" cy="50" r="46" stroke="#13C14E" strokeWidth="5" />
    <path
      d="M22 72 L22 42 L50 20 L78 42 L78 72"
      stroke="#13C14E"
      strokeWidth="7"
      strokeLinecap="round"
      strokeLinejoin="round"
      fill="none"
    />
    <path d="M50 20 L50 52" stroke="#13C14E" strokeWidth="7" strokeLinecap="round" />
    <path
      d="M35 72 Q50 56 65 72"
      stroke="#13C14E"
      strokeWidth="6"
      strokeLinecap="round"
      fill="none"
    />
  </svg>
)

export default function Login({ user, onSignIn, onSignInDemo }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState(null)
  const [loading, setLoading] = useState(false)

  if (user) {
    return <Navigate to="/" replace />
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError(null)
    setLoading(true)

    try {
      await onSignIn(email, password)
    } catch (err) {
      const msg = err.message || 'Neznámá chyba'
      if (msg.includes('Invalid login credentials')) {
        setError('Nesprávný e-mail nebo heslo.')
      } else if (msg.includes('Email not confirmed')) {
        setError('E-mail nebyl potvrzen. Zkontrolujte svou schránku.')
      } else {
        setError(`Chyba přihlášení: ${msg}`)
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <div
      className="flex items-center justify-center min-h-screen font-montserrat"
      style={{ background: '#dff0ec' }}
    >
      <div
        className="bg-white rounded-card shadow-card w-full"
        style={{ maxWidth: 400, padding: '48px 40px' }}
      >
        <div className="text-center mb-8">
          <div className="flex justify-center mb-4">
            <Logo size={64} />
          </div>
          <h1
            className="text-2xl font-black tracking-tight mb-1"
            style={{ color: '#0f1a14' }}
          >
            MOTO GO 24
          </h1>
          <p
            className="text-xs font-bold uppercase"
            style={{ color: '#8aab99', letterSpacing: 3 }}
          >
            Velín — přihlášení
          </p>
        </div>

        <form onSubmit={handleSubmit}>
          <div className="mb-4">
            <label
              className="block text-[10px] font-extrabold uppercase tracking-widest mb-2"
              style={{ color: '#8aab99' }}
            >
              E-mail
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              placeholder="admin@motogo24.cz"
              className="w-full outline-none font-montserrat"
              style={{
                padding: '12px 18px',
                borderRadius: 50,
                border: '2px solid #d4e8e0',
                background: '#f1faf7',
                color: '#0f1a14',
                fontSize: 14,
                fontFamily: 'inherit',
              }}
            />
          </div>

          <div className="mb-6">
            <label
              className="block text-[10px] font-extrabold uppercase tracking-widest mb-2"
              style={{ color: '#8aab99' }}
            >
              Heslo
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              placeholder="••••••••"
              className="w-full outline-none font-montserrat"
              style={{
                padding: '12px 18px',
                borderRadius: 50,
                border: '2px solid #d4e8e0',
                background: '#f1faf7',
                color: '#0f1a14',
                fontSize: 14,
                fontFamily: 'inherit',
              }}
            />
          </div>

          {error && (
            <div
              className="mb-4 text-center text-xs font-bold"
              style={{
                padding: '10px 16px',
                borderRadius: 14,
                background: '#fee2e2',
                color: '#991b1b',
              }}
            >
              {error}
            </div>
          )}

          <Button
            green
            type="submit"
            disabled={loading}
            style={{
              width: '100%',
              justifyContent: 'center',
              padding: '14px 22px',
              fontSize: 14,
            }}
          >
            {loading ? 'Přihlašování...' : 'Přihlásit se'}
          </Button>
        </form>

        {onSignInDemo && (
          <div className="mt-4 text-center">
            <div
              className="text-[10px] font-bold uppercase mb-2"
              style={{ color: '#8aab99', letterSpacing: 1 }}
            >
              nebo
            </div>
            <button
              onClick={onSignInDemo}
              className="w-full cursor-pointer font-montserrat"
              style={{
                padding: '12px 22px',
                borderRadius: 50,
                fontSize: 13,
                fontWeight: 800,
                border: '2px solid #74FB71',
                background: 'transparent',
                color: '#3dba3a',
                textTransform: 'uppercase',
                letterSpacing: 0.5,
              }}
            >
              Demo přístup
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
