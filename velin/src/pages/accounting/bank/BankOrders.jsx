import { useState, useEffect, useRef, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { Table, TRow, TH, TD } from '../../../components/ui/Table'
import Badge from '../../../components/ui/Badge'
import { TAB_ROW } from '../FinanceAStack'
import { loadPaymentOrders } from './bankApi'
import { fmtMoney, fmtDateTime, shortId } from './bankFormat'

const STATE = {
  pending: { label: 'Čeká na odeslání', color: '#b45309', bg: '#fef3c7' },
  submitted: { label: 'Odesláno bance', color: '#1a8a18', bg: '#dcfce7' },
  failed: { label: 'Selhalo', color: '#dc2626', bg: '#fee2e2' },
}

// Platební příkazy (vratky) — příkazy k úhradě podané bance automaticky při vratce (fio_payment_orders).
// Jen ke čtení: příkazy zakládá vratka v detailu rezervace, tady se nic neodesílá ani nemění.
export default function BankOrders({ tick }) {
  const [rows, setRows] = useState([])
  const [state, setState] = useState('loading') // loading | ready | missing | error
  const seq = useRef(0)

  const load = useCallback(async () => {
    const my = ++seq.current
    const r = await loadPaymentOrders()
    if (my !== seq.current) return
    if (r.ok) { setRows(r.rows); setState('ready') }
    else setState(s => (s === 'ready' ? s : r.missing ? 'missing' : 'error'))
  }, [])

  useEffect(() => { load() }, [load])
  useEffect(() => { if (tick) load() }, [tick]) // eslint-disable-line react-hooks/exhaustive-deps

  if (state === 'loading') return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (state !== 'ready') {
    return (
      <div className="p-4 rounded-card" style={{ background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22', fontSize: 13 }}>
        {state === 'missing' ? 'Platební příkazy budou dostupné po nasazení databázové části.' : 'Platební příkazy se nepodařilo načíst — zkuste to za chvíli znovu.'}
      </div>
    )
  }

  return (
    <div data-bank="orders">
      <p className="mb-4" style={{ fontSize: 13, color: '#1a2e22' }}>
        Vratky odeslané bance platebním příkazem. Příkaz vzniká sám při vratce v detailu rezervace — tady je jen přehled.
        Má-li účet zapnuté dodatečné potvrzování dávek, potvrďte dávku v internetovém bankovnictví.
      </p>
      <Table stack="tablet">
        <thead><TRow header><TH>Vytvořeno</TH><TH>Částka</TH><TH>Na účet</TH><TH>VS</TH><TH>Stav</TH><TH>Dávka v bance</TH><TH>Dobropis</TH><TH>Rezervace</TH></TRow></thead>
        <tbody>
          {rows.map(o => {
            const st = STATE[o.status] || { label: o.status || '—', color: '#1a2e22', bg: '#f3f4f6' }
            return (
              <tr key={o.id} className={TAB_ROW} style={{ borderBottom: '1px solid #d4e8e0' }}>
                <TD>{fmtDateTime(o.created_at)}</TD>
                <TD bold style={{ whiteSpace: 'nowrap' }}>{fmtMoney(o.amount)}</TD>
                <TD mono>{o.account_to ? `${o.account_to}${o.bank_code ? '/' + o.bank_code : ''}` : '—'}</TD>
                <TD mono>{o.vs || '—'}</TD>
                <TD>
                  <Badge label={st.label} color={st.color} bg={st.bg} />
                  {o.submitted_at && <div className="mt-1" style={{ fontSize: 12, color: '#4a6357' }}>odesláno {fmtDateTime(o.submitted_at)}</div>}
                  {o.status === 'failed' && <div className="mt-1 max-lg:ml-auto" style={{ fontSize: 12, color: '#dc2626', maxWidth: 260, overflowWrap: 'anywhere' }}>{o.error ? o.error + ' — ' : ''}vratku pošlete ručně (viz detail rezervace).</div>}
                </TD>
                <TD mono>{o.fio_instruction_id || '—'}</TD>
                <TD mono>{o.credit_note_number || '—'}</TD>
                <TD>{o.booking_id ? <Link to={`/rezervace/${o.booking_id}`} style={{ color: '#2563eb', fontWeight: 800 }} className="font-mono">#{shortId(o.booking_id)}</Link> : '—'}</TD>
              </tr>
            )
          })}
          {rows.length === 0 && <tr style={{ borderBottom: '1px solid #d4e8e0' }}><TD label="" colSpan={8}>Zatím nebyl odeslán žádný platební příkaz.</TD></tr>}
        </tbody>
      </Table>
    </div>
  )
}
