import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

// Stav MOTORKY (ne pojistky) — stejný číselník jako v Servisu (ActiveServiceTab).
const MOTO_STATUS_LABEL = { active: 'Aktivní', maintenance: 'V servisu', unavailable: 'Dočasně vyřazena', retired: 'Trvale vyřazena' }
const MOTO_STATUS_COLOR = { active: '#1a8a18', maintenance: '#b45309', unavailable: '#7c3aed', retired: '#6b7280' }
const MOTO_STATUS_BG = { active: '#dcfce7', maintenance: '#fef3c7', unavailable: '#f5f3ff', retired: '#f3f4f6' }

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
              <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide" style={{
                padding: '4px 10px',
                background: MOTO_STATUS_BG[m.status] || '#fef3c7',
                color: MOTO_STATUS_COLOR[m.status] || '#b45309',
              }}>
                {MOTO_STATUS_LABEL[m.status] || m.status || '—'}
              </span>
            </TD>
          </TRow>
        ))}
        {motos.length === 0 && <TRow><TD>Žádné motorky</TD></TRow>}
      </tbody>
    </Table>
  )
}
