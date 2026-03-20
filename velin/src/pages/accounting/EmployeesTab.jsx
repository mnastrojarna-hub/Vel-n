import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'
import { useDebugMode } from '../../hooks/useDebugMode'

const PER_PAGE = 25

const CONTRACT_TYPES = [
  { value: 'hpp', label: 'HPP (hlavni pracovni pomer)' },
  { value: 'dpp', label: 'DPP (dohoda o provedeni prace)' },
  { value: 'dpc', label: 'DPC (dohoda o pracovni cinnosti)' },
  { value: 'ico', label: 'OSVC / ICO (fakturace)' },
]

const MONTHS = ['Leden','Unor','Brezen','Duben','Kveten','Cerven','Cervenec','Srpen','Zari','Rijen','Listopad','Prosinec']

export default function EmployeesTab() {
  const debugMode = useDebugMode()
  const [employees, setEmployees] = useState([])
  const [payrolls, setPayrolls] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [showPayroll, setShowPayroll] = useState(false)
  const [selectedEmployee, setSelectedEmployee] = useState(null)
  const [subTab, setSubTab] = useState('list')

  useEffect(() => { load() }, [page, subTab])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      if (subTab === 'list') {
        const { data, count, error: err } = await debugAction('employees.list', 'EmployeesTab', () =>
          supabase.from('acc_employees').select('*', { count: 'exact' })
            .order('name', { ascending: true })
            .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
        )
        if (err) throw err
        setEmployees(data || [])
        setTotal(count || 0)
      } else {
        const { data, count, error: err } = await debugAction('payrolls.list', 'EmployeesTab', () =>
          supabase.from('acc_payrolls').select('*, acc_employees(name)', { count: 'exact' })
            .order('year', { ascending: false })
            .order('month', { ascending: false })
            .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
        )
        if (err) throw err
        setPayrolls(data || [])
        setTotal(count || 0)
      }
    } catch (e) {
      debugError('EmployeesTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function generatePayroll(year, month) {
    setError(null)
    try {
      const { data: emps } = await supabase.from('acc_employees').select('*').eq('active', true)
      if (!emps?.length) { setError('Zadni aktivni zamestnanci'); return }

      for (const emp of emps) {
        const existing = await supabase.from('acc_payrolls').select('id')
          .eq('employee_id', emp.id).eq('year', year).eq('month', month).maybeSingle()
        if (existing.data) continue

        const gross = emp.gross_salary || 0
        const calc = calculatePayroll(emp, gross)

        await supabase.from('acc_payrolls').insert({
          employee_id: emp.id,
          year, month,
          gross_salary: gross,
          social_employee: calc.socialEmployee,
          health_employee: calc.healthEmployee,
          tax_advance: calc.taxAdvance,
          net_salary: calc.netSalary,
          social_employer: calc.socialEmployer,
          health_employer: calc.healthEmployer,
          total_employer_cost: calc.totalEmployerCost,
          contract_type: emp.contract_type,
          status: 'prepared',
        })
      }

      // Auto-create accounting entries
      const { data: newPayrolls } = await supabase.from('acc_payrolls').select('*, acc_employees(name)')
        .eq('year', year).eq('month', month)
      for (const p of (newPayrolls || [])) {
        await supabase.from('accounting_entries').insert({
          type: 'expense',
          amount: p.total_employer_cost,
          description: `Mzda ${p.acc_employees?.name} ${month}/${year}`,
          category: 'mzdy',
          date: `${year}-${String(month).padStart(2, '0')}-${month === new Date().getMonth() + 1 ? new Date().getDate() : 28}`,
        })
      }

      await load()
    } catch (e) {
      setError('Chyba generovani: ' + e.message)
    }
  }

  function calculatePayroll(emp, gross) {
    if (emp.contract_type === 'ico') {
      return { socialEmployee: 0, healthEmployee: 0, taxAdvance: 0, netSalary: gross, socialEmployer: 0, healthEmployer: 0, totalEmployerCost: gross }
    }
    if (emp.contract_type === 'dpp' && gross <= 10000) {
      const tax = Math.ceil(gross * 0.15)
      return { socialEmployee: 0, healthEmployee: 0, taxAdvance: tax, netSalary: gross - tax, socialEmployer: 0, healthEmployer: 0, totalEmployerCost: gross }
    }
    // HPP or DPC or DPP above 10k
    const socialEmployee = Math.ceil(gross * 0.065)
    const healthEmployee = Math.ceil(gross * 0.045)
    const superGross = gross
    const taxBase = Math.ceil(superGross / 100) * 100
    const taxAdvance = Math.ceil(taxBase * 0.15) - (emp.tax_discount || 2570)
    const netSalary = gross - socialEmployee - healthEmployee - Math.max(taxAdvance, 0)
    const socialEmployer = Math.ceil(gross * 0.248)
    const healthEmployer = Math.ceil(gross * 0.09)
    const totalEmployerCost = gross + socialEmployer + healthEmployer
    return { socialEmployee, healthEmployee, taxAdvance: Math.max(taxAdvance, 0), netSalary, socialEmployer, healthEmployer, totalEmployerCost }
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kc'
  const totalPages = Math.ceil(total / PER_PAGE)
  const now = new Date()

  return (
    <div>
      <div className="flex gap-2 mb-4">
        {['list', 'payrolls'].map(t => (
          <button key={t} onClick={() => { setSubTab(t); setPage(1) }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '6px 14px', background: subTab === t ? '#1a2e22' : '#f1faf7', color: subTab === t ? '#74FB71' : '#1a2e22', border: 'none' }}>
            {t === 'list' ? 'Zamestnanci' : 'Vypocty mezd'}
          </button>
        ))}
      </div>

      <div className="flex items-center gap-3 mb-4">
        {subTab === 'list' && (
          <Button green onClick={() => setShowAdd(true)}>+ Novy zamestnanec</Button>
        )}
        {subTab === 'payrolls' && (
          <Button green onClick={() => generatePayroll(now.getFullYear(), now.getMonth() + 1)}>
            Generovat mzdy {MONTHS[now.getMonth()]} {now.getFullYear()}
          </Button>
        )}
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : subTab === 'list' ? (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Jmeno</TH><TH>Typ smlouvy</TH><TH>Hruba mzda</TH><TH>Nastup</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {employees.map(e => (
                <TRow key={e.id}>
                  <TD bold>{e.name}</TD>
                  <TD>{CONTRACT_TYPES.find(c => c.value === e.contract_type)?.label || e.contract_type}</TD>
                  <TD bold>{fmt(e.gross_salary)}</TD>
                  <TD>{e.start_date ? new Date(e.start_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>
                    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                      style={{ padding: '4px 10px', background: e.active ? '#dcfce7' : '#fee2e2', color: e.active ? '#1a8a18' : '#dc2626' }}>
                      {e.active ? 'Aktivni' : 'Neaktivni'}
                    </span>
                  </TD>
                  <TD>
                    <button onClick={() => setSelectedEmployee(e)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#2563eb' }}>Detail</button>
                  </TD>
                </TRow>
              ))}
              {employees.length === 0 && <TRow><TD>Zadni zamestnanci</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      ) : (
        <>
          {/* Summary cards */}
          {payrolls.length > 0 && (
            <div className="grid grid-cols-4 gap-3 mb-4">
              <MiniStat label="Hrube mzdy celkem" value={fmt(payrolls.reduce((s, p) => s + (p.gross_salary || 0), 0))} color="#1a2e22" />
              <MiniStat label="Odvody zamestnavatel" value={fmt(payrolls.reduce((s, p) => s + (p.social_employer || 0) + (p.health_employer || 0), 0))} color="#dc2626" />
              <MiniStat label="Ciste mzdy" value={fmt(payrolls.reduce((s, p) => s + (p.net_salary || 0), 0))} color="#1a8a18" />
              <MiniStat label="Celkove naklady" value={fmt(payrolls.reduce((s, p) => s + (p.total_employer_cost || 0), 0))} color="#b45309" />
            </div>
          )}
          <Table>
            <thead>
              <TRow header>
                <TH>Zamestnanec</TH><TH>Obdobi</TH><TH>Hruba</TH><TH>SP zamest.</TH><TH>ZP zamest.</TH>
                <TH>Zaloha dan</TH><TH>Cista</TH><TH>SP firma</TH><TH>ZP firma</TH><TH>Celk. naklad</TH><TH>Stav</TH>
              </TRow>
            </thead>
            <tbody>
              {payrolls.map(p => (
                <TRow key={p.id}>
                  <TD bold>{p.acc_employees?.name || '—'}</TD>
                  <TD>{MONTHS[p.month - 1]} {p.year}</TD>
                  <TD>{fmt(p.gross_salary)}</TD>
                  <TD>{fmt(p.social_employee)}</TD>
                  <TD>{fmt(p.health_employee)}</TD>
                  <TD>{fmt(p.tax_advance)}</TD>
                  <TD bold color="#1a8a18">{fmt(p.net_salary)}</TD>
                  <TD color="#dc2626">{fmt(p.social_employer)}</TD>
                  <TD color="#dc2626">{fmt(p.health_employer)}</TD>
                  <TD bold color="#b45309">{fmt(p.total_employer_cost)}</TD>
                  <TD>
                    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                      style={{ padding: '4px 10px', background: p.status === 'paid' ? '#dcfce7' : '#fef3c7', color: p.status === 'paid' ? '#1a8a18' : '#b45309' }}>
                      {p.status === 'paid' ? 'Vyplaceno' : 'Pripraveno'}
                    </span>
                  </TD>
                </TRow>
              ))}
              {payrolls.length === 0 && <TRow><TD>Zadne vypocty mezd</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddEmployeeModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
      {selectedEmployee && <EmployeeDetailModal employee={selectedEmployee} onClose={() => setSelectedEmployee(null)} onSaved={() => { setSelectedEmployee(null); load() }} />}
    </div>
  )
}

function AddEmployeeModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ name: '', contract_type: 'hpp', gross_salary: '', start_date: '', personal_id: '', bank_account: '', tax_discount: 2570 })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('acc_employees').insert({
        name: form.name,
        contract_type: form.contract_type,
        gross_salary: Number(form.gross_salary) || 0,
        start_date: form.start_date || null,
        personal_id: form.personal_id || null,
        bank_account: form.bank_account || null,
        tax_discount: Number(form.tax_discount) || 2570,
        active: true,
      })
      if (error) throw error
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Novy zamestnanec" onClose={onClose}>
      <div className="space-y-3">
        <div><Label>Jmeno a prijmeni</Label><input type="text" value={form.name} onChange={e => set('name', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Typ smlouvy</Label>
          <select value={form.contract_type} onChange={e => set('contract_type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            {CONTRACT_TYPES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </div>
        <div><Label>Hruba mzda (Kc)</Label><input type="number" value={form.gross_salary} onChange={e => set('gross_salary', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Datum nastupu</Label><input type="date" value={form.start_date} onChange={e => set('start_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Rodne cislo / ID</Label><input type="text" value={form.personal_id} onChange={e => set('personal_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Bankovni ucet</Label><input type="text" value={form.bank_account} onChange={e => set('bank_account', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Sleva na dani (Kc/mes)</Label><input type="number" value={form.tax_discount} onChange={e => set('tax_discount', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.name}>{saving ? 'Ukladam...' : 'Ulozit'}</Button>
      </div>
    </Modal>
  )
}

function EmployeeDetailModal({ employee, onClose, onSaved }) {
  const [form, setForm] = useState({ ...employee })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('acc_employees').update({
        name: form.name,
        contract_type: form.contract_type,
        gross_salary: Number(form.gross_salary) || 0,
        start_date: form.start_date || null,
        end_date: form.end_date || null,
        personal_id: form.personal_id || null,
        bank_account: form.bank_account || null,
        tax_discount: Number(form.tax_discount) || 2570,
        active: form.active,
      }).eq('id', employee.id)
      if (error) throw error
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={`Zamestnanec: ${employee.name}`} onClose={onClose}>
      <div className="space-y-3">
        <div><Label>Jmeno</Label><input type="text" value={form.name || ''} onChange={e => set('name', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Typ smlouvy</Label>
          <select value={form.contract_type} onChange={e => set('contract_type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            {CONTRACT_TYPES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </div>
        <div><Label>Hruba mzda (Kc)</Label><input type="number" value={form.gross_salary || ''} onChange={e => set('gross_salary', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Nastup</Label><input type="date" value={form.start_date || ''} onChange={e => set('start_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Konec</Label><input type="date" value={form.end_date || ''} onChange={e => set('end_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Sleva na dani</Label><input type="number" value={form.tax_discount || ''} onChange={e => set('tax_discount', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div className="flex items-center gap-2">
          <input type="checkbox" checked={form.active} onChange={e => set('active', e.target.checked)} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Aktivni</span>
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukladam...' : 'Ulozit'}</Button>
      </div>
    </Modal>
  )
}

function MiniStat({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
