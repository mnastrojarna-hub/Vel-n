import { useState } from 'react'
import { Navigate } from 'react-router-dom'
import Button from '../components/ui/Button'
import { supabase } from '../lib/supabase'

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

const inputStyle = {
  padding: '12px 18px',
  borderRadius: 50,
  border: '2px solid #d4e8e0',
  background: '#f1faf7',
  color: '#0f1a14',
  fontSize: 14,
  fontFamily: 'inherit',
}

const labelStyle = { color: '#1a2e22' }

export default function Login({ user, onSignIn }) {
  const [mode, setMode] = useState('login') // 'login' | 'forgot' | 'reset'
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [otp, setOtp] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [newPassword2, setNewPassword2] = useState('')
  const [error, setError] = useState(null)
  const [info, setInfo] = useState(null)
  const [loading, setLoading] = useState(false)

  if (user) {
    return <Navigate to="/" replace />
  }

  const goTo = (next) => {
    setMode(next)
    setError(null)
    setInfo(null)
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

  const handleForgot = async (e) => {
    e.preventDefault()
    setError(null)
    setInfo(null)
    setLoading(true)

    try {
      const { error: fnError } = await supabase.functions.invoke('send-recovery-otp', {
        body: { email: email.trim().toLowerCase() },
      })
      if (fnError) {
        setError('Server je nedostupný, zkuste to prosím za chvíli.')
        return
      }
      setMode('reset')
      setOtp('')
      setNewPassword('')
      setNewPassword2('')
      setInfo('Ověřovací kód jsme poslali na váš e-mail. Platí 1 hodinu — zkontrolujte i spam.')
    } catch {
      setError('Server je nedostupný, zkuste to prosím za chvíli.')
    } finally {
      setLoading(false)
    }
  }

  const handleReset = async (e) => {
    e.preventDefault()
    setError(null)
    setInfo(null)

    const code = otp.trim().toUpperCase()
    if (code.length < 6) {
      setError('Kód není správný. Zkontrolujte e-mail.')
      return
    }
    if (newPassword.length < 8) {
      setError('Heslo musí mít alespoň 8 znaků.')
      return
    }
    if (newPassword !== newPassword2) {
      setError('Hesla se neshodují.')
      return
    }

    setLoading(true)
    try {
      const { data, error: verifyError } = await supabase.auth.verifyOtp({
        email: email.trim().toLowerCase(),
        token: code,
        type: 'recovery',
      })
      if (verifyError || !data?.session) {
        setError('Kód není správný nebo vypršel. Zkuste to znovu.')
        return
      }

      const { error: updateError } = await supabase.auth.updateUser({ password: newPassword })
      if (updateError) {
        const m = (updateError.message || '').toLowerCase()
        if (m.includes('different from the old') || updateError.code === 'same_password') {
          setError('Nové heslo musí být jiné než to současné.')
        } else {
          setError('Heslo se nepodařilo uložit. Zkuste to znovu.')
        }
        return
      }
      // verifyOtp už vytvořil session → onAuthStateChange v useAuth nás přihlásí a přesměruje.
    } catch {
      setError('Server je nedostupný, zkuste to prosím za chvíli.')
    } finally {
      setLoading(false)
    }
  }

  const subtitle =
    mode === 'forgot'
      ? 'Velín — obnova hesla'
      : mode === 'reset'
        ? 'Velín — nové heslo'
        : 'Velín — přihlášení'

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
            className="text-sm font-bold uppercase"
            style={{ color: '#1a2e22', letterSpacing: 3 }}
          >
            {subtitle}
          </p>
        </div>

        {mode === 'login' && (
          <form onSubmit={handleSubmit}>
            <div className="mb-4">
              <label
                className="block text-sm font-extrabold uppercase tracking-widest mb-2"
                style={labelStyle}
              >
                E-mail
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                placeholder="admin@motogo24.cz"
                autoComplete="email"
                className="w-full outline-none font-montserrat"
                style={inputStyle}
              />
            </div>

            <div className="mb-6">
              <label
                className="block text-sm font-extrabold uppercase tracking-widest mb-2"
                style={labelStyle}
              >
                Heslo
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                placeholder="••••••••"
                autoComplete="current-password"
                className="w-full outline-none font-montserrat"
                style={inputStyle}
              />
            </div>

            {error && (
              <div
                className="mb-4 text-center text-sm font-bold"
                style={{ padding: '10px 16px', borderRadius: 14, background: '#fee2e2', color: '#991b1b' }}
              >
                {error}
              </div>
            )}

            <Button
              green
              type="submit"
              disabled={loading}
              style={{ width: '100%', justifyContent: 'center', padding: '14px 22px', fontSize: 14 }}
            >
              {loading ? 'Přihlašování...' : 'Přihlásit se'}
            </Button>

            <p className="text-center mt-5">
              <button
                type="button"
                onClick={() => goTo('forgot')}
                className="text-sm font-bold underline"
                style={{ color: '#1a2e22', background: 'none', border: 'none', cursor: 'pointer' }}
              >
                Zapomenuté heslo?
              </button>
            </p>
          </form>
        )}

        {mode === 'forgot' && (
          <form onSubmit={handleForgot}>
            <p className="text-sm mb-5 text-center" style={{ color: '#1a2e22' }}>
              Zadejte e-mail svého účtu. Pošleme vám 8-znakový ověřovací kód pro nastavení nového hesla.
            </p>

            <div className="mb-6">
              <label
                className="block text-sm font-extrabold uppercase tracking-widest mb-2"
                style={labelStyle}
              >
                E-mail
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                placeholder="admin@motogo24.cz"
                autoComplete="email"
                className="w-full outline-none font-montserrat"
                style={inputStyle}
              />
            </div>

            {error && (
              <div
                className="mb-4 text-center text-sm font-bold"
                style={{ padding: '10px 16px', borderRadius: 14, background: '#fee2e2', color: '#991b1b' }}
              >
                {error}
              </div>
            )}

            <Button
              green
              type="submit"
              disabled={loading}
              style={{ width: '100%', justifyContent: 'center', padding: '14px 22px', fontSize: 14 }}
            >
              {loading ? 'Odesílám...' : 'Odeslat ověřovací kód'}
            </Button>

            <p className="text-center mt-5">
              <button
                type="button"
                onClick={() => goTo('login')}
                className="text-sm font-bold underline"
                style={{ color: '#1a2e22', background: 'none', border: 'none', cursor: 'pointer' }}
              >
                ← Zpět na přihlášení
              </button>
            </p>
          </form>
        )}

        {mode === 'reset' && (
          <form onSubmit={handleReset}>
            {info && (
              <div
                className="mb-5 text-center text-sm font-bold"
                style={{ padding: '10px 16px', borderRadius: 14, background: '#dcfce7', color: '#166534' }}
              >
                {info}
              </div>
            )}

            <div className="mb-4">
              <label
                className="block text-sm font-extrabold uppercase tracking-widest mb-2"
                style={labelStyle}
              >
                Ověřovací kód
              </label>
              <input
                type="text"
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\s+/g, '').toUpperCase())}
                required
                placeholder="XXXXXXXX"
                autoComplete="one-time-code"
                maxLength={10}
                className="w-full outline-none font-montserrat text-center tracking-widest"
                style={{ ...inputStyle, letterSpacing: 4, fontWeight: 700 }}
              />
            </div>

            <div className="mb-4">
              <label
                className="block text-sm font-extrabold uppercase tracking-widest mb-2"
                style={labelStyle}
              >
                Nové heslo
              </label>
              <input
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                required
                placeholder="Min. 8 znaků"
                autoComplete="new-password"
                minLength={8}
                className="w-full outline-none font-montserrat"
                style={inputStyle}
              />
            </div>

            <div className="mb-6">
              <label
                className="block text-sm font-extrabold uppercase tracking-widest mb-2"
                style={labelStyle}
              >
                Nové heslo znovu
              </label>
              <input
                type="password"
                value={newPassword2}
                onChange={(e) => setNewPassword2(e.target.value)}
                required
                placeholder="Zopakujte heslo"
                autoComplete="new-password"
                minLength={8}
                className="w-full outline-none font-montserrat"
                style={inputStyle}
              />
            </div>

            {error && (
              <div
                className="mb-4 text-center text-sm font-bold"
                style={{ padding: '10px 16px', borderRadius: 14, background: '#fee2e2', color: '#991b1b' }}
              >
                {error}
              </div>
            )}

            <Button
              green
              type="submit"
              disabled={loading}
              style={{ width: '100%', justifyContent: 'center', padding: '14px 22px', fontSize: 14 }}
            >
              {loading ? 'Nastavuji...' : 'Nastavit heslo a přihlásit'}
            </Button>

            <p className="text-center mt-5">
              <button
                type="button"
                onClick={() => goTo('forgot')}
                className="text-sm font-bold underline"
                style={{ color: '#1a2e22', background: 'none', border: 'none', cursor: 'pointer' }}
              >
                ← Poslat kód znovu
              </button>
            </p>
          </form>
        )}
      </div>
    </div>
  )
}
