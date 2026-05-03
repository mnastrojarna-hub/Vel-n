import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import TranslationBackfillButton from '../../components/shared/TranslationBackfillButton'
import { autoTranslate } from '../../lib/autoTranslate'
import { debugAction } from '../../lib/debugLog'

// Stejné kategorie jako jsou v DB seedu — přidat lze i ručně přes editor (free text).
const DEFAULT_CATEGORIES = [
  { key: 'reservations', label: 'Rezervace' },
  { key: 'borrowing', label: 'Výpůjčka a vrácení' },
  { key: 'conditions', label: 'Výbava a podmínky' },
  { key: 'delivery', label: 'Přistavení' },
  { key: 'travel', label: 'Cesty do zahraničí' },
  { key: 'vouchers', label: 'Poukazy' },
]

export default function FaqSection() {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [filterCat, setFilterCat] = useState('')
  const [onlyUnpublished, setOnlyUnpublished] = useState(false)
  const [showAdd, setShowAdd] = useState(false)
  const [editing, setEditing] = useState(null)
  const [collapsedCats, setCollapsedCats] = useState({})

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const { data } = await supabase
      .from('faq_items')
      .select('*')
      .order('category_key', { ascending: true })
      .order('sort_order', { ascending: true })
    setItems(data || [])
    setLoading(false)
  }

  // Sloučí defaultní + reálně použité kategorie z DB (admin mohl založit vlastní)
  const allCategories = useMemo(() => {
    const map = new Map(DEFAULT_CATEGORIES.map(c => [c.key, c.label]))
    items.forEach(it => { if (!map.has(it.category_key)) map.set(it.category_key, it.category_label) })
    return Array.from(map.entries()).map(([key, label]) => ({ key, label }))
  }, [items])

  const filtered = useMemo(() => {
    return items.filter(it => {
      if (filterCat && it.category_key !== filterCat) return false
      if (onlyUnpublished && it.published) return false
      return true
    })
  }, [items, filterCat, onlyUnpublished])

  const grouped = useMemo(() => {
    const out = {}
    filtered.forEach(it => {
      const k = it.category_key
      if (!out[k]) out[k] = { label: it.category_label || k, items: [] }
      out[k].items.push(it)
    })
    return out
  }, [filtered])

  async function togglePublished(it) {
    await debugAction('faq.togglePublished', 'FaqSection', () =>
      supabase.from('faq_items').update({ published: !it.published }).eq('id', it.id)
    , { id: it.id, was: it.published })
    load()
  }

  async function toggleFeatured(it) {
    await debugAction('faq.toggleFeatured', 'FaqSection', () =>
      supabase.from('faq_items').update({ featured_home: !it.featured_home }).eq('id', it.id)
    , { id: it.id, was: it.featured_home })
    load()
  }

  async function deleteItem(it) {
    if (!confirm(`Smazat otázku „${it.question.slice(0, 60)}"?`)) return
    await debugAction('faq.delete', 'FaqSection', () =>
      supabase.from('faq_items').delete().eq('id', it.id)
    , { id: it.id })
    load()
  }

  const featuredCount = items.filter(i => i.featured_home && i.published).length
  const totalPublished = items.filter(i => i.published).length

  return (
    <div>
      {/* Header s popisem */}
      <div className="mb-4">
        <div className="flex items-center gap-3">
          <span style={{ fontSize: 24 }}>📋</span>
          <div className="flex-1">
            <h2 className="text-lg font-extrabold" style={{ color: '#0f1a14', margin: 0 }}>Časté dotazy (FAQ)</h2>
            <div className="text-xs font-mono" style={{ color: '#6b8f7b' }}>motogo24.com/jak-pujcit/faq</div>
          </div>
        </div>
        <p className="text-sm mt-2" style={{ color: '#4a6b5a' }}>
          Otázky se zobrazují na FAQ stránce v tabech podle kategorií. Položky označené ⭐ („zobrazit na hlavní stránce")
          se navíc objeví v sekci FAQ na domovské stránce. Po uložení každé otázky se obsah automaticky přeloží do 6 jazyků.
        </p>
      </div>

      {/* Add CTA */}
      <div className="flex items-center gap-3 mb-4 p-4 rounded-card" style={{ background: '#f1faf7', border: '2px dashed #74FB71' }}>
        <div className="flex-1">
          <div className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>Přidat novou otázku</div>
          <div className="text-xs mt-0.5" style={{ color: '#6b8f7b' }}>Vyber kategorii, napiš otázku a odpověď. HTML v odpovědi je povolený.</div>
        </div>
        <div className="text-xs font-bold mr-2" style={{ color: '#1a2e22' }}>
          {totalPublished} publikováno · ⭐ {featuredCount} na home
        </div>
        <Button green onClick={() => setShowAdd(true)}>+ Nová otázka</Button>
      </div>

      {/* Backfill překladů pro starší otázky bez vyplněného translations JSONB */}
      <div className="mb-4 p-3 rounded-card flex items-center justify-between gap-3"
        style={{ background: '#fff', border: '1px solid #e2ece7' }}>
        <div className="text-xs" style={{ color: '#4a6b5a' }}>
          Doplní EN/DE/ES/FR/NL/PL překlady pro otázky, kterým chybí <code>translations</code>
          (např. položky importované před zapnutím auto-překladu).
        </div>
        <TranslationBackfillButton
          table="faq_items"
          selectColumns="id, question, answer, translations"
          onDone={load}
        />
      </div>

      {/* Filter */}
      <div className="flex items-center gap-3 mb-4">
        <select value={filterCat} onChange={e => setFilterCat(e.target.value)}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="">Všechny kategorie</option>
          {allCategories.map(c => <option key={c.key} value={c.key}>{c.label} ({items.filter(i => i.category_key === c.key).length})</option>)}
        </select>
        <label className="flex items-center gap-2 text-sm cursor-pointer">
          <input type="checkbox" checked={onlyUnpublished} onChange={e => setOnlyUnpublished(e.target.checked)} />
          Jen nepublikované
        </label>
      </div>

      {loading ? (
        <div className="flex justify-center py-8">
          <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" />
        </div>
      ) : Object.keys(grouped).length === 0 ? (
        <div className="text-center py-8 text-sm" style={{ color: '#9ab3a5' }}>
          Žádné otázky. Klikni na „+ Nová otázka" a vytvoř první.
        </div>
      ) : (
        Object.entries(grouped).map(([catKey, cat]) => {
          const collapsed = collapsedCats[catKey]
          return (
            <div key={catKey} className="mb-3">
              <button
                onClick={() => setCollapsedCats(s => ({ ...s, [catKey]: !s[catKey] }))}
                className="w-full flex items-center gap-2 cursor-pointer"
                style={{
                  padding: '10px 14px', background: '#1a2e22', color: '#74FB71',
                  border: 'none', borderRadius: 10, marginBottom: 6, fontSize: 13, fontWeight: 800,
                  textTransform: 'uppercase', letterSpacing: 1, textAlign: 'left'
                }}
              >
                <span style={{ transform: collapsed ? 'none' : 'rotate(90deg)', transition: 'transform .15s' }}>&#9654;</span>
                <span className="flex-1">{cat.label}</span>
                <span style={{ background: '#74FB71', color: '#0f1a14', padding: '2px 8px', borderRadius: 8, fontSize: 11 }}>
                  {cat.items.length}
                </span>
              </button>
              {!collapsed && cat.items.map(it => (
                <FaqRow
                  key={it.id}
                  item={it}
                  onEdit={() => setEditing(it)}
                  onTogglePublished={() => togglePublished(it)}
                  onToggleFeatured={() => toggleFeatured(it)}
                  onDelete={() => deleteItem(it)}
                />
              ))}
            </div>
          )
        })
      )}

      {(showAdd || editing) && (
        <FaqEditor
          entry={editing}
          categories={allCategories}
          onClose={() => { setShowAdd(false); setEditing(null) }}
          onSaved={() => { setShowAdd(false); setEditing(null); load() }}
        />
      )}
    </div>
  )
}

