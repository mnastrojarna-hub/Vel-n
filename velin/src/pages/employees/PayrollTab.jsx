import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Badge from '../../components/ui/Badge'

export default function PayrollTab() {
  const [employees, setEmployees] = useState([])
  const [selEmp, setSelEmp] = useState(null)
  const [payrolls, setPayrolls] = useState([])
  const [loading, setLoading] = useState(true)
  const [showCalc, setShowCalc] = useState(false)

  useEffect(() => {
    supabase.from('acc_employees').select('*').eq('active', true).order('name')
      .then(({ data }) => { setEmployees(data || []); if (data?.length) setSelEmp(data[0].id); setLoading(false) })
  }, [])

  useEffect(() => { if (selEmp) loadPayrolls() }, [selEmp])

  async function loadPayrolls() {
    const { data } = await supabase.from('acc_payrolls').select('*')
      .eq('employee_id', selEmp).order('period', { ascending: false }).limit(24)
    setPayrolls(data || [])
  }

  const fmt = n => (n || 0).toLocaleString('cs-CZ') + ' Kc'
  const emp = employees.find(e => e.id === selEmp)

  // Souhrn za aktualni rok
  const thisYear = new Date().getFullYear()
  const yearPayrolls = payrolls.filter(p => p.period?.startsWith(String(thisYear)))
  const totalGross = yearPayrolls.reduce((s, p) => s + (p.gross || 0), 0)
  const totalNet = yearPayrolls.reduce((s, p) => s + (p.net || 0), 0)
  const totalSoc = yearPayrolls.reduce((s, p) => s + (p.social_insurance || 0), 0)
  const totalHealth = yearPayrolls.reduce((s, p) => s + (p.health_insurance || 0), 0)

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <select value={selEmp || ''} onChange={e => setSelEmp(e.target.value)}
          className="rounded-btn text-sm outline-none font-bold"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          {employees.map(e => <option key={e.id} value={e.id}>{e.name}</option>)}
        </select>
        <Button green onClick={() => setShowCalc(true)}>+ Vypocitat mzdu</Button>
      </div>

      {emp && (
        <div className="grid grid-cols-4 gap-3 mb-4">
          <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Hruba mzda</div>
            <div className="text-lg font-extrabold" style={{ color: '#1a2e22' }}>{fmt(emp.gross_salary)}</div></Card>
          <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Rocni hrube</div>
            <div className="text-lg font-extrabold" style={{ color: '#2563eb' }}>{fmt(totalGross)}</div></Card>
          <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Rocni ciste</div>
            <div className="text-lg font-extrabold" style={{ color: '#1a8a18' }}>{fmt(totalNet)}</div></Card>
          <Card><div className="text-sm font-extrabold uppercase" style={{ color: '#1a2e22' }}>Odvody celkem</div>
            <div className="text-lg font-extrabold" style={{ color: '#dc2626' }}>{fmt(totalSoc + totalHealth)}</div></Card>
        </div>
      )}

      <Table>
        <thead>
          <TRow header>
            <TH>Obdobi</TH><TH>Hruba</TH><TH>SP zamest.</TH><TH>ZP zamest.</TH>
            <TH>SP zamestnavatel</TH><TH>ZP zamestnavatel</TH>
            <TH>Zaloha dane</TH><TH>Cista</TH><TH>Celk. naklad</TH><TH>Stav</TH>
          </TRow>
        </thead>
        <tbody>
          {payrolls.map(p => (
            <TRow key={p.id}>
              <TD bold>{p.period}</TD>
              <TD>{fmt(p.gross)}</TD>
              <TD>{fmt(p.social_insurance)}</TD>
              <TD>{fmt(p.health_insurance)}</TD>
              <TD>{fmt(p.employer_social)}</TD>
              <TD>{fmt(p.employer_health)}</TD>
              <TD>{fmt(p.income_tax)}</TD>
              <TD bold color="#1a8a18">{fmt(p.net)}</TD>
              <TD bold color="#dc2626">{fmt(p.total_cost)}</TD>
              <TD>
                <Badge label={p.status === 'paid' ? 'Vyplaceno' : p.status === 'calculated' ? 'Vypocteno' : p.status || '—'}
                  color={p.status === 'paid' ? '#1a8a18' : '#b45309'}
                  bg={p.status === 'paid' ? '#dcfce7' : '#fef3c7'} />
              </TD>
            </TRow>
          ))}
          {payrolls.length === 0 && <TRow><TD>Zadne zaznamy</TD></TRow>}
        </tbody>
      </Table>

      {showCalc && emp && <CalcModal emp={emp} onClose={() => setShowCalc(false)}
        onSaved={() => { setShowCalc(false); loadPayrolls() }} />}
    </div>
  )
}

