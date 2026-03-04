import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'

import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'

export default function TemplatesTab() {
  const [templates, setTemplates] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [editing, setEditing] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const { data, error: err } = await supabase
      .from('document_templates')
      .select('*')
      .order('name')
    if (err) setError(err.message)
    else setTemplates(data || [])
    setLoading(false)
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (error) return <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>

  return (
    <div>
      {templates.length === 0 ? (
        <Card><p style={{ color: '#8aab99', fontSize: 13 }}>Žádné šablony</p></Card>
      ) : (
        <div className="grid grid-cols-2 gap-4">
          {templates.map(t => (
            <Card key={t.id}>
              <div className="flex items-center justify-between mb-2">
                <h4 className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{t.name}</h4>
                <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>{t.type}</span>
              </div>
              <p className="text-xs mb-3" style={{ color: '#4a6357', lineHeight: 1.5 }}>
                {t.description || 'Bez popisu'}
              </p>
              <div className="flex items-center gap-2">
                <span className="text-[10px]" style={{ color: '#8aab99' }}>
                  Proměnné: {extractVars(t.content).join(', ') || '—'}
                </span>
                <Button onClick={() => setEditing(t)} className="ml-auto" style={{ padding: '4px 14px', fontSize: 10 }}>
                  Upravit
                </Button>
              </div>
            </Card>
          ))}
        </div>
      )}

      {editing && (
        <EditTemplateModal
          template={editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load() }}
        />
      )}
    </div>
  )
}

function extractVars(content) {
  if (!content) return []
  const matches = content.match(/\{\{(\w+)\}\}/g)
  return matches ? [...new Set(matches.map(m => m.replace(/[{}]/g, '')))] : []
}

function EditTemplateModal({ template, onClose, onSaved }) {
  const [name, setName] = useState(template.name || '')
  const [content, setContent] = useState(template.content || '')
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase
        .from('document_templates')
        .update({ name, content })
        .eq('id', template.id)
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'template_updated', details: { template_id: template.id },
      })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={`Upravit šablonu: ${template.name}`} onClose={onClose} wide>
      <div className="space-y-3">
        <div>
          <Label>Název</Label>
          <input type="text" value={name} onChange={e => setName(e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>
        <div>
          <Label>Obsah šablony</Label>
          <textarea value={content} onChange={e => setContent(e.target.value)}
            className="w-full rounded-btn text-sm outline-none font-mono"
            style={{ padding: '12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 300, resize: 'vertical' }} />
        </div>
        <p className="text-[10px]" style={{ color: '#8aab99' }}>
          Proměnné: {'{{customer_name}}, {{moto_model}}, {{start_date}}, {{end_date}}, {{total_price}}'}
        </p>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}

function Label({ children }) {
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
