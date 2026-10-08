import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import { useAdminIdentity } from '../../hooks/useAdminIdentity'

const inp = { padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }
const FIELDS = [['company_name', 'Firma / jméno servisu'], ['ico', 'IČO'], ['dic', 'DIČ'], ['address', 'Adresa'], ['email', 'E-mail'], ['phone', 'Telefon'], ['bank_account', 'Bankovní účet']]

/** Servis → „Moje fakturační údaje“: hlavička přihlášeného účtu (externí servis), předvyplní dodavatele u faktur k servisu. */
export default function ServiceProviderProfile() {
  const me = useAdminIdentity()
  const [form, setForm] = useState({})
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState(null)
  useEffect(() => { if (me?.id) supabase.from('service_provider_profiles').select('*').eq('admin_id', me.id).maybeSingle().then(({ data }) => setForm(data || {})) }, [me?.id])

  async function save() {
    setSaving(true); setMsg(null)
    const payload = { admin_id: me.id, updated_at: new Date().toISOString() }
    for (const [k] of FIELDS) payload[k] = (form[k] || '').trim() || null
    const { error } = await supabase.from('service_provider_profiles').upsert(payload, { onConflict: 'admin_id' })
    setSaving(false); setMsg(error ? error.message : 'Uloženo')
  }
  if (!me) return null
  return (
    <Card style={{ padding: 14 }}>
      <div className="flex items-center gap-3 flex-wrap">
        <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Přihlášen: {me.name}</span>
        <span className="text-xs" style={{ color: '#6b7280' }}>{form.company_name ? `${form.company_name}${form.ico ? ` · IČO ${form.ico}` : ''}` : 'fakturační údaje nevyplněny'}</span>
        <button onClick={() => setOpen(o => !o)} className="ml-auto text-xs font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#2563eb' }}>{open ? 'skrýt' : 'Moje fakturační údaje'}</button>
      </div>
      {open && (
        <div className="mt-3">
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-2">
            {FIELDS.map(([k, label]) => (
              <input key={k} value={form[k] || ''} onChange={e => setForm(f => ({ ...f, [k]: e.target.value }))} placeholder={label} className="rounded-btn text-sm outline-none" style={inp} />
            ))}
          </div>
          <div className="flex items-center gap-3 mt-2">
            <Button small green onClick={save} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
            {msg && <span className="text-xs" style={{ color: msg === 'Uloženo' ? '#1a8a18' : '#dc2626' }}>{msg}</span>}
            <span className="text-xs" style={{ color: '#6b7280' }}>Předvyplní dodavatele při nahrání faktury k servisu.</span>
          </div>
        </div>
      )}
    </Card>
  )
}
