import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugError } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'
import SearchInput from '../../components/ui/SearchInput'
import ConfirmDialog from '../../components/ui/ConfirmDialog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import TemplateEditModal from './TemplateEditModal'

const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }

const LANG_OPTIONS = [
  { value: 'cs', label: 'Čeština' },
  { value: 'en', label: 'English' },
  { value: 'de', label: 'Deutsch' },
]

export default function MessageTemplatesTab({ channel }) {
  const debugMode = useDebugMode()
  const [templates, setTemplates] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [search, setSearch] = useState('')
  const [showEdit, setShowEdit] = useState(false)
  const [editing, setEditing] = useState(null)
  const [confirm, setConfirm] = useState(null)

  useEffect(() => { load() }, [channel])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const { data, error: err } = await debugAction('templates.load', 'MessageTemplatesTab', () =>
        supabase.from('message_templates').select('*').eq('channel', channel).order('slug')
      )
      if (err) throw err
      setTemplates(data || [])
    } catch (e) {
      debugError('MessageTemplatesTab', 'load', e)
      setError(e.message)
      setTemplates([])
    }
    setLoading(false)
  }

  function openNew() { setEditing(null); setShowEdit(true) }
  function openEdit(tpl) { setEditing(tpl); setShowEdit(true) }

  async function handleDuplicate(tpl) {
    try {
      const payload = {
        slug: tpl.slug + '_copy', name: tpl.name + ' (kopie)', channel: tpl.channel,
        language: tpl.language || 'cs', body_template: tpl.body_template || tpl.content || '',
        subject_template: tpl.subject_template || tpl.subject || null, is_marketing: tpl.is_marketing || false,
        is_active: false, wa_template_id: tpl.wa_template_id || null,
      }
      const { error: err } = await debugAction('templates.duplicate', 'MessageTemplatesTab', () =>
        supabase.from('message_templates').insert(payload)
      , payload)
      if (err) throw err
      load()
    } catch (e) {
      debugError('MessageTemplatesTab', 'duplicate', e)
      window.alert('Chyba při duplikaci: ' + e.message)
    }
  }

  async function handleToggleActive(tpl) {
    try {
      const { error: err } = await debugAction('templates.toggleActive', 'MessageTemplatesTab', () =>
        supabase.from('message_templates').update({ is_active: !tpl.is_active }).eq('id', tpl.id)
      )
      if (err) throw err
      load()
    } catch (e) { debugError('MessageTemplatesTab', 'toggleActive', e) }
    setConfirm(null)
  }

  async function handleDelete(tpl) {
    try {
      const { error: err } = await debugAction('templates.delete', 'MessageTemplatesTab', () =>
        supabase.from('message_templates').delete().eq('id', tpl.id)
      )
      if (err) throw err
      load()
    } catch (e) {
      debugError('MessageTemplatesTab', 'delete', e)
      window.alert('Chyba při mazání: ' + e.message)
    }
    setConfirm(null)
  }

  const filtered = templates.filter(t => {
    if (!search) return true
    const s = search.toLowerCase()
    return (t.slug || '').toLowerCase().includes(s) || (t.name || '').toLowerCase().includes(s) || (t.body_template || t.content || '').toLowerCase().includes(s)
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <h2 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{CHANNEL_LABELS[channel]} Šablony</h2>
          <Badge label={String(templates.length)} color="#1a2e22" bg="#f1faf7" />
        </div>
        <div className="flex items-center gap-3">
          <SearchInput value={search} onChange={setSearch} placeholder="Hledat šablonu…" />
          <Button green onClick={openNew}>+ Nová šablona</Button>
        </div>
      </div>

      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA MessageTemplatesTab ({channel})</strong><br />
          <div>templates: {templates.length}, filtered: {filtered.length}, search: "{search}"</div>
          {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
        </div>
      )}

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16">
          <div style={{ fontSize: 48, marginBottom: 12 }}>📝</div>
          <div style={{ color: '#1a2e22', fontSize: 14, fontWeight: 700 }}>
            {search ? 'Žádné šablony odpovídající hledání' : `Zatím žádné ${CHANNEL_LABELS[channel]} šablony. Vytvořte první!`}
          </div>
        </div>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Slug</TH><TH>Název</TH><TH>Marketing</TH><TH>Jazyk</TH><TH>Trigger</TH><TH>Stav</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {filtered.map(tpl => (
              <TRow key={tpl.id}>
                <TD><span className="font-mono text-sm" style={{ color: '#1a2e22' }}>{tpl.slug || '—'}</span></TD>
                <TD bold>{tpl.name || '—'}</TD>
                <TD>{tpl.is_marketing ? <Badge label="Marketing" color="#7c3aed" bg="#ede9fe" /> : <Badge label="Transakční" color="#1a8a18" bg="#dcfce7" />}</TD>
                <TD><span className="text-sm" style={{ color: '#1a2e22' }}>{LANG_OPTIONS.find(l => l.value === tpl.language)?.label || tpl.language || 'cs'}</span></TD>
                <TD>{tpl.trigger_type ? <Badge label={tpl.trigger_type} color="#b45309" bg="#fef3c7" /> : <span style={{ color: '#9ca3af', fontSize: 12 }}>Žádný</span>}</TD>
                <TD><Badge label={tpl.is_active ? 'Aktivní' : 'Neaktivní'} color={tpl.is_active ? '#1a8a18' : '#6b7280'} bg={tpl.is_active ? '#dcfce7' : '#f3f4f6'} /></TD>
                <TD>
                  <div className="flex gap-1.5">
                    <button onClick={() => openEdit(tpl)} className="text-sm font-bold cursor-pointer border-none rounded-btn" style={{ padding: '4px 10px', background: '#f1faf7', color: '#1a2e22' }}>Upravit</button>
                    <button onClick={() => handleDuplicate(tpl)} className="text-sm font-bold cursor-pointer border-none rounded-btn" style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb' }}>Duplikovat</button>
                    <button onClick={() => setConfirm({ tpl, action: 'toggle' })} className="text-sm font-bold cursor-pointer border-none rounded-btn"
                      style={{ padding: '4px 10px', background: tpl.is_active ? '#fee2e2' : '#dcfce7', color: tpl.is_active ? '#dc2626' : '#1a8a18' }}>
                      {tpl.is_active ? 'Deaktivovat' : 'Aktivovat'}
                    </button>
                    <button onClick={() => setConfirm({ tpl, action: 'delete' })} className="text-sm font-bold cursor-pointer border-none rounded-btn" style={{ padding: '4px 10px', background: '#fee2e2', color: '#dc2626' }}>Smazat</button>
                  </div>
                </TD>
              </TRow>
            ))}
          </tbody>
        </Table>
      )}

      {showEdit && (
        <TemplateEditModal channel={channel} template={editing} onClose={() => setShowEdit(false)} onSaved={() => { setShowEdit(false); load() }} />
      )}

      <ConfirmDialog
        open={!!confirm}
        title={confirm?.action === 'delete' ? 'Smazat šablonu?' : confirm?.tpl?.is_active ? 'Deaktivovat šablonu?' : 'Aktivovat šablonu?'}
        message={confirm?.action === 'delete' ? `Opravdu smazat šablonu "${confirm?.tpl?.name}"? Tuto akci nelze vrátit.` : confirm?.tpl?.is_active ? `Deaktivovat šablonu "${confirm?.tpl?.name}"? Nebude dostupná pro nové zprávy.` : `Aktivovat šablonu "${confirm?.tpl?.name}"?`}
        danger={confirm?.action === 'delete' || confirm?.tpl?.is_active}
        onConfirm={() => { if (!confirm) return; if (confirm.action === 'delete') handleDelete(confirm.tpl); else handleToggleActive(confirm.tpl) }}
        onCancel={() => setConfirm(null)}
      />
    </div>
  )
}
