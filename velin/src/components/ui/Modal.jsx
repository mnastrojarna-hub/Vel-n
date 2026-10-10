import { useEffect } from 'react'

// stickyHeader = na telefonu/tabletu (< 1024 px) zůstane titulek s ✕ nahoře i při posunu dlouhého obsahu
// (jen u modálů bez vlastních lepivých prvků uvnitř, jinak by je hlavička překryla). Desktop beze změny.
export default function Modal({ open, onClose, title, children, wide = false, noBackdropClose = true, stickyHeader = false }) {
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
        className="mg-modal bg-white rounded-card shadow-card relative p-4 sm:p-7"
        style={{
          width: wide ? 720 : 520,
          maxWidth: '100%',
          maxHeight: '92vh',
          overflow: 'auto',
        }}
        onClick={e => e.stopPropagation()}
      >
        <div className={`flex items-center justify-between mb-5${stickyHeader ? ' max-lg:sticky max-sm:-top-4 sm:max-lg:-top-7 max-lg:z-20 max-lg:bg-white max-lg:pb-3 max-lg:shadow-[0_1px_0_#e2ece7] max-sm:-mx-4 max-sm:px-4 max-sm:-mt-4 max-sm:pt-4 sm:max-lg:-mx-7 sm:max-lg:px-7 sm:max-lg:-mt-7 sm:max-lg:pt-7' : ''}`}>
          <h2
            className="font-extrabold uppercase tracking-wide"
            style={{ fontSize: 15, color: '#0f1a14' }}
          >
            {title}
          </h2>
          <button
            onClick={onClose}
            className="mg-modal-close cursor-pointer max-lg:shrink-0"
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
