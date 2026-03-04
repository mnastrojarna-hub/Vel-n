import { useState, useEffect, useRef } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { isDemoMode, INVENTORY, MOTOS } from '../lib/demoData'

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
  '/sos': 'SOS Panel',
}

export default function Topbar() {
  const [time, setTime] = useState(new Date())
  const [notifs, setNotifs] = useState({ messages: 0, sos: 0, lowStock: 0, stkSoon: 0 })
  const [dropdownOpen, setDropdownOpen] = useState(false)
  const location = useLocation()
  const navigate = useNavigate()
  const dropdownRef = useRef(null)

  useEffect(() => {
    const interval = setInterval(() => setTime(new Date()), 1000)
    return () => clearInterval(interval)
  }, [])

  useEffect(() => { loadNotifications() }, [])
  useEffect(() => {
    const interval = setInterval(loadNotifications, 30000)
    return () => clearInterval(interval)
  }, [])

  useEffect(() => {
    function handleClick(e) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target)) setDropdownOpen(false)
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [])

  async function loadNotifications() {
    if (isDemoMode()) {
      const lowStock = INVENTORY.filter(i => i.stock <= (i.min_stock || 0)).length
      const in30days = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)
      const stkSoon = MOTOS.filter(m => m.stk_valid_until && m.stk_valid_until <= in30days).length
      setNotifs({ messages: 3, sos: 0, lowStock, stkSoon })
      return
    }
    try {
      const [msgRes, sosRes, invRes, stkRes] = await Promise.all([
        supabase.from('messages').select('id', { count: 'exact', head: true }).eq('read', false),
        supabase.from('sos_incidents').select('id', { count: 'exact', head: true }).in('status', ['reported', 'acknowledged']),
        supabase.from('inventory').select('id, stock, min_stock'),
        supabase.from('motorcycles').select('id, stk_valid_until'),
      ])
      const lowStock = (invRes.data || []).filter(i => i.stock <= (i.min_stock || 0)).length
      const in30days = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)
      const stkSoon = (stkRes.data || []).filter(m => m.stk_valid_until && m.stk_valid_until <= in30days).length
      setNotifs({ messages: msgRes.count || 0, sos: sosRes.count || 0, lowStock, stkSoon })
    } catch {
      setNotifs({ messages: 0, sos: 0, lowStock: 0, stkSoon: 0 })
    }
  }

  const totalNotifs = notifs.messages + notifs.sos + notifs.lowStock + notifs.stkSoon
  const label = ROUTE_LABELS[location.pathname] || 'Velín'

  const notifItems = [
    notifs.sos > 0 && { icon: '🚨', text: `${notifs.sos} aktivních SOS`, path: '/sos', color: '#dc2626' },
    notifs.messages > 0 && { icon: '💬', text: `${notifs.messages} nepřečtených zpráv`, path: '/zpravy', color: '#8b5cf6' },
    notifs.lowStock > 0 && { icon: '📦', text: `${notifs.lowStock} pod minimem`, path: '/sklady', color: '#b45309' },
    notifs.stkSoon > 0 && { icon: '🏛️', text: `${notifs.stkSoon} STK brzy vyprší`, path: '/statni-sprava', color: '#b45309' },
  ].filter(Boolean)

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

        {/* Notification bell */}
        <div className="relative" ref={dropdownRef}>
          <button
            onClick={() => setDropdownOpen(!dropdownOpen)}
            className="relative cursor-pointer bg-transparent border-none text-xl"
            style={{ lineHeight: 1 }}
            title="Notifikace"
          >
            🔔
            {totalNotifs > 0 && (
              <span className="absolute -top-1 -right-1 flex items-center justify-center"
                style={{
                  minWidth: 16, height: 16, borderRadius: 8,
                  background: '#dc2626', color: '#fff',
                  fontSize: 9, fontWeight: 800, padding: '0 4px',
                }}>
                {totalNotifs}
              </span>
            )}
          </button>

          {dropdownOpen && (
            <div className="absolute right-0 top-full mt-2 z-50 rounded-card shadow-card bg-white"
              style={{ width: 280, border: '1px solid #d4e8e0' }}>
              <div className="p-3 text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99', borderBottom: '1px solid #d4e8e0' }}>
                Notifikace
              </div>
              {notifItems.length === 0 ? (
                <div className="p-4 text-center text-xs" style={{ color: '#8aab99' }}>Žádné notifikace</div>
              ) : (
                notifItems.map((n, i) => (
                  <div key={i}
                    onClick={() => { navigate(n.path); setDropdownOpen(false) }}
                    className="flex items-center gap-2 cursor-pointer transition-colors hover:bg-[#f1faf7]"
                    style={{ padding: '10px 14px', borderBottom: '1px solid #d4e8e0' }}>
                    <span className="text-base">{n.icon}</span>
                    <span className="text-xs font-bold" style={{ color: n.color }}>{n.text}</span>
                  </div>
                ))
              )}
            </div>
          )}
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
