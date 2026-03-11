import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../ui/Modal'
import Button from '../ui/Button'
import StatusBadge from '../ui/StatusBadge'

const UNAVAILABLE_REASONS = [
  { value: 'cleaning', label: 'Čištění / mytí' },
  { value: 'refueling', label: 'Tankování' },
  { value: 'transport', label: 'Přeprava mezi pobočkami' },
  { value: 'inspection', label: 'Kontrola / STK' },
  { value: 'photo', label: 'Focení / marketing' },
  { value: 'other', label: 'Jiný důvod' },
]

export default function MotoActionModal({ open, onClose, moto, onUpdated }) {
  const [branches, setBranches] = useState([])
  const [selectedBranch, setSelectedBranch] = useState('')
  const [reason, setReason] = useState('')
  const [customReason, setCustomReason] = useState('')
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(null)

  useEffect(() => {
    if (open) {
      supabase.from('branches').select('id, name').eq('active', true).order('name')
        .then(({ data }) => setBranches(data || []))
      setSelectedBranch('')
      setReason('')
      setCustomReason('')
      setNote('')
      setError(null)
      setSuccess(null)
    }
  }, [open, moto?.id])

  if (!open || !moto) return null

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  async function handleMigrate() {
    if (!selectedBranch) return
    setBusy(true); setError(null)
    try {
      const target = branches.find(b => b.id === selectedBranch)
      const { error: err } = await supabase.from('motorcycles')
        .update({ branch_id: selectedBranch }).eq('id', moto.id)
      if (err) throw err
      await logAudit('motorcycle_migrated', {
        moto_id: moto.id, model: moto.model,
        from_branch: moto.branches?.name || '—', to_branch: target?.name,
      })
      setSuccess(`Přesunuto na pobočku ${target?.name}`)
      onUpdated?.()
    } catch (e) {
      setError(e.message)
    } finally { setBusy(false) }
  }

  async function handleStatusChange(newStatus) {
    setBusy(true); setError(null)
    try {
      // Check active bookings before deactivating
      if (newStatus !== 'active' && newStatus !== 'maintenance') {
        const { data: activeBookings } = await supabase.from('bookings')
          .select('id').eq('moto_id', moto.id).in('status', ['pending', 'active', 'reserved'])
        if (activeBookings?.length > 0) {
          const ok = window.confirm(`Motorka má ${activeBookings.length} aktivní/ch rezervací. Při změně stavu budou stornovány. Pokračovat?`)
          if (!ok) { setBusy(false); return }
          for (const b of activeBookings) {
            await supabase.from('bookings').update({ status: 'cancelled', notes: `Motorka dočasně nedostupná: ${reason || newStatus}` }).eq('id', b.id)
          }
        }
      }

      const updateData = { status: newStatus }
      if (newStatus === 'active') updateData.last_service_date = new Date().toISOString().slice(0, 10)

      const { error: err } = await supabase.from('motorcycles').update(updateData).eq('id', moto.id)
      if (err) throw err

      // If sending to maintenance, create maintenance_log entry
      if (newStatus === 'maintenance' && note) {
        await supabase.from('maintenance_log').insert({
          moto_id: moto.id, description: note,
          service_type: 'Neplánovaný servis',
        })
      }

      const reasonText = reason === 'other' ? customReason : UNAVAILABLE_REASONS.find(r => r.value === reason)?.label
      await logAudit('motorcycle_status_changed', {
        moto_id: moto.id, model: moto.model,
        from_status: moto.status, to_status: newStatus,
        reason: reasonText || note || null,
      })

      const labels = { active: 'Aktivní', maintenance: 'Servis', out_of_service: 'Vyřazeno', unavailable: 'Nedostupná', retired: 'Vyřazena trvale' }
      setSuccess(`Stav změněn na: ${labels[newStatus] || newStatus}`)
      onUpdated?.()
    } catch (e) {
      setError(e.message)
    } finally { setBusy(false) }
  }

  const isActive = moto.status === 'active'
  const isMaintenance = moto.status === 'maintenance'
  const isOutOfService = moto.status === 'out_of_service' || moto.status === 'unavailable'

  return (
    <Modal open={open} onClose={onClose} title={`${moto.model} — Správa`} wide>
      {success && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>
          {success}
        </div>
      )}
      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
        </div>
      )}

      <div className="flex items-center gap-3 mb-5 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{moto.model}</span>
        <span className="font-mono text-sm" style={{ color: '#1a2e22' }}>{moto.spz}</span>
        <StatusBadge status={moto.status} />
        {moto.branches?.name && <span className="text-sm ml-auto" style={{ color: '#1a2e22' }}>Pobočka: <b style={{ color: '#0f1a14' }}>{moto.branches.name}</b></span>}
      </div>

      {/* Section: Přesun na pobočku */}
      <div className="mb-5">
        <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>Přesunout na pobočku</h3>
        <div className="flex items-center gap-2">
          <select value={selectedBranch} onChange={e => setSelectedBranch(e.target.value)}
            className="flex-1 rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
            <option value="">— Vyberte cílovou pobočku —</option>
            {branches.filter(b => b.id !== moto.branch_id).map(b => (
              <option key={b.id} value={b.id}>{b.name}</option>
            ))}
          </select>
          <Button green onClick={handleMigrate} disabled={!selectedBranch || busy}>
            {busy ? 'Přesouvám…' : 'Přesunout'}
          </Button>
        </div>
      </div>

      <hr style={{ border: 'none', borderTop: '1px solid #d4e8e0', margin: '20px 0' }} />

      {/* Section: Změna stavu */}
      <div>
        <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>Změnit stav motorky</h3>

        <div className="grid grid-cols-2 gap-3">
          {/* Vrátit do provozu */}
          {!isActive && (
            <button onClick={() => handleStatusChange('active')} disabled={busy}
              className="p-3 rounded-lg text-left cursor-pointer transition-colors"
              style={{ background: '#dcfce7', border: '2px solid #1a8a18', opacity: busy ? 0.5 : 1 }}>
              <div className="text-sm font-extrabold mb-1" style={{ color: '#1a8a18' }}>Vrátit do provozu</div>
              <div className="text-sm" style={{ color: '#1a2e22' }}>Motorka bude opět k dispozici pro zákazníky</div>
            </button>
          )}

          {/* Do servisu */}
          {!isMaintenance && (
            <button onClick={() => { if (!note) { document.getElementById('moto-action-note')?.focus(); return }; handleStatusChange('maintenance') }} disabled={busy}
              className="p-3 rounded-lg text-left cursor-pointer transition-colors"
              style={{ background: '#fef3c7', border: '2px solid #b45309', opacity: busy ? 0.5 : 1 }}>
              <div className="text-sm font-extrabold mb-1" style={{ color: '#b45309' }}>Odeslat do servisu</div>
              <div className="text-sm" style={{ color: '#1a2e22' }}>Vytvoří servisní záznam, motorka bude nedostupná</div>
            </button>
          )}

          {/* Dočasně vyřadit */}
          {!isOutOfService && (
            <button onClick={() => { if (!reason) return; handleStatusChange('out_of_service') }} disabled={busy || !reason}
              className="p-3 rounded-lg text-left cursor-pointer transition-colors"
              style={{ background: '#ede9fe', border: '2px solid #7c3aed', opacity: (busy || !reason) ? 0.5 : 1 }}>
              <div className="text-sm font-extrabold mb-1" style={{ color: '#7c3aed' }}>Dočasně vyřadit</div>
              <div className="text-sm" style={{ color: '#1a2e22' }}>Čištění, tankování, přeprava — vyberte důvod níže</div>
            </button>
          )}

          {/* Trvale vyřadit */}
          {moto.status !== 'retired' && (
            <button onClick={() => { if (window.confirm('Opravdu trvale vyřadit motorku?')) handleStatusChange('retired') }} disabled={busy}
              className="p-3 rounded-lg text-left cursor-pointer transition-colors"
              style={{ background: '#f3f4f6', border: '2px solid #6b7280', opacity: busy ? 0.5 : 1 }}>
              <div className="text-sm font-extrabold mb-1" style={{ color: '#1a2e22' }}>Trvale vyřadit</div>
              <div className="text-sm" style={{ color: '#1a2e22' }}>Motorka bude označena jako vyřazena z flotily</div>
            </button>
          )}
        </div>

        {/* Důvod dočasného vyřazení */}
        {!isOutOfService && (
          <div className="mt-4">
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Důvod dočasného vyřazení</label>
            <div className="flex flex-wrap gap-2">
              {UNAVAILABLE_REASONS.map(r => (
                <button key={r.value} onClick={() => setReason(r.value)}
                  className="rounded-btn text-sm font-bold cursor-pointer"
                  style={{
                    padding: '6px 12px', border: 'none',
                    background: reason === r.value ? '#7c3aed' : '#f1faf7',
                    color: reason === r.value ? '#fff' : '#1a2e22',
                  }}>
                  {r.label}
                </button>
              ))}
            </div>
            {reason === 'other' && (
              <input value={customReason} onChange={e => setCustomReason(e.target.value)}
                placeholder="Zadejte důvod…"
                className="w-full mt-2 rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
            )}
          </div>
        )}

        {/* Poznámka k servisu */}
        {!isMaintenance && (
          <div className="mt-4">
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Poznámka / popis závady (pro servis)</label>
            <textarea id="moto-action-note" value={note} onChange={e => setNote(e.target.value)}
              placeholder="Popište důvod servisu, závadu, poznámku…"
              className="w-full rounded-btn text-sm outline-none"
              rows={2}
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14', resize: 'vertical' }} />
          </div>
        )}
      </div>

      <div className="flex justify-end mt-5">
        <Button onClick={onClose}>Zavřít</Button>
      </div>
    </Modal>
  )
}
