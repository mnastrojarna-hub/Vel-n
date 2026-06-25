import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Badge from '../../components/ui/Badge'

// Platby DODAVATELŮM — historie odeslaných i neodeslaných plateb (přijaté faktury).
// Odesláno = invoice.status='paid' (paid_date), Neodesláno = ostatní.
const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'
const supplierOf = (inv) => inv.notes?.split('\n')[0] || '—'

export default function PaymentsTab() {
  const [rows, setRows] = useState([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(null)
  const [f, setF] = useState({ status: 'all', search: '', from: '', to: '', min: '', max: '', sort: 'date_desc' })

  const load = useCallback(async () => {
    setLoading(true)
    const { data } = await supabase.from('invoices').select('*').eq('type', 'received').limit(2000)
    setRows(data || [])
    setLoading(false)
  }, [])
  useEffect(() => { load() }, [load])

  const isSent = (inv) => inv.status === 'paid'
  const payDate = (inv) => inv.paid_date || null

  let list = rows.filter(inv => {
    if (f.status === 'sent' && !isSent(inv)) return false
    if (f.status === 'unsent' && isSent(inv)) return false
    if (f.search) { const s = f.search.toLowerCase(); if (!`${supplierOf(inv)} ${inv.number || ''} ${inv.variable_symbol || ''}`.toLowerCase().includes(s)) return false }
    const d = payDate(inv) || inv.due_date || inv.issue_date
    if (f.from && (!d || d < f.from)) return false
    if (f.to && (!d || d > f.to)) return false
    const amt = inv.total || 0
    if (f.min && amt < Number(f.min)) return false
    if (f.max && amt > Number(f.max)) return false
    return true
  })
  list.sort((a, b) => {
    if (f.sort.startsWith('amount')) return (f.sort.endsWith('asc') ? 1 : -1) * ((a.total || 0) - (b.total || 0))
    const da = payDate(a) || a.due_date || a.issue_date || '', db = payDate(b) || b.due_date || b.issue_date || ''
    return (f.sort.endsWith('asc') ? 1 : -1) * (da < db ? -1 : da > db ? 1 : 0)
  })

  const sentSum = rows.filter(isSent).reduce((s, i) => s + (i.total || 0), 0)
  const unsentSum = rows.filter(i => !isSent(i)).reduce((s, i) => s + (i.total || 0), 0)
  const sentCount = rows.filter(isSent).length
  const unsentCount = rows.length - sentCount

  async function markSent(inv) {
    setBusy(inv.id)
    await supabase.from('invoices').update({ status: 'paid', paid_date: new Date().toISOString().slice(0, 10) }).eq('id', inv.id)
    // snížit závazek
    try {
      const { data: liab } = await supabase.from('acc_liabilities').select('id').eq('invoice_number', inv.number).limit(1)
      if (liab && liab[0]) await supabase.from('acc_liabilities').update({ paid_amount: inv.total || 0, status: 'paid' }).eq('id', liab[0].id)
    } catch { /* noop */ }
    setBusy(null); load()
  }
  async function markUnsent(inv) {
    setBusy(inv.id)
    await supabase.from('invoices').update({ status: 'issued', paid_date: null }).eq('id', inv.id)
    setBusy(null); load()
  }

  const inp = { padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 10, outline: 'none', fontSize: 14, color: '#1a2e22' }

  return (
    <div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
        <Stat label="Odesláno (plateb)" value={sentCount} color="#1a8a18" />
        <Stat label="Odesláno (Kč)" value={fmt(sentSum)} color="#1a8a18" />
        <Stat label="Neodesláno (plateb)" value={unsentCount} color="#b45309" />
        <Stat label="Neodesláno (Kč)" value={fmt(unsentSum)} color="#b45309" />
      </div>

      <div className="flex flex-wrap items-center gap-2 mb-4">
        {[['all', 'Vše'], ['sent', 'Odeslané'], ['unsent', 'Neodeslané']].map(([k, l]) => (
          <button key={k} onClick={() => setF(o => ({ ...o, status: k }))} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '6px 14px', border: 'none', background: f.status === k ? '#1a2e22' : '#f1faf7', color: f.status === k ? '#74FB71' : '#1a2e22' }}>{l}</button>
        ))}
        <input value={f.search} onChange={e => setF(o => ({ ...o, search: e.target.value }))} placeholder="Dodavatel, č. dokladu, VS…" style={{ ...inp, minWidth: 200 }} />
        <label className="text-xs font-bold" style={{ color: '#1a2e22' }}>Od</label>
        <input type="date" value={f.from} onChange={e => setF(o => ({ ...o, from: e.target.value }))} style={inp} />
        <label className="text-xs font-bold" style={{ color: '#1a2e22' }}>Do</label>
        <input type="date" value={f.to} onChange={e => setF(o => ({ ...o, to: e.target.value }))} style={inp} />
        <input type="number" value={f.min} onChange={e => setF(o => ({ ...o, min: e.target.value }))} placeholder="Kč od" style={{ ...inp, width: 90 }} />
        <input type="number" value={f.max} onChange={e => setF(o => ({ ...o, max: e.target.value }))} placeholder="Kč do" style={{ ...inp, width: 90 }} />
        <select value={f.sort} onChange={e => setF(o => ({ ...o, sort: e.target.value }))} style={inp}>
          <option value="date_desc">Datum ↓</option><option value="date_asc">Datum ↑</option>
          <option value="amount_desc">Částka ↓</option><option value="amount_asc">Částka ↑</option>
        </select>
      </div>

      {loading ? <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
        : (
          <Table>
            <thead><TRow header><TH>Dodavatel</TH><TH>Č. dokladu</TH><TH>VS</TH><TH>Částka</TH><TH>Splatnost</TH><TH>Odesláno</TH><TH>Stav</TH><TH>Akce</TH></TRow></thead>
            <tbody>
              {list.map(inv => (
                <TRow key={inv.id}>
                  <TD><span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{supplierOf(inv)}</span></TD>
                  <TD mono bold>{inv.number || '—'}</TD>
                  <TD mono>{inv.variable_symbol || '—'}</TD>
                  <TD bold>{fmt(inv.total)}</TD>
                  <TD>{inv.due_date ? new Date(inv.due_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>{payDate(inv) ? new Date(payDate(inv)).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>{isSent(inv) ? <Badge label="Odesláno" color="#1a8a18" bg="#dcfce7" /> : <Badge label="Neodesláno" color="#b45309" bg="#fef3c7" />}</TD>
                  <TD>
                    {isSent(inv)
                      ? <button onClick={() => markUnsent(inv)} disabled={busy === inv.id} className="text-sm font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none', padding: '4px 6px' }}>Zrušit odeslání</button>
                      : <button onClick={() => markSent(inv)} disabled={busy === inv.id} className="text-sm font-bold cursor-pointer" style={{ color: '#1a8a18', background: 'none', border: 'none', padding: '4px 6px' }}>Označit odeslané</button>}
                  </TD>
                </TRow>
              ))}
              {list.length === 0 && <TRow><TD>Žádné platby</TD></TRow>}
            </tbody>
          </Table>
        )}
    </div>
  )
}

function Stat({ label, value, color }) {
  return (
    <div className="p-3 rounded-card" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
      <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-lg font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}
