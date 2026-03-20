import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugError } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import ConfirmDialog from '../../components/ui/ConfirmDialog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }

const TRIGGER_TYPES = [
  { value: 'booking_status_change', label: 'Změna stavu rezervace', icon: '🔄', desc: 'Při přechodu rezervace na konkrétní stav' },
  { value: 'booking_reminder', label: 'Připomínka rezervace', icon: '⏰', desc: 'X dní/hodin před začátkem/koncem rezervace' },
  { value: 'customer_inactivity', label: 'Neaktivita zákazníka', icon: '💤', desc: 'Zákazník si nic nepůjčil X dní' },
  { value: 'post_return', label: 'Po vrácení', icon: '✅', desc: 'X dní po dokončení rezervace (review, nabídka)' },
  { value: 'birthday', label: 'Narozeniny', icon: '🎂', desc: 'V den narozenin zákazníka' },
  { value: 'registration_welcome', label: 'Uvítací zpráva', icon: '👋', desc: 'Po registraci nového zákazníka' },
  { value: 'abandoned_booking', label: 'Opuštěná rezervace', icon: '🚪', desc: 'Neplatená rezervace po X min/hodinách' },
  { value: 'seasonal', label: 'Sezónní', icon: '📅', desc: 'Začátek/konec sezóny, speciální dny' },
]

const BOOKING_STATUSES = [
  { value: 'pending', label: 'Čekající' },
  { value: 'reserved', label: 'Rezervováno' },
  { value: 'active', label: 'Aktivní' },
  { value: 'completed', label: 'Dokončeno' },
  { value: 'cancelled', label: 'Zrušeno' },
]

const TIME_UNITS = [
  { value: 'minutes', label: 'minut' },
  { value: 'hours', label: 'hodin' },
  { value: 'days', label: 'dní' },
]

