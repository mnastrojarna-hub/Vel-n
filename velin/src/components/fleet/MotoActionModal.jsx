import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../ui/Modal'
import Button from '../ui/Button'
import StatusBadge from '../ui/StatusBadge'
import ReplacementMotoPicker from './ReplacementMotoPicker'
import ServiceChecklistView from './ServiceChecklistView'
import { UNAVAILABLE_REASONS } from './motoActionConstants'

export default function MotoActionModal({ open, onClose, moto, onUpdated }) {
  const [branches, setBranches] = useState([])
  const [selectedBranch, setSelectedBranch] = useState('')
  const [reason, setReason] = useState('')
  const [customReason, setCustomReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(null)
  const [showChecklist, setShowChecklist] = useState(false)
  const [showReplacement, setShowReplacement] = useState(false)
  const [pendingLogId, setPendingLogId] = useState(null)
  const [unavailableUntil, setUnavailableUntil] = useState('')

  useEffect(() => {
    if (open) {
      supabase.from('branches').select('id, name').eq('active', true).order('name')
        .then(({ data }) => setBranches(data || []))
      setSelectedBranch(''); setReason(''); setCustomReason(''); setError(null); setSuccess(null)
      setShowChecklist(false); setShowReplacement(false); setPendingLogId(null); setUnavailableUntil('')
    }
  }, [open, moto?.id])

  if (!open || !moto) return null

  async function logAudit(action, details) {
    try { const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  async function handleMigrate() {
    if (!selectedBranch) return
    setBusy(true); setError(null)
    try {
      const target = branches.find(b => b.id === selectedBranch)
      const { error: err } = await supabase.from('motorcycles').update({ branch_id: selectedBranch }).eq('id', moto.id)
      if (err) throw err
      await logAudit('motorcycle_migrated', { moto_id: moto.id, from_branch: moto.branches?.name, to_branch: target?.name })
      setSuccess(`Přesunuto na ${target?.name}`); onUpdated?.()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function handleSendToService({ selected, selectedLabels, fullDescription, isUrgent, serviceDateFrom, serviceDateTo }) {
    setBusy(true); setError(null)
    try {
      const today = new Date().toISOString().slice(0, 10)
      // Check active bookings
      const { data: active } = await supabase.from('bookings').select('id, status').eq('moto_id', moto.id).eq('status', 'active').gte('end_date', today)
      if (active?.length > 0) {
        if (!window.confirm(`Motorka má ${active.length} aktivní pronájem. Stornovat?`)) { setBusy(false); return }
        for (const b of active) await supabase.from('bookings').update({ status: 'cancelled', notes: 'Motorka do servisu' }).eq('id', b.id)
      }
      // Info future reservations
      const { data: future } = await supabase.from('bookings').select('id, start_date, end_date').eq('moto_id', moto.id).eq('status', 'reserved').gte('end_date', today).order('start_date').limit(5)
      if (future?.length > 0) {
        const lines = future.map(b => `  ${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}`).join('\n')
        window.alert(`Upozornění — budoucí rezervace (${future.length}):\n${lines}\nMotorka musí být ze servisu zpět včas.`)
      }

      await supabase.from('motorcycles').update({ status: 'maintenance' }).eq('id', moto.id)
      const { data: logData, error: logErr } = await supabase.from('maintenance_log').insert({
        moto_id: moto.id, description: fullDescription, service_type: 'extraordinary',
        service_date: serviceDateFrom || today, scheduled_date: serviceDateTo || serviceDateFrom || today,
        km_at_service: Number(moto.mileage) || null, status: 'in_service', is_urgent: isUrgent,
        items: selectedLabels.map(label => ({ label, done: false, note: '' })),
      }).select('id').single()
      if (logErr) setError(`Záznam: ${logErr.message}`)
      await logAudit('motorcycle_status_changed', { moto_id: moto.id, to_status: 'maintenance', is_urgent: isUrgent, checklist: selected })

      // >3 days in season on samoobslužná → replacement
      const days = serviceDateTo && serviceDateFrom ? Math.ceil((new Date(serviceDateTo) - new Date(serviceDateFrom)) / 86400000) : 0
      const month = new Date().getMonth()
      if (days > 3 && month >= 3 && month <= 9 && moto.branch_id && moto.branches?.type === 'samoobslužná') {
        setPendingLogId(logData?.id); setShowReplacement(true); setShowChecklist(false); setBusy(false); return
      }
      setSuccess('Motorka odeslána do servisu'); onUpdated?.()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function handleStatusChange(newStatus) {
    setBusy(true); setError(null)
    try {
      const today = new Date().toISOString().slice(0, 10)
      if (newStatus !== 'active' && newStatus !== 'maintenance') {
        const { data: active } = await supabase.from('bookings').select('id').eq('moto_id', moto.id).eq('status', 'active').gte('end_date', today)
        if (active?.length > 0) {
          if (!window.confirm(`Motorka má ${active.length} pronájem. Stornovat?`)) { setBusy(false); return }
          for (const b of active) await supabase.from('bookings').update({ status: 'cancelled', notes: `Nedostupná: ${reason || newStatus}` }).eq('id', b.id)
        }
        const { data: future } = await supabase.from('bookings').select('id, start_date, end_date, profiles(full_name)').eq('moto_id', moto.id).in('status', ['pending', 'reserved']).gte('start_date', today).order('start_date').limit(5)
        if (future?.length > 0) {
          const lines = future.map(b => `  ${b.profiles?.full_name || '?'}: ${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}`).join('\n')
          window.alert(`Nadcházející rezervace (${future.length}):\n${lines}`)
        }
      }
      const upd = { status: newStatus }
      if (newStatus === 'active') { upd.last_service_date = today; upd.unavailable_until = null }
      if (newStatus === 'out_of_service' && unavailableUntil) upd.unavailable_until = unavailableUntil
      await supabase.from('motorcycles').update(upd).eq('id', moto.id)
      const reasonText = reason === 'other' ? customReason : UNAVAILABLE_REASONS.find(r => r.value === reason)?.label
      await logAudit('motorcycle_status_changed', { moto_id: moto.id, from_status: moto.status, to_status: newStatus, reason: reasonText || null, unavailable_until: unavailableUntil || null })
      const labels = { active: 'Aktivní', maintenance: 'Servis', out_of_service: 'Vyřazeno', retired: 'Vyřazena trvale' }
      setSuccess(`Stav: ${labels[newStatus] || newStatus}${unavailableUntil ? ` (do ${new Date(unavailableUntil).toLocaleString('cs-CZ')})` : ''}`)
      onUpdated?.()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function handleDeactivateReplace(replacement) {
    setBusy(true)
    if (moto.branch_id && replacement?.id) {
      await supabase.from('motorcycles').update({ branch_id: moto.branch_id, status: 'active' }).eq('id', replacement.id)
    }
    await supabase.from('motorcycles').update({ status: 'out_of_service' }).eq('id', moto.id)
    await logAudit('moto_deactivated_replaced', { moto_id: moto.id, replacement_id: replacement?.id, branch_id: moto.branch_id })
    setBusy(false); setSuccess('Deaktivováno, náhrada přiřazena'); onUpdated?.()
  }

  const isActive = moto.status === 'active'
  const isMaintenance = moto.status === 'maintenance'
  const isOut = moto.status === 'out_of_service' || moto.status === 'unavailable'
  const [showDeactReplace, setShowDeactReplace] = useState(false)

  return (
    <Modal open={open} onClose={showChecklist ? () => setShowChecklist(false) : onClose}
      title={showChecklist ? `${moto.model} — Servisní checklist` : `${moto.model} — Správa`} wide>

      {showChecklist ? (
        <ServiceChecklistView moto={moto} onConfirm={handleSendToService} onBack={() => setShowChecklist(false)} busy={busy} error={error} />
      ) : showReplacement ? (
        <div className="p-3 rounded-lg" style={{ background: '#fef3c7', border: '1px solid #fde68a' }}>
          <div className="text-sm font-bold mb-2" style={{ color: '#b45309' }}>Servis &gt;3 dny v sezóně — vyberte náhradu na {moto.branches?.name || '—'}:</div>
          <ReplacementMotoPicker branchId={moto.branch_id} excludeMotoId={moto.id}
            onSelect={async (r) => { if (r?.id && moto.branch_id) { await supabase.from('motorcycles').update({ branch_id: moto.branch_id, status: 'active' }).eq('id', r.id); if (pendingLogId) await supabase.from('maintenance_log').update({ replacement_moto_id: r.id }).eq('id', pendingLogId); await logAudit('moto_replaced_long_service', { moto_id: moto.id, replacement_id: r.id }) }; setShowReplacement(false); setSuccess('Motorka v servisu, náhrada přiřazena'); onUpdated?.() }}
            onCancel={() => { setShowReplacement(false); setSuccess('Motorka v servisu (bez náhrady)'); onUpdated?.() }} />
        </div>
      ) : showDeactReplace ? (
        <div className="p-3 rounded-lg" style={{ background: '#ede9fe', border: '1px solid #c4b5fd' }}>
          <div className="text-sm font-bold mb-2" style={{ color: '#7c3aed' }}>Deaktivovat {moto.model} — vyberte náhradu:</div>
          <ReplacementMotoPicker branchId={moto.branch_id} excludeMotoId={moto.id}
            onSelect={handleDeactivateReplace} onCancel={() => setShowDeactReplace(false)} />
        </div>
      ) : (
        <>
          {success && <div className="mb-4 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>{success}</div>}
          {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

          <div className="flex items-center gap-3 mb-5 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{moto.model}</span>
            <span className="font-mono text-sm" style={{ color: '#1a2e22' }}>{moto.spz}</span>
            <StatusBadge status={moto.status} />
            {moto.branches?.name && <span className="text-sm ml-auto" style={{ color: '#1a2e22' }}>Pobočka: <b>{moto.branches.name}</b></span>}
          </div>

          {/* Přesun */}
          <div className="mb-5">
            <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>Přesunout na pobočku</h3>
            <div className="flex items-center gap-2">
              <select value={selectedBranch} onChange={e => setSelectedBranch(e.target.value)} className="flex-1 rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                <option value="">— Vyberte cílovou pobočku —</option>
                {branches.filter(b => b.id !== moto.branch_id).map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
              <Button green onClick={handleMigrate} disabled={!selectedBranch || busy}>{busy ? 'Přesouvám…' : 'Přesunout'}</Button>
            </div>
          </div>
          <hr style={{ border: 'none', borderTop: '1px solid #d4e8e0', margin: '20px 0' }} />

          {/* Stavy */}
          <div>
            <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>Změnit stav motorky</h3>
            <div className="grid grid-cols-2 gap-3">
              {!isActive && <StatusBtn color="#1a8a18" bg="#dcfce7" onClick={() => handleStatusChange('active')} disabled={busy}
                title="Vrátit do provozu" desc="Motorka bude opět k dispozici pro zákazníky" />}
              {!isMaintenance && <StatusBtn color="#b45309" bg="#fef3c7" onClick={() => setShowChecklist(true)} disabled={busy}
                title="Odeslat do servisu" desc="Otevře checklist závad a údržby" />}
              {!isOut && <StatusBtn color="#7c3aed" bg="#ede9fe" onClick={() => { if (reason) handleStatusChange('out_of_service') }} disabled={busy || !reason}
                title="Dočasně vyřadit" desc="Čištění, tankování, přeprava — vyberte důvod níže" />}
              {moto.status !== 'retired' && <StatusBtn color="#1a2e22" bg="#f3f4f6" onClick={() => { if (window.confirm('Opravdu trvale vyřadit?')) handleStatusChange('retired') }} disabled={busy}
                title="Trvale vyřadit" desc="Motorka bude označena jako vyřazena z flotily" />}
              {moto.branch_id && <StatusBtn color="#7c3aed" bg="#ede9fe" onClick={() => setShowDeactReplace(true)} disabled={busy}
                title="Deaktivovat + nahradit" desc="Vyřadit a přiřadit jinou motorku na pobočku" />}
            </div>
            {/* Důvod dočasného vyřazení */}
            {!isOut && <UnavailableReasonPicker reason={reason} setReason={setReason} customReason={customReason} setCustomReason={setCustomReason} unavailableUntil={unavailableUntil} setUnavailableUntil={setUnavailableUntil} />}
          </div>
          <div className="flex justify-end mt-5"><Button onClick={onClose}>Zavřít</Button></div>
        </>
      )}
    </Modal>
  )
}

function StatusBtn({ color, bg, onClick, disabled, title, desc }) {
  return (
    <button onClick={onClick} disabled={disabled} className="p-3 rounded-lg text-left cursor-pointer"
      style={{ background: bg, border: `2px solid ${color}`, opacity: disabled ? 0.5 : 1 }}>
      <div className="text-sm font-extrabold mb-1" style={{ color }}>{title}</div>
      <div className="text-sm" style={{ color: '#1a2e22' }}>{desc}</div>
    </button>
  )
}

function UnavailableReasonPicker({ reason, setReason, customReason, setCustomReason, unavailableUntil, setUnavailableUntil }) {
  return (
    <div className="mt-4">
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Důvod dočasného vyřazení</label>
      <div className="flex flex-wrap gap-2">
        {UNAVAILABLE_REASONS.map(r => (
          <button key={r.value} onClick={() => setReason(r.value)} className="rounded-btn text-sm font-bold cursor-pointer"
            style={{ padding: '6px 12px', border: 'none', background: reason === r.value ? '#7c3aed' : '#f1faf7', color: reason === r.value ? '#fff' : '#1a2e22' }}>
            {r.label}
          </button>
        ))}
      </div>
      {reason === 'other' && <input value={customReason} onChange={e => setCustomReason(e.target.value)} placeholder="Zadejte důvod…"
        className="w-full mt-2 rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />}
      {reason && (
        <div className="mt-3">
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Nedostupná do</label>
          <input type="datetime-local" value={unavailableUntil} onChange={e => setUnavailableUntil(e.target.value)}
            min={new Date().toISOString().slice(0, 16)} className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#ede9fe', border: '1px solid #c4b5fd' }} />
          <div className="text-sm mt-1" style={{ color: '#7c3aed' }}>
            {unavailableUntil ? `Auto-návrat ${new Date(unavailableUntil).toLocaleString('cs-CZ')}` : 'Nastavte čas auto-návratu do provozu'}
          </div>
        </div>
      )}
    </div>
  )
}
