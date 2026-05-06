import { useState, useEffect } from 'react'
import BulkActionsBar, { SelectAllCheckbox, RowCheckbox } from '../components/ui/BulkActionsBar'
import { exportToCsv, bulkDelete } from '../lib/bulkActions'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Modal from '../components/ui/Modal'

const PER_PAGE = 25

export default function Inventory() {
  const debugMode = useDebugMode()
  const navigate = useNavigate()
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = { search: '', category: '', stocks: [] }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_inventory_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  const [showAdd, setShowAdd] = useState(false)
  const [selectedIds, setSelectedIds] = useState(new Set())
  const [issueItem, setIssueItem] = useState(null) // sklad → pobočka modal

  useEffect(() => { localStorage.setItem('velin_inventory_filters', JSON.stringify(filters)) }, [filters])

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase
        .from('inventory')
        .select('*, suppliers(name)', { count: 'exact' })

      if (filters.search) query = query.or(`name.ilike.%${filters.search}%,sku.ilike.%${filters.search}%`)
      if (filters.category) query = query.eq('category', filters.category)

      query = query.order('name').range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await query
      if (err) throw err

      let filtered = data || []
      if (filters.stocks?.length > 0) {
        if (filters.stocks.includes('low') && !filters.stocks.includes('ok')) filtered = filtered.filter(i => i.stock <= i.min_stock)
        else if (filters.stocks.includes('ok') && !filters.stocks.includes('low')) filtered = filtered.filter(i => i.stock > i.min_stock)
      }

      setItems(filtered)
      setTotal(count || 0)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput
          value={filters.search}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }}
          placeholder="Hledat SKU, název…"
        />
        <CheckboxFilterGroup label="Zásoby" values={filters.stocks || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, stocks: v })) }}
          options={[{ value: 'low', label: 'Nízké zásoby' }, { value: 'ok', label: 'Dostatečné' }]} />
        {(filters.search || filters.category || (filters.stocks?.length > 0)) && (
          <button onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_inventory_filters') }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
            Reset
          </button>
        )}
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová položka</Button>
        </div>
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA Inventory</strong><br/>
        <div>items: {items.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: search="{filters.search}", category={filters.category || 'vše'}, stocks=[{(filters.stocks || []).join(', ') || 'vše'}]</div>
        <div>lowStock: {items.filter(i => i.stock <= i.min_stock).length} položek pod minimem</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <BulkActionsBar count={selectedIds.size} onClear={() => setSelectedIds(new Set())} actions={[
            { label: 'Export CSV', icon: '⬇', onClick: () => exportToCsv('inventory', [
              { key: 'sku', label: 'SKU' }, { key: 'name', label: 'Název' },
              { key: 'category', label: 'Kategorie' }, { key: 'stock', label: 'Sklad' },
              { key: 'min_stock', label: 'Min' }, { key: 'unit_price', label: 'Cena/ks' },
              { key: 'suppliers', label: 'Dodavatel', format: (_, r) => r.suppliers?.name || '' },
            ], items.filter(i => selectedIds.has(i.id))) },
            { label: 'Smazat', icon: '🗑', danger: true, confirm: 'Trvale smazat {count} skladových položek?', onClick: async () => { await bulkDelete('inventory', [...selectedIds], 'inventory_bulk_deleted'); setSelectedIds(new Set()); load() } },
          ]} />
          <Table>
            <thead>
              <TRow header>
                <TH><SelectAllCheckbox items={items} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TH>
                <TH>SKU</TH><TH>Název</TH><TH>Kategorie</TH><TH>Sklad</TH>
                <TH>Minimum</TH><TH>Stav</TH><TH>Cena/ks</TH><TH>Dodavatel</TH><TH></TH>
              </TRow>
            </thead>
            <tbody>
              {items.map(item => {
                const isLow = item.stock <= item.min_stock
                const isAcc = item.category === 'prislusenstvi'
                return (
                  <tr
                    key={item.id}
                    onClick={() => navigate(`/sklady/${item.id}`)}
                    className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                    style={{ borderBottom: '1px solid #d4e8e0', background: selectedIds.has(item.id) ? '#fef9c3' : isLow ? '#fff5f5' : 'transparent' }}
                  >
                    <TD><RowCheckbox id={item.id} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TD>
                    <TD mono bold>{item.sku || '—'}</TD>
                    <TD bold>{item.name}</TD>
                    <TD>{item.category || '—'}</TD>
                    <TD bold color={isLow ? '#dc2626' : '#0f1a14'}>{item.stock ?? 0}</TD>
                    <TD>{item.min_stock ?? 0}</TD>
                    <TD>
                      <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                        style={{ padding: '4px 10px', background: isLow ? '#fee2e2' : '#dcfce7', color: isLow ? '#dc2626' : '#1a8a18' }}>
                        {isLow ? 'Nízké' : 'OK'}
                      </span>
                    </TD>
                    <TD>{item.unit_price ? fmt(item.unit_price) : '—'}</TD>
                    <TD>{item.suppliers?.name || '—'}</TD>
                    <TD>
                      {isAcc && item.stock > 0 && (
                        <button
                          onClick={(e) => { e.stopPropagation(); setIssueItem(item) }}
                          className="rounded-btn text-xs font-bold cursor-pointer border-none"
                          style={{ padding: '4px 10px', background: '#1a2e22', color: '#74FB71' }}
                          title="Vydat ze skladu na pobočku"
                        >
                          → Pobočka
                        </button>
                      )}
                    </TD>
                  </tr>
                )
              })}
              {items.length === 0 && <TRow><TD>Žádné položky</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddItemModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
      {issueItem && <IssueToBranchModal item={issueItem} onClose={() => setIssueItem(null)} onSaved={() => { setIssueItem(null); load() }} />}
    </div>
  )
}

