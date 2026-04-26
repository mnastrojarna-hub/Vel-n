import { useState, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import ImageUploader from '../../components/ui/ImageUploader'
import { autoTranslateRow } from '../../lib/autoTranslate'

const STEPS = [
  { id: 1, label: 'Základní info', desc: 'Název článku a krátký popis' },
  { id: 2, label: 'Obsah', desc: 'Text článku (HTML)' },
  { id: 3, label: 'Média & štítky', desc: 'Obrázky a kategorie' },
  { id: 4, label: 'Náhled & publikace', desc: 'Kontrola a zveřejnění' },
]

function slugify(text) {
  return text.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
}

export default function BlogWizard({ onClose, onSaved }) {
  const [step, setStep] = useState(1)
  const [saving, setSaving] = useState(false)
  const [translating, setTranslating] = useState(false)
  const [translateStatus, setTranslateStatus] = useState(null)
  const [err, setErr] = useState(null)
  const [form, setForm] = useState({
    title: '', slug: '', excerpt: '', content: '',
    images: [], tags: '',
    published: false,
  })
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  // Stabilní složka pro nahrávané obrázky (i před uložením článku)
  const folderId = useMemo(() => {
    const r = (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`
    return `blog/${r}`
  }, [])

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
    const { data: inserted, error } = await supabase.from('cms_pages').insert(payload).select().single()
    setSaving(false)
    if (error) { setErr(error.message); return }
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('admin_audit_log').insert({
      admin_id: user?.id, action: 'blog_article_created',
      details: { slug: payload.slug, title: payload.title },
    })

    // Auto-překlad do 6 jazyků pro web — běží na pozadí, ale počkáme krátce kvůli toastu
    if (inserted?.id) {
      setTranslating(true)
      setTranslateStatus({ status: 'translating' })
      autoTranslateRow({
        table: 'cms_pages',
        id: inserted.id,
        row: payload,
        onStatus: (s) => setTranslateStatus(s),
      }).then((res) => {
        setTranslating(false)
        if (res?.success) {
          setTimeout(() => onSaved(), 600)
        } else {
          // I při selhání překladu článek ulož
          setTimeout(() => onSaved(), 1200)
        }
      })
      return
    }
    onSaved()
  }

  const canNext = step === 1 ? !!form.title : step === 2 ? !!form.content : true

  return (
    <Modal open title="Nový článek na blog" onClose={onClose} wide>
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
      <div className="flex justify-between mt-5">
        <div>
          {step > 1 && <Button onClick={() => setStep(step - 1)}>Zpět</Button>}
        </div>
        <div className="flex gap-2">
          <Button onClick={onClose} disabled={translating}>Zrušit</Button>
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
      <Hint text="Hlavní obsah článku — zobrazí se na detailu článku motogo24.cz/blog/{slug}. Můžete použít HTML tagy." />
      <div>
        <Label>Obsah článku (HTML) *</Label>
        <textarea value={form.content} onChange={e => set('content', e.target.value)}
          placeholder="<p>Text článku...</p>&#10;<h2>Podnadpis</h2>&#10;<p>Další odstavec...</p>"
          className="w-full rounded-btn text-sm outline-none font-mono"
          style={{ ...inputStyle, minHeight: 300, resize: 'vertical' }} />
      </div>
      <div className="p-3 rounded-card" style={{ background: '#f8fafc', border: '1px solid #e2ece7' }}>
        <div className="text-xs font-bold mb-1" style={{ color: '#6b8f7b' }}>Nápověda k formátování:</div>
        <div className="text-xs" style={{ color: '#4a6b5a', lineHeight: 1.6 }}>
          {'<p>odstavec</p> · <h2>podnadpis</h2> · <strong>tučně</strong> · <a href="...">odkaz</a> · <ul><li>seznam</li></ul> · <img src="URL">'}
        </div>
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
      <Hint text="Zkontrolujte článek před uložením. Koncept nebude vidět na webu, publikovaný ano." />
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
