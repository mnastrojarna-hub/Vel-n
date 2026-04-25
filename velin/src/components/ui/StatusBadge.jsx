import Badge from './Badge'

const STATUS_MAP = {
  // Moto statuses
  active: { label: 'Aktivní', color: '#1a8a18', bg: '#dcfce7' },
  maintenance: { label: 'V servisu', color: '#b45309', bg: '#fef3c7' },
  unavailable: { label: 'Dočasně vyřazena', color: '#7c3aed', bg: '#ede9fe' },
  retired: { label: 'Trvale vyřazena', color: '#1a2e22', bg: '#f3f4f6' },
  // Booking statuses
  pending: { label: 'Čeká na platbu', color: '#b45309', bg: '#fef3c7' },
  upcoming: { label: 'Nadcházející', color: '#7c3aed', bg: '#ede9fe' },
  reserved: { label: 'Nadcházející', color: '#7c3aed', bg: '#ede9fe' },
  completed: { label: 'Dokončeno', color: '#1a2e22', bg: '#f3f4f6' },
  completed_sos: { label: 'Dokončeno SOS', color: '#b91c1c', bg: '#fee2e2' },
  cancelled: { label: 'Zrušeno', color: '#dc2626', bg: '#fee2e2' },
  // Service log statuses
  pending_service: { label: 'Plánovaný', color: '#6366f1', bg: '#eef2ff' },
  in_service: { label: 'V servisu', color: '#2563eb', bg: '#dbeafe' },
  // Legacy aliases
  out_of_service: { label: 'Dočasně vyřazena', color: '#7c3aed', bg: '#ede9fe' },
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
  const s = STATUS_MAP[status] || { label: status, color: '#1a2e22', bg: '#f3f4f6' }
  return <Badge label={s.label} color={s.color} bg={s.bg} />
}
