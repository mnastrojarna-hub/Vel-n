export const PER_PAGE = 25
export const LS_KEY = 'velin_received_invoices_filters'

export const STATUS_MAP = {
  draft: { label: 'Koncept', color: '#1a2e22', bg: '#f3f4f6' },
  issued: { label: 'Přijata', color: '#b45309', bg: '#fef3c7' },
  paid: { label: 'Zaplacena', color: '#1a8a18', bg: '#dcfce7' },
  cancelled: { label: 'Stornována', color: '#dc2626', bg: '#fee2e2' },
}

export const STATUS_OPTIONS = [
  { value: 'issued', label: 'Přijata' },
  { value: 'paid', label: 'Zaplacena' },
  { value: 'cancelled', label: 'Stornována' },
]

export const FLEXI_STATUS_MAP = {
  pending: { label: 'OCR čeká', color: '#6b7280', bg: '#f3f4f6' },
  enriched: { label: 'Ke klasifikaci', color: '#b45309', bg: '#fef3c7' },
  validated: { label: 'Připraven', color: '#2563eb', bg: '#dbeafe' },
  exported: { label: 'Odesláno', color: '#7c3aed', bg: '#ede9fe' },
  approved: { label: 'Schváleno', color: '#1a8a18', bg: '#dcfce7' },
  submitted: { label: 'Odesláno FÚ', color: '#059669', bg: '#d1fae5' },
  error: { label: 'Chyba', color: '#dc2626', bg: '#fee2e2' },
}

export const CATEGORY_LABELS = {
  phm: 'PHM', pojisteni: 'Pojištění', servis_opravy: 'Servis/Opravy',
  najem: 'Nájem', energie: 'Energie', telekomunikace: 'Telekomunikace',
  marketing: 'Marketing', kancelar: 'Kancelář', mzdy: 'Mzdy',
  dane_odvody: 'Daně/Odvody', ostatni_naklady: 'Ostatní',
}
