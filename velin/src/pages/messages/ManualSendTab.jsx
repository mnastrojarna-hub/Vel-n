import { useState, useEffect, useRef, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'

import RadioOption from './RadioOption'
import ManualSendPreview from './ManualSendPreview'
import { BulkSegmentSelector, SingleCustomerField } from './CustomerSearchField'
import {
  CHANNEL_LABELS, CHAR_LIMITS, BULK_SEGMENTS, COUNTRY_OPTIONS, LANGUAGE_OPTIONS,
  calcSmsSegments, extractVariables, replaceVariables,
} from './messageHelpers'

export default function ManualSendTab({ channel }) {
  const debugMode = useDebugMode()

  // Send type: 'single' | 'bulk'
  const [sendType, setSendType] = useState('single')

  // Customer search + selection (single mode)
  const [customerSearch, setCustomerSearch] = useState('')
  const [debouncedSearch, setDebouncedSearch] = useState('')
  const [customers, setCustomers] = useState([])
  const [loadingCustomers, setLoadingCustomers] = useState(false)
  const [selectedCustomer, setSelectedCustomer] = useState(null)
  const searchTimer = useRef(null)

  // Bulk mode state
  const [bulkSegment, setBulkSegment] = useState('all')
  const [bulkCountry, setBulkCountry] = useState('')
  const [bulkLanguage, setBulkLanguage] = useState('')
  const [bulkRecipientCount, setBulkRecipientCount] = useState(0)
  const [bulkCountLoading, setBulkCountLoading] = useState(false)

  // Mode: 'template' | 'custom'
  const [mode, setMode] = useState('custom')

  // Templates
  const [templates, setTemplates] = useState([])
  const [selectedTemplateId, setSelectedTemplateId] = useState('')
  const [templateVars, setTemplateVars] = useState({})

  // Custom text
  const [subject, setSubject] = useState('')
  const [body, setBody] = useState('')

  // Send state
  const [sending, setSending] = useState(false)
  const [result, setResult] = useState(null)

  // Load templates on channel change
  useEffect(() => {
    loadTemplates()
    resetForm()
  }, [channel])

  // Count bulk recipients when segment/filters change
  useEffect(() => {
    if (sendType === 'bulk') countBulkRecipients()
  }, [bulkSegment, bulkCountry, bulkLanguage, sendType, channel])

  async function countBulkRecipients() {
    setBulkCountLoading(true)
    try {
      const contactField = channel === 'email' ? 'email' : 'phone'
      let query = supabase
        .from('profiles')
        .select('id', { count: 'exact', head: true })
        .not(contactField, 'is', null)

      if (bulkCountry) query = query.eq('country', bulkCountry)
      if (bulkLanguage) query = query.eq('language', bulkLanguage)

      if (bulkSegment === 'vip') {
        query = query.or('reliability_score->>score.gt.80')
      } else if (bulkSegment === 'past_customers') {
        const { data: bookingUsers } = await supabase
          .from('bookings').select('user_id').eq('status', 'completed')
        const ids = [...new Set((bookingUsers || []).map(b => b.user_id))].filter(Boolean)
        if (ids.length > 0) query = query.in('id', ids)
        else { setBulkRecipientCount(0); setBulkCountLoading(false); return }
      } else if (bulkSegment === 'new_no_booking') {
        const { data: allBookingUsers } = await supabase
          .from('bookings').select('user_id')
        const ids = [...new Set((allBookingUsers || []).map(b => b.user_id))].filter(Boolean)
        if (ids.length > 0) query = query.not('id', 'in', `(${ids.join(',')})`)
      }

      const { count } = await query
      setBulkRecipientCount(count || 0)
    } catch (e) {
      debugError('ManualSendTab', 'countBulkRecipients', e)
      setBulkRecipientCount(0)
    }
    setBulkCountLoading(false)
  }

  // Debounce customer search (300ms)
  useEffect(() => {
    clearTimeout(searchTimer.current)
    if (!customerSearch.trim()) {
      setDebouncedSearch('')
      setCustomers([])
      return
    }
    searchTimer.current = setTimeout(() => setDebouncedSearch(customerSearch), 300)
    return () => clearTimeout(searchTimer.current)
  }, [customerSearch])

  // Fetch customers on debounced search
  useEffect(() => {
    if (debouncedSearch.trim()) searchCustomers(debouncedSearch)
  }, [debouncedSearch])

  async function searchCustomers(q) {
    setLoadingCustomers(true)
    try {
      const { data, error } = await debugAction('manualSend.searchCustomers', 'ManualSendTab', () =>
        supabase.from('profiles')
          .select('id, full_name, email, phone')
          .or(`full_name.ilike.%${q}%,email.ilike.%${q}%,phone.ilike.%${q}%`)
          .order('full_name')
          .limit(20)
      )
      if (error) throw error
      setCustomers(data || [])
    } catch (e) {
      debugError('ManualSendTab', 'searchCustomers', e)
      setCustomers([])
    }
    setLoadingCustomers(false)
  }

  async function loadTemplates() {
    try {
      const { data } = await debugAction('manualSend.loadTemplates', 'ManualSendTab', () =>
        supabase.from('message_templates')
          .select('*')
          .eq('channel', channel)
          .eq('is_active', true)
          .order('name')
      )
      setTemplates(data || [])
    } catch (e) {
      debugError('ManualSendTab', 'loadTemplates', e)
      setTemplates([])
    }
  }

  function resetForm() {
    setSendType('single')
    setSelectedCustomer(null)
    setCustomerSearch('')
    setCustomers([])
    setBulkSegment('all')
    setBulkCountry('')
    setBulkLanguage('')
    setBulkRecipientCount(0)
    setMode('custom')
    setSelectedTemplateId('')
    setTemplateVars({})
    setSubject('')
    setBody('')
    setResult(null)
  }

  function selectCustomer(c) {
    setSelectedCustomer(c)
    setCustomerSearch('')
    setCustomers([])
  }

  function clearCustomer() {
    setSelectedCustomer(null)
    setCustomerSearch('')
  }

  // Selected template object
  const selectedTemplate = templates.find(t => t.id === selectedTemplateId) || null

  // Variables from selected template
  const templateVariables = useMemo(
    () => selectedTemplate ? extractVariables(selectedTemplate.content) : [],
    [selectedTemplate]
  )

  // Live preview of template with variables filled in
  const templatePreview = useMemo(
    () => selectedTemplate ? replaceVariables(selectedTemplate.content, templateVars) : '',
    [selectedTemplate, templateVars]
  )

  // Final message text
  const finalText = mode === 'template' ? templatePreview : body

  // SMS segment calculation
  const smsInfo = channel === 'sms' ? calcSmsSegments(finalText) : null

  // Validation
  const recipientValid = sendType === 'bulk'
    ? bulkRecipientCount > 0
    : selectedCustomer && (channel === 'email' ? !!selectedCustomer.email : !!selectedCustomer.phone)
  const contentValid = mode === 'template'
    ? !!selectedTemplate && templatePreview.trim().length > 0
    : body.trim().length > 0
  const emailSubjectValid = channel !== 'email' || subject.trim().length > 0
  const canSend = recipientValid && contentValid && emailSubjectValid && !sending

  // Recipient missing field warning
  const recipientWarning = sendType === 'single' && selectedCustomer && !recipientValid
    ? (channel === 'email' ? 'Zákazník nemá e-mail' : 'Zákazník nemá telefonní číslo')
    : null

  async function handleSend() {
    if (!canSend) return

    // Bulk: confirm before sending
    if (sendType === 'bulk') {
      const ok = window.confirm(`Opravdu odeslat ${CHANNEL_LABELS[channel]} zprávu ${bulkRecipientCount} příjemcům?`)
      if (!ok) return
    }

    setSending(true)
    setResult(null)
    try {
      if (sendType === 'bulk') {
        // Bulk send: fetch all recipient IDs and invoke edge function
        const contactField = channel === 'email' ? 'email' : 'phone'
        let query = supabase
          .from('profiles')
          .select('id, full_name, email, phone')
          .not(contactField, 'is', null)

        if (bulkCountry) query = query.eq('country', bulkCountry)
        if (bulkLanguage) query = query.eq('language', bulkLanguage)

        if (bulkSegment === 'vip') {
          query = query.or('reliability_score->>score.gt.80')
        } else if (bulkSegment === 'past_customers') {
          const { data: bookingUsers } = await supabase
            .from('bookings').select('user_id').eq('status', 'completed')
          const ids = [...new Set((bookingUsers || []).map(b => b.user_id))].filter(Boolean)
          if (ids.length > 0) query = query.in('id', ids)
        } else if (bulkSegment === 'new_no_booking') {
          const { data: allBookingUsers } = await supabase
            .from('bookings').select('user_id')
          const ids = [...new Set((allBookingUsers || []).map(b => b.user_id))].filter(Boolean)
          if (ids.length > 0) query = query.not('id', 'in', `(${ids.join(',')})`)
        }

        const { data: recipients } = await query
        const fnName = channel === 'email' ? 'send-email' : 'send-message'
        let sentOk = 0, sentFail = 0

        for (const r of (recipients || [])) {
          try {
            const to = channel === 'email' ? r.email : r.phone
            if (!to) { sentFail++; continue }
            const payload = {
              channel,
              to,
              customer_id: r.id,
              subject: channel === 'email' ? subject : undefined,
              template_slug: mode === 'template' && selectedTemplate ? selectedTemplate.slug || selectedTemplate.name : undefined,
              template_vars: mode === 'template' ? templateVars : undefined,
              raw_body: mode === 'custom' ? body.trim() : undefined,
              body: finalText,
            }
            await supabase.functions.invoke(fnName, { body: payload })
            sentOk++
          } catch { sentFail++ }
        }

        setResult({ ok: true, msg: `Hromadně odesláno: ${sentOk} OK, ${sentFail} selhalo` })
      } else {
        // Single send
        const to = channel === 'email' ? selectedCustomer.email : selectedCustomer.phone
        const payload = {
          channel,
          to,
          customer_id: selectedCustomer.id,
          subject: channel === 'email' ? subject : undefined,
          template_slug: mode === 'template' && selectedTemplate ? selectedTemplate.slug || selectedTemplate.name : undefined,
          template_vars: mode === 'template' ? templateVars : undefined,
          raw_body: mode === 'custom' ? body.trim() : undefined,
          body: finalText,
        }

        debugLog('ManualSendTab', 'handleSend', payload)

        const fnName = channel === 'email' ? 'send-email' : 'send-message'
        const { data, error } = await debugAction('manualSend.invoke', 'ManualSendTab', () =>
          supabase.functions.invoke(fnName, { body: payload })
        , payload)

        if (error) throw error
        setResult({ ok: true, msg: 'Zpráva odeslána!' })
      }

      // Reset form after success
      setSelectedCustomer(null)
      setCustomerSearch('')
      setMode('custom')
      setSelectedTemplateId('')
      setTemplateVars({})
      setSubject('')
      setBody('')
    } catch (e) {
      debugError('ManualSendTab', 'handleSend', e)
      setResult({ ok: false, msg: e.message || 'Nepodařilo se odeslat zprávu' })
    }
    setSending(false)
  }

  return (
    <Card>
      <h2 className="text-sm font-extrabold uppercase tracking-wide mb-5" style={{ color: '#1a2e22' }}>
        Ruční odeslání — {CHANNEL_LABELS[channel]}
      </h2>

      <div className="flex gap-6" style={{ flexWrap: 'wrap' }}>
        {/* LEFT: Formulář */}
        <div className="flex-1 space-y-4" style={{ minWidth: 340, maxWidth: 560 }}>

          {/* 0. Typ odeslání: Jednotlivé / Hromadné */}
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
              Typ odeslání
            </label>
            <div className="flex gap-3">
              <RadioOption
                checked={sendType === 'single'}
                onChange={() => setSendType('single')}
                label="Jednotlivé"
              />
              <RadioOption
                checked={sendType === 'bulk'}
                onChange={() => setSendType('bulk')}
                label="Hromadné"
              />
            </div>
          </div>

          {sendType === 'bulk' ? (
            <BulkSegmentSelector bulkSegment={bulkSegment} setBulkSegment={setBulkSegment} bulkCountry={bulkCountry} setBulkCountry={setBulkCountry} bulkLanguage={bulkLanguage} setBulkLanguage={setBulkLanguage} bulkCountLoading={bulkCountLoading} bulkRecipientCount={bulkRecipientCount} />
          ) : (
            <SingleCustomerField selectedCustomer={selectedCustomer} clearCustomer={clearCustomer} customerSearch={customerSearch} setCustomerSearch={setCustomerSearch} customers={customers} loadingCustomers={loadingCustomers} selectCustomer={selectCustomer} recipientWarning={recipientWarning} />
          )}

          {/* 2. Způsob */}
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
              Způsob
            </label>
            <div className="flex gap-3">
              <RadioOption
                checked={mode === 'template'}
                onChange={() => setMode('template')}
                label="Použít šablonu"
                disabled={templates.length === 0}
              />
              <RadioOption
                checked={mode === 'custom'}
                onChange={() => setMode('custom')}
                label="Vlastní text"
              />
            </div>
          </div>

          {/* 2a. Template mode */}
          {mode === 'template' && (
            <div className="space-y-3">
              <div>
                <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                  Šablona
                </label>
                <select
                  value={selectedTemplateId}
                  onChange={e => { setSelectedTemplateId(e.target.value); setTemplateVars({}) }}
                  className="w-full rounded-btn text-sm outline-none cursor-pointer"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
                >
                  <option value="">— Vyberte šablonu —</option>
                  {templates.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                </select>
              </div>

              {/* Template variable fields */}
              {templateVariables.length > 0 && (
                <div className="space-y-2">
                  <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
                    Proměnné
                  </div>
                  {templateVariables.map(v => (
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
              )}
            </div>
          )}

          {/* 2b. Custom mode */}
          {mode === 'custom' && (
            <div className="space-y-3">
              {channel === 'email' && (
                <div>
                  <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                    Předmět
                  </label>
                  <input
                    type="text"
                    value={subject}
                    onChange={e => setSubject(e.target.value)}
                    placeholder="Předmět e-mailu…"
                    className="w-full rounded-btn text-sm outline-none"
                    style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
                  />
                </div>
              )}

              <div>
                <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                  Zpráva
                </label>
                <textarea
                  value={body}
                  onChange={e => setBody(e.target.value)}
                  placeholder={`Napište ${CHANNEL_LABELS[channel]} zprávu…`}
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 140, resize: 'vertical' }}
                  maxLength={channel === 'email' ? undefined : CHAR_LIMITS[channel] || undefined}
                />
                {channel !== 'email' && (
                  <div className="flex justify-between mt-1" style={{ fontSize: 11, color: '#1a2e22' }}>
                    <span>{body.length} / {CHAR_LIMITS[channel]} znaků</span>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* 3. Odeslat */}
          <div className="flex items-center gap-3 pt-2">
            <Button green onClick={handleSend} disabled={!canSend}>
              {sending ? 'Odesílám…' : sendType === 'bulk' ? `Hromadně odeslat (${bulkRecipientCount})` : `Odeslat ${CHANNEL_LABELS[channel]}`}
            </Button>
            {result && (
              <Badge
                label={result.msg}
                color={result.ok ? '#1a6a18' : '#991b1b'}
                bg={result.ok ? '#dcfce7' : '#fee2e2'}
              />
            )}
          </div>
        </div>

        {/* RIGHT: Náhled */}
        <div className="flex-shrink-0" style={{ width: 280, minWidth: 240 }}>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
            Náhled
          </div>

          <ManualSendPreview channel={channel} finalText={finalText} subject={subject} smsInfo={smsInfo} />
        </div>
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
        <div className="mt-4 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA ManualSendTab ({channel})</strong><br/>
          <div>customer: {selectedCustomer ? `${selectedCustomer.full_name} (${selectedCustomer.id?.slice(-8)})` : 'žádný'}</div>
          <div>mode: {mode}, template: {selectedTemplateId || '—'}, vars: {JSON.stringify(templateVars)}</div>
          <div>canSend: {String(canSend)}, recipientValid: {String(recipientValid)}, contentValid: {String(contentValid)}</div>
        </div>
      )}
    </Card>
  )
}

