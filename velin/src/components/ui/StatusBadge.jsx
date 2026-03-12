import Badge from './Badge'

const STATUS_MAP = {
  active: { label: 'Aktivní', color: '#1a8a18', bg: '#dcfce7' },
  upcoming: { label: 'Nadcházející', color: '#7c3aed', bg: '#ede9fe' },
  maintenance: { label: 'Servis', color: '#b45309', bg: '#fef3c7' },
  out_of_service: { label: 'Vyřazeno', color: '#dc2626', bg: '#fee2e2' },
  unavailable: { label: 'Nedostupná', color: '#7c3aed', bg: '#ede9fe' },
  retired: { label: 'Vyřazena trvale', color: '#6b7280', bg: '#f3f4f6' },
  pending: { label: 'Čekající', color: '#b45309', bg: '#fef3c7' },
  completed: { label: 'Dokončeno', color: '#6b7280', bg: '#f3f4f6' },
  cancelled: { label: 'Zrušeno', color: '#dc2626', bg: '#fee2e2' },
  reserved: { label: 'Rezervováno', color: '#2563eb', bg: '#dbeafe' },
  in_service: { label: 'V servisu', color: '#2563eb', bg: '#dbeafe' },
}

export function getDisplayStatus(booking) {
  if (!booking) return booking?.status || 'pending'
  if ((booking.status === 'active' || booking.status === 'reserved') && booking.start_date) {
    const now = new Date()
    const todayLocal = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const startLocal = new Date(booking.start_date.slice(0, 10) + 'T00:00:00')
    if (startLocal > todayLocal) return 'upcoming'
  }
  return booking.status
}

export default function StatusBadge({ status }) {
  const s = STATUS_MAP[status] || { label: status, color: '#6b7280', bg: '#f3f4f6' }
  return <Badge label={s.label} color={s.color} bg={s.bg} />
}
