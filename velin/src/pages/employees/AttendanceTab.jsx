import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'

const STATUS_MAP = {
  present: { label: 'Pritomen', color: '#1a8a18', bg: '#dcfce7' },
  absent: { label: 'Neomluven', color: '#dc2626', bg: '#fee2e2' },
  sick: { label: 'Nemoc', color: '#b45309', bg: '#fef3c7' },
  vacation: { label: 'Dovolena', color: '#2563eb', bg: '#dbeafe' },
  home_office: { label: 'Home office', color: '#7c3aed', bg: '#ede9fe' },
  half_day: { label: 'Pulden', color: '#0891b2', bg: '#cffafe' },
}

const DAYS_CS = ['Po', 'Ut', 'St', 'Ct', 'Pa', 'So', 'Ne']

function getMonthDays(year, month) {
  const days = []
  const first = new Date(year, month, 1)
  const last = new Date(year, month + 1, 0)
  const startDay = (first.getDay() + 6) % 7
  for (let i = 0; i < startDay; i++) days.push(null)
  for (let d = 1; d <= last.getDate(); d++) days.push(d)
  return days
}

export default function AttendanceTab() {
  const [employees, setEmployees] = useState([])
  const [selEmp, setSelEmp] = useState(null)
  const [year, setYear] = useState(new Date().getFullYear())
  const [month, setMonth] = useState(new Date().getMonth())
  const [records, setRecords] = useState([])
  const [loading, setLoading] = useState(true)
  const [showAdd, setShowAdd] = useState(null)

  useEffect(() => {
    supabase.from('acc_employees').select('id, name, active').eq('active', true).order('name')
      .then(({ data }) => {
        setEmployees(data || [])
        if (data?.length && !selEmp) setSelEmp(data[0].id)
        setLoading(false)
      })
  }, [])

  useEffect(() => { if (selEmp) loadAttendance() }, [selEmp, year, month])

  async function loadAttendance() {
    const start = `${year}-${String(month + 1).padStart(2, '0')}-01`
    const end = `${year}-${String(month + 1).padStart(2, '0')}-${new Date(year, month + 1, 0).getDate()}`
    const { data } = await supabase.from('emp_attendance').select('*')
      .eq('employee_id', selEmp).gte('date', start).lte('date', end)
    setRecords(data || [])
  }

  const days = getMonthDays(year, month)
  const recordMap = {}
  records.forEach(r => { recordMap[new Date(r.date).getDate()] = r })
  const monthNames = ['Leden','Unor','Brezen','Duben','Kveten','Cerven','Cervenec','Srpen','Zari','Rijen','Listopad','Prosinec']

  const totalHours = records.reduce((s, r) => s + (parseFloat(r.hours_worked) || 0), 0)
  const presentDays = records.filter(r => r.status === 'present' || r.status === 'half_day').length
  const sickDays = records.filter(r => r.status === 'sick').length
  const vacDays = records.filter(r => r.status === 'vacation').length

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <select value={selEmp || ''} onChange={e => setSelEmp(e.target.value)}
          className="rounded-btn text-sm outline-none font-bold"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          {employees.map(e => <option key={e.id} value={e.id}>{e.name}</option>)}
        </select>
        <button onClick={() => setMonth(m => m === 0 ? (setYear(y => y - 1), 11) : m - 1)}
          className="rounded-btn cursor-pointer" style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>◀</button>
        <span className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>{monthNames[month]} {year}</span>
        <button onClick={() => setMonth(m => m === 11 ? (setYear(y => y + 1), 0) : m + 1)}
          className="rounded-btn cursor-pointer" style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>▶</button>
      </div>

      <div className="grid grid-cols-4 gap-3 mb-4">
        <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Odpracovano</div>
          <div className="text-lg font-extrabold" style={{ color: '#1a8a18' }}>{totalHours.toFixed(1)} h</div></Card>
        <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Pritomnost</div>
          <div className="text-lg font-extrabold" style={{ color: '#2563eb' }}>{presentDays} dni</div></Card>
        <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Nemoc</div>
          <div className="text-lg font-extrabold" style={{ color: '#b45309' }}>{sickDays} dni</div></Card>
        <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Dovolena</div>
          <div className="text-lg font-extrabold" style={{ color: '#7c3aed' }}>{vacDays} dni</div></Card>
      </div>

      <Card>
        <div className="grid grid-cols-7 gap-1 mb-2">
          {DAYS_CS.map(d => <div key={d} className="text-center text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>{d}</div>)}
        </div>
        <div className="grid grid-cols-7 gap-1">
          {days.map((day, i) => {
            if (!day) return <div key={`e${i}`} />
            const rec = recordMap[day]
            const st = rec ? STATUS_MAP[rec.status] : null
            const isWeekend = ((new Date(year, month, day).getDay() + 6) % 7) >= 5
            return (
              <div key={day} onClick={() => setShowAdd({ day, rec })}
                className="rounded-lg cursor-pointer text-center transition-all hover:ring-2 hover:ring-green-300"
                style={{
                  padding: '8px 4px', minHeight: 60,
                  background: st ? st.bg : isWeekend ? '#f9fafb' : '#f1faf7',
                  border: `1px solid ${st ? st.color + '40' : '#d4e8e0'}`,
                }}>
                <div className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>{day}</div>
                {rec && <>
                  <div className="text-[9px] font-bold mt-1" style={{ color: st?.color }}>{st?.label}</div>
                  {rec.hours_worked > 0 && <div className="text-[9px] font-bold" style={{ color: '#6b7280' }}>{rec.hours_worked}h</div>}
                </>}
              </div>
            )
          })}
        </div>
      </Card>

      {showAdd && <AttendanceModal day={showAdd.day} rec={showAdd.rec} empId={selEmp}
        year={year} month={month} onClose={() => setShowAdd(null)}
        onSaved={() => { setShowAdd(null); loadAttendance() }} />}
    </div>
  )
}

function AttendanceModal({ day, rec, empId, year, month, onClose, onSaved }) {
  const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
  const [form, setForm] = useState({
    status: rec?.status || 'present',
    check_in: rec?.check_in ? rec.check_in.slice(11, 16) : '08:00',
    check_out: rec?.check_out ? rec.check_out.slice(11, 16) : '16:30',
    break_minutes: rec?.break_minutes || 30,
    note: rec?.note || '',
  })
  const [saving, setSaving] = useState(false)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const iStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }

  function calcHours() {
    if (form.status === 'absent' || form.status === 'sick' || form.status === 'vacation') return 0
    const [h1, m1] = form.check_in.split(':').map(Number)
    const [h2, m2] = form.check_out.split(':').map(Number)
    const mins = (h2 * 60 + m2) - (h1 * 60 + m1) - (form.break_minutes || 0)
    return Math.max(0, +(mins / 60).toFixed(2))
  }

  async function save() {
    setSaving(true)
    const hours = calcHours()
    const payload = {
      employee_id: empId, date: dateStr, status: form.status,
      check_in: ['present', 'half_day', 'home_office'].includes(form.status) ? `${dateStr}T${form.check_in}:00Z` : null,
      check_out: ['present', 'half_day', 'home_office'].includes(form.status) ? `${dateStr}T${form.check_out}:00Z` : null,
      break_minutes: form.break_minutes, hours_worked: hours, note: form.note || null,
    }
    try {
      const { error } = rec
        ? await supabase.from('emp_attendance').update(payload).eq('id', rec.id)
        : await supabase.from('emp_attendance').insert(payload)
      if (error) throw error
      onSaved()
    } catch (e) { alert(e.message) } finally { setSaving(false) }
  }

  async function remove() {
    if (!rec) return
    await supabase.from('emp_attendance').delete().eq('id', rec.id)
    onSaved()
  }

  return (
    <Modal open title={`Dochazka ${day}. ${month + 1}. ${year}`} onClose={onClose}>
      <div className="space-y-3">
        <div><Lbl>Stav</Lbl>
          <select value={form.status} onChange={e => set('status', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={iStyle}>
            {Object.entries(STATUS_MAP).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select>
        </div>
        {['present', 'half_day', 'home_office'].includes(form.status) && <>
          <div className="grid grid-cols-3 gap-3">
            <div><Lbl>Prichod</Lbl><input type="time" value={form.check_in} onChange={e => set('check_in', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
            <div><Lbl>Odchod</Lbl><input type="time" value={form.check_out} onChange={e => set('check_out', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
            <div><Lbl>Pauza (min)</Lbl><input type="number" value={form.break_minutes} onChange={e => set('break_minutes', parseInt(e.target.value) || 0)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
          </div>
          <div className="text-sm font-bold" style={{ color: '#1a8a18' }}>Odpracovano: {calcHours()} h</div>
        </>}
        <div><Lbl>Poznamka</Lbl><input type="text" value={form.note} onChange={e => set('note', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
      </div>
      <div className="flex justify-between mt-4">
        {rec ? <button onClick={remove} className="text-sm font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none' }}>Smazat</button> : <div />}
        <div className="flex gap-2">
          <Button onClick={onClose}>Zrusit</Button>
          <Button green onClick={save} disabled={saving}>{saving ? 'Ukladam...' : 'Ulozit'}</Button>
        </div>
      </div>
    </Modal>
  )
}

function Lbl({ children }) {
  return <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</div>
}
