import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

export default function InsuranceTab() {
  const [motos, setMotos] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const { data } = await supabase
      .from('motorcycles')
      .select('id, model, spz, insurance_company, insurance_valid_until, insurance_policy_number')
      .order('insurance_valid_until')
    setMotos(data || [])
    setLoading(false)
  }

  function daysUntil(dateStr) {
    if (!dateStr) return null
    return Math.ceil((new Date(dateStr) - new Date()) / (1000 * 60 * 60 * 24))
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <Table>
      <thead>
        <TRow header>
          <TH>Motorka</TH><TH>SPZ</TH><TH>Pojišťovna</TH>
          <TH>Číslo smlouvy</TH><TH>Platnost do</TH><TH>Stav</TH>
        </TRow>
      </thead>
      <tbody>
        {motos.map(m => {
          const days = daysUntil(m.insurance_valid_until)
          const expired = days !== null && days < 0
          const warning = days !== null && days >= 0 && days < 30
          return (
            <TRow key={m.id}>
              <TD bold>{m.model}</TD>
              <TD mono>{m.spz}</TD>
              <TD>{m.insurance_company || '—'}</TD>
              <TD mono>{m.insurance_policy_number || '—'}</TD>
              <TD>{m.insurance_valid_until ? new Date(m.insurance_valid_until).toLocaleDateString('cs-CZ') : '—'}</TD>
              <TD>
                <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase" style={{
                  padding: '4px 10px',
                  background: expired ? '#fee2e2' : warning ? '#fef3c7' : '#dcfce7',
                  color: expired ? '#dc2626' : warning ? '#b45309' : '#1a8a18',
                }}>
                  {expired ? 'Vypršelo' : warning ? 'Brzy vyprší' : days !== null ? 'Platné' : 'N/A'}
                </span>
              </TD>
            </TRow>
          )
        })}
        {motos.length === 0 && <TRow><TD>Žádné motorky</TD></TRow>}
      </tbody>
    </Table>
  )
}
