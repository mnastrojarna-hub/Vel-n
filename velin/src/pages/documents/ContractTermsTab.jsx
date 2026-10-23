import { useState, useEffect, useRef } from 'react'
import { openPrintWindow } from '../../lib/sanitize'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import RichTextEditor, { buildPreviewHtml } from '../../components/ui/RichTextEditor'
import CustomDocumentsSection from './CustomDocumentsSection'
import { TR_LANGS, useSourceHashes, pickLangs, runDocTranslation, translateAllRows, bulkResultText } from './docTranslations'
import TranslationStatusChips from './TranslationStatusChips'
import { convertPdfToHtml } from '../../lib/pdfImport'

const CONTRACT_TYPES = [
  { type: 'vop', label: 'Obchodní podmínky (VOP)', icon: '📜', description: 'Všeobecné obchodní podmínky pro pronájem motocyklů' },
  { type: 'rental_contract', label: 'Nájemní smlouva', icon: '📋', description: 'Smlouva o pronájmu motocyklu s automatickým vyplněním údajů' },
  // Výpůjčka výbavy bez motorky (booking_kind='gear'): generate-document ji použije místo rental_contract (seed 20261023d)
  { type: 'gear_rental_contract', label: 'Smlouva o nájmu výbavy', icon: '🧥', description: 'Smlouva o nájmu motorkářské výbavy (výpůjčka výbavy bez motorky) s automatickým vyplněním údajů — příloha „Smlouva“ u výpůjček výbavy' },
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
  // Proměnné plní edge generate-document (gear větev) — {{gear_items_table}} = tabulka kusů a velikostí
  gear_rental_contract: [
    'customer_name', 'customer_address', 'customer_id_number', 'customer_id_expiry',
    'customer_phone', 'customer_email', 'customer_dob', 'customer_ico', 'customer_dic',
    'gear_items_table', 'gear_period', 'gear_days',
    'start_date', 'start_time', 'end_date', 'end_time',
    'total_price', 'total_price_words',
    'branch_name', 'branch_address',
    'today', 'booking_number',
    'company_name', 'company_address', 'company_ico', 'company_dic',
    'company_phone', 'company_email', 'company_web',
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
  const [bulk, setBulk] = useState(null) // null | { text } | { text, done:true }
  const [importingType, setImportingType] = useState(null) // typ, u kterého běží převod PDF
  const fileInputRef = useRef(null)
  const importTypeRef = useRef(null) // typ šablony, pro kterou byl otevřen výběr PDF

  // Nahrání PDF: převede se přes edge fn `pdf-to-html` na HTML a předvyplní
  // do editačního modalu — admin zkontroluje a uloží stávající cestou
  // (content_html), takže překlady, generování i mailové přílohy fungují dál.
  function handlePdfPick(type) {
    importTypeRef.current = type
    if (fileInputRef.current) { fileInputRef.current.value = ''; fileInputRef.current.click() }
  }

  async function handlePdfSelected(e) {
    const file = e.target.files?.[0]
    const type = importTypeRef.current
    if (!file || !type) return
    const ct = CONTRACT_TYPES.find(c => c.type === type)
    setImportingType(type)
    setTrMsg(m => ({ ...m, [type]: { ok: true, text: `Převádím „${file.name}" na text… (u delších dokumentů to může trvat i několik minut — nechte stránku otevřenou)` } }))
    const res = await convertPdfToHtml(file)
    setImportingType(null)
    if (!res.success) {
      setTrMsg(m => ({ ...m, [type]: { ok: false, text: `Nahrání PDF selhalo: ${res.error}` } }))
      return
    }
    setTrMsg(m => ({ ...m, [type]: { ok: true, text: `PDF „${file.name}" převedeno — zkontrolujte obsah a uložte.` } }))
    const tpl = getTemplate(type)
    setEditing({
      ...(tpl || { type, name: ct?.label || type, version: 0 }),
      content_html: res.html,
      _fromPdf: true,
    })
  }

  // Přeloží naráz všechny smluvní šablony do všech 7 jazyků. Bez force jen chybějící
  // a ZASTARALÉ překlady (česká verze se od překladu změnila), s force úplně vše znovu.
  async function handleTranslateAll({ force = false } = {}) {
    if (force && !window.confirm(`Přeložit znovu všechny smluvní texty do ${TR_LANGS.length} jazyků (${TR_LANGS.join(', ')}) — i ty aktuální? Trvá to desítky minut, nechte stránku otevřenou.`)) return
    setBulk({ text: 'Načítám šablony…' })
    // select('*') — snese i DB bez sloupce translation_src (pak je vše zastaralé)
    const { data: rows, error: err } = await supabase
      .from('document_templates')
      .select('*')
      .in('type', CONTRACT_TYPES.map(c => c.type))
      .order('type')
    if (err) { setBulk({ text: 'Chyba: ' + err.message, done: true }); return }
    const res = await translateAllRows('document_templates', rows || [], {
      force,
      labelOf: r => CONTRACT_TYPES.find(c => c.type === r.type)?.label || r.type,
      onText: text => setBulk({ text }),
    })
    setBulk({ text: bulkResultText(res, 'Smluvní texty'), done: true })
    load()
  }

  // Jeden dokument: bez voleb chybějící + zastaralé jazyky, { force } všechny, { langs } jen zadané.
  async function handleTranslate(tpl, opts = {}) {
    if (!tpl?.id) return
    const setMsg = v => setTrMsg(m => ({ ...m, [tpl.type]: v }))
    setTranslatingType(tpl.type)
    const todo = await pickLangs('document_templates', tpl, opts)
    if (todo.length === 0) {
      setTranslatingType(null)
      setMsg({ ok: true, text: 'Všechny překlady jsou aktuální. Pro nové přeložení použij „Přeložit znovu vše".' })
      return
    }
    await runDocTranslation('document_templates', tpl, todo, setMsg)
    setTranslatingType(null)
    load()
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

  const srcHashes = useSourceHashes('document_templates', templates)
  // Sloupec translation_src ještě v DB není (migrace 20261011) → aktuálnost nejde ověřit
  const srcMissing = templates.length > 0 && !templates.some(t => 'translation_src' in t)

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <div className="space-y-4">
      <div className="p-3 rounded-card" style={{ background: '#f0fdf4', border: '1px solid #bbf7d0', fontSize: 12, color: '#166534' }}>
        Smluvní texty se automaticky zobrazují v zákaznické aplikaci a používají se při generování dokumentů k rezervacím. Změny se projeví okamžitě.
        {' '}Závazná je česká verze. Překlad platí jen pro české znění, ze kterého vznikl — po úpravě češtiny je <strong>ZASTARALÝ</strong> a web, aplikace,
        PDF ani AI ho nepoužijí (ukážou češtinu), dokud ho znovu nepřeložíte.
      </div>

      {srcMissing && (
        <div className="p-3 rounded-card" style={{ background: '#fef3c7', border: '1px solid #fde68a', fontSize: 12, color: '#92400e' }}>
          Evidence aktuálnosti překladů (sloupec <code>translation_src</code>) ještě není v databázi — všechny existující překlady se proto zobrazují jako zastaralé
          a „Přeložit“ do té doby přeloží znovu všechny jazyky (aktuálnost se nemá kam uložit).
        </div>
      )}

      {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      <input
        ref={fileInputRef}
        type="file"
        accept="application/pdf,.pdf"
        style={{ display: 'none' }}
        onChange={handlePdfSelected}
      />

      <div className="flex items-center gap-3 flex-wrap">
        <Button green onClick={() => handleTranslateAll()} disabled={!!bulk && !bulk.done}>
          {bulk && !bulk.done ? 'Překládám…' : `🌍 Přeložit chybějící a zastaralé (${TR_LANGS.length} jazyků)`}
        </Button>
        <Button onClick={() => handleTranslateAll({ force: true })} disabled={!!bulk && !bulk.done}>
          Přeložit znovu vše (force)
        </Button>
        {bulk && <span className="text-sm" style={{ color: bulk.done ? '#15803d' : '#6b7a72' }}>{bulk.text}</span>}
      </div>

      <div className="grid grid-cols-1 gap-4">
        {CONTRACT_TYPES.map(ct => {
          const tpl = getTemplate(ct.type)
          const vars = TEMPLATE_VARS[ct.type] || []
          return (
            <Card key={ct.type}>
              {/* < 1024 px: popis nahoře přes celou šířku, tlačítka pod ním se zalamují */}
              <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-3 lg:flex-wrap">
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
                      </div>
                    )}
                    {tpl && (
                      <TranslationStatusChips table="document_templates" row={tpl} srcHash={srcHashes[tpl.id]}
                        busy={translatingType === ct.type || (!!bulk && !bulk.done)}
                        onTranslateLang={lang => handleTranslate(tpl, { langs: [lang] })} />
                    )}
                    {tpl && trMsg[ct.type] && <p className="text-sm mt-1" style={{ color: trMsg[ct.type].ok ? '#15803d' : '#dc2626' }}>{trMsg[ct.type].text}</p>}
                  </div>
                </div>
                <div className="flex flex-wrap lg:flex-nowrap gap-2 shrink-0">
                  {tpl && (
                    <Button onClick={() => setPreview(tpl)}>
                      Náhled
                    </Button>
                  )}
                  {tpl && (
                    <Button onClick={() => handleTranslate(tpl)} disabled={translatingType === ct.type || (!!bulk && !bulk.done)}>
                      {translatingType === ct.type ? 'Překládám…' : '🌍 Přeložit'}
                    </Button>
                  )}
                  {tpl && translatingType !== ct.type && Object.keys(tpl.content_translations || {}).some(k => TR_LANGS.includes(k)) && (
                    <Button onClick={() => handleTranslate(tpl, { force: true })} disabled={!!bulk && !bulk.done}>Přeložit znovu vše</Button>
                  )}
                  <Button onClick={() => handlePdfPick(ct.type)} disabled={importingType === ct.type}>
                    {importingType === ct.type ? 'Převádím PDF…' : '📄 Nahrát PDF'}
                  </Button>
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
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, new_data: details })
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
          updated_at: new Date().toISOString(), // trigger updated_at má tabulka až od migrace 20261011 — do té doby jen takto
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

  // Odsazení lišty = vnitřní odsazení Modalu (telefon < 640 px: 16 px, jinak 28 px) — třídy stickyBarCls
  const stickyBar = {
    position: 'sticky', left: 0, right: 0,
    background: '#fff', borderTop: '1px solid #e2ece7',
    display: 'flex', justifyContent: 'space-between', gap: 12,
  }

  return (
    <Modal open title={isNew ? `Vytvořit: ${name || template.type}` : `Upravit: ${name}`} onClose={onClose} wide>
      <div className="space-y-3">
        {template._fromPdf && (
          <div className="p-3 rounded-card" style={{ background: '#eff6ff', border: '1px solid #bfdbfe', fontSize: 12, color: '#1e40af' }}>
            📄 Obsah byl načten z nahraného PDF (dosavadní text šablony se uložením PŘEPÍŠE).
            Zkontrolujte text a formátování, případně vložte proměnné z menu „+ Proměnná…“.
            Po uložení spusťte „Přeložit znovu vše“, aby se přegenerovaly překlady z nového znění.
          </div>
        )}
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

      {/* telefon: užší tlačítka, aby se lišta vešla do jednoho řádku (jinak zabírá 2 řádky nad editorem) */}
      <div className={stickyBarCls} style={stickyBar}>
        <Button onClick={() => setShowPreview(true)} className="max-sm:!px-4">Náhled</Button>
        <div className="flex gap-2 max-lg:ml-auto">
          <Button onClick={onClose} className="max-sm:!px-4">Zrušit</Button>
          <Button green onClick={handleSave} disabled={saving || !name || !content} className="max-sm:!px-4">
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
          openPrintWindow(previewHtml)
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

// Spodní lišta modálu přilepená k okraji: záporné okraje = padding Modalu (p-4 / sm:p-7), na úzkém displeji se zalamuje.
// z-index < 1024 px nad lepicí lištou RichTextEditoru (z 5) — na telefonu by jinak při posunu překryla Uložit/Zrušit.
const stickyBarCls = '-bottom-4 sm:-bottom-7 mt-4 -mx-4 -mb-4 sm:-mx-7 sm:-mb-7 px-4 sm:px-7 py-[14px] flex-wrap lg:flex-nowrap z-[2] max-lg:z-[6]'
const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
