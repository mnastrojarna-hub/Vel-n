import { TYPE_LABELS, TYPE_ICONS, SEVERITY_MAP, STATUS_COLORS } from '../SOSPanel'

export { TYPE_LABELS, TYPE_ICONS, SEVERITY_MAP, STATUS_COLORS }

export const DECISION_LABELS = {
  replacement_moto: '🏍️ Chce náhradní motorku',
  end_ride: '🚛 Ukončuje jízdu (odtah)',
  continue: '✅ Pokračuje v jízdě',
  waiting: '⏳ Čeká na rozhodnutí',
}

export const REPLACEMENT_STATUS_LABELS = {
  selecting: 'Zákazník vybírá motorku',
  pending_payment: 'Čeká na platbu',
  paid: 'Zaplaceno',
  admin_review: 'Čeká na schválení',
  approved: 'Schváleno – připravit přistavení',
  dispatched: 'Motorka na cestě',
  delivered: 'Doručeno zákazníkovi',
  rejected: 'Zamítnuto',
}

export const REPLACEMENT_STATUS_COLORS = {
  selecting: { bg: '#fef3c7', color: '#b45309' },
  pending_payment: { bg: '#fef3c7', color: '#b45309' },
  paid: { bg: '#dbeafe', color: '#2563eb' },
  admin_review: { bg: '#fee2e2', color: '#dc2626' },
  approved: { bg: '#dcfce7', color: '#1a8a18' },
  dispatched: { bg: '#dbeafe', color: '#2563eb' },
  delivered: { bg: '#dcfce7', color: '#1a8a18' },
  rejected: { bg: '#fee2e2', color: '#dc2626' },
}

export const DAMAGE_LABELS = {
  none: 'Žádné poškození',
  cosmetic: 'Kosmetické (škrábance, odřeniny)',
  functional: 'Funkční (ovlivňuje provoz)',
  totaled: 'Totální škoda',
}

export function WorkflowBtn({ label, icon, done, onClick }) {
  return (
    <button onClick={done ? undefined : onClick}
      className="rounded-btn text-sm font-extrabold tracking-wide cursor-pointer border-none inline-flex items-center gap-1"
      style={{
        padding: '6px 14px',
        background: done ? '#dcfce7' : '#f1faf7',
        color: done ? '#15803d' : '#1a2e22',
        border: done ? '1px solid #86efac' : '1px solid #d4e8e0',
        opacity: done ? 0.7 : 1,
        cursor: done ? 'default' : 'pointer',
      }}>
      <span>{icon}</span>
      <span>{done ? `${label} ✓` : label}</span>
    </button>
  )
}

export function InfoRow({ label, value, mono }) {
  return (
    <div className="flex items-center gap-2 mb-1">
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 55 }}>{label}</span>
      <span className={`text-sm font-medium ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value || '—'}</span>
    </div>
  )
}
