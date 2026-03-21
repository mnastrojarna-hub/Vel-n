import { useState } from 'react'

const TYPES = [
  { value: 'revenue', label: 'Příjem' },
  { value: 'expense', label: 'Výdaj' },
  { value: 'asset', label: 'Majetek' },
  { value: 'payroll', label: 'Mzdy' },
]

const STATUSES = [
  { value: 'pending', label: 'Čeká' },
  { value: 'enriched', label: 'Ke schválení' },
  { value: 'validated', label: 'Připraven' },
  { value: 'exported', label: 'Odesláno' },
  { value: 'approved', label: 'Schváleno' },
  { value: 'error', label: 'Chyba' },
]

const PAYMENT_OPTIONS = [
  { value: '', label: '— Neurčeno —' },
  { value: 'bank_transfer', label: 'Bankovní převod' },
  { value: 'cash', label: 'Hotovost' },
  { value: 'card', label: 'Karta' },
]

export default function EventEditModal({ event, onClose, onSave }) {
  const meta = event.metadata || {}
  const [amount, setAmount] = useState(event.amount_czk || 0)
  const [eventType, setEventType] = useState(event.event_type || 'expense')
  const [status, setStatus] = useState(event.status || 'pending')
  const [duzp, setDuzp] = useState(event.duzp || '')
  const [supplierName, setSupplierName] = useState(meta.supplier_name || '')
  const [invoiceNumber, setInvoiceNumber] = useState(meta.invoice_number || '')
  const [variableSymbol, setVariableSymbol] = useState(meta.variable_symbol || '')
  const [bankAccount, setBankAccount] = useState(meta.supplier_bank_account || '')
  const [dueDate, setDueDate] = useState(meta.due_date || '')
  const [receivedDate, setReceivedDate] = useState(meta.received_date || '')
  const [paymentMethod, setPaymentMethod] = useState(meta.payment_method || '')
  const [saving, setSaving] = useState(false)

  async function handleSave() {
    setSaving(true)
    const updatedMeta = {
      ...meta,
      supplier_name: supplierName,
      invoice_number: invoiceNumber,
      variable_symbol: variableSymbol,
      supplier_bank_account: bankAccount,
      due_date: dueDate || null,
      received_date: receivedDate || null,
      payment_method: paymentMethod || null,
    }
    await onSave({
      amount_czk: parseFloat(amount) || 0,
      event_type: eventType,
      status,
      duzp: duzp || null,
      metadata: updatedMeta,
    })
    setSaving(false)
  }

  const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, width: '100%', fontSize: 14 }

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
      onClick={onClose}>
      <div style={{ background: '#fff', borderRadius: 16, padding: 24, width: '100%', maxWidth: 560, maxHeight: '90vh', overflow: 'auto' }}
        onClick={e => e.stopPropagation()}>
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-lg font-extrabold" style={{ color: '#1a2e22' }}>Upravit událost</h3>
          <button onClick={onClose} style={{ background: 'none', border: 'none', fontSize: 20, cursor: 'pointer', color: '#6b7280' }}>×</button>
        </div>

        <div className="grid grid-cols-2 gap-3 mb-4">
          <div>
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>Částka (Kč)</label>
            <input type="number" value={amount} onChange={e => setAmount(e.target.value)} style={inputStyle} />
          </div>
          <div>
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>Datum (DUZP)</label>
            <input type="date" value={duzp} onChange={e => setDuzp(e.target.value)} style={inputStyle} />
          </div>
          <div>
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>Typ</label>
            <select value={eventType} onChange={e => setEventType(e.target.value)} style={inputStyle}>
              {TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </div>
          <div>
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>Status</label>
            <select value={status} onChange={e => setStatus(e.target.value)} style={inputStyle}>
              {STATUSES.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
            </select>
          </div>
        </div>

        <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Dokladová data</div>
        <div className="grid grid-cols-2 gap-3 mb-4">
          <div>
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>Dodavatel</label>
            <input value={supplierName} onChange={e => setSupplierName(e.target.value)} style={inputStyle} />
          </div>
          <div>
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>Číslo faktury</label>
            <input value={invoiceNumber} onChange={e => setInvoiceNumber(e.target.value)} style={inputStyle} />
          </div>
          <div>
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>VS</label>
            <input value={variableSymbol} onChange={e => setVariableSymbol(e.target.value)} style={inputStyle} />
          </div>
          <div>
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>Číslo účtu</label>
            <input value={bankAccount} onChange={e => setBankAccount(e.target.value)} style={inputStyle} />
          </div>
          <div>
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>Splatnost</label>
            <input type="date" value={dueDate} onChange={e => setDueDate(e.target.value)} style={inputStyle} />
          </div>
          <div>
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>Datum přijetí</label>
            <input type="date" value={receivedDate} onChange={e => setReceivedDate(e.target.value)} style={inputStyle} />
          </div>
          <div className="col-span-2">
            <label className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>Způsob platby</label>
            <select value={paymentMethod} onChange={e => setPaymentMethod(e.target.value)} style={inputStyle}>
              {PAYMENT_OPTIONS.map(p => <option key={p.value} value={p.value}>{p.label}</option>)}
            </select>
          </div>
        </div>

        <div className="flex justify-end gap-2">
          <button onClick={onClose}
            className="text-sm font-bold cursor-pointer rounded"
            style={{ padding: '8px 20px', background: '#f3f4f6', border: '1px solid #d4d4d8', color: '#6b7280' }}>
            Zrušit
          </button>
          <button onClick={handleSave} disabled={saving}
            className="text-sm font-bold cursor-pointer rounded"
            style={{ padding: '8px 20px', background: '#1a8a18', border: 'none', color: '#fff', opacity: saving ? 0.5 : 1 }}>
            {saving ? 'Ukládám...' : 'Uložit'}
          </button>
        </div>
      </div>
    </div>
  )
}
