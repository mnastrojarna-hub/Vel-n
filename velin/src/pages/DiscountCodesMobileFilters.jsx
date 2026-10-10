import { useState } from 'react'
import { useMediaQuery } from '../hooks/useIsMobile'

// Slevové kódy (Promo kódy / Dárkové poukazy) — filtry na telefonu (< 768 px) schované
// pod tlačítkem „Filtry (n)“, jinak by zabraly celou obrazovku nad seznamem.
// Tablet a PC: děti se vykreslí přímo (stejné DOM jako dřív), tlačítko neexistuje.
export default function DiscountCodesMobileFilters({ active = 0, children }) {
  const isPhone = useMediaQuery('(max-width: 767px)')
  const [open, setOpen] = useState(false)
  if (!isPhone) return <>{children}</>
  return (
    <>
      <button type="button" onClick={() => setOpen(o => !o)} aria-expanded={open}
        className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
        style={{ padding: '8px 14px', minHeight: 40, background: active > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
        Filtry{active > 0 ? ` (${active})` : ''} {open ? '▴' : '▾'}
      </button>
      {open && children}
    </>
  )
}
