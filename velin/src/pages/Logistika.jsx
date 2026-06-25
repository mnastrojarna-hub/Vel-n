import { useState, useEffect, useCallback, lazy, Suspense } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import Inventory from './Inventory'
import SkuTag, { SkuConventionInfo } from '../components/ui/SkuTag'
import { buildSku, parseSku, normalizeSlug } from '../lib/sku'
import { accSku, deductFromWarehouse, returnToWarehouse, loadAccessoryTypes } from './BranchHelpers'

// Skladově se NErozlišuje řidič/spolujezdec — fyzické typy gearu (mají velikost):
const PHYSICAL_GEAR = ['helmet', 'jacket', 'pants', 'boots', 'gloves', 'balaclava']
const physicalTypes = (types) => (types || []).filter(t => PHYSICAL_GEAR.includes(t.key))
// Kategorie položky při naskladnění (skladová + účetní rovina). sized=gear s velikostí;
// asset=jen finance (nenaskladňuje se na sklad); inv=inventory.category; skuCat=SKU prefix.
// „Příslušenství" = vše půjčované k motorkám i mimo oficiální flow (zámky, páteřáky, držáky).
const ITEM_CATS = [
  { key: 'prislusenstvi_gear', label: 'Příslušenství – výbava (velikost)', sized: true, inv: 'prislusenstvi', skuCat: 'prislusenstvi' },
  { key: 'prislusenstvi', label: 'Příslušenství – ostatní (zámek, páteřák, držák…)', inv: 'prislusenstvi', skuCat: 'prislusenstvi' },
  { key: 'zbozi', label: 'Zboží – e-shop', inv: 'inventory', skuCat: 'zbozi' },
  { key: 'dily', label: 'Náhradní díly – servis', inv: 'material', skuCat: 'dily' },
  { key: 'material', label: 'Materiál', inv: 'material', skuCat: 'material' },
  { key: 'spotrebni', label: 'Spotřební / režie', inv: 'supplies', skuCat: 'spotrebni' },
  { key: 'dlouhodoby', label: 'Dlouhodobý majetek (motorka…) – jen finance', asset: true, inv: 'inventory', skuCat: 'majetek' },
]
const catDef = (k) => ITEM_CATS.find(c => c.key === k) || ITEM_CATS[1]
// Mapování AI category_suggestion → naše klíče
const AI_CAT_MAP = { prislusenstvi: 'prislusenstvi', zbozi: 'zbozi', dily: 'dily', material: 'material', spotrebni: 'spotrebni' }

const OrdersTab = lazy(() => import('./accounting/AutoOrdersTab'))

const TYPE_LABELS = { boots: 'Boty', helmet: 'Helma', gloves: 'Rukavice', pants: 'Kalhoty', jacket: 'Bunda', balaclava: 'Kukla' }
const STATUS_LABELS = {
  open: 'Otevřeno', warehouse_filled: 'Doplněno ze skladu', transfer_requested: 'Přesun zadán',
  order_created: 'Objednáno', resolved: 'Vyřešeno', dismissed: 'Zamítnuto',
}
const STATUS_COLORS = {
  open: '#dc2626', warehouse_filled: '#0ea5e9', transfer_requested: '#8b5cf6',
  order_created: '#f59e0b', resolved: '#16a34a', dismissed: '#64748b',
}
const tlabel = (t) => TYPE_LABELS[t] || t
const fmtDay = (d) => new Date(d + 'T00:00:00').toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric' })
const todayIso = () => new Date().toISOString().slice(0, 10)
const addDaysIso = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10) }

const TABS = [
  ['calendar', 'Dostupnost'], ['worklist', 'Chybí kus'], ['transfers', 'Přesuny'],
  ['stock', 'Sklad'], ['receive', 'Naskladnění'], ['catalog', 'Číselník SKU'], ['orders', 'Objednávky'],
]

