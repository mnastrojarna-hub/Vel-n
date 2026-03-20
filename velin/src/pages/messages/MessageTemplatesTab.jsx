import { useState, useEffect, useRef, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Badge from '../../components/ui/Badge'
import SearchInput from '../../components/ui/SearchInput'
import ConfirmDialog from '../../components/ui/ConfirmDialog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }

const AVAILABLE_VARS = [
  'customer_name', 'booking_number', 'motorcycle', 'start_date', 'end_date',
  'total_price', 'door_code_moto', 'door_code_gear', 'voucher_code',
  'review_link', 'link', 'discount', 'price',
]

const SAMPLE_VARS = {
  customer_name: 'Jan Novák',
  booking_number: '#RES-2026-0099',
  motorcycle: 'BMW R 1200 GS Adventure',
  start_date: '15. 6. 2026',
  end_date: '18. 6. 2026',
  total_price: '7 800 Kč',
  door_code_moto: '482917',
  door_code_gear: '613284',
  voucher_code: 'GIFT-ABC123',
  review_link: 'https://motogo24.cz/review',
  link: 'https://motogo24.cz',
  discount: '20%',
  price: '2 500 Kč',
}

const LANG_OPTIONS = [
  { value: 'cs', label: 'Čeština' },
  { value: 'en', label: 'English' },
  { value: 'de', label: 'Deutsch' },
]

function extractVariables(content) {
  if (!content) return []
  const matches = content.match(/\{\{(\w+)\}\}/g)
  if (!matches) return []
  return [...new Set(matches.map(m => m.replace(/\{\{|\}\}/g, '')))]
}

function replaceVariables(content, vars) {
  if (!content) return ''
  let result = content
  Object.entries(vars).forEach(([key, val]) => {
    result = result.replaceAll(`{{${key}}}`, val || `{{${key}}}`)
  })
  return result
}

export default function MessageTemplatesTab({ channel }) {
  const debugMode = useDebugMode()
  const [templates, setTemplates] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [search, setSearch] = useState('')
  const [showEdit, setShowEdit] = useState(false)
  const [editing, setEditing] = useState(null) // null = new, object = edit
  const [confirm, setConfirm] = useState(null)

  useEffect(() => { load() }, [channel])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const { data, error: err } = await debugAction('templates.load', 'MessageTemplatesTab', () =>
        supabase.from('message_templates')
          .select('*')
          .eq('channel', channel)
          .order('slug')
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

  function openNew() {
    setEditing(null)
    setShowEdit(true)
  }

  function openEdit(tpl) {
    setEditing(tpl)
    setShowEdit(true)
  }

  async function handleDuplicate(tpl) {
    try {
      const payload = {
        slug: tpl.slug + '_copy',
        name: tpl.name + ' (kopie)',
        channel: tpl.channel,
        language: tpl.language || 'cs',
        body_template: tpl.body_template || tpl.content || '',
        subject_template: tpl.subject_template || tpl.subject || null,
        is_marketing: tpl.is_marketing || false,
        is_active: false,
        wa_template_id: tpl.wa_template_id || null,
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
        supabase.from('message_templates')
          .update({ is_active: !tpl.is_active })
          .eq('id', tpl.id)
      )
      if (err) throw err
      load()
    } catch (e) {
      debugError('MessageTemplatesTab', 'toggleActive', e)
    }
    setConfirm(null)
  }

  // Filter by search
  const filtered = templates.filter(t => {
    if (!search) return true
    const s = search.toLowerCase()
    return (t.slug || '').toLowerCase().includes(s)
      || (t.name || '').toLowerCase().includes(s)
      || (t.body_template || t.content || '').toLowerCase().includes(s)
  })

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <h2 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
            {CHANNEL_LABELS[channel]} Šablony
          </h2>
          <Badge label={String(templates.length)} color="#1a2e22" bg="#f1faf7" />
        </div>
        <div className="flex items-center gap-3">
          <SearchInput value={search} onChange={setSearch} placeholder="Hledat šablonu…" />
          <Button green onClick={openNew}>+ Nová šablona</Button>
        </div>
      </div>

      {/* Diagnostika */}
      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA MessageTemplatesTab ({channel})</strong><br />
          <div>templates: {templates.length}, filtered: {filtered.length}, search: "{search}"</div>
          {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
        </div>
      )}

      {/* Error */}
      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Table */}
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
              <TH>Slug</TH>
              <TH>Název</TH>
              <TH>Marketing</TH>
              <TH>Jazyk</TH>
              <TH>Stav</TH>
              <TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {filtered.map(tpl => (
              <TRow key={tpl.id}>
                <TD><span className="font-mono text-sm" style={{ color: '#1a2e22' }}>{tpl.slug || '—'}</span></TD>
                <TD bold>{tpl.name || '—'}</TD>
                <TD>
                  {tpl.is_marketing
                    ? <Badge label="Marketing" color="#7c3aed" bg="#ede9fe" />
                    : <Badge label="Transakční" color="#1a8a18" bg="#dcfce7" />
                  }
                </TD>
                <TD>
                  <span className="text-sm" style={{ color: '#1a2e22' }}>
                    {LANG_OPTIONS.find(l => l.value === tpl.language)?.label || tpl.language || 'cs'}
                  </span>
                </TD>
                <TD>
                  <Badge
                    label={tpl.is_active ? 'Aktivní' : 'Neaktivní'}
                    color={tpl.is_active ? '#1a8a18' : '#6b7280'}
                    bg={tpl.is_active ? '#dcfce7' : '#f3f4f6'}
                  />
                </TD>
                <TD>
                  <div className="flex gap-1.5">
                    <button
                      onClick={() => openEdit(tpl)}
                      className="text-sm font-bold cursor-pointer border-none rounded-btn"
                      style={{ padding: '4px 10px', background: '#f1faf7', color: '#1a2e22' }}
                    >
                      Upravit
                    </button>
                    <button
                      onClick={() => handleDuplicate(tpl)}
                      className="text-sm font-bold cursor-pointer border-none rounded-btn"
                      style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb' }}
                    >
                      Duplikovat
                    </button>
                    <button
                      onClick={() => setConfirm({ tpl, action: 'toggle' })}
                      className="text-sm font-bold cursor-pointer border-none rounded-btn"
                      style={{
                        padding: '4px 10px',
                        background: tpl.is_active ? '#fee2e2' : '#dcfce7',
                        color: tpl.is_active ? '#dc2626' : '#1a8a18',
                      }}
                    >
                      {tpl.is_active ? 'Deaktivovat' : 'Aktivovat'}
                    </button>
                  </div>
                </TD>
              </TRow>
            ))}
          </tbody>
        </Table>
      )}

      {/* Edit/New modal */}
      {showEdit && (
        <TemplateEditModal
          channel={channel}
          template={editing}
          onClose={() => setShowEdit(false)}
          onSaved={() => { setShowEdit(false); load() }}
        />
      )}

      {/* Confirm dialog */}
      <ConfirmDialog
        open={!!confirm}
        title={confirm?.tpl?.is_active ? 'Deaktivovat šablonu?' : 'Aktivovat šablonu?'}
        message={confirm?.tpl?.is_active
          ? `Deaktivovat šablonu "${confirm?.tpl?.name}"? Nebude dostupná pro nové zprávy.`
          : `Aktivovat šablonu "${confirm?.tpl?.name}"?`
        }
        danger={confirm?.tpl?.is_active}
        onConfirm={() => confirm && handleToggleActive(confirm.tpl)}
        onCancel={() => setConfirm(null)}
      />
    </div>
  )
}

