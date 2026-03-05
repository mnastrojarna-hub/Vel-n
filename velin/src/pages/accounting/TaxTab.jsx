import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'

export default function TaxTab() {
  const [records, setRecords] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [generating, setGenerating] = useState(false)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const { data, error: err } = await supabase
      .from('tax_records')
      .select('*')
      .order('period', { ascending: false })
    if (err) setError(err.message)
    else setRecords(data || [])
    setLoading(false)
  }

  async function generateTax(period) {
    setGenerating(true)
    setError(null)
    try {
      const { data, error } = await supabase.functions.invoke('generate-tax', {
        body: { period, type: 'vat_summary' },
      })
      if (error) throw error
      if (data?.url) window.open(data.url, '_blank')
      await load()
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'tax_generated', details: { period },
      })
    } catch (e) {
      setError('Generování selhalo: ' + e.message)
    } finally {
      setGenerating(false)
    }
  }

  async function handleExport(format) {
    try {
      const { data, error } = await supabase.functions.invoke('export-data', {
        body: { type: 'tax_records', format },
      })
      if (error) throw error
      if (data?.url) window.open(data.url, '_blank')
    } catch (e) {
      setError('Export selhal: ' + e.message)
    }
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'
  const now = new Date()
  const currentQ = `${now.getFullYear()}-Q${Math.ceil((now.getMonth() + 1) / 3)}`

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <Button green onClick={() => generateTax(currentQ)} disabled={generating}>
          {generating ? 'Generuji…' : `Generovat DPH ${currentQ}`}
        </Button>
        <div className="ml-auto flex gap-2">
          <Button onClick={() => handleExport('csv')}>CSV</Button>
          <Button onClick={() => handleExport('xlsx')}>XLSX</Button>
        </div>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : records.length === 0 ? (
        <Card><p style={{ color: '#8aab99', fontSize: 13 }}>Žádné daňové záznamy</p></Card>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Období</TH><TH>Typ</TH><TH>Základ daně</TH>
              <TH>DPH</TH><TH>Celkem</TH><TH>Stav</TH>
            </TRow>
          </thead>
          <tbody>
            {records.map(r => (
              <TRow key={r.id}>
                <TD bold>{r.period || '—'}</TD>
                <TD>{r.type || '—'}</TD>
                <TD>{fmt(r.tax_base)}</TD>
                <TD bold>{fmt(r.vat_amount)}</TD>
                <TD bold>{fmt(r.total)}</TD>
                <TD>
                  <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                    style={{
                      padding: '4px 10px',
                      background: r.status === 'submitted' ? '#dcfce7' : '#fef3c7',
                      color: r.status === 'submitted' ? '#1a8a18' : '#b45309',
                    }}>
                    {r.status === 'submitted' ? 'Odesláno' : 'Připraveno'}
                  </span>
                </TD>
              </TRow>
            ))}
          </tbody>
        </Table>
      )}
    </div>
  )
}
