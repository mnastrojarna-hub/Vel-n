import { Outlet } from 'react-router-dom'
import Sidebar from './Sidebar'
import Topbar from './Topbar'
import DebugPanel from './DebugPanel'

export default function Layout({ admin, onSignOut }) {
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
    </div>
  )
}
