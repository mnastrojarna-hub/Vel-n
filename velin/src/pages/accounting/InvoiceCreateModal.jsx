import { useState, useEffect, useMemo, useRef } from 'react'
import { supabase } from '../../lib/supabase'
import { createInvoice, calculateTotals, renderAndStoreInvoicePdf } from '../../lib/invoiceUtils'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

// Typy dokladů — všechny ruční řady (FV/ZF/DP/KF/Dobropis + e-shop)
const TYPE_OPTIONS = [
  { value: 'issued', label: 'Vystavená (FV)' },
  { value: 'advance', label: 'Zálohová (ZF)' },
  { value: 'payment_receipt', label: 'Doklad k platbě (DP)' },
  { value: 'final', label: 'Konečná (KF)' },
  { value: 'credit_note', label: 'Dobropis (DB)' },
  { value: 'shop_proforma', label: 'Shop zálohová' },
  { value: 'shop_final', label: 'Shop konečná' },
]

// Způsoby platby — hodnoty musí sedět s MANUAL_METHOD_LABELS v invoiceTemplate.js
const PAYMENT_METHODS = [
  { value: '', label: '— Nevyplněno —' },
  { value: 'bank_transfer', label: 'Převodem' },
  { value: 'card', label: 'Kartou' },
  { value: 'cash', label: 'Hotově' },
  { value: 'qr', label: 'QR platba' },
  { value: 'crypto', label: 'Kryptoměna' },
  { value: 'voucher', label: 'Dárkový poukaz' },
]

const REASON_PRESETS = [
  'Oprava poškození', 'Pozdní vrácení', 'Tankování', 'Mytí motorky',
  'Spoluúčast na pojistné události', 'Ztráta klíčů', 'Nadměrný nájezd km',
]

const today = () => new Date().toISOString().slice(0, 10)

