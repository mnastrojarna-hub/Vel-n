import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

const EXPENSE_CATEGORIES = [
  { value: '', label: '— Vyberte typ nakladu —' },
  { value: 'phm', label: 'PHM' }, { value: 'pojisteni', label: 'Pojisteni' },
  { value: 'servis_opravy', label: 'Servis / Opravy' }, { value: 'najem', label: 'Najem' },
  { value: 'energie', label: 'Energie' }, { value: 'telekomunikace', label: 'Telekomunikace' },
  { value: 'marketing', label: 'Marketing' }, { value: 'kancelar', label: 'Kancelar' },
  { value: 'mzdy', label: 'Mzdy' }, { value: 'dane_odvody', label: 'Dane / Odvody' },
  { value: 'zbozi_eshop', label: 'Zbozi (e-shop)' }, { value: 'material', label: 'Material' },
  { value: 'ostatni_naklady', label: 'Ostatni naklady' },
]
const PAYMENT_OPTIONS = [
  { value: '', label: '— Neurceno —' },
  { value: 'bank_transfer', label: 'Bankovni prevod' },
  { value: 'cash', label: 'Hotovost' }, { value: 'card', label: 'Karta' },
]

function guessExpenseCategory(supplier, notes) {
  const text = ((supplier || '') + ' ' + (notes || '')).toLowerCase()
  const rules = [
    { keywords: ['benzin', 'phm', 'nafta', 'cerpaci', 'shell', 'omv', 'mol', 'orlen', 'eni', 'palivo'], cat: 'phm' },
    { keywords: ['pojist', 'generali', 'allianz', 'kooper', 'ceska_pojistovna', 'uniqa', 'csob poj'], cat: 'pojisteni' },
    { keywords: ['servis', 'oprava', 'udrzba', 'pneu', 'olej', 'filtr', 'brzdov', 'retez', 'moto dil', 'nahradni', 'dily'], cat: 'servis_opravy' },
    { keywords: ['najem', 'pronajem', 'rent', 'nebytov'], cat: 'najem' },
    { keywords: ['elektr', 'plyn', 'voda', 'teplo', 'energie', 'cez', 'eon', 'pre', 'innogy'], cat: 'energie' },
    { keywords: ['telefon', 'mobil', 'internet', 'hosting', 'domena', 'vodafone', 'o2', 't-mobile', 'server'], cat: 'telekomunikace' },
    { keywords: ['reklam', 'market', 'propagac', 'inzer', 'google', 'facebook', 'meta', 'instagram', 'tisk', 'letak'], cat: 'marketing' },
    { keywords: ['kancelar', 'papir', 'toner', 'tisk', 'kancelarsk'], cat: 'kancelar' },
    { keywords: ['mzd', 'plat', 'odmena', 'dpp', 'dpc'], cat: 'mzdy' },
    { keywords: ['dan', 'cssz', 'vzp', 'pojistn', 'finan.urad', 'fu '], cat: 'dane_odvody' },
    { keywords: ['helma', 'rukavice', 'bunda', 'kalhoty', 'boty', 'kukla', 'obleceni', 'vystroj', 'prislusenstvi'], cat: 'zbozi_eshop' },
    { keywords: ['material', 'sroub', 'podlozk', 'hadice'], cat: 'material' },
  ]
  for (const rule of rules) { if (rule.keywords.some(k => text.includes(k))) return rule.cat }
  return 'ostatni_naklady'
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) { return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label> }

