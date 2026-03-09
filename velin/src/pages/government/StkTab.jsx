import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

export default function StkTab() {
  const [motos, setMotos] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      debugLog('StkTab', 'load')
      const { data, error } = await debugAction('motorcycles.stk', 'StkTab', () =>
        supabase
          .from('motorcycles')
          .select('id, model, spz, stk_valid_until')
          .order('stk_valid_until')
      )
      if (error) throw error
      setMotos(data || [])
    } catch (e) {
      debugError('StkTab', 'load', e)
    }
    setLoading(false)
  }

  function daysUntil(dateStr) {
    if (!dateStr) return null
    const diff = Math.ceil((new Date(dateStr) - new Date()) / (1000 * 60 * 60 * 24))
    return diff
  }

  function daysColor(days) {
    if (days === null) return '#8aab99'
    if (days < 0) return '#dc2626'
    if (days < 30) return '#dc2626'
    if (days < 90) return '#b45309'
    return '#1a8a18'
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  return (
    <Table>
      <thead>
        <TRow header>
          <TH>Motorka</TH><TH>SPZ</TH><TH>STK do</TH><TH>Dní do STK</TH>
        </TRow>
      </thead>
      <tbody>
        {motos.map(m => {
          const stkDays = daysUntil(m.stk_valid_until)
          return (
            <TRow key={m.id}>
              <TD bold>{m.model}</TD>
              <TD mono>{m.spz}</TD>
              <TD>{m.stk_valid_until ? new Date(m.stk_valid_until).toLocaleDateString('cs-CZ') : '—'}</TD>
              <TD>
                <span style={{ color: daysColor(stkDays), fontWeight: 700 }}>
                  {stkDays !== null ? (stkDays < 0 ? `${Math.abs(stkDays)} po` : stkDays) : '—'}
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