function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => {
    if (values.includes(val)) onChange(values.filter(v => v !== val))
    else onChange([...values, val])
  }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn"
      style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer"
          style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)}
            className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}

const INVENTORY_CATEGORIES = [
  { value: 'material', label: 'Materiál' },
  { value: 'inventory', label: 'Zboží' },
  { value: 'supplies', label: 'Spotřební materiál' },
  { value: 'prislusenstvi', label: 'Příslušenství' },
]

function AddItemModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ name: '', sku: '', category: 'material', stock: 0, min_stock: 0, unit_price: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  // SKU builder pro kategorii „prislusenstvi" — místo volného textu nabízíme
  // dropdowny typ + velikost z `accessory_types`. SKU se skládá automaticky
  // jako `prislusenstvi-{type}-{size}`. Manuální mód jako únik pro nestandardní položky.
  const [accTypes, setAccTypes] = useState([])
  const [skuType, setSkuType] = useState('')
  const [skuSize, setSkuSize] = useState('')
  const [skuManual, setSkuManual] = useState(false)

  useEffect(() => {
    supabase.from('accessory_types')
      .select('id, key, label, sizes, is_consumable, audience, sort_order')
      .eq('is_active', true)
      .order('sort_order')
      .then(({ data }) => setAccTypes(data || []))
  }, [])

  const isAcc = form.category === 'prislusenstvi'
  const selectedType = accTypes.find(t => t.key === skuType)
  const sizeOptions = selectedType?.sizes || []

  // Auto-build SKU + name z dropdownů (jen v auto módu pro prislusenstvi)
  useEffect(() => {
    if (!isAcc || skuManual) return
    if (skuType && skuSize){
      const sku = `prislusenstvi-${skuType}-${skuSize}`
      const name = `${selectedType?.label || skuType} ${skuSize}`
      setForm(f => ({ ...f, sku, name }))
    }
  }, [isAcc, skuManual, skuType, skuSize, selectedType])

  // Při přepnutí kategorie shoď SKU builder state
  useEffect(() => {
    if (!isAcc){ setSkuType(''); setSkuSize(''); setSkuManual(false) }
  }, [isAcc])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      await debugAction('handleSave', 'AddItemModal', async () => {
        const { error } = await supabase.from('inventory').insert({
          ...form, stock: Number(form.stock) || 0, min_stock: Number(form.min_stock) || 0,
          unit_price: Number(form.unit_price) || 0,
        })
        if (error) throw error
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'inventory_item_created', details: {} })
        onSaved()
      }, form)
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  const skuValid = !isAcc || skuManual || (skuType && skuSize)
  const canSave = !saving && form.name && form.sku && skuValid

  return (
    <Modal open title="Nová skladová položka" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Kategorie</label>
          <select value={form.category} onChange={e => set('category', e.target.value)}
            className="w-full rounded-btn text-sm outline-none cursor-pointer"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
            {INVENTORY_CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </div>
        <FormField label="Cena/ks (Kč)" value={form.unit_price} onChange={v => set('unit_price', v)} type="number" />

        {isAcc ? (
          <>
            <div>
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Typ příslušenství</label>
              <select value={skuType} onChange={e => { setSkuType(e.target.value); setSkuSize('') }}
                disabled={skuManual}
                className="w-full rounded-btn text-sm outline-none cursor-pointer"
                style={{ padding: '8px 12px', background: skuManual ? '#f5f5f5' : '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
                <option value="">— vyber typ —</option>
                {accTypes.map(t => (
                  <option key={t.id} value={t.key}>{t.label}{t.is_consumable ? ' (spotřební)' : ''}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Velikost</label>
              <select value={skuSize} onChange={e => setSkuSize(e.target.value)}
                disabled={skuManual || !selectedType}
                className="w-full rounded-btn text-sm outline-none cursor-pointer"
                style={{ padding: '8px 12px', background: (skuManual || !selectedType) ? '#f5f5f5' : '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
                <option value="">— vyber velikost —</option>
                {sizeOptions.map(s => <option key={s} value={s}>{s}</option>)}
              </select>
            </div>
          </>
        ) : null}

        <div className="col-span-2">
          <div className="flex items-center justify-between mb-1">
            <label className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Název</label>
            {isAcc && (
              <label className="text-xs font-bold cursor-pointer flex items-center gap-1" style={{ color: '#1a2e22' }}>
                <input type="checkbox" checked={skuManual} onChange={e => setSkuManual(e.target.checked)} />
                Manuální SKU + název
              </label>
            )}
          </div>
          <input type="text" value={form.name} onChange={e => set('name', e.target.value)}
            disabled={isAcc && !skuManual && skuType && skuSize}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: (isAcc && !skuManual && skuType && skuSize) ? '#f5f5f5' : '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
        </div>
        <div className="col-span-2">
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>SKU</label>
          <input type="text" value={form.sku} onChange={e => set('sku', e.target.value)}
            disabled={isAcc && !skuManual}
            className="w-full rounded-btn text-sm outline-none font-mono"
            style={{ padding: '8px 12px', background: (isAcc && !skuManual) ? '#f5f5f5' : '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
          {isAcc && !skuManual && (
            <div className="text-xs mt-1" style={{ color: '#6b8f7b' }}>
              SKU se skládá automaticky: <span className="font-mono">prislusenstvi-{skuType || '<typ>'}-{skuSize || '<vel>'}</span>
            </div>
          )}
        </div>
        <FormField label="Počáteční stav" value={form.stock} onChange={v => set('stock', v)} type="number" />
        <FormField label="Minimum" value={form.min_stock} onChange={v => set('min_stock', v)} type="number" />
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={!canSave}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}

function FormField({ label, value, onChange, type = 'text' }) {
  return (
    <div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
      <input type={type} value={value} onChange={e => onChange(e.target.value)}
        className="w-full rounded-btn text-sm outline-none"
        style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}

// ─── Issue to Branch Modal ────────────────────────────────────────────
// Vydat ze skladu na pobočku: parsuje SKU `prislusenstvi-{type}-{size}`,
// odečte stock z inventory + upsertuje branch_accessories (přičítá ke
// stávajícímu množství). Loguje pohyb do inventory_movements.
function IssueToBranchModal({ item, onClose, onSaved }) {
  const [branches, setBranches] = useState([])
  const [branchId, setBranchId] = useState('')
  const [qty, setQty] = useState(1)
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  // SKU parser: prislusenstvi-{type}-{size}, kde size může obsahovat pomlčky/číslice
  const parsed = (() => {
    if (!item.sku) return null
    const m = /^prislusenstvi-([a-z0-9_]+)-(.+)$/i.exec(item.sku)
    if (!m) return null
    return { type: m[1], size: m[2] }
  })()

  useEffect(() => {
    supabase.from('branches').select('id, name, branch_code, is_open').order('name')
      .then(({ data }) => {
        const list = data || []
        setBranches(list)
        if (list.length === 1) setBranchId(list[0].id)
      })
  }, [])

  async function handleIssue() {
    setErr(null)
    if (!parsed) { setErr('SKU nemá tvar `prislusenstvi-{typ}-{velikost}`. Opravte SKU nebo použijte ruční přidání v pobočce.'); return }
    if (!branchId) { setErr('Vyberte pobočku.'); return }
    const n = Math.max(1, parseInt(qty, 10) || 0)
    if (n <= 0) { setErr('Zadejte počet kusů.'); return }
    if (n > (item.stock || 0)) { setErr(`Na skladě je jen ${item.stock || 0} ks.`); return }
    setSaving(true)
    try {
      const branchName = branches.find(b => b.id === branchId)?.name || ''
      const { data: { user } } = await supabase.auth.getUser()

      // 1) Odečíst ze skladu (inventory.stock) + log pohybu
      const { error: invErr } = await supabase.from('inventory')
        .update({ stock: (item.stock || 0) - n }).eq('id', item.id)
      if (invErr) throw invErr
      await supabase.from('inventory_movements').insert({
        item_id: item.id, type: 'issue', quantity: n,
        note: `Výdej na pobočku ${branchName} (${parsed.type} ${parsed.size})`,
        performed_by: user?.id,
      })

      // 2) Přičíst do branch_accessories (upsert: pokud řádek existuje, sečíst)
      const { data: existing } = await supabase.from('branch_accessories')
        .select('id, quantity')
        .eq('branch_id', branchId)
        .eq('type', parsed.type)
        .eq('size', parsed.size)
        .maybeSingle()
      if (existing) {
        const { error: upErr } = await supabase.from('branch_accessories')
          .update({ quantity: (existing.quantity || 0) + n })
          .eq('id', existing.id)
        if (upErr) throw upErr
      } else {
        const { error: insErr } = await supabase.from('branch_accessories').insert({
          branch_id: branchId, type: parsed.type, size: parsed.size, quantity: n,
        })
        if (insErr) throw insErr
      }

      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'inventory_issued_to_branch',
        details: { sku: item.sku, branch_id: branchId, branch_name: branchName, qty: n },
      })
      onSaved()
    } catch (e) {
      setErr(e.message || String(e))
    } finally { setSaving(false) }
  }

  return (
    <Modal open title={`Vydat na pobočku — ${item.name}`} onClose={onClose}>
      <div className="space-y-3">
        <div className="text-sm" style={{ color: '#1a2e22' }}>
          <div>SKU: <span className="font-mono font-bold">{item.sku || '—'}</span></div>
          {parsed ? (
            <div>Typ: <strong>{parsed.type}</strong> · Velikost: <strong>{parsed.size}</strong></div>
          ) : (
            <div className="text-xs" style={{ color: '#dc2626' }}>
              ⚠ SKU nemá očekávaný tvar `prislusenstvi-typ-velikost` — výdej skrze tento dialog nebude fungovat.
            </div>
          )}
          <div>Sklad: <strong>{item.stock ?? 0} ks</strong></div>
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Pobočka</label>
          <select value={branchId} onChange={e => setBranchId(e.target.value)}
            className="w-full rounded-btn text-sm outline-none cursor-pointer"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
            <option value="">— vyber pobočku —</option>
            {branches.map(b => (
              <option key={b.id} value={b.id}>{b.name}{b.branch_code ? ` (${b.branch_code})` : ''}{!b.is_open ? ' — zavřená' : ''}</option>
            ))}
          </select>
        </div>
        <FormField label="Počet kusů" value={qty} onChange={setQty} type="number" />
        {err && <p className="text-sm" style={{ color: '#dc2626' }}>{err}</p>}
        <div className="flex justify-end gap-3 pt-2">
          <Button onClick={onClose}>Zrušit</Button>
          <Button green onClick={handleIssue} disabled={saving || !parsed || !branchId}>
            {saving ? 'Vydávám…' : 'Vydat na pobočku'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}
