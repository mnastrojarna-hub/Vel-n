import { useState, useEffect } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { isDemoMode } from '../lib/demoData'

const NAV = [
  { id: 'dashboard', path: '/', label: 'Velín', icon: '⚡' },
  { id: 'fleet', path: '/flotila', label: 'Flotila', icon: '🏍️' },
  { id: 'bookings', path: '/rezervace', label: 'Rezervace', icon: '📅' },
  { id: 'customers', path: '/zakaznici', label: 'Zákazníci', icon: '👥' },
  { id: 'finance', path: '/finance', label: 'Finance', icon: '💰' },
  { id: 'accounting', path: '/ucetnictvi', label: 'Účetnictví', icon: '📒' },
  { id: 'documents', path: '/dokumenty', label: 'Dokumenty', icon: '📄' },
  { id: 'inventory', path: '/sklady', label: 'Sklady', icon: '📦' },
  { id: 'service', path: '/servis', label: 'Servis', icon: '🔧' },
  { id: 'messages', path: '/zpravy', label: 'Zprávy', icon: '💬', badgeKey: 'messages' },
  { id: 'cms', path: '/cms', label: 'Web CMS', icon: '🌐' },
  { id: 'stats', path: '/statistiky', label: 'Statistiky', icon: '📊' },
  { id: 'purchases', path: '/nakupy', label: 'Nákupy', icon: '🛒' },
  { id: 'government', path: '/statni-sprava', label: 'Státní správa', icon: '🏛️' },
  { id: 'ai', path: '/ai-copilot', label: 'AI Copilot', icon: '🤖' },
  { id: 'sos', path: '/sos', label: 'SOS Panel', icon: '🚨', badgeKey: 'sos' },
]

