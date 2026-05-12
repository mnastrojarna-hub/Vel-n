import { useState, useEffect, useRef, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import ConfirmDialog from '../../components/ui/ConfirmDialog'
import RichTextEditor, { buildPreviewHtml } from '../../components/ui/RichTextEditor'
import { translateDocument, TRANSLATE_TARGET_LANGS } from '../../lib/autoTranslate'

// Vlastní dokumenty vytvořené ve Velíně (mimo 5 pevných smluvních typů).
// Tabulka: custom_documents (title, slug, description, kind 'html'|'pdf',
// content_html, pdf_path, show_on_web, sort_order, active, version).
// Bucket pro PDF: 'media' (veřejný) — uloženo do media/documents/<slug>-<stamp>.pdf,
// v pdf_path je rovnou veřejná URL, web na ni odkazuje.

function slugify(s) {
  return String(s || '')
    .toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '')
    .slice(0, 80)
}

export default function CustomDocumentsSection() {
  const [docs, setDocs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [tableMissing, setTableMissing] = useState(false)
  const [editing, setEditing] = useState(null)
  const [preview, setPreview] = useState(null)
  const [toDelete, setToDelete] = useState(null)
  const [translatingId, setTranslatingId] = useState(null)
  const [trMsg, setTrMsg] = useState({}) // id -> { ok, text }

  async function handleTranslate(doc) {
    setTranslatingId(doc.id)
    setTrMsg(m => ({ ...m, [doc.id]: null }))
    const res = await translateDocument({ table: 'custom_documents', id: doc.id })
    setTranslatingId(null)
    if (res?.success) {
      const langs = Object.keys(res.translations || {})
      const failed = res.errors ? Object.keys(res.errors) : []
      setTrMsg(m => ({ ...m, [doc.id]: { ok: failed.length === 0, text: failed.length ? `Přeloženo: ${langs.join(', ')} · selhalo: ${failed.join(', ')} (${Object.values(res.errors)[0]})` : `Přeloženo do: ${langs.join(', ')}` } }))
      load()
    } else {
      setTrMsg(m => ({ ...m, [doc.id]: { ok: false, text: 'Překlad selhal: ' + (res?.error || 'neznámá chyba') } }))
    }
  }

  const load = useCallback(async () => {
    setLoading(true); setError(null)
    const { data, error: err } = await supabase
      .from('custom_documents').select('*').order('sort_order').order('title')
    if (err) {
      // tabulka ještě neexistuje → schovej sekci místo červené chyby
      if (/relation .*custom_documents.* does not exist|could not find the table/i.test(err.message || '')) {
        setTableMissing(true)
      } else setError(err.message)
    } else { setDocs(data || []); setTableMissing(false) }
    setLoading(false)
  }, [])

  useEffect(() => { load() }, [load])

  async function handleDelete(doc) {
    setToDelete(null)
    const { error: err } = await debugAction('customDocument.delete', 'CustomDocumentsSection', () =>
      supabase.from('custom_documents').delete().eq('id', doc.id), { id: doc.id })
    if (err) { setError(err.message); return }
    load()
  }

  if (tableMissing) return null
  if (loading) return <div className="flex justify-center py-8"><div className="animate-spin rounded-full h-7 w-7 border-t-2 border-brand-gd" /></div>

  return (
    <div className="space-y-3 mt-8">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#0f1a14' }}>Vlastní dokumenty</h3>
          <p className="text-sm mt-1" style={{ color: '#1a2e22' }}>
            Vlastní texty nebo nahraná PDF. Se zapnutým „Zobrazit na webu" se automaticky objeví v sekci
            {' '}<strong>Dokumenty a návody</strong> na webu vedle ostatních ke stažení. Pro cizojazyčné verze webu
            klikni <strong>🌍 Přeložit</strong> — Claude přeloží obsah (i z nahraného PDF) do 6 jazyků; cizojazyčná
            verze se pak zobrazí jako přeložená HTML stránka (český originál zůstává beze změny).
          </p>
        </div>
        <Button green onClick={() => setEditing({ kind: 'html', title: '', slug: '', description: '', content_html: '', pdf_path: '', show_on_web: true, sort_order: (docs.reduce((m, d) => Math.max(m, d.sort_order || 0), 0) + 10), active: true })}>
          + Nový dokument
        </Button>
      </div>

      {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {docs.length === 0 ? (
        <div className="p-3 rounded-card text-center" style={{ background: '#f1faf7', fontSize: 13, color: '#1a2e22' }}>
          Zatím žádné vlastní dokumenty. Klikněte „+ Nový dokument" pro vytvoření textu nebo nahrání PDF.
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-3">
          {docs.map(d => (
            <Card key={d.id}>
              <div className="flex items-start justify-between gap-3 flex-wrap">
                <div className="flex items-start gap-3" style={{ minWidth: 0, flex: 1 }}>
                  <span style={{ fontSize: 26 }}>{d.kind === 'pdf' ? '📎' : '📄'}</span>
                  <div style={{ minWidth: 0 }}>
                    <h4 className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>
                      {d.title || '(bez názvu)'}{' '}
                      <span style={{ fontSize: 11, fontWeight: 700, color: d.active ? '#15803d' : '#b45309' }}>
                        {d.active ? '' : '· skrytý'}{d.show_on_web ? '' : ' · jen interně'}
                      </span>
                    </h4>
                    {d.description && <p className="text-sm mt-1" style={{ color: '#1a2e22' }}>{d.description}</p>}
                    <div className="flex items-center gap-3 mt-1 flex-wrap text-sm" style={{ color: '#6b7a72' }}>
                      <span>/dokumenty/{d.slug}</span>
                      <span>{d.kind === 'pdf' ? 'PDF' : `HTML · ${(d.content_html || '').length} znaků`}</span>
                      {d.updated_at && <span>upraveno {new Date(d.updated_at).toLocaleDateString('cs-CZ')}</span>}
                      <span>{(() => { const ks = Object.keys(d.translations || {}).filter(k => TRANSLATE_TARGET_LANGS.includes(k)); return ks.length ? `🌍 přeloženo: ${ks.join(', ')}` : '🌍 jen česky' })()}</span>
                    </div>
                    {trMsg[d.id] && <p className="text-sm mt-1" style={{ color: trMsg[d.id].ok ? '#15803d' : '#dc2626' }}>{trMsg[d.id].text}</p>}
                  </div>
                </div>
                <div className="flex gap-2 shrink-0">
                  {d.kind === 'pdf' && d.pdf_path
                    ? <a href={d.pdf_path} target="_blank" rel="noopener"><Button>Otevřít PDF</Button></a>
                    : <Button onClick={() => setPreview(d)}>Náhled</Button>}
                  <Button onClick={() => handleTranslate(d)} disabled={translatingId === d.id}>{translatingId === d.id ? 'Překládám…' : '🌍 Přeložit'}</Button>
                  <Button green onClick={() => setEditing(d)}>Upravit</Button>
                  <Button onClick={() => setToDelete(d)}>Smazat</Button>
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}

      {editing && (
        <EditCustomDocModal
          doc={editing}
          existingSlugs={docs.filter(x => x.id !== editing.id).map(x => x.slug)}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load() }}
        />
      )}

      {preview && (
        <Modal open title={`Náhled: ${preview.title}`} onClose={() => setPreview(null)} wide>
          <div className="border rounded-lg overflow-hidden" style={{ background: '#fff' }}>
            <iframe srcDoc={buildPreviewHtml(preview.content_html)} style={{ width: '100%', height: '70vh', border: 'none', background: '#fff', display: 'block' }} title="Náhled" />
          </div>
          <div className="flex justify-end mt-4"><Button onClick={() => setPreview(null)}>Zavřít</Button></div>
        </Modal>
      )}

      {toDelete && (
        <ConfirmDialog
          open
          title="Smazat dokument?"
          message={`Opravdu smazat „${toDelete.title}"? Tato akce je nevratná.`}
          danger
          onConfirm={() => handleDelete(toDelete)}
          onCancel={() => setToDelete(null)}
        />
      )}
    </div>
  )
}

function EditCustomDocModal({ doc, existingSlugs, onClose, onSaved }) {
  const isNew = !doc.id
  const [title, setTitle] = useState(doc.title || '')
  const [slug, setSlug] = useState(doc.slug || '')
  const [slugTouched, setSlugTouched] = useState(!isNew)
  const [description, setDescription] = useState(doc.description || '')
  const [kind, setKind] = useState(doc.kind || 'html')
  const [content, setContent] = useState(doc.content_html || '')
  const [pdfPath, setPdfPath] = useState(doc.pdf_path || '')
  const [showOnWeb, setShowOnWeb] = useState(doc.show_on_web !== false)
  const [sortOrder, setSortOrder] = useState(doc.sort_order || 100)
  const [active, setActive] = useState(doc.active !== false)
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const [dragOver, setDragOver] = useState(false)
  const [uploading, setUploading] = useState(false)
  const fileRef = useRef(null)

  useEffect(() => {
    if (!slugTouched) setSlug(slugify(title))
  }, [title, slugTouched])

  async function uploadPdf(file) {
    if (!file) return
    if (file.type !== 'application/pdf' && !/\.pdf$/i.test(file.name || '')) { setErr('Vyberte prosím soubor PDF.'); return }
    if (file.size > 25 * 1024 * 1024) { setErr('PDF je příliš velké (max 25 MB).'); return }
    setUploading(true); setErr(null)
    try {
      const base = slugify(title) || slugify(file.name.replace(/\.pdf$/i, '')) || 'dokument'
      const stamp = Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
      const path = `documents/${base}-${stamp}.pdf`
      const { error: upErr } = await supabase.storage.from('media').upload(path, file, { contentType: 'application/pdf', upsert: false })
      if (upErr) throw upErr
      const { data } = supabase.storage.from('media').getPublicUrl(path)
      setPdfPath(data.publicUrl)
    } catch (e) { setErr('Nahrání PDF selhalo: ' + (e.message || e)) } finally { setUploading(false) }
  }

  async function handleSave() {
    setErr(null)
    const finalSlug = slugify(slug)
    if (!title.trim()) return setErr('Vyplňte název.')
    if (!finalSlug) return setErr('Vyplňte platný odkaz (slug).')
    if (existingSlugs.includes(finalSlug)) return setErr('Tento odkaz (slug) už používá jiný dokument.')
    if (kind === 'html' && !content.trim()) return setErr('Vyplňte obsah dokumentu.')
    if (kind === 'pdf' && !pdfPath) return setErr('Nahrajte PDF soubor.')

    setSaving(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      let updatedBy = null
      if (user?.id) {
        const { data: adminRow } = await supabase.from('admin_users').select('id').eq('id', user.id).maybeSingle()
        if (adminRow) updatedBy = user.id
      }
      const payload = {
        title: title.trim(),
        slug: finalSlug,
        description: description.trim() || null,
        kind,
        content_html: kind === 'html' ? content : null,
        pdf_path: kind === 'pdf' ? pdfPath : null,
        show_on_web: showOnWeb,
        sort_order: Number(sortOrder) || 100,
        active,
        ...(updatedBy ? { updated_by: updatedBy } : {}),
      }
      if (isNew) {
        const res = await debugAction('customDocument.create', 'EditCustomDocModal', () =>
          supabase.from('custom_documents').insert({ ...payload, version: 1 }).select().single(),
          { ...payload, content_html: `[${(content || '').length} chars]` })
        if (res?.error) throw res.error
      } else {
        const res = await debugAction('customDocument.update', 'EditCustomDocModal', () =>
          supabase.from('custom_documents').update({ ...payload, version: (doc.version || 1) + 1 }).eq('id', doc.id),
          { id: doc.id, ...payload, content_html: `[${(content || '').length} chars]` })
        if (res?.error) throw res.error
      }
      onSaved()
    } catch (e) { setErr(e.message || String(e)) } finally { setSaving(false) }
  }

  const stickyBar = {
    position: 'sticky', bottom: -28, left: 0, right: 0, background: '#fff', borderTop: '1px solid #e2ece7',
    margin: '16px -28px -28px', padding: '14px 28px', display: 'flex', justifyContent: 'flex-end', gap: 12, zIndex: 2,
  }

  return (
    <Modal open title={isNew ? 'Nový dokument' : `Upravit: ${doc.title}`} onClose={onClose} wide>
      <div className="space-y-3">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div>
            <Label>Název</Label>
            <input type="text" value={title} onChange={e => setTitle(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          </div>
          <div>
            <Label>Odkaz na webu (slug)</Label>
            <input type="text" value={slug} onChange={e => { setSlug(e.target.value); setSlugTouched(true) }} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="napr-podminky-pojisteni" />
            <p className="text-sm mt-1" style={{ color: '#6b7a72' }}>URL: /dokumenty/{slugify(slug) || '…'}</p>
          </div>
        </div>

        <div>
          <Label>Popisek (volitelné)</Label>
          <input type="text" value={description} onChange={e => setDescription(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>

        <div className="flex items-center gap-4 flex-wrap">
          <Label>Typ dokumentu</Label>
          <label className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: '#1a2e22' }}>
            <input type="radio" checked={kind === 'html'} onChange={() => setKind('html')} /> Text (formátovaný, s proměnnými)
          </label>
          <label className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: '#1a2e22' }}>
            <input type="radio" checked={kind === 'pdf'} onChange={() => setKind('pdf')} /> PDF soubor (beze změn, bez proměnných)
          </label>
        </div>

        {kind === 'html' ? (
          <div>
            <Label>Obsah</Label>
            <p className="text-sm mb-1" style={{ color: '#6b7a72' }}>
              Tip: text z Wordu vložte přes <strong>Ctrl+V</strong> — formátování (písmo, velikost, tučné/kurzíva, barvy, zarovnání, tabulky) zůstane zachováno.
            </p>
            <p className="text-sm mb-1" style={{ color: '#6b7a72' }}>
              Proměnné (na webu se nahradí): <code>{'{{firma}}'}</code> <code>{'{{ico}}'}</code> <code>{'{{adresa}}'}</code> <code>{'{{telefon}}'}</code> <code>{'{{email}}'}</code> <code>{'{{web}}'}</code> <code>{'{{datum}}'}</code>
            </p>
            <RichTextEditor value={content} onChange={setContent} placeholder="Vložte nebo napište obsah dokumentu…" minHeight={340} maxHeight="50vh" />
          </div>
        ) : (
          <div>
            <Label>PDF soubor</Label>
            <div
              onDragOver={e => { e.preventDefault(); setDragOver(true) }}
              onDragLeave={() => setDragOver(false)}
              onDrop={e => { e.preventDefault(); setDragOver(false); uploadPdf(e.dataTransfer.files?.[0]) }}
              onClick={() => fileRef.current?.click()}
              style={{
                border: '2px dashed ' + (dragOver ? '#74FB71' : '#d4e8e0'), borderRadius: 12, padding: 24,
                textAlign: 'center', background: dragOver ? '#f0fdf4' : '#f1faf7', cursor: 'pointer', color: '#1a2e22',
              }}
            >
              {uploading ? 'Nahrávám PDF…' : pdfPath
                ? <>PDF nahráno ✓ <span style={{ display: 'block', fontSize: 12, color: '#6b7a72', wordBreak: 'break-all', marginTop: 4 }}>{pdfPath}</span><span style={{ display: 'block', fontSize: 12, marginTop: 6 }}>Klikněte nebo přetáhněte pro nahrazení.</span></>
                : <>Přetáhněte sem PDF soubor nebo klikněte pro výběr <span style={{ display: 'block', fontSize: 12, color: '#6b7a72', marginTop: 4 }}>max 25 MB</span></>}
              <input ref={fileRef} type="file" accept="application/pdf,.pdf" hidden onChange={e => uploadPdf(e.target.files?.[0])} />
            </div>
          </div>
        )}

        <div className="flex items-center gap-5 flex-wrap pt-1">
          <label className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: '#1a2e22' }}>
            <input type="checkbox" checked={showOnWeb} onChange={e => setShowOnWeb(e.target.checked)} /> Zobrazit na webu (Dokumenty a návody)
          </label>
          <label className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: '#1a2e22' }}>
            <input type="checkbox" checked={active} onChange={e => setActive(e.target.checked)} /> Aktivní
          </label>
          <label className="flex items-center gap-2 text-sm" style={{ color: '#1a2e22' }}>
            Pořadí <input type="number" value={sortOrder} onChange={e => setSortOrder(e.target.value)} className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 80 }} />
          </label>
        </div>
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}

      <div style={stickyBar}>
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || uploading}>{saving ? 'Ukládám…' : isNew ? 'Vytvořit' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
