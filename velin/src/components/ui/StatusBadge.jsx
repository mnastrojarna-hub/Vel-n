import Badge from './Badge'

const STATUS_MAP = {
  active: { label: 'Aktivní', color: '#1a8a18', bg: '#dcfce7' },
  maintenance: { label: 'Servis', color: '#b45309', bg: '#fef3c7' },
  out_of_service: { label: 'Vyřazeno', color: '#dc2626', bg: '#fee2e2' },
  pending: { label: 'Čekající', color: '#b45309', bg: '#fef3c7' },
  completed: { label: 'Dokončeno', color: '#6b7280', bg: '#f3f4f6' },
  cancelled: { label: 'Zrušeno', color: '#dc2626', bg: '#fee2e2' },
  reserved: { label: 'Nadcházející', color: '#2563eb', bg: '#dbeafe' },
  in_service: { label: 'V servisu', color: '#2563eb', bg: '#dbeafe' },
}

export default function StatusBadge({ status }) {
  const s = STATUS_MAP[status] || { label: status, color: '#6b7280', bg: '#f3f4f6' }
  return <Badge label={s.label} color={s.color} bg={s.bg} />
}
