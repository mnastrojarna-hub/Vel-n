import { useState } from 'react'
import { supabase } from '../lib/supabase'
import Modal from '../components/ui/Modal'
import Button from '../components/ui/Button'
import { ASSIGNABLE_SECTIONS, allowedSectionIds } from '../lib/velinSections'

export const ROLE_LABELS = {
  superadmin: 'Superadmin (vše + správa uživatelů)',
  manager: 'Manažer',
  operator: 'Operátor',
  viewer: 'Prohlížeč',
}
const ROLES = ['operator', 'manager', 'viewer', 'superadmin']

/** Volání edge funkce `admin-users` (JWT přihlášeného superadmina předá SDK samo). */
export async function callAdminUsers(body) {
  const { data, error } = await supabase.functions.invoke('admin-users', { body })
  if (error) {
    // supabase-js u non-2xx vrací FunctionsHttpError s Response uvnitř — vytáhni důvod
    let detail = ''
    let code = ''
    try { const j = await error.context?.json?.(); detail = j?.error || j?.reason || ''; code = j?.code || '' } catch { /* noop */ }
    const err = new Error(detail || error.message || 'Server je nedostupný')
    err.code = code
    throw err
  }
  if (data?.error) { const err = new Error(data.error); err.code = data.code || ''; throw err }
  return data
}

const iStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }

export default function VelinUserModal({ admin, user, onClose, onSaved }) {
  const editing = !!user
  const isSelf = editing && user.id === admin?.id
  const initialSections = editing ? (allowedSectionIds(user) ?? ASSIGNABLE_SECTIONS.map(s => s.id)) : []
  const [form, setForm] = useState({
    name: user?.name || '', email: user?.email || '', phone: user?.phone || '',
    role: user?.role || 'operator', password: '', password2: '',
    sections: initialSections,
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const [pwMode, setPwMode] = useState(false) // u editace: změna hesla
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const toggleSection = (id) => setForm(f => ({
    ...f, sections: f.sections.includes(id) ? f.sections.filter(s => s !== id) : [...f.sections, id],
  }))

  async function save() {
    setErr(null)
    if (!form.name.trim()) { setErr('Vyplňte jméno'); return }
    if (!editing) {
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim())) { setErr('Zadejte platný e-mail'); return }
      if (form.password.length < 8) { setErr('Heslo musí mít alespoň 8 znaků'); return }
      if (form.password !== form.password2) { setErr('Hesla se neshodují'); return }
    } else if (pwMode) {
      if (form.password.length < 8) { setErr('Nové heslo musí mít alespoň 8 znaků'); return }
      if (form.password !== form.password2) { setErr('Hesla se neshodují'); return }
    }
    if (form.role !== 'superadmin' && form.sections.length === 0) {
      setErr('Zaškrtněte alespoň jednu sekci, kterou má uživatel vidět'); return
    }
    if (isSelf && form.role !== 'superadmin') { setErr('Sami sobě nemůžete odebrat roli superadmina'); return }
    setSaving(true)
    try {
      if (!editing) {
        const payload = {
          action: 'create', email: form.email.trim().toLowerCase(), password: form.password,
          name: form.name.trim(), phone: form.phone.trim() || null, role: form.role, sections: form.sections,
        }
        try {
          await callAdminUsers(payload)
        } catch (e) {
          // E-mail patří existujícímu zákaznickému účtu → heslo se mu přepíše jen po potvrzení
          if (e.code !== 'exists_customer') throw e
          if (!window.confirm(`${e.message}\n\nPokračovat?`)) { setSaving(false); return }
          await callAdminUsers({ ...payload, confirm_existing: true })
        }
      } else {
        await callAdminUsers({
          action: 'update', user_id: user.id, name: form.name.trim(), phone: form.phone.trim() || null,
          role: form.role, sections: form.sections,
        })
        if (pwMode) await callAdminUsers({ action: 'set_password', user_id: user.id, new_password: form.password })
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={editing ? 'Upravit uživatele Velína' : 'Nový uživatel Velína'} onClose={onClose} wide>
      {err && <div className="mb-3 p-2 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{err}</div>}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div><Lbl>Jméno</Lbl><input type="text" value={form.name} onChange={e => set('name', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} placeholder="Jan Novák" /></div>
        <div><Lbl>E-mail (přihlašovací)</Lbl><input type="email" value={form.email} disabled={editing} onChange={e => set('email', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...iStyle, opacity: editing ? 0.6 : 1 }} placeholder="servis@motogo24.cz" autoComplete="off" /></div>
        <div><Lbl>Telefon</Lbl><input type="text" value={form.phone} onChange={e => set('phone', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>Role</Lbl><select value={form.role} disabled={isSelf} onChange={e => set('role', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle}>
          {ROLES.map(r => <option key={r} value={r}>{ROLE_LABELS[r]}</option>)}
        </select></div>
        {(!editing || pwMode) && (
          <>
            <div><Lbl>{editing ? 'Nové heslo' : 'Heslo'}</Lbl><input type="password" value={form.password} onChange={e => set('password', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} placeholder="Min. 8 znaků" autoComplete="new-password" /></div>
            <div><Lbl>Heslo znovu</Lbl><input type="password" value={form.password2} onChange={e => set('password2', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} placeholder="Zopakujte heslo" autoComplete="new-password" /></div>
          </>
        )}
        {editing && !pwMode && (
          <div className="sm:col-span-2">
            <button type="button" onClick={() => setPwMode(true)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}>
              Nastavit nové heslo (uživatel si ho může změnit i sám přes „Zapomenuté heslo?“)
            </button>
          </div>
        )}
      </div>

      <div className="mt-4">
        <Lbl>Sekce Velína, které uživatel vidí</Lbl>
        {form.role === 'superadmin' ? (
          <div className="text-sm font-medium" style={{ color: '#1a2e22' }}>Superadmin vidí všechny sekce včetně správy uživatelů.</div>
        ) : (
          <>
            <div className="flex gap-3 mb-2">
              <button type="button" onClick={() => set('sections', ASSIGNABLE_SECTIONS.map(s => s.id))} className="text-xs font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}>Vybrat vše</button>
              <button type="button" onClick={() => set('sections', [])} className="text-xs font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none', padding: 0 }}>Zrušit výběr</button>
            </div>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
              {ASSIGNABLE_SECTIONS.map(s => (
                <label key={s.id} className="flex items-center gap-2 cursor-pointer rounded-btn" style={{ padding: '6px 10px', background: form.sections.includes(s.id) ? '#e2f5ec' : '#f8fcfa', border: '1px solid #d4e8e0' }}>
                  <input type="checkbox" checked={form.sections.includes(s.id)} onChange={() => toggleSection(s.id)} className="w-4 h-4 accent-green-500" />
                  <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{s.icon} {s.label}</span>
                </label>
              ))}
            </div>
          </>
        )}
      </div>

      <div className="flex justify-end gap-2 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={save} disabled={saving}>{saving ? 'Ukládám...' : (editing ? 'Uložit' : 'Založit účet')}</Button>
      </div>
    </Modal>
  )
}

function Lbl({ children }) {
  return <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</div>
}
