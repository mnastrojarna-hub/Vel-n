import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { fetchVelinAccounts } from '../../hooks/useAdminIdentity'

// Sdílené části servisních formulářů (ServiceLogModal, ServiceLogCard).
export const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }
export function Label({ children, hint }) {
  return (
    <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
      {children}{hint && <span className="ml-2 normal-case font-medium" style={{ color: '#6b7280', fontSize: 11 }}>{hint}</span>}
    </label>
  )
}
export function Field({ label, hint, children, className = '' }) {
  return <div className={className}><Label hint={hint}>{label}</Label>{children}</div>
}

/**
 * Technik: výchozí = přihlášený účet (login), nebo jiný účet Velína, nebo zaměstnanec / externí jméno.
 * value = { technician_admin_id, technician_id, performed_by }
 */
export function TechnicianSelect({ value, onChange, me }) {
  const [accounts, setAccounts] = useState([])
  const [employees, setEmployees] = useState([])
  useEffect(() => {
    fetchVelinAccounts().then(setAccounts)
    supabase.from('acc_employees').select('id, name, position, hourly_rate').order('name').then(({ data }) => setEmployees(data || []))
  }, [])
  const mode = value.technician_admin_id ? `a:${value.technician_admin_id}` : value.technician_id ? `e:${value.technician_id}` : value.performed_by ? 'ext' : 'me'
  function select(v) {
    if (v === 'me') onChange({ technician_admin_id: me?.id || null, technician_id: null, performed_by: me?.name || '' })
    else if (v === 'ext') onChange({ technician_admin_id: null, technician_id: null, performed_by: value.performed_by || '' })
    else if (v.startsWith('a:')) { const a = accounts.find(x => x.id === v.slice(2)); onChange({ technician_admin_id: a?.id || null, technician_id: null, performed_by: a?.label || '' }) }
    else if (v.startsWith('e:')) { const e = employees.find(x => x.id === v.slice(2)); onChange({ technician_admin_id: null, technician_id: e?.id || null, performed_by: e?.name || '' }) }
  }
  const selectedEmp = employees.find(e => e.id === value.technician_id)
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <select value={mode === 'me' && !value.performed_by && !me ? 'ext' : mode} onChange={e => select(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
        <option value="me">Já — {me?.name || 'přihlášený účet'} (automaticky)</option>
        {accounts.filter(a => a.id !== me?.id).map(a => <option key={a.id} value={`a:${a.id}`}>{a.label} — účet Velína</option>)}
        {employees.map(e => <option key={e.id} value={`e:${e.id}`}>{e.name}{e.position ? ` (${e.position})` : ''} — zaměstnanec</option>)}
        <option value="ext">Externí technik (jméno)…</option>
      </select>
      {mode === 'ext' ? (
        <input type="text" value={value.performed_by || ''} onChange={e => onChange({ ...value, performed_by: e.target.value })} placeholder="Jméno / firma technika" className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
      ) : (
        <div className="text-xs flex items-center" style={{ color: '#6b7280' }}>
          {selectedEmp ? `Sazba ${selectedEmp.hourly_rate || 500} Kč/h` : 'Jméno se zapíše automaticky podle přihlášení; při dokončení servisu se doplní, kdo ho dokončil.'}
        </div>
      )}
    </div>
  )
}

/** Náklady: hodiny × sazba + extra, nebo ruční celkem; + součet nahraných faktur. */
export function CostFields({ form, set, hourlyRate = 500, invoiced = 0 }) {
  const labor = (Number(form.labor_hours) || 0) * hourlyRate
  const extra = Number(form.extra_cost) || 0
  const calc = labor + extra
  return (
    <div>
      <div className="grid grid-cols-3 gap-3">
        <div><div className="text-xs font-bold mb-1" style={{ color: '#6b7280' }}>Hodiny práce</div><input type="number" step="0.5" min="0" value={form.labor_hours ?? ''} onChange={e => set('labor_hours', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="0" /></div>
        <div><div className="text-xs font-bold mb-1" style={{ color: '#6b7280' }}>Díly / extra (Kč)</div><input type="number" min="0" value={form.extra_cost ?? ''} onChange={e => set('extra_cost', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="0" /></div>
        <div><div className="text-xs font-bold mb-1" style={{ color: '#6b7280' }}>Celkem (Kč)</div><input type="number" min="0" value={form.cost ?? ''} onChange={e => set('cost', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, background: form.cost ? '#fff' : '#f1faf7' }} placeholder={calc ? String(calc) : (invoiced ? String(invoiced) : '0')} /></div>
      </div>
      <div className="text-xs mt-1" style={{ color: '#9ca3af' }}>
        {calc > 0 && !form.cost ? `Kalkulace: ${labor > 0 ? `${Number(form.labor_hours)} h × ${hourlyRate} Kč` : ''}${labor > 0 && extra > 0 ? ' + ' : ''}${extra > 0 ? `${extra} Kč díly` : ''} = ${calc} Kč. ` : ''}
        {invoiced > 0 ? `Nahrané faktury: ${Number(invoiced).toLocaleString('cs-CZ')} Kč. ` : ''}
        Celkem nechte prázdné pro automatický výpočet.
      </div>
    </div>
  )
}

export const STATUS_OPTIONS = [
  { value: 'pending', label: 'Naplánovaný (motorka jezdí dál do dne servisu)' },
  { value: 'in_service', label: 'V servisu (motorka vyřazená z půjčování)' },
  { value: 'completed', label: 'Dokončeno (zápis do servisní knížky)' },
]
export const SERVICE_TYPE_OPTIONS = [
  { value: 'regular', label: 'Pravidelný servis' }, { value: 'extraordinary', label: 'Mimořádný servis' },
  { value: 'repair', label: 'Oprava' }, { value: 'inspection', label: 'Inspekce / kontrola (neblokuje rezervace)' },
]
