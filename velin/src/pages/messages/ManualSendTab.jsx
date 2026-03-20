import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'

const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }

export default function ManualSendTab({ channel }) {
  const [customers, setCustomers] = useState([])
  const [templates, setTemplates] = useState([])
  const [customerSearch, setCustomerSearch] = useState('')
  const [selectedCustomer, setSelectedCustomer] = useState('')
  const [subject, setSubject] = useState('')
  const [body, setBody] = useState('')
  const [sending, setSending] = useState(false)
  const [result, setResult] = useState(null)

  useEffect(() => { loadCustomers(); loadTemplates() }, [channel])

  async function loadCustomers() {
    const { data } = await debugAction('manualSend.loadCustomers', 'ManualSendTab', () =>
      supabase.from('profiles').select('id, full_name, email, phone').order('full_name').limit(200)
    )
    setCustomers(data || [])
  }

  async function loadTemplates() {
    const { data } = await debugAction('manualSend.loadTemplates', 'ManualSendTab', () =>
      supabase.from('message_templates').select('*').order('name')
    )
    setTemplates(data || [])
  }

  function applyTemplate(tplId) {
    const tpl = templates.find(t => t.id === tplId)
    if (tpl) {
      setBody(tpl.content || '')
      if (tpl.subject) setSubject(tpl.subject)
    }
  }

  async function handleSend() {
    if (!selectedCustomer || !body.trim()) return
    setSending(true)
    setResult(null)
    try {
      const customer = customers.find(c => c.id === selectedCustomer)
      const logEntry = {
        user_id: selectedCustomer,
        channel,
        type: 'manual',
        subject: subject || null,
        content: body.trim(),
        recipient: channel === 'email' ? customer?.email : customer?.phone,
        status: 'pending',
        created_at: new Date().toISOString(),
      }
      const { error } = await debugAction('manualSend.send', 'ManualSendTab', () =>
        supabase.from('notification_log').insert(logEntry)
      , logEntry)

      if (error) throw error
      setResult({ ok: true, msg: `${CHANNEL_LABELS[channel]} zpráva zařazena k odeslání` })
      setBody('')
      setSubject('')
      setSelectedCustomer('')
    } catch (e) {
      setResult({ ok: false, msg: `Chyba: ${e.message || 'Nepodařilo se odeslat'}` })
    }
    setSending(false)
  }

  const filteredCustomers = customerSearch
    ? customers.filter(c =>
        (c.full_name || '').toLowerCase().includes(customerSearch.toLowerCase()) ||
        (c.email || '').toLowerCase().includes(customerSearch.toLowerCase()) ||
        (c.phone || '').includes(customerSearch)
      )
    : customers

  return (
    <Card>
      <h2 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#1a2e22' }}>
        Ruční odeslání — {CHANNEL_LABELS[channel]}
      </h2>

      <div className="space-y-4" style={{ maxWidth: 600 }}>
        {/* Zákazník */}
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
            Příjemce
          </label>
          <input
            type="text"
            placeholder="Hledat zákazníka…"
            value={customerSearch}
            onChange={e => setCustomerSearch(e.target.value)}
            className="w-full rounded-btn text-sm outline-none mb-1"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
          />
          <select
            value={selectedCustomer}
            onChange={e => setSelectedCustomer(e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
            size={Math.min(filteredCustomers.length + 1, 6)}
          >
            <option value="">— Vyberte zákazníka —</option>
            {filteredCustomers.map(c => (
              <option key={c.id} value={c.id}>
                {c.full_name || 'Bez jména'} ({channel === 'email' ? c.email : c.phone || c.email})
              </option>
            ))}
          </select>
        </div>

        {/* Šablona */}
        {templates.length > 0 && (
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
              Šablona (volitelné)
            </label>
            <select
              onChange={e => { if (e.target.value) applyTemplate(e.target.value) }}
              value=""
              className="w-full rounded-btn text-sm outline-none cursor-pointer"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
            >
              <option value="">— Použít šablonu —</option>
              {templates.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
          </div>
        )}

        {/* Předmět (jen pro email) */}
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

        {/* Tělo zprávy */}
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>
            Zpráva
          </label>
          <textarea
            value={body}
            onChange={e => setBody(e.target.value)}
            placeholder={`Napište ${CHANNEL_LABELS[channel]} zprávu…`}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 120, resize: 'vertical' }}
          />
          {channel === 'sms' && (
            <div className="mt-1" style={{ fontSize: 11, color: '#1a2e22' }}>
              {body.length} znaků {body.length > 160 ? `(${Math.ceil(body.length / 153)} SMS)` : ''}
            </div>
          )}
        </div>

        {/* Odeslat */}
        <div className="flex items-center gap-3">
          <Button green onClick={handleSend} disabled={sending || !selectedCustomer || !body.trim()}>
            {sending ? 'Odesílám…' : `Odeslat ${CHANNEL_LABELS[channel]}`}
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
    </Card>
  )
}