/* ────────────────────── Template Edit Modal ────────────────────── */

function TemplateEditModal({ channel, template, onClose, onSaved }) {
  const isNew = !template
  const [slug, setSlug] = useState(template?.slug || '')
  const [name, setName] = useState(template?.name || '')
  const [language, setLanguage] = useState(template?.language || 'cs')
  const [bodyTemplate, setBodyTemplate] = useState(template?.body_template || template?.content || '')
  const [subjectTemplate, setSubjectTemplate] = useState(template?.subject_template || template?.subject || '')
  const [isMarketing, setIsMarketing] = useState(template?.is_marketing || false)
  const [isActive, setIsActive] = useState(template?.is_active ?? true)
  const [waTemplateId, setWaTemplateId] = useState(template?.wa_template_id || '')
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const textareaRef = useRef(null)

  // Detected variables from body
  const detectedVars = useMemo(() => extractVariables(bodyTemplate), [bodyTemplate])

  // Live preview with sample data
  const previewText = useMemo(() => replaceVariables(bodyTemplate, SAMPLE_VARS), [bodyTemplate])
  const previewSubject = useMemo(() => replaceVariables(subjectTemplate, SAMPLE_VARS), [subjectTemplate])

  function insertVariable(varName) {
    const ta = textareaRef.current
    if (!ta) return
    const start = ta.selectionStart
    const end = ta.selectionEnd
    const tag = `{{${varName}}}`
    const newVal = bodyTemplate.slice(0, start) + tag + bodyTemplate.slice(end)
    setBodyTemplate(newVal)
    setTimeout(() => {
      ta.focus()
      ta.selectionStart = ta.selectionEnd = start + tag.length
    }, 0)
  }

  // Auto-generate slug from name for new templates
  function handleNameChange(val) {
    setName(val)
    if (isNew) {
      const autoSlug = val.toLowerCase()
        .normalize('NFD').replace(/[\u0300-\u036f]/g, '') // strip diacritics
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_|_$/g, '')
      setSlug(autoSlug)
    }
  }

  async function handleSave() {
    if (!name.trim() || !slug.trim() || !bodyTemplate.trim()) return
    setSaving(true)
    setErr(null)
    try {
      const payload = {
        slug: slug.trim(),
        name: name.trim(),
        channel,
        language,
        body_template: bodyTemplate,
        content: bodyTemplate, // keep content in sync
        subject_template: channel === 'email' ? subjectTemplate || null : null,
        subject: channel === 'email' ? subjectTemplate || null : null,
        is_marketing: isMarketing,
        is_active: isActive,
        wa_template_id: channel === 'whatsapp' ? waTemplateId || null : null,
      }

      debugLog('TemplateEditModal', 'save', payload)

      if (isNew) {
        const { error: insertErr } = await debugAction('templates.insert', 'TemplateEditModal', () =>
          supabase.from('message_templates').insert(payload)
        , payload)
        if (insertErr) throw insertErr
      } else {
        const { error: updateErr } = await debugAction('templates.update', 'TemplateEditModal', () =>
          supabase.from('message_templates').update(payload).eq('id', template.id)
        , { id: template.id, ...payload })
        if (updateErr) throw updateErr
      }

      onSaved()
    } catch (e) {
      debugError('TemplateEditModal', 'save', e)
      setErr(e.message || 'Nepodařilo se uložit šablonu')
    }
    setSaving(false)
  }

  const canSave = name.trim() && slug.trim() && bodyTemplate.trim() && !saving

  return (
    <Modal open title={isNew ? `Nová ${CHANNEL_LABELS[channel]} šablona` : `Upravit: ${template.name}`} onClose={onClose} wide>
      <div className="flex gap-6" style={{ flexWrap: 'wrap' }}>
        {/* LEFT: Form */}
        <div className="flex-1 space-y-3" style={{ minWidth: 340 }}>
          {/* Slug */}
          <div>
            <Label>Slug</Label>
            <input
              type="text"
              value={slug}
              onChange={e => setSlug(e.target.value)}
              placeholder="napr. booking_confirmation"
              readOnly={!isNew}
              className="w-full rounded-btn text-sm outline-none font-mono"
              style={{
                ...inputStyle,
                opacity: isNew ? 1 : 0.7,
                cursor: isNew ? 'text' : 'default',
              }}
            />
          </div>

          {/* Name */}
          <div>
            <Label>Název *</Label>
            <input
              type="text"
              value={name}
              onChange={e => handleNameChange(e.target.value)}
              placeholder="Název šablony…"
              className="w-full rounded-btn text-sm outline-none"
              style={inputStyle}
            />
          </div>

          {/* Language */}
          <div>
            <Label>Jazyk</Label>
            <select
              value={language}
              onChange={e => setLanguage(e.target.value)}
              className="w-full rounded-btn text-sm outline-none cursor-pointer"
              style={{ ...inputStyle, color: '#1a2e22' }}
            >
              {LANG_OPTIONS.map(l => <option key={l.value} value={l.value}>{l.label}</option>)}
            </select>
          </div>

          {/* Subject (email only) */}
          {channel === 'email' && (
            <div>
              <Label>Předmět</Label>
              <input
                type="text"
                value={subjectTemplate}
                onChange={e => setSubjectTemplate(e.target.value)}
                placeholder="Předmět e-mailu… (může obsahovat {{proměnné}})"
                className="w-full rounded-btn text-sm outline-none"
                style={inputStyle}
              />
            </div>
          )}

          {/* Body template */}
          <div>
            <Label>Tělo šablony *</Label>
            <textarea
              ref={textareaRef}
              value={bodyTemplate}
              onChange={e => setBodyTemplate(e.target.value)}
              placeholder={channel === 'email' ? 'HTML nebo text šablony…' : 'Text šablony… Použijte {{proměnné}} pro dynamický obsah.'}
              className="w-full rounded-btn text-sm outline-none"
              style={{
                ...inputStyle,
                minHeight: channel === 'email' ? 240 : 180,
                resize: 'vertical',
                fontFamily: channel === 'email' ? 'monospace' : 'inherit',
                fontSize: 14,
                lineHeight: 1.6,
              }}
            />
          </div>

          {/* Variable badges */}
          <div>
            <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
              Vložit proměnnou:
            </span>
            <div className="flex flex-wrap gap-1 mt-1">
              {AVAILABLE_VARS.map(v => (
                <button
                  key={v}
                  onClick={() => insertVariable(v)}
                  className="rounded-btn font-mono font-bold cursor-pointer border-none"
                  style={{
                    padding: '3px 8px',
                    fontSize: 10,
                    background: detectedVars.includes(v) ? '#e8fee7' : '#f1faf7',
                    border: detectedVars.includes(v) ? '1px solid #74FB71' : '1px solid #d4e8e0',
                    color: '#2563eb',
                  }}
                >
                  {`{{${v}}}`}
                </button>
              ))}
            </div>
          </div>

          {/* WA template ID */}
          {channel === 'whatsapp' && (
            <div>
              <Label>WhatsApp Template ID (Meta)</Label>
              <input
                type="text"
                value={waTemplateId}
                onChange={e => setWaTemplateId(e.target.value)}
                placeholder="Meta template SID…"
                className="w-full rounded-btn text-sm outline-none font-mono"
                style={inputStyle}
              />
              <div className="mt-1" style={{ fontSize: 11, color: '#6b7280' }}>
                Vyžadováno pro marketingové šablony schválené Metou.
              </div>
            </div>
          )}

          {/* Checkboxes */}
          <div className="flex items-center gap-6 pt-1">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={isMarketing}
                onChange={e => setIsMarketing(e.target.checked)}
                className="accent-[#7c3aed]"
                style={{ width: 16, height: 16 }}
              />
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Marketingová šablona</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={isActive}
                onChange={e => setIsActive(e.target.checked)}
                className="accent-[#1a8a18]"
                style={{ width: 16, height: 16 }}
              />
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Aktivní</span>
            </label>
          </div>
        </div>

        {/* RIGHT: Preview */}
        <div className="flex-shrink-0" style={{ width: 300, minWidth: 260 }}>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
            Náhled
          </div>

          {/* Subject preview for email */}
          {channel === 'email' && previewSubject && (
            <div className="text-sm font-bold mb-2" style={{ color: '#0f1a14' }}>
              Předmět: {previewSubject}
            </div>
          )}

          {previewText ? (
            channel === 'email' ? (
              // Email: render HTML
              <div
                className="rounded-card"
                style={{
                  padding: 16,
                  background: '#fff',
                  border: '1px solid #d4e8e0',
                  maxHeight: 400,
                  overflow: 'auto',
                  fontSize: 13,
                  lineHeight: 1.6,
                }}
                dangerouslySetInnerHTML={{ __html: previewText }}
              />
            ) : channel === 'sms' ? (
              // SMS bubble
              <div>
                <div
                  className="rounded-card"
                  style={{
                    padding: '14px 16px',
                    background: '#dcfce7',
                    color: '#0f1a14',
                    fontSize: 13,
                    lineHeight: 1.5,
                    whiteSpace: 'pre-wrap',
                    wordBreak: 'break-word',
                    borderRadius: '16px 16px 4px 16px',
                    maxHeight: 300,
                    overflow: 'auto',
                  }}
                >
                  {previewText}
                </div>
                <div className="mt-2" style={{ fontSize: 11, color: '#1a2e22' }}>
                  {previewText.length} znaků
                </div>
              </div>
            ) : (
              // WhatsApp bubble
              <div
                className="rounded-card"
                style={{
                  padding: '10px 14px',
                  background: '#e7feed',
                  color: '#0f1a14',
                  fontSize: 13,
                  lineHeight: 1.5,
                  whiteSpace: 'pre-wrap',
                  wordBreak: 'break-word',
                  borderRadius: '16px 16px 4px 16px',
                  maxHeight: 300,
                  overflow: 'auto',
                }}
              >
                {previewText}
              </div>
            )
          ) : (
            <div
              className="rounded-card flex items-center justify-center"
              style={{
                padding: 24,
                background: '#f1faf7',
                border: '1px dashed #d4e8e0',
                color: '#1a2e22',
                fontSize: 12,
                minHeight: 120,
              }}
            >
              Začněte psát pro zobrazení náhledu
            </div>
          )}

          {/* Detected variables */}
          {detectedVars.length > 0 && (
            <div className="mt-3">
              <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                Použité proměnné:
              </div>
              <div className="flex flex-wrap gap-1">
                {detectedVars.map(v => (
                  <span
                    key={v}
                    className="inline-block rounded-btn font-mono font-bold"
                    style={{
                      padding: '2px 6px',
                      fontSize: 9,
                      background: SAMPLE_VARS[v] ? '#dcfce7' : '#fef3c7',
                      border: SAMPLE_VARS[v] ? '1px solid #86efac' : '1px solid #fbbf24',
                      color: SAMPLE_VARS[v] ? '#1a8a18' : '#b45309',
                    }}
                  >
                    {`{{${v}}}`}{SAMPLE_VARS[v] ? '' : ' ⚠'}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Error */}
      {err && <div className="mt-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{err}</div>}

      {/* Footer */}
      <div className="flex justify-end gap-2 mt-5 pt-4" style={{ borderTop: '1px solid #e5e7eb' }}>
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={!canSave}>
          {saving ? 'Ukládám…' : isNew ? 'Vytvořit' : 'Uložit'}
        </Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
