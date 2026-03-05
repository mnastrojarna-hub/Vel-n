import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'

const GROUPS = ['general', 'pricing', 'contact', 'legal']

export default function VariablesTab() {
  const [vars, setVars] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [filterGroup, setFilterGroup] = useState('')
  const [editing, setEditing] = useState(null)
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => { load() }, [filterGroup])

  async function load() {
    setLoading(true)
    let query = supabase.from('cms_variables').select('*').order('key')
    const { data, error: err } = await query
    if (err) setError(err.message)
    else setVars(data || [])
    setLoading(false)
  }

  async function saveInline(id, value) {
    const { error } = await supabase.from('cms_variables').update({ value }).eq('id', id)
    if (error) setError(error.message)
    else {
      setVars(v => v.map(item => item.id === id ? { ...item, value } : item))
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'cms_variable_updated', details: { id } })
    }
  }

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <select value={filterGroup} onChange={e => setFilterGroup(e.target.value)}
          className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
          <option value="">Všechny skupiny</option>
          {GROUPS.map(g => <option key={g} value={g}>{g}</option>)}
        </select>
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová proměnná</Button>
        </div>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Skupina</TH><TH>Klíč</TH><TH>Hodnota</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {vars.map(v => (
              <TRow key={v.id}>
                <TD>
                  <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                    style={{ padding: '3px 8px', background: '#f1faf7', color: '#4a6357' }}>
                    {v.group}
                  </span>
                </TD>
                <TD mono bold>{v.key}</TD>
                <TD>
                  <InlineEdit value={v.value} onSave={val => saveInline(v.id, val)} />
                </TD>
                <TD>
                  <button onClick={() => setEditing(v)} className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer"
                    style={{ padding: '3px 8px', background: '#f1faf7', color: '#4a6357', border: 'none' }}>
                    Upravit
                  </button>
                </TD>
              </TRow>
            ))}
            {vars.length === 0 && <TRow><TD>Žádné proměnné</TD></TRow>}
          </tbody>
        </Table>
      )}

      {(showAdd || editing) && (
        <VarModal entry={editing} onClose={() => { setShowAdd(false); setEditing(null) }} onSaved={() => { setShowAdd(false); setEditing(null); load() }} />
      )}
    </div>
  )
}

function InlineEdit({ value, onSave }) {
  const [val, setVal] = useState(value || '')
  const [changed, setChanged] = useState(false)
  return (
    <div className="flex items-center gap-1">
      <input value={val} onChange={e => { setVal(e.target.value); setChanged(true) }}
        className="rounded-btn text-sm outline-none flex-1"
        style={{ padding: '4px 8px', background: changed ? '#fef3c7' : 'transparent', border: '1px solid transparent', color: '#0f1a14' }}
        onBlur={() => { if (changed) { onSave(val); setChanged(false) } }}
        onKeyDown={e => { if (e.key === 'Enter') { onSave(val); setChanged(false) } }}
      />
    </div>
  )
}

function VarModal({ entry, onClose, onSaved }) {
  const [form, setForm] = useState(entry ? { key: entry.key, value: entry.value, group: entry.group } : { key: '', value: '', group: 'general' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { group: _g, ...payload } = form
      if (entry) {
        const { error } = await supabase.from('cms_variables').update(payload).eq('id', entry.id)
        if (error) throw error
      } else {
        const { error } = await supabase.from('cms_variables').insert(payload)
        if (error) throw error
      }
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: entry ? 'cms_var_updated' : 'cms_var_created', details: { key: form.key } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={entry ? 'Upravit proměnnou' : 'Nová proměnná'} onClose={onClose}>
      <div className="space-y-3">
        <div>
          <Label>Skupina</Label>
          <select value={form.group} onChange={e => set('group', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            {GROUPS.map(g => <option key={g} value={g}>{g}</option>)}
          </select>
        </div>
        <div><Label>Klíč</Label><input value={form.key} onChange={e => set('key', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Hodnota</Label><textarea value={form.value} onChange={e => set('value', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 80, resize: 'vertical' }} /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.key}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
