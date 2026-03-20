import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'
import { useDebugMode } from '../../hooks/useDebugMode'

const PER_PAGE = 25
const CATEGORIES = [
  { value: 'material', label: 'Material' },
  { value: 'inventory', label: 'Drobny majetek' },
  { value: 'supplies', label: 'Zasoby' },
  { value: 'receivables', label: 'Pohledavky' },
  { value: 'cash', label: 'Penize' },
  { value: 'bank', label: 'Bankovni ucet' },
  { value: 'prepaid', label: 'Naklady pristich obdobi' },
]

export default function ShortTermAssetsTab() {
  const debugMode = useDebugMode()
  const [assets, setAssets] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [detail, setDetail] = useState(null)
  const [summary, setSummary] = useState({ total: 0, byCategory: {} })

  useEffect(() => { load() }, [page])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const { data, count, error: err } = await debugAction('short_term_assets.list', 'ShortTermAssetsTab', () =>
        supabase.from('acc_short_term_assets').select('*', { count: 'exact' })
          .order('acquired_date', { ascending: false })
          .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      )
      if (err) throw err
      setAssets(data || [])
      setTotal(count || 0)

      // Load summary
      const { data: all } = await supabase.from('acc_short_term_assets').select('category, current_value, status')
        .eq('status', 'active')
      const byCategory = {}
      let totalVal = 0
      for (const a of (all || [])) {
        const val = a.current_value || 0
        totalVal += val
        byCategory[a.category] = (byCategory[a.category] || 0) + val
      }
      setSummary({ total: totalVal, byCategory })
    } catch (e) {
      debugError('ShortTermAssetsTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function dispose(id) {
    await supabase.from('acc_short_term_assets').update({ status: 'disposed', disposed_date: new Date().toISOString().slice(0, 10) }).eq('id', id)
    await load()
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kc'
  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <Button green onClick={() => setShowAdd(true)}>+ Novy kratkodoby majetek</Button>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Summary */}
      <div className="grid grid-cols-4 gap-3 mb-4">
        <MiniStat label="Kratkodoby majetek celkem" value={fmt(summary.total)} color="#1a2e22" />
        {Object.entries(summary.byCategory).slice(0, 3).map(([cat, val]) => (
          <MiniStat key={cat} label={CATEGORIES.find(c => c.value === cat)?.label || cat} value={fmt(val)} color="#2563eb" />
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Nazev</TH><TH>Kategorie</TH><TH>Porizovaci cena</TH><TH>Aktualni hodnota</TH>
                <TH>Datum porizeni</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {assets.map(a => (
                <TRow key={a.id}>
                  <TD bold>{a.name}</TD>
                  <TD>{CATEGORIES.find(c => c.value === a.category)?.label || a.category}</TD>
                  <TD>{fmt(a.purchase_price)}</TD>
                  <TD bold color="#1a8a18">{fmt(a.current_value)}</TD>
                  <TD>{a.acquired_date ? new Date(a.acquired_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>
                    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                      style={{ padding: '4px 10px', background: a.status === 'active' ? '#dcfce7' : '#fee2e2', color: a.status === 'active' ? '#1a8a18' : '#dc2626' }}>
                      {a.status === 'active' ? 'Aktivni' : a.status === 'disposed' ? 'Vyrazeno' : a.status}
                    </span>
                  </TD>
                  <TD>
                    <div className="flex gap-1">
                      <button onClick={() => setDetail(a)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#2563eb' }}>Detail</button>
                      {a.status === 'active' && (
                        <button onClick={() => dispose(a.id)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#dc2626' }}>Vyradit</button>
                      )}
                    </div>
                  </TD>
                </TRow>
              ))}
              {assets.length === 0 && <TRow><TD>Zadny kratkodoby majetek</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddAssetModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
      {detail && (
        <Modal open title={`Majetek: ${detail.name}`} onClose={() => setDetail(null)}>
          <div className="grid grid-cols-2 gap-4">
            <DetailRow label="Nazev" value={detail.name} />
            <DetailRow label="Kategorie" value={CATEGORIES.find(c => c.value === detail.category)?.label || detail.category} />
            <DetailRow label="Porizovaci cena" value={fmt(detail.purchase_price)} />
            <DetailRow label="Aktualni hodnota" value={fmt(detail.current_value)} />
            <DetailRow label="Datum porizeni" value={detail.acquired_date ? new Date(detail.acquired_date).toLocaleDateString('cs-CZ') : '—'} />
            <DetailRow label="Stav" value={detail.status === 'active' ? 'Aktivni' : 'Vyrazeno'} />
            {detail.description && <div className="col-span-2"><DetailRow label="Popis" value={detail.description} /></div>}
            {detail.invoice_number && <DetailRow label="Cislo faktury" value={detail.invoice_number} />}
            {detail.supplier && <DetailRow label="Dodavatel" value={detail.supplier} />}
          </div>
          <div className="flex justify-end mt-5"><Button onClick={() => setDetail(null)}>Zavrit</Button></div>
        </Modal>
      )}
    </div>
  )
}

function AddAssetModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ name: '', category: 'inventory', purchase_price: '', acquired_date: new Date().toISOString().slice(0, 10), description: '', invoice_number: '', supplier: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const price = Number(form.purchase_price) || 0
      const { error } = await supabase.from('acc_short_term_assets').insert({
        name: form.name,
        category: form.category,
        purchase_price: price,
        current_value: price,
        acquired_date: form.acquired_date,
        description: form.description || null,
        invoice_number: form.invoice_number || null,
        supplier: form.supplier || null,
        status: 'active',
      })
      if (error) throw error

      // Auto accounting entry
      await supabase.from('accounting_entries').insert({
        type: 'expense',
        amount: price,
        description: `Porizeni: ${form.name}`,
        category: 'kratkodoby_majetek',
        date: form.acquired_date,
      })

      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Novy kratkodoby majetek" onClose={onClose}>
      <div className="space-y-3">
        <div><Label>Nazev</Label><input type="text" value={form.name} onChange={e => set('name', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Kategorie</Label>
          <select value={form.category} onChange={e => set('category', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </div>
        <div><Label>Porizovaci cena (Kc)</Label><input type="number" value={form.purchase_price} onChange={e => set('purchase_price', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Datum porizeni</Label><input type="date" value={form.acquired_date} onChange={e => set('acquired_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Dodavatel</Label><input type="text" value={form.supplier} onChange={e => set('supplier', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Cislo faktury</Label><input type="text" value={form.invoice_number} onChange={e => set('invoice_number', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Popis</Label><textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60 }} /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.name || !form.purchase_price}>{saving ? 'Ukladam...' : 'Ulozit'}</Button>
      </div>
    </Modal>
  )
}

function DetailRow({ label, value }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-semibold" style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
    </div>
  )
}

function MiniStat({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