const Logo = ({ size = 44 }) => (
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

export default function Sidebar({ admin, onSignOut }) {
  const [collapsed, setCollapsed] = useState(false)
  const [mobileOpen, setMobileOpen] = useState(false)
  const [badges, setBadges] = useState({ messages: 0, sos: 0 })
  const location = useLocation()
  const navigate = useNavigate()

  useEffect(() => {
    loadBadges()
    const interval = setInterval(loadBadges, 15000)
    return () => clearInterval(interval)
  }, [])

  async function loadBadges() {
    if (isDemoMode()) { setBadges({ messages: 3, sos: 0 }); return }
    try {
      const [msgRes, sosRes] = await Promise.all([
        supabase.from('messages').select('id', { count: 'exact', head: true }).eq('read', false),
        supabase.from('sos_incidents').select('id', { count: 'exact', head: true }).in('status', ['reported', 'acknowledged']),
      ])
      setBadges({ messages: msgRes.count || 0, sos: sosRes.count || 0 })
    } catch {
      setBadges({ messages: 0, sos: 0 })
    }
  }

  const isActive = (path) => {
    if (path === '/') return location.pathname === '/'
    return location.pathname.startsWith(path)
  }

  const handleNav = (path) => {
    navigate(path)
    setMobileOpen(false)
  }

  const sidebarContent = (
    <>
      {/* Logo */}
      <div
        className="flex items-center gap-3 cursor-pointer shrink-0"
        style={{
          padding: collapsed ? '16px 8px' : '20px',
          borderBottom: '1px solid rgba(255,255,255,.08)',
        }}
        onClick={() => setCollapsed(!collapsed)}
      >
        <div className="shrink-0">
          <Logo size={collapsed ? 38 : 44} />
        </div>
        {!collapsed && (
          <div>
            <div className="text-base font-black text-white tracking-tight">MOTO GO 24</div>
            <div
              className="text-[9px] font-bold uppercase mt-0.5"
              style={{ color: 'rgba(255,255,255,.4)', letterSpacing: '3px' }}
            >
              Velín
            </div>
          </div>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto" style={{ padding: '10px 6px' }}>
        {NAV.map((item) => {
          const active = isActive(item.path)
          return (
            <button
              key={item.id}
              onClick={() => handleNav(item.path)}
              className="w-full flex items-center gap-2.5 mb-px transition-all"
              style={{
                padding: collapsed ? '9px 0' : '9px 14px',
                justifyContent: collapsed ? 'center' : 'flex-start',
                borderRadius: 14,
                border: 'none',
                cursor: 'pointer',
                fontSize: 13,
                fontWeight: active ? 800 : 600,
                background: active ? 'rgba(116,251,113,.12)' : 'transparent',
                color: active ? '#74FB71' : 'rgba(255,255,255,.5)',
                borderLeft: active ? '3px solid #74FB71' : '3px solid transparent',
                fontFamily: 'inherit',
              }}
            >
              <span className="text-base shrink-0">{item.icon}</span>
              {!collapsed && <span className="flex-1 text-left">{item.label}</span>}
              {!collapsed && item.badgeKey && badges[item.badgeKey] > 0 && (
                <span className="flex items-center justify-center shrink-0"
                  style={{
                    minWidth: 18, height: 18, borderRadius: 9,
                    background: item.badgeKey === 'sos' ? '#dc2626' : '#74FB71',
                    color: item.badgeKey === 'sos' ? '#fff' : '#1a2e22',
                    fontSize: 9, fontWeight: 800, padding: '0 5px',
                  }}>
                  {badges[item.badgeKey]}
                </span>
              )}
            </button>
          )
        })}
      </nav>

      {/* Admin profile */}
      {!collapsed && (
        <div
          className="flex items-center gap-2.5 shrink-0"
          style={{
            padding: '14px 16px',
            borderTop: '1px solid rgba(255,255,255,.08)',
          }}
        >
          <div
            className="flex items-center justify-center text-sm font-black shrink-0"
            style={{
              width: 32,
              height: 32,
              borderRadius: '50%',
              background: '#74FB71',
              color: '#1a2e22',
            }}
          >
            {admin?.name?.[0]?.toUpperCase() || 'A'}
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-xs font-bold text-white truncate">
              {admin?.name || 'Admin'}
            </div>
            <div className="text-[10px] font-medium" style={{ color: 'rgba(255,255,255,.35)' }}>
              {admin?.role || 'Správce'}
            </div>
          </div>
          <button
            onClick={onSignOut}
            className="text-[10px] font-bold uppercase opacity-40 hover:opacity-100 transition-opacity cursor-pointer bg-transparent border-none text-white"
            title="Odhlásit se"
          >
            ↗
          </button>
        </div>
      )}
    </>
  )

  return (
    <>
      {/* Mobile hamburger */}
      <button
        className="fixed top-3 left-3 z-50 md:hidden flex items-center justify-center"
        style={{
          width: 40,
          height: 40,
          borderRadius: 12,
          background: '#1a2e22',
          border: 'none',
          cursor: 'pointer',
          color: '#74FB71',
          fontSize: 20,
        }}
        onClick={() => setMobileOpen(!mobileOpen)}
      >
        {mobileOpen ? '✕' : '☰'}
      </button>

      {/* Mobile overlay */}
      {mobileOpen && (
        <div
          className="fixed inset-0 z-40 md:hidden"
          style={{ background: 'rgba(0,0,0,.5)' }}
          onClick={() => setMobileOpen(false)}
        />
      )}

      {/* Sidebar - desktop */}
      <div
        className="hidden md:flex flex-col shrink-0 transition-all"
        style={{
          width: collapsed ? 62 : 260,
          background: '#1a2e22',
          overflow: 'hidden',
        }}
      >
        {sidebarContent}
      </div>

      {/* Sidebar - mobile */}
      <div
        className={`fixed top-0 left-0 z-40 h-full flex flex-col md:hidden transition-transform ${
          mobileOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
        style={{
          width: 260,
          background: '#1a2e22',
          overflow: 'hidden',
        }}
      >
        {sidebarContent}
      </div>
    </>
  )
}