function FaqRow({ item, onEdit, onTogglePublished, onToggleFeatured, onDelete }) {
  const it = item
  return (
    <div className="flex items-center gap-3 p-3 rounded-card mb-1"
      style={{ background: '#fff', border: '1px solid #e2ece7', opacity: it.published ? 1 : 0.6 }}>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{it.question}</span>
          {it.featured_home && (
            <span className="text-xs font-bold rounded-btn shrink-0"
              style={{ padding: '1px 8px', background: '#fef3c7', color: '#b45309' }}>⭐ home</span>
          )}
          {!it.published && (
            <span className="text-xs font-bold rounded-btn shrink-0"
              style={{ padding: '1px 8px', background: '#fee2e2', color: '#b91c1c' }}>skryto</span>
          )}
          <span className="text-xs font-mono ml-auto shrink-0" style={{ color: '#9ab3a5' }}>#{it.sort_order}</span>
        </div>
        <div className="text-xs mt-1 truncate" style={{ color: '#6b8f7b' }}
          dangerouslySetInnerHTML={{ __html: stripTagsLite(it.answer).slice(0, 160) + (it.answer.length > 160 ? '…' : '') }} />
      </div>
      <div className="flex gap-1 shrink-0">
        <SmBtn label="Upravit" onClick={onEdit} />
        <SmBtn label={it.featured_home ? '★ Home' : '☆ Home'} onClick={onToggleFeatured} active={it.featured_home} />
        <SmBtn label={it.published ? 'Skrýt' : 'Zveřejnit'} onClick={onTogglePublished} />
        <SmBtn label="Smazat" onClick={onDelete} danger />
      </div>
    </div>
  )
}

