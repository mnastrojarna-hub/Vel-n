import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'

const FIELDS = [
  { key: 'company_name', label: 'Název firmy' },
  { key: 'company_ico', label: 'IČO' },
  { key: 'company_dic', label: 'DIČ' },
  { key: 'company_address', label: 'Sídlo' },
]

export default function CompanyTab() {
  const [values, setValues] = useState({})
  const [loaded, setLoaded] = useState(false)
  const [saving, setSaving] = useState(false)

  useEffect(() => { load() }, [])

  async function load() {
    const { data } = await supabase
      .from('cms_variables')
      .select('key, value')
      .in('key', FIELDS.map(f => f.key))
    const map = {}
    ;(data || []).forEach(d => { map[d.key] = d.value || '' })
    setValues(map)
    setLoaded(true)
  }

  async function save() {
    setSaving(true)
    for (const field of FIELDS) {
      const { data: existing } = await supabase.from('cms_variables').select('id').eq('key', field.key).single()
      if (existing) {
        await supabase.from('cms_variables').update({ value: values[field.key] || '' }).eq('id', existing.id)
      } else {
        await supabase.from('cms_variables').insert({ key: field.key, value: values[field.key] || '', group: 'general' })
      }
    }
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'company_info_updated', details: values })
    setSaving(false)
  }

  if (!loaded) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <div className="max-w-lg">
      <Card>
        <div className="text-sm font-bold mb-4" style={{ color: '#0f1a14' }}>Firemní údaje</div>
        <div className="space-y-3">
          {FIELDS.map(f => (
            <div key={f.key}>
              <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{f.label}</label>
              <input value={values[f.key] || ''} onChange={e => setValues(v => ({ ...v, [f.key]: e.target.value }))}
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            </div>
          ))}
        </div>
        <div className="mt-5">
          <Button green onClick={save} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit údaje'}</Button>
        </div>
      </Card>
    </div>
  )
}
