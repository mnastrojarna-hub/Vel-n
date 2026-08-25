import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { purgeWebCache } from '../../lib/webCache'
import Modal from '../ui/Modal'
import Button from '../ui/Button'
import ReplacementMotoPicker from './ReplacementMotoPicker'
import ServiceChecklistView from './ServiceChecklistView'
import { UNAVAILABLE_REASONS } from './motoActionConstants'
import MotoStatusPanel from './MotoStatusPanel'
import { fetchBlockingBookings, fetchActiveBookings, blockingBookingsMessage } from './bookingGuard'

export default function MotoActionModal({ open, onClose, moto, onUpdated }) {
  const [branches, setBranches] = useState([])
  const [selectedBranch, setSelectedBranch] = useState('')
  const [reason, setReason] = useState('')
  const [customReason, setCustomReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(null)
  const [showChecklist, setShowChecklist] = useState(false)
  // Checklist má dva režimy: úprava otevřeného záznamu vs. NOVÝ servis.
  // Režim nesmí být odvozen z hasOpenLogs — motorka může mít otevřený záznam
  // (např. zimní odstávku) a přesto potřebuje přidat další servis.
  const [checklistEdit, setChecklistEdit] = useState(false)
  const [showReplacement, setShowReplacement] = useState(false)
  const [pendingLogId, setPendingLogId] = useState(null)
  const [unavailableUntil, setUnavailableUntil] = useState('')
  const [showDeactReplace, setShowDeactReplace] = useState(false)
  const [openLogs, setOpenLogs] = useState([])

  useEffect(() => {
    if (open && moto?.id) {
      supabase.from('branches').select('id, name, type, active').order('name')
        .then(({ data }) => setBranches(data || []))
      // Check for open maintenance_log entries
      supabase.from('maintenance_log').select('id, description, service_date, scheduled_date, status, items, is_urgent')
        .eq('moto_id', moto.id).is('completed_date', null)
        .then(({ data }) => setOpenLogs(data || []))
      setSelectedBranch(''); setReason(''); setCustomReason(''); setError(null); setSuccess(null)
      setShowChecklist(false); setChecklistEdit(false); setShowReplacement(false); setShowDeactReplace(false); setPendingLogId(null); setUnavailableUntil('')
    }
  }, [open, moto?.id])

  if (!open || !moto) return null

  const isSamoobsluzna = moto.branches?.type === 'samoobslužná'

  async function logAudit(action, details) {
    try { const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  // Po úspěšné změně motorky zneplatni cache webu (jinak katalog drží starý
  // stav až 30 min) a teprve pak refetchni Velín.
  const refresh = () => { purgeWebCache(); onUpdated?.() }

  async function handleMigrate() {
    if (!selectedBranch) return
    setBusy(true); setError(null)
    try {
      const target = branches.find(b => b.id === selectedBranch)
      const { error: err } = await supabase.from('motorcycles').update({ branch_id: selectedBranch }).eq('id', moto.id)
      if (err) throw err
      await logAudit('motorcycle_migrated', { moto_id: moto.id, from_branch: moto.branches?.name, to_branch: target?.name })
      setSuccess(`Přesunuto na ${target?.name}`); refresh()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function handleSendToService({ selected, selectedLabels, fullDescription, isUrgent, serviceDateFrom, serviceDateTo }) {
    setBusy(true); setError(null)
    try {
      const today = new Date().toISOString().slice(0, 10)
      const serviceStart = serviceDateFrom || today
      // Servis naplánovaný na budoucí den NESMÍ motorku vyřadit už dnes — status
      // na 'maintenance' a stornování aktuálních pronájmů řešíme jen když servis
      // začíná dnes (nebo dříve). Záznam je pak 'pending' až do dne servisu.
      const isFuture = serviceStart > today
      if (!isFuture) {
        // Probíhající pronájem se NESMÍ rušit — motorku, na které někdo právě jede,
        // nelze poslat do servisu. Admin musí pronájem nejdřív vyřešit individuálně
        // (úprava rezervace dle dohody se zákazníkem).
        const active = await fetchActiveBookings(moto.id)
        if (active.length > 0) {
          window.alert(blockingBookingsMessage(active))
          setBusy(false); return
        }
      }
      const { data: future } = await supabase.from('bookings').select('id, start_date, end_date').eq('moto_id', moto.id).eq('status', 'reserved').gte('end_date', serviceStart).order('start_date').limit(5)
      if (future?.length > 0) {
        const lines = future.map(b => `  ${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}`).join('\n')
        window.alert(`Upozornění — budoucí rezervace (${future.length}):\n${lines}\nMotorka musí být ze servisu zpět včas.`)
      }
      if (!isFuture) await supabase.from('motorcycles').update({ status: 'maintenance' }).eq('id', moto.id)
      const { data: logData, error: logErr } = await supabase.from('maintenance_log').insert({
        moto_id: moto.id, description: fullDescription, service_type: 'extraordinary',
        service_date: serviceStart, scheduled_date: serviceDateTo || serviceStart,
        km_at_service: Number(moto.mileage) || null, status: isFuture ? 'pending' : 'in_service', is_urgent: isUrgent,
        items: selectedLabels.map(label => ({ label, done: false, note: '' })),
      }).select('id').single()
      if (logErr) setError(`Záznam: ${logErr.message}`)
      await supabase.from('service_orders').insert({
        moto_id: moto.id, type: fullDescription, notes: selectedLabels.join(', '),
        status: isFuture ? 'pending' : 'in_service', maintenance_log_id: logData?.id,
      })
      await logAudit('motorcycle_status_changed', { moto_id: moto.id, to_status: 'maintenance', is_urgent: isUrgent, checklist: selected })

      const days = serviceDateTo && serviceDateFrom ? Math.ceil((new Date(serviceDateTo) - new Date(serviceDateFrom)) / 86400000) : 0
      const month = new Date().getMonth()
      if (days > 3 && month >= 3 && month <= 9 && moto.branch_id && isSamoobsluzna) {
        setPendingLogId(logData?.id); setShowReplacement(true); setShowChecklist(false); setBusy(false); return
      }
      setSuccess('Motorka odeslána do servisu'); refresh()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  // Update existing maintenance_log entry (edit mode)
  async function handleUpdateService({ selectedLabels, fullDescription, isUrgent, serviceDateFrom, serviceDateTo }) {
    const logToUpdate = openLogs[0]
    if (!logToUpdate) return
    setBusy(true); setError(null)
    try {
      const today = new Date().toISOString().slice(0, 10)
      await supabase.from('maintenance_log').update({
        description: fullDescription,
        service_date: serviceDateFrom || today,
        scheduled_date: serviceDateTo || serviceDateFrom || today,
        is_urgent: isUrgent,
        items: selectedLabels.map(label => ({ label, done: false, note: '' })),
      }).eq('id', logToUpdate.id)
      await logAudit('maintenance_log_updated', { log_id: logToUpdate.id, moto_id: moto.id })
      setShowChecklist(false)
      setSuccess('Servisní plán aktualizován'); refresh()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  // Close open maintenance logs + set status active
  async function handleCloseServiceAndActivate() {
    setBusy(true); setError(null)
    try {
      const today = new Date().toISOString().slice(0, 10)
      await supabase.from('maintenance_log').update({ completed_date: today, status: 'completed' })
        .eq('moto_id', moto.id).is('completed_date', null)
      await supabase.from('service_orders').update({ status: 'completed', completed_at: new Date().toISOString() })
        .eq('moto_id', moto.id).in('status', ['pending', 'in_service'])
      await supabase.from('motorcycles').update({ status: 'active', last_service_date: today }).eq('id', moto.id)
      await logAudit('motorcycle_service_closed', { moto_id: moto.id, open_logs: openLogs.length })
      setSuccess('Servis ukončen, motorka aktivní'); refresh()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function handleStatusChange(newStatus) {
    setBusy(true); setError(null)
    try {
      const today = new Date().toISOString().slice(0, 10)
      if (newStatus !== 'active' && newStatus !== 'maintenance') {
        // Vyřazení (dočasné/trvalé) NESMÍ rušit rezervace. Pokud má motorka
        // aktivní/nadcházející/pending rezervaci, akci zablokuj — admin ji vyřeší
        // individuálně (úprava rezervace dle dohody se zákazníkem).
        const blocking = await fetchBlockingBookings(moto.id)
        if (blocking.length > 0) {
          window.alert(blockingBookingsMessage(blocking))
          setBusy(false); return
        }
      }
      const upd = { status: newStatus }
      if (newStatus === 'active') {
        upd.last_service_date = today; upd.unavailable_until = null; upd.unavailable_reason = null
        // Check for open maintenance logs — warn before closing them
        const { data: openSvcLogs } = await supabase.from('maintenance_log').select('id, description, items')
          .eq('moto_id', moto.id).is('completed_date', null)
        if (openSvcLogs?.length > 0) {
          const itemCount = openSvcLogs.reduce((sum, l) => sum + (l.items?.length || 0), 0)
          if (!window.confirm(`Motorka má ${openSvcLogs.length} otevřený servisní záznam (${itemCount} úkonů). Vrácením do provozu se všechny záznamy uzavřou.\n\nPokud chcete zachovat servisní záznamy, použijte „Vrátit do servisu".\n\nPokračovat a uzavřít záznamy?`)) {
            setBusy(false); return
          }
        }
        // Close open maintenance logs + service orders
        await supabase.from('maintenance_log').update({ completed_date: today, status: 'completed' })
          .eq('moto_id', moto.id).is('completed_date', null)
        await supabase.from('service_orders').update({ status: 'completed', completed_at: new Date().toISOString() })
          .eq('moto_id', moto.id).in('status', ['pending', 'in_service'])
      }
      if (newStatus === 'maintenance') {
        upd.unavailable_until = null; upd.unavailable_reason = null
        // Preserve existing maintenance_log entries — do NOT modify them
      }
      if (newStatus === 'unavailable') {
        const reasonText = reason === 'other' ? customReason : UNAVAILABLE_REASONS.find(r => r.value === reason)?.label
        upd.unavailable_reason = reasonText || null
        if (unavailableUntil) {
          upd.unavailable_until = unavailableUntil
        } else {
          // Max do 28.2. následujícího roku
          const now = new Date()
          const maxYear = now.getMonth() <= 1 ? now.getFullYear() : now.getFullYear() + 1
          upd.unavailable_until = `${maxYear}-02-28T23:59:59`
        }
      }
      await supabase.from('motorcycles').update(upd).eq('id', moto.id)
      const reasonText = reason === 'other' ? customReason : UNAVAILABLE_REASONS.find(r => r.value === reason)?.label
      await logAudit('motorcycle_status_changed', { moto_id: moto.id, from_status: moto.status, to_status: newStatus, reason: reasonText || null })
      const labels = { active: 'Aktivní', maintenance: 'V servisu', unavailable: 'Dočasně vyřazena', retired: 'Trvale vyřazena' }
      setSuccess(`Stav: ${labels[newStatus] || newStatus}${unavailableUntil ? ` (do ${new Date(unavailableUntil).toLocaleString('cs-CZ')})` : ''}`)
      refresh()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  async function handleDeactivateReplace(replacement) {
    // Deaktivace NESMÍ osiřet zákaznickou rezervaci — pokud nějaká existuje,
    // admin ji vyřeší individuálně (úprava rezervace) ještě před deaktivací.
    const blocking = await fetchBlockingBookings(moto.id)
    if (blocking.length > 0) {
      window.alert(blockingBookingsMessage(blocking))
      setShowDeactReplace(false)
      return
    }
    setBusy(true)
    if (moto.branch_id && replacement?.id) {
      await supabase.from('motorcycles').update({ branch_id: moto.branch_id, status: 'active' }).eq('id', replacement.id)
    }
    const now = new Date()
    const maxYear = now.getMonth() <= 1 ? now.getFullYear() : now.getFullYear() + 1
    const reasonText = reason === 'other' ? customReason : UNAVAILABLE_REASONS.find(r => r.value === reason)?.label
    await supabase.from('motorcycles').update({
      status: 'unavailable',
      unavailable_reason: reasonText || 'Deaktivováno — náhrada',
      unavailable_until: unavailableUntil || `${maxYear}-02-28T23:59:59`,
    }).eq('id', moto.id)
    await logAudit('moto_deactivated_replaced', { moto_id: moto.id, replacement_id: replacement?.id, branch_id: moto.branch_id })
    setBusy(false); setSuccess('Deaktivováno, náhrada přiřazena'); refresh()
  }

  async function handleDeactivateSimple() {
    // Deaktivace NESMÍ osiřet zákaznickou rezervaci — pokud nějaká existuje,
    // admin ji vyřeší individuálně (úprava rezervace) ještě před deaktivací.
    const blocking = await fetchBlockingBookings(moto.id)
    if (blocking.length > 0) {
      window.alert(blockingBookingsMessage(blocking))
      return
    }
    setBusy(true)
    const now = new Date()
    const maxYear = now.getMonth() <= 1 ? now.getFullYear() : now.getFullYear() + 1
    const reasonText = reason === 'other' ? customReason : UNAVAILABLE_REASONS.find(r => r.value === reason)?.label
    await supabase.from('motorcycles').update({
      status: 'unavailable',
      unavailable_reason: reasonText || 'Deaktivováno',
      unavailable_until: unavailableUntil || `${maxYear}-02-28T23:59:59`,
    }).eq('id', moto.id)
    await logAudit('moto_deactivated', { moto_id: moto.id })
    setBusy(false); setSuccess('Motorka dočasně vyřazena'); refresh()
  }

  const hasOpenLogs = openLogs.length > 0
  const openChecklist = (edit) => { setChecklistEdit(edit); setError(null); setShowChecklist(true) }

  return (
    <Modal open={open} onClose={showChecklist ? () => setShowChecklist(false) : onClose}
      title={showChecklist ? `${moto.model} — ${checklistEdit ? 'Upravit servisní plán' : 'Servisní checklist'}` : `${moto.model} — Správa`} wide>

      {showChecklist ? (
        <ServiceChecklistView moto={moto}
          onConfirm={checklistEdit ? handleUpdateService : handleSendToService}
          onBack={() => setShowChecklist(false)} busy={busy} error={error}
          initialData={checklistEdit ? openLogs[0] : null}
          editMode={checklistEdit} />
      ) : showReplacement ? (
        <div className="p-3 rounded-lg" style={{ background: '#fef3c7', border: '1px solid #fde68a' }}>
          <div className="text-sm font-bold mb-2" style={{ color: '#b45309' }}>Servis &gt;3 dny v sezóně — vyberte náhradu na {moto.branches?.name || '—'}:</div>
          <ReplacementMotoPicker branchId={moto.branch_id} excludeMotoId={moto.id}
            onSelect={async (r) => { if (r?.id && moto.branch_id) { await supabase.from('motorcycles').update({ branch_id: moto.branch_id, status: 'active' }).eq('id', r.id); if (pendingLogId) await supabase.from('maintenance_log').update({ replacement_moto_id: r.id }).eq('id', pendingLogId); await logAudit('moto_replaced_long_service', { moto_id: moto.id, replacement_id: r.id }) }; setShowReplacement(false); setSuccess('Motorka v servisu, náhrada přiřazena'); refresh() }}
            onCancel={() => { setShowReplacement(false); setSuccess('Motorka v servisu (bez náhrady)'); refresh() }} />
        </div>
      ) : showDeactReplace ? (
        <div className="p-3 rounded-lg" style={{ background: '#ede9fe', border: '1px solid #c4b5fd' }}>
          <div className="text-sm font-bold mb-2" style={{ color: '#7c3aed' }}>Deaktivovat {moto.model} — vyberte náhradu:</div>
          <ReplacementMotoPicker branchId={moto.branch_id} excludeMotoId={moto.id}
            onSelect={handleDeactivateReplace} onCancel={() => setShowDeactReplace(false)} />
        </div>
      ) : (
        <MotoStatusPanel
          moto={moto} branches={branches} selectedBranch={selectedBranch} setSelectedBranch={setSelectedBranch}
          handleMigrate={handleMigrate} handleStatusChange={handleStatusChange}
          handleCloseServiceAndActivate={handleCloseServiceAndActivate}
          handleDeactivateSimple={handleDeactivateSimple}
          openChecklist={openChecklist} setShowDeactReplace={setShowDeactReplace}
          reason={reason} setReason={setReason} customReason={customReason} setCustomReason={setCustomReason}
          unavailableUntil={unavailableUntil} setUnavailableUntil={setUnavailableUntil}
          openLogs={openLogs} busy={busy} success={success} error={error}
          onClose={onClose} isSamoobsluzna={isSamoobsluzna}
        />
      )}
    </Modal>
  )
}

// StatusBtn and UnavailableReasonPicker moved to ./MotoActionHelpers.jsx
