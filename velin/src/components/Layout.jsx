import { Outlet, useLocation } from 'react-router-dom'
import Sidebar from './Sidebar'
import Topbar from './Topbar'
import DebugPanel from './DebugPanel'
import ErrorBoundary from './ErrorBoundary'

export default function Layout({ admin, onSignOut }) {
  const location = useLocation()
  return (
    <div className="flex h-screen overflow-hidden font-montserrat" style={{ background: '#dff0ec' }}>
      <Sidebar admin={admin} onSignOut={onSignOut} />
      <div className="flex-1 flex flex-col overflow-hidden">
        <Topbar />
        <div className="flex-1 overflow-y-auto p-3 md:p-6" style={{ paddingBottom: 60 }}>
          {/* Pád vykreslení stránky (nebo selhání lazy chunku) dřív odmontoval CELÝ strom
              → bílá obrazovka bez menu i chyby. Boundary drží menu a ukáže, co spadlo;
              key dle cesty = přechod na jinou stránku boundary resetuje. */}
          <ErrorBoundary key={location.pathname} scope={location.pathname}>
            <Outlet />
          </ErrorBoundary>
        </div>
      </div>
      <DebugPanel />
    </div>
  )
}
