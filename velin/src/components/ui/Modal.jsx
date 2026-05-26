import { useEffect } from 'react'

export default function Modal({ open, onClose, title, children, wide = false, noBackdropClose = true }) {
  useEffect(() => {
    if (open) document.body.style.overflow = 'hidden'
    else document.body.style.overflow = ''
    return () => { document.body.style.overflow = '' }
  }, [open])

  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4"
      style={{ background: 'rgba(15,26,20,.45)' }}
      onClick={noBackdropClose ? undefined : onClose}
    >
      <div
        className="bg-white rounded-card shadow-card relative p-4 sm:p-7"
        style={{
          width: wide ? 720 : 520,
          maxWidth: '100%',
          maxHeight: '92vh',
          overflow: 'auto',
        }}
        onClick={e => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-5">
          <h2
            className="font-extrabold uppercase tracking-wide"
            style={{ fontSize: 15, color: '#0f1a14' }}
          >
            {title}
          </h2>
          <button
            onClick={onClose}
            className="cursor-pointer"
            style={{
              background: '#f1faf7',
              border: 'none',
              borderRadius: 50,
              width: 32,
              height: 32,
              fontSize: 18,
              color: '#1a2e22',
            }}
          >
            ✕
          </button>
        </div>
        {children}
      </div>
    </div>
  )
}
