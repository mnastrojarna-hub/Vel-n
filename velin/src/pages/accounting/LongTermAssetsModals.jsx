import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'

const CATEGORIES = [
  { value: 'vehicles', label: 'Dopravni prostredky' }, { value: 'machinery', label: 'Stroje a pristroje' },
  { value: 'buildings', label: 'Stavby' }, { value: 'land', label: 'Pozemky' },
  { value: 'equipment', label: 'Vybaveni' }, { value: 'intangible', label: 'Nehmotny majetek' },
]

const DEPRECIATION_GROUPS = [
  { value: 1, label: 'Skupina 1 (3 roky)', years: 3, firstYearRate: 20, nextYearRate: 40 },
  { value: 2, label: 'Skupina 2 (5 let)', years: 5, firstYearRate: 11, nextYearRate: 22.25 },
  { value: 3, label: 'Skupina 3 (10 let)', years: 10, firstYearRate: 5.5, nextYearRate: 10.5 },
  { value: 4, label: 'Skupina 4 (20 let)', years: 20, firstYearRate: 2.15, nextYearRate: 5.15 },
  { value: 5, label: 'Skupina 5 (30 let)', years: 30, firstYearRate: 1.4, nextYearRate: 3.4 },
  { value: 6, label: 'Skupina 6 (50 let)', years: 50, firstYearRate: 1.02, nextYearRate: 2.02 },
]

const DEPRECIATION_METHODS = [
  { value: 'linear', label: 'Rovnomerne (linearni)' }, { value: 'accelerated', label: 'Zrychlene' },
]

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) { return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label> }
const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kc'

