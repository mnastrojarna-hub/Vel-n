import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }

export default function MessageTemplatesTab({ channel }) {
  const [templates, setTemplates] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showEdit, setShowEdit] = useState(false)
  const [editing, setEditing] = useState(null)

  // Form
  const [formName, setFormName] = useState('')
  const [formSubject, setFormSubject] = useState('')
  const [formContent, setFormContent] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => { load() }, [channel, search])

  async function load() {
    setLoading(true)
    try {
      let query = supabase
        .from('message_templates')
        .select('*')
        .order('name')

      if (search) {
        query = query.or(`name.ilike.%${search}%,content.ilike.%${search}%`)
      }

      const { data, error } = await debugAction('templates.load', 'MessageTemplatesTab', () => query)
      if (error) throw error
      setTemplates(data || [])
    } catch {
      setTemplates([])
    }
    setLoading(false)
  }

  function openNew() {
    setEditing(null)
    setFormName('')
    setFormSubject('')
    setFormContent('')
    setShowEdit(true)
  }

  function openEdit(tpl) {
    setEditing(tpl)
    setFormName(tpl.name || '')
    setFormSubject(tpl.subject || '')
    setFormContent(tpl.content || '')
    setShowEdit(true)
  }

  async function handleSave() {
    if (!formName.trim() || !formContent.trim()) return
    setSaving(true)
    try {
      const payload = {
        name: formName.trim(),
        subject: formSubject || null,
        content: formContent.trim(),
        channel,
      }

      if (editing) {
        await debugAction('templates.update', 'MessageTemplatesTab', () =>
          supabase.from('message_templates').update(payload).eq('id', editing.id)
        , { id: editing.id, ...payload })
      } else {
        await debugAction('templates.insert', 'MessageTemplatesTab', () =>
          supabase.from('message_templates').insert(payload)
        , payload)
      }

      setShowEdit(false)
      load()
    } catch {}
    setSaving(false)
  }

  async function handleDelete(tpl) {
    if (!confirm(`Smazat šablonu "${tpl.name}"?`)) return
    await debugAction('templates.delete', 'MessageTemplatesTab', () =>
      supabase.from('message_templates').delete().eq('id', tpl.id)
    , { id: tpl.id })
    load()
  }

  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
          {CHANNEL_LABELS[channel]} Šablony
        </h2>
        <div className="flex items-center gap-3">
          <SearchInput value={search} onChange={setSearch} placeholder="Hledat šablonu…" />
          <Button green onClick={openNew}>+ Nová šablona</Button>
        </div>
      </div>

      {loading && templates.length === 0 ? (
        <div className="flex justify-center py-8">
          <div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" />
        </div>
      ) : templates.length === 0 ? (
        <div className="text-center py-8" style={{ color: '#1a2e22', fontSize: 13 }}>
          Žádné {CHANNEL_LABELS[channel]} šablony
        </div>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Název</TH>
              {channel === 'email' && <TH>Předmět</TH>}
              <TH>Obsah</TH>
              <TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {templates.map(tpl => (
              <TRow key={tpl.id}>
                <TD bold>{tpl.name}</TD>
                {channel === 'email' && <TD>{tpl.subject || '—'}</TD>}
                <TD>
                  <div style={{ maxWidth: 400, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {tpl.content}
                  </div>
                </TD>
                <TD>
                  <div className="flex gap-2">
                    <button
                      onClick={() => openEdit(tpl)}
                      className="text-sm font-bold cursor-pointer border-none rounded-btn"
                      style={{ padding: '4px 10px', background: '#f1faf7', color: '#1a2e22' }}
                    >
                      Upravit
                    </button>
                    <button
                      onClick={() => handleDelete(tpl)}
                      className="text-sm font-bold cursor-pointer border-none rounded-btn"
                      style={{ padding: '4px 10px', background: '#fee2e2', color: '#991b1b' }}
                    >
                      Smazat
                    </button>
                  </div>
                </TD>
              </TRow>
            ))}
          </tbody>
        </Table>
      )}

      {/* Edit/New modal */}
      <Modal open={showEdit} title={editing ? 'Upravit šablonu' : `Nová ${CHANNEL_LABELS[channel]} šablona`} onClose={() => setShowEdit(false)}>
        <div className="space-y-3">
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              Název šablony
            </label>
            <input
              type="text"
              value={formName}
              onChange={e => setFormName(e.target.value)}
              placeholder="Název…"
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
            />
          </div>

          {channel === 'email' && (
            <div>
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                Předmět (volitelné)
              </label>
              <input
                type="text"
                value={formSubject}
                onChange={e => setFormSubject(e.target.value)}
                placeholder="Předmět e-mailu…"
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
              />
            </div>
          )}

          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              Obsah šablony
            </label>
            <textarea
              value={formContent}
              onChange={e => setFormContent(e.target.value)}
              placeholder="Text šablony… Můžete použít {{jmeno}}, {{email}} jako proměnné."
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 140, resize: 'vertical' }}
            />
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <Button onClick={() => setShowEdit(false)}>Zrušit</Button>
            <Button green onClick={handleSave} disabled={saving || !formName.trim() || !formContent.trim()}>
              {saving ? 'Ukládám…' : editing ? 'Uložit' : 'Vytvořit'}
            </Button>
          </div>
        </div>
      </Modal>
    </Card>
  )
}
