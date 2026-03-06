import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import Modal from '../../components/ui/Modal'

export default function PagesTab() {
  const [pages, setPages] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [editing, setEditing] = useState(null)
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const { data, error: err } = await supabase.from('cms_pages').select('*').order('title')
    if (err) setError(err.message)
    else setPages(data || [])
    setLoading(false)
  }

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová stránka</Button>
        </div>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Název</TH><TH>Slug</TH><TH>Stav</TH><TH>Poslední úprava</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {pages.map(p => (
              <TRow key={p.id}>
                <TD bold>{p.title}</TD>
                <TD mono>{p.slug}</TD>
                <TD>
                  <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                    style={{
                      padding: '4px 10px',
                      background: p.published ? '#dcfce7' : '#fef3c7',
                      color: p.published ? '#1a8a18' : '#b45309',
                    }}>
                    {p.published ? 'Publikováno' : 'Koncept'}
                  </span>
                </TD>
                <TD>{p.updated_at ? new Date(p.updated_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                <TD>
                  <button onClick={() => setEditing(p)} className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer"
                    style={{ padding: '3px 8px', background: '#f1faf7', color: '#4a6357', border: 'none' }}>
                    Upravit
                  </button>
                </TD>
              </TRow>
            ))}
            {pages.length === 0 && <TRow><TD>Žádné stránky</TD></TRow>}
          </tbody>
        </Table>
      )}

      {(showAdd || editing) && (
        <PageModal entry={editing} onClose={() => { setShowAdd(false); setEditing(null) }} onSaved={() => { setShowAdd(false); setEditing(null); load() }} />
      )}
    </div>
  )
}

function PageModal({ entry, onClose, onSaved }) {
  const [form, setForm] = useState(entry ? {
    title: entry.title || '', slug: entry.slug || '', content: entry.content || '', published: entry.published ?? false,
  } : { title: '', slug: '', content: '', published: false })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const payload = { ...form, updated_at: new Date().toISOString() }
      if (entry) {
        const result = await debugAction('cmsPage.update', 'PageModal', () =>
          supabase.from('cms_pages').update(payload).eq('id', entry.id)
        , payload)
        if (result?.error) throw result.error
      } else {
        const result = await debugAction('cmsPage.create', 'PageModal', () =>
          supabase.from('cms_pages').insert(payload)
        , payload)
        if (result?.error) throw result.error
      }
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: entry ? 'cms_page_updated' : 'cms_page_created', details: { slug: form.slug } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={entry ? `Upravit: ${entry.title}` : 'Nová stránka'} onClose={onClose} wide>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div><Label>Název</Label><input value={form.title} onChange={e => set('title', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
          <div><Label>Slug</Label><input value={form.slug} onChange={e => set('slug', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        </div>
        <div>
          <Label>Stav</Label>
          <select value={form.published ? 'true' : 'false'} onChange={e => set('published', e.target.value === 'true')} className="rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="false">Koncept</option>
            <option value="true">Publikováno</option>
          </select>
        </div>
        <div>
          <Label>Obsah (Markdown)</Label>
          <textarea value={form.content} onChange={e => set('content', e.target.value)}
            className="w-full rounded-btn text-sm outline-none font-mono"
            style={{ ...inputStyle, minHeight: 300, resize: 'vertical' }} />
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.title}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
