import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Card from '../../components/ui/Card'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import { CampaignStep2, CampaignStep3, CampaignStep4 } from './CampaignSteps'

import {
  CHANNEL_LABELS, COUNTRY_OPTIONS, LANGUAGE_OPTIONS,
  calcSmsSegments, extractVariables, replaceVariables,
} from './messageHelpers'

const STEP_LABELS = ['Zakladni info', 'Prijemci', 'Nahled', 'Odeslani']
const SEGMENTS = [
  { value: 'all', icon: '\ud83d\udccb', label: 'Vsichni zakaznici', desc: 'Zakaznici se souhlasem s marketingem' },
  { value: 'vip', icon: '\u2b50', label: 'VIP zakaznici', desc: 'Reliability skore > 80 nebo VIP tag' },
  { value: 'past_customers', icon: '\ud83c\udfcd\ufe0f', label: 'Minuli zakaznici', desc: 'Alespon 1 dokoncena rezervace' },
  { value: 'new_no_booking', icon: '\ud83d\udc4b', label: 'Novi bez rezervace', desc: 'Registrovani, ale dosud si nepujcili' },
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

      {step === 2 && (
        <CampaignStep2 segment={segment} setSegment={setSegment} segments={SEGMENTS} filterCountry={filterCountry} setFilterCountry={setFilterCountry} filterLanguage={filterLanguage} setFilterLanguage={setFilterLanguage} recipientCountLoading={recipientCountLoading} recipientCount={recipientCount} channel={channel} />
      )}

      {step === 3 && (
        <CampaignStep3 variables={variables} templateVars={templateVars} setTemplateVars={setTemplateVars} previewText={previewText} estimatePrice={estimatePrice} sampleRecipients={sampleRecipients} recipientCount={recipientCount} channel={channel} />
      )}

      {step === 4 && (
        <CampaignStep4 name={name} channel={channel} selectedTemplate={selectedTemplate} recipientCount={recipientCount} estimatePrice={estimatePrice} scheduleMode={scheduleMode} setScheduleMode={setScheduleMode} scheduledAt={scheduledAt} setScheduledAt={setScheduledAt} confirmed={confirmed} setConfirmed={setConfirmed} />
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
