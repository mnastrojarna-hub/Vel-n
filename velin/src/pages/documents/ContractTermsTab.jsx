import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import RichTextEditor, { buildPreviewHtml } from '../../components/ui/RichTextEditor'
import CustomDocumentsSection from './CustomDocumentsSection'
import { translateDocument, TRANSLATE_TARGET_LANGS } from '../../lib/autoTranslate'

const CONTRACT_TYPES = [
  { type: 'vop', label: 'Obchodní podmínky (VOP)', icon: '📜', description: 'Všeobecné obchodní podmínky pro pronájem motocyklů' },
  { type: 'rental_contract', label: 'Nájemní smlouva', icon: '📋', description: 'Smlouva o pronájmu motocyklu s automatickým vyplněním údajů' },
  { type: 'handover_protocol', label: 'Předávací protokol', icon: '📝', description: 'Protokol o předání motocyklu včetně výbavových položek' },
  { type: 'damage_protocol', label: 'Protokol o poškození', icon: '⚠️', description: 'Protokol o poškození motocyklu při vrácení (závady, fotodokumentace, odhad nákladů)' },
  { type: 'gdpr', label: 'GDPR — souhlas se zpracováním', icon: '🔒', description: 'Informace a souhlas zákazníka se zpracováním osobních údajů (GDPR)' },
]

const TEMPLATE_VARS = {
  vop: [
    'customer_name', 'today', 'booking_number',
    'company_name', 'company_address', 'company_ico', 'company_dic',
  ],
  rental_contract: [
    'customer_name', 'customer_address', 'customer_id_number', 'customer_id_expiry',
    'customer_license', 'customer_license_expiry', 'customer_license_group',
    'customer_phone', 'customer_email', 'customer_dob',
    'moto_model', 'moto_brand', 'moto_spz', 'moto_vin', 'moto_year',
    'moto_engine', 'moto_power', 'moto_color', 'moto_category',
    'start_date', 'start_time', 'end_date', 'end_time',
    'rental_period', 'days', 'daily_rate',
    'total_price', 'total_price_words', 'rental_price',
    'extras_price', 'extras_list', 'delivery_fee', 'deposit', 'insurance',
    'pickup_location', 'pickup_method', 'return_location', 'return_method',
    'branch_name', 'branch_address',
    'today', 'booking_number',
    'company_name', 'company_address', 'company_ico', 'company_dic',
  ],
  handover_protocol: [
    'booking_number', 'customer_name', 'customer_id_number', 'customer_license',
    'moto_model', 'moto_brand', 'moto_spz', 'moto_vin',
    'start_date', 'end_date', 'today',
  ],
  damage_protocol: [
    'booking_number', 'customer_name', 'customer_id_number',
    'moto_model', 'moto_brand', 'moto_spz', 'moto_vin',
    'end_date', 'today', 'today_time', 'mileage', 'accessories',
    'company_name', 'company_address', 'company_ico', 'company_dic',
  ],
  gdpr: [
    'customer_name', 'customer_address', 'customer_email', 'today',
    'company_name', 'company_address', 'company_ico', 'company_dic',
  ],
}