export default function Logistika() {
  const [tab, setTab] = useState(() => {
    const t = new URLSearchParams(window.location.search).get('tab')
    return TABS.some(([k]) => k === t) ? t : 'calendar'
  })
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

  const showBranch = tab === 'calendar' || tab === 'worklist'

  return (
    <div className="p-4 md:p-6">
      <div className="flex items-center justify-between flex-wrap gap-3 mb-4">
        <div>
          <h1 className="text-2xl font-black" style={{ color: '#0f1a14' }}>📦 Logistika zboží</h1>
          <p className="text-sm" style={{ color: '#1a2e22', opacity: 0.6 }}>
            Dostupnost výbavy, deficity z rezervací, přesuny, sklad a objednávky
          </p>
        </div>
        {showBranch && (
          <select value={branchId} onChange={e => setBranchId(e.target.value)}
            className="rounded-btn text-sm font-semibold outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
            {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        )}
      </div>

      <div className="flex gap-2 mb-4 flex-wrap">
        {TABS.map(([k, l]) => (
          <button key={k} onClick={() => setTab(k)}
            className="text-sm font-bold cursor-pointer rounded-btn"
            style={{ padding: '8px 16px', border: 'none', background: tab === k ? '#1a2e22' : '#e8f3ee', color: tab === k ? '#74FB71' : '#1a2e22' }}>
            {l}
          </button>
        ))}
      </div>

      {tab === 'calendar' ? <CalendarTab branchId={branchId} from={from} to={to} setFrom={setFrom} setTo={setTo} />
        : tab === 'worklist' ? <WorklistTab branches={branches} />
        : tab === 'transfers' ? <PresunyTab branches={branches} />
        : tab === 'stock' ? <Inventory />
        : tab === 'receive' ? <NaskladneniTab />
        : tab === 'catalog' ? <CatalogTab />
        : <Suspense fallback={<div className="py-10 text-center text-sm" style={{ opacity: .5 }}>Načítám…</div>}><OrdersTab /></Suspense>}
    </div>
  )
}

// ─── Dostupnost (kalendář) ──────────────────────────────────────────
function CalendarTab({ branchId, from, to, setFrom, setTo }) {
  const [rows, setRows] = useState([])
  const [loading, setLoading] = useState(false)
  const [def, setDef] = useState({ count: 0, min: null, max: null })

  const load = useCallback(async () => {
    if (!branchId) return
    setLoading(true)
    // Recompute deficitů na CELÝ horizont této pobočky → kalendář i Chybí kus i banner sedí
    try { await supabase.rpc('detect_gear_shortages_for_window', { p_branch_id: branchId, p_from: todayIso(), p_to: addDaysIso(120) }) } catch { /* noop */ }
    const { data, error } = await supabase.rpc('get_branch_gear_calendar', { p_branch_id: branchId, p_from: from, p_to: to })
    setRows(error ? [] : (data || []))
    // Souhrn deficitů této pobočky (i mimo zobrazené okno) → navede uživatele
    const { data: defs } = await supabase.from('gear_shortages').select('shortage_date')
      .eq('branch_id', branchId).gt('deficit_qty', 0)
      .in('status', ['open', 'warehouse_filled', 'transfer_requested', 'order_created'])
    const ds = (defs || []).map(d => d.shortage_date).sort()
    setDef({ count: ds.length, min: ds[0] || null, max: ds[ds.length - 1] || null })
    setLoading(false)
  }, [branchId, from, to])
  useEffect(() => { load() }, [load])

  const outOfRange = def.count > 0 && (def.max > to || def.min < from)
  const noDeficits = def.count === 0
  const preset = (n) => { setFrom(todayIso()); setTo(addDaysIso(n)) }

  const days = []
  for (let d = new Date(from + 'T00:00:00'); d <= new Date(to + 'T00:00:00'); d.setDate(d.getDate() + 1)) days.push(d.toISOString().slice(0, 10))

  const group = (consumable) => {
    const map = {}
    rows.filter(r => !!r.is_consumable === consumable).forEach(r => {
      const key = `${r.accessory_type}|${r.size}`
      if (!map[key]) map[key] = { type: r.accessory_type, size: r.size, byDay: {}, stock: r.stock }
      map[key].byDay[r.shortage_date] = r
    })
    return Object.values(map)
  }
  const nonCons = group(false)
  const cons = group(true)

  return (
    <Card>
      <div className="flex items-center gap-3 mb-3 flex-wrap">
        <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Od</label>
        <input type="date" value={from} onChange={e => setFrom(e.target.value)}
          className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Do</label>
        <input type="date" value={to} onChange={e => setTo(e.target.value)}
          className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        {[['14 dní', 14], ['30 dní', 30], ['90 dní', 90]].map(([l, n]) => (
          <button key={n} onClick={() => preset(n)} className="text-xs font-bold cursor-pointer rounded-btn"
            style={{ padding: '5px 10px', border: '1px solid #d4e8e0', background: '#fff', color: '#1a2e22' }}>{l}</button>
        ))}
        <div className="flex items-center gap-3 ml-auto text-xs" style={{ color: '#1a2e22' }}>
          <Legend color="#16a34a" text="volné" /><Legend color="#f59e0b" text="vyčerpáno" /><Legend color="#dc2626" text="deficit" />
        </div>
      </div>

      {outOfRange && (
        <div className="mb-3 rounded-btn flex items-center gap-3 flex-wrap" style={{ padding: '10px 12px', background: '#fff5f5', border: '1px solid #fca5a5' }}>
          <span className="text-sm font-bold" style={{ color: '#dc2626' }}>
            ⚠ Na této pobočce je {def.count} deficitů ({fmtDay(def.min)} – {fmtDay(def.max)}), část je mimo zobrazené období.
          </span>
          <button onClick={() => { setFrom(def.min < todayIso() ? todayIso() : def.min); setTo(def.max) }}
            className="text-xs font-bold cursor-pointer rounded-btn" style={{ padding: '5px 10px', border: 'none', background: '#dc2626', color: '#fff' }}>
            Zobrazit období deficitů
          </button>
        </div>
      )}
      {!loading && noDeficits && (
        <div className="mb-3 text-xs" style={{ color: '#1a2e22', opacity: 0.6 }}>
          Tato pobočka nemá žádné deficity. Deficit z „Chybí kus" může být na jiné pobočce — přepni ji v selectoru nahoře.
        </div>
      )}

      {loading ? <div className="py-8 text-center text-sm" style={{ color: '#1a2e22', opacity: 0.5 }}>Načítám…</div>
        : nonCons.length === 0 && cons.length === 0 ? <div className="py-8 text-center text-sm" style={{ color: '#1a2e22', opacity: 0.5 }}>Žádné typy příslušenství. Přidej je ve Velíně → Pobočky → Příslušenství.</div>
        : (
          <>
            <SectionTitle>Nespotřební (půjčované)</SectionTitle>
            {nonCons.length === 0 ? <Empty /> : (
              <div className="overflow-x-auto mb-5">
                <table className="text-xs" style={{ borderCollapse: 'collapse', minWidth: '100%' }}>
                  <thead><tr>
                    <th className="text-left sticky left-0" style={{ padding: '6px 8px', background: '#fff', color: '#1a2e22', minWidth: 130 }}>Výbava</th>
                    {days.map(d => <th key={d} style={{ padding: '6px 4px', color: '#1a2e22', fontWeight: 700 }}>{fmtDay(d)}</th>)}
                  </tr></thead>
                  <tbody>
                    {nonCons.map(line => (
                      <tr key={line.type + line.size}>
                        <td className="sticky left-0 font-bold" style={{ padding: '5px 8px', background: '#fff', color: '#0f1a14', whiteSpace: 'nowrap' }}>{tlabel(line.type)} {line.size}</td>
                        {days.map(d => {
                          const c = line.byDay[d]
                          const stock = c?.stock ?? 0, free = c?.free ?? 0, deficit = c?.deficit ?? 0
                          const bg = deficit > 0 ? '#fde2e2' : (stock > 0 && free === 0) ? '#fef3cd' : (stock > 0 ? '#e3f6e8' : '#f3f4f6')
                          const fg = deficit > 0 ? '#dc2626' : (stock > 0 && free === 0) ? '#b45309' : (stock > 0 ? '#16a34a' : '#9ca3af')
                          return (
                            <td key={d} title={`Skladem ${stock} · Vybookováno ${c?.booked ?? 0}`}
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

            <SectionTitle>Spotřební</SectionTitle>
            {cons.length === 0 ? <Empty /> : (
              <div className="flex flex-wrap gap-2">
                {cons.map(line => (
                  <div key={line.type + line.size} className="rounded-btn text-sm font-bold" style={{ padding: '6px 12px', background: (line.stock > 0 ? '#e3f6e8' : '#fee2e2'), color: (line.stock > 0 ? '#16a34a' : '#dc2626'), border: '1px solid #d4e8e0' }}>
                    {tlabel(line.type)} {line.size}: {line.stock} ks
                  </div>
                ))}
              </div>
            )}
          </>
        )}
    </Card>
  )
}
const SectionTitle = ({ children }) => <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>{children}</div>
const Empty = () => <div className="text-xs mb-4" style={{ color: '#1a2e22', opacity: 0.45 }}>— žádné —</div>
const Legend = ({ color, text }) => <span className="inline-flex items-center gap-1"><span style={{ width: 10, height: 10, borderRadius: 3, background: color, display: 'inline-block' }} />{text}</span>

// ─── Chybí kus (fronta) ─────────────────────────────────────────────
function WorklistTab({ branches }) {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [showDone, setShowDone] = useState(false)
  const [busy, setBusy] = useState(null)
  const [transferFor, setTransferFor] = useState(null)
  const bmap = Object.fromEntries((branches || []).map(b => [b.id, b.name]))

  const load = useCallback(async (recompute = false) => {
    setLoading(true)
    // Recompute → badge / kalendář / fronta vždy souhlasí (žádná „potěmkinova vesnice")
    if (recompute) { try { await supabase.rpc('detect_gear_shortages', { p_horizon_days: 120 }) } catch { /* noop */ } }
    let q = supabase.from('gear_shortages').select('*').order('shortage_date', { ascending: true })  // BEZ embedu branches (2 FK → dvojznačné)
    if (!showDone) q = q.in('status', ['open', 'warehouse_filled', 'transfer_requested', 'order_created'])
    const { data, error } = await q
    setItems(error ? [] : (data || []))
    setLoading(false)
  }, [showDone])

  useEffect(() => { load(true) }, [])          // první načtení vždy přepočítá
  useEffect(() => { load(false) }, [showDone])  // přepnutí filtru jen čte

  async function recomputeBranch(branchId) {
    try { await supabase.rpc('detect_gear_shortages_for_window', { p_branch_id: branchId, p_from: todayIso(), p_to: addDaysIso(120) }) } catch { /* noop */ }
  }

  async function fillFromWarehouse(it) {
    setBusy(it.id)
    try {
      const qty = it.deficit_qty
      const ok = await deductFromWarehouse(accSku(it.accessory_type, it.size), qty, bmap[it.branch_id] || '')
      if (!ok) { alert('Není skladem — použij přesun z jiné pobočky nebo vytvoř objednávku.'); return }
      const { data: row } = await supabase.from('branch_accessories').select('id, quantity')
        .eq('branch_id', it.branch_id).eq('type', it.accessory_type).eq('size', it.size).maybeSingle()
      if (row) await supabase.from('branch_accessories').update({ quantity: (row.quantity || 0) + qty }).eq('id', row.id)
      else await supabase.from('branch_accessories').insert({ branch_id: it.branch_id, type: it.accessory_type, size: it.size, quantity: qty })
      await supabase.from('gear_shortages').update({ status: 'warehouse_filled', updated_at: new Date().toISOString() }).eq('id', it.id)
      await recomputeBranch(it.branch_id)
    } finally { setBusy(null); load(false) }
  }

  async function createOrder(it) {
    setBusy(it.id)
    try {
      const { data, error } = await supabase.rpc('create_gear_purchase_order', { p_shortage_id: it.id, p_qty: null })
      if (error) { alert('Chyba: ' + error.message); return }
      if (!data?.success) {
        if (data?.error === 'no_inventory_item') alert(`Položka „${data.sku}" není v centrálním skladu — nejdřív ji založ ve Sklad.`)
        else if (data?.error === 'no_supplier') alert('U skladové položky chybí dodavatel — doplň ho ve Sklad a zkus znovu.')
        else alert('Objednávku nelze vytvořit: ' + (data?.error || 'neznámá chyba'))
        return
      }
      alert(`Vytvořena objednávka ${data.order_number} (draft). Odeslání dodavateli dokončíš v záložce Objednávky.`)
    } finally { setBusy(null); load(false) }
  }

  async function autoOrderAll() {
    if (!confirm('Založit draft objednávky pro všechny otevřené deficity, které mají skladovou položku a dodavatele?')) return
    setBusy('auto')
    try {
      const { data, error } = await supabase.rpc('auto_order_gear_shortages')
      if (error) { alert('Chyba: ' + error.message); return }
      const d = data || {}
      alert(`Hotovo:\n• Vytvořeno objednávek: ${d.created || 0}\n• Napojeno na existující: ${d.skipped_dup || 0}\n• Bez skladové položky: ${d.skipped_no_item || 0}\n• Bez dodavatele: ${d.skipped_no_supplier || 0}`)
    } finally { setBusy(null); load(false) }
  }

  async function setStatus(it, status) {
    setBusy(it.id)
    const patch = { status, updated_at: new Date().toISOString() }
    if (status === 'resolved' || status === 'dismissed') patch.resolved_at = new Date().toISOString()
    await supabase.from('gear_shortages').update(patch).eq('id', it.id)
    setBusy(null); load(false)
  }

  const openCount = items.filter(i => i.status === 'open').length

  return (
    <Card>
      <div className="flex items-center justify-between mb-3 flex-wrap gap-2">
        <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>{openCount} otevřených deficitů</div>
        <div className="flex items-center gap-3 flex-wrap">
          <ActBtn disabled={loading} color="#1a2e22" onClick={() => load(true)}>🔄 Přepočítat</ActBtn>
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
              <div key={it.id} className="flex items-center gap-3 flex-wrap rounded-btn" style={{ padding: '10px 12px', background: '#f9fdfb', border: '1px solid #e2eee8' }}>
                <div style={{ minWidth: 150 }}>
                  <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>
                    {tlabel(it.accessory_type)} {it.size}
                    {it.audience === 'child' && <span className="ml-1 text-xs" title="dětská velikost">👶</span>}
                  </div>
                  <div className="text-xs" style={{ color: '#1a2e22', opacity: 0.7 }}>{bmap[it.branch_id] || '—'} · {fmtDay(it.shortage_date)}</div>
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
      {transferFor && <TransferModal it={transferFor} branchName={bmap[transferFor.branch_id] || ''} onClose={() => setTransferFor(null)} onDone={() => { setTransferFor(null); load(false) }} />}
    </Card>
  )
}

// ─── Modal: přesun z jiné pobočky (z fronty deficitu) ────────────────
function TransferModal({ it, branchName, onClose, onDone }) {
  const [sources, setSources] = useState(null)
  const [qty, setQty] = useState(it.deficit_qty)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    supabase.rpc('find_gear_surplus_branches', {
      p_type: it.accessory_type, p_size: it.size, p_from: it.shortage_date, p_to: addDaysIso(120), p_exclude_branch: it.branch_id,
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
        <div className="text-base font-black mb-1" style={{ color: '#0f1a14' }}>Přesun: {tlabel(it.accessory_type)} {it.size}</div>
        <div className="text-xs mb-3" style={{ color: '#1a2e22', opacity: 0.7 }}>Cíl: {branchName} · {fmtDay(it.shortage_date)} · chybí {it.deficit_qty} ks</div>
        <div className="flex items-center gap-2 mb-3">
          <label className="text-sm font-bold" style={{ color: '#1a2e22' }}>Počet</label>
          <input type="number" min={1} max={it.deficit_qty} value={qty} onChange={e => setQty(Math.max(1, Number(e.target.value) || 1))}
            className="rounded-btn text-sm outline-none w-20" style={{ padding: '5px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>
        {sources === null ? <div className="py-4 text-center text-sm" style={{ opacity: 0.5 }}>Hledám přebytky…</div>
          : sources.length === 0 ? <div className="py-4 text-center text-sm" style={{ color: '#dc2626' }}>Žádná pobočka nemá v termínu volný kus — doplň ze skladu nebo vytvoř objednávku.</div>
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

// ─── Přesuny (obecné: sklad↔pobočka, pobočka↔pobočka) ────────────────
function PresunyTab({ branches }) {
  const [accTypes, setAccTypes] = useState([])
  const [dir, setDir] = useState('wh2branch')   // wh2branch | branch2wh | branch2branch
  const [type, setType] = useState(''); const [size, setSize] = useState('')
  const [fromBranch, setFromBranch] = useState(''); const [toBranch, setToBranch] = useState('')
  const [qty, setQty] = useState(1); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState(null)

  useEffect(() => { loadAccessoryTypes().then(setAccTypes) }, [])
  const sizes = accTypes.find(t => t.key === type)?.sizes || []
  const bname = (id) => branches.find(b => b.id === id)?.name || ''

  async function adjustBranch(branchId, delta) {
    const { data: row } = await supabase.from('branch_accessories').select('id, quantity')
      .eq('branch_id', branchId).eq('type', type).eq('size', size).maybeSingle()
    if (row) await supabase.from('branch_accessories').update({ quantity: Math.max(0, (row.quantity || 0) + delta) }).eq('id', row.id)
    else if (delta > 0) await supabase.from('branch_accessories').insert({ branch_id: branchId, type, size, quantity: delta })
    return row?.quantity || 0
  }
  async function recompute(branchId) {
    try { await supabase.rpc('detect_gear_shortages_for_window', { p_branch_id: branchId, p_from: todayIso(), p_to: addDaysIso(120) }) } catch { /* noop */ }
  }

  async function go() {
    setMsg(null)
    const n = Math.max(1, Number(qty) || 0)
    if (!type || !size) { setMsg({ err: true, t: 'Vyber typ a velikost.' }); return }
    setBusy(true)
    try {
      if (dir === 'wh2branch') {
        if (!toBranch) { setMsg({ err: true, t: 'Vyber cílovou pobočku.' }); return }
        const ok = await deductFromWarehouse(accSku(type, size), n, bname(toBranch))
        if (!ok) { setMsg({ err: true, t: 'Na centrálním skladu není dost kusů.' }); return }
        await adjustBranch(toBranch, n); await recompute(toBranch)
        setMsg({ t: `Přesunuto ${n} ks ze skladu → ${bname(toBranch)}.` })
      } else if (dir === 'branch2wh') {
        if (!fromBranch) { setMsg({ err: true, t: 'Vyber zdrojovou pobočku.' }); return }
        const cur = await adjustBranch(fromBranch, 0)
        if (cur < n) { setMsg({ err: true, t: `Na pobočce je jen ${cur} ks.` }); return }
        await adjustBranch(fromBranch, -n)
        await returnToWarehouse(accSku(type, size), n, bname(fromBranch))
        await recompute(fromBranch)
        setMsg({ t: `Vráceno ${n} ks z ${bname(fromBranch)} → sklad.` })
      } else {
        if (!fromBranch || !toBranch || fromBranch === toBranch) { setMsg({ err: true, t: 'Vyber různou zdrojovou a cílovou pobočku.' }); return }
        const { data, error } = await supabase.rpc('transfer_branch_gear', { p_from_branch: fromBranch, p_to_branch: toBranch, p_type: type, p_size: size, p_qty: n })
        if (error || !data?.success) { setMsg({ err: true, t: 'Přesun selhal: ' + (error?.message || data?.error || '') }); return }
        setMsg({ t: `Přesunuto ${n} ks ${bname(fromBranch)} → ${bname(toBranch)}.` })
      }
    } finally { setBusy(false) }
  }

  const Sel = ({ value, onChange, children }) => (
    <select value={value} onChange={e => onChange(e.target.value)} className="rounded-btn text-sm outline-none"
      style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>{children}</select>
  )

  return (
    <Card>
      <div className="text-sm mb-3" style={{ color: '#1a2e22', opacity: 0.7 }}>Přesun výbavy mezi centrálním skladem a pobočkami i mezi pobočkami navzájem.</div>
      <div className="flex gap-2 mb-4 flex-wrap">
        {[['wh2branch', 'Sklad → Pobočka'], ['branch2wh', 'Pobočka → Sklad'], ['branch2branch', 'Pobočka → Pobočka']].map(([k, l]) => (
          <button key={k} onClick={() => setDir(k)} className="text-sm font-bold cursor-pointer rounded-btn"
            style={{ padding: '6px 12px', border: 'none', background: dir === k ? '#1a2e22' : '#e8f3ee', color: dir === k ? '#74FB71' : '#1a2e22' }}>{l}</button>
        ))}
      </div>

      <div className="flex items-end gap-3 flex-wrap">
        {(dir === 'branch2wh' || dir === 'branch2branch') && (
          <Field label="Z pobočky"><Sel value={fromBranch} onChange={setFromBranch}><option value="">—</option>{branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}</Sel></Field>
        )}
        {(dir === 'wh2branch' || dir === 'branch2branch') && (
          <Field label="Na pobočku"><Sel value={toBranch} onChange={setToBranch}><option value="">—</option>{branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}</Sel></Field>
        )}
        <Field label="Typ"><Sel value={type} onChange={v => { setType(v); setSize('') }}><option value="">—</option>{physicalTypes(accTypes).map(t => <option key={t.key} value={t.key}>{t.label}</option>)}</Sel></Field>
        <Field label="Velikost"><Sel value={size} onChange={setSize}><option value="">—</option>{sizes.map(s => <option key={s} value={s}>{s}</option>)}</Sel></Field>
        <Field label="Počet">
          <input type="number" min={1} value={qty} onChange={e => setQty(e.target.value)} className="rounded-btn text-sm outline-none w-20"
            style={{ padding: '7px 8px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </Field>
        <button onClick={go} disabled={busy} className="text-sm font-bold cursor-pointer rounded-btn"
          style={{ padding: '8px 18px', border: 'none', background: '#1a2e22', color: '#74FB71', opacity: busy ? 0.5 : 1 }}>{busy ? 'Přesouvám…' : 'Přesunout'}</button>
      </div>
      {msg && <div className="mt-3 text-sm font-bold" style={{ color: msg.err ? '#dc2626' : '#16a34a' }}>{msg.t}</div>}
    </Card>
  )
}
const Field = ({ label, children }) => (
  <div className="flex flex-col gap-1"><span className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{label}</span>{children}</div>
)

function ActBtn({ children, color, onClick, disabled }) {
  return (
    <button onClick={onClick} disabled={disabled} className="text-xs font-bold cursor-pointer rounded-btn"
      style={{ padding: '5px 10px', border: `1px solid ${color}`, background: '#fff', color, opacity: disabled ? 0.5 : 1 }}>{children}</button>
  )
}

// ─── Naskladnění z dokladu (Fáze 4) ─────────────────────────────────
const TYPE_KEYWORDS = [
  ['boots', /\b(bot|boty|boot|obuv)/i], ['helmet', /\b(helm|p[řr]ilb)/i],
  ['gloves', /\b(rukav|glove)/i], ['pants', /\b(kalhot|pants)/i],
  ['jacket', /\b(bund|jacket)/i], ['balaclava', /\b(kukl|balaclava)/i],
]
function guessLine(desc) {
  const d = String(desc || ''); let type = ''
  for (const [t, re] of TYPE_KEYWORDS) { if (re.test(d)) { type = t; break } }
  let size = ''
  const num = d.match(/\b(3[3-9]|4[0-9])\b/)
  const alpha = d.match(/\b(XS|S|M|L|XL|XXL|2XL|3XL)\b/i)
  if (num) size = num[1]; else if (alpha) size = alpha[1].toUpperCase()
  return { type, size }
}

function NaskladneniTab() {
  const [accTypes, setAccTypes] = useState([])
  const [docType, setDocType] = useState('ocr')
  const [docs, setDocs] = useState([])
  const [docId, setDocId] = useState('')
  const [lines, setLines] = useState([])
  const [busy, setBusy] = useState(false)
  const [ocrBusy, setOcrBusy] = useState(false)
  const [ocrInfo, setOcrInfo] = useState(null)
  const [ocrDoc, setOcrDoc] = useState(null)   // data pro commit (zápis do financí až po Uložit)
  const [catalog, setCatalog] = useState([])

  useEffect(() => { loadAccessoryTypes().then(setAccTypes) }, [])
  useEffect(() => { supabase.from('sku_catalog').select('sku,name,category,type,size,aliases').then(({ data }) => setCatalog(data || [])) }, [])

  // Číselník: najdi položku podle názvu/aliasu (učí se z minulých korekcí)
  function catalogMatch(desc) {
    const k = normalizeSlug(desc || ''); if (!k) return null
    for (const r of catalog) { if ([r.name, ...(r.aliases || [])].filter(Boolean).map(normalizeSlug).includes(k)) return r }
    for (const r of catalog) { for (const a of [r.name, ...(r.aliases || [])]) { const ak = normalizeSlug(a); if (ak && ak.length > 3 && k.includes(ak)) return r } }
    return null
  }
  function catRowToLine(r, it) {
    const cat = r.category === 'prislusenstvi' ? ((r.size || r.type) ? 'prislusenstvi_gear' : 'prislusenstvi') : (AI_CAT_MAP[r.category] || 'prislusenstvi')
    const ps = parseSku(r.sku)
    return { name: it.description || r.name, qty: it.quantity || 1, unit_price: it.unit_price ?? it.amount ?? 0,
      cat, type: r.type || (ps?.type || ''), size: r.size || (ps?.size || it.size || ''),
      slug: cat === 'prislusenstvi_gear' ? '' : (ps && !ps.isAccessory ? ps.slug : (r.name || '')), color: it.color || '' }
  }
  useEffect(() => {
    setDocId(''); setLines([]); setOcrInfo(null); setOcrDoc(null)
    if (docType === 'manual' || docType === 'ocr') { setDocs([]); return }
    if (docType === 'dl') supabase.from('delivery_notes').select('id, dl_number, supplier_name, items, delivery_date').order('created_at', { ascending: false }).limit(50).then(({ data }) => setDocs(data || []))
    else supabase.from('invoices').select('id, number, notes, items, issue_date').eq('type', 'received').order('issue_date', { ascending: false }).limit(50).then(({ data }) => setDocs(data || []))
  }, [docType])

  const mkLine = (name, price, qty) => { const g = guessLine(name); return { name: name || '', qty: qty || 1, unit_price: price || 0, cat: g.type ? 'prislusenstvi_gear' : 'prislusenstvi', type: g.type, size: g.size, slug: name || '', color: '' } }
  // Z OCR řádku poskládá položku: nejdřív zkusí číselník (naučené), pak AI návrh.
  const mkLineFromOcr = (it) => {
    const m = catalogMatch(it.original_description) || catalogMatch(it.description)
    if (m) return catRowToLine(m, it)
    const price = it.unit_price ?? it.amount ?? 0
    const p = it.sku_suggestion ? parseSku(it.sku_suggestion) : null
    if (p && p.isAccessory) return { name: it.description || '', qty: it.quantity || 1, unit_price: price, cat: 'prislusenstvi_gear', type: p.type || '', size: it.size || p.size || '', slug: '', color: it.color || '' }
    const aiCat = AI_CAT_MAP[it.category_suggestion] || (p && !p.isAccessory ? AI_CAT_MAP[p.category] : null) || 'prislusenstvi'
    const slug = (p && !p.isAccessory && p.slug) ? p.slug : (it.description || '')
    return { name: it.description || '', qty: it.quantity || 1, unit_price: price, cat: aiCat, type: '', size: it.size || '', slug, color: it.color || '' }
  }

  async function handleOcr(file) {
    if (!file) return
    setOcrBusy(true); setOcrInfo(null); setLines([])
    try {
      const b64 = await new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = rej; r.readAsDataURL(file) })
      // EXTRACT — jen vyčíst (přeložit, ČNB, SKU). NIC se zatím nezapisuje do financí ani skladu.
      const { data, error } = await supabase.functions.invoke('receive-invoice', { body: { mode: 'extract', image_base64: b64, file_name: file.name || 'foto.jpg', source: 'velin' } })
      if (error) { alert('OCR selhalo: ' + error.message); return }
      if (!data?.success) { alert('Doklad se nepodařilo přečíst: ' + (data?.error || 'neznámá chyba')); return }
      const items = Array.isArray(data.line_items) ? data.line_items : []
      const ex = data.extracted || {}
      setOcrDoc(data.doc || null)
      setOcrInfo({
        supplier: ex.supplier, number: ex.invoice_number,
        type: data.document_type, count: items.length, eventId: null,
        lang: data.source_language, needsReview: data.needs_review,
        currency: data.currency, fxDate: data.fx_date, fxFailed: data.fx_failed, isProforma: data.is_proforma,
        amount: data.amount_czk, ico: ex.supplier_ico, bank: ex.supplier_bank_account,
        vs: ex.variable_symbol, issue: ex.date, due: ex.due_date, pay: ex.payment_method,
      })
      setLines(items.length ? items.map(mkLineFromOcr) : [mkLine('', 0, 1)])
    } finally { setOcrBusy(false) }
  }
  function pickDoc(id) {
    setDocId(id); const d = docs.find(x => x.id === id); const items = Array.isArray(d?.items) ? d.items : []
    setLines(items.length ? items.map(it => mkLine(it.description || it.name || '', it.amount ?? it.unit_price ?? 0, it.quantity || 1)) : [mkLine('', 0, 1)])
  }
  const upd = (i, patch) => setLines(ls => ls.map((l, j) => j === i ? { ...l, ...patch } : l))
  const lineSku = (l) => { const d = catDef(l.cat); if (d.asset) return ''; if (d.sized) return (l.type && l.size) ? accSku(l.type, l.size) : ''; return l.slug ? buildSku(d.skuCat, l.slug) : '' }
  const discard = () => { setLines([]); setOcrInfo(null); setOcrDoc(null); setDocId('') }

  async function stockAll() {
    setBusy(true)
    try {
      // 1) ZÁPIS DO FINANCÍ až teď (Uložit): commit OCR dokladu → finanční událost
      let eventId = ocrInfo?.eventId
      if (docType === 'ocr' && ocrDoc && !eventId) {
        const { data: c, error: ce } = await supabase.functions.invoke('receive-invoice', { body: { mode: 'commit', source: 'velin', doc: ocrDoc } })
        if (ce || !c?.success) { alert('Uložení do financí selhalo: ' + (ce?.message || c?.error || 'neznámá chyba')); return }
        eventId = c.financial_event_id
        setOcrInfo(o => ({ ...o, eventId }))
      }
      // 2) Zálohová (proforma) → jen do financí, NEnaskladňovat
      if (ocrInfo?.isProforma) { alert('Uloženo do Finance → Účetnictví → Finanční události (zálohová faktura — nenaskladňuje se).'); discard(); return }

      // 3) NASKLADNĚNÍ
      const payload = lines.map(l => ({ sku: lineSku(l), name: l.color ? `${l.name} ${l.color}` : l.name, qty: Number(l.qty) || 0, unit_price: Number(l.unit_price) || 0, category: catDef(l.cat).inv })).filter(l => l.sku && l.qty > 0)
      if (!payload.length) {
        if (docType === 'ocr') { alert('Uloženo do financí. Žádná skladová položka (vyplň typ+velikost / kategorii u položek, které chceš naskladnit).'); discard() }
        else alert('Žádná položka nemá vyplněné SKU a počet > 0.')
        return
      }
      const d = docs.find(x => x.id === docId)
      const note = docType === 'ocr' ? `Naskladnění z faktury (OCR)${ocrInfo?.supplier ? ' ' + ocrInfo.supplier : ''}${ocrInfo?.number ? ' ' + ocrInfo.number : ''}${eventId ? ' [FE:' + eventId + ']' : ''}`.trim()
        : docType === 'manual' ? 'Ruční naskladnění'
        : `Naskladnění z ${docType === 'dl' ? 'DL ' + (d?.dl_number || '') : 'FA ' + (d?.number || '')}`.trim()
      const { data, error } = await supabase.rpc('receive_stock_from_document', { p_lines: payload, p_note: note })
      if (error) { alert('Chyba: ' + error.message); return }
      if (!data?.success) { alert('Naskladnění selhalo: ' + (data?.error || '')); return }
      // 4) Učení číselníku z (zkorigovaných) položek → příště zařadí samo
      for (const l of lines) {
        const sku = lineSku(l); if (!sku) continue
        const dd = catDef(l.cat)
        try { await supabase.rpc('learn_sku', { p_sku: sku, p_name: l.name || sku, p_category: dd.skuCat === 'majetek' ? 'zbozi' : dd.skuCat, p_type: dd.sized ? (l.type || '') : '', p_size: dd.sized ? (l.size || '') : '', p_alias: (l.name || '').trim() }) } catch { /* noop */ }
      }
      supabase.from('sku_catalog').select('sku,name,category,type,size,aliases').then(({ data: c }) => setCatalog(c || []))
      alert(`Uloženo${docType === 'ocr' ? ' do financí' : ''}. Naskladněno ${data.stocked} položek.`); discard()
    } finally { setBusy(false) }
  }

  return (
    <Card>
      <div className="flex items-center gap-2 mb-3 flex-wrap">
        {[['ocr', '📷 Vyfotit / nahrát'], ['dl', 'Z dodacího listu'], ['invoice', 'Z přijaté faktury'], ['manual', 'Ručně']].map(([k, l]) => (
          <button key={k} onClick={() => setDocType(k)} className="text-sm font-bold cursor-pointer rounded-btn"
            style={{ padding: '6px 12px', border: 'none', background: docType === k ? '#1a2e22' : '#e8f3ee', color: docType === k ? '#74FB71' : '#1a2e22' }}>{l}</button>
        ))}
        {docType === 'ocr' && (
          <label className="rounded-btn text-sm font-bold cursor-pointer inline-flex items-center" style={{ padding: '7px 12px', background: '#1a2e22', color: '#74FB71', opacity: ocrBusy ? 0.6 : 1 }}>
            {ocrBusy ? 'Čtu doklad…' : '📷 Vybrat / vyfotit fakturu'}
            <input type="file" accept="image/*" capture="environment" style={{ display: 'none' }} disabled={ocrBusy} onChange={e => handleOcr(e.target.files?.[0])} />
          </label>
        )}
        {(docType === 'dl' || docType === 'invoice') && (
          <select value={docId} onChange={e => pickDoc(e.target.value)} className="rounded-btn text-sm outline-none" style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', minWidth: 260 }}>
            <option value="">— vyber doklad —</option>
            {docs.map(d => <option key={d.id} value={d.id}>{docType === 'dl' ? (d.dl_number || '—') : (d.number || '—')} · {d.supplier_name || (d.notes?.split('\n')[0]) || ''} · {(Array.isArray(d.items) ? d.items.length : 0)} pol.</option>)}
          </select>
        )}
        {docType === 'manual' && <button onClick={() => setLines(ls => [...ls, mkLine('', 0, 1)])} className="text-sm font-bold cursor-pointer rounded-btn" style={{ padding: '6px 12px', border: '1px solid #1a2e22', background: '#fff', color: '#1a2e22' }}>+ Řádek</button>}
        <span className="ml-auto"><SkuConventionInfo /></span>
      </div>
      {docType === 'ocr' && ocrInfo && ocrInfo.isProforma && (
        <div className="mb-2 rounded-btn text-sm font-bold" style={{ padding: '8px 12px', background: '#fff5f5', color: '#dc2626', border: '1px solid #fca5a5' }}>
          ⚠ Zálohová faktura (proforma) — zboží zatím nedorazilo, <b>nenaskladňuje se</b>. Po <b>Uložit</b> se zapíše jen jako evidence do finanční události.
        </div>
      )}
      {docType === 'ocr' && ocrInfo && !ocrInfo.isProforma && (
        <div className="mb-2 rounded-btn text-sm font-bold" style={{ padding: '8px 12px', background: '#e3f6e8', color: '#16a34a', border: '1px solid #bbf7d0' }}>
          ✓ {ocrInfo.type === 'delivery_note' ? 'Dodací list' : 'Faktura'}: {ocrInfo.supplier || 'dodavatel ?'}{ocrInfo.number ? ` · ${ocrInfo.number}` : ''} · {ocrInfo.count} položek
          {ocrInfo.lang && ocrInfo.lang !== 'cs' ? ` · přeloženo z „${ocrInfo.lang}"` : ''}
          {ocrInfo.currency && ocrInfo.currency !== 'CZK' ? (ocrInfo.fxFailed ? ` · ⚠ kurz ČNB nenačten — ceny v ${ocrInfo.currency}` : ` · ceny převedeny ${ocrInfo.currency}→CZK (ČNB ${ocrInfo.fxDate || ''})`) : ''}
          <div className="text-xs font-semibold mt-1" style={{ color: '#1a2e22', opacity: 0.8 }}>
            💡 Zatím nic nezapsáno. Po kliknutí na <b>Uložit</b> se doklad zapíše do Finance → Účetnictví → Finanční události a zboží se naskladní.{ocrInfo.needsReview ? ' Nízká jistota OCR — zkontroluj údaje.' : ''}
          </div>
        </div>
      )}
      {docType === 'ocr' && ocrInfo && (
        <div className="mb-2 text-xs flex flex-wrap gap-x-4 gap-y-1 rounded-btn" style={{ color: '#1a2e22', padding: '6px 10px', background: '#f1faf7', border: '1px solid #e2eee8' }}>
          {[['Č. dokladu', ocrInfo.number], ['Částka', ocrInfo.amount != null ? `${Number(ocrInfo.amount).toLocaleString('cs-CZ')} Kč` : null], ['Splatnost', ocrInfo.due], ['Vystaveno', ocrInfo.issue], ['VS', ocrInfo.vs], ['IČO', ocrInfo.ico], ['Č. účtu', ocrInfo.bank], ['Platba', ocrInfo.pay]]
            .filter(([, v]) => v).map(([k, v]) => <span key={k}><b>{k}:</b> {v}</span>)}
        </div>
      )}
      <div className="text-xs mb-2" style={{ color: '#1a2e22', opacity: 0.6 }}>
        📷 Vyfoť fakturu/dodací list → AI ji přečte (a přeloží, když je cizojazyčná): <b>založí finanční událost</b> (→ po schválení faktura + majetek/materiál) a vypíše položky. Zkontroluj typ/velikost nebo kategorii (SKU) a počet → <b>Naskladnit</b> přidá zboží rovnou na sklad.
      </div>

      {lines.length === 0 ? <div className="py-8 text-center text-sm" style={{ color: '#1a2e22', opacity: 0.5 }}>Vyber doklad nebo přidej řádek.</div>
        : (
          <div className="flex flex-col gap-2">
            {lines.map((l, i) => (
              <div key={i} className="flex items-center gap-2 flex-wrap rounded-btn" style={{ padding: '8px 10px', background: '#f9fdfb', border: '1px solid #e2eee8' }}>
                <input value={l.name} onChange={e => upd(i, { name: e.target.value })} placeholder="Název položky" className="rounded-btn text-sm outline-none" style={{ padding: '5px 8px', background: '#fff', border: '1px solid #d4e8e0', flex: '1 1 160px', minWidth: 120 }} />
                <select value={l.cat} onChange={e => upd(i, { cat: e.target.value, type: '', size: '' })} className="rounded-btn text-xs outline-none" style={{ padding: '5px 6px', background: '#fff', border: '1px solid #d4e8e0', maxWidth: 230 }}>
                  {ITEM_CATS.map(c => <option key={c.key} value={c.key}>{c.label}</option>)}
                </select>
                {catDef(l.cat).sized ? (
                  <>
                    <select value={l.type} onChange={e => upd(i, { type: e.target.value, size: '' })} className="rounded-btn text-xs outline-none" style={{ padding: '5px 6px', background: '#fff', border: '1px solid #d4e8e0' }}>
                      <option value="">typ</option>{physicalTypes(accTypes).map(t => <option key={t.key} value={t.key}>{t.label}</option>)}
                    </select>
                    <select value={l.size} onChange={e => upd(i, { size: e.target.value })} className="rounded-btn text-xs outline-none" style={{ padding: '5px 6px', background: '#fff', border: '1px solid #d4e8e0' }}>
                      <option value="">vel.</option>{(accTypes.find(t => t.key === l.type)?.sizes || []).map(s => <option key={s} value={s}>{s}</option>)}
                    </select>
                  </>
                ) : catDef(l.cat).asset ? null : (
                  <input value={l.slug} onChange={e => upd(i, { slug: e.target.value })} placeholder="název (kufr-givi-46l)" className="rounded-btn text-xs outline-none" style={{ padding: '5px 8px', background: '#fff', border: '1px solid #d4e8e0', width: 150 }} />
                )}
                <input type="number" min={1} value={l.qty} onChange={e => upd(i, { qty: e.target.value })} title="Počet" className="rounded-btn text-sm outline-none w-16" style={{ padding: '5px 8px', background: '#fff', border: '1px solid #d4e8e0' }} />
                <input type="number" min={0} value={l.unit_price} onChange={e => upd(i, { unit_price: e.target.value })} title="Cena/ks (CZK)" className="rounded-btn text-sm outline-none w-20" style={{ padding: '5px 8px', background: '#fff', border: '1px solid #d4e8e0' }} />
                <input value={l.color || ''} onChange={e => upd(i, { color: e.target.value })} placeholder="barva" title="Barva (zvlášť, nepatří do velikosti)" className="rounded-btn text-xs outline-none" style={{ padding: '5px 8px', background: '#fff', border: '1px solid #d4e8e0', width: 72 }} />
                {catDef(l.cat).asset
                  ? <span className="text-xs font-mono" style={{ color: '#64748b', minWidth: 90 }} title="Dlouhodobý majetek se nenaskladňuje, eviduje se ve financích">jen finance</span>
                  : <span className="text-xs font-mono" style={{ color: lineSku(l) ? '#16a34a' : '#dc2626', minWidth: 90 }}>{lineSku(l) || 'chybí SKU'}</span>}
                <button onClick={() => setLines(ls => ls.filter((_, j) => j !== i))} className="text-xs font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#dc2626' }}>✕</button>
              </div>
            ))}
          </div>
        )}
      {lines.length > 0 && (
        <div className="flex justify-end items-center gap-3 mt-4">
          <button onClick={discard} disabled={busy} className="text-sm font-bold cursor-pointer rounded-btn" style={{ padding: '9px 16px', border: '1px solid #dc2626', background: '#fff', color: '#dc2626', opacity: busy ? 0.5 : 1 }}>Zahodit</button>
          <button onClick={stockAll} disabled={busy} className="text-sm font-bold cursor-pointer rounded-btn" style={{ padding: '9px 18px', border: 'none', background: '#1a2e22', color: '#74FB71', opacity: busy ? 0.5 : 1 }}>{busy ? 'Ukládám…' : (ocrInfo?.isProforma ? 'Uložit doklad (jen finance)' : `Uložit (${lines.filter(l => lineSku(l) && Number(l.qty) > 0).length})`)}</button>
        </div>
      )}
    </Card>
  )
}

// ─── Číselník SKU (autoritativní seznam položek) ────────────────────
function CatalogTab() {
  const [rows, setRows] = useState([])
  const [accTypes, setAccTypes] = useState([])
  const [q, setQ] = useState('')
  const [cat, setCat] = useState('')
  const [loading, setLoading] = useState(true)
  const [add, setAdd] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase.from('sku_catalog').select('*').order('category').order('sku')
    setRows(error ? [] : (data || []))
    setLoading(false)
  }, [])
  useEffect(() => { load(); loadAccessoryTypes().then(setAccTypes) }, [load])

  const filtered = rows.filter(r =>
    (!cat || r.category === cat) &&
    (!q || r.sku.includes(q.toLowerCase()) || (r.name || '').toLowerCase().includes(q.toLowerCase()) || (r.aliases || []).join(' ').toLowerCase().includes(q.toLowerCase())))

  async function del(id) { if (!confirm('Smazat položku z číselníku?')) return; await supabase.from('sku_catalog').delete().eq('id', id); load() }

  return (
    <Card>
      <div className="flex items-center gap-2 mb-3 flex-wrap">
        <input value={q} onChange={e => setQ(e.target.value)} placeholder="Hledat SKU / název / alias…"
          className="rounded-btn text-sm outline-none" style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', minWidth: 220 }} />
        <select value={cat} onChange={e => setCat(e.target.value)} className="rounded-btn text-sm outline-none" style={{ padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">Vše</option>
          {['prislusenstvi', 'dily', 'material', 'zbozi', 'spotrebni'].map(c => <option key={c} value={c}>{c}</option>)}
        </select>
        <span className="text-sm" style={{ color: '#1a2e22', opacity: 0.6 }}>{filtered.length} položek</span>
        <span className="ml-auto flex items-center gap-2">
          <SkuConventionInfo />
          <button onClick={() => setAdd(true)} className="text-sm font-bold cursor-pointer rounded-btn" style={{ padding: '7px 14px', border: 'none', background: '#1a2e22', color: '#74FB71' }}>+ Položka</button>
        </span>
      </div>
      <div className="text-xs mb-2" style={{ color: '#1a2e22', opacity: 0.6 }}>
        Autoritativní seznam SKU. AI při scanu navrhuje SKU dle konvence a snaží se trefit tento číselník. Aliasy = cizojazyčné/alternativní názvy pro lepší rozpoznání.
      </div>
      {loading ? <div className="py-8 text-center text-sm" style={{ opacity: 0.5 }}>Načítám…</div>
        : filtered.length === 0 ? <div className="py-8 text-center text-sm" style={{ opacity: 0.5 }}>Žádné položky. Nasaď SQL `sku_catalog` + seed, nebo přidej položku.</div>
        : (
          <div className="overflow-x-auto">
            <table className="text-sm w-full" style={{ borderCollapse: 'collapse' }}>
              <thead><tr style={{ borderBottom: '1px solid #d4e8e0' }}>
                {['SKU', 'Název', 'Kategorie', 'Aliasy', ''].map(h => <th key={h} className="text-left text-xs font-extrabold uppercase" style={{ padding: '6px 8px', color: '#1a2e22' }}>{h}</th>)}
              </tr></thead>
              <tbody>
                {filtered.map(r => (
                  <tr key={r.id} style={{ borderBottom: '1px solid #eef5f1' }}>
                    <td style={{ padding: '5px 8px' }}><SkuTag sku={r.sku} /></td>
                    <td style={{ padding: '5px 8px', color: '#0f1a14' }}>{r.name}</td>
                    <td style={{ padding: '5px 8px', color: '#1a2e22' }}>{r.category}</td>
                    <td style={{ padding: '5px 8px', color: '#1a2e22', opacity: 0.7, fontSize: 12 }}>{(r.aliases || []).join(', ')}</td>
                    <td style={{ padding: '5px 8px' }}><button onClick={() => del(r.id)} className="text-xs font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#dc2626' }}>✕</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      {add && <CatalogAddModal accTypes={accTypes} onClose={() => setAdd(false)} onSaved={() => { setAdd(false); load() }} />}
    </Card>
  )
}

function CatalogAddModal({ accTypes, onClose, onSaved }) {
  const [cat, setCat] = useState('zbozi')
  const [type, setType] = useState(''); const [size, setSize] = useState('')
  const [slug, setSlug] = useState(''); const [name, setName] = useState('')
  const [aliases, setAliases] = useState(''); const [busy, setBusy] = useState(false); const [err, setErr] = useState(null)

  const isAcc = cat === 'prislusenstvi'
  const sizes = accTypes.find(t => t.key === type)?.sizes || []
  const sku = isAcc ? (type && size ? accSku(type, size) : '') : (slug ? buildSku(cat, slug) : '')

  async function save() {
    setErr(null)
    if (!sku) { setErr('Vyplň typ+velikost nebo název pro SKU.'); return }
    setBusy(true)
    const payload = {
      sku, category: cat,
      name: name || (isAcc ? `${accTypes.find(t => t.key === type)?.label || type} ${size}` : slug),
      type: isAcc ? type : null, size: isAcc ? size : null,
      aliases: aliases.split(',').map(s => s.trim()).filter(Boolean),
      is_consumable: cat === 'spotrebni' || !!accTypes.find(t => t.key === type)?.is_consumable,
    }
    const { error } = await supabase.from('sku_catalog').insert(payload)
    setBusy(false)
    if (error) { setErr(error.message); return }
    onSaved()
  }

  const F = ({ label, children }) => <div className="flex flex-col gap-1"><span className="text-xs font-extrabold uppercase" style={{ color: '#1a2e22' }}>{label}</span>{children}</div>
  const inp = { padding: '7px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 10, outline: 'none', fontSize: 14 }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,.5)' }} onClick={onClose}>
      <div className="rounded-card" style={{ background: '#fff', padding: 20, width: 'min(94vw, 440px)' }} onClick={e => e.stopPropagation()}>
        <div className="text-base font-black mb-3" style={{ color: '#0f1a14' }}>Nová položka číselníku</div>
        <div className="flex flex-col gap-3">
          <F label="Kategorie">
            <select value={cat} onChange={e => setCat(e.target.value)} style={inp}>
              {[['prislusenstvi', 'Příslušenství (gear)'], ['zbozi', 'Zboží (půjčovní)'], ['spotrebni', 'Spotřební'], ['material', 'Materiál'], ['dily', 'Náhradní díl']].map(([k, l]) => <option key={k} value={k}>{l}</option>)}
            </select>
          </F>
          {isAcc ? (
            <div className="flex gap-3">
              <F label="Typ"><select value={type} onChange={e => { setType(e.target.value); setSize('') }} style={inp}><option value="">—</option>{physicalTypes(accTypes).map(t => <option key={t.key} value={t.key}>{t.label}</option>)}</select></F>
              <F label="Velikost"><select value={size} onChange={e => setSize(e.target.value)} style={inp}><option value="">—</option>{sizes.map(s => <option key={s} value={s}>{s}</option>)}</select></F>
            </div>
          ) : (
            <F label="Název pro SKU (slug)"><input value={slug} onChange={e => setSlug(e.target.value)} placeholder="kufr-givi-46l" style={inp} /></F>
          )}
          <F label="Název položky"><input value={name} onChange={e => setName(e.target.value)} placeholder="(volitelné — doplní se z typu/slugu)" style={inp} /></F>
          <F label="Aliasy (čárkou) — cizojazyčné/alt názvy"><input value={aliases} onChange={e => setAliases(e.target.value)} placeholder="pantalon, hose, trousers" style={inp} /></F>
          <div className="text-sm font-mono" style={{ color: sku ? '#16a34a' : '#dc2626' }}>{sku || 'chybí SKU'}</div>
          {err && <div className="text-sm" style={{ color: '#dc2626' }}>{err}</div>}
        </div>
        <div className="flex justify-end gap-3 mt-4">
          <button onClick={onClose} className="text-sm font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#64748b' }}>Zrušit</button>
          <button onClick={save} disabled={busy || !sku} className="text-sm font-bold cursor-pointer rounded-btn" style={{ padding: '8px 16px', border: 'none', background: '#1a2e22', color: '#74FB71', opacity: (busy || !sku) ? 0.5 : 1 }}>{busy ? 'Ukládám…' : 'Přidat'}</button>
        </div>
      </div>
    </div>
  )
}