export function AddAssetModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ name: '', category: 'vehicles', purchase_price: '', acquired_date: new Date().toISOString().slice(0, 10), depreciation_group: 2, depreciation_method: 'linear', description: '', invoice_number: '', supplier: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const price = Number(form.purchase_price) || 0
      const { error } = await supabase.from('acc_long_term_assets').insert({ name: form.name, category: form.category, purchase_price: price, current_value: price, total_depreciated: 0, acquired_date: form.acquired_date, depreciation_group: Number(form.depreciation_group), depreciation_method: form.depreciation_method, description: form.description || null, invoice_number: form.invoice_number || null, supplier: form.supplier || null, status: 'active' })
      if (error) throw error
      await supabase.from('accounting_entries').insert({ type: 'expense', amount: price, description: `Porizeni DM: ${form.name}`, category: 'dlouhodoby_majetek', date: form.acquired_date })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  const selectedGroup = DEPRECIATION_GROUPS.find(g => g.value === Number(form.depreciation_group))

  return (
    <Modal open title="Novy dlouhodoby majetek" onClose={onClose}>
      <div className="space-y-3">
        <div><Label>Nazev</Label><input type="text" value={form.name} onChange={e => set('name', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Kategorie</Label><select value={form.category} onChange={e => set('category', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>{CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}</select></div>
        <div><Label>Porizovaci cena (Kc)</Label><input type="number" value={form.purchase_price} onChange={e => set('purchase_price', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Datum porizeni</Label><input type="date" value={form.acquired_date} onChange={e => set('acquired_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Odpisova skupina</Label><select value={form.depreciation_group} onChange={e => set('depreciation_group', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>{DEPRECIATION_GROUPS.map(g => <option key={g.value} value={g.value}>{g.label}</option>)}</select></div>
        <div><Label>Metoda odpisu</Label><select value={form.depreciation_method} onChange={e => set('depreciation_method', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>{DEPRECIATION_METHODS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}</select></div>
        {selectedGroup && form.purchase_price && <div className="p-3 rounded-lg" style={{ background: '#f0fdf4', border: '1px solid #bbf7d0', fontSize: 12 }}><strong>Nahled odpisu:</strong> {selectedGroup.years} let, 1. rok: {fmt(Math.round(Number(form.purchase_price) * selectedGroup.firstYearRate / 100))}, dalsi roky: {fmt(Math.round(Number(form.purchase_price) * selectedGroup.nextYearRate / 100))}</div>}
        <div><Label>Dodavatel</Label><input type="text" value={form.supplier} onChange={e => set('supplier', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Cislo faktury</Label><input type="text" value={form.invoice_number} onChange={e => set('invoice_number', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Popis</Label><textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60 }} /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5"><Button onClick={onClose}>Zrusit</Button><Button green onClick={handleSave} disabled={saving || !form.name || !form.purchase_price}>{saving ? 'Ukladam...' : 'Ulozit'}</Button></div>
    </Modal>
  )
}

export function AssetDetailModal({ asset, onClose }) {
  const [depEntries, setDepEntries] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('acc_depreciation_entries').select('*').eq('asset_id', asset.id).order('year', { ascending: true }).then(({ data }) => { setDepEntries(data || []); setLoading(false) })
  }, [asset.id])

  const group = DEPRECIATION_GROUPS.find(g => g.value === asset.depreciation_group)
  const pct = asset.purchase_price > 0 ? Math.round(((asset.total_depreciated || 0) / asset.purchase_price) * 100) : 0

  return (
    <Modal open title={`Majetek: ${asset.name}`} onClose={onClose}>
      <div className="grid grid-cols-2 gap-4 mb-4">
        <DetailRow label="Nazev" value={asset.name} />
        <DetailRow label="Kategorie" value={CATEGORIES.find(c => c.value === asset.category)?.label || asset.category} />
        <DetailRow label="Porizovaci cena" value={fmt(asset.purchase_price)} />
        <DetailRow label="Zustat. hodnota" value={fmt(asset.current_value)} />
        <DetailRow label="Odepsano" value={`${fmt(asset.total_depreciated)} (${pct}%)`} />
        <DetailRow label="Odpisova skupina" value={group ? group.label : `Sk. ${asset.depreciation_group}`} />
        <DetailRow label="Metoda" value={asset.depreciation_method === 'linear' ? 'Rovnomerne' : 'Zrychlene'} />
        <DetailRow label="Datum porizeni" value={asset.acquired_date ? new Date(asset.acquired_date).toLocaleDateString('cs-CZ') : '—'} />
      </div>
      <div className="mb-4">
        <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Prubeh odpisovani</div>
        <div style={{ background: '#e5e7eb', borderRadius: 8, height: 20, overflow: 'hidden' }}><div style={{ background: '#74FB71', height: '100%', width: `${pct}%`, transition: 'width 0.3s', borderRadius: 8 }} /></div>
        <div className="text-sm mt-1" style={{ color: '#6b7280' }}>{pct}% odepsano</div>
      </div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Historie odpisu</div>
      {loading ? <div className="py-4 text-center text-sm" style={{ color: '#6b7280' }}>Nacitam...</div> : depEntries.length === 0 ? <div className="py-2 text-sm" style={{ color: '#6b7280' }}>Zadne odpisy</div> : (
        <Table><thead><TRow header><TH>Rok</TH><TH>Cislo</TH><TH>Rocni odpis</TH><TH>Kumulativne</TH><TH>Zbyva</TH></TRow></thead>
          <tbody>{depEntries.map(d => <TRow key={d.id}><TD>{d.year}</TD><TD>{d.year_number}.</TD><TD bold color="#dc2626">{fmt(d.annual_amount)}</TD><TD>{fmt(d.cumulative_amount)}</TD><TD color="#1a8a18">{fmt(d.remaining_value)}</TD></TRow>)}</tbody>
        </Table>
      )}
      <div className="flex justify-end mt-5"><Button onClick={onClose}>Zavrit</Button></div>
    </Modal>
  )
}

function DetailRow({ label, value }) {
  return (<div><div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div><div className="text-sm font-semibold" style={{ color: '#0f1a14' }}>{value ?? '—'}</div></div>)
}
