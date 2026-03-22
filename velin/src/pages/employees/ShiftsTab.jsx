import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'

const SHIFT_MAP = {
  morning: { label: 'Rano', color: '#b45309', bg: '#fef3c7' },
  afternoon: { label: 'Odpoledne', color: '#2563eb', bg: '#dbeafe' },
  night: { label: 'Noc', color: '#7c3aed', bg: '#ede9fe' },
  full_day: { label: 'Cely den', color: '#1a8a18', bg: '#dcfce7' },
  free: { label: 'Volno', color: '#6b7280', bg: '#f3f4f6' },
}
const DAYS_CS = ['Po', 'Ut', 'St', 'Ct', 'Pa', 'So', 'Ne']

function getWeekDates(offset = 0) {
  const now = new Date()
  const monday = new Date(now)
  monday.setDate(now.getDate() - ((now.getDay() + 6) % 7) + offset * 7)
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(monday)
    d.setDate(monday.getDate() + i)
    return d.toISOString().slice(0, 10)
  })
}

export default function ShiftsTab() {
  const [employees, setEmployees] = useState([])
  const [branches, setBranches] = useState([])
  const [shifts, setShifts] = useState([])
  const [weekOffset, setWeekOffset] = useState(0)
  const [loading, setLoading] = useState(true)
  const [showAdd, setShowAdd] = useState(null)

  const weekDates = getWeekDates(weekOffset)

  useEffect(() => {
    Promise.all([
      supabase.from('acc_employees').select('id, name, active').eq('active', true).order('name'),
      supabase.from('branches').select('id, name'),
    ]).then(([empRes, brRes]) => {
      setEmployees(empRes.data || [])
      setBranches(brRes.data || [])
      setLoading(false)
    })
  }, [])

  useEffect(() => { loadShifts() }, [weekOffset, employees])

  async function loadShifts() {
    if (!employees.length) return
    const { data } = await supabase.from('emp_shifts').select('*')
      .gte('date', weekDates[0]).lte('date', weekDates[6])
    setShifts(data || [])
  }

  const shiftMap = {}
  shifts.forEach(s => { shiftMap[`${s.employee_id}_${s.date}`] = s })

  const weekLabel = `${new Date(weekDates[0]).toLocaleDateString('cs-CZ')} - ${new Date(weekDates[6]).toLocaleDateString('cs-CZ')}`

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <button onClick={() => setWeekOffset(w => w - 1)} className="rounded-btn cursor-pointer"
          style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>◀</button>
        <span className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>{weekLabel}</span>
        <button onClick={() => setWeekOffset(w => w + 1)} className="rounded-btn cursor-pointer"
          style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>▶</button>
        <button onClick={() => setWeekOffset(0)} className="rounded-btn cursor-pointer text-sm font-bold"
          style={{ padding: '6px 12px', background: '#74FB71', border: 'none', color: '#1a2e22' }}>Dnes</button>
      </div>

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full" style={{ borderCollapse: 'collapse' }}>
            <thead>
              <tr>
                <th className="text-left text-sm font-extrabold uppercase p-2" style={{ color: '#1a2e22', minWidth: 140 }}>Zamestnanec</th>
                {weekDates.map((d, i) => (
                  <th key={d} className="text-center text-sm font-extrabold uppercase p-2" style={{ color: '#1a2e22', minWidth: 100 }}>
                    {DAYS_CS[i]}<br /><span className="text-[10px] font-bold" style={{ color: '#6b7280' }}>{new Date(d).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric' })}</span>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {employees.map(emp => (
                <tr key={emp.id} style={{ borderTop: '1px solid #d4e8e0' }}>
                  <td className="text-sm font-bold p-2" style={{ color: '#1a2e22' }}>{emp.name}</td>
                  {weekDates.map(date => {
                    const shift = shiftMap[`${emp.id}_${date}`]
                    const st = shift ? SHIFT_MAP[shift.shift_type] : null
                    return (
                      <td key={date} className="text-center p-1">
                        <div onClick={() => setShowAdd({ empId: emp.id, date, shift })}
                          className="rounded-lg cursor-pointer transition-all hover:ring-2 hover:ring-green-300"
                          style={{ padding: '8px 4px', background: st ? st.bg : '#f9fafb', border: `1px solid ${st ? st.color + '30' : '#e5e7eb'}`, minHeight: 40 }}>
                          {shift ? <>
                            <div className="text-[10px] font-bold" style={{ color: st?.color }}>{st?.label}</div>
                            {shift.start_time && <div className="text-[9px]" style={{ color: '#6b7280' }}>{shift.start_time?.slice(0, 5)}-{shift.end_time?.slice(0, 5)}</div>}
                          </> : <div className="text-[10px]" style={{ color: '#d1d5db' }}>+</div>}
                        </div>
                      </td>
                    )
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      {showAdd && <ShiftModal {...showAdd} branches={branches}
        onClose={() => setShowAdd(null)} onSaved={() => { setShowAdd(null); loadShifts() }} />}
    </div>
  )
}

function ShiftModal({ empId, date, shift, branches, onClose, onSaved }) {
  const [form, setForm] = useState({
    shift_type: shift?.shift_type || 'morning',
    start_time: shift?.start_time?.slice(0, 5) || '06:00',
    end_time: shift?.end_time?.slice(0, 5) || '14:00',
    branch_id: shift?.branch_id || '',
    note: shift?.note || '',
  })
  const [saving, setSaving] = useState(false)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const iStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }

  const defaultTimes = { morning: ['06:00', '14:00'], afternoon: ['14:00', '22:00'], night: ['22:00', '06:00'], full_day: ['08:00', '20:00'], free: ['', ''] }
  function onTypeChange(t) {
    const [s, e] = defaultTimes[t] || ['', '']
    setForm(f => ({ ...f, shift_type: t, start_time: s, end_time: e }))
  }

  async function save() {
    setSaving(true)
    const payload = {
      employee_id: empId, date, shift_type: form.shift_type,
      start_time: form.start_time || null, end_time: form.end_time || null,
      branch_id: form.branch_id || null, note: form.note || null,
    }
    try {
      const { error } = shift
        ? await supabase.from('emp_shifts').update(payload).eq('id', shift.id)
        : await supabase.from('emp_shifts').insert(payload)
      if (error) throw error
      onSaved()
    } catch (e) { alert(e.message) } finally { setSaving(false) }
  }

  async function remove() {
    if (!shift) return
    await supabase.from('emp_shifts').delete().eq('id', shift.id)
    onSaved()
  }

  return (
    <Modal open title={`Smena ${new Date(date).toLocaleDateString('cs-CZ')}`} onClose={onClose}>
      <div className="space-y-3">
        <div><Lbl>Typ smeny</Lbl><select value={form.shift_type} onChange={e => onTypeChange(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle}>
          {Object.entries(SHIFT_MAP).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
        </select></div>
        {form.shift_type !== 'free' && <div className="grid grid-cols-2 gap-3">
          <div><Lbl>Od</Lbl><input type="time" value={form.start_time} onChange={e => set('start_time', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
          <div><Lbl>Do</Lbl><input type="time" value={form.end_time} onChange={e => set('end_time', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        </div>}
        {branches.length > 0 && <div><Lbl>Pobocka</Lbl><select value={form.branch_id} onChange={e => set('branch_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle}>
          <option value="">—</option>
          {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
        </select></div>}
        <div><Lbl>Poznamka</Lbl><input type="text" value={form.note} onChange={e => set('note', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
      </div>
      <div className="flex justify-between mt-4">
        {shift ? <button onClick={remove} className="text-sm font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none' }}>Smazat</button> : <div />}
        <div className="flex gap-2"><Button onClick={onClose}>Zrusit</Button>
          <Button green onClick={save} disabled={saving}>{saving ? 'Ukladam...' : 'Ulozit'}</Button></div>
      </div>
    </Modal>
  )
}

function Lbl({ children }) {
  return <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</div>
}
