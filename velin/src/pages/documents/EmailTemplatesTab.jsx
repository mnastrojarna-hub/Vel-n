import { useState, useEffect, useRef, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Badge from '../../components/ui/Badge'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

const SAMPLE_VARS = {
  booking_number: 'A1B2C3D4', customer_name: ' Jan Novák', moto_model: 'BMW R 1200 GS Adventure',
  motorcycle: 'BMW R 1200 GS Adventure', start_date: '15. 6. 2026', end_date: '18. 6. 2026',
  total_price: '7 800', pickup_location: 'Mezná 9, 393 01 Mezná',
  resume_link: 'https://motogo24.cz/#/rezervace?resume=abc123',
  voucher_code: 'MGABC123 (3 000 Kč)', voucher_amount: '3 000', voucher_value: '3 000',
  voucher_expiry: '15. 6. 2029', order_number: 'OBJ-2026-01001', discount_code: 'DIKY200',
  google_review_url: 'https://g.page/MotoGo24/review', facebook_review_url: 'https://facebook.com/MotoGo24/reviews',
  site_url: 'https://motogo24.cz', price_difference: '-1 200',
  invoice_number: 'ZF-2026-0001', invoice_type: 'Zálohová faktura',
  issue_date: '15. 6. 2026', due_date: '29. 6. 2026', variable_symbol: 'ZF-2026-0001',
}

const EMAIL_STATUS = {
  sent: { label: 'Odesláno', color: '#1a8a18', bg: '#dcfce7' },
  failed: { label: 'Chyba', color: '#dc2626', bg: '#fee2e2' },
  queued: { label: 'Ve frontě', color: '#b45309', bg: '#fef3c7' },
  bounced: { label: 'Nedoručeno', color: '#1a2e22', bg: '#f3f4f6' },
}

/** Metadata pro každý slug — kategorie, trigger, přílohy, popis */
const TEMPLATE_META = {
  booking_reserved: {
    category: 'reservation', categoryLabel: 'Rezervace',
    trigger: 'Stripe webhook po platbě',
    attachments: 'ZF, DP, Smlouva, VOP',
    info: 'Odesílá se automaticky zákazníkovi po úspěšné platbě rezervace (web i app). Obsahuje informace k převzetí motorky.',
  },
  booking_abandoned: {
    category: 'reservation', categoryLabel: 'Rezervace',
    trigger: 'Auto-cancel po 4h (web)',
    attachments: 'ZF',
    info: 'Odesílá se automaticky když zákazník na webu nedokončí platbu do 4 hodin. Obsahuje CTA tlačítko pro dokončení.',
  },
  booking_cancelled: {
    category: 'storno', categoryLabel: 'Storno',
    trigger: 'Změna stavu na cancelled (app/web/velín)',
    attachments: 'Dobropis',
    info: 'Odesílá se automaticky při stornování rezervace z jakéhokoliv zdroje. Auto Stripe refund dle storno podmínek (7+ dní=100%, 2-7=50%, <2=0%).',
  },
  booking_completed: {
    category: 'reservation', categoryLabel: 'Rezervace',
    trigger: 'Změna stavu active → completed',
    attachments: 'KF (konečná faktura)',
    info: 'Odesílá se automaticky po dokončení pronájmu (vrácení motorky). Obsahuje žádost o recenzi a slevový kód na příští rezervaci.',
  },
  booking_modified: {
    category: 'reservation', categoryLabel: 'Rezervace',
    trigger: 'Úprava termínu/motorky (velín nebo app)',
    attachments: 'ZF, DP, Smlouva, VOP',
    info: 'Odesílá se při jakékoliv změně rezervace — zkrácení, prodloužení, změna motorky, změna místa přistavení. Dokumenty se regenerují s novými daty.',
  },
  voucher_purchased: {
    category: 'shop', categoryLabel: 'E-shop',
    trigger: 'Stripe webhook po platbě objednávky',
    attachments: 'ZF, DP, Voucher HTML, FV (elektronický)',
    info: 'Odesílá se po zakoupení dárkového poukazu nebo e-shop objednávky. Pro elektronické poukazy obsahuje i konečnou fakturu.',
  },
  sos_incident: {
    category: 'other', categoryLabel: 'Ostatní',
    trigger: 'Vytvoření SOS incidentu (app)',
    attachments: 'Žádné',
    info: 'Odesílá se automaticky zákazníkovi při nahlášení SOS incidentu. Obsahuje omluvu a kontakt na linku pomoci.',
  },
  invoice_advance: {
    category: 'invoice', categoryLabel: 'Faktura',
    trigger: 'Ruční odeslání z Velínu / automaticky',
    attachments: 'Faktura HTML v příloze',
    info: 'E-mail se zálohovou fakturou (ZF/proforma). Odesílá se s fakturou v příloze.',
  },
  invoice_payment_receipt: {
    category: 'invoice', categoryLabel: 'Faktura',
    trigger: 'Ruční odeslání z Velínu / automaticky',
    attachments: 'Doklad HTML v příloze',
    info: 'E-mail s dokladem o přijaté platbě (DP). Odesílá se s dokladem v příloze.',
  },
  invoice_final: {
    category: 'invoice', categoryLabel: 'Faktura',
    trigger: 'Dokončení pronájmu / ruční odeslání',
    attachments: 'Faktura HTML v příloze',
    info: 'E-mail s konečnou fakturou (FV/KF). Odesílá se po dokončení pronájmu nebo ručně z Velínu.',
  },
  invoice_shop_final: {
    category: 'invoice', categoryLabel: 'Faktura',
    trigger: 'Odeslání zboží z Velínu (shipped/delivered)',
    attachments: 'Faktura HTML v příloze',
    info: 'E-mail s konečnou fakturou za e-shop objednávku. Odesílá se při expedici fyzického zboží nebo poukazu z Velínu.',
  },
  // Web varianty
  web_booking_reserved: { category: 'reservation', categoryLabel: 'Rezervace', trigger: 'Web platba', attachments: 'ZF, DP, Smlouva, VOP', info: 'Web varianta potvrzení rezervace. Pokud neexistuje, použije se booking_reserved.' },
  web_booking_abandoned: { category: 'reservation', categoryLabel: 'Rezervace', trigger: 'Auto-cancel web 4h', attachments: 'ZF', info: 'Web varianta nedokončené rezervace. Pokud neexistuje, použije se booking_abandoned.' },
  web_booking_cancelled: { category: 'storno', categoryLabel: 'Storno', trigger: 'Storno web rezervace', attachments: 'Dobropis', info: 'Web varianta storna. Pokud neexistuje, použije se booking_cancelled.' },
  web_booking_completed: { category: 'reservation', categoryLabel: 'Rezervace', trigger: 'Dokončení web pronájmu', attachments: 'KF', info: 'Web varianta dokončení. Pokud neexistuje, použije se booking_completed.' },
  web_voucher_purchased: { category: 'shop', categoryLabel: 'E-shop', trigger: 'Web nákup poukazu', attachments: 'ZF, DP, Voucher, FV', info: 'Web varianta nákupu poukazu. Pokud neexistuje, použije se voucher_purchased.' },
}

const CATEGORIES = [
  { value: 'reservation', label: 'Rezervace', color: '#2563eb', bg: '#dbeafe' },
  { value: 'storno', label: 'Storno', color: '#dc2626', bg: '#fee2e2' },
  { value: 'invoice', label: 'Faktura', color: '#b45309', bg: '#fef3c7' },
  { value: 'shop', label: 'E-shop', color: '#7c3aed', bg: '#ede9fe' },
  { value: 'other', label: 'Ostatní', color: '#1a2e22', bg: '#f3f4f6' },
]

function getTemplateMeta(slug) {
  return TEMPLATE_META[slug] || { category: 'other', categoryLabel: 'Ostatní', trigger: '—', attachments: '—', info: '' }
}

export default function EmailTemplatesTab() {
  const [templates, setTemplates] = useState([])
  const [sentEmails, setSentEmails] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [editing, setEditing] = useState(null)
  const defaultFilters = { search: '', statuses: [], categories: [] }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_emailtemplates_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_emailtemplates_filters', JSON.stringify(filters)) }, [filters])

  useEffect(() => { load(); loadSent() }, [])

  async function load() {
    setLoading(true)
    try {
      const { data, error: err } = await supabase.from('email_templates').select('*').order('name')
      if (err) throw err
      setTemplates(data || [])
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function loadSent() {
    try {
      const { data } = await supabase.from('sent_emails').select('*').order('created_at', { ascending: false }).limit(30)
      setSentEmails(data || [])
    } catch {}
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (error) return <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>

  const filteredTemplates = templates.filter(t => {
    const meta = getTemplateMeta(t.slug)
    if (filters.categories?.length > 0 && !filters.categories.includes(meta.category)) return false
    if (filters.search) {
      const s = filters.search.toLowerCase()
      if (!(t.name || '').toLowerCase().includes(s) && !(t.slug || '').toLowerCase().includes(s) && !(t.description || '').toLowerCase().includes(s) && !(meta.info || '').toLowerCase().includes(s)) return false
    }
    return true
  })

  const filteredEmails = sentEmails.filter(e => {
    if (filters.statuses?.length > 0 && !filters.statuses.includes(e.status)) return false
    if (filters.search) {
      const s = filters.search.toLowerCase()
      if (!(e.recipient_email || '').toLowerCase().includes(s) && !(e.subject || '').toLowerCase().includes(s) && !(e.template_slug || '').toLowerCase().includes(s)) return false
    }
    return true
  })

  // Group templates by category
  const grouped = {}
  filteredTemplates.forEach(t => {
    const meta = getTemplateMeta(t.slug)
    if (!grouped[meta.category]) grouped[meta.category] = []
    grouped[meta.category].push(t)
  })

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <input type="text" value={filters.search} onChange={e => setFilters(f => ({ ...f, search: e.target.value }))}
          placeholder="Hledat šablonu, e-mail…"
          className="rounded-btn text-sm outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', minWidth: 200 }} />
        <CheckboxFilterGroup label="Kategorie" values={filters.categories || []}
          onChange={v => setFilters(f => ({ ...f, categories: v }))}
          options={CATEGORIES.map(c => ({ value: c.value, label: c.label }))} />
        <CheckboxFilterGroup label="Stav" values={filters.statuses || []}
          onChange={v => setFilters(f => ({ ...f, statuses: v }))}
          options={[{ value: 'sent', label: 'Odesláno' }, { value: 'failed', label: 'Chyba' }, { value: 'queued', label: 'Ve frontě' }]} />
        {(filters.search || filters.statuses?.length > 0 || filters.categories?.length > 0) && (
          <button onClick={() => { setFilters({ ...defaultFilters }); localStorage.removeItem('velin_emailtemplates_filters') }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
            Reset
          </button>
        )}
      </div>

      {filteredTemplates.length === 0 ? (
        <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné e-mailové šablony odpovídající filtru</p></Card>
      ) : (
        CATEGORIES.filter(c => grouped[c.value]?.length > 0).map(cat => (
          <div key={cat.value} className="mb-6">
            <div className="flex items-center gap-2 mb-3">
              <span className="inline-block rounded-btn text-xs font-extrabold uppercase tracking-wide"
                style={{ padding: '4px 10px', background: cat.bg, color: cat.color }}>{cat.label}</span>
              <span className="text-sm" style={{ color: '#6b7280' }}>{grouped[cat.value].length} {grouped[cat.value].length === 1 ? 'šablona' : grouped[cat.value].length < 5 ? 'šablony' : 'šablon'}</span>
            </div>
            <div className="grid grid-cols-2 gap-4">
              {grouped[cat.value].map(t => (
                <TemplateCard key={t.id} template={t} onEdit={() => setEditing(t)} />
              ))}
            </div>
          </div>
        ))
      )}

      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3 mt-8" style={{ color: '#1a2e22' }}>Poslední odeslané e-maily</h3>
      <SentEmailsTable emails={filteredEmails} />

      {editing && (
        <EditEmailTemplateModal
          template={editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load() }}
        />
      )}
    </div>
  )
}

function TemplateCard({ template, onEdit }) {
  const vars = template.variables || extractVars(template.body_html)
  const meta = getTemplateMeta(template.slug)
  const catDef = CATEGORIES.find(c => c.value === meta.category) || CATEGORIES[4]

  return (
    <Card>
      <div className="flex items-center justify-between mb-1">
        <h4 className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{template.name}</h4>
        <div className="flex items-center gap-1">
          <Badge label={catDef.label} color={catDef.color} bg={catDef.bg} />
          <Badge label={template.active ? 'Aktivní' : 'Neaktivní'} color={template.active ? '#1a8a18' : '#6b7280'} bg={template.active ? '#dcfce7' : '#f3f4f6'} />
        </div>
      </div>
      <div className="text-xs font-mono mb-2" style={{ color: '#6b7280' }}>{template.slug}</div>

      {/* Info box */}
      <div className="rounded-btn text-xs mb-2" style={{ padding: '8px 10px', background: '#f8faf9', border: '1px solid #e5e7eb', lineHeight: 1.6, color: '#374151' }}>
        {meta.info && <div className="mb-1">{meta.info}</div>}
        <div className="flex flex-wrap gap-x-4 gap-y-1 mt-1" style={{ fontSize: 11 }}>
          <span><strong style={{ color: '#1a2e22' }}>Trigger:</strong> {meta.trigger}</span>
          <span><strong style={{ color: '#1a2e22' }}>Přílohy:</strong> {meta.attachments}</span>
        </div>
      </div>

      {vars.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-2">
          {vars.map(v => (
            <span key={v} className="inline-block rounded-btn text-[9px] font-mono font-bold"
              style={{ padding: '2px 6px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
              {`{{${v}}}`}
            </span>
          ))}
        </div>
      )}
      <Button onClick={onEdit} style={{ padding: '4px 14px', fontSize: 13 }}>Upravit</Button>
    </Card>
  )
}

function extractVars(content) {
  if (!content) return []
  const matches = content.match(/\{\{(\w+)\}\}/g)
  return matches ? [...new Set(matches.map(m => m.replace(/[{}]/g, '')))] : []
}

function SentEmailsTable({ emails }) {
  if (emails.length === 0) return <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné odeslané e-maily</p></Card>
  return (
    <Table>
      <thead><TRow header><TH>Příjemce</TH><TH>Šablona</TH><TH>Předmět</TH><TH>Stav</TH><TH>Datum</TH></TRow></thead>
      <tbody>
        {emails.map(e => {
          const st = EMAIL_STATUS[e.status] || EMAIL_STATUS.queued
          return (
            <TRow key={e.id}>
              <TD>{e.recipient_email || '—'}</TD>
              <TD><span className="font-mono text-xs">{e.template_slug || '—'}</span></TD>
              <TD>{e.subject || '—'}</TD>
              <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
              <TD>{e.created_at ? new Date(e.created_at).toLocaleString('cs-CZ') : '—'}</TD>
            </TRow>
          )
        })}
      </tbody>
    </Table>
  )
}

function EditEmailTemplateModal({ template, onClose, onSaved }) {
  const [name, setName] = useState(template.name || '')
  const [subject, setSubject] = useState(template.subject || '')
  const [bodyHtml, setBodyHtml] = useState(template.body_html || '')
  const [active, setActive] = useState(template.active ?? true)
  const [saving, setSaving] = useState(false)
  const [testing, setTesting] = useState(false)
  const [err, setErr] = useState(null)
  const [showPreview, setShowPreview] = useState(false)
  const [dragOver, setDragOver] = useState(false)
  const textareaRef = useRef(null)
  const fileInputRef = useRef(null)
  const meta = getTemplateMeta(template.slug)

  const vars = template.variables || extractVars(bodyHtml)

  function insertVariable(varName) {
    const ta = textareaRef.current; if (!ta) return
    const start = ta.selectionStart; const end = ta.selectionEnd
    const tag = `{{${varName}}}`
    const newVal = bodyHtml.slice(0, start) + tag + bodyHtml.slice(end)
    setBodyHtml(newVal)
    setTimeout(() => { ta.focus(); ta.selectionStart = ta.selectionEnd = start + tag.length }, 0)
  }

  const handleFileDrop = useCallback((e) => {
    e.preventDefault(); setDragOver(false)
    const file = e.dataTransfer?.files?.[0] || e.target?.files?.[0]
    if (!file) return
    if (file.name.endsWith('.html') || file.name.endsWith('.htm') || file.type === 'text/html') {
      const reader = new FileReader()
      reader.onload = (ev) => setBodyHtml(ev.target.result)
      reader.readAsText(file)
    } else { setErr('Podporované formáty: .html, .htm') }
  }, [])

  function getPreviewHtml() {
    let html = bodyHtml
    for (const [k, v] of Object.entries(SAMPLE_VARS)) html = html.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), v)
    return html
  }

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const updatePayload = { name, subject, body_html: bodyHtml, active, updated_by: user?.id }
      const result = await debugAction('emailTemplate.update', 'EditEmailTemplateModal', () =>
        supabase.from('email_templates').update(updatePayload).eq('id', template.id)
      , updatePayload)
      if (result?.error) throw result.error
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'email_template_updated', details: { template_id: template.id } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  async function handleTestSend() {
    setTesting(true); setErr(null)
    try {
      const result = await debugAction('emailTemplate.testSend', 'EditEmailTemplateModal', () =>
        supabase.functions.invoke('send-email', { body: { template_slug: template.slug, test: true } })
      , { template_slug: template.slug, test: true })
      if (result?.error) throw result.error
    } catch (e) { setErr(`Test e-mail se nepodařilo odeslat: ${e.message || 'Edge Function nemusí být nasazena.'}`) }
    setTesting(false)
  }

  return (
    <Modal open title={`Upravit: ${template.name}`} onClose={onClose} wide>
      {/* Info panel */}
      <div className="rounded-btn mb-4" style={{ padding: '12px 14px', background: '#f8faf9', border: '1px solid #d4e8e0' }}>
        <div className="text-sm mb-1" style={{ color: '#374151', lineHeight: 1.6 }}>{meta.info}</div>
        <div className="flex flex-wrap gap-x-4 gap-y-1" style={{ fontSize: 12 }}>
          <span><strong style={{ color: '#1a2e22' }}>Trigger:</strong> {meta.trigger}</span>
          <span><strong style={{ color: '#1a2e22' }}>Přílohy:</strong> {meta.attachments}</span>
          <span><strong style={{ color: '#1a2e22' }}>Slug:</strong> <code style={{ background: '#e5e7eb', padding: '1px 4px', borderRadius: 4 }}>{template.slug}</code></span>
        </div>
      </div>

      <div className="space-y-3">
        <div><Label>Název</Label><input type="text" value={name} onChange={e => setName(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Předmět</Label><input type="text" value={subject} onChange={e => setSubject(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>

        <div className="rounded-lg text-center cursor-pointer transition-colors"
          style={{ padding: '16px', border: `2px dashed ${dragOver ? '#74FB71' : '#d4e8e0'}`, background: dragOver ? '#f0fff4' : '#f9fdfb' }}
          onDragOver={e => { e.preventDefault(); setDragOver(true) }} onDragLeave={() => setDragOver(false)}
          onDrop={handleFileDrop} onClick={() => fileInputRef.current?.click()}>
          <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>Přetáhněte HTML soubor sem nebo klikněte pro výběr</div>
          <div className="text-xs mt-1" style={{ color: '#6b7280' }}>Podporované formáty: .html, .htm</div>
          <input ref={fileInputRef} type="file" accept=".html,.htm" onChange={handleFileDrop} className="hidden" />
        </div>

        <div><Label>HTML tělo</Label>
          <textarea ref={textareaRef} value={bodyHtml} onChange={e => setBodyHtml(e.target.value)}
            className="w-full rounded-btn text-sm outline-none font-mono"
            style={{ ...inputStyle, minHeight: 300, resize: 'vertical' }} />
        </div>
        {vars.length > 0 && (
          <div>
            <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Vložit proměnnou:</span>
            <div className="flex flex-wrap gap-1 mt-1">
              {vars.map(v => (
                <button key={v} onClick={() => insertVariable(v)}
                  className="rounded-btn text-[9px] font-mono font-bold cursor-pointer"
                  style={{ padding: '3px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#2563eb' }}>
                  {`{{${v}}}`}
                </button>
              ))}
            </div>
          </div>
        )}
        <div className="flex items-center gap-2">
          <input type="checkbox" checked={active} onChange={e => setActive(e.target.checked)} id="tpl-active" />
          <label htmlFor="tpl-active" className="text-sm font-bold" style={{ color: '#1a2e22' }}>Aktivní</label>
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-between gap-3 mt-5">
        <div className="flex gap-2">
          <Button onClick={() => setShowPreview(true)}>Náhled</Button>
          <Button onClick={handleTestSend} disabled={testing}>{testing ? 'Odesílám…' : 'Odeslat test'}</Button>
        </div>
        <div className="flex gap-2">
          <Button onClick={onClose}>Zrušit</Button>
          <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
        </div>
      </div>

      {showPreview && (
        <Modal open title="Náhled e-mailu" onClose={() => setShowPreview(false)} wide>
          <div className="text-sm font-bold mb-2" style={{ color: '#1a2e22' }}>
            Předmět: {subject.replace(/\{\{(\w+)\}\}/g, (_, k) => SAMPLE_VARS[k] || `{{${k}}}`)}
          </div>
          <div className="rounded-card" style={{ padding: 16, background: '#fff', border: '1px solid #d4e8e0', maxHeight: 500, overflow: 'auto' }}
            dangerouslySetInnerHTML={{ __html: getPreviewHtml() }} />
          <div className="flex justify-end mt-4"><Button onClick={() => setShowPreview(false)}>Zavřít</Button></div>
        </Modal>
      )}
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => {
    if (values.includes(val)) onChange(values.filter(v => v !== val))
    else onChange([...values, val])
  }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn"
      style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer"
          style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)}
            className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}
