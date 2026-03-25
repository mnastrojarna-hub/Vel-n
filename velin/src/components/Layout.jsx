import { useEffect } from 'react'
import { Outlet } from 'react-router-dom'
import Sidebar from './Sidebar'
import Topbar from './Topbar'
import DebugPanel from './DebugPanel'
import FloatingAiPanel from './ai/FloatingAiPanel'
import { startMonitoring } from '../lib/aiMonitoring'

export default function Layout({ admin, onSignOut }) {
  // Start AI agent monitoring (runs every 15 min)
  useEffect(() => { startMonitoring() }, [])

  return (
    <div className="flex h-screen overflow-hidden font-montserrat" style={{ background: '#dff0ec' }}>
      <Sidebar admin={admin} onSignOut={onSignOut} />
      <div className="flex-1 flex flex-col overflow-hidden">
        <Topbar />
        <div className="flex-1 overflow-y-auto" style={{ padding: 24, paddingBottom: 60 }}>
          <Outlet />
        </div>
      </div>
      <DebugPanel />
      <FloatingAiPanel />
    </div>
  )
}
