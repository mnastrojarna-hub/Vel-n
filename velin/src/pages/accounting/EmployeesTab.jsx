import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

const CONTRACT_TYPES = [
  { value: 'hpp', label: 'HPP' },
  { value: 'dpp', label: 'DPP' },
  { value: 'dpc', label: 'DPC' },
  { value: 'ico', label: 'ICO' },
]

const CONTRACT_COLORS = {
  hpp: '#1a8a18', dpp: '#2563eb', dpc: '#7c3aed', ico: '#b45309',
}
const CONTRACT_BGS = {
  hpp: '#dcfce7', dpp: '#dbeafe', dpc: '#ede9fe', ico: '#fef3c7',
}

export default function EmployeesTab() {
  const [employees, setEmployees] = useState([])
  const [payrolls, setPayrolls] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [showPayroll, setShowPayroll] = useState(null)
  const [filter, setFilter] = useState('')

  useEffect(() => { load() }, [page, filter])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase.from('acc_employees')
        .select('*', { count: 'exact' })
        .order('name', { ascending: true })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      if (filter) query = query.eq('contract_type', filter)
      const { data, count, error: err } = await query
      if (err) throw err
      setEmployees(data || [])
      setTotal(count || 0)
    } catch (e) {
      setError(e.message || 'Chyba pri nacitani zamestnancu')
    } finally {
      setLoading(false)
    }
  }

  async function loadPayrolls(employeeId) {
    const { data } = await supabase.from('acc_payrolls')
      .select('*')
      .eq('employee_id', employeeId)
      .order('period', { ascending: false })
      .limit(24)
    setPayrolls(data || [])
  }

  const fmt = n => (n || 0).toLocaleString('cs-CZ') + ' Kc'
  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <Button green onClick={() => setShowAdd(true)}>+ Novy zamestnanec</Button>
        <select value={filter} onChange={e => { setPage(1); setFilter(e.target.value) }}
          className="rounded-btn text-sm outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Vsechny typy</option>
          {CONTRACT_TYPES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
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
                <TH>Jmeno</TH><TH>Typ smlouvy</TH><TH>Hruba mzda</TH>
                <TH>Sleva na dani</TH><TH>Nastup</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {employees.map(emp => (
                <TRow key={emp.id}>
                  <TD bold>{emp.name}</TD>
                  <TD>
                    <Badge label={CONTRACT_TYPES.find(c => c.value === emp.contract_type)?.label || emp.contract_type}
                      color={CONTRACT_COLORS[emp.contract_type] || '#6b7280'}
                      bg={CONTRACT_BGS[emp.contract_type] || '#f3f4f6'} />
                  </TD>
                  <TD bold>{fmt(emp.gross_salary)}</TD>
                  <TD>{fmt(emp.tax_discount)}</TD>
                  <TD>{emp.start_date ? new Date(emp.start_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>
                    <span className="text-sm font-bold" style={{ color: emp.active ? '#1a8a18' : '#dc2626' }}>
                      {emp.active ? 'Aktivni' : 'Neaktivni'}
                    </span>
                  </TD>
                  <TD>
                    <button onClick={() => { setShowPayroll(emp); loadPayrolls(emp.id) }}
                      className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>
                      Mzdy
                    </button>
                  </TD>
                </TRow>
              ))}
              {employees.length === 0 && <TRow><TD>Zadni zamestnanci</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddEmployeeModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}

      {showPayroll && (
        <Modal open title={`Mzdy — ${showPayroll.name}`} onClose={() => setShowPayroll(null)}>
          {payrolls.length === 0 ? (
            <p className="text-sm" style={{ color: '#6b7280' }}>Zadne zaznamy o mzdach</p>
          ) : (
            <Table>
              <thead>
                <TRow header>
                  <TH>Obdobi</TH><TH>Hruba</TH><TH>Soc. pojisteni</TH>
                  <TH>Zdrav. pojisteni</TH><TH>Dan</TH><TH>Cista</TH><TH>Stav</TH>
                </TRow>
              </thead>
              <tbody>
                {payrolls.map(p => (
                  <TRow key={p.id}>
                    <TD bold>{p.period}</TD>
                    <TD>{fmt(p.gross)}</TD>
                    <TD>{fmt(p.social_insurance)}</TD>
                    <TD>{fmt(p.health_insurance)}</TD>
                    <TD>{fmt(p.income_tax)}</TD>
                    <TD bold color="#1a8a18">{fmt(p.net)}</TD>
                    <TD>
                      <span className="text-sm font-bold" style={{ color: p.status === 'paid' ? '#1a8a18' : '#b45309' }}>
                        {p.status === 'paid' ? 'Vyplaceno' : p.status === 'calculated' ? 'Vypocteno' : p.status || '—'}
                      </span>
                    </TD>
                  </TRow>
                ))}
              </tbody>
            </Table>
          )}
          <div className="flex justify-end mt-4">
            <Button onClick={() => setShowPayroll(null)}>Zavrit</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}

function AddEmployeeModal({ onClose, onSaved }) {
  const [form, setForm] = useState({
    name: '', contract_type: 'hpp', gross_salary: '', start_date: '',
    bank_account: '', tax_discount: '2570',
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function save() {
    if (!form.name) { setErr('Vyplnte jmeno'); return }
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('acc_employees').insert({
        name: form.name,
        contract_type: form.contract_type,
        gross_salary: parseFloat(form.gross_salary) || 0,
        start_date: form.start_date || null,
        bank_account: form.bank_account || null,
        tax_discount: parseFloat(form.tax_discount) || 2570,
        active: true,
      })
      if (error) throw error
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }

  return (
    <Modal open title="Novy zamestnanec" onClose={onClose}>
      {err && <div className="mb-3 p-2 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{err}</div>}
      <div className="space-y-3">
        <div>
          <Label>Jmeno</Label>
          <input type="text" value={form.name} onChange={e => set('name', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Typ smlouvy</Label>
          <select value={form.contract_type} onChange={e => set('contract_type', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            {CONTRACT_TYPES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </div>
        <div>
          <Label>Hruba mzda (Kc)</Label>
          <input type="number" value={form.gross_salary} onChange={e => set('gross_salary', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Datum nastupu</Label>
          <input type="date" value={form.start_date} onChange={e => set('start_date', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Bankovni ucet</Label>
          <input type="text" value={form.bank_account} onChange={e => set('bank_account', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Sleva na dani (Kc)</Label>
          <input type="number" value={form.tax_discount} onChange={e => set('tax_discount', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>
      <div className="flex justify-end gap-2 mt-4">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={save} disabled={saving}>{saving ? 'Ukladam...' : 'Ulozit'}</Button>
      </div>
    </Modal>
  )
}

function Label({ children }) {
  return <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</div>
}
