import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Card from '../../components/ui/Card'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }
const STEP_LABELS = ['Základní info', 'Příjemci', 'Náhled', 'Odeslání']

const SEGMENTS = [
  { value: 'all', icon: '📋', label: 'Všichni zákazníci', desc: 'Zákazníci se souhlasem s marketingem' },
  { value: 'vip', icon: '⭐', label: 'VIP zákazníci', desc: 'Reliability skóre > 80 nebo VIP tag' },
  { value: 'past_customers', icon: '🏍️', label: 'Minulí zákazníci', desc: 'Alespoň 1 dokončená rezervace' },
  { value: 'new_no_booking', icon: '👋', label: 'Noví bez rezervace', desc: 'Registrovaní, ale dosud si nepůjčili' },
]

// SMS pricing helpers (same as ManualSendTab)
const GSM7 = /^[A-Za-z0-9 @£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&'()*+,\-./:;<=>?¡ÄÖÑÜ§¿äöñüà^{}\\[~\]|€]*$/

function calcSmsSegments(text) {
  if (!text) return { segments: 0 }
  const isUcs2 = !GSM7.test(text)
  const perSegment = isUcs2 ? (text.length > 70 ? 67 : 70) : (text.length > 160 ? 153 : 160)
  return { segments: Math.ceil(text.length / perSegment) }
}

function extractVariables(templateContent) {
  if (!templateContent) return []
  const matches = templateContent.match(/\{\{(\w+)\}\}/g)
  if (!matches) return []
  return [...new Set(matches.map(m => m.replace(/\{\{|\}\}/g, '')))]
}

function replaceVariables(templateContent, vars) {
  if (!templateContent) return ''
  let result = templateContent
  Object.entries(vars).forEach(([key, val]) => {
    result = result.replaceAll(`{{${key}}}`, val || `{{${key}}}`)
  })
  return result
}

const COUNTRY_OPTIONS = [
  { value: '', label: 'Všechny země' },
  { value: 'CZ', label: 'Česko' },
  { value: 'SK', label: 'Slovensko' },
  { value: 'DE', label: 'Německo' },
  { value: 'AT', label: 'Rakousko' },
  { value: 'PL', label: 'Polsko' },
]

const LANGUAGE_OPTIONS = [
  { value: '', label: 'Všechny jazyky' },
  { value: 'cs', label: 'Čeština' },
  { value: 'en', label: 'English' },
  { value: 'de', label: 'Deutsch' },
]

export default function CampaignCreateModal({ open, channel, onClose, onCreated }) {
  const [step, setStep] = useState(1)
  const [name, setName] = useState('')
  const [templateId, setTemplateId] = useState('')
  const [segment, setSegment] = useState('all')
  const [filterCountry, setFilterCountry] = useState('')
  const [filterLanguage, setFilterLanguage] = useState('')
  const [recipientCount, setRecipientCount] = useState(0)
  const [recipientCountLoading, setRecipientCountLoading] = useState(false)
  const [templateVars, setTemplateVars] = useState({})
  const [scheduleMode, setScheduleMode] = useState('now')
  const [scheduledAt, setScheduledAt] = useState('')
  const [confirmed, setConfirmed] = useState(false)
  const [sending, setSending] = useState(false)
  const [templates, setTemplates] = useState([])
  const [sampleRecipients, setSampleRecipients] = useState([])

  // Load marketing templates on mount/channel change
  useEffect(() => {
    if (!open) return
    supabase.from('message_templates')
      .select('*')
      .eq('channel', channel)
      .eq('is_marketing', true)
      .eq('is_active', true)
      .order('name')
      .then(({ data }) => setTemplates(data || []))
  }, [channel, open])

  // Count recipients on segment/filter change
  useEffect(() => {
    if (!open) return
    countRecipients()
  }, [segment, filterCountry, filterLanguage, open, channel])

  // Reset on open
  useEffect(() => {
    if (open) {
      setStep(1)
      setName('')
      setTemplateId('')
      setSegment('all')
      setFilterCountry('')
      setFilterLanguage('')
      setRecipientCount(0)
      setTemplateVars({})
      setScheduleMode('now')
      setScheduledAt('')
      setConfirmed(false)
      setSending(false)
      setSampleRecipients([])
    }
  }, [open])

  const selectedTemplate = templates.find(t => t.id === templateId) || null
  const templateBody = selectedTemplate?.body_template || selectedTemplate?.content || ''
  const variables = useMemo(() => extractVariables(templateBody), [templateBody])
  const previewText = useMemo(() => replaceVariables(templateBody, templateVars), [templateBody, templateVars])
  const contactField = channel === 'email' ? 'email' : 'phone'

  function applyFilters(query) {
    if (filterCountry) query = query.eq('country', filterCountry)
    if (filterLanguage) query = query.eq('language', filterLanguage)
    return query
  }

  async function countRecipients() {
    setRecipientCountLoading(true)
    try {
      let query = supabase
        .from('profiles')
        .select('id', { count: 'exact', head: true })
        .eq('marketing_consent', true)
        .not(contactField, 'is', null)

      query = applyFilters(query)

      if (segment === 'vip') {
        query = query.or('reliability_score->>score.gt.80')
      } else if (segment === 'past_customers') {
        const { data: bookingUsers } = await supabase
          .from('bookings')
          .select('user_id')
          .eq('status', 'completed')
        const ids = [...new Set((bookingUsers || []).map(b => b.user_id))].filter(Boolean)
        if (ids.length > 0) {
          query = query.in('id', ids)
        } else {
          setRecipientCount(0)
          setRecipientCountLoading(false)
          return
        }
      } else if (segment === 'new_no_booking') {
        const { data: allBookingUsers } = await supabase
          .from('bookings')
          .select('user_id')
        const ids = [...new Set((allBookingUsers || []).map(b => b.user_id))].filter(Boolean)
        if (ids.length > 0) {
          query = query.not('id', 'in', `(${ids.join(',')})`)
        }
      }

      const { count, error } = await debugAction('campaignCreate.countRecipients', 'CampaignCreateModal', () => query)
      if (error) throw error
      setRecipientCount(count || 0)

      // Load sample recipients (first 5)
      let sampleQuery = supabase
        .from('profiles')
        .select('id, full_name, email, phone, country, language')
        .eq('marketing_consent', true)
        .not(contactField, 'is', null)
        .limit(5)

      sampleQuery = applyFilters(sampleQuery)

      if (segment === 'past_customers') {
        const { data: bookingUsers } = await supabase
          .from('bookings')
          .select('user_id')
          .eq('status', 'completed')
        const ids = [...new Set((bookingUsers || []).map(b => b.user_id))].filter(Boolean)
        if (ids.length > 0) sampleQuery = sampleQuery.in('id', ids)
      } else if (segment === 'new_no_booking') {
        const { data: allBookingUsers } = await supabase
          .from('bookings')
          .select('user_id')
        const ids = [...new Set((allBookingUsers || []).map(b => b.user_id))].filter(Boolean)
        if (ids.length > 0) sampleQuery = sampleQuery.not('id', 'in', `(${ids.join(',')})`)
      }

      const { data: samples } = await sampleQuery
      setSampleRecipients(samples || [])
    } catch (e) {
      debugError('CampaignCreateModal', 'countRecipients', e)
      setRecipientCount(0)
      setSampleRecipients([])
    }
    setRecipientCountLoading(false)
  }

  // Validation per step
  const step1Valid = name.trim() && templateId
  const step2Valid = segment && recipientCount > 0
  const step3Valid = variables.length === 0 || variables.every(v => templateVars[v]?.trim())
  const step4Valid = confirmed && (scheduleMode === 'now' || scheduledAt)

  function canNext() {
    if (step === 1) return step1Valid
    if (step === 2) return step2Valid
    if (step === 3) return step3Valid
    return false
  }

  // Price estimation
  function estimatePrice() {
    if (channel === 'sms') {
      const { segments } = calcSmsSegments(previewText)
      const totalSms = segments * recipientCount
      const price = totalSms * 1.35
      return `${segments} SMS × ${recipientCount} příjemců = ${totalSms} SMS ≈ ${Math.round(price)} Kč`
    }
    if (channel === 'whatsapp') {
      const price = recipientCount * 2.5
      return `${recipientCount} zpráv ≈ ${Math.round(price)} Kč`
    }
    return `${recipientCount} emailů`
  }

  async function handleSubmit(asDraft = false) {
    setSending(true)
    try {
      const segFilter = {}
      if (filterCountry) segFilter.country = filterCountry
      if (filterLanguage) segFilter.language = filterLanguage

      const payload = {
        name: name.trim(),
        channel,
        template_id: templateId,
        segment,
        segment_filter: Object.keys(segFilter).length > 0 ? segFilter : null,
        template_vars: Object.keys(templateVars).length > 0 ? templateVars : null,
        total_recipients: recipientCount,
        sent_count: 0,
        failed_count: 0,
        status: asDraft ? 'draft' : (scheduleMode === 'scheduled' ? 'scheduled' : 'draft'),
        scheduled_at: scheduleMode === 'scheduled' && !asDraft ? scheduledAt : null,
      }

      debugLog('CampaignCreateModal', 'submit', payload)

      const { data, error } = await debugAction('campaignCreate.insert', 'CampaignCreateModal', () =>
        supabase.from('broadcast_campaigns').insert(payload).select().single()
      )
      if (error) throw error

      // If sending now (not draft, not scheduled), invoke edge function
      if (!asDraft && scheduleMode === 'now') {
        await supabase.functions.invoke('send-broadcast', {
          body: { campaign_id: data.id }
        })
      }

      onClose()
      onCreated()
      window.alert(asDraft ? 'Kampaň uložena jako koncept.' : scheduleMode === 'scheduled' ? 'Kampaň naplánována.' : 'Kampaň odeslána!')
    } catch (e) {
      debugError('CampaignCreateModal', 'submit', e)
      window.alert('Chyba: ' + (e.message || 'Nepodařilo se vytvořit kampaň'))
    }
    setSending(false)
  }

  if (!open) return null

  return (
    <Modal open title="Nová kampaň" onClose={onClose} wide>
      {/* Stepper */}
      <div className="flex items-center justify-center gap-2 mb-6">
        {STEP_LABELS.map((label, i) => {
          const num = i + 1
          const isActive = step === num
          const isDone = step > num
          return (
            <div key={num} className="flex items-center gap-2">
              {i > 0 && (
                <div style={{ width: 32, height: 2, background: isDone ? '#1a8a18' : '#d1d5db' }} />
              )}
              <div className="flex items-center gap-1.5">
                <div
                  className="flex items-center justify-center font-bold text-sm"
                  style={{
                    width: 32, height: 32, borderRadius: '50%',
                    background: isDone ? '#1a8a18' : isActive ? '#74FB71' : '#f3f4f6',
                    color: isDone ? '#fff' : isActive ? '#0f1a14' : '#9ca3af',
                    border: isActive ? '2px solid #1a8a18' : '2px solid transparent',
                  }}
                >
                  {isDone ? '✓' : num}
                </div>
                <span
                  className="text-sm font-bold hidden sm:inline"
                  style={{ color: isActive ? '#0f1a14' : isDone ? '#1a8a18' : '#9ca3af', whiteSpace: 'nowrap' }}
                >
                  {label}
                </span>
              </div>
            </div>
          )
        })}
      </div>

      {/* Step 1 — Základní info */}
      {step === 1 && (
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              Název kampaně *
            </label>
            <input
              type="text"
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="Např. Zahájení sezóny 2026"
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
            />
          </div>

          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              Šablona *
            </label>
            {templates.length === 0 ? (
              <div className="rounded-card" style={{ padding: 16, background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, color: '#78350f' }}>
                ⚠️ Nejdříve vytvořte marketingovou šablonu v záložce Šablony.
              </div>
            ) : (
              <select
                value={templateId}
                onChange={e => { setTemplateId(e.target.value); setTemplateVars({}) }}
                className="w-full rounded-btn text-sm outline-none cursor-pointer"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
              >
                <option value="">— Vyberte šablonu —</option>
                {templates.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
              </select>
            )}
          </div>

          {/* Template preview */}
          {selectedTemplate && (
            <div className="rounded-card" style={{ padding: 12, background: '#f8fcfa', border: '1px solid #d4e8e0', fontFamily: 'monospace', fontSize: 12, whiteSpace: 'pre-wrap', maxHeight: 180, overflow: 'auto', color: '#1a2e22' }}>
              {templateBody || '(prázdná šablona)'}
            </div>
          )}
        </div>
      )}

      {/* Step 2 — Segment příjemců */}
      {step === 2 && (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            {SEGMENTS.map(s => (
              <div
                key={s.value}
                onClick={() => setSegment(s.value)}
                className="cursor-pointer rounded-card"
                style={{
                  padding: 12,
                  border: segment === s.value ? '2px solid #74FB71' : '2px solid #d4e8e0',
                  background: segment === s.value ? '#f0fdf0' : '#fff',
                }}
              >
                <div className="flex items-center gap-2 mb-1">
                  <span style={{ fontSize: 20 }}>{s.icon}</span>
                  <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{s.label}</span>
                </div>
                <div style={{ fontSize: 12, color: '#6b7280' }}>{s.desc}</div>
              </div>
            ))}
          </div>

          {/* Filtry: země a jazyk */}
          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
              Filtrovat podle
            </div>
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="block text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Země původu</label>
                <select
                  value={filterCountry}
                  onChange={e => setFilterCountry(e.target.value)}
                  className="w-full rounded-btn text-sm outline-none cursor-pointer"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
                >
                  {COUNTRY_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
                </select>
              </div>
              <div className="flex-1">
                <label className="block text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Jazyk aplikace</label>
                <select
                  value={filterLanguage}
                  onChange={e => setFilterLanguage(e.target.value)}
                  className="w-full rounded-btn text-sm outline-none cursor-pointer"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
                >
                  {LANGUAGE_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
                </select>
              </div>
            </div>
            {(filterCountry || filterLanguage) && (
              <div className="flex items-center gap-2 mt-2">
                <Badge label={filterCountry ? `Země: ${COUNTRY_OPTIONS.find(o => o.value === filterCountry)?.label}` : ''} color="#2563eb" bg="#dbeafe" />
                {filterLanguage && <Badge label={`Jazyk: ${LANGUAGE_OPTIONS.find(o => o.value === filterLanguage)?.label}`} color="#7c3aed" bg="#ede9fe" />}
                <button
                  onClick={() => { setFilterCountry(''); setFilterLanguage('') }}
                  className="text-sm font-bold cursor-pointer border-none rounded-btn"
                  style={{ padding: '3px 8px', background: '#fee2e2', color: '#dc2626' }}
                >
                  Zrušit filtry
                </button>
              </div>
            )}
          </div>

          {/* Počet příjemců */}
          <div className="flex items-center gap-3 py-2">
            {recipientCountLoading ? (
              <div className="animate-spin rounded-full h-5 w-5 border-t-2 border-brand-gd" />
            ) : (
              <div className="flex items-center gap-2">
                <span style={{ fontSize: 24 }}>👥</span>
                <span className="text-2xl font-black" style={{ color: '#1a8a18' }}>{recipientCount}</span>
                <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>příjemců</span>
              </div>
            )}
          </div>

          {recipientCount === 0 && !recipientCountLoading && (
            <div className="rounded-card" style={{ padding: 12, background: '#fee2e2', border: '1px solid #fca5a5', fontSize: 13, color: '#dc2626' }}>
              Žádní příjemci v tomto segmentu. Zvolte jiný segment.
            </div>
          )}

          {/* GDPR */}
          <div className="rounded-card" style={{ padding: 12, background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, color: '#78350f' }}>
            ⚠️ Kampaň bude odeslána pouze zákazníkům s aktivním marketingovým souhlasem.
            Zákazníci bez souhlasu (marketing_consent=false) jsou automaticky vyloučeni.
          </div>

          {/* WhatsApp info */}
          {channel === 'whatsapp' && (
            <div className="rounded-card" style={{ padding: 12, background: '#dbeafe', border: '1px solid #93c5fd', fontSize: 13, color: '#1e40af' }}>
              ℹ️ WhatsApp marketingové zprávy vyžadují šablonu schválenou Metou.
              Pokud šablona nemá wa_template_id, zprávy nebudou doručeny.
            </div>
          )}
        </div>
      )}

      {/* Step 3 — Náhled a proměnné */}
      {step === 3 && (
        <div className="space-y-4">
          {/* Template variables */}
          {variables.length > 0 && (
            <div>
              <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
                Proměnné šablony
              </div>
              <div className="space-y-2">
                {variables.map(v => (
                  <div key={v}>
                    <label className="block text-sm font-bold mb-0.5" style={{ color: '#1a2e22' }}>
                      {`{{${v}}}`}
                    </label>
                    <input
                      type="text"
                      value={templateVars[v] || ''}
                      onChange={e => setTemplateVars(prev => ({ ...prev, [v]: e.target.value }))}
                      placeholder={`Hodnota pro ${v}…`}
                      className="w-full rounded-btn text-sm outline-none"
                      style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
                    />
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Message preview (dark card) */}
          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
              Náhled zprávy
            </div>
            <div className="rounded-card" style={{ padding: 16, background: '#1a2e22', color: '#74FB71', fontSize: 13, lineHeight: 1.6, whiteSpace: 'pre-wrap', fontFamily: 'monospace', maxHeight: 200, overflow: 'auto' }}>
              {previewText || '(prázdná šablona)'}
            </div>
          </div>

          {/* Price estimate */}
          <div className="text-sm font-bold" style={{ color: '#1a8a18' }}>
            {estimatePrice()}
          </div>

          {/* Sample recipients */}
          {sampleRecipients.length > 0 && (
            <div>
              <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
                Ukázka příjemců
              </div>
              <Table>
                <thead>
                  <TRow header>
                    <TH>Jméno</TH>
                    <TH>{channel === 'email' ? 'Email' : 'Telefon'}</TH>
                    <TH>Země</TH>
                    <TH>Jazyk</TH>
                  </TRow>
                </thead>
                <tbody>
                  {sampleRecipients.map(r => (
                    <TRow key={r.id}>
                      <TD>{r.full_name || '—'}</TD>
                      <TD mono>{channel === 'email' ? r.email : r.phone || '—'}</TD>
                      <TD>{r.country || '—'}</TD>
                      <TD>{r.language || '—'}</TD>
                    </TRow>
                  ))}
                </tbody>
              </Table>
              {recipientCount > 5 && (
                <div className="text-center mt-1" style={{ fontSize: 12, color: '#6b7280' }}>
                  …a dalších {recipientCount - 5} příjemců
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {/* Step 4 — Odeslání */}
      {step === 4 && (
        <div className="space-y-4">
          {/* Rekapitulace */}
          <Card>
            <div className="space-y-2" style={{ fontSize: 13 }}>
              <div className="flex gap-2">
                <span className="font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 100 }}>Kampaň:</span>
                <span className="font-bold" style={{ color: '#0f1a14' }}>{name}</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 100 }}>Kanál:</span>
                <Badge label={CHANNEL_LABELS[channel]} color="#2563eb" bg="#dbeafe" />
              </div>
              <div className="flex gap-2">
                <span className="font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 100 }}>Šablona:</span>
                <span style={{ color: '#0f1a14' }}>{selectedTemplate?.name || '—'}</span>
              </div>
              <div className="flex gap-2">
                <span className="font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 100 }}>Příjemci:</span>
                <span className="font-bold" style={{ color: '#1a8a18' }}>{recipientCount}</span>
              </div>
              <div className="flex gap-2">
                <span className="font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 100 }}>Odhad ceny:</span>
                <span className="font-bold" style={{ color: '#1a8a18' }}>{estimatePrice()}</span>
              </div>
            </div>
          </Card>

          {/* Způsob odeslání */}
          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
              Způsob odeslání
            </div>
            <div className="flex gap-3">
              <div
                onClick={() => setScheduleMode('now')}
                className="cursor-pointer rounded-card flex-1"
                style={{
                  padding: 12,
                  border: scheduleMode === 'now' ? '2px solid #74FB71' : '2px solid #d4e8e0',
                  background: scheduleMode === 'now' ? '#f0fdf0' : '#fff',
                }}
              >
                <div className="flex items-center gap-2">
                  <span style={{ fontSize: 18 }}>🚀</span>
                  <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Odeslat ihned</span>
                </div>
              </div>
              <div
                onClick={() => setScheduleMode('scheduled')}
                className="cursor-pointer rounded-card flex-1"
                style={{
                  padding: 12,
                  border: scheduleMode === 'scheduled' ? '2px solid #74FB71' : '2px solid #d4e8e0',
                  background: scheduleMode === 'scheduled' ? '#f0fdf0' : '#fff',
                }}
              >
                <div className="flex items-center gap-2">
                  <span style={{ fontSize: 18 }}>📅</span>
                  <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Naplánovat</span>
                </div>
              </div>
            </div>
          </div>

          {/* Date/time pickers for scheduled */}
          {scheduleMode === 'scheduled' && (
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Datum</label>
                <input
                  type="date"
                  value={scheduledAt ? scheduledAt.split('T')[0] : ''}
                  onChange={e => {
                    const time = scheduledAt ? scheduledAt.split('T')[1] || '09:00' : '09:00'
                    setScheduledAt(e.target.value + 'T' + time)
                  }}
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
                />
              </div>
              <div className="flex-1">
                <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Čas</label>
                <input
                  type="time"
                  value={scheduledAt ? scheduledAt.split('T')[1] || '09:00' : '09:00'}
                  onChange={e => {
                    const date = scheduledAt ? scheduledAt.split('T')[0] : new Date().toISOString().split('T')[0]
                    setScheduledAt(date + 'T' + e.target.value)
                  }}
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
                />
              </div>
            </div>
          )}

          {/* Confirmation checkbox */}
          <label className="flex items-start gap-3 cursor-pointer rounded-card" style={{ padding: 12, background: confirmed ? '#f0fdf0' : '#f8fcfa', border: confirmed ? '2px solid #74FB71' : '2px solid #d4e8e0' }}>
            <input
              type="checkbox"
              checked={confirmed}
              onChange={e => setConfirmed(e.target.checked)}
              className="accent-[#1a8a18] mt-0.5"
              style={{ width: 18, height: 18 }}
            />
            <span className="text-sm" style={{ color: '#1a2e22', lineHeight: 1.5 }}>
              ✅ Rozumím, že odesílám <strong>{recipientCount}</strong> marketingových zpráv přes <strong>{CHANNEL_LABELS[channel]}</strong>.
              Tuto akci nelze vrátit zpět.
            </span>
          </label>
        </div>
      )}

      {/* Footer buttons */}
      <div className="flex justify-between items-center mt-6 pt-4" style={{ borderTop: '1px solid #e5e7eb' }}>
        <div>
          {step > 1 && (
            <Button onClick={() => setStep(s => s - 1)}>← Zpět</Button>
          )}
        </div>
        <div className="flex gap-2">
          {step === 4 && (
            <Button onClick={() => handleSubmit(true)} disabled={sending}>
              {sending ? 'Ukládám…' : 'Uložit jako koncept'}
            </Button>
          )}
          {step < 4 ? (
            <Button green onClick={() => setStep(s => s + 1)} disabled={!canNext()}>
              Další →
            </Button>
          ) : (
            <Button
              green
              onClick={() => handleSubmit(false)}
              disabled={!step4Valid || sending}
            >
              {sending ? 'Odesílám…' : scheduleMode === 'scheduled' ? 'Naplánovat' : 'Odeslat'}
            </Button>
          )}
        </div>
      </div>
    </Modal>
  )
}
