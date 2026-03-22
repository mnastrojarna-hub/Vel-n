import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25
const CT = [
  { value: 'hpp', label: 'HPP' }, { value: 'dpp', label: 'DPP' },
  { value: 'dpc', label: 'DPC' }, { value: 'ico', label: 'ICO' },
]
const CC = { hpp: '#1a8a18', dpp: '#2563eb', dpc: '#7c3aed', ico: '#b45309' }
const CB = { hpp: '#dcfce7', dpp: '#dbeafe', dpc: '#ede9fe', ico: '#fef3c7' }

export default function EmployeeListTab() {
  const [employees, setEmployees] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [editEmp, setEditEmp] = useState(null)
  const [filter, setFilter] = useState('')

  useEffect(() => { load() }, [page, filter])

  async function load() {
    setLoading(true); setError(null)
    try {
      let q = supabase.from('acc_employees').select('*', { count: 'exact' })
        .order('name').range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      if (filter) q = q.eq('contract_type', filter)
      const { data, count, error: e } = await q
      if (e) throw e
      setEmployees(data || []); setTotal(count || 0)
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  const fmt = n => (n || 0).toLocaleString('cs-CZ') + ' Kc'

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <Button green onClick={() => setShowAdd(true)}>+ Novy zamestnanec</Button>
        <select value={filter} onChange={e => { setPage(1); setFilter(e.target.value) }}
          className="rounded-btn text-sm outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Vsechny typy</option>
          {CT.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
        </select>
      </div>
      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Jmeno</TH><TH>Telefon</TH><TH>Email</TH><TH>Pozice</TH>
                <TH>Typ</TH><TH>Hruba mzda</TH><TH>Nastup</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {employees.map(emp => (
                <TRow key={emp.id}>
                  <TD bold>{emp.name}</TD>
                  <TD>{emp.phone || '—'}</TD>
                  <TD>{emp.email || '—'}</TD>
                  <TD>{emp.position || '—'}</TD>
                  <TD><Badge label={CT.find(c => c.value === emp.contract_type)?.label || emp.contract_type}
                    color={CC[emp.contract_type] || '#6b7280'} bg={CB[emp.contract_type] || '#f3f4f6'} /></TD>
                  <TD bold>{fmt(emp.gross_salary)}</TD>
                  <TD>{emp.start_date ? new Date(emp.start_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD><span className="text-sm font-bold" style={{ color: emp.active ? '#1a8a18' : '#dc2626' }}>
                    {emp.active ? 'Aktivni' : 'Neaktivni'}</span></TD>
                  <TD>
                    <button onClick={() => setEditEmp(emp)} className="text-sm font-bold cursor-pointer"
                      style={{ color: '#2563eb', background: 'none', border: 'none' }}>Upravit</button>
                  </TD>
                </TRow>
              ))}
              {employees.length === 0 && <TRow><TD>Zadni zamestnanci</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={Math.ceil(total / PER_PAGE)} onPageChange={setPage} />
        </>
      )}
      {showAdd && <EmpModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
      {editEmp && <EmpModal emp={editEmp} onClose={() => setEditEmp(null)} onSaved={() => { setEditEmp(null); load() }} />}
    </div>
  )
}

function EmpModal({ emp, onClose, onSaved }) {
  const [form, setForm] = useState({
    name: emp?.name || '', contract_type: emp?.contract_type || 'hpp',
    gross_salary: emp?.gross_salary || '', start_date: emp?.start_date || '',
    bank_account: emp?.bank_account || '', tax_discount: emp?.tax_discount || '2570',
    phone: emp?.phone || '', email: emp?.email || '', position: emp?.position || '',
    vacation_days_total: emp?.vacation_days_total || 20, active: emp?.active ?? true,
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const iStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }

  async function save() {
    if (!form.name) { setErr('Vyplnte jmeno'); return }
    setSaving(true); setErr(null)
    try {
      const payload = {
        name: form.name, contract_type: form.contract_type,
        gross_salary: parseFloat(form.gross_salary) || 0,
        start_date: form.start_date || null, bank_account: form.bank_account || null,
        tax_discount: parseFloat(form.tax_discount) || 2570,
        phone: form.phone || null, email: form.email || null, position: form.position || null,
        vacation_days_total: parseInt(form.vacation_days_total) || 20, active: form.active,
      }
      const { error } = emp
        ? await supabase.from('acc_employees').update(payload).eq('id', emp.id)
        : await supabase.from('acc_employees').insert(payload)
      if (error) throw error
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={emp ? 'Upravit zamestnance' : 'Novy zamestnanec'} onClose={onClose}>
      {err && <div className="mb-3 p-2 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{err}</div>}
      <div className="grid grid-cols-2 gap-3">
        <div><Lbl>Jmeno</Lbl><input type="text" value={form.name} onChange={e => set('name', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>Pozice</Lbl><input type="text" value={form.position} onChange={e => set('position', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>Telefon</Lbl><input type="text" value={form.phone} onChange={e => set('phone', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>Email</Lbl><input type="email" value={form.email} onChange={e => set('email', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>Typ smlouvy</Lbl><select value={form.contract_type} onChange={e => set('contract_type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle}>
          {[{v:'hpp',l:'HPP'},{v:'dpp',l:'DPP'},{v:'dpc',l:'DPC'},{v:'ico',l:'ICO'}].map(c => <option key={c.v} value={c.v}>{c.l}</option>)}
        </select></div>
        <div><Lbl>Hruba mzda (Kc)</Lbl><input type="number" value={form.gross_salary} onChange={e => set('gross_salary', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>Datum nastupu</Lbl><input type="date" value={form.start_date} onChange={e => set('start_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>Bankovni ucet</Lbl><input type="text" value={form.bank_account} onChange={e => set('bank_account', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>Sleva na dani (Kc)</Lbl><input type="number" value={form.tax_discount} onChange={e => set('tax_discount', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        <div><Lbl>Dnu dovolene</Lbl><input type="number" value={form.vacation_days_total} onChange={e => set('vacation_days_total', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={iStyle} /></div>
        {emp && <div><Lbl>Stav</Lbl><label className="flex items-center gap-2 cursor-pointer mt-1">
          <input type="checkbox" checked={form.active} onChange={e => set('active', e.target.checked)} className="w-4 h-4 accent-green-500" />
          <span className="text-sm font-bold">{form.active ? 'Aktivni' : 'Neaktivni'}</span>
        </label></div>}
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
