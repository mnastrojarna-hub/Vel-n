import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import { accSku, deductFromWarehouse } from './BranchHelpers'

const TYPE_LABELS = { boots: 'Boty', helmet: 'Helma', gloves: 'Rukavice', pants: 'Kalhoty', jacket: 'Bunda', balaclava: 'Kukla' }
const STATUS_LABELS = {
  open: 'Otevřeno', warehouse_filled: 'Doplněno ze skladu', transfer_requested: 'Přesun zadán',
  order_created: 'Objednáno', resolved: 'Vyřešeno', dismissed: 'Zamítnuto',
}
const STATUS_COLORS = {
  open: '#dc2626', warehouse_filled: '#0ea5e9', transfer_requested: '#8b5cf6',
  order_created: '#f59e0b', resolved: '#16a34a', dismissed: '#64748b',
}

const fmtDay = (d) => new Date(d + 'T00:00:00').toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric' })
const todayIso = () => new Date().toISOString().slice(0, 10)
const addDaysIso = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10) }

export default function Logistika() {
  const [tab, setTab] = useState('calendar')
  const [branches, setBranches] = useState([])
  const [branchId, setBranchId] = useState('')
  const [from, setFrom] = useState(todayIso())
  const [to, setTo] = useState(addDaysIso(13))

  useEffect(() => {
    supabase.from('branches').select('id, name').order('name').then(({ data }) => {
      setBranches(data || [])
      if (data && data.length) setBranchId(data[0].id)
    })
  }, [])

  const branchName = branches.find(b => b.id === branchId)?.name || ''

  return (
    <div className="p-4 md:p-6">
      <div className="flex items-center justify-between flex-wrap gap-3 mb-4">
        <div>
          <h1 className="text-2xl font-black" style={{ color: '#0f1a14' }}>📦 Logistika zboží</h1>
          <p className="text-sm" style={{ color: '#1a2e22', opacity: 0.6 }}>
            Dostupnost výbavy na pobočkách a deficity z rezervací
          </p>
        </div>
        <select value={branchId} onChange={e => setBranchId(e.target.value)}
          className="rounded-btn text-sm font-semibold outline-none"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
          {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
        </select>
      </div>

      <div className="flex gap-2 mb-4">
        {[['calendar', 'Dostupnost'], ['worklist', 'Chybí kus']].map(([k, l]) => (
          <button key={k} onClick={() => setTab(k)}
            className="text-sm font-bold cursor-pointer rounded-btn"
            style={{
              padding: '8px 16px', border: 'none',
              background: tab === k ? '#1a2e22' : '#e8f3ee',
              color: tab === k ? '#74FB71' : '#1a2e22',
            }}>
            {l}
          </button>
        ))}
      </div>

      {tab === 'calendar'
        ? <CalendarTab branchId={branchId} from={from} to={to} setFrom={setFrom} setTo={setTo} />
        : <WorklistTab branchName={branchName} from={from} to={to} />}
    </div>
  )
}

// ─── Kalendář dostupnosti ───────────────────────────────────────────
function CalendarTab({ branchId, from, to, setFrom, setTo }) {
  const [rows, setRows] = useState([])
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    if (!branchId) return
    setLoading(true)
    const { data, error } = await supabase.rpc('get_branch_gear_calendar', {
      p_branch_id: branchId, p_from: from, p_to: to,
    })
    setRows(error ? [] : (data || []))
    setLoading(false)
  }, [branchId, from, to])

  useEffect(() => { load() }, [load])

  // days header
  const days = []
  for (let d = new Date(from + 'T00:00:00'); d <= new Date(to + 'T00:00:00'); d.setDate(d.getDate() + 1)) {
    days.push(d.toISOString().slice(0, 10))
  }
  // group rows by type+size
  const map = {}
  rows.forEach(r => {
    const key = `${r.accessory_type}|${r.size}`
    if (!map[key]) map[key] = { type: r.accessory_type, size: r.size, byDay: {} }
    map[key].byDay[r.shortage_date] = r
  })
  const lines = Object.values(map).sort((a, b) =>
    a.type === b.type ? String(a.size).localeCompare(String(b.size), 'cs', { numeric: true }) : a.type.localeCompare(b.type))

  return (
    <Card>
      <div className="flex items-center gap-3 mb-3 flex-wrap">
        <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Od</label>
        <input type="date" value={from} onChange={e => setFrom(e.target.value)}
          className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Do</label>
        <input type="date" value={to} onChange={e => setTo(e.target.value)}
          className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        <div className="flex items-center gap-3 ml-auto text-xs" style={{ color: '#1a2e22' }}>
          <Legend color="#16a34a" text="volné" />
          <Legend color="#f59e0b" text="vyčerpáno" />
          <Legend color="#dc2626" text="deficit" />
        </div>
      </div>

      {loading ? <div className="py-8 text-center text-sm" style={{ color: '#1a2e22', opacity: 0.5 }}>Načítám…</div>
        : lines.length === 0 ? <div className="py-8 text-center text-sm" style={{ color: '#1a2e22', opacity: 0.5 }}>Žádná výbava ani poptávka v tomto období.</div>
        : (
          <div className="overflow-x-auto">
            <table className="text-xs" style={{ borderCollapse: 'collapse', minWidth: '100%' }}>
              <thead>
                <tr>
                  <th className="text-left sticky left-0" style={{ padding: '6px 8px', background: '#fff', color: '#1a2e22', minWidth: 130 }}>Výbava</th>
                  {days.map(d => <th key={d} style={{ padding: '6px 4px', color: '#1a2e22', fontWeight: 700 }}>{fmtDay(d)}</th>)}
                </tr>
              </thead>
              <tbody>
                {lines.map(line => (
                  <tr key={line.type + line.size}>
                    <td className="sticky left-0 font-bold" style={{ padding: '5px 8px', background: '#fff', color: '#0f1a14', whiteSpace: 'nowrap' }}>
                      {(TYPE_LABELS[line.type] || line.type)} {line.size}
                    </td>
                    {days.map(d => {
                      const c = line.byDay[d]
                      const stock = c?.stock ?? 0, booked = c?.booked ?? 0, free = c?.free ?? 0, deficit = c?.deficit ?? 0
                      const bg = deficit > 0 ? '#fde2e2' : (stock > 0 && free === 0) ? '#fef3cd' : (stock > 0 ? '#e3f6e8' : '#f3f4f6')
                      const fg = deficit > 0 ? '#dc2626' : (stock > 0 && free === 0) ? '#b45309' : '#16a34a'
                      return (
                        <td key={d} title={`Skladem ${stock} · Vybookováno ${booked}`}
                          style={{ padding: '3px 4px', textAlign: 'center', background: bg, color: fg, fontWeight: 800, borderRadius: 4, minWidth: 34 }}>
                          {deficit > 0 ? `−${deficit}` : (stock > 0 ? free : '·')}
                        </td>
                      )
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
    </Card>
  )
}

function Legend({ color, text }) {
  return <span className="inline-flex items-center gap-1"><span style={{ width: 10, height: 10, borderRadius: 3, background: color, display: 'inline-block' }} />{text}</span>
}

// ─── Fronta „Chybí kus" ─────────────────────────────────────────────
function WorklistTab({ branchName }) {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [showDone, setShowDone] = useState(false)
  const [busy, setBusy] = useState(null)
  const [transferFor, setTransferFor] = useState(null)

  const load = useCallback(async () => {
    setLoading(true)
    let q = supabase.from('gear_shortages')
      .select('*, branches(name)')
      .order('shortage_date', { ascending: true })
    if (!showDone) q = q.in('status', ['open', 'warehouse_filled', 'transfer_requested', 'order_created'])
    const { data, error } = await q
    setItems(error ? [] : (data || []))
    setLoading(false)
  }, [showDone])

  useEffect(() => { load() }, [load])

  async function recompute(branchId) {
    const horizon = addDaysIso(120)
    await supabase.rpc('detect_gear_shortages_for_window', { p_branch_id: branchId, p_from: todayIso(), p_to: horizon })
  }

  async function fillFromWarehouse(it) {
    setBusy(it.id)
    try {
      const qty = it.deficit_qty
      const ok = await deductFromWarehouse(accSku(it.accessory_type, it.size), qty, it.branches?.name || branchName)
      if (!ok) { alert('Není skladem — použij přesun z jiné pobočky nebo vytvoř objednávku.'); setBusy(null); return }
      // navýšit kusy na pobočce
      const { data: row } = await supabase.from('branch_accessories')
        .select('id, quantity').eq('branch_id', it.branch_id).eq('type', it.accessory_type).eq('size', it.size).maybeSingle()
      if (row) await supabase.from('branch_accessories').update({ quantity: (row.quantity || 0) + qty }).eq('id', row.id)
      else await supabase.from('branch_accessories').insert({ branch_id: it.branch_id, type: it.accessory_type, size: it.size, quantity: qty })
      await supabase.from('gear_shortages').update({ status: 'warehouse_filled', updated_at: new Date().toISOString() }).eq('id', it.id)
      await recompute(it.branch_id)
    } finally { setBusy(null); load() }
  }

  async function createOrder(it) {
    setBusy(it.id)
    try {
      const { data, error } = await supabase.rpc('create_gear_purchase_order', { p_shortage_id: it.id, p_qty: null })
      if (error) { alert('Chyba: ' + error.message); return }
      if (!data?.success) {
        if (data?.error === 'no_inventory_item') alert(`Položka „${data.sku}" není v centrálním skladu — nejdřív ji založ v Sklady.`)
        else if (data?.error === 'no_supplier') alert('U skladové položky chybí dodavatel — doplň ho v Sklady a zkus znovu.')
        else alert('Objednávku nelze vytvořit: ' + (data?.error || 'neznámá chyba'))
        return
      }
      alert(`Vytvořena objednávka ${data.order_number} (draft). Odeslání dodavateli dokončíš v Nákupy.`)
    } finally { setBusy(null); load() }
  }

  async function autoOrderAll() {
    if (!confirm('Založit draft objednávky pro všechny otevřené deficity, které mají skladovou položku a dodavatele?')) return
    setBusy('auto')
    try {
      const { data, error } = await supabase.rpc('auto_order_gear_shortages')
      if (error) { alert('Chyba: ' + error.message); return }
      const d = data || {}
      alert(`Hotovo:\n• Vytvořeno objednávek: ${d.created || 0}\n• Napojeno na existující: ${d.skipped_dup || 0}\n• Bez skladové položky: ${d.skipped_no_item || 0}\n• Bez dodavatele: ${d.skipped_no_supplier || 0}`)
    } finally { setBusy(null); load() }
  }

  async function setStatus(it, status) {
    setBusy(it.id)
    const patch = { status, updated_at: new Date().toISOString() }
    if (status === 'resolved' || status === 'dismissed') patch.resolved_at = new Date().toISOString()
    await supabase.from('gear_shortages').update(patch).eq('id', it.id)
    setBusy(null); load()
  }

  return (
    <Card>
      <div className="flex items-center justify-between mb-3 flex-wrap gap-2">
        <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>
          {items.filter(i => i.status === 'open').length} otevřených deficitů
        </div>
        <div className="flex items-center gap-3 flex-wrap">
          <ActBtn disabled={busy === 'auto'} color="#f59e0b" onClick={autoOrderAll}>🔁 Objednat automaticky vše</ActBtn>
          <label className="text-sm flex items-center gap-1.5 cursor-pointer" style={{ color: '#1a2e22' }}>
            <input type="checkbox" checked={showDone} onChange={e => setShowDone(e.target.checked)} /> Zobrazit i vyřešené
          </label>
        </div>
      </div>

      {loading ? <div className="py-8 text-center text-sm" style={{ color: '#1a2e22', opacity: 0.5 }}>Načítám…</div>
        : items.length === 0 ? <div className="py-8 text-center text-sm" style={{ color: '#16a34a', fontWeight: 700 }}>✓ Žádné deficity — vše pokryto.</div>
        : (
          <div className="flex flex-col gap-2">
            {items.map(it => (
              <div key={it.id} className="flex items-center gap-3 flex-wrap rounded-btn"
                style={{ padding: '10px 12px', background: '#f9fdfb', border: '1px solid #e2eee8' }}>
                <div style={{ minWidth: 150 }}>
                  <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>
                    {(TYPE_LABELS[it.accessory_type] || it.accessory_type)} {it.size}
                    {it.audience === 'child' && <span className="ml-1 text-xs" title="dětská velikost">👶</span>}
                  </div>
                  <div className="text-xs" style={{ color: '#1a2e22', opacity: 0.7 }}>{it.branches?.name || ''} · {fmtDay(it.shortage_date)}</div>
                </div>
                <div className="text-sm" style={{ color: '#1a2e22' }}>
                  potřeba <b>{it.needed_qty}</b> · skladem <b>{it.stock_qty}</b> · chybí <b style={{ color: '#dc2626' }}>{it.deficit_qty}</b>
                </div>
                <span className="text-xs font-bold rounded-full ml-auto" style={{ padding: '3px 10px', background: (STATUS_COLORS[it.status] || '#64748b') + '22', color: STATUS_COLORS[it.status] || '#64748b' }}>
                  {STATUS_LABELS[it.status] || it.status}
                </span>
                {['open', 'warehouse_filled', 'transfer_requested', 'order_created'].includes(it.status) && (
                  <div className="flex gap-1.5 flex-wrap">
                    <ActBtn disabled={busy === it.id} color="#0ea5e9" onClick={() => fillFromWarehouse(it)}>Doplnit ze skladu</ActBtn>
                    <ActBtn disabled={busy === it.id} color="#8b5cf6" onClick={() => setTransferFor(it)}>Přesunout z pobočky</ActBtn>
                    <ActBtn disabled={busy === it.id} color="#f59e0b" onClick={() => createOrder(it)}>Vytvořit objednávku</ActBtn>
                    <ActBtn disabled={busy === it.id} color="#16a34a" onClick={() => setStatus(it, 'resolved')}>Vyřešeno</ActBtn>
                    <ActBtn disabled={busy === it.id} color="#64748b" onClick={() => setStatus(it, 'dismissed')}>Zamítnout</ActBtn>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      {transferFor && (
        <TransferModal it={transferFor} onClose={() => setTransferFor(null)} onDone={() => { setTransferFor(null); load() }} />
      )}
    </Card>
  )
}

// ─── Modal: přesun z jiné pobočky ───────────────────────────────────
function TransferModal({ it, onClose, onDone }) {
  const [sources, setSources] = useState(null)
  const [qty, setQty] = useState(it.deficit_qty)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    const horizon = addDaysIso(120)
    supabase.rpc('find_gear_surplus_branches', {
      p_type: it.accessory_type, p_size: it.size, p_from: it.shortage_date, p_to: horizon, p_exclude_branch: it.branch_id,
    }).then(({ data, error }) => setSources(error ? [] : (data || [])))
  }, [it])

  async function transfer(src) {
    const n = Math.min(qty, src.free_qty, it.deficit_qty)
    if (n <= 0) return
    setBusy(true)
    const { data, error } = await supabase.rpc('transfer_branch_gear', {
      p_from_branch: src.branch_id, p_to_branch: it.branch_id,
      p_type: it.accessory_type, p_size: it.size, p_qty: n, p_shortage_id: it.id,
    })
    setBusy(false)
    if (error || !data?.success) { alert('Přesun selhal: ' + (error?.message || data?.error || '')); return }
    onDone()
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,.5)' }} onClick={onClose}>
      <div className="rounded-card" style={{ background: '#fff', padding: 20, width: 'min(92vw, 440px)' }} onClick={e => e.stopPropagation()}>
        <div className="text-base font-black mb-1" style={{ color: '#0f1a14' }}>
          Přesun: {(TYPE_LABELS[it.accessory_type] || it.accessory_type)} {it.size}
        </div>
        <div className="text-xs mb-3" style={{ color: '#1a2e22', opacity: 0.7 }}>
          Cíl: {it.branches?.name} · {fmtDay(it.shortage_date)} · chybí {it.deficit_qty} ks
        </div>
        <div className="flex items-center gap-2 mb-3">
          <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Počet</label>
          <input type="number" min={1} max={it.deficit_qty} value={qty}
            onChange={e => setQty(Math.max(1, Number(e.target.value) || 1))}
            className="rounded-btn text-sm outline-none w-20" style={{ padding: '5px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>
        {sources === null ? <div className="py-4 text-center text-sm" style={{ opacity: 0.5 }}>Hledám přebytky…</div>
          : sources.length === 0 ? <div className="py-4 text-center text-sm" style={{ color: '#dc2626' }}>Žádná pobočka nemá v termínu volný kus — vytvoř objednávku.</div>
          : (
            <div className="flex flex-col gap-1.5">
              {sources.map(s => (
                <div key={s.branch_id} className="flex items-center gap-3 rounded-btn" style={{ padding: '8px 12px', background: '#f9fdfb', border: '1px solid #e2eee8' }}>
                  <div className="flex-1">
                    <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{s.branch_name}</div>
                    <div className="text-xs" style={{ color: '#16a34a' }}>volných {s.free_qty} ks</div>
                  </div>
                  <ActBtn disabled={busy} color="#8b5cf6" onClick={() => transfer(s)}>Přesunout {Math.min(qty, s.free_qty, it.deficit_qty)} ks</ActBtn>
                </div>
              ))}
            </div>
          )}
        <button onClick={onClose} className="mt-4 text-sm font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#64748b' }}>Zavřít</button>
      </div>
    </div>
  )
}

function ActBtn({ children, color, onClick, disabled }) {
  return (
    <button onClick={onClick} disabled={disabled}
      className="text-xs font-bold cursor-pointer rounded-btn"
      style={{ padding: '5px 10px', border: `1px solid ${color}`, background: '#fff', color, opacity: disabled ? 0.5 : 1 }}>
      {children}
    </button>
  )
}
