import { useState, useEffect, useRef } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import AiNotificationBell from './ai/AiNotificationBell'
import LanguageSwitcher from './LanguageSwitcher'
import { useLang } from '../i18n/LanguageProvider'


const ROUTE_LABEL_KEYS = {
  '/': 'nav.dashboard',
  '/flotila': 'nav.fleet',
  '/rezervace': 'nav.bookings',
  '/zakaznici': 'nav.customers',
  '/finance': 'nav.finance',
  '/dokumenty': 'nav.documents',
  '/sklady': 'nav.inventory',
  '/servis': 'nav.service',
  '/zpravy': 'nav.messages',
  '/cms': 'nav.cms',
  '/analyza': 'nav.analyza',
  '/e-shop': 'nav.eshop',
  '/statni-sprava': 'nav.government',
  '/ai-copilot': 'nav.aiCopilot',
  '/sos': 'nav.sos',
  '/pobocky': 'nav.branches',
  '/slevove-kody': 'nav.discountCodes',
  '/zamestnanci': 'nav.employees',
  '/orchestrator': 'nav.orchestrator',
}

export default function Topbar() {
  const { t, lang } = useLang()
  const [time, setTime] = useState(new Date())
  const [notifs, setNotifs] = useState({ messages: 0, sos: 0, lowStock: 0, stkSoon: 0 })
  const [dropdownOpen, setDropdownOpen] = useState(false)
  const location = useLocation()
  const navigate = useNavigate()
  const dropdownRef = useRef(null)

  const localeMap = { cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', es: 'es-ES', fr: 'fr-FR', nl: 'nl-NL', pl: 'pl-PL' }
  const dateLocale = localeMap[lang] || 'cs-CZ'

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
    try {
      const [msgRes, sosRes, invRes, stkRes] = await Promise.all([
        supabase.from('messages').select('id', { count: 'exact', head: true }).is('read_at', null),
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
  const labelKey = ROUTE_LABEL_KEYS[location.pathname]
  const label = labelKey ? t(labelKey) : t('nav.dashboard')

  const notifItems = [
    notifs.sos > 0 && { icon: '🚨', text: t('topbar.activeSosCount', { count: notifs.sos }), path: '/sos', color: '#dc2626' },
    notifs.messages > 0 && { icon: '💬', text: t('topbar.unreadMessagesCount', { count: notifs.messages }), path: '/zpravy', color: '#8b5cf6' },
    notifs.lowStock > 0 && { icon: '📦', text: t('topbar.lowStockCount', { count: notifs.lowStock }), path: '/sklady', color: '#b45309' },
    notifs.stkSoon > 0 && { icon: '🔧', text: t('topbar.stkSoonCount', { count: notifs.stkSoon }), path: '/servis', color: '#b45309' },
  ].filter(Boolean)

  return (
    <div
      className="flex items-center justify-between shrink-0 bg-white"
      style={{
        padding: '12px 28px',
        height: 60,
        borderBottom: '1px solid #1a2e22',
      }}
    >
      <div className="flex items-center gap-3">
        <div className="w-8 md:hidden" />
        <h1 className="m-0 text-xl font-black" style={{ color: '#0f1a14' }}>
          {label}
        </h1>
      </div>
      <div className="flex items-center gap-3 sm:gap-5">
        <div className="text-sm font-semibold hidden lg:block" style={{ color: '#1a2e22' }}>
          {time.toLocaleDateString(dateLocale, {
            weekday: 'long',
            day: 'numeric',
            month: 'long',
            year: 'numeric',
          })}
        </div>
        <div
          className="text-sm font-extrabold hidden sm:block"
          style={{ color: '#1a8a18', letterSpacing: 1 }}
        >
          {time.toLocaleTimeString(dateLocale)}
        </div>

        {/* Language switcher — viditelně v horním menu */}
        <LanguageSwitcher />

        {/* AI Agent notifications */}
        <AiNotificationBell />

        {/* System notification bell */}
        <div className="relative" ref={dropdownRef}>
          <button
            onClick={() => setDropdownOpen(!dropdownOpen)}
            className="relative cursor-pointer bg-transparent border-none text-xl"
            style={{ lineHeight: 1 }}
            title={t('topbar.notifications')}
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
              style={{ width: 280, border: '1px solid #1a2e22' }}>
              <div className="p-3 text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', borderBottom: '1px solid #1a2e22' }}>
                {t('topbar.notifications')}
              </div>
              {notifItems.length === 0 ? (
                <div className="p-4 text-center text-sm" style={{ color: '#1a2e22' }}>{t('topbar.noNotifications')}</div>
              ) : (
                notifItems.map((n, i) => (
                  <div key={i}
                    onClick={() => { navigate(n.path); setDropdownOpen(false) }}
                    className="flex items-center gap-2 cursor-pointer transition-colors hover:bg-[#f5f5f5]"
                    style={{ padding: '10px 14px', borderBottom: '1px solid #1a2e22' }}>
                    <span className="text-base">{n.icon}</span>
                    <span className="text-sm font-bold" style={{ color: n.color }}>{n.text}</span>
                  </div>
                ))
              )}
            </div>
          )}
        </div>

        <div
          className="hidden sm:block"
          style={{
            width: 8,
            height: 8,
            borderRadius: '50%',
            background: '#74FB71',
            boxShadow: '0 0 8px #74FB71',
          }}
          title={t('topbar.online')}
        />
      </div>
    </div>
  )
}
