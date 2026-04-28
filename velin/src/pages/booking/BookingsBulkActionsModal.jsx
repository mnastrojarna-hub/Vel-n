import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

export default function BookingsBulkActionsModal({ open, onClose, selectedBookings, onUpdated }) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(null)
  const [mode, setMode] = useState(null)
  const [reason, setReason] = useState('')
  const [shiftDays, setShiftDays] = useState('')
  const [exportFormat, setExportFormat] = useState('csv')

  useEffect(() => {
    if (open) {
      setMode(null); setError(null); setSuccess(null); setReason(''); setShiftDays(''); setExportFormat('csv')
    }
  }, [open])

  if (!open) return null

  const ids = selectedBookings.map(b => b.id)
  const count = ids.length

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  async function run(label, fn) {
    setBusy(true); setError(null); setSuccess(null)
    try {
      await fn()
      setSuccess(`${label} (${count} rezervací)`)
      onUpdated?.()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function handleStatusChange(newStatus) {
    const labels = { reserved: 'Potvrzeno (rezervováno)', active: 'Aktivováno', completed: 'Dokončeno', cancelled: 'Zrušeno' }
    await run(`Stav: ${labels[newStatus] || newStatus}`, async () => {
      const upd = { status: newStatus }
      if (newStatus === 'cancelled') {
        upd.cancellation_reason = reason || 'Hromadné storno'
        upd.cancelled_at = new Date().toISOString()
        upd.cancelled_by_source = 'admin'
      }
      if (newStatus === 'completed') {
        upd.actual_return_date = new Date().toISOString().slice(0, 10)
        upd.returned_at = new Date().toISOString()
      }
      const { error: err } = await supabase.from('bookings').update(upd).in('id', ids)
      if (err) throw err
      await logAudit('booking_bulk_status_changed', { count, to_status: newStatus, reason: upd.cancellation_reason || null, ids })
    })
  }

  async function handlePaymentChange(newPayment) {
    await run(`Platba: ${newPayment === 'paid' ? 'Zaplaceno' : 'Nezaplaceno'}`, async () => {
      const { error: err } = await supabase.from('bookings').update({ payment_status: newPayment }).in('id', ids)
      if (err) throw err
      await logAudit('booking_bulk_payment_changed', { count, to_payment: newPayment, ids })
    })
  }

  async function handleShiftDates() {
    const n = parseInt(shiftDays)
    if (isNaN(n) || n === 0) { setError('Zadej počet dní (kladný = posun vpřed, záporný = vzad)'); return }
    await run(`Termíny posunuty o ${n} dní`, async () => {
      // Need to fetch current dates and update each row
      for (const b of selectedBookings) {
        if (!b.start_date || !b.end_date) continue
        const newStart = new Date(b.start_date); newStart.setDate(newStart.getDate() + n)
        const newEnd = new Date(b.end_date); newEnd.setDate(newEnd.getDate() + n)
        await supabase.from('bookings').update({
          start_date: newStart.toISOString().slice(0, 10),
          end_date: newEnd.toISOString().slice(0, 10),
        }).eq('id', b.id)
      }
      await logAudit('booking_bulk_dates_shifted', { count, days: n, ids })
    })
  }

  async function handleDelete() {
    if (!window.confirm(`TRVALE smazat ${count} rezervací? Tato akce je nevratná.`)) return
    await run('Rezervace smazány', async () => {
      const { error: err } = await supabase.from('bookings').delete().in('id', ids)
      if (err) throw err
      await logAudit('booking_bulk_deleted', { count, ids })
    })
  }

  function handleExport() {
    const headers = ['ID', 'Zákazník', 'Email', 'Telefon', 'Motorka', 'SPZ', 'Od', 'Do', 'Cena', 'Stav', 'Platba', 'Vytvořeno']
    const rows = selectedBookings.map(b => [
      b.id?.slice(-8).toUpperCase() || '',
      b.profiles?.full_name || b.customer_name || '',
      b.profiles?.email || '',
      b.profiles?.phone || '',
      b.motorcycles?.model || '',
      b.motorcycles?.spz || '',
      b.start_date?.slice(0, 10) || '',
      b.end_date?.slice(0, 10) || '',
      b.total_price || 0,
      b.status || '',
      b.payment_status || '',
      b.created_at?.slice(0, 19).replace('T', ' ') || '',
    ])
    const csv = [headers, ...rows].map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n')
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `rezervace-${new Date().toISOString().slice(0, 10)}.csv`
    a.click(); URL.revokeObjectURL(url)
    setSuccess(`Exportováno ${count} rezervací do CSV`)
    logAudit('booking_bulk_exported', { count, format: 'csv' })
  }

  return (
    <Modal open={open} onClose={onClose} title={`Hromadná správa rezervací (${count})`} wide>
      {success && <Banner color="#16a34a" bg="#dcfce7">{success}</Banner>}
      {error && <Banner color="#dc2626" bg="#fee2e2">{error}</Banner>}

      <div className="mb-4">
        <div className="text-sm font-bold mb-2" style={{ color: '#1a2e22' }}>Vybrané rezervace:</div>
        <div className="flex flex-wrap gap-1.5 max-h-24 overflow-auto p-2 rounded-btn" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          {selectedBookings.map(b => (
            <span key={b.id} className="text-xs font-bold px-2 py-1 rounded-btn" style={{ background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
              #{b.id?.slice(-8).toUpperCase()} {b.profiles?.full_name || '—'}
            </span>
          ))}
        </div>
      </div>

      {!mode && (
        <div className="grid grid-cols-2 gap-3">
          <ModeBtn label="Změnit stav" desc="Potvrdit / aktivovat / dokončit / zrušit" onClick={() => setMode('status')} />
          <ModeBtn label="Změnit platbu" desc="Označit jako zaplaceno / nezaplaceno" onClick={() => setMode('payment')} />
          <ModeBtn label="Posunout termíny" desc="O X dní vpřed nebo vzad" onClick={() => setMode('shift')} />
          <ModeBtn label="Export do CSV" desc="Stáhnout vybrané rezervace" onClick={() => setMode('export')} />
          <ModeBtn label="Smazat rezervace" desc="Trvale odstranit (nevratné)" onClick={() => setMode('delete')} danger />
        </div>
      )}

      {mode === 'status' && (
        <Section title="Změnit stav" onBack={() => setMode(null)}>
          <div className="grid grid-cols-2 gap-2 mb-3">
            <StatusBtn label="✓ Potvrdit (reserved)" color="#2563eb" onClick={() => handleStatusChange('reserved')} disabled={busy} />
            <StatusBtn label="▶ Aktivovat (running)" color="#16a34a" onClick={() => handleStatusChange('active')} disabled={busy} />
            <StatusBtn label="✓ Dokončit" color="#1a8a18" onClick={() => handleStatusChange('completed')} disabled={busy} />
            <StatusBtn label="✗ Zrušit" color="#dc2626" onClick={() => handleStatusChange('cancelled')} disabled={busy} />
          </div>
          <Label>Důvod (pro storno):</Label>
          <input value={reason} onChange={e => setReason(e.target.value)} placeholder="Např. nedostavil se, COVID…"
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </Section>
      )}

      {mode === 'payment' && (
        <Section title="Označit platbu" onBack={() => setMode(null)}>
          <div className="grid grid-cols-2 gap-2">
            <StatusBtn label="✓ Zaplaceno" color="#16a34a" onClick={() => handlePaymentChange('paid')} disabled={busy} />
            <StatusBtn label="✗ Nezaplaceno" color="#dc2626" onClick={() => handlePaymentChange('unpaid')} disabled={busy} />
          </div>
        </Section>
      )}

      {mode === 'shift' && (
        <Section title="Posunout termíny" onBack={() => setMode(null)}>
          <Label>Počet dní (+/-)</Label>
          <input type="number" value={shiftDays} onChange={e => setShiftDays(e.target.value)}
            placeholder="Např. 7 (vpřed) nebo -3 (vzad)"
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          <div className="text-xs mt-2" style={{ color: '#6b7280' }}>Posune start_date i end_date o zadaný počet dní u všech vybraných rezervací.</div>
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleShiftDates} disabled={busy || !shiftDays}>{busy ? 'Pracuji…' : `Posunout (${count})`}</Button>
          </div>
        </Section>
      )}

      {mode === 'export' && (
        <Section title="Export do CSV" onBack={() => setMode(null)}>
          <div className="text-sm" style={{ color: '#1a2e22' }}>Stáhne CSV soubor s {count} rezervacemi (ID, zákazník, motorka, termíny, cena, stav).</div>
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleExport} disabled={busy}>Stáhnout CSV</Button>
          </div>
        </Section>
      )}

      {mode === 'delete' && (
        <Section title="Trvale smazat rezervace" onBack={() => setMode(null)}>
          <div className="p-3 rounded-card mb-3" style={{ background: '#fee2e2', color: '#dc2626' }}>
            <strong>Pozor!</strong> Tato akce je <strong>nevratná</strong>. {count} rezervací bude trvale odstraněno ze Supabase.
          </div>
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button onClick={handleDelete} disabled={busy} style={{ background: '#dc2626', color: '#fff' }}>
              {busy ? 'Pracuji…' : `Trvale smazat (${count})`}
            </Button>
          </div>
        </Section>
      )}

      {!mode && (
        <div className="flex justify-end mt-5">
          <Button onClick={onClose}>Zavřít</Button>
        </div>
      )}
    </Modal>
  )
}

function Banner({ children, color, bg }) {
  return <div className="mb-3 p-3 rounded-card text-sm font-bold" style={{ background: bg, color }}>{children}</div>
}

function Section({ title, onBack, children }) {
  return (
    <div className="p-4 rounded-card" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>{title}</div>
      {children}
    </div>
  )
}

function ModeBtn({ label, desc, onClick, danger = false }) {
  return (
    <button onClick={onClick} className="text-left rounded-card cursor-pointer transition-all hover:shadow"
      style={{ padding: 16, background: '#fff', border: `1px solid ${danger ? '#fca5a5' : '#d4e8e0'}` }}>
      <div className="font-extrabold uppercase tracking-wide text-sm" style={{ color: danger ? '#dc2626' : '#1a2e22' }}>{label}</div>
      <div className="text-xs mt-1" style={{ color: '#6b7280' }}>{desc}</div>
    </button>
  )
}

function StatusBtn({ label, color, onClick, disabled }) {
  return (
    <button onClick={onClick} disabled={disabled}
      className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer text-sm disabled:opacity-50"
      style={{ padding: '10px 14px', background: '#fff', border: `2px solid ${color}`, color }}>
      {label}
    </button>
  )
}

function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
