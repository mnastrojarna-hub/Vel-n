import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'

const DOC_TYPES = {
  contract: { label: 'Smlouva', color: '#1a8a18', bg: '#dcfce7' },
  amendment: { label: 'Dodatek', color: '#2563eb', bg: '#dbeafe' },
  termination: { label: 'Vypoved', color: '#dc2626', bg: '#fee2e2' },
  agreement: { label: 'Dohoda', color: '#7c3aed', bg: '#ede9fe' },
  certificate: { label: 'Osvedceni', color: '#0891b2', bg: '#cffafe' },
  other: { label: 'Jine', color: '#6b7280', bg: '#f3f4f6' },
}

export default function DocumentsTab() {
  const [employees, setEmployees] = useState([])
  const [selEmp, setSelEmp] = useState(null)
  const [docs, setDocs] = useState([])
  const [loading, setLoading] = useState(true)
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => {
    supabase.from('acc_employees').select('id, name, active').eq('active', true).order('name')
      .then(({ data }) => { setEmployees(data || []); if (data?.length) setSelEmp(data[0].id); setLoading(false) })
  }, [])

  useEffect(() => { if (selEmp) loadDocs() }, [selEmp])

  async function loadDocs() {
    const { data } = await supabase.from('emp_documents').select('*')
      .eq('employee_id', selEmp).order('created_at', { ascending: false })
    setDocs(data || [])
  }

  async function deleteDoc(id) {
    if (!confirm('Opravdu smazat dokument?')) return
    await supabase.from('emp_documents').delete().eq('id', id)
    loadDocs()
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  const activeCount = docs.filter(d => !d.valid_until || new Date(d.valid_until) >= new Date()).length
  const expiredCount = docs.filter(d => d.valid_until && new Date(d.valid_until) < new Date()).length

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <select value={selEmp || ''} onChange={e => setSelEmp(e.target.value)}
          className="rounded-btn text-sm outline-none font-bold"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          {employees.map(e => <option key={e.id} value={e.id}>{e.name}</option>)}
        </select>
        <Button green onClick={() => setShowAdd(true)}>+ Novy dokument</Button>
        <span className="text-sm font-bold" style={{ color: '#1a8a18' }}>{activeCount} platnych</span>
        {expiredCount > 0 && <span className="text-sm font-bold" style={{ color: '#dc2626' }}>{expiredCount} expirovanych</span>}
      </div>

      <Table>
        <thead>
          <TRow header>
            <TH>Nazev</TH><TH>Typ</TH><TH>Popis</TH><TH>Platnost od</TH><TH>Platnost do</TH><TH>Stav</TH><TH>Akce</TH>
          </TRow>
        </thead>
        <tbody>
          {docs.map(d => {
            const expired = d.valid_until && new Date(d.valid_until) < new Date()
            return (
              <TRow key={d.id}>
                <TD bold>{d.name}</TD>
                <TD><Badge {...(DOC_TYPES[d.type] || DOC_TYPES.other)} /></TD>
                <TD>{d.description || '—'}</TD>
                <TD>{d.valid_from ? new Date(d.valid_from).toLocaleDateString('cs-CZ') : '—'}</TD>
                <TD>{d.valid_until ? new Date(d.valid_until).toLocaleDateString('cs-CZ') : 'Neurcito'}</TD>
                <TD><span className="text-sm font-bold" style={{ color: expired ? '#dc2626' : '#1a8a18' }}>
                  {expired ? 'Expirovano' : 'Platny'}</span></TD>
                <TD>
                  <div className="flex gap-2">
                    {d.file_url && <a href={d.file_url} target="_blank" rel="noopener noreferrer"
                      className="text-sm font-bold" style={{ color: '#2563eb' }}>Stahnout</a>}
                    <button onClick={() => deleteDoc(d.id)} className="text-sm font-bold cursor-pointer"
                      style={{ color: '#dc2626', background: 'none', border: 'none' }}>Smazat</button>
                  </div>
                </TD>
              </TRow>
            )
          })}
          {docs.length === 0 && <TRow><TD>Zadne dokumenty</TD></TRow>}
        </tbody>
      </Table>

      {showAdd && <DocModal empId={selEmp} onClose={() => setShowAdd(false)}
        onSaved={() => { setShowAdd(false); loadDocs() }} />}
    </div>
  )
}

function DocModal({ empId, onClose, onSaved }) {
  const [form, setForm] = useState({ name: '', type: 'contract', description: '', file_url: '', valid_from: '', valid_until: '' })
  const [saving, setSaving] = useState(false)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const iStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }

  async function save() {
    if (!form.name) return
    setSaving(true)
    try {
      const { error } = await supabase.from('emp_documents').insert({
        employee_id: empId, name: form.name, type: form.type,
        description: form.description || null, file_url: form.file_url || null,
        valid_from: form.valid_from || null, valid_until: form.valid_until || null,
      })
      if (error) throw error
      onSaved()
    } catch (e) { alert(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Novy dokument" onClose={onClose}>
      <div className="space-y-3">
        <div><Lbl>Nazev</Lbl><input type="text" value={form.name} onChange={e => set('name', e.target.value)}
          placeholder="Pracovni smlouva" className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>Typ</Lbl><select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle}>
          {Object.entries(DOC_TYPES).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
        </select></div>
        <div><Lbl>Popis</Lbl><input type="text" value={form.description} onChange={e => set('description', e.target.value)}
          className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>URL souboru</Lbl><input type="url" value={form.file_url} onChange={e => set('file_url', e.target.value)}
          placeholder="https://..." className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div className="grid grid-cols-2 gap-3">
          <div><Lbl>Platnost od</Lbl><input type="date" value={form.valid_from} onChange={e => set('valid_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
          <div><Lbl>Platnost do</Lbl><input type="date" value={form.valid_until} onChange={e => set('valid_until', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        </div>
      </div>
      <div className="flex justify-end gap-2 mt-4">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={save} disabled={saving}>{saving ? 'Ukladam...' : 'Ulozit'}</Button>
      </div>
    </Modal>
  )
}

function Lbl({ children }) {
  return <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</div>
}
