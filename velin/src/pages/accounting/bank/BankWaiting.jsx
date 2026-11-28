import { useState, useEffect, useRef, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { Table, TRow, TH, TD } from '../../../components/ui/Table'
import Badge from '../../../components/ui/Badge'
import Button from '../../../components/ui/Button'
import { TAB_ROW } from '../FinanceAStack'
import { loadWaiting } from './bankApi'
import { fmtMoney, fmtDateTime, fmtUntil } from './bankFormat'

const KIND = {
  booking: 'Rezervace (QR)', gear: 'Výpůjčka výbavy (QR)', surcharge: 'Doplatek rezervace',
  booking_change: 'Úprava rezervace (web)', voucher: 'Dárkový poukaz', shop_order: 'Objednávka e-shopu',
}
const STATE = {
  waiting: { label: 'Čeká na platbu', color: '#b45309', bg: '#fef3c7' },
  expired: { label: 'Po lhůtě', color: '#dc2626', bg: '#fee2e2' },
  cancelled: { label: 'Zrušeno', color: '#1a2e22', bg: '#f3f4f6' },
}

// Čekající platby — vše, na co automat čeká (akce fio-sync „waiting“): rezervace a výpůjčky s QR platbou,
// doplatky rezervací, doplatky úprav z webu, poukazy / objednávky převodem. Jen přehled, nic se tu nemění.
export default function BankWaiting({ tick, now }) {
  const [items, setItems] = useState([])
  const [state, setState] = useState('loading') // loading | ready | missing | error
  const seq = useRef(0)

  const load = useCallback(async () => {
    const my = ++seq.current
    const r = await loadWaiting()
    if (my !== seq.current) return
    if (r.ok) { setItems(Array.isArray(r.data.items) ? r.data.items : []); setState('ready') }
    else setState(s => (s === 'ready' ? s : r.missing ? 'missing' : 'error'))
  }, [])

  useEffect(() => { load() }, [load])
  useEffect(() => { if (tick) load() }, [tick]) // eslint-disable-line react-hooks/exhaustive-deps

  if (state === 'loading') return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (state === 'missing') return <Notice>Seznam čekajících plateb bude dostupný po nasazení serverové části.</Notice>
  if (state === 'error') return <Notice>Čekající platby se nepodařilo načíst. <button onClick={() => { setState('loading'); load() }} className="font-bold underline cursor-pointer" style={{ background: 'none', border: 'none', color: 'inherit' }}>Zkusit znovu</button></Notice>

  const waiting = items.filter(i => i.state === 'waiting' || !i.state)
  const sum = waiting.reduce((s, i) => s + (Number(i.amount) || 0), 0)

  return (
    <div data-bank="waiting">
      <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
        <p style={{ fontSize: 13, color: '#1a2e22' }}>
          Čeká se na <b>{waiting.length}</b> {waiting.length === 1 ? 'platbu' : waiting.length >= 2 && waiting.length <= 4 ? 'platby' : 'plateb'} převodem, celkem <b>{fmtMoney(sum)}</b>.
          Jakmile peníze dorazí se správným variabilním symbolem, potvrdí se samy.
        </p>
        <Button small onClick={load} className="max-lg:min-h-[36px]">Obnovit</Button>
      </div>
      <Table stack="tablet">
        <thead><TRow header><TH>Co se platí</TH><TH>Zákazník</TH><TH>VS</TH><TH>Částka</TH><TH>Vytvořeno</TH><TH>Lhůta</TH><TH>Stav</TH><TH>Záznam</TH></TRow></thead>
        <tbody>
          {items.map(i => {
            const st = STATE[i.state] || STATE.waiting
            const to = i.booking_id ? `/rezervace/${i.booking_id}` : i.order_id ? '/e-shop' : null
            return (
              <tr key={`${i.target_type}:${i.target_id}`} className={TAB_ROW} style={{ borderBottom: '1px solid #d4e8e0' }}>
                <TD>
                  <div className="font-bold" style={{ color: '#1a2e22' }}>{i.label || KIND[i.kind] || '—'}</div>
                  <div style={{ fontSize: 12, color: '#4a6357' }}>{KIND[i.kind] || ''}</div>
                </TD>
                <TD>
                  <div>{i.customer_name || '—'}</div>
                  {i.customer_email && <div style={{ fontSize: 12, color: '#4a6357', overflowWrap: 'anywhere' }}>{i.customer_email}</div>}
                </TD>
                <TD mono>{i.vs || '—'}</TD>
                <TD bold style={{ whiteSpace: 'nowrap' }}>{fmtMoney(i.amount)}</TD>
                <TD>{fmtDateTime(i.created_at)}</TD>
                <TD style={{ color: i.expires_at && Date.parse(i.expires_at) < now ? '#dc2626' : '#0f1a14' }}>{i.expires_at ? fmtUntil(i.expires_at, now) : 'bez lhůty'}</TD>
                <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
                <TD>{to ? <Link to={to} style={{ color: '#2563eb', fontWeight: 800 }}>Otevřít ↗</Link> : '—'}</TD>
              </tr>
            )
          })}
          {items.length === 0 && <tr style={{ borderBottom: '1px solid #d4e8e0' }}><TD label="" colSpan={8}>Právě se nečeká na žádnou platbu převodem.</TD></tr>}
        </tbody>
      </Table>
    </div>
  )
}

function Notice({ children }) {
  return <div className="p-4 rounded-card" style={{ background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22', fontSize: 13 }}>{children}</div>
}