export default function AutoMessagesTab({ channel }) {
  const [rules, setRules] = useState([])
  const [loading, setLoading] = useState(true)
  const [templates, setTemplates] = useState([])
  const [showCreate, setShowCreate] = useState(false)
  const [editing, setEditing] = useState(null)
  const [confirm, setConfirm] = useState(null)

  useEffect(() => { load(); loadTemplates() }, [channel])

  async function load() {
    setLoading(true)
    try {
      const { data } = await debugAction('autoMessages.load', 'AutoMessagesTab', () =>
        supabase.from('automation_rules')
          .select('*')
          .eq('channel', channel)
          .order('created_at', { ascending: false })
      )
      setRules(data || [])
    } catch (e) {
      debugError('AutoMessagesTab', 'load', e)
      setRules([])
    }
    setLoading(false)
  }

  async function loadTemplates() {
    try {
      const { data } = await supabase.from('message_templates')
        .select('id, slug, name, body_template, content')
        .eq('channel', channel)
        .eq('is_active', true)
        .order('name')
      setTemplates(data || [])
    } catch { setTemplates([]) }
  }

  async function handleToggle(rule) {
    try {
      await supabase.from('automation_rules')
        .update({ is_active: !rule.is_active })
        .eq('id', rule.id)
      load()
    } catch (e) {
      debugError('AutoMessagesTab', 'toggle', e)
    }
    setConfirm(null)
  }

  async function handleDelete(rule) {
    try {
      await supabase.from('automation_rules').delete().eq('id', rule.id)
      load()
    } catch (e) {
      debugError('AutoMessagesTab', 'delete', e)
      window.alert('Chyba: ' + e.message)
    }
    setConfirm(null)
  }

  const triggerLabel = (type) => TRIGGER_TYPES.find(t => t.value === type)?.label || type
  const triggerIcon = (type) => TRIGGER_TYPES.find(t => t.value === type)?.icon || '⚙️'

  function formatTriggerConfig(rule) {
    const c = rule.trigger_config || {}
    if (rule.trigger_type === 'booking_status_change') {
      return `Stav: ${c.from_status || '*'} → ${c.to_status || '*'}`
    }
    if (rule.trigger_type === 'booking_reminder') {
      return `${c.amount || '?'} ${c.unit || 'dní'} před ${c.reference === 'end' ? 'koncem' : 'začátkem'}`
    }
    if (rule.trigger_type === 'customer_inactivity') {
      return `Neaktivní ${c.days || '?'} dní`
    }
    if (rule.trigger_type === 'post_return') {
      return `${c.days || '?'} dní po vrácení`
    }
    if (rule.trigger_type === 'abandoned_booking') {
      return `${c.amount || '?'} ${c.unit || 'min'} po vytvoření`
    }
    if (rule.trigger_type === 'birthday') return 'V den narozenin'
    if (rule.trigger_type === 'registration_welcome') return 'Ihned po registraci'
    if (rule.trigger_type === 'seasonal') return c.description || 'Sezónní trigger'
    return JSON.stringify(c)
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <h2 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
            Automatické zprávy — {CHANNEL_LABELS[channel]}
          </h2>
          <Badge label={String(rules.length)} color="#1a2e22" bg="#f1faf7" />
        </div>
        <Button green onClick={() => { setEditing(null); setShowCreate(true) }}>
          + Přidat automatickou zprávu
        </Button>
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : rules.length === 0 ? (
        <div className="text-center py-16">
          <div style={{ fontSize: 48, marginBottom: 12 }}>🤖</div>
          <div style={{ color: '#1a2e22', fontSize: 14, fontWeight: 700 }}>
            Zatím žádné automatické zprávy pro {CHANNEL_LABELS[channel]}.
          </div>
          <div style={{ color: '#6b7280', fontSize: 13, marginTop: 4 }}>
            Vytvořte pravidlo, které automaticky odešle zprávu při splnění podmínky.
          </div>
        </div>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Název</TH>
              <TH>Trigger</TH>
              <TH>Podmínka</TH>
              <TH>Šablona</TH>
              <TH>Stav</TH>
              <TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {rules.map(rule => (
              <TRow key={rule.id}>
                <TD bold>{rule.name || '—'}</TD>
                <TD>
                  <span style={{ marginRight: 4 }}>{triggerIcon(rule.trigger_type)}</span>
                  {triggerLabel(rule.trigger_type)}
                </TD>
                <TD><span style={{ fontSize: 12, color: '#1a2e22' }}>{formatTriggerConfig(rule)}</span></TD>
                <TD>
                  {rule.template_slug
                    ? <Badge label={rule.template_slug} color="#1a2e22" bg="#f1faf7" />
                    : <span style={{ color: '#6b7280', fontSize: 12 }}>Vlastní text</span>
                  }
                </TD>
                <TD>
                  <Badge
                    label={rule.is_active ? 'Aktivní' : 'Neaktivní'}
                    color={rule.is_active ? '#1a8a18' : '#6b7280'}
                    bg={rule.is_active ? '#dcfce7' : '#f3f4f6'}
                  />
                </TD>
                <TD>
                  <div className="flex gap-1.5">
                    <button
                      onClick={() => { setEditing(rule); setShowCreate(true) }}
                      className="text-sm font-bold cursor-pointer border-none rounded-btn"
                      style={{ padding: '4px 10px', background: '#f1faf7', color: '#1a2e22' }}
                    >
                      Upravit
                    </button>
                    <button
                      onClick={() => setConfirm({ rule, action: 'toggle' })}
                      className="text-sm font-bold cursor-pointer border-none rounded-btn"
                      style={{
                        padding: '4px 10px',
                        background: rule.is_active ? '#fee2e2' : '#dcfce7',
                        color: rule.is_active ? '#dc2626' : '#1a8a18',
                      }}
                    >
                      {rule.is_active ? 'Vypnout' : 'Zapnout'}
                    </button>
                    <button
                      onClick={() => setConfirm({ rule, action: 'delete' })}
                      className="text-sm font-bold cursor-pointer border-none rounded-btn"
                      style={{ padding: '4px 10px', background: '#fee2e2', color: '#dc2626' }}
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

      {/* Create / Edit modal */}
      {showCreate && (
        <AutoRuleModal
          channel={channel}
          rule={editing}
          templates={templates}
          onClose={() => setShowCreate(false)}
          onSaved={() => { setShowCreate(false); load() }}
        />
      )}

      {/* Confirm dialog */}
      <ConfirmDialog
        open={!!confirm}
        title={confirm?.action === 'delete' ? 'Smazat pravidlo?' : (confirm?.rule?.is_active ? 'Vypnout pravidlo?' : 'Zapnout pravidlo?')}
        message={confirm?.action === 'delete'
          ? `Opravdu smazat pravidlo "${confirm?.rule?.name}"? Tuto akci nelze vrátit.`
          : confirm?.rule?.is_active
            ? `Vypnout automatickou zprávu "${confirm?.rule?.name}"?`
            : `Zapnout automatickou zprávu "${confirm?.rule?.name}"?`
        }
        danger={confirm?.action === 'delete' || confirm?.rule?.is_active}
        onConfirm={() => {
          if (!confirm) return
          if (confirm.action === 'delete') handleDelete(confirm.rule)
          else handleToggle(confirm.rule)
        }}
        onCancel={() => setConfirm(null)}
      />
    </div>
  )
}

/* ────────────────── Auto Rule Create/Edit Modal ────────────────── */

function AutoRuleModal({ channel, rule, templates, onClose, onSaved }) {
  const isNew = !rule
  const [name, setName] = useState(rule?.name || '')
  const [triggerType, setTriggerType] = useState(rule?.trigger_type || '')
  const [triggerConfig, setTriggerConfig] = useState(rule?.trigger_config || {})
  const [useTemplate, setUseTemplate] = useState(rule?.template_id ? true : false)
  const [templateId, setTemplateId] = useState(rule?.template_id || '')
  const [customBody, setCustomBody] = useState(rule?.custom_body || '')
  const [isActive, setIsActive] = useState(rule?.is_active ?? true)
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  function updateConfig(key, val) {
    setTriggerConfig(prev => ({ ...prev, [key]: val }))
  }

  const selectedTemplate = templates.find(t => t.id === templateId)

  async function handleSave() {
    if (!name.trim() || !triggerType) return
    setSaving(true)
    setErr(null)
    try {
      const payload = {
        name: name.trim(),
        channel,
        trigger_type: triggerType,
        trigger_config: triggerConfig,
        template_id: useTemplate && templateId ? templateId : null,
        template_slug: useTemplate && selectedTemplate ? selectedTemplate.slug : null,
        custom_body: !useTemplate ? customBody : null,
        is_active: isActive,
      }

      if (isNew) {
        const { error } = await supabase.from('automation_rules').insert(payload)
        if (error) throw error
      } else {
        const { error } = await supabase.from('automation_rules').update(payload).eq('id', rule.id)
        if (error) throw error
      }

      onSaved()
    } catch (e) {
      debugError('AutoRuleModal', 'save', e)
      setErr(e.message || 'Nepodařilo se uložit')
    }
    setSaving(false)
  }

  const canSave = name.trim() && triggerType && (useTemplate ? !!templateId : customBody.trim()) && !saving

  return (
    <Modal open title={isNew ? 'Nová automatická zpráva' : `Upravit: ${rule.name}`} onClose={onClose} wide>
      <div className="space-y-4">
        {/* Název */}
        <div>
          <Label>Název pravidla *</Label>
          <input
            type="text"
            value={name}
            onChange={e => setName(e.target.value)}
            placeholder="Např. Připomínka den před půjčením"
            className="w-full rounded-btn text-sm outline-none"
            style={inputStyle}
          />
        </div>

        {/* Trigger type */}
        <div>
          <Label>Trigger (spouštěč) *</Label>
          <div className="grid grid-cols-2 gap-2">
            {TRIGGER_TYPES.map(t => (
              <div
                key={t.value}
                onClick={() => { setTriggerType(t.value); setTriggerConfig({}) }}
                className="cursor-pointer rounded-card"
                style={{
                  padding: 10,
                  border: triggerType === t.value ? '2px solid #74FB71' : '2px solid #d4e8e0',
                  background: triggerType === t.value ? '#f0fdf0' : '#fff',
                }}
              >
                <div className="flex items-center gap-2 mb-0.5">
                  <span style={{ fontSize: 16 }}>{t.icon}</span>
                  <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{t.label}</span>
                </div>
                <div style={{ fontSize: 11, color: '#6b7280' }}>{t.desc}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Trigger config — context-sensitive */}
        {triggerType === 'booking_status_change' && (
          <div className="flex gap-3">
            <div className="flex-1">
              <Label>Ze stavu</Label>
              <select value={triggerConfig.from_status || ''} onChange={e => updateConfig('from_status', e.target.value)}
                className="w-full rounded-btn text-sm outline-none cursor-pointer" style={{ ...inputStyle, color: '#1a2e22' }}>
                <option value="">Jakýkoliv</option>
                {BOOKING_STATUSES.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
              </select>
            </div>
            <div className="flex items-end pb-2 text-lg font-bold" style={{ color: '#1a2e22' }}>→</div>
            <div className="flex-1">
              <Label>Na stav *</Label>
              <select value={triggerConfig.to_status || ''} onChange={e => updateConfig('to_status', e.target.value)}
                className="w-full rounded-btn text-sm outline-none cursor-pointer" style={{ ...inputStyle, color: '#1a2e22' }}>
                <option value="">— Vyberte —</option>
                {BOOKING_STATUSES.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
              </select>
            </div>
          </div>
        )}

        {triggerType === 'booking_reminder' && (
          <div className="flex gap-3 items-end">
            <div>
              <Label>Kolik</Label>
              <input type="number" min="1" value={triggerConfig.amount || ''} onChange={e => updateConfig('amount', Number(e.target.value))}
                className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 80 }} />
            </div>
            <div>
              <Label>Jednotka</Label>
              <select value={triggerConfig.unit || 'days'} onChange={e => updateConfig('unit', e.target.value)}
                className="rounded-btn text-sm outline-none cursor-pointer" style={{ ...inputStyle, color: '#1a2e22' }}>
                {TIME_UNITS.map(u => <option key={u.value} value={u.value}>{u.label}</option>)}
              </select>
            </div>
            <div>
              <Label>Před</Label>
              <select value={triggerConfig.reference || 'start'} onChange={e => updateConfig('reference', e.target.value)}
                className="rounded-btn text-sm outline-none cursor-pointer" style={{ ...inputStyle, color: '#1a2e22' }}>
                <option value="start">začátkem</option>
                <option value="end">koncem</option>
              </select>
            </div>
          </div>
        )}

        {triggerType === 'customer_inactivity' && (
          <div className="flex gap-3 items-end">
            <div>
              <Label>Neaktivní po</Label>
              <input type="number" min="1" value={triggerConfig.days || ''} onChange={e => updateConfig('days', Number(e.target.value))}
                className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 80 }} placeholder="30" />
            </div>
            <span className="text-sm font-bold pb-2" style={{ color: '#1a2e22' }}>dní od poslední rezervace</span>
          </div>
        )}

        {triggerType === 'post_return' && (
          <div className="flex gap-3 items-end">
            <div>
              <Label>Odeslat po</Label>
              <input type="number" min="1" value={triggerConfig.days || ''} onChange={e => updateConfig('days', Number(e.target.value))}
                className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 80 }} placeholder="3" />
            </div>
            <span className="text-sm font-bold pb-2" style={{ color: '#1a2e22' }}>dnech po vrácení motorky</span>
          </div>
        )}

        {triggerType === 'abandoned_booking' && (
          <div className="flex gap-3 items-end">
            <div>
              <Label>Po</Label>
              <input type="number" min="1" value={triggerConfig.amount || ''} onChange={e => updateConfig('amount', Number(e.target.value))}
                className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 80 }} placeholder="30" />
            </div>
            <div>
              <select value={triggerConfig.unit || 'minutes'} onChange={e => updateConfig('unit', e.target.value)}
                className="rounded-btn text-sm outline-none cursor-pointer" style={{ ...inputStyle, color: '#1a2e22' }}>
                {TIME_UNITS.map(u => <option key={u.value} value={u.value}>{u.label}</option>)}
              </select>
            </div>
            <span className="text-sm font-bold pb-2" style={{ color: '#1a2e22' }}>bez platby</span>
          </div>
        )}

        {triggerType === 'seasonal' && (
          <div>
            <Label>Popis (kdy se má spustit)</Label>
            <input type="text" value={triggerConfig.description || ''} onChange={e => updateConfig('description', e.target.value)}
              placeholder="Např. Začátek sezóny - 1. dubna"
              className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          </div>
        )}

        {/* Zpráva: ze šablony nebo vlastní */}
        <div>
          <Label>Obsah zprávy</Label>
          <div className="flex gap-3 mb-3">
            <label className="flex items-center gap-2 cursor-pointer rounded-btn"
              style={{ padding: '6px 12px', background: useTemplate ? '#e8fee7' : '#f1faf7', border: useTemplate ? '1px solid #74FB71' : '1px solid #d4e8e0' }}>
              <input type="radio" checked={useTemplate} onChange={() => setUseTemplate(true)} className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Ze šablony</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer rounded-btn"
              style={{ padding: '6px 12px', background: !useTemplate ? '#e8fee7' : '#f1faf7', border: !useTemplate ? '1px solid #74FB71' : '1px solid #d4e8e0' }}>
              <input type="radio" checked={!useTemplate} onChange={() => setUseTemplate(false)} className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Vlastní text</span>
            </label>
          </div>

          {useTemplate ? (
            <div>
              <select value={templateId} onChange={e => setTemplateId(e.target.value)}
                className="w-full rounded-btn text-sm outline-none cursor-pointer"
                style={{ ...inputStyle, color: '#1a2e22' }}>
                <option value="">— Vyberte šablonu —</option>
                {templates.map(t => <option key={t.id} value={t.id}>{t.name} ({t.slug})</option>)}
              </select>
              {selectedTemplate && (
                <div className="mt-2 rounded-card" style={{ padding: 10, background: '#f8fcfa', border: '1px solid #d4e8e0', fontSize: 12, whiteSpace: 'pre-wrap', maxHeight: 120, overflow: 'auto', color: '#1a2e22' }}>
                  {selectedTemplate.body_template || selectedTemplate.content || '(prázdná)'}
                </div>
              )}
            </div>
          ) : (
            <textarea
              value={customBody}
              onChange={e => setCustomBody(e.target.value)}
              placeholder="Text automatické zprávy… Použijte {{customer_name}}, {{motorcycle}}, atd."
              className="w-full rounded-btn text-sm outline-none"
              style={{ ...inputStyle, minHeight: 100, resize: 'vertical' }}
            />
          )}
        </div>

        {/* Aktivní */}
        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={isActive} onChange={e => setIsActive(e.target.checked)}
            className="accent-[#1a8a18]" style={{ width: 16, height: 16 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Aktivní (pravidlo bude zpracováváno)</span>
        </label>

        {err && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{err}</div>}
      </div>

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
