import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Modal from '../../components/ui/Modal'
import { useDebugMode } from '../../hooks/useDebugMode'

const QUARTERS = [1, 2, 3, 4]

export default function VATReturnsTab() {
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
      const { data, error: err } = await debugAction('vat_returns.list', 'VATReturnsTab', () =>
        supabase.from('acc_vat_returns').select('*')
          .order('year', { ascending: false })
          .order('quarter', { ascending: false })
      )
      if (err) throw err
      setReturns(data || [])
    } catch (e) {
      debugError('VATReturnsTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function generateVATReturn(year, quarter) {
    setGenerating(true)
    setError(null)
    try {
      const existing = returns.find(r => r.year === year && r.quarter === quarter)
      if (existing) { setError(`Priznani za Q${quarter}/${year} jiz existuje`); setGenerating(false); return }

      const qStart = `${year}-${String((quarter - 1) * 3 + 1).padStart(2, '0')}-01`
      const qEndMonth = quarter * 3
      const qEnd = `${year}-${String(qEndMonth).padStart(2, '0')}-${new Date(year, qEndMonth, 0).getDate()}`

      // Gather all invoices for the period
      const [issuedRes, receivedRes] = await Promise.all([
        supabase.from('invoices').select('total, tax_amount, type')
          .gte('issue_date', qStart).lte('issue_date', qEnd)
          .neq('type', 'received'),
        supabase.from('invoices').select('total, tax_amount')
          .gte('issue_date', qStart).lte('issue_date', qEnd)
          .eq('type', 'received'),
      ])

      const issuedInvoices = issuedRes.data || []
      const receivedInvoices = receivedRes.data || []

      const outputVat = issuedInvoices.reduce((s, i) => s + (i.tax_amount || 0), 0)
      const inputVat = receivedInvoices.reduce((s, i) => s + (i.tax_amount || 0), 0)
      const taxableOutputs = issuedInvoices.reduce((s, i) => s + (i.total || 0), 0)
      const taxableInputs = receivedInvoices.reduce((s, i) => s + (i.total || 0), 0)
      const vatDifference = outputVat - inputVat

      const { error: insertErr } = await supabase.from('acc_vat_returns').insert({
        year, quarter,
        period_from: qStart,
        period_to: qEnd,
        taxable_outputs: taxableOutputs,
        output_vat: outputVat,
        taxable_inputs: taxableInputs,
        input_vat: inputVat,
        vat_difference: vatDifference,
        vat_to_pay: Math.max(vatDifference, 0),
        vat_to_refund: Math.max(-vatDifference, 0),
        total_invoices_issued: issuedInvoices.length,
        total_invoices_received: receivedInvoices.length,
        status: 'prepared',
        details: {
          issued_breakdown: issuedInvoices,
          received_breakdown: receivedInvoices,
          generated_at: new Date().toISOString(),
        },
      })
      if (insertErr) throw insertErr

      // Also create tax_records entry for compatibility
      await supabase.from('tax_records').upsert({
        type: 'vat_return',
        period_from: qStart,
        period_to: qEnd,
        tax_base: taxableOutputs - taxableInputs,
        vat_amount: vatDifference,
        total: vatDifference,
        status: 'prepared',
      }, { onConflict: 'type,period_from' }).catch(() => {})

      await load()
    } catch (e) {
      debugError('VATReturnsTab', 'generate', e)
      setError('Chyba generovani: ' + e.message)
    } finally {
      setGenerating(false)
    }
  }

  async function markSubmitted(id) {
    await supabase.from('acc_vat_returns').update({ status: 'submitted', submitted_at: new Date().toISOString() }).eq('id', id)
    await load()
  }

  function generateXml(ret) {
    const ci = companyInfo || {}
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<Pisemnost nazevSW="MotoGo24 Velin" verzeSW="1.0">
  <DPHDP3 verzePis="02.01">
    <VetaD dic="${ci.dic || ''}" rok="${ret.year}" ctvrt="${ret.quarter}" />
    <VetaA obrat23="${ret.taxable_outputs}" dan23="${ret.output_vat}" />
    <VetaB pln23="${ret.taxable_inputs}" odp_tuz23="${ret.input_vat}" />
    <VetaC dan_zocelk="${ret.vat_to_pay}" odp_zocelk="${ret.vat_to_refund}" />
  </DPHDP3>
</Pisemnost>`
    const blob = new Blob([xml], { type: 'application/xml' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `DPH_Q${ret.quarter}_${ret.year}.xml`
    a.click()
    URL.revokeObjectURL(url)
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kc'
  const now = new Date()
  const currentQ = Math.ceil((now.getMonth() + 1) / 3)

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <Button green onClick={() => generateVATReturn(now.getFullYear(), currentQ)} disabled={generating}>
          {generating ? 'Generuji...' : `Generovat DPH Q${currentQ}/${now.getFullYear()}`}
        </Button>
        <span className="text-sm" style={{ color: '#6b7280' }}>
          {companyInfo?.vat_payer === false ? '(Firma neni platce DPH — podklady pro kontrolu)' : ''}
        </span>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Summary for current year */}
      {returns.length > 0 && (
        <div className="grid grid-cols-4 gap-3 mb-4">
          <MiniStat label="Vydana DPH celkem" value={fmt(returns.filter(r => r.year === now.getFullYear()).reduce((s, r) => s + (r.output_vat || 0), 0))} color="#dc2626" />
          <MiniStat label="Prijata DPH celkem" value={fmt(returns.filter(r => r.year === now.getFullYear()).reduce((s, r) => s + (r.input_vat || 0), 0))} color="#1a8a18" />
          <MiniStat label="K uhrade" value={fmt(returns.filter(r => r.year === now.getFullYear()).reduce((s, r) => s + (r.vat_to_pay || 0), 0))} color="#b45309" />
          <MiniStat label="K vraceni" value={fmt(returns.filter(r => r.year === now.getFullYear()).reduce((s, r) => s + (r.vat_to_refund || 0), 0))} color="#2563eb" />
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : returns.length === 0 ? (
        <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>Zadna DPH priznani</p></Card>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Obdobi</TH><TH>Zdanit. vystupy</TH><TH>DPH vystup</TH><TH>Zdanit. vstupy</TH>
              <TH>DPH vstup</TH><TH>K uhrade/vraceni</TH><TH>Stav</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {returns.map(r => (
              <TRow key={r.id}>
                <TD bold>Q{r.quarter}/{r.year}</TD>
                <TD>{fmt(r.taxable_outputs)}</TD>
                <TD color="#dc2626">{fmt(r.output_vat)}</TD>
                <TD>{fmt(r.taxable_inputs)}</TD>
                <TD color="#1a8a18">{fmt(r.input_vat)}</TD>
                <TD bold color={r.vat_difference >= 0 ? '#dc2626' : '#1a8a18'}>
                  {r.vat_difference >= 0 ? `Uhradit ${fmt(r.vat_to_pay)}` : `Vraceni ${fmt(r.vat_to_refund)}`}
                </TD>
                <TD>
                  <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                    style={{ padding: '4px 10px', background: r.status === 'submitted' ? '#dcfce7' : '#fef3c7', color: r.status === 'submitted' ? '#1a8a18' : '#b45309' }}>
                    {r.status === 'submitted' ? 'Podano' : 'Pripraveno'}
                  </span>
                </TD>
                <TD>
                  <div className="flex gap-1">
                    <button onClick={() => setDetail(r)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#2563eb' }}>Detail</button>
                    <button onClick={() => generateXml(r)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#059669' }}>XML</button>
                    {r.status !== 'submitted' && (
                      <button onClick={() => markSubmitted(r.id)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#b45309' }}>Oznacit podano</button>
                    )}
                  </div>
                </TD>
              </TRow>
            ))}
          </tbody>
        </Table>
      )}

      {detail && (
        <Modal open title={`DPH Priznani Q${detail.quarter}/${detail.year}`} onClose={() => setDetail(null)}>
          <div className="grid grid-cols-2 gap-4">
            <DetailRow label="Obdobi" value={`${detail.period_from} — ${detail.period_to}`} />
            <DetailRow label="Stav" value={detail.status === 'submitted' ? 'Podano' : 'Pripraveno'} />
            <DetailRow label="Zdanitelne vystupy" value={fmt(detail.taxable_outputs)} />
            <DetailRow label="DPH na vystupu" value={fmt(detail.output_vat)} />
            <DetailRow label="Zdanitelne vstupy" value={fmt(detail.taxable_inputs)} />
            <DetailRow label="DPH na vstupu" value={fmt(detail.input_vat)} />
            <DetailRow label="Rozdil DPH" value={fmt(detail.vat_difference)} />
            <DetailRow label="K uhrade" value={fmt(detail.vat_to_pay)} />
            <DetailRow label="K vraceni" value={fmt(detail.vat_to_refund)} />
            <DetailRow label="Pocet faktur vydanych" value={detail.total_invoices_issued} />
            <DetailRow label="Pocet faktur prijatych" value={detail.total_invoices_received} />
          </div>
          <div className="flex justify-end gap-3 mt-5">
            <Button onClick={() => generateXml(detail)}>Stahnout XML</Button>
            <Button onClick={() => setDetail(null)}>Zavrit</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}

function DetailRow({ label, value }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-semibold" style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
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
