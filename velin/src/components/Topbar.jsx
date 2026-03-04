import { useState, useEffect } from 'react'
import { useLocation } from 'react-router-dom'

const ROUTE_LABELS = {
  '/': 'Velín',
  '/flotila': 'Flotila',
  '/rezervace': 'Rezervace',
  '/zakaznici': 'Zákazníci',
  '/finance': 'Finance',
  '/ucetnictvi': 'Účetnictví',
  '/dokumenty': 'Dokumenty',
  '/sklady': 'Sklady',
  '/servis': 'Servis',
  '/zpravy': 'Zprávy',
  '/cms': 'Web CMS',
  '/statistiky': 'Statistiky',
  '/nakupy': 'Nákupy',
  '/statni-sprava': 'Státní správa',
  '/ai-copilot': 'AI Copilot',
}

export default function Topbar() {
  const [time, setTime] = useState(new Date())
  const location = useLocation()

  useEffect(() => {
    const interval = setInterval(() => setTime(new Date()), 1000)
    return () => clearInterval(interval)
  }, [])

  const label = ROUTE_LABELS[location.pathname] || 'Velín'

  return (
    <div
      className="flex items-center justify-between shrink-0 bg-white"
      style={{
        padding: '12px 28px',
        height: 60,
        borderBottom: '1px solid #d4e8e0',
      }}
    >
      <div className="flex items-center gap-3">
        {/* Spacer for mobile hamburger */}
        <div className="w-8 md:hidden" />
        <h1 className="m-0 text-xl font-black" style={{ color: '#0f1a14' }}>
          {label}
        </h1>
      </div>
      <div className="flex items-center gap-5">
        <div className="text-xs font-semibold hidden sm:block" style={{ color: '#8aab99' }}>
          {time.toLocaleDateString('cs-CZ', {
            weekday: 'long',
            day: 'numeric',
            month: 'long',
            year: 'numeric',
          })}
        </div>
        <div
          className="text-sm font-extrabold"
          style={{ color: '#1a8a18', letterSpacing: 1 }}
        >
          {time.toLocaleTimeString('cs-CZ')}
        </div>
        <div
          style={{
            width: 8,
            height: 8,
            borderRadius: '50%',
            background: '#74FB71',
            boxShadow: '0 0 8px #74FB71',
          }}
          title="Online"
        />
      </div>
    </div>
  )
}