export default function InvoiceCreateModal({ onClose, onSaved, prefillBooking }) {
  const [customers, setCustomers] = useState([])
  const [bookings, setBookings] = useState([])
  const [inventory, setInventory] = useState([])
  const [form, setForm] = useState({
    type: 'issued',
    customer_id: '',
    booking_id: prefillBooking || '',
    payment_method: '',
    variable_symbol: '',
    issue_date: today(),
    due_date: '',
    paid_date: '',
    notes: '',
    description: '',
    send_email: true,
  })
  const [items, setItems] = useState([{ description: '', qty: 1, unit_price: 0 }])
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const [showStock, setShowStock] = useState(false)

  useEffect(() => {
    supabase.from('profiles').select('id, full_name, email').order('full_name').then(({ data }) => setCustomers(data || []))
    supabase.from('bookings').select('id, start_date, end_date, total_price, profiles(full_name, email), motorcycles!moto_id(model), sos_incident_id')
      .order('start_date', { ascending: false }).limit(100).then(({ data }) => setBookings(data || []))
    supabase.from('inventory').select('id, name, sku, category, stock, unit_price').order('name').then(({ data }) => setInventory(data || []))
  }, [])

  // Předvyplnění z rezervace
  useEffect(() => {
    if (!form.booking_id) return
    const b = bookings.find(x => x.id === form.booking_id)
    if (!b) return
    if (items.length === 1 && !items[0].description && !items[0].inventory_id) {
      setItems([{ description: `Pronájem ${b.motorcycles?.model || 'motorky'} (${b.start_date} – ${b.end_date})`, qty: 1, unit_price: b.total_price || 0 }])
    }
    if (!form.customer_id && b.profiles) {
      const cust = customers.find(c => c.full_name === b.profiles.full_name)
      if (cust) setForm(f => ({ ...f, customer_id: cust.id }))
    }
  }, [form.booking_id, bookings, customers])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const updateItem = (idx, field, value) => setItems(prev => prev.map((it, i) => i === idx ? { ...it, [field]: value } : it))
  const addItem = () => setItems(prev => [...prev, { description: '', qty: 1, unit_price: 0 }])
  const removeItem = (idx) => setItems(prev => prev.filter((_, i) => i !== idx))

  function addStockItem(inv) {
    setShowStock(false)
    setItems(prev => {
      const base = prev.length === 1 && !prev[0].description && !prev[0].inventory_id ? [] : prev
      return [...base, {
        description: inv.sku ? `${inv.name} (${inv.sku})` : inv.name,
        qty: 1, unit_price: Number(inv.unit_price) || 0,
        inventory_id: inv.id, max_stock: Number(inv.stock) || 0,
      }]
    })
  }

  function applyPreset(preset) {
    set('description', preset)
    if (items.length === 1 && !items[0].description && !items[0].inventory_id) setItems([{ description: preset, qty: 1, unit_price: 0 }])
  }

  const { total } = calculateTotals(items)
  const fmt = (n) => n.toLocaleString('cs-CZ', { minimumFractionDigits: 2 }) + ' Kč'

  // Kontrola skladu — nelze vydat víc, než je skladem
  const stockError = useMemo(() => {
    for (const it of items) {
      if (it.inventory_id && (it.qty || 0) > (it.max_stock || 0)) {
        return `Skladem je jen ${it.max_stock || 0} ks: ${it.description}`
      }
    }
    return null
  }, [items])

  async function decrementStock() {
    const { data: { user } } = await supabase.auth.getUser()
    for (const it of items) {
      if (!it.inventory_id) continue
      const n = Math.max(0, Number(it.qty) || 0)
      if (n <= 0) continue
      const inv = inventory.find(x => x.id === it.inventory_id)
      const newStock = Math.max(0, (Number(inv?.stock) || 0) - n)
      await supabase.from('inventory').update({ stock: newStock }).eq('id', it.inventory_id)
      await supabase.from('inventory_movements').insert({
        item_id: it.inventory_id, type: 'issue', quantity: n,
        note: `Výdej na fakturu — ${it.description}`, performed_by: user?.id,
      })
    }
  }

  async function handleSave() {
    if (!form.customer_id) return setErr('Vyberte zákazníka.')
    if (items.length === 0 || !items.some(i => i.description)) return setErr('Přidejte alespoň jednu položku.')
    if (stockError) return setErr(stockError)
    setSaving(true); setErr(null)
    try {
      const notesWithDesc = [form.description, form.notes].filter(Boolean).join(' — ')
      const selectedBooking = bookings.find(x => x.id === form.booking_id)
      const cleanItems = items.filter(i => i.description).map(({ max_stock, ...rest }) => rest)
      const payment = (form.payment_method || form.variable_symbol || form.paid_date) ? {
        method: form.payment_method || undefined,
        vs: form.variable_symbol || undefined,
        paid_date: form.paid_date || undefined,
      } : null

      const invoice = await createInvoice({
        type: form.type,
        customer_id: form.customer_id,
        booking_id: form.booking_id || null,
        items: cleanItems,
        notes: notesWithDesc,
        issue_date: form.issue_date || undefined,
        due_date: form.due_date || null,
        source: selectedBooking?.sos_incident_id ? 'sos' : 'edit',
        status: form.paid_date ? 'paid' : undefined,
        payment,
      })

      // Odečíst vydané kusy ze skladu (neblokující — doklad zůstává platný i kdyby sklad selhal)
      try { await decrementStock() } catch (e) { console.warn('[InvoiceCreate] decrementStock failed:', e?.message) }

      // Vyrenderovat a uložit PDF, aby ho mail mohl přiložit jako přílohu
      try { await renderAndStoreInvoicePdf(invoice.id) } catch (e) { console.warn('[InvoiceCreate] renderAndStoreInvoicePdf failed:', e?.message) }

      // Odeslat zákazníkovi (s PDF přílohou — pdf_path už je uložen)
      if (form.send_email && invoice) {
        const customer = customers.find(c => c.id === form.customer_id)
        if (customer?.email) {
          try {
            const { error: efErr } = await supabase.functions.invoke('send-email', { body: { type: 'invoice', invoice_id: invoice.id } })
            if (efErr) {
              await supabase.from('sent_emails').insert({
                template_slug: 'invoice', recipient_email: customer.email, recipient_id: form.customer_id,
                booking_id: form.booking_id || null, subject: `Faktura ${invoice.number} — MotoGo24`,
                body_html: `<p>Dobrý den, byla Vám vystavena faktura č. ${invoice.number} na částku ${fmt(total)}.</p>`,
                status: 'queued',
              })
            }
          } catch {}
        }
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová faktura" onClose={onClose} wide noBackdropClose>
      <div className="space-y-4">
        {/* Typ */}
        <div>
          <Label>Typ faktury</Label>
          <div className="flex flex-wrap gap-2">
            {TYPE_OPTIONS.map(t => (
              <button key={t.value} onClick={() => set('type', t.value)}
                className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                style={{ padding: '6px 14px', border: 'none', background: form.type === t.value ? '#74FB71' : '#f1faf7', color: '#1a2e22' }}>
                {t.label}
              </button>
            ))}
          </div>
        </div>

        {/* Zákazník + Rezervace (s vyhledáváním) */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label>Zákazník *</Label>
            <SearchableSelect value={form.customer_id} onChange={v => set('customer_id', v)} placeholder="Hledat zákazníka…"
              options={customers.map(c => ({ value: c.id, label: `${c.full_name}${c.email ? ` (${c.email})` : ''}` }))} />
          </div>
          <div>
            <Label>Rezervace</Label>
            <SearchableSelect value={form.booking_id} onChange={v => set('booking_id', v)} placeholder="Hledat rezervaci…" allowEmpty
              options={bookings.map(b => ({ value: b.id, label: `${b.motorcycles?.model || '—'} — ${b.start_date} (${b.profiles?.full_name || '—'})` }))} />
          </div>
        </div>

        {/* Důvod / popis */}
        <div>
          <Label>Důvod / popis faktury</Label>
          <input value={form.description} onChange={e => set('description', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Např. oprava poškození, pozdní vrácení…" />
          <div className="flex flex-wrap gap-1 mt-2">
            {REASON_PRESETS.map(p => (
              <button key={p} onClick={() => applyPreset(p)} className="text-sm cursor-pointer rounded-btn"
                style={{ padding: '3px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>{p}</button>
            ))}
          </div>
        </div>

        {/* Položky */}
        <div>
          <div className="flex items-center justify-between mb-1">
            <Label>Položky faktury</Label>
            <div className="relative">
              <button onClick={() => setShowStock(s => !s)} className="text-sm font-bold cursor-pointer rounded-btn"
                style={{ padding: '4px 12px', background: '#e8fde8', border: '1px solid #74FB71', color: '#1a2e22' }}>+ Ze skladu</button>
              {showStock && (
                <div className="absolute right-0 z-20 mt-1" style={{ width: 340 }}>
                  <StockPicker inventory={inventory} onPick={addStockItem} onClose={() => setShowStock(false)} />
                </div>
              )}
            </div>
          </div>
          <div className="rounded-lg overflow-x-auto" style={{ border: '1px solid #d4e8e0' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
              <thead>
                <tr style={{ background: '#f1faf7' }}>
                  <th style={thS}>Popis</th>
                  <th style={{ ...thS, textAlign: 'center', width: 70 }}>Ks</th>
                  <th style={{ ...thS, textAlign: 'right', width: 110 }}>Cena/ks</th>
                  <th style={{ ...thS, textAlign: 'right', width: 100 }}>Celkem</th>
                  <th style={{ width: 32 }} />
                </tr>
              </thead>
              <tbody>
                {items.map((it, i) => (
                  <tr key={i} style={{ borderTop: '1px solid #e5e7eb' }}>
                    <td style={{ padding: 4 }}>
                      <input value={it.description} onChange={e => updateItem(i, 'description', e.target.value)}
                        className="w-full text-sm outline-none" style={{ padding: '4px 6px', background: 'transparent' }} placeholder="Popis položky…" />
                      {it.inventory_id && <span style={{ fontSize: 10, color: '#1a8a18', fontWeight: 700, paddingLeft: 6 }}>● sklad ({it.max_stock} ks)</span>}
                    </td>
                    <td style={{ padding: 4 }}>
                      <input type="number" value={it.qty} onChange={e => updateItem(i, 'qty', Number(e.target.value))} min="1"
                        className="w-full text-sm text-center outline-none" style={{ padding: 4, background: 'transparent',
                          color: it.inventory_id && it.qty > it.max_stock ? '#dc2626' : undefined }} />
                    </td>
                    <td style={{ padding: 4 }}>
                      <input type="number" value={it.unit_price} onChange={e => updateItem(i, 'unit_price', Number(e.target.value))}
                        className="w-full text-sm text-right outline-none" style={{ padding: 4, background: 'transparent' }} />
                    </td>
                    <td style={{ padding: '4px 8px', textAlign: 'right', fontWeight: 600 }}>{((it.unit_price || 0) * (it.qty || 1)).toLocaleString('cs-CZ')} Kč</td>
                    <td style={{ padding: 4 }}>
                      {items.length > 1 && <button onClick={() => removeItem(i)} className="cursor-pointer" style={{ background: 'none', border: 'none', color: '#dc2626', fontSize: 14 }}>✕</button>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button onClick={addItem} className="mt-2 text-sm font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#2563eb' }}>+ Přidat položku ručně</button>
        </div>

        {/* Souhrn */}
        <div className="flex justify-end">
          <div style={{ minWidth: 220 }}>
            <div className="flex justify-between py-1 font-bold text-sm" style={{ borderTop: '2px solid #1a8a18', color: '#1a8a18' }}>
              <span>Celkem:</span><span>{fmt(total)}</span>
            </div>
            <div className="py-1" style={{ color: '#1a2e22', fontSize: 13 }}>Cena je konečná — neplátce DPH</div>
          </div>
        </div>

        {/* Platba + data */}
        <div className="grid grid-cols-3 gap-3">
          <div>
            <Label>Způsob platby</Label>
            <select value={form.payment_method} onChange={e => set('payment_method', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
              {PAYMENT_METHODS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
            </select>
          </div>
          <div>
            <Label>Variabilní symbol</Label>
            <input value={form.variable_symbol} onChange={e => set('variable_symbol', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Výchozí = číslo dokladu" />
          </div>
          <div>
            <Label>Datum úhrady</Label>
            <input type="date" value={form.paid_date} onChange={e => set('paid_date', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          </div>
        </div>
        <div className="grid grid-cols-3 gap-3">
          <div>
            <Label>Datum vystavení</Label>
            <input type="date" value={form.issue_date} onChange={e => set('issue_date', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          </div>
          <div>
            <Label>Splatnost</Label>
            <input type="date" value={form.due_date} onChange={e => set('due_date', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          </div>
          <div>
            <Label>Poznámka</Label>
            <input value={form.notes} onChange={e => set('notes', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Volitelná poznámka…" />
          </div>
        </div>

        {/* Odeslat */}
        <div className="flex items-center gap-2">
          <input type="checkbox" id="send_email" checked={form.send_email} onChange={e => set('send_email', e.target.checked)} />
          <label htmlFor="send_email" className="text-sm font-bold cursor-pointer" style={{ color: '#1a2e22' }}>
            Automaticky odeslat zákazníkovi (e-mail s PDF přílohou)
          </label>
        </div>
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving}>{saving ? 'Vytvářím…' : 'Vytvořit fakturu'}</Button>
      </div>
    </Modal>
  )
}

const thS = { padding: '6px 8px', textAlign: 'left', fontSize: 13, fontWeight: 700, color: '#1a2e22' }

function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

// Vyhledávací rozbalovací výběr (zákazník / rezervace)
function SearchableSelect({ value, onChange, options, placeholder, allowEmpty }) {
  const [open, setOpen] = useState(false)
  const [q, setQ] = useState('')
  const ref = useRef(null)
  const selected = options.find(o => o.value === value)
  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase()
    if (!s) return options.slice(0, 50)
    return options.filter(o => o.label.toLowerCase().includes(s)).slice(0, 50)
  }, [q, options])
  useEffect(() => {
    const onDoc = e => { if (ref.current && !ref.current.contains(e.target)) setOpen(false) }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [])
  return (
    <div className="relative" ref={ref}>
      <button type="button" onClick={() => setOpen(o => !o)}
        className="w-full rounded-btn text-sm outline-none text-left" style={{ ...inputStyle, color: selected ? '#0f1a14' : '#6b7280' }}>
        {selected ? selected.label : (placeholder || '— Vyberte —')}
      </button>
      {open && (
        <div className="absolute z-20 mt-1 w-full rounded-lg" style={{ background: '#fff', border: '1px solid #d4e8e0', boxShadow: '0 6px 18px rgba(0,0,0,.12)' }}>
          <input autoFocus value={q} onChange={e => setQ(e.target.value)} placeholder="Hledat…"
            className="w-full text-sm outline-none" style={{ padding: '8px 10px', borderBottom: '1px solid #e5e7eb' }} />
          <div style={{ maxHeight: 220, overflowY: 'auto' }}>
            {allowEmpty && (
              <div onClick={() => { onChange(''); setOpen(false); setQ('') }} className="cursor-pointer text-sm" style={{ padding: '7px 10px', color: '#6b7280' }}>— Žádná —</div>
            )}
            {filtered.map(o => (
              <div key={o.value} onClick={() => { onChange(o.value); setOpen(false); setQ('') }}
                className="cursor-pointer text-sm hover:bg-[#f1faf7]" style={{ padding: '7px 10px', color: '#0f1a14', background: o.value === value ? '#e8fde8' : undefined }}>
                {o.label}
              </div>
            ))}
            {filtered.length === 0 && <div className="text-sm" style={{ padding: '7px 10px', color: '#6b7280' }}>Nic nenalezeno</div>}
          </div>
        </div>
      )}
    </div>
  )
}

// Vyhledávací výběr skladové položky (přidá řádek + později odečte ze skladu)
function StockPicker({ inventory, onPick, onClose }) {
  const [q, setQ] = useState('')
  const ref = useRef(null)
  useEffect(() => {
    const onDoc = e => { if (ref.current && !ref.current.contains(e.target)) onClose() }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [])
  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase()
    const base = s ? inventory.filter(i => `${i.name} ${i.sku || ''}`.toLowerCase().includes(s)) : inventory
    return base.slice(0, 60)
  }, [q, inventory])
  return (
    <div ref={ref} className="rounded-lg" style={{ background: '#fff', border: '1px solid #74FB71', boxShadow: '0 6px 18px rgba(0,0,0,.14)' }}>
      <input autoFocus value={q} onChange={e => setQ(e.target.value)} placeholder="Hledat na skladě (název / SKU)…"
        className="w-full text-sm outline-none" style={{ padding: '8px 10px', borderBottom: '1px solid #e5e7eb' }} />
      <div style={{ maxHeight: 260, overflowY: 'auto' }}>
        {filtered.map(inv => (
          <div key={inv.id} onClick={() => onPick(inv)} className="cursor-pointer hover:bg-[#f1faf7]"
            style={{ padding: '7px 10px', borderBottom: '1px solid #f3f4f6', opacity: (inv.stock || 0) <= 0 ? 0.55 : 1 }}>
            <div className="flex justify-between text-sm">
              <span style={{ color: '#0f1a14', fontWeight: 600 }}>{inv.name}</span>
              <span style={{ color: (inv.stock || 0) <= 0 ? '#dc2626' : '#1a8a18', fontWeight: 700 }}>{inv.stock || 0} ks</span>
            </div>
            <div style={{ fontSize: 11, color: '#6b7280' }}>{inv.sku || '—'} · {(Number(inv.unit_price) || 0).toLocaleString('cs-CZ')} Kč</div>
          </div>
        ))}
        {filtered.length === 0 && <div className="text-sm" style={{ padding: '8px 10px', color: '#6b7280' }}>Sklad prázdný / nic nenalezeno</div>}
      </div>
    </div>
  )
}