function stripTagsLite(html) {
  return String(html || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()
}

function SmBtn({ label, onClick, danger, active }) {
  return (
    <button onClick={onClick}
      className="rounded-btn text-xs font-bold cursor-pointer"
      style={{
        padding: '4px 10px', border: 'none',
        background: danger ? '#fee2e2' : (active ? '#fef3c7' : '#f1faf7'),
        color: danger ? '#dc2626' : (active ? '#b45309' : '#1a2e22'),
      }}
    >{label}</button>
  )
}

function FaqEditor({ entry, categories, onClose, onSaved }) {
  const [form, setForm] = useState(entry ? {
    category_key: entry.category_key,
    category_label: entry.category_label,
    question: entry.question,
    answer: entry.answer,
    sort_order: entry.sort_order,
    featured_home: entry.featured_home,
    published: entry.published,
  } : {
    category_key: categories[0]?.key || 'reservations',
    category_label: categories[0]?.label || 'Rezervace',
    question: '',
    answer: '',
    sort_order: 0,
    featured_home: false,
    published: true,
  })
  const [saving, setSaving] = useState(false)
  const [translating, setTranslating] = useState(false)
  const [err, setErr] = useState(null)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  function pickCategory(key) {
    const cat = categories.find(c => c.key === key)
    set('category_key', key)
    if (cat) set('category_label', cat.label)
  }

  async function handleSave() {
    if (!form.question.trim() || !form.answer.trim()) {
      setErr('Otázka i odpověď musí být vyplněné.')
      return
    }
    if (!form.category_key.trim() || !form.category_label.trim()) {
      setErr('Vyber kategorii (klíč i název).')
      return
    }
    setSaving(true); setErr(null)
    try {
      const payload = {
        category_key: form.category_key.trim(),
        category_label: form.category_label.trim(),
        question: form.question.trim(),
        answer: form.answer.trim(),
        sort_order: parseInt(form.sort_order, 10) || 0,
        featured_home: !!form.featured_home,
        published: !!form.published,
      }
      let savedId = entry?.id
      if (entry) {
        const r = await debugAction('faq.update', 'FaqEditor', () =>
          supabase.from('faq_items').update(payload).eq('id', entry.id)
        , { id: entry.id })
        if (r?.error) throw r.error
      } else {
        const r = await debugAction('faq.create', 'FaqEditor', () =>
          supabase.from('faq_items').insert(payload).select().single()
        , payload)
        if (r?.error) throw r.error
        savedId = r?.data?.id
      }
      // Auto-překlad otázky + odpovědi do EN/DE/ES/FR/NL/PL na pozadí
      if (savedId) {
        setTranslating(true)
        try {
          await autoTranslate({
            table: 'faq_items',
            id: savedId,
            fields: { question: payload.question, answer: payload.answer },
          })
        } catch (_) { /* best-effort */ }
        setTranslating(false)
      }
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: entry ? 'faq_updated' : 'faq_created',
        details: { id: savedId, question: payload.question.slice(0, 80) }
      })
      onSaved()
    } catch (e) {
      setErr(e.message || String(e))
    } finally { setSaving(false) }
  }

  return (
    <Modal open title={entry ? 'Upravit otázku' : 'Nová otázka'} onClose={onClose} wide>
      <div className="space-y-3">
        <div className="flex gap-3">
          <div className="flex-1">
            <Label>Kategorie</Label>
            <select value={form.category_key} onChange={e => pickCategory(e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
              {categories.map(c => <option key={c.key} value={c.key}>{c.label}</option>)}
            </select>
          </div>
          <div style={{ width: 160 }}>
            <Label>Pořadí</Label>
            <input type="number" value={form.sort_order} onChange={e => set('sort_order', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          </div>
        </div>
        <div className="text-xs" style={{ color: '#6b8f7b', marginTop: -4 }}>
          Klíč: <code>{form.category_key}</code> · Název: <input
            type="text" value={form.category_label} onChange={e => set('category_label', e.target.value)}
            style={{ padding: '2px 6px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 6, fontSize: 12, marginLeft: 4 }}
          />
        </div>

        <div>
          <Label>Otázka</Label>
          <input value={form.question} onChange={e => set('question', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle}
            placeholder="Např. Jak si mohu rezervovat motorku?" />
        </div>

        <div>
          <Label>Odpověď (HTML povolený)</Label>
          <textarea value={form.answer} onChange={e => set('answer', e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ ...inputStyle, minHeight: 140, resize: 'vertical', fontFamily: 'inherit' }}
            placeholder="Odpověď zákazníkovi. Můžeš použít <strong>tučné</strong>, <a href='/...'>odkazy</a>, <br> atd." />
          <div className="text-xs mt-1" style={{ color: '#9ab3a5' }}>
            Tip: HTML jako <code>&lt;strong&gt;</code>, <code>&lt;a href&gt;</code>, <code>&lt;br&gt;</code> se přenáší 1:1 na web.
          </div>
        </div>

        <div className="flex gap-4 items-center">
          <label className="flex items-center gap-2 cursor-pointer text-sm">
            <input type="checkbox" checked={form.published} onChange={e => set('published', e.target.checked)} />
            <span style={{ fontWeight: 700 }}>Publikováno</span>
          </label>
          <label className="flex items-center gap-2 cursor-pointer text-sm">
            <input type="checkbox" checked={form.featured_home} onChange={e => set('featured_home', e.target.checked)} />
            <span style={{ fontWeight: 700 }}>⭐ Zobrazit i na home</span>
            <span className="text-xs" style={{ color: '#9ab3a5' }}>(prvních 4 podle pořadí)</span>
          </label>
        </div>
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}

      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || translating}>
          {saving ? 'Ukládám…' : translating ? '🌍 Překládám…' : 'Uložit'}
        </Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
