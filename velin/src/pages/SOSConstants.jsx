// SOS shared constants

export const TYPE_LABELS = {
  theft: 'Krádež motorky',
  accident_minor: 'Lehká nehoda (pojízdná)',
  accident_major: 'Závažná nehoda (nepojízdná)',
  breakdown_minor: 'Lehká porucha (pojízdná)',
  breakdown_major: 'Těžká porucha (nepojízdná)',
  defect_question: 'Dotaz na závadu',
  location_share: 'Sdílení polohy',
  other: 'Jiný problém',
  // Zpětná kompatibilita
  accident: 'Nehoda',
  breakdown: 'Porucha',
}

// Kategorie pro výrazný badge v kartě
const TYPE_CATEGORY = {
  theft:           { label: 'KRÁDEŽ',  bg: '#7f1d1d', color: '#fff' },
  accident_minor:  { label: 'NEHODA',  bg: '#fee2e2', color: '#dc2626' },
  accident_major:  { label: 'NEHODA',  bg: '#dc2626', color: '#fff' },
  accident:        { label: 'NEHODA',  bg: '#dc2626', color: '#fff' },
  breakdown_minor: { label: 'PORUCHA', bg: '#fef3c7', color: '#b45309' },
  breakdown_major: { label: 'PORUCHA', bg: '#b45309', color: '#fff' },
  breakdown:       { label: 'PORUCHA', bg: '#b45309', color: '#fff' },
  defect_question: { label: 'ZÁVADA',  bg: '#f1faf7', color: '#1a2e22' },
  location_share:  { label: 'POLOHA',  bg: '#dbeafe', color: '#2563eb' },
  other:           { label: 'JINÉ',    bg: '#f3f4f6', color: '#1a2e22' },
}

export const TYPE_ICONS = {
  theft: '🔒',
  accident_minor: '⚠️',
  accident_major: '🚨',
  breakdown_minor: '🔧',
  breakdown_major: '🛑',
  defect_question: '❓',
  location_share: '📍',
  other: '📞',
  accident: '🚨',
  breakdown: '🔧',
}

export const SEVERITY_MAP = {
  critical: { label: 'Kritické', bg: '#7f1d1d', color: '#fff', border: '#dc2626' },
  high: { label: 'Vysoká', bg: '#fee2e2', color: '#dc2626', border: '#dc2626' },
  medium: { label: 'Střední', bg: '#fef3c7', color: '#b45309', border: '#f59e0b' },
  low: { label: 'Nízká', bg: '#f1faf7', color: '#1a2e22', border: '#d4e8e0' },
}

export const STATUS_COLORS = {
  reported: { bg: '#fee2e2', color: '#dc2626', label: 'Nový' },
  acknowledged: { bg: '#fef3c7', color: '#b45309', label: 'Potvrzeno' },
  in_progress: { bg: '#dbeafe', color: '#2563eb', label: 'Řeší se' },
  resolved: { bg: '#dcfce7', color: '#1a8a18', label: 'Vyřešeno' },
  closed: { bg: '#f3f4f6', color: '#1a2e22', label: 'Uzavřeno' },
}

export const LIGHT_AUTO_ACK = ['breakdown_minor', 'defect_question', 'location_share', 'other']

export const HEAVY_TYPES = ['theft', 'accident_minor', 'accident_major', 'breakdown_major', 'accident', 'breakdown']
export const LIGHT_TYPES = ['breakdown_minor', 'defect_question', 'location_share', 'other']

export const TYPE_FILTERS = [
    { key: 'all_type', label: 'Vše', icon: '' },
    { key: 'nehody', label: 'Nehody', icon: '💥', types: ['accident_minor','accident_major','accident'] },
    { key: 'poruchy', label: 'Poruchy', icon: '🔧', types: ['breakdown_minor','breakdown_major','breakdown'] },
    { key: 'kradeze', label: 'Krádeže', icon: '🔒', types: ['theft'] },
    { key: 'ostatni', label: 'Ostatní', icon: '📞', types: ['defect_question','location_share','other'] },
  ]

  // Sub-filtry pro nehody a poruchy
export const SUB_FILTERS = {
    nehody: [
      { key: 'all', label: 'Všechny nehody' },
      { key: 'lehke', label: 'Lehké', types: ['accident_minor'] },
      { key: 'tezke', label: 'Těžké', types: ['accident_major', 'accident'] },
      { key: 'zavinene', label: 'Zaviněné', filterFn: i => i.customer_fault === true },
      { key: 'nezavinene', label: 'Bez zavinění', filterFn: i => i.customer_fault === false },
    ],
    poruchy: [
      { key: 'all', label: 'Všechny poruchy' },
      { key: 'lehke', label: 'Lehké', types: ['breakdown_minor'] },
      { key: 'tezke', label: 'Těžké', types: ['breakdown_major', 'breakdown'] },
    ],
  }
