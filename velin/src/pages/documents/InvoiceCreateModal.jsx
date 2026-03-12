import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { createInvoice, calculateTotals } from '../../lib/invoiceUtils'
import { generateInvoiceHtml } from '../../lib/invoiceTemplate'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

const REASON_PRESETS = [
  'Oprava poškození',
  'Pozdní vrácení',
  'Tankování',
  'Mytí motorky',
  'Spoluúčast na pojistné události',
  'Ztráta klíčů',
  'Nadměrný nájezd km',
]

export default function InvoiceCreateModal({ onClose, onSaved, prefillBooking }) {
  const [customers, setCustomers] = useState([])
  const [bookings, setBookings] = useState([])
  const [form, setForm] = useState({
    type: 'issued',
    customer_id: '',
    booking_id: prefillBooking || '',
    due_date: '',
    notes: '',
    description: '',
    send_email: true,
  })
  const [items, setItems] = useState([
    { description: '', qty: 1, unit_price: 0 },
  ])
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('profiles').select('id, full_name, email').order('full_name').then(({ data }) => setCustomers(data || []))
    supabase.from('bookings').select('id, start_date, end_date, total_price, contract_url, profiles(full_name, email), motorcycles(model), sos_incident_id, modification_history')
      .order('start_date', { ascending: false }).limit(50).then(({ data }) => setBookings(data || []))
  }, [])

  // Auto-fill items from booking
  useEffect(() => {
    if (!form.booking_id) return
    const b = bookings.find(x => x.id === form.booking_id)
    if (!b) return
    if (items.length === 1 && !items[0].description) {
      setItems([{
        description: `Pronájem ${b.motorcycles?.model || 'motorky'} (${b.start_date} – ${b.end_date})`,
        qty: 1,
        unit_price: b.total_price || 0,
      }])
    }
    if (!form.customer_id && b.profiles) {
      const cust = customers.find(c => c.full_name === b.profiles.full_name)
      if (cust) setForm(f => ({ ...f, customer_id: cust.id }))
    }
  }, [form.booking_id, bookings, customers])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  function updateItem(idx, field, value) {
    setItems(prev => prev.map((it, i) => i === idx ? { ...it, [field]: value } : it))
  }

  function addItem() {
    setItems(prev => [...prev, { description: '', qty: 1, unit_price: 0 }])
  }

  function removeItem(idx) {
    setItems(prev => prev.filter((_, i) => i !== idx))
  }

  function applyPreset(preset) {
    set('description', preset)
    if (items.length === 1 && !items[0].description) {
      setItems([{ description: preset, qty: 1, unit_price: 0 }])
    }
  }

  const { subtotal, taxAmount, total } = calculateTotals(items)
  const fmt = (n) => n.toLocaleString('cs-CZ', { minimumFractionDigits: 2 }) + ' Kč'

  // Find contract number from selected booking
  const selectedBooking = bookings.find(x => x.id === form.booking_id)
  const contractNumber = selectedBooking?.contract_url ? selectedBooking.id.slice(0, 8).toUpperCase() : null

  async function handleSave() {
    if (!form.customer_id) return setErr('Vyberte zákazníka.')
    if (items.length === 0 || !items[0].description) return setErr('Přidejte alespoň jednu položku.')
    setSaving(true); setErr(null)
    try {
      const notesWithDesc = [form.description, form.notes].filter(Boolean).join(' — ')
      const invoice = await createInvoice({
        type: form.type,
        customer_id: form.customer_id,
        booking_id: form.booking_id || null,
        items,
        notes: notesWithDesc,
        due_date: form.due_date || null,
        source: selectedBooking?.sos_incident_id ? 'sos' : 'edit',
      })

      // Auto-send email to customer
      if (form.send_email && invoice) {
        const customer = customers.find(c => c.id === form.customer_id)
        if (customer?.email) {
          try {
            // Try edge function first
            const { error: efErr } = await supabase.functions.invoke('send-email', {
              body: { type: 'invoice', invoice_id: invoice.id },
            })
            if (efErr) {
              // Fallback: queue in sent_emails
              await supabase.from('sent_emails').insert({
                template_slug: 'invoice',
                recipient_email: customer.email,
                recipient_id: form.customer_id,
                booking_id: form.booking_id || null,
                subject: `Faktura ${invoice.number} — MotoGo24`,
                body_html: `<p>Dobrý den, byla Vám vystavena faktura č. ${invoice.number} na částku ${fmt(total)}.</p>`,
                status: 'queued',
              })
            }
          } catch {} // non-blocking
        }
      }

      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová faktura" onClose={onClose} wide noBackdropClose>
      <div className="space-y-4">
        {/* Type selector */}
        <div>
          <Label>Typ faktury</Label>
          <div className="flex flex-wrap gap-2">
            {[
              { value: 'issued', label: 'Vystavená (FV)' },
              { value: 'proforma', label: 'Zálohová (ZF)' },
              { value: 'final', label: 'Konečná (KF)' },
              { value: 'payment_receipt', label: 'Doklad k platbě (DP)' },
              { value: 'shop_proforma', label: 'Shop zálohová' },
              { value: 'shop_final', label: 'Shop konečná' },
            ].map(t => (
              <button key={t.value} onClick={() => set('type', t.value)}
                className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                style={{
                  padding: '6px 14px', border: 'none',
                  background: form.type === t.value ? '#74FB71' : '#f1faf7',
                  color: form.type === t.value ? '#1a2e22' : '#1a2e22',
                }}>{t.label}</button>
            ))}
          </div>
        </div>

        {/* Customer + Booking */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label>Zákazník *</Label>
            <select value={form.customer_id} onChange={e => set('customer_id', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
              <option value="">— Vyberte zákazníka —</option>
              {customers.map(c => <option key={c.id} value={c.id}>{c.full_name} ({c.email})</option>)}
            </select>
          </div>
          <div>
            <Label>Rezervace</Label>
            <select value={form.booking_id} onChange={e => set('booking_id', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
              <option value="">— Volitelné —</option>
              {bookings.map(b => (
                <option key={b.id} value={b.id}>
                  {b.motorcycles?.model} — {b.start_date} ({b.profiles?.full_name})
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Contract number info */}
        {contractNumber && (
          <div className="p-2 rounded-lg text-sm" style={{ background: '#dbeafe', color: '#1e40af' }}>
            Smlouva: <span className="font-bold font-mono">{contractNumber}</span>
          </div>
        )}

        {/* Description / reason */}
        <div>
          <Label>Důvod / popis faktury</Label>
          <input value={form.description} onChange={e => set('description', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle}
            placeholder="Např. oprava poškození, pozdní vrácení…" />
          <div className="flex flex-wrap gap-1 mt-2">
            {REASON_PRESETS.map(p => (
              <button key={p} onClick={() => applyPreset(p)}
                className="text-sm cursor-pointer rounded-btn"
                style={{ padding: '3px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
                {p}
              </button>
            ))}
          </div>
        </div>

        {/* Items */}
        <div>
          <Label>Položky faktury</Label>
          <div className="rounded-lg overflow-hidden" style={{ border: '1px solid #d4e8e0' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
              <thead>
                <tr style={{ background: '#f1faf7' }}>
                  <th style={{ padding: '6px 8px', textAlign: 'left', fontSize: 13, fontWeight: 700, color: '#1a2e22' }}>Popis</th>
                  <th style={{ padding: '6px 8px', textAlign: 'center', fontSize: 13, fontWeight: 700, color: '#1a2e22', width: 60 }}>Ks</th>
                  <th style={{ padding: '6px 8px', textAlign: 'right', fontSize: 13, fontWeight: 700, color: '#1a2e22', width: 100 }}>Cena/ks</th>
                  <th style={{ padding: '6px 8px', textAlign: 'right', fontSize: 13, fontWeight: 700, color: '#1a2e22', width: 90 }}>Celkem</th>
                  <th style={{ width: 32 }} />
                </tr>
              </thead>
              <tbody>
                {items.map((it, i) => (
                  <tr key={i} style={{ borderTop: '1px solid #e5e7eb' }}>
                    <td style={{ padding: 4 }}>
                      <input value={it.description} onChange={e => updateItem(i, 'description', e.target.value)}
                        className="w-full text-sm outline-none" style={{ padding: '4px 6px', background: 'transparent' }}
                        placeholder="Popis položky…" />
                    </td>
                    <td style={{ padding: 4 }}>
                      <input type="number" value={it.qty} onChange={e => updateItem(i, 'qty', Number(e.target.value))}
                        className="w-full text-sm text-center outline-none" style={{ padding: '4px', background: 'transparent' }} min="1" />
                    </td>
                    <td style={{ padding: 4 }}>
                      <input type="number" value={it.unit_price} onChange={e => updateItem(i, 'unit_price', Number(e.target.value))}
                        className="w-full text-sm text-right outline-none" style={{ padding: '4px', background: 'transparent' }} />
                    </td>
                    <td style={{ padding: '4px 8px', textAlign: 'right', fontWeight: 600, fontSize: 12 }}>
                      {((it.unit_price || 0) * (it.qty || 1)).toLocaleString('cs-CZ')} Kč
                    </td>
                    <td style={{ padding: 4 }}>
                      {items.length > 1 && (
                        <button onClick={() => removeItem(i)} className="cursor-pointer"
                          style={{ background: 'none', border: 'none', color: '#dc2626', fontSize: 14 }}>✕</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button onClick={addItem} className="mt-2 text-sm font-bold cursor-pointer"
            style={{ background: 'none', border: 'none', color: '#2563eb' }}>+ Přidat položku</button>
        </div>

        {/* Totals */}
        <div className="flex justify-end">
          <div style={{ minWidth: 220, fontSize: 12 }}>
            <div className="flex justify-between py-1 font-bold text-sm" style={{ borderTop: '2px solid #1a8a18', color: '#1a8a18' }}>
              <span>Celkem:</span><span>{fmt(total)}</span>
            </div>
            <div className="py-1" style={{ color: '#1a2e22', fontSize: 13 }}>Cena je konečná — neplátce DPH</div>
          </div>
        </div>

        {/* Due date + notes */}
        <div className="grid grid-cols-2 gap-3">
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

        {/* Send email toggle */}
        <div className="flex items-center gap-2">
          <input type="checkbox" id="send_email" checked={form.send_email} onChange={e => set('send_email', e.target.checked)} />
          <label htmlFor="send_email" className="text-sm font-bold cursor-pointer" style={{ color: '#1a2e22' }}>
            Automaticky odeslat zákazníkovi (email + notifikace)
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

function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
