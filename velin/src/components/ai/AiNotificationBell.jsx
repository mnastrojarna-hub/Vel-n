// AI Notification Bell — shows in header, opens dropdown with agent findings
import { useState, useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { getNotifications, getUnreadCount, markRead, markAllRead, NOTIF_SEVERITY } from '../../lib/aiNotifications'

export default function AiNotificationBell() {
  const [open, setOpen] = useState(false)
  const [notifs, setNotifs] = useState([])
  const [unread, setUnread] = useState(0)
  const ref = useRef(null)
  const navigate = useNavigate()

  useEffect(() => {
    const refresh = () => { setNotifs(getNotifications()); setUnread(getUnreadCount()) }
    refresh()
    const interval = setInterval(refresh, 5000)
    return () => clearInterval(interval)
  }, [])

  // Close on click outside
  useEffect(() => {
    if (!open) return
    const handler = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false) }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [open])

  function handleClick(notif) {
    markRead(notif.id)
    setNotifs(getNotifications())
    setUnread(getUnreadCount())
    if (notif.link?.path) {
      navigate(notif.link.path)
      setOpen(false)
    }
  }

  function handleMarkAll() {
    markAllRead()
    setNotifs(getNotifications())
    setUnread(0)
  }

  return (
    <div ref={ref} style={{ position: 'relative' }}>
      {/* Bell button */}
      <button onClick={() => setOpen(!open)} style={{
        background: 'none', border: 'none', cursor: 'pointer', position: 'relative',
        fontSize: 18, padding: '4px 8px', borderRadius: 8,
        color: unread > 0 ? '#dc2626' : '#666',
      }}>
        🔔
        {unread > 0 && (
          <span style={{
            position: 'absolute', top: 0, right: 0, minWidth: 16, height: 16,
            borderRadius: 8, background: '#dc2626', color: '#fff',
            fontSize: 9, fontWeight: 800, display: 'flex', alignItems: 'center', justifyContent: 'center',
            padding: '0 3px',
          }}>{unread > 99 ? '99+' : unread}</span>
        )}
      </button>

      {/* Dropdown */}
      {open && (
        <div style={{
          position: 'absolute', top: '100%', right: 0, width: 380, maxHeight: 500,
          background: '#fff', borderRadius: 12, boxShadow: '0 8px 30px rgba(0,0,0,0.15)',
          border: '1px solid #d4e8e0', zIndex: 9999, overflow: 'hidden',
          display: 'flex', flexDirection: 'column',
        }}>
          {/* Header */}
          <div style={{
            padding: '10px 14px', borderBottom: '1px solid #d4e8e0',
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          }}>
            <span style={{ fontWeight: 800, fontSize: 13, color: '#0f1a14' }}>
              Upozornění od agentů ({unread} nepřečtených)
            </span>
            {unread > 0 && (
              <button onClick={handleMarkAll} style={{
                fontSize: 10, color: '#2563eb', background: 'none', border: 'none', cursor: 'pointer',
              }}>Označit vše</button>
            )}
          </div>

          {/* List */}
          <div style={{ flex: 1, overflow: 'auto', maxHeight: 420 }}>
            {notifs.length === 0 ? (
              <div style={{ textAlign: 'center', padding: 30, color: '#999', fontSize: 12 }}>
                Žádná upozornění
              </div>
            ) : notifs.slice(0, 50).map(n => {
              const sev = NOTIF_SEVERITY[n.severity] || NOTIF_SEVERITY.info
              return (
                <div key={n.id} onClick={() => handleClick(n)} style={{
                  padding: '8px 14px', cursor: 'pointer', borderBottom: '1px solid #f1f5f9',
                  background: n.read ? '#fff' : sev.bg,
                  opacity: n.read ? 0.6 : 1,
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 2 }}>
                    <span style={{ fontSize: 14 }}>{n.agentIcon || '🤖'}</span>
                    <span style={{
                      fontSize: 9, padding: '1px 5px', borderRadius: 4, fontWeight: 700,
                      background: sev.color, color: '#fff',
                    }}>{sev.label}</span>
                    <span style={{ fontSize: 11, fontWeight: 700, color: '#0f1a14', flex: 1 }}>{n.title}</span>
                    {!n.read && <span style={{ width: 6, height: 6, borderRadius: 3, background: sev.color }} />}
                  </div>
                  {n.detail && <div style={{ fontSize: 10, color: '#666', marginLeft: 22 }}>{n.detail}</div>}
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 2, marginLeft: 22 }}>
                    <span style={{ fontSize: 9, color: '#999' }}>
                      {n.createdAt ? new Date(n.createdAt).toLocaleString('cs-CZ', { hour: '2-digit', minute: '2-digit', day: 'numeric', month: 'numeric' }) : ''}
                    </span>
                    {n.link && (
                      <span style={{ fontSize: 9, color: '#2563eb' }}>
                        Otevřít: {n.link.label}
                      </span>
                    )}
                  </div>
                </div>
              )
            })}
          </div>

          {/* Footer */}
          <div style={{ padding: '8px 14px', borderTop: '1px solid #d4e8e0', textAlign: 'center' }}>
            <button onClick={() => { setOpen(false); navigate('/orchestrator') }} style={{
              fontSize: 11, color: '#2563eb', background: 'none', border: 'none', cursor: 'pointer',
            }}>Všechny nálezy v AI Řediteli</button>
          </div>
        </div>
      )}
    </div>
  )
}
