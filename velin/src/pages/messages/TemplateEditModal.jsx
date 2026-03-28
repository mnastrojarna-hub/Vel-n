import { useState, useRef, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

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

const TRIGGER_OPTIONS = [
  { value: '', label: 'Žádný trigger (ruční/kampaňové)' },
  { value: 'booking_reserved', label: 'Rezervace vytvořena' },
  { value: 'booking_confirmed', label: 'Rezervace potvrzena' },
  { value: 'booking_active', label: 'Rezervace aktivní (vyzvednutí)' },
  { value: 'booking_completed', label: 'Rezervace dokončena' },
  { value: 'booking_cancelled', label: 'Rezervace zrušena' },
  { value: 'booking_reminder', label: 'Připomínka před rezervací' },
  { value: 'post_return_review', label: 'Po vrácení — žádost o recenzi' },
  { value: 'customer_welcome', label: 'Uvítání nového zákazníka' },
  { value: 'customer_inactivity', label: 'Neaktivita zákazníka' },
  { value: 'door_codes', label: 'Přístupové kódy' },
  { value: 'voucher_purchased', label: 'Voucher zakoupen' },
  { value: 'payment_receipt', label: 'Potvrzení platby' },
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

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

export default function TemplateEditModal({ channel, template, onClose, onSaved }) {
  const isNew = !template
  const [slug, setSlug] = useState(template?.slug || '')
  const [name, setName] = useState(template?.name || '')
  const [language, setLanguage] = useState(template?.language || 'cs')
  const [bodyTemplate, setBodyTemplate] = useState(template?.body_template || template?.content || '')
  const [subjectTemplate, setSubjectTemplate] = useState(template?.subject_template || template?.subject || '')
  const [isMarketing, setIsMarketing] = useState(template?.is_marketing || false)
  const [isActive, setIsActive] = useState(template?.is_active ?? true)
  const [triggerType, setTriggerType] = useState(template?.trigger_type || '')
  const [waTemplateId, setWaTemplateId] = useState(template?.wa_template_id || '')
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const textareaRef = useRef(null)

  const detectedVars = useMemo(() => extractVariables(bodyTemplate), [bodyTemplate])
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

  function handleNameChange(val) {
    setName(val)
    if (isNew) {
      const autoSlug = val.toLowerCase()
        .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
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
        content: bodyTemplate,
        subject_template: channel === 'email' ? subjectTemplate || null : null,
        subject: channel === 'email' ? subjectTemplate || null : null,
        is_marketing: isMarketing,
        is_active: isActive,
        trigger_type: triggerType || null,
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
          <div>
            <Label>Slug</Label>
            <input type="text" value={slug} onChange={e => setSlug(e.target.value)} placeholder="napr. booking_confirmation" readOnly={!isNew}
              className="w-full rounded-btn text-sm outline-none font-mono" style={{ ...inputStyle, opacity: isNew ? 1 : 0.7, cursor: isNew ? 'text' : 'default' }} />
          </div>
          <div>
            <Label>Název *</Label>
            <input type="text" value={name} onChange={e => handleNameChange(e.target.value)} placeholder="Název šablony…" className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          </div>
          <div>
            <Label>Jazyk</Label>
            <select value={language} onChange={e => setLanguage(e.target.value)} className="w-full rounded-btn text-sm outline-none cursor-pointer" style={{ ...inputStyle, color: '#1a2e22' }}>
              {LANG_OPTIONS.map(l => <option key={l.value} value={l.value}>{l.label}</option>)}
            </select>
          </div>
          {channel === 'email' && (
            <div>
              <Label>Předmět</Label>
              <input type="text" value={subjectTemplate} onChange={e => setSubjectTemplate(e.target.value)} placeholder="Předmět e-mailu… (může obsahovat {{proměnné}})" className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
            </div>
          )}
          <div>
            <Label>Tělo šablony *</Label>
            <textarea ref={textareaRef} value={bodyTemplate} onChange={e => setBodyTemplate(e.target.value)}
              placeholder={channel === 'email' ? 'HTML nebo text šablony…' : 'Text šablony… Použijte {{proměnné}} pro dynamický obsah.'}
              className="w-full rounded-btn text-sm outline-none"
              style={{ ...inputStyle, minHeight: channel === 'email' ? 240 : 180, resize: 'vertical', fontFamily: channel === 'email' ? 'monospace' : 'inherit', fontSize: 14, lineHeight: 1.6 }} />
          </div>
          <div>
            <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Vložit proměnnou:</span>
            <div className="flex flex-wrap gap-1 mt-1">
              {AVAILABLE_VARS.map(v => (
                <button key={v} onClick={() => insertVariable(v)} className="rounded-btn font-mono font-bold cursor-pointer border-none"
                  style={{ padding: '3px 8px', fontSize: 10, background: detectedVars.includes(v) ? '#e8fee7' : '#f1faf7', border: detectedVars.includes(v) ? '1px solid #74FB71' : '1px solid #d4e8e0', color: '#2563eb' }}>
                  {`{{${v}}}`}
                </button>
              ))}
            </div>
          </div>
          {channel === 'whatsapp' && (
            <div>
              <Label>WhatsApp Template ID (Meta)</Label>
              <input type="text" value={waTemplateId} onChange={e => setWaTemplateId(e.target.value)} placeholder="Meta template SID…" className="w-full rounded-btn text-sm outline-none font-mono" style={inputStyle} />
              <div className="mt-1" style={{ fontSize: 11, color: '#6b7280' }}>Vyžadováno pro marketingové šablony schválené Metou.</div>
            </div>
          )}
          <div>
            <Label>Trigger (automatické odeslání)</Label>
            <select value={triggerType} onChange={e => setTriggerType(e.target.value)} className="w-full rounded-btn text-sm outline-none cursor-pointer" style={{ ...inputStyle, color: '#1a2e22' }}>
              {TRIGGER_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
            {triggerType && (
              <div className="mt-1" style={{ fontSize: 11, color: '#6b7280' }}>Tato šablona se automaticky odešle při události: {TRIGGER_OPTIONS.find(o => o.value === triggerType)?.label}</div>
            )}
          </div>
          <div className="flex items-center gap-6 pt-1">
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" checked={isMarketing} onChange={e => setIsMarketing(e.target.checked)} className="accent-[#7c3aed]" style={{ width: 16, height: 16 }} />
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Marketingová šablona</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" checked={isActive} onChange={e => setIsActive(e.target.checked)} className="accent-[#1a8a18]" style={{ width: 16, height: 16 }} />
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Aktivní</span>
            </label>
          </div>
        </div>

        {/* RIGHT: Preview */}
        <div className="flex-shrink-0" style={{ width: 300, minWidth: 260 }}>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Náhled</div>
          {channel === 'email' && previewSubject && (
            <div className="text-sm font-bold mb-2" style={{ color: '#0f1a14' }}>Předmět: {previewSubject}</div>
          )}
          {previewText ? (
            channel === 'email' ? (
              <div className="rounded-card" style={{ padding: 16, background: '#fff', border: '1px solid #d4e8e0', maxHeight: 400, overflow: 'auto', fontSize: 13, lineHeight: 1.6 }} dangerouslySetInnerHTML={{ __html: previewText }} />
            ) : channel === 'sms' ? (
              <div>
                <div className="rounded-card" style={{ padding: '14px 16px', background: '#dcfce7', color: '#0f1a14', fontSize: 13, lineHeight: 1.5, whiteSpace: 'pre-wrap', wordBreak: 'break-word', borderRadius: '16px 16px 4px 16px', maxHeight: 300, overflow: 'auto' }}>{previewText}</div>
                <div className="mt-2" style={{ fontSize: 11, color: '#1a2e22' }}>{previewText.length} znaků</div>
              </div>
            ) : (
              <div className="rounded-card" style={{ padding: '10px 14px', background: '#e7feed', color: '#0f1a14', fontSize: 13, lineHeight: 1.5, whiteSpace: 'pre-wrap', wordBreak: 'break-word', borderRadius: '16px 16px 4px 16px', maxHeight: 300, overflow: 'auto' }}>{previewText}</div>
            )
          ) : (
            <div className="rounded-card flex items-center justify-center" style={{ padding: 24, background: '#f1faf7', border: '1px dashed #d4e8e0', color: '#1a2e22', fontSize: 12, minHeight: 120 }}>Začněte psát pro zobrazení náhledu</div>
          )}
          {detectedVars.length > 0 && (
            <div className="mt-3">
              <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Použité proměnné:</div>
              <div className="flex flex-wrap gap-1">
                {detectedVars.map(v => (
                  <span key={v} className="inline-block rounded-btn font-mono font-bold"
                    style={{ padding: '2px 6px', fontSize: 9, background: SAMPLE_VARS[v] ? '#dcfce7' : '#fef3c7', border: SAMPLE_VARS[v] ? '1px solid #86efac' : '1px solid #fbbf24', color: SAMPLE_VARS[v] ? '#1a8a18' : '#b45309' }}>
                    {`{{${v}}}`}{SAMPLE_VARS[v] ? '' : ' ⚠'}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {err && <div className="mt-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{err}</div>}
      <div className="flex justify-end gap-2 mt-5 pt-4" style={{ borderTop: '1px solid #e5e7eb' }}>
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={!canSave}>{saving ? 'Ukládám…' : isNew ? 'Vytvořit' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}
