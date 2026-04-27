import { useState, useMemo, useEffect, useRef, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import ImageUploader from '../../components/ui/ImageUploader'
import RichTextEditor from '../../components/ui/RichTextEditor'
import { autoTranslateRow } from '../../lib/autoTranslate'

const STEPS = [
  { id: 1, label: 'Základní info', desc: 'Název článku a krátký popis' },
  { id: 2, label: 'Obsah', desc: 'Text článku' },
  { id: 3, label: 'Média & štítky', desc: 'Obrázky a kategorie' },
  { id: 4, label: 'Náhled & publikace', desc: 'Kontrola a zveřejnění' },
]

const LS_KEY = 'blogWizard_draft_v1'
const AUTOSAVE_DEBOUNCE_MS = 1500

function slugify(text) {
  return (text || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
}

function emptyForm() {
  return { title: '', slug: '', excerpt: '', content: '', images: [], tags: '', published: false }
}

function formFromExisting(row) {
  if (!row) return emptyForm()
  return {
    title: row.title || '',
    slug: row.slug || '',
    excerpt: row.excerpt || '',
    content: row.content || '',
    images: Array.isArray(row.images) ? row.images : (row.image_url ? [row.image_url] : []),
    tags: Array.isArray(row.tags) ? row.tags.join(', ') : (row.tags || ''),
    published: !!row.published,
  }
}

function formHasContent(f) {
  return !!(f && (f.title?.trim() || f.content?.trim() || f.excerpt?.trim() || (f.images || []).length))
}

export default function BlogWizard({ onClose, onSaved, existing = null }) {
  const [step, setStep] = useState(1)
  const [saving, setSaving] = useState(false)
  const [translating, setTranslating] = useState(false)
  const [translateStatus, setTranslateStatus] = useState(null)
  const [err, setErr] = useState(null)
  const [autosaveStatus, setAutosaveStatus] = useState('idle') // idle | saving | saved | error
  const [draftId, setDraftId] = useState(existing?.id || null)
  const [restoreOffer, setRestoreOffer] = useState(null) // { form, draftId } | null

  const [form, setForm] = useState(() => formFromExisting(existing))
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  // Stabilní složka pro nahrávané obrázky (i před uložením článku)
  const folderId = useMemo(() => {
    if (existing?.id) return `blog/${existing.id}`
    const r = (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`
    return `blog/${r}`
  }, [existing?.id])

  // Refy pro stabilní hodnoty v listenerech (beforeunload / debounce)
  const formRef = useRef(form)
  const draftIdRef = useRef(draftId)
  useEffect(() => { formRef.current = form }, [form])
  useEffect(() => { draftIdRef.current = draftId }, [draftId])

  // 1) Restore z localStorage (jen pro nový článek bez existing)
  useEffect(() => {
    if (existing) return
    try {
      const raw = localStorage.getItem(LS_KEY)
      if (!raw) return
      const data = JSON.parse(raw)
      if (data && formHasContent(data.form)) {
        setRestoreOffer(data)
      }
    } catch {}
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  function acceptRestore() {
    if (restoreOffer?.form) setForm(restoreOffer.form)
    if (restoreOffer?.draftId) setDraftId(restoreOffer.draftId)
    setRestoreOffer(null)
  }
  function discardRestore() {
    try { localStorage.removeItem(LS_KEY) } catch {}
    setRestoreOffer(null)
  }

  // 2) Záloha do localStorage při každé změně (synchronní, rychlé)
  useEffect(() => {
    try {
      if (formHasContent(form)) {
        localStorage.setItem(LS_KEY, JSON.stringify({ form, draftId }))
      }
    } catch {}
  }, [form, draftId])

  // 3) Debounced autosave do DB jako koncept
  const saveDraft = useCallback(async () => {
    const f = formRef.current
    if (!formHasContent(f)) return null
    setAutosaveStatus('saving')
    const tags = (f.tags || '').split(',').map(t => t.trim()).filter(Boolean)
    const images = (f.images || []).filter(Boolean)
    const payload = {
      title: f.title?.trim() || '(bez názvu)',
      slug: f.slug?.trim() || slugify(f.title) || `koncept-${Date.now()}`,
      content: f.content || '',
      excerpt: f.excerpt || '',
      image_url: images[0] || '',
      images, tags,
      published: false,
      updated_at: new Date().toISOString(),
    }
    let id = draftIdRef.current
    if (id) {
      const { error } = await supabase.from('cms_pages').update(payload).eq('id', id)
      if (error) { setAutosaveStatus('error'); return null }
    } else {
      const { data, error } = await supabase.from('cms_pages').insert(payload).select('id').single()
      if (error || !data?.id) { setAutosaveStatus('error'); return null }
      id = data.id
      setDraftId(id)
      draftIdRef.current = id
    }
    setAutosaveStatus('saved')
    return id
  }, [])

  useEffect(() => {
    if (!formHasContent(form)) return
    if (saving || translating) return
    const t = setTimeout(() => { saveDraft() }, AUTOSAVE_DEBOUNCE_MS)
    return () => clearTimeout(t)
  }, [form.title, form.slug, form.excerpt, form.content, form.images, form.tags, saveDraft, saving, translating])

  // 4) Ochrana proti zavření prohlížeče: záloha do LS + browser prompt
  useEffect(() => {
    function onBeforeUnload(e) {
      if (!formHasContent(formRef.current)) return
      try {
        localStorage.setItem(LS_KEY, JSON.stringify({ form: formRef.current, draftId: draftIdRef.current }))
      } catch {}
      // Standardní browser prompt — uživatel uvidí "změny nemusí být uloženy"
      e.preventDefault()
      e.returnValue = ''
      return ''
    }
    window.addEventListener('beforeunload', onBeforeUnload)
    return () => window.removeEventListener('beforeunload', onBeforeUnload)
  }, [])

  // 5) Bezpečné zavření modálu — vždy uloží jako koncept, nikdy nezahodí text
  async function handleClose() {
    if (translating || saving) return // čekáme na dokončení akce
    if (formHasContent(form)) {
      const id = await saveDraft()
      if (id) {
        try { localStorage.removeItem(LS_KEY) } catch {}
      }
    } else {
      try { localStorage.removeItem(LS_KEY) } catch {}
    }
    onClose()
  }

  async function handlePublish() {
    setSaving(true); setErr(null); setTranslateStatus(null)
    const tags = form.tags.split(',').map(t => t.trim()).filter(Boolean)
    const images = (form.images || []).filter(Boolean)
    const payload = {
      title: form.title,
      slug: form.slug || slugify(form.title),
      content: form.content,
      excerpt: form.excerpt,
      image_url: images[0] || '',
      images, tags,
      published: form.published,
      updated_at: new Date().toISOString(),
    }

    let id = draftIdRef.current
    let error = null
    if (id) {
      const res = await supabase.from('cms_pages').update(payload).eq('id', id).select().single()
      error = res.error
    } else {
      const res = await supabase.from('cms_pages').insert(payload).select().single()
      error = res.error
      if (res.data?.id) { id = res.data.id; setDraftId(id); draftIdRef.current = id }
    }
    setSaving(false)
    if (error) { setErr(error.message); return }

    try { localStorage.removeItem(LS_KEY) } catch {}

    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('admin_audit_log').insert({
      admin_id: user?.id,
      action: existing ? 'blog_article_updated' : 'blog_article_created',
      details: { slug: payload.slug, title: payload.title, published: payload.published },
    })

    // Auto-překlad do 6 jazyků (en, de, es, fr, nl, pl) — vždy, i pro koncept,
    // aby web měl přeložené texty hned jakmile uživatel přepne na publikováno.
    if (id) {
      setTranslating(true)
      setTranslateStatus({ status: 'translating' })
      autoTranslateRow({
        table: 'cms_pages',
        id,
        row: payload,
        onStatus: (s) => setTranslateStatus(s),
      }).then((res) => {
        setTranslating(false)
        setTimeout(() => onSaved(), res?.success ? 600 : 1200)
      })
      return
    }
    onSaved()
  }

  const canNext = step === 1 ? !!form.title : step === 2 ? !!form.content : true
  const titleText = existing ? 'Upravit článek' : 'Nový článek na blog'

  return (
    <Modal open title={titleText} onClose={handleClose} wide>
      {/* Restore prompt z localStorage */}
      {restoreOffer && (
        <div className="mb-4 p-3 rounded-card flex items-center gap-3" style={{ background: '#fef3c7', border: '1px solid #fde68a' }}>
          <div className="flex-1 text-sm" style={{ color: '#78350f' }}>
            <div className="font-extrabold">Máte rozepsaný článek z minula</div>
            <div className="text-xs mt-0.5" style={{ color: '#92400e' }}>
              {restoreOffer.form?.title || '(bez názvu)'} — chcete pokračovat tam, kde jste skončili?
            </div>
          </div>
          <Button small onClick={discardRestore}>Zahodit</Button>
          <Button small green onClick={acceptRestore}>Načíst</Button>
        </div>
      )}

      {/* Stepper */}
      <div className="flex gap-1 mb-5">
        {STEPS.map(s => (
          <div key={s.id} className="flex-1 text-center">
            <div
              className="mx-auto flex items-center justify-center text-sm font-extrabold"
              style={{
                width: 32, height: 32, borderRadius: '50%',
                background: step === s.id ? '#74FB71' : step > s.id ? '#22c55e' : '#e2ece7',
                color: step >= s.id ? '#1a2e22' : '#9ab3a5',
              }}
            >
              {step > s.id ? '✓' : s.id}
            </div>
            <div className="text-xs font-bold mt-1" style={{ color: step === s.id ? '#1a2e22' : '#9ab3a5' }}>
              {s.label}
            </div>
          </div>
        ))}
      </div>

      {/* Step content */}
      {step === 1 && <Step1 form={form} set={set} />}
      {step === 2 && <Step2 form={form} set={set} />}
      {step === 3 && <Step3 form={form} set={set} folderId={folderId} />}
      {step === 4 && <Step4 form={form} set={set} />}

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      {translateStatus && <TranslationStatus status={translateStatus} />}

      {/* Navigation */}
      <div className="flex justify-between mt-5 items-center">
        <div className="flex items-center gap-3">
          {step > 1 && <Button onClick={() => setStep(step - 1)}>Zpět</Button>}
          <AutosaveIndicator status={autosaveStatus} hasContent={formHasContent(form)} draftId={draftId} />
        </div>
        <div className="flex gap-2">
          <Button onClick={handleClose} disabled={translating || saving}>
            {formHasContent(form) ? 'Uložit a zavřít' : 'Zavřít'}
          </Button>
          {step < 4 ? (
            <Button green onClick={() => setStep(step + 1)} disabled={!canNext}>
              Další krok
            </Button>
          ) : (
            <Button green onClick={handlePublish} disabled={saving || translating || !form.title}>
              {saving
                ? 'Ukládám...'
                : translating
                  ? 'Překládám…'
                  : form.published ? 'Publikovat článek' : 'Uložit jako koncept'}
            </Button>
          )}
        </div>
      </div>
    </Modal>
  )
}

function AutosaveIndicator({ status, hasContent, draftId }) {
  if (!hasContent) return null
  const map = {
    idle: draftId ? { text: 'Koncept uložen', color: '#6b8f7b' } : { text: 'Bude uloženo jako koncept', color: '#9ab3a5' },
    saving: { text: '⏳ Ukládám koncept…', color: '#1d4ed8' },
    saved: { text: '✓ Koncept uložen', color: '#16a34a' },
    error: { text: '⚠ Autosave selhal (text je zálohován v prohlížeči)', color: '#dc2626' },
  }
  const cfg = map[status] || map.idle
  return <span className="text-xs font-bold" style={{ color: cfg.color }}>{cfg.text}</span>
}

function Step1({ form, set }) {
  return (
    <div className="space-y-3">
      <Hint text="Tento název se zobrazí jako nadpis článku na stránce motogo24.cz/blog" />
      <div>
        <Label>Název článku *</Label>
        <input value={form.title} onChange={e => { set('title', e.target.value); if (!form.slug) set('slug', slugify(e.target.value)) }}
          placeholder="např. Top 5 tras na Vysočině" className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
      </div>
      <div>
        <Label>URL slug</Label>
        <Hint text="Adresa článku: motogo24.cz/blog/{slug} — generuje se automaticky z názvu" />
        <input value={form.slug} onChange={e => set('slug', e.target.value)}
          placeholder="top-5-tras-na-vysocine" className="w-full rounded-btn text-sm outline-none font-mono" style={inputStyle} />
      </div>
      <div>
        <Label>Krátký popis (excerpt)</Label>
        <Hint text="Zobrazí se na kartě článku v seznamu blogu a v Google výsledcích" />
        <textarea value={form.excerpt} onChange={e => set('excerpt', e.target.value)}
          placeholder="2-3 věty shrnující o čem článek je..."
          className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 80, resize: 'vertical' }} />
      </div>
    </div>
  )
}

function Step2({ form, set }) {
  return (
    <div className="space-y-3">
      <Hint text="Hlavní obsah článku — zobrazí se na detailu článku motogo24.cz/blog/{slug}. Použijte lištu pro formátování (tučně, kurzíva, nadpisy, seznamy, odkazy, obrázky)." />
      <div>
        <Label>Obsah článku *</Label>
        <RichTextEditor
          value={form.content}
          onChange={html => set('content', html)}
          placeholder="Začněte psát článek… Pomocí lišty výše můžete přidat nadpisy, seznamy, odkazy a obrázky."
          minHeight={340}
        />
      </div>
    </div>
  )
}

function Step3({ form, set, folderId }) {
  return (
    <div className="space-y-3">
      <div>
        <Label>Obrázky článku</Label>
        <Hint text="Přetáhněte fotky z počítače sem nebo klikněte pro výběr. První obrázek se použije jako hlavní (náhled v seznamu blogu). Ostatní se zobrazí jako galerie." />
        <ImageUploader
          value={form.images}
          onChange={urls => set('images', urls)}
          folder={folderId}
        />
      </div>
      <div>
        <Label>Štítky / kategorie (oddělené čárkou)</Label>
        <Hint text="Slouží k filtrování článků v blogu — např. Motorkářské trasy, Novinky, Rady a tipy" />
        <input value={form.tags} onChange={e => set('tags', e.target.value)}
          placeholder="Motorkářské trasy, Rady a tipy" className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
      </div>
    </div>
  )
}

function Step4({ form, set }) {
  const tags = form.tags.split(',').map(t => t.trim()).filter(Boolean)
  const heroImage = (form.images || [])[0] || ''
  return (
    <div className="space-y-4">
      <Hint text="Zkontrolujte článek před uložením. Koncept nebude vidět na webu, publikovaný ano. Po uložení se text automaticky přeloží do EN, DE, ES, FR, NL a PL." />
      <div className="rounded-card p-4" style={{ background: '#f8fafc', border: '1px solid #e2ece7' }}>
        <div className="text-xs font-bold uppercase mb-3" style={{ color: '#6b8f7b' }}>Náhled článku na webu</div>
        {heroImage && (
          <div className="rounded-card overflow-hidden mb-3" style={{ maxHeight: 200 }}>
            <img src={heroImage} alt="" style={{ width: '100%', objectFit: 'cover' }}
              onError={e => { e.target.style.display = 'none' }} />
          </div>
        )}
        <h3 className="font-extrabold text-base" style={{ color: '#0f1a14', margin: 0 }}>{form.title || '(bez názvu)'}</h3>
        <p className="text-sm mt-1" style={{ color: '#4a6b5a' }}>{form.excerpt || '(bez popisu)'}</p>
        <div className="text-xs font-mono mt-2" style={{ color: '#9ab3a5' }}>
          motogo24.cz/blog/{form.slug || slugify(form.title) || '...'}
        </div>
        {tags.length > 0 && (
          <div className="flex gap-1 mt-2 flex-wrap">
            {tags.map(t => (
              <span key={t} className="text-xs font-bold rounded-btn" style={{ padding: '2px 8px', background: '#e2ece7', color: '#1a2e22' }}>{t}</span>
            ))}
          </div>
        )}
      </div>

      <div className="flex items-center gap-3 p-3 rounded-card" style={{ background: form.published ? '#dcfce7' : '#fef3c7', border: '1px solid ' + (form.published ? '#bbf7d0' : '#fde68a') }}>
        <input type="checkbox" id="wiz-publish" checked={form.published} onChange={e => set('published', e.target.checked)}
          style={{ width: 20, height: 20, accentColor: '#22c55e' }} />
        <label htmlFor="wiz-publish" className="cursor-pointer">
          <div className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>
            {form.published ? 'Publikovat ihned' : 'Uložit jako koncept'}
          </div>
          <div className="text-xs" style={{ color: '#4a6b5a' }}>
            {form.published ? 'Článek bude okamžitě viditelný na motogo24.cz/blog' : 'Článek neuvidí návštěvníci webu, dokud ho nezveřejníte'}
          </div>
        </label>
      </div>
    </div>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
function Hint({ text }) {
  return <div className="text-xs mb-2" style={{ color: '#6b8f7b', lineHeight: 1.5 }}>{text}</div>
}

function TranslationStatus({ status }) {
  if (!status) return null
  const map = {
    translating: { bg: '#dbeafe', color: '#1d4ed8', text: '🌍 Překládám do 6 jazyků (en, de, es, fr, nl, pl) — Anthropic Claude…' },
    done:        { bg: '#dcfce7', color: '#166534', text: `✓ Přeloženo do ${(status.languages || []).length} jazyků` },
    error:       { bg: '#fee2e2', color: '#dc2626', text: `⚠️ Překlad selhal: ${status.error || 'neznámá chyba'} (článek je uložen, můžete přeložit později)` },
    skipped:     { bg: '#f3f4f6', color: '#6b7280', text: 'ℹ️ Žádný text k překladu' },
  }
  const cfg = map[status.status] || map.translating
  return (
    <div className="mt-3 rounded-card text-xs font-bold" style={{ padding: '8px 12px', background: cfg.bg, color: cfg.color }}>
      {cfg.text}
    </div>
  )
}
