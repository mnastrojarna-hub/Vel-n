import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'
import ReplacementMotoPicker from '../../components/fleet/ReplacementMotoPicker'

const SEASON_START = 3, SEASON_END = 9

export default function ServiceMotoActions({ moto, logs, onDone }) {
  const [mode, setMode] = useState(null) // 'deactivate' | 'retire' | 'reschedule'
  const [busy, setBusy] = useState(false)
  const [rescheduleDate, setRescheduleDate] = useState('')
  const [rescheduleLogId, setRescheduleLogId] = useState(null)
  const [retireNote, setRetireNote] = useState('')

  const hasPlanned = logs.some(l => l.service_type === 'regular')
  const hasUrgent = logs.some(l => l.is_urgent)
  const isSamoobsluzna = moto.branches?.type === 'samoobslužná'

  async function audit(action, details) {
    try { const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  // Deactivate moto → must pick replacement for branch
  async function handleReplace(replacementMoto) {
    setBusy(true)
    // Move replacement to this moto's branch
    if (moto.branch_id && replacementMoto.id) {
      await supabase.from('motorcycles').update({ branch_id: moto.branch_id, status: 'active' }).eq('id', replacementMoto.id)
    }
    // Deactivate original
    const now = new Date()
    const maxYear = now.getMonth() <= 1 ? now.getFullYear() : now.getFullYear() + 1
    await supabase.from('motorcycles').update({
      status: 'unavailable',
      unavailable_reason: 'Deaktivováno — náhrada přiřazena',
      unavailable_until: `${maxYear}-02-28T23:59:59`,
    }).eq('id', moto.id)
    // Link replacement in active logs
    for (const l of logs) {
      await supabase.from('maintenance_log').update({ replacement_moto_id: replacementMoto.id }).eq('id', l.id)
    }
    await audit('moto_replaced_in_service', { moto_id: moto.id, replacement_id: replacementMoto.id, branch_id: moto.branch_id })
    setBusy(false)
    onDone()
  }

  // Retire moto → disassembly scheduled for winter
  async function handleRetire() {
    setBusy(true)
    await supabase.from('motorcycles').update({ status: 'retired' }).eq('id', moto.id)
    // Schedule winter disassembly
    const winterDate = getNextWinterDate()
    await supabase.from('maintenance_log').insert({
      moto_id: moto.id, service_type: 'extraordinary', is_urgent: false,
      description: `Rozebrání na náhradní díly — prodej externí firmou\n${retireNote}`.trim(),
      scheduled_date: winterDate, status: 'pending',
      retirement_type: 'disassembly',
    })
    await audit('moto_retired_from_service', { moto_id: moto.id, disassembly_date: winterDate, note: retireNote })
    setBusy(false)
    onDone()
  }

  // Reschedule planned service to given date
  async function handleReschedule() {
    if (!rescheduleDate || !rescheduleLogId) return
    setBusy(true)
    await supabase.from('maintenance_log').update({ scheduled_date: rescheduleDate, service_date: rescheduleDate, status: 'pending' }).eq('id', rescheduleLogId)
    await audit('service_rescheduled', { log_id: rescheduleLogId, new_date: rescheduleDate, moto_id: moto.id })
    setBusy(false)
    onDone()
  }

  function getNextWinterDate() {
    const now = new Date()
    const y = now.getMonth() >= 10 ? now.getFullYear() : now.getFullYear()
    // Schedule for January next year (or this year if before January)
    const target = now.getMonth() <= 1 ? new Date(y, 0, 15) : new Date(y + 1, 0, 15)
    return target.toISOString().slice(0, 10)
  }

  async function handleReactivate() {
    setBusy(true)
    const today = new Date().toISOString().slice(0, 10)
    await supabase.from('motorcycles').update({ status: 'active', last_service_date: today }).eq('id', moto.id)
    // Close all open maintenance logs for this moto
    await supabase.from('maintenance_log').update({ completed_date: today, status: 'completed' }).eq('moto_id', moto.id).is('completed_date', null)
    await audit('moto_reactivated_from_service', { moto_id: moto.id })
    setBusy(false)
    onDone()
  }

  return (
    <div className="p-3 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fde68a' }}>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#b45309' }}>Servisní akce</div>

      {!mode && (
        <div className="flex gap-2 flex-wrap">
          <button onClick={handleReactivate} disabled={busy}
            className="rounded-btn text-sm font-bold cursor-pointer"
            style={{ padding: '6px 14px', background: '#dcfce7', color: '#1a8a18', border: 'none' }}>
            {busy ? 'Aktivuji…' : 'Vrátit do provozu'}
          </button>
          {isSamoobsluzna ? (
            <button onClick={() => setMode('deactivate')} className="rounded-btn text-sm font-bold cursor-pointer"
              style={{ padding: '6px 14px', background: '#ede9fe', color: '#7c3aed', border: 'none' }}>
              Deaktivovat + nahradit
            </button>
          ) : (
            <button onClick={async () => {
                setBusy(true)
                const now = new Date()
                const maxYear = now.getMonth() <= 1 ? now.getFullYear() : now.getFullYear() + 1
                await supabase.from('motorcycles').update({
                  status: 'unavailable',
                  unavailable_reason: 'Deaktivováno ze servisu',
                  unavailable_until: `${maxYear}-02-28T23:59:59`,
                }).eq('id', moto.id)
                await audit('moto_deactivated', { moto_id: moto.id })
                setBusy(false); onDone()
              }}
              className="rounded-btn text-sm font-bold cursor-pointer" disabled={busy}
              style={{ padding: '6px 14px', background: '#ede9fe', color: '#7c3aed', border: 'none' }}>
              {busy ? 'Vyřazuji…' : 'Dočasně vyřadit'}
            </button>
          )}
          <button onClick={() => setMode('retire')} className="rounded-btn text-sm font-bold cursor-pointer"
            style={{ padding: '6px 14px', background: '#f3f4f6', color: '#6b7280', border: 'none' }}>
            Vyřadit z flotily
          </button>
          {hasPlanned && hasUrgent && (
            <button onClick={() => setMode('reschedule')} className="rounded-btn text-sm font-bold cursor-pointer"
              style={{ padding: '6px 14px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
              Přeplánovat plánovaný servis
            </button>
          )}
        </div>
      )}

      {/* Deactivate + Replace (only samoobslužná) */}
      {mode === 'deactivate' && (
        <div>
          <div className="text-xs mb-2 p-2 rounded" style={{ background: '#fee2e2', color: '#dc2626' }}>
            Samoobslužná pobočka <b>{moto.branches?.name || '—'}</b> musí být vždy obsazená — vyberte náhradu:
          </div>
          <ReplacementMotoPicker branchId={moto.branch_id} excludeMotoId={moto.id}
            onSelect={handleReplace} onCancel={() => setMode(null)} />
        </div>
      )}

      {/* Retire */}
      {mode === 'retire' && (
        <div>
          <div className="text-sm mb-2" style={{ color: '#1a2e22' }}>
            Motorka bude vyřazena. Naplánuje se rozebrání na díly v zimním období ({getNextWinterDate()}). Zbylé díly půjdou do šrotu, prodej zajistí externí firma.
          </div>
          <textarea value={retireNote} onChange={e => setRetireNote(e.target.value)}
            placeholder="Seznam dílů k prodeji / poznámky pro firmu…" rows={3}
            className="w-full rounded-btn text-sm outline-none mb-2"
            style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', resize: 'vertical' }} />
          <div className="flex gap-2">
            <Button onClick={() => setMode(null)}>Zrušit</Button>
            <Button onClick={handleRetire} disabled={busy} style={{ background: '#dc2626', color: '#fff' }}>
              {busy ? 'Vyřazuji…' : 'Potvrdit vyřazení'}
            </Button>
          </div>
        </div>
      )}

      {/* Reschedule planned service */}
      {mode === 'reschedule' && (
        <div>
          <div className="text-sm mb-2" style={{ color: '#1a2e22' }}>Přesuňte plánovaný servis na jiné datum (když motorka není rezervovaná):</div>
          <div className="flex gap-2 items-end flex-wrap">
            <select value={rescheduleLogId || ''} onChange={e => setRescheduleLogId(e.target.value)}
              className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }}>
              <option value="">— Vyberte servis —</option>
              {logs.filter(l => l.service_type === 'regular' || !l.is_urgent).map(l => (
                <option key={l.id} value={l.id}>{l.description?.slice(0, 40) || l.service_type} ({l.service_date || '—'})</option>
              ))}
            </select>
            <input type="date" value={rescheduleDate} onChange={e => setRescheduleDate(e.target.value)}
              className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
            <Button onClick={() => setMode(null)}>Zrušit</Button>
            <Button green onClick={handleReschedule} disabled={busy || !rescheduleDate || !rescheduleLogId}>
              {busy ? 'Přesouvám…' : 'Přeplánovat'}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