export default function ContractTermsTab() {
  const [templates, setTemplates] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [editing, setEditing] = useState(null)
  const [preview, setPreview] = useState(null)
  const [translatingType, setTranslatingType] = useState(null)
  const [trMsg, setTrMsg] = useState({}) // type -> { ok, text }

  async function handleTranslate(tpl) {
    if (!tpl?.id) return
    setTranslatingType(tpl.type)
    setTrMsg(m => ({ ...m, [tpl.type]: null }))
    const res = await translateDocument({ table: 'document_templates', id: tpl.id })
    setTranslatingType(null)
    if (res?.success) {
      const langs = Object.keys(res.translations || {})
      const failed = res.errors ? Object.keys(res.errors) : []
      setTrMsg(m => ({ ...m, [tpl.type]: { ok: failed.length === 0, text: failed.length ? `Přeloženo: ${langs.join(', ')} · selhalo: ${failed.join(', ')}` : `Přeloženo do: ${langs.join(', ')}` } }))
      load()
    } else {
      setTrMsg(m => ({ ...m, [tpl.type]: { ok: false, text: 'Překlad selhal: ' + (res?.error || 'neznámá chyba') } }))
    }
  }

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true); setError(null)
    const { data, error: err } = await supabase
      .from('document_templates')
      .select('*')
      .in('type', CONTRACT_TYPES.map(c => c.type))
      .order('type')
    if (err) setError(err.message)
    else setTemplates(data || [])
    setLoading(false)
  }

  function getTemplate(type) {
    return templates.find(t => t.type === type)
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <div className="space-y-4">
      <div className="p-3 rounded-card" style={{ background: '#f0fdf4', border: '1px solid #bbf7d0', fontSize: 12, color: '#166534' }}>
        Smluvní texty se automaticky zobrazují v zákaznické aplikaci a používají se při generování dokumentů k rezervacím. Změny se projeví okamžitě.
      </div>

      {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      <div className="grid grid-cols-1 gap-4">
        {CONTRACT_TYPES.map(ct => {
          const tpl = getTemplate(ct.type)
          const vars = TEMPLATE_VARS[ct.type] || []
          return (
            <Card key={ct.type}>
              <div className="flex items-start justify-between gap-3 flex-wrap">
                <div className="flex items-start gap-3" style={{ minWidth: 0, flex: 1 }}>
                  <span style={{ fontSize: 28 }}>{ct.icon}</span>
                  <div style={{ minWidth: 0 }}>
                    <h3 className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{ct.label}</h3>
                    <p className="text-sm mt-1" style={{ color: '#1a2e22' }}>{ct.description}</p>
                    {tpl && (
                      <div className="flex items-center gap-3 mt-2 flex-wrap">
                        <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
                          Verze {tpl.version || 1}
                        </span>
                        <span className="text-sm" style={{ color: '#1a2e22' }}>
                          Upraveno: {tpl.updated_at ? new Date(tpl.updated_at).toLocaleDateString('cs-CZ') : '—'}
                        </span>
                        {vars.length > 0 && (
                          <span className="text-sm" style={{ color: '#1a2e22' }}>
                            Proměnné: {vars.length}
                          </span>
                        )}
                        <span className="text-sm" style={{ color: '#1a2e22' }}>
                          {(() => { const ks = Object.keys(tpl.translations || {}).filter(k => TRANSLATE_TARGET_LANGS.includes(k)); return ks.length ? `🌍 přeloženo: ${ks.join(', ')}` : '🌍 jen česky' })()}
                        </span>
                      </div>
                    )}
                    {tpl && trMsg[ct.type] && <p className="text-sm mt-1" style={{ color: trMsg[ct.type].ok ? '#15803d' : '#dc2626' }}>{trMsg[ct.type].text}</p>}
                  </div>
                </div>
                <div className="flex gap-2 shrink-0">
                  {tpl && (
                    <Button onClick={() => setPreview(tpl)}>
                      Náhled
                    </Button>
                  )}
                  {tpl && (
                    <Button onClick={() => handleTranslate(tpl)} disabled={translatingType === ct.type}>
                      {translatingType === ct.type ? 'Překládám…' : '🌍 Přeložit'}
                    </Button>
                  )}
                  <Button green onClick={() => setEditing(tpl || { type: ct.type, name: ct.label, content_html: '', version: 0 })}>
                    {tpl ? 'Upravit' : 'Vytvořit'}
                  </Button>
                </div>
              </div>
              {!tpl && (
                <div className="mt-3 p-2 rounded-lg text-center" style={{ background: '#fef3c7', fontSize: 13, color: '#b45309' }}>
                  Šablona ještě nebyla vytvořena. Klikněte &quot;Vytvořit&quot; pro vložení textu.
                </div>
              )}
            </Card>
          )
        })}
      </div>

      {editing && (
        <EditContractModal
          template={editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load() }}
        />
      )}

      {preview && (
        <PreviewModal
          template={preview}
          onClose={() => setPreview(null)}
        />
      )}

      <CustomDocumentsSection />
    </div>
  )
}

