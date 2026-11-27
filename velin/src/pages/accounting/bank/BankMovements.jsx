import { useState, useEffect, useRef, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { Table, TRow, TH, TD } from '../../../components/ui/Table'
import Badge from '../../../components/ui/Badge'
import SearchInput from '../../../components/ui/SearchInput'
import Pagination from '../../../components/ui/Pagination'
import { TAB_ROW } from '../FinanceAStack'
import { loadMovements, loadOrderNumbers } from './bankApi'
import { statusOf, reasonText, needsStaff, followupOpen, FOLLOWUP, fmtMoney, fmtDate, shortId } from './bankFormat'
import BankMovementDetail from './BankMovementDetail'

const PER_PAGE = 25
const FILTERS = [['todo', 'K vyřešení'], ['matched', 'Spárované'], ['ignored', 'Ignorované'], ['outgoing', 'Odchozí'], ['all', 'Vše']]
const EMPTY = {
  todo: 'Nic k vyřešení — všechny příchozí platby jsou spárované.',
  matched: 'Žádné spárované pohyby.', ignored: 'Žádné ignorované pohyby.', outgoing: 'Žádné odchozí pohyby.', all: 'Žádné pohyby.',
}

/** Odkaz na to, k čemu je pohyb přiřazený (rezervace / objednávka). */
export function TargetLink({ tx, orderNumbers = {} }) {
  if (tx.booking_id) {
    const what = tx.target_type === 'surcharge' || tx.status === 'confirmed_surcharge' ? 'Doplatek ' : tx.target_type === 'request' || tx.status === 'confirmed_change' ? 'Úprava ' : ''
    return <Link to={`/rezervace/${tx.booking_id}`} onClick={e => e.stopPropagation()} style={{ color: '#2563eb', fontWeight: 800 }}>{what}<span className="font-mono">#{shortId(tx.booking_id)}</span></Link>
  }
  if (tx.order_id) {
    return <Link to="/e-shop" onClick={e => e.stopPropagation()} title="Otevřít objednávky e-shopu" style={{ color: '#2563eb', fontWeight: 800 }}>Objednávka <span className="font-mono">{orderNumbers[tx.order_id] || ''}</span></Link>
  }
  return <span>—</span>
}

// Seznam bankovních pohybů (fio_transactions) — filtry, hledání, období, stránkování, detail.
export default function BankMovements({ tick, todoCount, notify, onChanged }) {
  const [f, setF] = useState({ filter: 'todo', search: '', from: '', to: '' })
  const [page, setPage] = useState(1)
  const [rows, setRows] = useState([])
  const [total, setTotal] = useState(0)
  const [orderNumbers, setOrderNumbers] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [detailId, setDetailId] = useState(null)
  const seq = useRef(0)

  const load = useCallback(async (quiet) => {
    const my = ++seq.current
    if (!quiet) setLoading(true)
    const r = await loadMovements({ ...f, page, perPage: PER_PAGE })
    if (my !== seq.current) return
    if (r.ok) {
      setRows(r.rows); setTotal(r.total); setError(null)
      loadOrderNumbers(r.rows.map(x => x.order_id)).then(m => { if (my === seq.current) setOrderNumbers(m) })
    } else if (!quiet) {
      setRows([]); setTotal(0)
      setError(r.missing ? 'Pohyby budou dostupné po nasazení databázové části.' : 'Pohyby se nepodařilo načíst — zkuste to za chvíli znovu.')
    }
    setLoading(false)
  }, [f, page])

  useEffect(() => { load(false) }, [load])
  // živé obnovení (realtime / 60 s) — potichu, bez točícího kolečka a bez přepsání seznamu chybou
  useEffect(() => { if (tick) load(true) }, [tick]) // eslint-disable-line react-hooks/exhaustive-deps

  const set = (patch) => { setPage(1); setF(o => ({ ...o, ...patch })) }
  const changed = () => { load(true); onChanged() }
  const totalPages = Math.ceil(total / PER_PAGE)
  const inp = { padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 10, outline: 'none', fontSize: 14, color: '#1a2e22' }

  return (
    <div>
      <div className="flex flex-wrap items-center gap-2 mb-4">
        {FILTERS.map(([k, l]) => (
          <button key={k} onClick={() => set({ filter: k })} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer max-lg:min-h-[36px]"
            style={{ padding: '6px 14px', border: 'none', background: f.filter === k ? '#74FB71' : '#f1faf7', color: '#1a2e22', boxShadow: f.filter === k ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {l}
            {k === 'todo' && todoCount > 0 && (
              <span className="ml-1.5 inline-flex items-center justify-center rounded-full font-extrabold"
                style={{ minWidth: 18, height: 18, padding: '0 5px', fontSize: 10, background: '#dc2626', color: '#fff' }}>{todoCount}</span>
            )}
          </button>
        ))}
      </div>
      <div className="flex flex-wrap items-center gap-2 mb-4">
        <div className="max-sm:w-full">
          <SearchInput value={f.search} onChange={v => set({ search: v })} placeholder="VS, plátce, částka, zpráva…" />
        </div>
        <span className="flex items-center gap-2 max-sm:w-full lg:contents">
          <label className="text-xs font-bold max-sm:w-6" style={{ color: '#1a2e22' }} htmlFor="bank-from">Od</label>
          <input id="bank-from" type="date" value={f.from} onChange={e => set({ from: e.target.value })} className="max-sm:flex-1 max-sm:min-w-0" style={inp} />
        </span>
        <span className="flex items-center gap-2 max-sm:w-full lg:contents">
          <label className="text-xs font-bold max-sm:w-6" style={{ color: '#1a2e22' }} htmlFor="bank-to">Do</label>
          <input id="bank-to" type="date" value={f.to} onChange={e => set({ to: e.target.value })} className="max-sm:flex-1 max-sm:min-w-0" style={inp} />
        </span>
        {(f.search || f.from || f.to) && (
          <button onClick={() => set({ search: '', from: '', to: '' })} className="text-sm font-bold cursor-pointer max-lg:min-h-[36px]"
            style={{ color: '#1a2e22', background: 'none', border: 'none', padding: '4px 6px', textDecoration: 'underline' }}>Zrušit hledání</button>
        )}
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fef3c7', color: '#b45309', fontSize: 13 }}>{error}</div>}

      {loading ? <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
        : !error && (
          <>
            <Table stack="tablet">
              <thead><TRow header><TH>Datum</TH><TH>Částka</TH><TH>VS</TH><TH>Plátce / protiúčet</TH><TH>Zpráva</TH><TH>Stav</TH><TH>Spárováno s</TH></TRow></thead>
              <tbody>
                {rows.map(tx => {
                  const st = statusOf(tx.status)
                  const todo = needsStaff(tx)
                  return (
                    <tr key={tx.fio_id} onClick={() => setDetailId(tx.fio_id)} className={`cursor-pointer hover:bg-[#f1faf7] transition-colors ${TAB_ROW}`}
                      style={{ borderBottom: '1px solid #d4e8e0' }} data-fio-id={tx.fio_id}>
                      <TD>{fmtDate(tx.tx_date)}</TD>
                      <TD bold style={{ color: Number(tx.amount) > 0 ? '#1a8a18' : '#4a6357', whiteSpace: 'nowrap' }}>
                        {Number(tx.amount) > 0 ? '+' : ''}{fmtMoney(tx.amount, tx.currency)}
                      </TD>
                      <TD mono>{tx.vs || '—'}</TD>
                      <TD>
                        <div className="font-bold" style={{ color: '#1a2e22' }}>{tx.counter_name || '—'}</div>
                        {tx.counter_account && <div className="font-mono" style={{ fontSize: 12, color: '#4a6357' }}>{tx.counter_account}{tx.counter_bank ? '/' + tx.counter_bank : ''}</div>}
                      </TD>
                      <TD style={{ maxWidth: 240, overflowWrap: 'anywhere' }}>{tx.message || '—'}</TD>
                      <TD>
                        <Badge label={st.label} color={st.color} bg={st.bg} />
                        {followupOpen(tx) && <div className="mt-1"><Badge label={FOLLOWUP[tx.followup] || 'Úkol'} color="#b45309" bg="#fef3c7" /></div>}
                        {todo && <div className="mt-1 max-lg:ml-auto" style={{ fontSize: 12, color: '#4a6357', maxWidth: 280 }}>{reasonText(tx)}</div>}
                      </TD>
                      <TD><TargetLink tx={tx} orderNumbers={orderNumbers} /></TD>
                    </tr>
                  )
                })}
                {rows.length === 0 && <tr style={{ borderBottom: '1px solid #d4e8e0' }}><TD label="" colSpan={7}>{f.search || f.from || f.to ? 'Hledání neodpovídá žádný pohyb.' : EMPTY[f.filter]}</TD></tr>}
              </tbody>
            </Table>
            <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
          </>
        )}

      {detailId !== null && (
        <BankMovementDetail fioId={detailId} tick={tick} orderNumbers={orderNumbers} notify={notify}
          onClose={() => setDetailId(null)} onChanged={changed} />
      )}
    </div>
  )
}
