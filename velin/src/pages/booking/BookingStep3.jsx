import { useState } from 'react'
import Button from '../../components/ui/Button'

function fmtDate(d) { return d ? d.toLocaleDateString('cs-CZ') : '—' }

export default function BookingStep3({ selectedMoto, startDate, endDate, days, totalPrice, customers, onBack, onCreate, saving, noPayment, setNoPayment }) {
  const [customerSearch, setCustomerSearch] = useState('')
  const [selectedCustomer, setSelectedCustomer] = useState(null)
  const [pickupTime, setPickupTime] = useState('09:00')
  const [notes, setNotes] = useState('')

  const filteredCustomers = customerSearch.length > 1
    ? customers.filter(c =>
      (c.full_name || '').toLowerCase().includes(customerSearch.toLowerCase()) ||
      (c.email || '').toLowerCase().includes(customerSearch.toLowerCase()) ||
      (c.phone || '').includes(customerSearch)
    ).slice(0, 8)
    : []

  return (
    <div>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Zákazník</label>
          {selectedCustomer ? (
            <div className="p-3 rounded-lg" style={{ background: '#eafbe9', border: '1px solid #74FB71' }}>
              <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{selectedCustomer.full_name}</div>
              <div className="text-sm" style={{ color: '#1a2e22' }}>{selectedCustomer.email}</div>
              {selectedCustomer.phone && <div className="text-sm" style={{ color: '#1a2e22' }}>{selectedCustomer.phone}</div>}
              <button onClick={() => { setSelectedCustomer(null); setCustomerSearch('') }}
                className="text-sm font-bold cursor-pointer mt-1" style={{ color: '#dc2626', background: 'none', border: 'none' }}>Změnit</button>
            </div>
          ) : (
            <div>
              <input type="text" value={customerSearch} onChange={e => setCustomerSearch(e.target.value)}
                placeholder="Hledat jméno, email, telefon…"
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
              {filteredCustomers.length > 0 && (
                <div className="mt-1 rounded-lg" style={{ border: '1px solid #d4e8e0', maxHeight: 180, overflowY: 'auto' }}>
                  {filteredCustomers.map(c => (
                    <div key={c.id} className="p-2 cursor-pointer text-sm hover:bg-green-50"
                      style={{ borderBottom: '1px solid #f1faf7' }}
                      onClick={() => { setSelectedCustomer(c); setCustomerSearch('') }}>
                      <span className="font-bold">{c.full_name}</span>
                      <span className="ml-2" style={{ color: '#1a2e22' }}>{c.email}</span>
                    </div>
                  ))}
                </div>
              )}
              {customerSearch.length > 1 && filteredCustomers.length === 0 && (
                <p className="text-sm mt-1" style={{ color: '#1a2e22' }}>Žádný zákazník nenalezen</p>
              )}
            </div>
          )}

          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1 mt-4" style={{ color: '#1a2e22' }}>Čas vyzvednutí</label>
          <input type="time" value={pickupTime} onChange={e => setPickupTime(e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />

          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1 mt-4" style={{ color: '#1a2e22' }}>Poznámka</label>
          <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2}
            placeholder="Interní poznámka (volitelné)"
            className="w-full rounded-btn text-sm outline-none resize-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>

        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Shrnutí rezervace</label>
          <div className="rounded-lg p-4" style={{ background: '#f8faf9', border: '1px solid #e5e7eb' }}>
            <div className="text-sm font-bold mb-2" style={{ color: '#0f1a14' }}>{selectedMoto?.model}</div>
            <div className="text-sm mb-3" style={{ color: '#1a2e22' }}>{selectedMoto?.spz || '—'}</div>
            <div className="flex justify-between text-sm mb-1"><span style={{ color: '#1a2e22' }}>Vyzvednutí</span><span className="font-bold" style={{ color: '#0f1a14' }}>{fmtDate(startDate)}</span></div>
            <div className="flex justify-between text-sm mb-1"><span style={{ color: '#1a2e22' }}>Vrácení</span><span className="font-bold" style={{ color: '#0f1a14' }}>{fmtDate(endDate)}</span></div>
            <div className="flex justify-between text-sm mb-3"><span style={{ color: '#1a2e22' }}>Počet dní</span><span className="font-bold" style={{ color: '#0f1a14' }}>{days}</span></div>
            <div style={{ borderTop: '1px solid #d4e8e0', paddingTop: 8 }}>
              <div className="flex justify-between">
                <span className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>Celkem</span>
                <span className="text-sm font-extrabold" style={{ color: '#1a8a18' }}>{totalPrice ? totalPrice.toLocaleString('cs-CZ') + ' Kč' : '—'}</span>
              </div>
            </div>
          </div>

          <label className="flex items-center gap-2 mt-4 cursor-pointer p-3 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fbbf24' }}>
            <input type="checkbox" checked={noPayment} onChange={e => setNoPayment(e.target.checked)}
              style={{ width: 16, height: 16, accentColor: '#1a8a18' }} />
            <div>
              <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>Bez platby</div>
              <div className="text-sm" style={{ color: '#1a2e22' }}>
                {noPayment ? 'Rezervace bude označena jako zaplacená' : 'Zákazníkovi se v appce zobrazí výzva k platbě'}
              </div>
            </div>
          </label>
        </div>
      </div>

      <div className="flex justify-between mt-5">
        <Button onClick={onBack}>← Zpět</Button>
        <Button green onClick={() => onCreate({ selectedCustomer, pickupTime, notes })} disabled={saving || !selectedCustomer}>
          {saving ? 'Vytvářím…' : noPayment ? 'Vytvořit (zaplaceno)' : 'Vytvořit a odeslat k platbě'}
        </Button>
      </div>
    </div>
  )
}
