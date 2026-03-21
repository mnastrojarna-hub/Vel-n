import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Modal from '../../components/ui/Modal'
import { useDebugMode } from '../../hooks/useDebugMode'

export default function TaxReturnsTab() {
  const debugMode = useDebugMode()
  const [returns, setReturns] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [generating, setGenerating] = useState(false)
  const [detail, setDetail] = useState(null)
  const [companyInfo, setCompanyInfo] = useState(null)

  useEffect(() => { load(); loadCompanyInfo() }, [])

  async function loadCompanyInfo() {
    const { data } = await supabase.from('app_settings').select('value').eq('key', 'company_info').maybeSingle()
    if (data?.value) setCompanyInfo(data.value)
  }

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const { data, error: err } = await debugAction('tax_returns.list', 'TaxReturnsTab', () =>
        supabase.from('acc_tax_returns').select('*').order('year', { ascending: false })
      )
      if (err) throw err
      setReturns(data || [])
    } catch (e) {
      debugError('TaxReturnsTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function generateTaxReturn(year) {
    setGenerating(true)
    setError(null)
    try {
      const existing = returns.find(r => r.year === year)
      if (existing) { setError(`Danove priznani za ${year} jiz existuje`); setGenerating(false); return }

      const yearStart = `${year}-01-01`
      const yearEnd = `${year}-12-31`

      // Gather all financial data
      const [revenueRes, expenseRes, invoicesRes, payrollsRes, depreciationRes, assetsRes] = await Promise.all([
        supabase.from('accounting_entries').select('amount').eq('type', 'revenue').gte('date', yearStart).lte('date', yearEnd),
        supabase.from('accounting_entries').select('amount').eq('type', 'expense').gte('date', yearStart).lte('date', yearEnd),
        supabase.from('invoices').select('total, type').gte('issue_date', yearStart).lte('issue_date', yearEnd),
        supabase.from('acc_payrolls').select('total_employer_cost, gross_salary').eq('year', year),
        supabase.from('acc_depreciation_entries').select('annual_amount').eq('year', year),
        supabase.from('acc_long_term_assets').select('purchase_price'),
      ])

      const totalRevenue = (revenueRes.data || []).reduce((s, e) => s + Math.abs(e.amount || 0), 0)
      const totalExpenses = (expenseRes.data || []).reduce((s, e) => s + Math.abs(e.amount || 0), 0)
      const totalPayroll = (payrollsRes.data || []).reduce((s, p) => s + (p.total_employer_cost || 0), 0)
      const totalDepreciation = (depreciationRes.data || []).reduce((s, d) => s + (d.annual_amount || 0), 0)

      const grossIncome = totalRevenue
      const deductibleExpenses = totalExpenses + totalPayroll + totalDepreciation
      const taxBase = Math.max(grossIncome - deductibleExpenses, 0)
      const roundedTaxBase = Math.floor(taxBase / 100) * 100

      // Progressive tax: 15% up to 1,935,552 CZK, 23% above
      let incomeTax = 0
      if (roundedTaxBase <= 1935552) {
        incomeTax = Math.ceil(roundedTaxBase * 0.15)
      } else {
        incomeTax = Math.ceil(1935552 * 0.15 + (roundedTaxBase - 1935552) * 0.23)
      }

      // Basic taxpayer discount 30,840 CZK/year
      const taxDiscount = 30840
      const taxAfterDiscount = Math.max(incomeTax - taxDiscount, 0)

      // Tax advances already paid
      const { data: advances } = await supabase.from('acc_payrolls').select('tax_advance').eq('year', year)
      const paidAdvances = (advances || []).reduce((s, a) => s + (a.tax_advance || 0), 0)
      const taxToPay = Math.max(taxAfterDiscount - paidAdvances, 0)
      const taxToRefund = Math.max(paidAdvances - taxAfterDiscount, 0)

      const { error: insertErr } = await supabase.from('acc_tax_returns').insert({
        year,
        total_revenue: totalRevenue,
        total_expenses: totalExpenses,
        payroll_costs: totalPayroll,
        depreciation: totalDepreciation,
        gross_income: grossIncome,
        deductible_expenses: deductibleExpenses,
        tax_base: taxBase,
        rounded_tax_base: roundedTaxBase,
        income_tax_15: Math.min(roundedTaxBase, 1935552) * 0.15,
        income_tax_23: Math.max(roundedTaxBase - 1935552, 0) * 0.23,
        total_income_tax: incomeTax,
        tax_discount: taxDiscount,
        tax_after_discount: taxAfterDiscount,
        paid_advances: paidAdvances,
        tax_to_pay: taxToPay,
        tax_to_refund: taxToRefund,
        status: 'prepared',
        details: {
          revenue_entries: revenueRes.data?.length || 0,
          expense_entries: expenseRes.data?.length || 0,
          invoices_count: invoicesRes.data?.length || 0,
          payroll_months: payrollsRes.data?.length || 0,
          generated_at: new Date().toISOString(),
        },
      })
      if (insertErr) throw insertErr

      // Create tax_records entry
      await supabase.from('tax_records').upsert({
        type: 'income_tax',
        period_from: yearStart,
        period_to: yearEnd,
        tax_base: taxBase,
        vat_amount: 0,
        total: taxAfterDiscount,
        status: 'prepared',
      }, { onConflict: 'type,period_from' }).catch(() => {})

      await load()
    } catch (e) {
      debugError('TaxReturnsTab', 'generate', e)
      setError('Chyba generovani: ' + e.message)
    } finally {
      setGenerating(false)
    }
  }

  async function markSubmitted(id) {
    await supabase.from('acc_tax_returns').update({ status: 'submitted', submitted_at: new Date().toISOString() }).eq('id', id)
    await load()
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kc'
  const now = new Date()
  const prevYear = now.getFullYear() - 1

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <Button green onClick={() => generateTaxReturn(prevYear)} disabled={generating}>
          {generating ? 'Generuji...' : `Generovat DP za ${prevYear}`}
        </Button>
        <Button onClick={() => generateTaxReturn(now.getFullYear())} disabled={generating}>
          DP za {now.getFullYear()} (prubezne)
        </Button>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : returns.length === 0 ? (
        <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>Zadna danova priznani</p></Card>
      ) : (
        returns.map(r => (
          <Card key={r.id} className="mb-4">
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
                Danove priznani {r.year}
              </h3>
              <div className="flex items-center gap-2">
                <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                  style={{ padding: '4px 10px', background: r.status === 'submitted' ? '#dcfce7' : '#fef3c7', color: r.status === 'submitted' ? '#1a8a18' : '#b45309' }}>
                  {r.status === 'submitted' ? 'Podano' : 'Pripraveno'}
                </span>
                {r.status !== 'submitted' && (
                  <button onClick={() => markSubmitted(r.id)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#b45309' }}>Oznacit podano</button>
                )}
              </div>
            </div>

            <div className="grid grid-cols-3 gap-3 mb-3">
              <MiniStat label="Prijmy celkem" value={fmt(r.total_revenue)} color="#1a8a18" />
              <MiniStat label="Vydaje celkem" value={fmt(r.deductible_expenses)} color="#dc2626" />
              <MiniStat label="Zaklad dane" value={fmt(r.rounded_tax_base)} color="#1a2e22" />
            </div>
            <div className="grid grid-cols-4 gap-3 mb-3">
              <MiniStat label="Dan 15%" value={fmt(r.income_tax_15)} color="#6b7280" />
              <MiniStat label="Dan 23%" value={fmt(r.income_tax_23)} color="#6b7280" />
              <MiniStat label="Sleva na poplatnika" value={fmt(r.tax_discount)} color="#2563eb" />
              <MiniStat label="Dan po sleve" value={fmt(r.tax_after_discount)} color="#b45309" />
            </div>
            <div className="grid grid-cols-3 gap-3">
              <MiniStat label="Zaplacene zalohy" value={fmt(r.paid_advances)} color="#6b7280" />
              <MiniStat label="Doplatek" value={fmt(r.tax_to_pay)} color="#dc2626" />
              <MiniStat label="Preplatek" value={fmt(r.tax_to_refund)} color="#1a8a18" />
            </div>

            <div className="mt-3 text-sm" style={{ color: '#6b7280' }}>
              Odpisy: {fmt(r.depreciation)} | Mzdy: {fmt(r.payroll_costs)} | Vydaje: {fmt(r.total_expenses)}
            </div>
          </Card>
        ))
      )}
    </div>
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
