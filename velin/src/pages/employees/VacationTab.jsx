import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'

const TYPE_MAP = {
  vacation: { label: 'Dovolena', color: '#2563eb', bg: '#dbeafe' },
  sick: { label: 'Nemoc', color: '#b45309', bg: '#fef3c7' },
  personal: { label: 'Osobni', color: '#7c3aed', bg: '#ede9fe' },
  unpaid: { label: 'Neplacene', color: '#dc2626', bg: '#fee2e2' },
  maternity: { label: 'Materstvi', color: '#0891b2', bg: '#cffafe' },
  other: { label: 'Jine', color: '#6b7280', bg: '#f3f4f6' },
}
const STATUS_MAP = {
  pending: { label: 'Ceka', color: '#b45309', bg: '#fef3c7' },
  approved: { label: 'Schvaleno', color: '#1a8a18', bg: '#dcfce7' },
  rejected: { label: 'Zamitnuto', color: '#dc2626', bg: '#fee2e2' },
  cancelled: { label: 'Zruseno', color: '#6b7280', bg: '#f3f4f6' },
}

export default function VacationTab() {
  const [employees, setEmployees] = useState([])
  const [selEmp, setSelEmp] = useState(null)
  const [vacations, setVacations] = useState([])
  const [loading, setLoading] = useState(true)
  const [showAdd, setShowAdd] = useState(false)
  const [empData, setEmpData] = useState(null)

  useEffect(() => {
    supabase.from('acc_employees').select('*').eq('active', true).order('name')
      .then(({ data }) => { setEmployees(data || []); if (data?.length) { setSelEmp(data[0].id); setEmpData(data[0]) }; setLoading(false) })
  }, [])

  useEffect(() => {
    if (selEmp) { loadVacations(); setEmpData(employees.find(e => e.id === selEmp)) }
  }, [selEmp])

  async function loadVacations() {
    const { data } = await supabase.from('emp_vacations').select('*')
      .eq('employee_id', selEmp).order('start_date', { ascending: false }).limit(50)
    setVacations(data || [])
  }

  const usedDays = vacations.filter(v => v.status === 'approved' && v.type === 'vacation').reduce((s, v) => s + (v.days || 0), 0)
  const totalDays = empData?.vacation_days_total || 20
  const remaining = totalDays - (empData?.vacation_days_used || usedDays)

  async function approve(id) {
    await supabase.from('emp_vacations').update({ status: 'approved', approved_at: new Date().toISOString() }).eq('id', id)
    loadVacations()
  }
  async function reject(id) {
    await supabase.from('emp_vacations').update({ status: 'rejected' }).eq('id', id)
    loadVacations()
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <select value={selEmp || ''} onChange={e => setSelEmp(e.target.value)}
          className="rounded-btn text-sm outline-none font-bold"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          {employees.map(e => <option key={e.id} value={e.id}>{e.name}</option>)}
        </select>
        <Button green onClick={() => setShowAdd(true)}>+ Nova zadost</Button>
      </div>

      <div className="grid grid-cols-3 gap-3 mb-4">
        <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Narok</div>
          <div className="text-lg font-extrabold" style={{ color: '#2563eb' }}>{totalDays} dni</div></Card>
        <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Cerpano</div>
          <div className="text-lg font-extrabold" style={{ color: '#b45309' }}>{usedDays} dni</div></Card>
        <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Zbyva</div>
          <div className="text-lg font-extrabold" style={{ color: remaining > 0 ? '#1a8a18' : '#dc2626' }}>{remaining} dni</div></Card>
      </div>

      <Table>
        <thead>
          <TRow header>
            <TH>Od</TH><TH>Do</TH><TH>Dni</TH><TH>Typ</TH><TH>Stav</TH><TH>Poznamka</TH><TH>Akce</TH>
          </TRow>
        </thead>
        <tbody>
          {vacations.map(v => (
            <TRow key={v.id}>
              <TD bold>{new Date(v.start_date).toLocaleDateString('cs-CZ')}</TD>
              <TD>{new Date(v.end_date).toLocaleDateString('cs-CZ')}</TD>
              <TD bold>{v.days}</TD>
              <TD><Badge {...(TYPE_MAP[v.type] || TYPE_MAP.other)} /></TD>
              <TD><Badge {...(STATUS_MAP[v.status] || STATUS_MAP.pending)} /></TD>
              <TD>{v.note || '—'}</TD>
              <TD>
                {v.status === 'pending' && <>
                  <button onClick={() => approve(v.id)} className="text-sm font-bold cursor-pointer mr-2"
                    style={{ color: '#1a8a18', background: 'none', border: 'none' }}>Schvalit</button>
                  <button onClick={() => reject(v.id)} className="text-sm font-bold cursor-pointer"
                    style={{ color: '#dc2626', background: 'none', border: 'none' }}>Zamitnout</button>
                </>}
              </TD>
            </TRow>
          ))}
          {vacations.length === 0 && <TRow><TD>Zadne zaznamy</TD></TRow>}
        </tbody>
      </Table>

      {showAdd && <VacModal empId={selEmp} onClose={() => setShowAdd(false)}
        onSaved={() => { setShowAdd(false); loadVacations() }} />}
    </div>
  )
}

function VacModal({ empId, onClose, onSaved }) {
  const [form, setForm] = useState({ start_date: '', end_date: '', type: 'vacation', note: '' })
  const [saving, setSaving] = useState(false)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const iStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }

  function calcDays() {
    if (!form.start_date || !form.end_date) return 0
    const s = new Date(form.start_date), e = new Date(form.end_date)
    let days = 0
    for (let d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) {
      const dow = d.getDay()
      if (dow !== 0 && dow !== 6) days++
    }
    return days
  }

  async function save() {
    if (!form.start_date || !form.end_date) return
    setSaving(true)
    try {
      const { error } = await supabase.from('emp_vacations').insert({
        employee_id: empId, start_date: form.start_date, end_date: form.end_date,
        days: calcDays(), type: form.type, status: 'pending', note: form.note || null,
      })
      if (error) throw error
      onSaved()
    } catch (e) { alert(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nova zadost o dovolenou" onClose={onClose}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div><Lbl>Od</Lbl><input type="date" value={form.start_date} onChange={e => set('start_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
          <div><Lbl>Do</Lbl><input type="date" value={form.end_date} onChange={e => set('end_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        </div>
        {form.start_date && form.end_date && <div className="text-sm font-bold" style={{ color: '#2563eb' }}>Pracovnich dni: {calcDays()}</div>}
        <div><Lbl>Typ</Lbl><select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle}>
          {Object.entries(TYPE_MAP).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
        </select></div>
        <div><Lbl>Poznamka</Lbl><input type="text" value={form.note} onChange={e => set('note', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
      </div>
      <div className="flex justify-end gap-2 mt-4">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={save} disabled={saving}>{saving ? 'Ukladam...' : 'Podat zadost'}</Button>
      </div>
    </Modal>
  )
}

function Lbl({ children }) {
  return <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</div>
}
