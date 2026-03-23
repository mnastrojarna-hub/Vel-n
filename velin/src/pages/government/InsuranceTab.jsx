import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

export default function InsuranceTab() {
  const [motos, setMotos] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      debugLog('InsuranceTab', 'load')
      const { data, error } = await debugAction('motorcycles.insurance', 'InsuranceTab', () =>
        supabase
          .from('motorcycles')
          .select('id, model, spz, insurance_price, status')
          .order('model')
      )
      if (error) throw error
      setMotos(data || [])
    } catch (e) {
      debugError('InsuranceTab', 'load', e)
    }
    setLoading(false)
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <Table>
      <thead>
        <TRow header>
          <TH>Motorka</TH><TH>SPZ</TH><TH>Cena pojištění</TH><TH>Stav</TH>
        </TRow>
      </thead>
      <tbody>
        {motos.map(m => (
          <TRow key={m.id}>
            <TD bold>{m.model}</TD>
            <TD mono>{m.spz || '—'}</TD>
            <TD>{m.insurance_price ? `${m.insurance_price.toLocaleString('cs-CZ')} Kč` : '—'}</TD>
            <TD>
              <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase" style={{
                padding: '4px 10px',
                background: m.status === 'active' ? '#dcfce7' : '#fef3c7',
                color: m.status === 'active' ? '#1a8a18' : '#b45309',
              }}>
                {m.status || '—'}
              </span>
            </TD>
          </TRow>
        ))}
        {motos.length === 0 && <TRow><TD>Žádné motorky</TD></TRow>}
      </tbody>
    </Table>
  )
}
