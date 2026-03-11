import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'

const CONTRACT_TYPES = [
  { type: 'vop', label: 'Obchodn\u00ed podm\u00ednky (VOP)', icon: '\ud83d\udcdc', description: 'V\u0161eobecn\u00e9 obchodn\u00ed podm\u00ednky pro pron\u00e1jem motocykl\u016f' },
  { type: 'rental_contract', label: 'N\u00e1jemn\u00ed smlouva', icon: '\ud83d\udccb', description: 'Smlouva o pron\u00e1jmu motocyklu s automatick\u00fdm vypln\u011bn\u00edm \u00fadaj\u016f' },
  { type: 'handover_protocol', label: 'P\u0159ed\u00e1vac\u00ed protokol', icon: '\ud83d\udcdd', description: 'Protokol o p\u0159ed\u00e1n\u00ed motocyklu v\u010detn\u011b v\u00fdbavov\u00fdch polo\u017eek' },
]

const TEMPLATE_VARS = {
  vop: [],
  rental_contract: [
    'customer_name', 'customer_address', 'customer_id_number', 'customer_license',
    'customer_phone', 'customer_email',
    'moto_model', 'moto_spz', 'moto_vin',
    'start_date', 'start_time', 'end_date', 'end_time',
    'rental_period', 'total_price', 'total_price_words',
    'pickup_location', 'return_location',
    'today', 'booking_number',
  ],
  handover_protocol: [
    'booking_number', 'customer_name',
    'moto_model', 'moto_vin',
    'mileage', 'fuel_state', 'technical_state',
    'today', 'today_time',
  ],
}

