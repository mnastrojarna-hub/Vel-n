import { useState } from 'react'
import { Navigate } from 'react-router-dom'
import Button from '../components/ui/Button'
import LanguageSwitcher from '../components/LanguageSwitcher'
import { useLang } from '../i18n/LanguageProvider'

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

export default function Login({ user, onSignIn }) {
  const { t } = useLang()
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
      const msg = err.message || ''
      if (msg.includes('Invalid login credentials')) {
        setError(t('login.errInvalid'))
      } else if (msg.includes('Email not confirmed')) {
        setError(t('login.errEmailNotConfirmed'))
      } else {
        setError(t('login.errGeneric', { msg: msg || t('common.error') }))
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <div
      className="relative flex items-center justify-center min-h-screen font-montserrat"
      style={{ background: '#dff0ec' }}
    >
      <div
        className="absolute"
        style={{ top: 20, right: 20, zIndex: 10 }}
      >
        <LanguageSwitcher variant="light" />
      </div>

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
            className="text-sm font-bold uppercase"
            style={{ color: '#1a2e22', letterSpacing: 3 }}
          >
            {t('login.subtitle')}
          </p>
        </div>

        <form onSubmit={handleSubmit}>
          <div className="mb-4">
            <label
              className="block text-sm font-extrabold uppercase tracking-widest mb-2"
              style={{ color: '#1a2e22' }}
            >
              {t('login.email')}
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              placeholder={t('login.emailPlaceholder')}
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
              className="block text-sm font-extrabold uppercase tracking-widest mb-2"
              style={{ color: '#1a2e22' }}
            >
              {t('login.password')}
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              placeholder={t('login.passwordPlaceholder')}
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
              className="mb-4 text-center text-sm font-bold"
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
            {loading ? t('login.submitting') : t('login.submit')}
          </Button>
        </form>

      </div>
    </div>
  )
}
