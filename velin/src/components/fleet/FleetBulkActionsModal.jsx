import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../ui/Modal'
import Button from '../ui/Button'
import { UNAVAILABLE_REASONS } from './motoActionConstants'

const CATEGORIES = [
  { value: 'cestovni', label: 'Cestovní' },
  { value: 'sportovni', label: 'Sportovní' },
  { value: 'naked', label: 'Naked' },
  { value: 'chopper', label: 'Chopper' },
  { value: 'detske', label: 'Dětské' },
]

export default function FleetBulkActionsModal({ open, onClose, selectedMotos, onUpdated }) {
  const [branches, setBranches] = useState([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(null)
  const [mode, setMode] = useState(null)

  // form state per mode
  const [targetBranch, setTargetBranch] = useState('')
  const [targetCategory, setTargetCategory] = useState('')
  const [reason, setReason] = useState('')
  const [customReason, setCustomReason] = useState('')
  const [unavailableUntil, setUnavailableUntil] = useState('')
  const [bookingFrom, setBookingFrom] = useState('')
  const [bookingTo, setBookingTo] = useState('')
  const [bookingNote, setBookingNote] = useState('')
  const [priceField, setPriceField] = useState('all')
  const [priceValue, setPriceValue] = useState('')

  useEffect(() => {
    if (open) {
      supabase.from('branches').select('id, name').order('name').then(({ data }) => setBranches(data || []))
      setMode(null); setError(null); setSuccess(null)
      setTargetBranch(''); setTargetCategory(''); setReason(''); setCustomReason(''); setUnavailableUntil('')
      setBookingFrom(''); setBookingTo(''); setBookingNote(''); setPriceField('all'); setPriceValue('')
    }
  }, [open])

  if (!open) return null

  const ids = selectedMotos.map(m => m.id)
  const count = ids.length

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  async function run(actionLabel, fn) {
    setBusy(true); setError(null); setSuccess(null)
    try {
      await fn()
      setSuccess(`${actionLabel} (${count} motorek)`)
      onUpdated?.()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function handleMigrate() {
    if (!targetBranch) { setError('Vyber pobočku'); return }
    const target = branches.find(b => b.id === targetBranch)
    await run(`Přesunuto na ${target?.name}`, async () => {
      const { error: err } = await supabase.from('motorcycles').update({ branch_id: targetBranch }).in('id', ids)
      if (err) throw err
      await logAudit('motorcycle_bulk_migrated', { count: ids.length, to_branch: target?.name, ids })
    })
  }

  async function handleSetCategory() {
    if (!targetCategory) { setError('Vyber kategorii'); return }
    await run(`Kategorie změněna`, async () => {
      const { error: err } = await supabase.from('motorcycles').update({ category: targetCategory }).in('id', ids)
      if (err) throw err
      await logAudit('motorcycle_bulk_category', { count: ids.length, category: targetCategory, ids })
    })
  }

  async function handleStatusChange(newStatus) {
    const today = new Date().toISOString().slice(0, 10)
    await run(`Stav: ${statusLabel(newStatus)}`, async () => {
      // Cancel active bookings if leaving operation
      if (newStatus !== 'active' && newStatus !== 'maintenance') {
        const { data: active } = await supabase.from('bookings').select('id').in('moto_id', ids)
          .eq('status', 'active').gte('end_date', today)
        if (active?.length > 0) {
          if (!window.confirm(`${active.length} aktivních pronájmů — stornovat všechny?`)) return
          await supabase.from('bookings').update({ status: 'cancelled', notes: `Hromadné vyřazení: ${reasonText() || newStatus}` })
            .in('id', active.map(b => b.id))
        }
      }
      const upd = { status: newStatus }
      if (newStatus === 'active') {
        upd.unavailable_until = null; upd.unavailable_reason = null; upd.last_service_date = today
        await supabase.from('maintenance_log').update({ completed_date: today, status: 'completed' })
          .in('moto_id', ids).is('completed_date', null)
        await supabase.from('service_orders').update({ status: 'completed', completed_at: new Date().toISOString() })
          .in('moto_id', ids).in('status', ['pending', 'in_service'])
      }
      if (newStatus === 'maintenance') {
        upd.unavailable_until = null; upd.unavailable_reason = null
      }
      if (newStatus === 'unavailable') {
        upd.unavailable_reason = reasonText() || null
        if (unavailableUntil) upd.unavailable_until = unavailableUntil
        else {
          const now = new Date()
          const maxYear = now.getMonth() <= 1 ? now.getFullYear() : now.getFullYear() + 1
          upd.unavailable_until = `${maxYear}-02-28T23:59:59`
        }
      }
      const { error: err } = await supabase.from('motorcycles').update(upd).in('id', ids)
      if (err) throw err
      await logAudit('motorcycle_bulk_status_changed', { count: ids.length, to_status: newStatus, reason: reasonText(), ids })
    })
  }

  async function handleSendToService() {
    const today = new Date().toISOString().slice(0, 10)
    await run('Odesláno do servisu', async () => {
      const { data: active } = await supabase.from('bookings').select('id').in('moto_id', ids)
        .eq('status', 'active').gte('end_date', today)
      if (active?.length > 0) {
        if (!window.confirm(`${active.length} aktivních pronájmů — stornovat všechny?`)) return
        await supabase.from('bookings').update({ status: 'cancelled', notes: 'Hromadné odeslání do servisu' })
          .in('id', active.map(b => b.id))
      }
      await supabase.from('motorcycles').update({ status: 'maintenance' }).in('id', ids)
      const description = bookingNote || 'Hromadné odeslání do servisu'
      const logs = ids.map(mid => ({
        moto_id: mid, description, service_type: 'extraordinary',
        service_date: today, scheduled_date: today,
        status: 'in_service', is_urgent: false, items: [],
      }))
      await supabase.from('maintenance_log').insert(logs)
      await logAudit('motorcycle_bulk_to_service', { count: ids.length, ids })
    })
  }

  async function handleBulkBook() {
    if (!bookingFrom || !bookingTo) { setError('Vyplň datum od a do'); return }
    if (bookingFrom > bookingTo) { setError('Začátek musí být před koncem'); return }
    await run('Motorky zablokovány na zvolené období', async () => {
      const today = new Date().toISOString().slice(0, 10)
      // Cancel active bookings overlapping the period
      const { data: active } = await supabase.from('bookings').select('id').in('moto_id', ids)
        .in('status', ['pending', 'reserved', 'active'])
        .lte('start_date', bookingTo).gte('end_date', bookingFrom)
      if (active?.length > 0) {
        if (!window.confirm(`${active.length} rezervací se překrývá. Stornovat všechny?`)) return
        await supabase.from('bookings').update({ status: 'cancelled', notes: `Hromadná blokace: ${bookingNote || bookingFrom + ' – ' + bookingTo}` })
          .in('id', active.map(b => b.id))
      }
      const upd = {
        status: 'unavailable',
        unavailable_until: `${bookingTo}T23:59:59`,
        unavailable_reason: bookingNote || `Blokace ${bookingFrom} – ${bookingTo}`,
      }
      // If blokace starts in future, only set unavailable_until + reason; status change happens auto on date
      if (bookingFrom > today) {
        // Just record reason + until — leave status as-is unless already unavailable
        const { error: err } = await supabase.from('motorcycles').update({
          unavailable_until: upd.unavailable_until,
          unavailable_reason: upd.unavailable_reason,
        }).in('id', ids)
        if (err) throw err
      } else {
        const { error: err } = await supabase.from('motorcycles').update(upd).in('id', ids)
        if (err) throw err
      }
      await logAudit('motorcycle_bulk_blocked', { count: ids.length, from: bookingFrom, to: bookingTo, note: bookingNote, ids })
    })
  }

  async function handlePriceUpdate() {
    const v = Number(priceValue)
    if (!priceValue || isNaN(v) || v < 0) { setError('Zadej platnou cenu'); return }
    await run('Cena aktualizována', async () => {
      const fields = priceField === 'all'
        ? ['price_mon', 'price_tue', 'price_wed', 'price_thu', 'price_fri', 'price_sat', 'price_sun']
        : [priceField]
      const upd = {}
      fields.forEach(f => { upd[f] = v })
      const { error: err } = await supabase.from('motorcycles').update(upd).in('id', ids)
      if (err) throw err
      await logAudit('motorcycle_bulk_price', { count: ids.length, fields, value: v, ids })
    })
  }

  function reasonText() {
    if (!reason) return null
    if (reason === 'other') return customReason || null
    return UNAVAILABLE_REASONS.find(r => r.value === reason)?.label || null
  }

  return (
    <Modal open={open} onClose={onClose} title={`Hromadná správa flotily (${count})`} wide>
      {success && <Banner color="#16a34a" bg="#dcfce7">{success}</Banner>}
      {error && <Banner color="#dc2626" bg="#fee2e2">{error}</Banner>}

      <div className="mb-4">
        <div className="text-sm font-bold mb-2" style={{ color: '#1a2e22' }}>Vybrané motorky:</div>
        <div className="flex flex-wrap gap-1.5 max-h-24 overflow-auto p-2 rounded-btn" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          {selectedMotos.map(m => (
            <span key={m.id} className="text-xs font-bold px-2 py-1 rounded-btn" style={{ background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
              {m.model} <span className="font-mono" style={{ color: '#6b7280' }}>{m.spz}</span>
            </span>
          ))}
        </div>
      </div>

      {!mode && (
        <div className="grid grid-cols-2 gap-3">
          <ModeBtn label="Přesunout na pobočku" desc="Změna branch_id pro všechny" onClick={() => setMode('migrate')} />
          <ModeBtn label="Změnit stav" desc="Aktivní / servis / vyřazené" onClick={() => setMode('status')} />
          <ModeBtn label="Odeslat do servisu" desc="Vytvoří servisní záznam" onClick={() => setMode('service')} />
          <ModeBtn label="Hromadná blokace" desc="Vytvoří interní rezervaci" onClick={() => setMode('book')} />
          <ModeBtn label="Aktualizovat cenu" desc="Cena/den, jeden nebo všechny dny" onClick={() => setMode('price')} />
          <ModeBtn label="Změnit kategorii" desc="Cestovní / sportovní / naked…" onClick={() => setMode('category')} />
        </div>
      )}

      {mode === 'migrate' && (
        <Section title="Přesunout na pobočku" onBack={() => setMode(null)}>
          <Select value={targetBranch} onChange={setTargetBranch}
            options={[{ value: '', label: '— vyber pobočku —' }, ...branches.map(b => ({ value: b.id, label: b.name }))]} />
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleMigrate} disabled={busy || !targetBranch}>{busy ? 'Pracuji…' : `Přesunout (${count})`}</Button>
          </div>
        </Section>
      )}

      {mode === 'status' && (
        <Section title="Změnit stav" onBack={() => setMode(null)}>
          <div className="grid grid-cols-2 gap-2 mb-3">
            <StatusBtn label="✅ Aktivní" color="#16a34a" onClick={() => handleStatusChange('active')} disabled={busy} />
            <StatusBtn label="🔧 V servisu" color="#f59e0b" onClick={() => handleStatusChange('maintenance')} disabled={busy} />
            <StatusBtn label="⏸ Dočasně vyřadit" color="#6b7280" onClick={() => handleStatusChange('unavailable')} disabled={busy} />
            <StatusBtn label="🚫 Trvale vyřadit" color="#dc2626" onClick={() => {
              if (window.confirm(`Trvale vyřadit ${count} motorek? Tato akce by měla být použita jen pro motorky, které už nebudou v provozu.`)) handleStatusChange('retired')
            }} disabled={busy} />
          </div>
          <div className="text-sm font-bold mb-1" style={{ color: '#1a2e22' }}>Důvod (pro dočasné vyřazení):</div>
          <Select value={reason} onChange={setReason}
            options={[{ value: '', label: '— bez důvodu —' }, ...UNAVAILABLE_REASONS.map(r => ({ value: r.value, label: r.label }))]} />
          {reason === 'other' && (
            <input className="mt-2 w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
              placeholder="Vlastní důvod" value={customReason} onChange={e => setCustomReason(e.target.value)} />
          )}
          <div className="text-sm font-bold mt-3 mb-1" style={{ color: '#1a2e22' }}>Vyřazeno do (volitelné):</div>
          <input type="datetime-local" value={unavailableUntil} onChange={e => setUnavailableUntil(e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </Section>
      )}

      {mode === 'service' && (
        <Section title="Odeslat všechny do servisu" onBack={() => setMode(null)}>
          <textarea placeholder="Popis servisu (volitelné)" value={bookingNote} onChange={e => setBookingNote(e.target.value)}
            className="w-full rounded-btn text-sm outline-none" rows={3}
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleSendToService} disabled={busy}>{busy ? 'Pracuji…' : `Odeslat do servisu (${count})`}</Button>
          </div>
        </Section>
      )}

      {mode === 'book' && (
        <Section title="Hromadná blokace (interní rezervace)" onBack={() => setMode(null)}>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Od</Label>
              <input type="date" value={bookingFrom} onChange={e => setBookingFrom(e.target.value)}
                className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            </div>
            <div>
              <Label>Do</Label>
              <input type="date" value={bookingTo} onChange={e => setBookingTo(e.target.value)}
                className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
            </div>
          </div>
          <div className="mt-3">
            <Label>Poznámka</Label>
            <input value={bookingNote} onChange={e => setBookingNote(e.target.value)}
              placeholder="Důvod blokace (event, focení, vlastní jízda…)"
              className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          </div>
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleBulkBook} disabled={busy || !bookingFrom || !bookingTo}>{busy ? 'Pracuji…' : `Vytvořit blokace (${count})`}</Button>
          </div>
        </Section>
      )}

      {mode === 'price' && (
        <Section title="Aktualizovat cenu/den" onBack={() => setMode(null)}>
          <Label>Pole ceny</Label>
          <Select value={priceField} onChange={setPriceField}
            options={[
              { value: 'all', label: 'Všechny dny (po–ne)' },
              { value: 'price_mon', label: 'Pondělí' },
              { value: 'price_tue', label: 'Úterý' },
              { value: 'price_wed', label: 'Středa' },
              { value: 'price_thu', label: 'Čtvrtek' },
              { value: 'price_fri', label: 'Pátek' },
              { value: 'price_sat', label: 'Sobota' },
              { value: 'price_sun', label: 'Neděle' },
            ]} />
          <Label className="mt-3">Nová cena (Kč)</Label>
          <input type="number" min="0" value={priceValue} onChange={e => setPriceValue(e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handlePriceUpdate} disabled={busy || !priceValue}>{busy ? 'Pracuji…' : `Nastavit cenu (${count})`}</Button>
          </div>
        </Section>
      )}

      {mode === 'category' && (
        <Section title="Změnit kategorii" onBack={() => setMode(null)}>
          <Select value={targetCategory} onChange={setTargetCategory}
            options={[{ value: '', label: '— vyber kategorii —' }, ...CATEGORIES]} />
          <div className="flex justify-end gap-2 mt-4">
            <Button onClick={() => setMode(null)}>Zpět</Button>
            <Button green onClick={handleSetCategory} disabled={busy || !targetCategory}>{busy ? 'Pracuji…' : `Nastavit (${count})`}</Button>
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

function statusLabel(s) {
  return ({ active: 'Aktivní', maintenance: 'V servisu', unavailable: 'Dočasně vyřazena', retired: 'Trvale vyřazena' })[s] || s
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

function ModeBtn({ label, desc, onClick }) {
  return (
    <button onClick={onClick} className="text-left rounded-card cursor-pointer transition-all hover:shadow"
      style={{ padding: 16, background: '#fff', border: '1px solid #d4e8e0' }}>
      <div className="font-extrabold uppercase tracking-wide text-sm" style={{ color: '#1a2e22' }}>{label}</div>
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

function Label({ children, className = '' }) {
  return <label className={`block text-sm font-extrabold uppercase tracking-wide mb-1 ${className}`} style={{ color: '#1a2e22' }}>{children}</label>
}

function Select({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="w-full rounded-btn text-sm outline-none cursor-pointer"
      style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}
