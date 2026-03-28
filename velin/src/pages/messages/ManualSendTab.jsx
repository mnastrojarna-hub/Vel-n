import { useState, useEffect, useRef, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'

import RadioOption from './RadioOption'
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

          {/* 1. Příjemce */}
          {sendType === 'bulk' ? (
            <div className="space-y-3">
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
                Skupina příjemců
              </label>
              <div className="grid grid-cols-2 gap-2">
                {BULK_SEGMENTS.map(s => (
                  <div
                    key={s.value}
                    onClick={() => setBulkSegment(s.value)}
                    className="cursor-pointer rounded-card"
                    style={{
                      padding: 10,
                      border: bulkSegment === s.value ? '2px solid #74FB71' : '2px solid #d4e8e0',
                      background: bulkSegment === s.value ? '#f0fdf0' : '#fff',
                    }}
                  >
                    <div className="flex items-center gap-2 mb-0.5">
                      <span style={{ fontSize: 16 }}>{s.icon}</span>
                      <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{s.label}</span>
                    </div>
                    <div style={{ fontSize: 11, color: '#6b7280' }}>{s.desc}</div>
                  </div>
                ))}
              </div>

              {/* Filtry */}
              <div className="flex gap-3">
                <div className="flex-1">
                  <label className="block text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Země</label>
                  <select
                    value={bulkCountry}
                    onChange={e => setBulkCountry(e.target.value)}
                    className="w-full rounded-btn text-sm outline-none cursor-pointer"
                    style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
                  >
                    {COUNTRY_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
                  </select>
                </div>
                <div className="flex-1">
                  <label className="block text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Jazyk</label>
                  <select
                    value={bulkLanguage}
                    onChange={e => setBulkLanguage(e.target.value)}
                    className="w-full rounded-btn text-sm outline-none cursor-pointer"
                    style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
                  >
                    {LANGUAGE_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
                  </select>
                </div>
              </div>

              {/* Počet příjemců */}
              <div className="flex items-center gap-2">
                {bulkCountLoading ? (
                  <div className="animate-spin rounded-full h-5 w-5 border-t-2 border-brand-gd" />
                ) : (
                  <>
                    <span style={{ fontSize: 20 }}>👥</span>
                    <span className="text-xl font-black" style={{ color: '#1a8a18' }}>{bulkRecipientCount}</span>
                    <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>příjemců</span>
                  </>
                )}
              </div>
            </div>
          ) : (
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              Příjemce
            </label>

            {selectedCustomer ? (
              <div className="flex items-center gap-3 rounded-btn" style={{ padding: '10px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                <div className="flex-1">
                  <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{selectedCustomer.full_name || 'Bez jména'}</div>
                  <div className="flex gap-4 mt-0.5" style={{ fontSize: 12, color: '#1a2e22' }}>
                    {selectedCustomer.phone && <span>📱 {selectedCustomer.phone}</span>}
                    {selectedCustomer.email && <span>📧 {selectedCustomer.email}</span>}
                  </div>
                </div>
                <button onClick={clearCustomer}
                  className="cursor-pointer border-none rounded-btn text-sm font-bold"
                  style={{ padding: '4px 10px', background: '#fee2e2', color: '#dc2626' }}>
                  Změnit
                </button>
              </div>
            ) : (
              <div className="relative">
                <input
                  type="text"
                  placeholder="Hledat jméno, email, telefon…"
                  value={customerSearch}
                  onChange={e => setCustomerSearch(e.target.value)}
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
                />
                {/* Dropdown results */}
                {(customers.length > 0 || loadingCustomers) && customerSearch.trim() && (
                  <div className="absolute left-0 right-0 top-full mt-1 bg-white rounded-card shadow-card z-10"
                    style={{ border: '1px solid #d4e8e0', maxHeight: 240, overflow: 'auto' }}>
                    {loadingCustomers ? (
                      <div className="flex justify-center py-3">
                        <div className="animate-spin rounded-full h-5 w-5 border-t-2 border-brand-gd" />
                      </div>
                    ) : (
                      customers.map(c => (
                        <div key={c.id} onClick={() => selectCustomer(c)}
                          className="cursor-pointer transition-colors"
                          style={{ padding: '8px 12px', borderBottom: '1px solid #f1faf7' }}
                          onMouseEnter={e => e.currentTarget.style.background = '#f1faf7'}
                          onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                          <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{c.full_name || 'Bez jména'}</div>
                          <div style={{ fontSize: 11, color: '#1a2e22' }}>
                            {c.phone && `📱 ${c.phone}`}{c.phone && c.email && ' · '}{c.email && `📧 ${c.email}`}
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                )}
              </div>
            )}

            {recipientWarning && (
              <div className="mt-1 text-sm font-bold" style={{ color: '#dc2626' }}>
                ⚠ {recipientWarning}
              </div>
            )}
          </div>
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

          {finalText ? (
            <div>
              {/* SMS bubble preview */}
              {channel === 'sms' && (
                <div>
                  <div className="rounded-card" style={{ padding: '14px 16px', background: '#dcfce7', color: '#0f1a14', fontSize: 13, lineHeight: 1.5, whiteSpace: 'pre-wrap', wordBreak: 'break-word', borderRadius: '16px 16px 4px 16px', maxHeight: 300, overflow: 'auto' }}>
                    {finalText}
                  </div>
                  <div className="mt-2 space-y-0.5" style={{ fontSize: 11, color: '#1a2e22' }}>
                    <div>{smsInfo.chars} znaků · {smsInfo.isUcs2 ? 'UCS-2 (diakritika)' : 'GSM 7-bit'}</div>
                    <div>{smsInfo.segments} {smsInfo.segments === 1 ? 'segment' : smsInfo.segments < 5 ? 'segmenty' : 'segmentů'} ({smsInfo.perSegment} znaků/segment)</div>
                    <div>Odhadovaná cena: ~{(smsInfo.segments * 0.5).toFixed(1)} Kč</div>
                  </div>
                </div>
              )}

              {/* WhatsApp bubble preview */}
              {channel === 'whatsapp' && (
                <div>
                  <div className="rounded-card" style={{ padding: '10px 14px', background: '#e7feed', color: '#0f1a14', fontSize: 13, lineHeight: 1.5, whiteSpace: 'pre-wrap', wordBreak: 'break-word', borderRadius: '16px 16px 4px 16px', maxHeight: 300, overflow: 'auto' }}>
                    {finalText}
                  </div>
                  <div className="mt-2" style={{ fontSize: 11, color: '#1a2e22' }}>
                    {finalText.length} / {CHAR_LIMITS.whatsapp} znaků
                  </div>
                </div>
              )}

              {/* Email preview */}
              {channel === 'email' && (
                <div className="rounded-card" style={{ background: '#fff', border: '1px solid #d4e8e0', overflow: 'hidden' }}>
                  {subject && (
                    <div className="text-sm font-bold" style={{ padding: '8px 12px', borderBottom: '1px solid #d4e8e0', color: '#0f1a14' }}>
                      {subject}
                    </div>
                  )}
                  <div style={{ padding: '10px 12px', fontSize: 13, lineHeight: 1.5, whiteSpace: 'pre-wrap', wordBreak: 'break-word', color: '#0f1a14', maxHeight: 300, overflow: 'auto' }}>
                    {finalText}
                  </div>
                </div>
              )}
            </div>
          ) : (
            <div className="rounded-card flex items-center justify-center"
              style={{ padding: 24, background: '#f1faf7', border: '1px dashed #d4e8e0', color: '#1a2e22', fontSize: 12, minHeight: 120 }}>
              Začněte psát pro zobrazení náhledu
            </div>
          )}
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

