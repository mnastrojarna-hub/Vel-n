// Flexi pipeline status → badge mapping
export const FLEXI_STATUS_MAP = {
  pending: { label: 'OCR čeká', color: '#6b7280', bg: '#f3f4f6' },
  enriched: { label: 'Ke klasifikaci', color: '#b45309', bg: '#fef3c7' },
  validated: { label: 'Připraven', color: '#2563eb', bg: '#dbeafe' },
  exported: { label: 'Odesláno', color: '#7c3aed', bg: '#ede9fe' },
  approved: { label: 'Schváleno', color: '#1a8a18', bg: '#dcfce7' },
  submitted: { label: 'Odesláno FÚ', color: '#059669', bg: '#d1fae5' },
  error: { label: 'Chyba', color: '#dc2626', bg: '#fee2e2' },
}

// AI category → Czech label
export const CATEGORY_LABELS = {
  phm: 'PHM', pojisteni: 'Pojištění', servis_opravy: 'Servis/Opravy',
  najem: 'Nájem', energie: 'Energie', telekomunikace: 'Telekomunikace',
  marketing: 'Marketing', kancelar: 'Kancelář', mzdy: 'Mzdy',
  dane_odvody: 'Daně/Odvody', ostatni_naklady: 'Ostatní',
}

export function AIDetail({ label, value, mono }) {
  return (
    <div>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#7c3aed' }}>{label}</div>
      <div className={`text-sm font-bold ${mono ? 'font-mono' : ''}`} style={{ color: '#1a2e22' }}>{value || '\u2014'}</div>
    </div>
  )
}

export function CheckboxFilterGroup({ label, options, selected, onChange }) {
  function toggle(value) {
    if (selected.includes(value)) onChange(selected.filter(v => v !== value))
    else onChange([...selected, value])
  }
  return (
    <div className="flex flex-wrap items-center gap-3 mb-4">
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(opt => (
        <label key={opt.value} className="flex items-center gap-1.5 cursor-pointer text-sm" style={{ color: '#1a2e22' }}>
          <input type="checkbox" checked={selected.includes(opt.value)} onChange={() => toggle(opt.value)} className="cursor-pointer" style={{ accentColor: '#1a8a18' }} />
          {opt.label}
        </label>
      ))}
    </div>
  )
}