export default function ContractTermsTab() {
  const [templates, setTemplates] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [editing, setEditing] = useState(null)
  const [preview, setPreview] = useState(null)

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
        Smluvn\u00ed texty se automaticky zobrazuj\u00ed v z\u00e1kaznick\u00e9 aplikaci a pou\u017e\u00edvaj\u00ed se p\u0159i generov\u00e1n\u00ed dokument\u016f k rezervac\u00edm. Zm\u011bny se projev\u00ed okam\u017eit\u011b.
      </div>

      {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      <div className="grid grid-cols-1 gap-4">
        {CONTRACT_TYPES.map(ct => {
          const tpl = getTemplate(ct.type)
          const vars = TEMPLATE_VARS[ct.type] || []
          return (
            <Card key={ct.type}>
              <div className="flex items-start justify-between">
                <div className="flex items-start gap-3">
                  <span style={{ fontSize: 28 }}>{ct.icon}</span>
                  <div>
                    <h3 className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>{ct.label}</h3>
                    <p className="text-sm mt-1" style={{ color: '#1a2e22' }}>{ct.description}</p>
                    {tpl && (
                      <div className="flex items-center gap-3 mt-2">
                        <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
                          Verze {tpl.version || 1}
                        </span>
                        <span className="text-sm" style={{ color: '#1a2e22' }}>
                          Upraveno: {tpl.updated_at ? new Date(tpl.updated_at).toLocaleDateString('cs-CZ') : '\u2014'}
                        </span>
                        {vars.length > 0 && (
                          <span className="text-sm" style={{ color: '#1a2e22' }}>
                            Prom\u011bnn\u00e9: {vars.length}
                          </span>
                        )}
                      </div>
                    )}
                  </div>
                </div>
                <div className="flex gap-2">
                  {tpl && (
                    <Button onClick={() => setPreview(tpl)} style={{ padding: '5px 14px', fontSize: 13 }}>
                      N\u00e1hled
                    </Button>
                  )}
                  <Button green onClick={() => setEditing(tpl || { type: ct.type, name: ct.label, content_html: '', version: 0 })}
                    style={{ padding: '5px 14px', fontSize: 13 }}>
                    {tpl ? 'Upravit' : 'Vytvo\u0159it'}
                  </Button>
                </div>
              </div>
              {!tpl && (
                <div className="mt-3 p-2 rounded-lg text-center" style={{ background: '#fef3c7', fontSize: 13, color: '#b45309' }}>
                  \u0160ablona je\u0161t\u011b nebyla vytvo\u0159ena. Klikn\u011bte &quot;Vytvo\u0159it&quot; pro vlo\u017een\u00ed textu.
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

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (isNew) {
        const payload = {
          name,
          type: template.type,
          content_html: content,
          version: 1,
          updated_by: user?.id,
        }
        const result = await debugAction('contractTemplate.create', 'EditContractModal', () =>
          supabase.from('document_templates').insert(payload)
        , payload)
        if (result?.error) throw result.error
        await supabase.from('admin_audit_log').insert({
          admin_id: user?.id, action: 'contract_template_created', details: { type: template.type },
        })
      } else {
        const newVersion = (template.version || 1) + 1
        const payload = { name, content_html: content, version: newVersion, updated_by: user?.id }
        const result = await debugAction('contractTemplate.update', 'EditContractModal', () =>
          supabase.from('document_templates').update(payload).eq('id', template.id)
        , payload)
        if (result?.error) throw result.error
        await supabase.from('admin_audit_log').insert({
          admin_id: user?.id, action: 'contract_template_updated', details: { template_id: template.id, type: template.type, version: newVersion },
        })
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={isNew ? `Vytvo\u0159it: ${name || template.type}` : `Upravit: ${name}`} onClose={onClose} wide>
      <div className="space-y-3">
        <div>
          <Label>N\u00e1zev</Label>
          <input type="text" value={name} onChange={e => setName(e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={inputStyle} />
        </div>

        {vars.length > 0 && (
          <div className="p-3 rounded-lg" style={{ background: '#f0fdf4', border: '1px solid #bbf7d0' }}>
            <Label>Dostupn\u00e9 prom\u011bnn\u00e9 (vlo\u017ete do textu jako {'{{'}n\u00e1zev{'}}'})</Label>
            <div className="flex flex-wrap gap-1 mt-1">
              {vars.map(v => (
                <button key={v} onClick={() => {
                  const textarea = document.getElementById('contract-content')
                  if (textarea) {
                    const pos = textarea.selectionStart
                    const newContent = content.slice(0, pos) + `{{${v}}}` + content.slice(pos)
                    setContent(newContent)
                  }
                }}
                  className="rounded-btn text-sm font-mono cursor-pointer"
                  style={{ padding: '2px 8px', background: '#dcfce7', color: '#166534', border: '1px solid #bbf7d0' }}>
                  {`{{${v}}}`}
                </button>
              ))}
            </div>
          </div>
        )}

        <div>
          <Label>Obsah ({vars.length > 0 ? 'HTML \u0161ablona s prom\u011bnn\u00fdmi' : 'HTML text'})</Label>
          <textarea id="contract-content" value={content} onChange={e => setContent(e.target.value)}
            className="w-full rounded-btn text-sm outline-none font-mono"
            style={{ ...inputStyle, minHeight: 450, resize: 'vertical' }} />
        </div>

        <div className="flex items-center gap-2 text-sm" style={{ color: '#1a2e22' }}>
          <span>D\u00e9lka: {content.length} znak\u016f</span>
          {vars.length > 0 && (
            <span>| Pou\u017eit\u00e9 prom\u011bnn\u00e9: {extractVars(content).length}/{vars.length}</span>
          )}
        </div>
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}

      <div className="flex justify-between gap-3 mt-5">
        <Button onClick={() => setShowPreview(true)}>N\u00e1hled</Button>
        <div className="flex gap-2">
          <Button onClick={onClose}>Zru\u0161it</Button>
          <Button green onClick={handleSave} disabled={saving || !name || !content}>
            {saving ? 'Ukl\u00e1d\u00e1m\u2026' : isNew ? 'Vytvo\u0159it' : 'Ulo\u017eit'}
          </Button>
        </div>
      </div>

      {showPreview && (
        <Modal open title="N\u00e1hled dokumentu" onClose={() => setShowPreview(false)} wide>
          <div className="border rounded-lg overflow-auto" style={{ maxHeight: 550, background: '#fff' }}>
            <iframe
              srcDoc={content}
              style={{ width: '100%', height: 520, border: 'none' }}
              title="N\u00e1hled"
            />
          </div>
          <div className="flex justify-end mt-4">
            <Button onClick={() => setShowPreview(false)}>Zav\u0159\u00edt</Button>
          </div>
        </Modal>
      )}
    </Modal>
  )
}

function PreviewModal({ template, onClose }) {
  return (
    <Modal open title={`N\u00e1hled: ${template.name}`} onClose={onClose} wide>
      <div className="border rounded-lg overflow-auto" style={{ maxHeight: 600, background: '#fff' }}>
        <iframe
          srcDoc={template.content_html || '<p>Pr\u00e1zdn\u00fd obsah</p>'}
          style={{ width: '100%', height: 560, border: 'none' }}
          title="N\u00e1hled"
        />
      </div>
      <div className="flex justify-between mt-4">
        <Button onClick={() => {
          const win = window.open('', '_blank')
          if (win) { win.document.write(template.content_html || ''); win.document.close(); win.onload = () => win.print() }
        }}>Tisk / PDF</Button>
        <Button onClick={onClose}>Zav\u0159\u00edt</Button>
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