export default function AddReceivedModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ number: '', supplier: '', supplier_ico: '', supplier_bank_account: '', variable_symbol: '', total: '', due_date: '', issue_date: '', category: '', payment_method: '', notes: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const [supplierSuggestions, setSupplierSuggestions] = useState([])
  const [aiSuggested, setAiSuggested] = useState(false)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  function autoClassify(supplier, notes) {
    const guess = guessExpenseCategory(supplier, notes)
    if (guess) { setForm(f => ({ ...f, category: guess })); setAiSuggested(true) }
  }

  async function searchSupplier(name) {
    set('supplier', name)
    if (name.length < 2) { setSupplierSuggestions([]); return }
    const { data } = await supabase.from('suppliers').select('name, ico, bank_account, default_category').ilike('name', `%${name}%`).limit(5)
    setSupplierSuggestions(data || [])
    if (!data || data.length === 0) autoClassify(name, form.notes)
  }

  function selectSupplier(s) {
    setForm(f => ({ ...f, supplier: s.name, supplier_ico: s.ico || f.supplier_ico, supplier_bank_account: s.bank_account || f.supplier_bank_account, category: s.default_category || guessExpenseCategory(s.name, f.notes) }))
    setAiSuggested(!s.default_category); setSupplierSuggestions([])
  }

  async function handleSave() {
    if (!form.number || !form.total) return setErr('Vyplnte cislo faktury a castku.')
    if (!form.category) {
      const guess = guessExpenseCategory(form.supplier, form.notes)
      if (guess) { set('category', guess); return setErr('AI navrhl kategorii — zkontrolujte a ulozte znovu.') }
      return setErr('Vyberte typ nakladu.')
    }
    setSaving(true); setErr(null)
    try {
      const { data: inv, error: invErr } = await supabase.from('invoices').insert({
        number: form.number, type: 'received', total: Number(form.total) || 0, subtotal: Number(form.total) || 0, tax_amount: 0,
        issue_date: form.issue_date || new Date().toISOString().slice(0, 10), due_date: form.due_date || null, variable_symbol: form.variable_symbol || null,
        notes: [form.supplier, form.supplier_ico ? `ICO: ${form.supplier_ico}` : null, form.supplier_bank_account ? `Ucet: ${form.supplier_bank_account}` : null, form.category ? `Kategorie: ${form.category}` : null, form.payment_method ? `Platba: ${form.payment_method}` : null, form.notes].filter(Boolean).join('\n'),
        status: 'issued', source: 'manual',
      }).select().single()
      if (invErr) throw invErr
      if (form.supplier) {
        const normalized = form.supplier.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim()
        const { data: existing } = await supabase.from('suppliers').select('id').eq('normalized_name', normalized).limit(1)
        if (!existing || existing.length === 0) { await supabase.from('suppliers').insert({ name: form.supplier, normalized_name: normalized, ico: form.supplier_ico || null, bank_account: form.supplier_bank_account || null, default_category: form.category || null }) }
      }
      await supabase.from('financial_events').insert({ event_type: 'expense', source: 'manual', amount_czk: Number(form.total) || 0, duzp: form.issue_date || new Date().toISOString().slice(0, 10), status: 'enriched', linked_entity_type: 'invoice', linked_entity_id: inv.id, metadata: { supplier_name: form.supplier, supplier_ico: form.supplier_ico, supplier_bank_account: form.supplier_bank_account, invoice_number: form.number, variable_symbol: form.variable_symbol, due_date: form.due_date, payment_method: form.payment_method, ai_classification: { category: form.category } } })
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'received_invoice_created', details: { number: form.number } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nova prijata faktura" onClose={onClose}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div><Label>Cislo faktury *</Label><input value={form.number} onChange={e => set('number', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="FV-2026-0001" /></div>
          <div><Label>Datum vystaveni</Label><input type="date" value={form.issue_date} onChange={e => set('issue_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        </div>
        <div style={{ position: 'relative' }}>
          <Label>Dodavatel *</Label>
          <input value={form.supplier} onChange={e => searchSupplier(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Zacnete psat nazev..." />
          {supplierSuggestions.length > 0 && (
            <div style={{ position: 'absolute', top: '100%', left: 0, right: 0, zIndex: 50, background: '#fff', border: '1px solid #d4e8e0', borderRadius: 8, boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}>
              {supplierSuggestions.map((s, i) => (
                <div key={i} onClick={() => selectSupplier(s)} className="px-3 py-2 text-sm cursor-pointer hover:bg-[#f1faf7]" style={{ borderBottom: i < supplierSuggestions.length - 1 ? '1px solid #f0f0f0' : 'none' }}>
                  <strong>{s.name}</strong>{s.ico ? ` (ICO: ${s.ico})` : ''}
                </div>
              ))}
            </div>
          )}
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div><Label>ICO dodavatele</Label><input value={form.supplier_ico} onChange={e => set('supplier_ico', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
          <div><Label>Bankovni ucet</Label><input value={form.supplier_bank_account} onChange={e => set('supplier_bank_account', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div><Label>Castka (Kc) *</Label><input type="number" value={form.total} onChange={e => set('total', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
          <div><Label>Variabilni symbol</Label><input value={form.variable_symbol} onChange={e => set('variable_symbol', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div><Label>Splatnost</Label><input type="date" value={form.due_date} onChange={e => set('due_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
          <div><Label>Zpusob platby</Label><select value={form.payment_method} onChange={e => set('payment_method', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>{PAYMENT_OPTIONS.map(p => <option key={p.value} value={p.value}>{p.label}</option>)}</select></div>
        </div>
        <div><Label>Typ nakladu * {aiSuggested && <span style={{ color: '#7c3aed', fontWeight: 400, fontSize: 10 }}>(AI navrh)</span>}</Label>
          <select value={form.category} onChange={e => { set('category', e.target.value); setAiSuggested(false) }} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, borderColor: aiSuggested ? '#7c3aed' : '#d4e8e0' }}>
            {EXPENSE_CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </div>
        <div><Label>Poznamka</Label>
          <textarea value={form.notes} onChange={e => { set('notes', e.target.value); if (!form.category || aiSuggested) autoClassify(form.supplier, e.target.value) }} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} placeholder="Popis, za co je faktura..." />
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukladam...' : 'Ulozit'}</Button>
      </div>
    </Modal>
  )
}