function EditContractModal({ template, onClose, onSaved }) {
  const [name, setName] = useState(template.name || '')
  const [content, setContent] = useState(template.content_html || '')
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const [showPreview, setShowPreview] = useState(false)
  const isNew = !template.id
  const vars = TEMPLATE_VARS[template.type] || []

  async function safeAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch { /* audit log je best-effort, neblokuje uložení */ }
  }

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      // updated_by je FK na admin_users(id). Pokusíme se ji nastavit jen pokud
      // je uživatel reálně v admin_users (jinak by FK violation rozbila uložení).
      let updatedBy = null
      if (user?.id) {
        const { data: adminRow } = await supabase
          .from('admin_users').select('id').eq('id', user.id).maybeSingle()
        if (adminRow) updatedBy = user.id
      }

      if (isNew) {
        const payload = {
          name,
          type: template.type,
          content_html: content,
          version: 1,
          ...(updatedBy ? { updated_by: updatedBy } : {}),
        }
        const result = await debugAction('contractTemplate.create', 'EditContractModal', () =>
          supabase.from('document_templates').insert(payload).select().single()
        , { ...payload, content_html: `[${content.length} chars]` })
        if (result?.error) throw result.error
        await safeAudit('contract_template_created', { type: template.type })
      } else {
        const newVersion = (template.version || 1) + 1
        const payload = {
          name,
          content_html: content,
          version: newVersion,
          ...(updatedBy ? { updated_by: updatedBy } : {}),
        }
        // Bez .select() — vyhneme se PostgREST RETURNING přes RLS, které občas
        // u `update` vrací prázdné pole i když řádek byl změněn.
        const result = await debugAction('contractTemplate.update', 'EditContractModal', () =>
          supabase.from('document_templates').update(payload).eq('id', template.id)
        , { ...payload, content_html: `[${content.length} chars]` })
        if (result?.error) throw result.error

        // Ověření: znovu načteme řádek a zkontrolujeme, že version se navýšila.
        // Pokud ne, RLS politika UPDATE filtruje řádek nebo trigger update potlačil.
        const { data: verify, error: verifyErr } = await supabase
          .from('document_templates').select('version, name').eq('id', template.id).maybeSingle()
        if (verifyErr) throw verifyErr
        if (!verify || verify.version !== newVersion) {
          throw new Error('Šablona se neuložila. Zkontrolujte, že máte admin přístup (RLS politika `document_templates_admin`).')
        }
        await safeAudit('contract_template_updated', { template_id: template.id, type: template.type, version: newVersion })
      }
      onSaved()
    } catch (e) { setErr(e.message || String(e)) } finally { setSaving(false) }
  }

  const stickyBar = {
    position: 'sticky', bottom: -28, left: 0, right: 0,
    background: '#fff', borderTop: '1px solid #e2ece7',
    margin: '16px -28px -28px', padding: '14px 28px',
    display: 'flex', justifyContent: 'space-between', gap: 12,
    zIndex: 2,
  }

  return (
    <Modal open title={isNew ? `Vytvořit: ${name || template.type}` : `Upravit: ${name}`} onClose={onClose} wide>
      <div className="space-y-3">
        <div>
          <Label>Název</Label>
          <input type="text" value={name} onChange={e => setName(e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={inputStyle} />
        </div>

        <div>
          <Label>Obsah</Label>
          <RichTextEditor
            value={content}
            onChange={setContent}
            placeholder="Začněte psát obsah… Pomocí lišty formátujte text a z menu „+ Proměnná…“ vkládejte placeholdery."
            minHeight={360}
            maxHeight="55vh"
            variables={vars.length > 0 ? vars.map(v => ({ label: `{{${v}}}`, value: `{{${v}}}` })) : null}
          />
        </div>

        <div className="flex items-center gap-2 text-sm" style={{ color: '#1a2e22' }}>
          <span>Délka: {content.length} znaků</span>
          {vars.length > 0 && (
            <span>| Použité proměnné: {extractVars(content).length}/{vars.length}</span>
          )}
        </div>
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}

      <div style={stickyBar}>
        <Button onClick={() => setShowPreview(true)}>Náhled</Button>
        <div className="flex gap-2">
          <Button onClick={onClose}>Zrušit</Button>
          <Button green onClick={handleSave} disabled={saving || !name || !content}>
            {saving ? 'Ukládám…' : isNew ? 'Vytvořit' : 'Uložit'}
          </Button>
        </div>
      </div>

      {showPreview && (
        <Modal open title="Náhled dokumentu" onClose={() => setShowPreview(false)} wide>
          <div className="border rounded-lg overflow-hidden" style={{ background: '#fff' }}>
            <iframe
              srcDoc={buildPreviewHtml(content)}
              style={{ width: '100%', height: '70vh', border: 'none', background: '#fff', display: 'block' }}
              title="Náhled"
            />
          </div>
          <div className="flex justify-end mt-4">
            <Button onClick={() => setShowPreview(false)}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </Modal>
  )
}

function PreviewModal({ template, onClose }) {
  const previewHtml = buildPreviewHtml(template.content_html)
  return (
    <Modal open title={`Náhled: ${template.name}`} onClose={onClose} wide>
      <div className="border rounded-lg overflow-hidden" style={{ background: '#fff' }}>
        <iframe
          srcDoc={previewHtml}
          style={{ width: '100%', height: '70vh', border: 'none', background: '#fff', display: 'block' }}
          title="Náhled"
        />
      </div>
      <div className="flex justify-between mt-4">
        <Button onClick={() => {
          const win = window.open('', '_blank')
          if (win) { win.document.write(previewHtml); win.document.close(); win.onload = () => win.print() }
        }}>Tisk / PDF</Button>
        <Button onClick={onClose}>Zavřít</Button>
      </div>
    </Modal>
  )
}

function extractVars(content) {
  if (!content) return []
  const matches = content.match(/\{\{(\w+)\}\}/g)
  return matches ? [...new Set(matches.map(m => m.replace(/[{}]/g, '')))] : []
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
