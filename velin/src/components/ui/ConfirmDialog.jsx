import Button from './Button'

export default function ConfirmDialog({ open, title, message, onConfirm, onCancel, danger = false }) {
  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center"
      style={{ background: 'rgba(15,26,20,.45)' }}
      onClick={onCancel}
    >
      <div
        className="bg-white rounded-card shadow-card"
        style={{ padding: 28, width: 420, maxWidth: '95vw' }}
        onClick={e => e.stopPropagation()}
      >
        <h3
          className="font-extrabold uppercase tracking-wide mb-2"
          style={{ fontSize: 14, color: danger ? '#dc2626' : '#0f1a14' }}
        >
          {title}
        </h3>
        <p className="mb-6" style={{ fontSize: 13, color: '#4a6357', lineHeight: 1.6 }}>
          {message}
        </p>
        <div className="flex gap-3 justify-end">
          <Button onClick={onCancel}>Zrušit</Button>
          <Button
            onClick={onConfirm}
            style={danger ? {
              background: '#dc2626',
              color: '#fff',
              boxShadow: '0 4px 16px rgba(220,38,38,.25)',
            } : undefined}
            green={!danger}
          >
            Potvrdit
          </Button>
        </div>
      </div>
    </div>
  )
}
