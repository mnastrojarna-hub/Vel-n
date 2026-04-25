import Badge from './Badge'
import { useLang } from '../../i18n/LanguageProvider'

const STATUS_STYLE = {
  active:          { key: 'status.active',         color: '#1a8a18', bg: '#dcfce7' },
  maintenance:     { key: 'status.maintenance',    color: '#b45309', bg: '#fef3c7' },
  unavailable:     { key: 'status.unavailable',    color: '#7c3aed', bg: '#ede9fe' },
  retired:         { key: 'status.retired',        color: '#1a2e22', bg: '#f3f4f6' },
  pending:         { key: 'status.pendingPayment', color: '#b45309', bg: '#fef3c7' },
  upcoming:        { key: 'status.upcoming',       color: '#7c3aed', bg: '#ede9fe' },
  reserved:        { key: 'status.reserved',       color: '#7c3aed', bg: '#ede9fe' },
  completed:       { key: 'status.completed',      color: '#1a2e22', bg: '#f3f4f6' },
  completed_sos:   { key: 'status.completedSos',   color: '#b91c1c', bg: '#fee2e2' },
  cancelled:       { key: 'status.cancelled',      color: '#dc2626', bg: '#fee2e2' },
  pending_service: { key: 'status.pendingService', color: '#6366f1', bg: '#eef2ff' },
  in_service:      { key: 'status.inService',      color: '#2563eb', bg: '#dbeafe' },
  out_of_service:  { key: 'status.unavailable',    color: '#7c3aed', bg: '#ede9fe' },
}

export function getDisplayStatus(booking) {
  if (!booking) return booking?.status || 'pending'
  // SOS-ended bookings
  if (booking.status === 'completed' && booking.ended_by_sos) return 'completed_sos'
  if ((booking.status === 'active' || booking.status === 'reserved') && booking.start_date) {
    const now = new Date()
    const todayLocal = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const start = new Date(booking.start_date)
    const startLocal = new Date(start.getFullYear(), start.getMonth(), start.getDate())
    const end = booking.end_date ? new Date(booking.end_date) : null
    const endLocal = end ? new Date(end.getFullYear(), end.getMonth(), end.getDate()) : null
    // end_date < today → expired, show as completed
    if (endLocal && endLocal < todayLocal) return 'completed'
    if (startLocal > todayLocal) return 'upcoming'
  }
  return booking.status
}

export default function StatusBadge({ status }) {
  const { t } = useLang()
  const s = STATUS_STYLE[status]
  if (!s) return <Badge label={status} color="#1a2e22" bg="#f3f4f6" />
  return <Badge label={t(s.key)} color={s.color} bg={s.bg} />
}
