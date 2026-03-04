import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { isDemoMode } from '../../lib/demoData'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'

export default function DataBoxTab() {
  const [dsId, setDsId] = useState('')
  const [saving, setSaving] = useState(false)
  const [loaded, setLoaded] = useState(false)

  useEffect(() => { load() }, [])

  async function load() {
    if (isDemoMode()) {
      setLoaded(true)
      return
    }
    const { data } = await supabase.from('cms_variables').select('value').eq('key', 'datove_schranky_id').single()
    if (data) setDsId(data.value || '')
    setLoaded(true)
  }

  async function save() {
    setSaving(true)
    const { data: existing } = await supabase.from('cms_variables').select('id').eq('key', 'datove_schranky_id').single()
    if (existing) {
      await supabase.from('cms_variables').update({ value: dsId }).eq('id', existing.id)
    } else {
      await supabase.from('cms_variables').insert({ key: 'datove_schranky_id', value: dsId, group: 'general' })
    }
    setSaving(false)
  }

  return (
    <div className="max-w-lg">
      <Card>
        <div className="text-sm font-bold mb-3" style={{ color: '#0f1a14' }}>Datová schránka</div>
        <div className="text-xs mb-4" style={{ color: '#8aab99' }}>
          Napojení na ISDS připravujeme. Zde můžete uložit ID datové schránky.
        </div>

        {loaded && (
          <div className="space-y-3">
            <div>
              <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>ID datové schránky</label>
              <input value={dsId} onChange={e => setDsId(e.target.value)}
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
                placeholder="např. abc1234" />
            </div>
            <Button green onClick={save} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
          </div>
        )}
      </Card>

      <Card>
        <div className="flex items-center gap-3 mt-2">
          <div className="w-3 h-3 rounded-full" style={{ background: '#fbbf24' }} />
          <span className="text-xs font-bold" style={{ color: '#b45309' }}>Napojení na ISDS je v přípravě</span>
        </div>
      </Card>
    </div>
  )
}
