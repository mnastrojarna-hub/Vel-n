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

const SERVICE_CHECKLIST = [
  { group: 'Motor & olej', items: [
    { id: 'oil_change', label: 'Výměna oleje' },
    { id: 'oil_filter', label: 'Výměna olejového filtru' },
    { id: 'air_filter', label: 'Výměna vzduchového filtru' },
    { id: 'spark_plugs', label: 'Výměna svíček' },
    { id: 'coolant', label: 'Kontrola / výměna chladicí kapaliny' },
    { id: 'engine_noise', label: 'Neobvyklý zvuk motoru' },
  ]},
  { group: 'Brzdy & podvozek', items: [
    { id: 'brake_pads_front', label: 'Brzdové destičky přední' },
    { id: 'brake_pads_rear', label: 'Brzdové destičky zadní' },
    { id: 'brake_fluid', label: 'Výměna brzdové kapaliny' },
    { id: 'brake_discs', label: 'Kontrola brzdových kotoučů' },
    { id: 'suspension', label: 'Kontrola tlumičů / pružin' },
  ]},
  { group: 'Pneumatiky & kola', items: [
    { id: 'tire_front', label: 'Výměna přední pneumatiky' },
    { id: 'tire_rear', label: 'Výměna zadní pneumatiky' },
    { id: 'tire_pressure', label: 'Kontrola tlaku pneumatik' },
    { id: 'wheel_bearings', label: 'Kontrola ložisek kol' },
  ]},
  { group: 'Řetěz & převody', items: [
    { id: 'chain_adjust', label: 'Seřízení řetězu' },
    { id: 'chain_replace', label: 'Výměna řetězu + rozet' },
    { id: 'chain_lube', label: 'Promazání řetězu' },
  ]},
  { group: 'Elektrika & světla', items: [
    { id: 'battery', label: 'Kontrola / výměna baterie' },
    { id: 'lights', label: 'Kontrola světel' },
    { id: 'fuses', label: 'Kontrola pojistek' },
    { id: 'starter', label: 'Problém se startérem' },
  ]},
  { group: 'Ostatní', items: [
    { id: 'stk', label: 'Příprava na STK' },
    { id: 'clutch', label: 'Kontrola / seřízení spojky' },
    { id: 'cosmetic', label: 'Kosmetická oprava (lak, plasty)' },
    { id: 'accident_repair', label: 'Oprava po nehodě' },
    { id: 'other_repair', label: 'Jiná oprava' },
  ]},
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
  const [showServiceChecklist, setShowServiceChecklist] = useState(false)
  const [checkedItems, setCheckedItems] = useState({})
  const [serviceDateFrom, setServiceDateFrom] = useState(() => new Date().toISOString().slice(0, 10))
  const [serviceDateTo, setServiceDateTo] = useState('')

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
      setShowServiceChecklist(false)
      setCheckedItems({})
    }
  }, [open, moto?.id])

  if (!open || !moto) return null

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const { error } = await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
      if (error) console.warn('[logAudit] failed:', error.message)
    } catch (e) { console.warn('[logAudit] error:', e.message) }
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

  function openServiceChecklist() {
    setShowServiceChecklist(true)
  }

  async function confirmSendToService() {
    const selected = Object.entries(checkedItems).filter(([, v]) => v).map(([k]) => k)
    const selectedLabels = []
    SERVICE_CHECKLIST.forEach(g => g.items.forEach(i => {
      if (selected.includes(i.id)) selectedLabels.push(i.label)
    }))

    const checklistText = selectedLabels.length > 0
      ? selectedLabels.map(l => `- ${l}`).join('\n')
      : ''
    const fullDescription = [note.trim(), checklistText].filter(Boolean).join('\n\n')

    if (!fullDescription) {
      setError('Vyplňte poznámku nebo zaškrtněte alespoň jednu položku')
      return
    }

    setShowServiceChecklist(false)
    setBusy(true); setError(null)
    try {
      // Check truly active bookings (currently rented out)
      const today = new Date().toISOString().slice(0, 10)
      const { data: activeBookings } = await supabase.from('bookings')
        .select('id, status, start_date, end_date')
        .eq('moto_id', moto.id)
        .eq('status', 'active')
        .gte('end_date', today)
      if (activeBookings?.length > 0) {
        const ok = window.confirm(`Motorka má ${activeBookings.length} aktivní rezervaci (právě pronajatá). Stornovat a přesunout do servisu?`)
        if (!ok) { setBusy(false); return }
        for (const b of activeBookings) {
          await supabase.from('bookings').update({ status: 'cancelled', notes: `Motorka odeslána do servisu` }).eq('id', b.id)
        }
      }

      // Check future reserved bookings — just inform, don't block
      const { data: reservedBookings } = await supabase.from('bookings')
        .select('id, start_date, end_date')
        .eq('moto_id', moto.id)
        .eq('status', 'reserved')
        .gte('end_date', today)
        .order('start_date', { ascending: true })
        .limit(5)
      let nextReservationInfo = ''
      if (reservedBookings?.length > 0) {
        const fmtD = d => new Date(d).toLocaleDateString('cs-CZ')
        const lines = reservedBookings.map(b => `  ${fmtD(b.start_date)} – ${fmtD(b.end_date)}`).join('\n')
        nextReservationInfo = `\n\nBudoucí rezervace (${reservedBookings.length}):\n${lines}\n\nMotorka musí být ze servisu zpět včas.`
        window.alert(`Upozornění: Motorka má budoucí rezervace:${nextReservationInfo}`)
      }

      const { error: err } = await supabase.from('motorcycles').update({ status: 'maintenance' }).eq('id', moto.id)
      if (err) throw err

      // DB CHECK constraint: service_type IN ('regular', 'extraordinary', 'repair')
      // Map checklist items: scheduled maintenance = regular, accident/damage = extraordinary, rest = repair
      const EXTRAORDINARY_IDS = ['accident_repair', 'engine_noise', 'starter']
      const REGULAR_IDS = ['oil_change', 'oil_filter', 'air_filter', 'spark_plugs', 'coolant',
        'brake_pads_front', 'brake_pads_rear', 'brake_fluid', 'brake_discs',
        'tire_front', 'tire_rear', 'tire_pressure', 'chain_adjust', 'chain_replace', 'chain_lube',
        'stk', 'lights', 'battery']
      const hasExtraordinary = selected.some(id => EXTRAORDINARY_IDS.includes(id))
      const hasRegular = selected.some(id => REGULAR_IDS.includes(id))
      const serviceType = hasExtraordinary ? 'extraordinary' : hasRegular ? 'regular' : 'repair'

      const logPayload = {
        moto_id: moto.id,
        description: fullDescription,
        service_type: serviceType,
        service_date: serviceDateFrom || today,
        scheduled_date: serviceDateTo || serviceDateFrom || today,
        km_at_service: Number(moto.mileage) || null,
        status: 'in_service',
        items: selectedLabels.map(label => ({ label, done: false, note: '' })),
      }
      const { error: logErr } = await supabase.from('maintenance_log').insert(logPayload)
      if (logErr) {
        console.error('[confirmSendToService] insert failed:', logErr, logPayload)
        setError(`Servisní záznam se nepodařilo vytvořit: ${logErr.message}`)
      }

      await logAudit('motorcycle_status_changed', {
        moto_id: moto.id, model: moto.model,
        from_status: moto.status, to_status: 'maintenance',
        reason: fullDescription,
        checklist: selected,
      })

      setSuccess('Motorka odeslána do servisu')
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

  const checkedCount = Object.values(checkedItems).filter(Boolean).length

  return (
    <Modal open={open} onClose={showServiceChecklist ? () => setShowServiceChecklist(false) : onClose} title={showServiceChecklist ? `${moto.model} — Servisní checklist` : `${moto.model} — Správa`} wide>
      {showServiceChecklist ? (
        /* ═══ SERVISNÍ CHECKLIST ═══ */
        <div>
          <div className="mb-4 p-3 rounded-lg" style={{ background: '#fef3c7', border: '1px solid #fde68a' }}>
            <div className="text-sm font-bold" style={{ color: '#b45309' }}>
              Zaškrtněte co je potřeba opravit / zkontrolovat. Můžete přidat i vlastní poznámku.
            </div>
          </div>

          <div className="space-y-4 mb-4" style={{ maxHeight: 400, overflowY: 'auto' }}>
            {SERVICE_CHECKLIST.map(group => (
              <div key={group.group}>
                <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>{group.group}</div>
                <div className="grid grid-cols-2 gap-1">
                  {group.items.map(item => (
                    <label key={item.id} className="flex items-center gap-2 p-2 rounded cursor-pointer transition-colors"
                      style={{ background: checkedItems[item.id] ? '#dcfce7' : '#f1faf7', border: `1px solid ${checkedItems[item.id] ? '#1a8a18' : '#d4e8e0'}` }}>
                      <input type="checkbox" checked={!!checkedItems[item.id]}
                        onChange={e => setCheckedItems(c => ({ ...c, [item.id]: e.target.checked }))}
                        className="accent-[#1a8a18]" style={{ width: 16, height: 16 }} />
                      <span className="text-sm" style={{ color: '#0f1a14', fontWeight: checkedItems[item.id] ? 700 : 400 }}>{item.label}</span>
                    </label>
                  ))}
                </div>
              </div>
            ))}
          </div>

          <div className="grid grid-cols-2 gap-3 mb-4">
            <div>
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Servis od</label>
              <input type="date" value={serviceDateFrom}
                onChange={e => setServiceDateFrom(e.target.value)}
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
            </div>
            <div>
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Plánované dokončení</label>
              <input type="date" value={serviceDateTo}
                onChange={e => setServiceDateTo(e.target.value)}
                min={serviceDateFrom}
                className="w-full rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
            </div>
          </div>

          <div className="mb-4">
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Doplňující poznámka</label>
            <textarea value={note} onChange={e => setNote(e.target.value)}
              placeholder="Popište závadu, okolnosti, další info pro technika…"
              className="w-full rounded-btn text-sm outline-none"
              rows={3}
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14', resize: 'vertical' }} />
          </div>

          {error && <div className="mb-3 p-2 rounded text-sm" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>}

          <div className="flex items-center justify-between">
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
              {checkedCount > 0 ? `Zaškrtnuto: ${checkedCount} položek` : 'Nic nezaškrtnuto'}
            </span>
            <div className="flex gap-2">
              <Button onClick={() => setShowServiceChecklist(false)}>Zpět</Button>
              <Button green onClick={confirmSendToService} disabled={busy}>
                {busy ? 'Odesílám…' : 'Odeslat do servisu'}
              </Button>
            </div>
          </div>
        </div>
      ) : (
        /* ═══ HLAVNÍ SPRÁVA ═══ */
        <>
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

              {/* Do servisu — otevře checklist */}
              {!isMaintenance && (
                <button onClick={openServiceChecklist} disabled={busy}
                  className="p-3 rounded-lg text-left cursor-pointer transition-colors"
                  style={{ background: '#fef3c7', border: '2px solid #b45309', opacity: busy ? 0.5 : 1 }}>
                  <div className="text-sm font-extrabold mb-1" style={{ color: '#b45309' }}>Odeslat do servisu</div>
                  <div className="text-sm" style={{ color: '#1a2e22' }}>Otevře checklist závad a údržby</div>
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
          </div>

          <div className="flex justify-end mt-5">
            <Button onClick={onClose}>Zavřít</Button>
          </div>
        </>
      )}
    </Modal>
  )
}