function CalcModal({ emp, onClose, onSaved }) {
  const now = new Date()
  const [period, setPeriod] = useState(`${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`)
  const [saving, setSaving] = useState(false)
  const gross = emp.gross_salary || 0
  const taxDiscount = emp.tax_discount || 2570

  // Vypocet HPP (zjednoduseny dle CZ 2024/2025)
  const socEmp = Math.round(gross * 0.065)
  const healthEmp = Math.round(gross * 0.045)
  const socEmpr = Math.round(gross * 0.248)
  const healthEmpr = Math.round(gross * 0.09)
  const superGross = gross
  const taxBase = Math.ceil(superGross / 100) * 100
  const taxBefore = Math.round(taxBase * 0.15)
  const tax = Math.max(0, taxBefore - taxDiscount)
  const net = gross - socEmp - healthEmp - tax
  const totalCost = gross + socEmpr + healthEmpr

  async function save() {
    setSaving(true)
    try {
      const { error } = await supabase.from('acc_payrolls').insert({
        employee_id: emp.id, period, gross,
        social_insurance: socEmp, health_insurance: healthEmp,
        employer_social: socEmpr, employer_health: healthEmpr,
        income_tax: tax, net, total_cost: totalCost, status: 'calculated',
      })
      if (error) throw error
      onSaved()
    } catch (e) { alert(e.message) } finally { setSaving(false) }
  }

  const fmt = n => (n || 0).toLocaleString('cs-CZ') + ' Kc'

  return (
    <Modal open title={`Vypocet mzdy — ${emp.name}`} onClose={onClose}>
      <div className="mb-3">
        <div className="text-sm font-extrabold uppercase mb-1" style={{ color: '#1a2e22' }}>Obdobi</div>
        <input type="month" value={period} onChange={e => setPeriod(e.target.value)}
          className="rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
      </div>
      <Card style={{ background: '#f1faf7' }}>
        <div className="grid grid-cols-2 gap-2 text-sm">
          <div className="font-bold">Hruba mzda:</div><div className="font-extrabold">{fmt(gross)}</div>
          <div className="font-bold">SP zamestnanec (6.5%):</div><div>{fmt(socEmp)}</div>
          <div className="font-bold">ZP zamestnanec (4.5%):</div><div>{fmt(healthEmp)}</div>
          <div className="font-bold">Zaklad dane:</div><div>{fmt(taxBase)}</div>
          <div className="font-bold">Dan 15%:</div><div>{fmt(taxBefore)}</div>
          <div className="font-bold">Sleva na dani:</div><div>{fmt(taxDiscount)}</div>
          <div className="font-bold">Zaloha dane:</div><div>{fmt(tax)}</div>
          <div className="font-extrabold text-base" style={{ color: '#1a8a18' }}>Cista mzda:</div>
          <div className="font-extrabold text-base" style={{ color: '#1a8a18' }}>{fmt(net)}</div>
          <div className="font-bold border-t pt-2 mt-2" style={{ borderColor: '#d4e8e0' }}>SP zamestnavatel (24.8%):</div><div className="border-t pt-2 mt-2" style={{ borderColor: '#d4e8e0' }}>{fmt(socEmpr)}</div>
          <div className="font-bold">ZP zamestnavatel (9%):</div><div>{fmt(healthEmpr)}</div>
          <div className="font-extrabold" style={{ color: '#dc2626' }}>Celkovy naklad:</div>
          <div className="font-extrabold" style={{ color: '#dc2626' }}>{fmt(totalCost)}</div>
        </div>
      </Card>
      <div className="flex justify-end gap-2 mt-4">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={save} disabled={saving}>{saving ? 'Ukladam...' : 'Ulozit vypocet'}</Button>
      </div>
    </Modal>
  )
}
