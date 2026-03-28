import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'
import Button from '../ui/Button'
import Badge from '../ui/Badge'
import ConfirmDialog from '../ui/ConfirmDialog'
import Modal from '../ui/Modal'
import ServiceOrdersPanel from './ServiceOrdersPanel'

/* ═══ SERVIS TAB — editovatelné intervaly + díly + objednávky pro technika ═══ */
export default function ServiceTab({ motoId, motoMileage, purchaseMileage, trackingUnit = 'km', logAudit }) {
  const unitLabel = trackingUnit === 'mh' ? 'MH' : 'km'
  const [logs, setLogs] = useState([])
  const [schedules, setSchedules] = useState([])
  const [loading, setLoading] = useState(true)
  const [confirmService, setConfirmService] = useState(null)
  const [showOrder, setShowOrder] = useState(null)
  const [editing, setEditing] = useState(null)
  const [saving, setSaving] = useState(false)
  // Parts management
  const [partsBySchedule, setPartsBySchedule] = useState({}) // schedule_id -> [{id, inventory_item_id, quantity, notes, inventory}]
  const [inventoryItems, setInventoryItems] = useState([])
  const [expandedParts, setExpandedParts] = useState(null) // schedule_id or null

  useEffect(() => { loadAll() }, [motoId])

  async function loadAll() {
    setLoading(true)
    const [logRes, schedRes, invRes] = await Promise.all([
      supabase.from('maintenance_log').select('*').eq('moto_id', motoId).order('created_at', { ascending: false }),
      supabase.from('maintenance_schedules').select('*').eq('moto_id', motoId).eq('active', true),
      supabase.from('inventory').select('id, name, sku, stock, unit_price, supplier_id'),
    ])
    if (logRes.error) console.error('[ServiceTab] logs query failed:', logRes.error)
    if (schedRes.error) console.error('[ServiceTab] schedules query failed:', schedRes.error)
    setLogs(logRes.data || [])
    setSchedules(schedRes.data || [])
    setInventoryItems(invRes.data || [])
    // Load parts for all schedules
    const schedIds = (schedRes.data || []).map(s => s.id)
    if (schedIds.length) {
      const { data: parts } = await supabase
        .from('service_parts')
        .select('*, inventory(name, sku, stock, unit_price)')
        .in('schedule_id', schedIds)
      const map = {}
      for (const p of (parts || [])) {
        if (!map[p.schedule_id]) map[p.schedule_id] = []
        map[p.schedule_id].push(p)
      }
      setPartsBySchedule(map)
    } else {
      setPartsBySchedule({})
    }
    setLoading(false)
  }

  async function addPart(scheduleId, itemId, qty) {
    await supabase.from('service_parts').upsert({
      schedule_id: scheduleId,
      inventory_item_id: itemId,
      quantity: Number(qty) || 1,
    }, { onConflict: 'schedule_id,inventory_item_id' })
    await logAudit('service_part_added', { schedule_id: scheduleId, item_id: itemId })
    await loadAll()
  }

  async function removePart(partId, scheduleId) {
    await supabase.from('service_parts').delete().eq('id', partId)
    await logAudit('service_part_removed', { part_id: partId, schedule_id: scheduleId })
    await loadAll()
  }

  async function updatePartQty(partId, qty) {
    await supabase.from('service_parts').update({ quantity: Number(qty) || 1 }).eq('id', partId)
    await loadAll()
  }

  async function handleSaveSchedule(sched) {
    setSaving(true)
    await supabase.from('maintenance_schedules').update({
      description: sched.description,
      interval_km: Number(sched.interval_km) || 0,
      interval_days: Number(sched.interval_days) || null,
      first_service_km: Number(sched.first_service_km) || null,
      first_service_desc: sched.first_service_desc || null,
    }).eq('id', sched.id)
    await logAudit('schedule_updated', { schedule_id: sched.id, moto_id: motoId })
    setEditing(null)
    setSaving(false)
    await loadAll()
  }

  async function handleAddSchedule(form) {
    setSaving(true)
    const intervalDays = Number(form.interval_days) || null
    // Calculate next_date from interval_days so it shows in "Plánované" tab
    let nextDate = null
    if (intervalDays) {
      const d = new Date()
      d.setDate(d.getDate() + intervalDays)
      nextDate = d.toISOString().slice(0, 10)
    }
    await supabase.from('maintenance_schedules').insert({
      moto_id: motoId,
      description: form.description,
      interval_km: Number(form.interval_km) || 10000,
      interval_days: intervalDays,
      schedule_type: intervalDays ? 'both' : 'mileage',
      active: true,
      next_date: nextDate,
      first_service_km: Number(form.first_service_km) || null,
      first_service_desc: form.first_service_desc || null,
    })
    await logAudit('schedule_created', { moto_id: motoId })
    setSaving(false)
    await loadAll()
  }

  async function handleDeleteSchedule(id) {
    await supabase.from('maintenance_schedules').update({ active: false }).eq('id', id)
    await logAudit('schedule_deleted', { schedule_id: id })
    await loadAll()
  }

  async function handleConfirmService(schedule) {
    const today = new Date().toISOString().slice(0, 10)
    const { data: newLog } = await supabase.from('maintenance_log').insert({
      moto_id: motoId, service_type: 'regular',
      description: `Plánovaný servis: ${schedule.description}`,
      km_at_service: Number(motoMileage) || 0,
      service_date: today,
      scheduled_date: today,
      status: 'in_service',
    }).select().single()

    // Recalculate next_date based on interval_days
    const updateData = {
      last_service_km: Number(motoMileage) || 0,
      last_performed: new Date().toISOString().split('T')[0],
    }
    if (schedule.interval_days) {
      const nd = new Date()
      nd.setDate(nd.getDate() + schedule.interval_days)
      updateData.next_date = nd.toISOString().slice(0, 10)
    }
    await supabase.from('maintenance_schedules')
      .update(updateData)
      .eq('id', schedule.id)

    await logAudit('service_confirmed', { moto_id: motoId, schedule_id: schedule.id })

    const order = {
      moto_id: motoId, type: schedule.description,
      items: getServiceItems(schedule.description),
      km: Number(motoMileage) || 0, created_at: new Date().toISOString(),
      status: 'pending', maintenance_log_id: newLog?.id,
    }
    await supabase.from('service_orders').insert(order)
    setConfirmService(null)
    setShowOrder(order)
    await loadAll()
  }

  if (loading) return <Spinner />

  return (
    <div className="space-y-5">
      {/* Otevřené servisní zakázky (pokud existují) */}
      <ServiceOrdersPanel motoId={motoId} logAudit={logAudit} />

      {/* Servisní plány — editovatelné */}
      <Card>
        <div className="flex items-center justify-between mb-4">
          <SectionTitle>Servisní intervaly</SectionTitle>
          <AddScheduleBtn onAdd={handleAddSchedule} saving={saving} unitLabel={unitLabel} existingTypes={schedules.map(s => s.description)} />
        </div>
        {schedules.length === 0 ? <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné servisní plány</p> : (
          <div className="space-y-3">
            {schedules.map(s => {
              const currentKm = Number(motoMileage) || 0
              const baseMileage = Number(purchaseMileage) || 0
              const hasBeenServiced = !!s.last_service_km
              // 1. servis = od purchase_mileage + first_service_km (korekce)
              // 2+ servis = od last_service_km + interval_km (pravidelný)
              const isFirstService = !hasBeenServiced
              let nextAt
              if (isFirstService && s.first_service_km) {
                nextAt = baseMileage + Number(s.first_service_km)
              } else if (hasBeenServiced) {
                nextAt = s.last_service_km + (s.interval_km || 0)
              } else {
                nextAt = baseMileage + (s.interval_km || 0)
              }
              const remaining = nextAt - currentKm
              const overdue = remaining <= 0
              const isEditing = editing === s.id

              if (isEditing) return (
                <ScheduleEditRow key={s.id} schedule={s} saving={saving} unitLabel={unitLabel}
                  onSave={handleSaveSchedule} onCancel={() => setEditing(null)} />
              )

              const parts = partsBySchedule[s.id] || []
              const isExpanded = expandedParts === s.id

              return (
                <div key={s.id}>
                  <div className="flex items-center gap-3 p-3 rounded-lg" style={{ background: overdue ? '#fee2e2' : '#f1faf7' }}>
                    <div className="flex-1">
                      <span className="font-bold text-sm">{s.description}</span>
                      {isFirstService && s.first_service_km ? (
                        <span className="text-sm ml-3" style={{ color: '#2563eb' }}>
                          1. servis při {nextAt.toLocaleString('cs-CZ')} {unitLabel}
                          {s.first_service_desc ? ` (${s.first_service_desc})` : ''}
                        </span>
                      ) : (
                        <span className="text-sm ml-3" style={{ color: '#1a2e22' }}>
                          každých {s.interval_km?.toLocaleString('cs-CZ')} {unitLabel}
                          {s.interval_days ? ` / ${s.interval_days} dní` : ''}
                        </span>
                      )}
                      <span className="text-sm ml-2" style={{ color: overdue ? '#dc2626' : '#1a8a18', fontWeight: 700 }}>
                        {overdue ? `PO TERMÍNU ${Math.abs(remaining).toLocaleString('cs-CZ')} ${unitLabel}` : `za ${remaining.toLocaleString('cs-CZ')} ${unitLabel}`}
                      </span>
                    </div>
                    <button onClick={() => setExpandedParts(isExpanded ? null : s.id)}
                      className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}
                      title="Díly pro servis">
                      {parts.length ? `${parts.length} dílů` : 'Díly'}
                    </button>
                    <button onClick={() => setEditing(s.id)} className="text-sm font-bold cursor-pointer" style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Upravit</button>
                    <button onClick={() => handleDeleteSchedule(s.id)} className="text-sm font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none' }}>×</button>
                    <Button green onClick={() => setConfirmService(s)}>Potvrdit servis</Button>
                  </div>
                  {isExpanded && (
                    <PartsPanel
                      parts={parts}
                      inventoryItems={inventoryItems}
                      scheduleId={s.id}
                      onAdd={addPart}
                      onRemove={removePart}
                      onUpdateQty={updatePartQty}
                    />
                  )}
                </div>
              )
            })}
          </div>
        )}
      </Card>

      {/* Historie */}
      <Card>
        <SectionTitle>Historie servisu</SectionTitle>
        {logs.length === 0 ? <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné servisní záznamy</p> : (
          <div className="space-y-3">
            {logs.map(l => {
              const fmtDate = d => d ? new Date(d).toLocaleDateString('cs-CZ') : null
              const startDate = fmtDate(l.scheduled_date) || fmtDate(l.created_at)
              const endDate = fmtDate(l.completed_date)
              const km = l.km_at_service || l.mileage_at_service
              const isCompleted = !!l.completed_date || l.status === 'completed'
              return (
                <div key={l.id} className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                  <div className="flex items-center gap-3 mb-2">
                    <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{{ regular: 'Pravidelný servis', extraordinary: 'Mimořádný servis', repair: 'Oprava' }[l.service_type] || l.type || 'Servis'}</span>
                    <span className="text-sm font-bold" style={{
                      padding: '2px 8px', borderRadius: 6,
                      background: isCompleted ? '#dcfce7' : '#fef3c7',
                      color: isCompleted ? '#166534' : '#b45309',
                    }}>{isCompleted ? 'Dokončeno' : 'V servisu'}</span>
                    {(l.cost || l.total_cost) && <span className="text-sm font-bold ml-auto">{(l.cost || l.total_cost).toLocaleString('cs-CZ')} Kč</span>}
                  </div>
                  <div className="grid grid-cols-3 gap-2 text-sm mb-2" style={{ color: '#1a2e22' }}>
                    <div><span className="font-bold">Do servisu:</span> {startDate || '—'}</div>
                    <div><span className="font-bold">Ze servisu:</span> {endDate || '—'}</div>
                    <div><span className="font-bold">Km:</span> {km ? km.toLocaleString('cs-CZ') : '—'}</div>
                  </div>
                  {l.performed_by && <div className="text-sm mb-1" style={{ color: '#1a2e22' }}><span className="font-bold">Technik:</span> {l.performed_by}</div>}
                  {l.description && (
                    <div className="text-sm p-2 rounded" style={{ background: '#e8f5e9', color: '#0f1a14', whiteSpace: 'pre-wrap' }}>
                      <span className="font-bold">Servisní záznam:</span> {l.description}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </Card>

      <ConfirmDialog
        open={!!confirmService}
        title={`Potvrdit servis: ${confirmService?.description || ''}`}
        message={`Bude vytvořena objednávka pro technika. ${trackingUnit === 'mh' ? 'Motohodiny' : 'Tachometr'}: ${Number(motoMileage || 0).toLocaleString('cs-CZ')} ${unitLabel}.`}
        onConfirm={() => confirmService && handleConfirmService(confirmService)}
        onCancel={() => setConfirmService(null)}
      />

      {showOrder && (
        <Modal open title="Servisní objednávka" onClose={() => setShowOrder(null)}>
          <div className="p-4 rounded-lg mb-3" style={{ background: '#dcfce7' }}>
            <div className="text-sm font-bold mb-1" style={{ color: '#166534' }}>{showOrder.type}</div>
            <div className="text-sm" style={{ color: '#1a2e22' }}>{unitLabel}: {showOrder.km.toLocaleString('cs-CZ')} | {showOrder.created_at.slice(0, 10)}</div>
          </div>
          <SectionTitle>Úkoly pro technika</SectionTitle>
          {showOrder.items.map((item, i) => (
            <div key={i} className="p-2 rounded-lg mb-1" style={{ background: '#f1faf7', fontSize: 13 }}>{item}</div>
          ))}
          <Button green onClick={() => setShowOrder(null)} className="mt-4">Zavřít</Button>
        </Modal>
      )}
    </div>
  )
}

function ScheduleEditRow({ schedule, saving, unitLabel = 'km', onSave, onCancel }) {
  const [form, setForm] = useState({ ...schedule })
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const isFirstService = !schedule.last_service_km
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '2px solid #74FB71' }}>
      <div className="grid grid-cols-3 gap-2 mb-2">
        <input value={form.description || ''} onChange={e => set('description', e.target.value)} placeholder="Popis" className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
        <input type="number" value={form.interval_km || ''} onChange={e => set('interval_km', e.target.value)} placeholder={`Interval ${unitLabel}`} className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
        <input type="number" value={form.interval_days || ''} onChange={e => set('interval_days', e.target.value)} placeholder="Interval dní" className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
      </div>
      {isFirstService && (
        <div className="grid grid-cols-2 gap-2 mb-2">
          <input type="number" value={form.first_service_km || ''} onChange={e => set('first_service_km', e.target.value)} placeholder={`1. servis za ${unitLabel}`} className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#eff6ff', border: '1px solid #bfdbfe' }} />
          <input value={form.first_service_desc || ''} onChange={e => set('first_service_desc', e.target.value)} placeholder="Co u 1. servisu" className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#eff6ff', border: '1px solid #bfdbfe' }} />
        </div>
      )}
      <div className="flex gap-2">
        <Button green onClick={() => onSave(form)} disabled={saving}>Uložit</Button>
        <Button onClick={onCancel}>Zrušit</Button>
      </div>
    </div>
  )
}

const SERVICE_PRESETS = [
  { key: 'oil', label: 'Výměna oleje', icon: '🛢️', defaultKm: 5000, defaultDays: 365 },
  { key: 'tires', label: 'Výměna pneumatik', icon: '🔘', defaultKm: 15000, defaultDays: null },
  { key: 'brakes', label: 'Kontrola brzd', icon: '🛑', defaultKm: 10000, defaultDays: 365 },
  { key: 'full', label: 'Kompletní servis', icon: '🔧', defaultKm: 20000, defaultDays: 365 },
  { key: 'chain', label: 'Řetěz / rozvodový řemen', icon: '⛓️', defaultKm: 20000, defaultDays: null },
  { key: 'coolant', label: 'Chladicí kapalina', icon: '💧', defaultKm: 30000, defaultDays: 730 },
  { key: 'air_filter', label: 'Vzduchový filtr', icon: '🌬️', defaultKm: 15000, defaultDays: 365 },
  { key: 'stk', label: 'STK / Inspekce', icon: '📋', defaultKm: null, defaultDays: 730 },
  { key: 'custom', label: 'Vlastní...', icon: '✏️', defaultKm: 10000, defaultDays: null },
]

function AddScheduleBtn({ onAdd, saving, unitLabel = 'km', existingTypes = [] }) {
  const [open, setOpen] = useState(false)
  const [step, setStep] = useState(1) // 1 = choose type, 2 = configure
  const [selected, setSelected] = useState(null)
  const [form, setForm] = useState({ description: '', interval_km: '', interval_days: '', first_service_km: '', first_service_desc: '' })
  const [hasFirstService, setHasFirstService] = useState(false)

  function reset() {
    setOpen(false); setStep(1); setSelected(null); setHasFirstService(false)
    setForm({ description: '', interval_km: '', interval_days: '', first_service_km: '', first_service_desc: '' })
  }

  function selectPreset(preset) {
    setSelected(preset.key)
    setForm({
      description: preset.key === 'custom' ? '' : preset.label,
      interval_km: preset.defaultKm || '',
      interval_days: preset.defaultDays || '',
      first_service_km: '',
      first_service_desc: '',
    })
    setStep(2)
  }

  function handleSubmit() {
    if (!form.description) return
    const submitForm = { ...form }
    if (!hasFirstService) { submitForm.first_service_km = ''; submitForm.first_service_desc = '' }
    onAdd(submitForm)
    reset()
  }

  if (!open) return (
    <button onClick={() => setOpen(true)}
      className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
      style={{ padding: '6px 16px', background: '#74FB71', color: '#1a2e22', border: 'none' }}>
      + Nový servisní plán
    </button>
  )

  // Existing type names for "already added" badge
  const existingLower = existingTypes.map(t => (t || '').toLowerCase())

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,.4)' }} onClick={e => { if (e.target === e.currentTarget) reset() }}>
      <div className="rounded-card shadow-xl w-full max-w-lg" style={{ background: '#fff', maxHeight: '85vh', overflow: 'auto' }}>
        {/* Header */}
        <div className="flex items-center justify-between p-4" style={{ borderBottom: '1px solid #d4e8e0' }}>
          <h3 className="font-extrabold text-base" style={{ color: '#0f1a14' }}>
            {step === 1 ? 'Vyberte typ servisu' : 'Nastavení plánu'}
          </h3>
          <button onClick={reset} className="text-lg font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#6b7280' }}>×</button>
        </div>

        {step === 1 && (
          <div className="p-4">
            <div className="grid grid-cols-2 gap-2">
              {SERVICE_PRESETS.map(p => {
                const alreadyExists = p.key !== 'custom' && existingLower.some(e => e.includes(p.label.toLowerCase().split(' ')[0]))
                return (
                  <button key={p.key} onClick={() => selectPreset(p)}
                    className="flex items-center gap-3 p-3 rounded-lg text-left cursor-pointer transition-all"
                    style={{
                      background: alreadyExists ? '#f9fafb' : '#f1faf7',
                      border: '2px solid transparent',
                      opacity: alreadyExists ? 0.6 : 1,
                    }}
                    onMouseEnter={e => e.currentTarget.style.borderColor = '#74FB71'}
                    onMouseLeave={e => e.currentTarget.style.borderColor = 'transparent'}>
                    <span style={{ fontSize: 22 }}>{p.icon}</span>
                    <div>
                      <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{p.label}</div>
                      {p.defaultKm && <div className="text-xs" style={{ color: '#6b7280' }}>~{p.defaultKm.toLocaleString('cs-CZ')} {unitLabel}</div>}
                      {p.defaultDays && !p.defaultKm && <div className="text-xs" style={{ color: '#6b7280' }}>~{p.defaultDays} dní</div>}
                      {alreadyExists && <div className="text-xs font-bold" style={{ color: '#b45309' }}>Již přidáno</div>}
                    </div>
                  </button>
                )
              })}
            </div>
          </div>
        )}

        {step === 2 && (
          <div className="p-4 space-y-4">
            {/* Back button */}
            <button onClick={() => setStep(1)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>
              ← Zpět na výběr typu
            </button>

            {/* Selected type badge */}
            {selected && selected !== 'custom' && (
              <div className="flex items-center gap-2 p-2 rounded-lg" style={{ background: '#dcfce7' }}>
                <span style={{ fontSize: 18 }}>{SERVICE_PRESETS.find(p => p.key === selected)?.icon}</span>
                <span className="font-bold text-sm" style={{ color: '#166534' }}>{form.description}</span>
              </div>
            )}

            {/* Custom description */}
            {selected === 'custom' && (
              <div>
                <label className="block text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Název servisu</label>
                <input value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))}
                  placeholder="např. Výměna svíček, Kontrola ventilů..."
                  autoFocus
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
              </div>
            )}

            {/* Interval settings */}
            <div>
              <label className="block text-xs font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Intervaly</label>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs mb-1" style={{ color: '#6b7280' }}>Interval ({unitLabel})</label>
                  <input type="number" value={form.interval_km}
                    onChange={e => setForm(f => ({ ...f, interval_km: e.target.value }))}
                    placeholder={`např. 10 000 ${unitLabel}`}
                    className="w-full rounded-btn text-sm outline-none"
                    style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
                </div>
                <div>
                  <label className="block text-xs mb-1" style={{ color: '#6b7280' }}>Interval (dní)</label>
                  <input type="number" value={form.interval_days}
                    onChange={e => setForm(f => ({ ...f, interval_days: e.target.value }))}
                    placeholder="např. 365"
                    className="w-full rounded-btn text-sm outline-none"
                    style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
                </div>
              </div>
            </div>

            {/* First service toggle */}
            <div className="rounded-lg p-3" style={{ background: '#eff6ff', border: '1px solid #bfdbfe' }}>
              <label className="flex items-center gap-3 cursor-pointer">
                <input type="checkbox" checked={hasFirstService}
                  onChange={e => setHasFirstService(e.target.checked)}
                  style={{ width: 18, height: 18, accentColor: '#2563eb' }} />
                <div>
                  <div className="text-sm font-bold" style={{ color: '#1e40af' }}>Jiný interval pro 1. servis</div>
                  <div className="text-xs" style={{ color: '#6b7280' }}>Např. první výměna oleje po 1 000 {unitLabel}, pak každých 5 000 {unitLabel}</div>
                </div>
              </label>
              {hasFirstService && (
                <div className="grid grid-cols-2 gap-3 mt-3">
                  <div>
                    <label className="block text-xs mb-1" style={{ color: '#6b7280' }}>1. servis za ({unitLabel})</label>
                    <input type="number" value={form.first_service_km}
                      onChange={e => setForm(f => ({ ...f, first_service_km: e.target.value }))}
                      placeholder={`např. 1 000`}
                      className="w-full rounded-btn text-sm outline-none"
                      style={{ padding: '8px 12px', background: '#fff', border: '1px solid #bfdbfe' }} />
                  </div>
                  <div>
                    <label className="block text-xs mb-1" style={{ color: '#6b7280' }}>Poznámka k 1. servisu</label>
                    <input value={form.first_service_desc}
                      onChange={e => setForm(f => ({ ...f, first_service_desc: e.target.value }))}
                      placeholder="Záběhový servis"
                      className="w-full rounded-btn text-sm outline-none"
                      style={{ padding: '8px 12px', background: '#fff', border: '1px solid #bfdbfe' }} />
                  </div>
                </div>
              )}
            </div>

            {/* Submit */}
            <div className="flex gap-3 pt-2">
              <button onClick={handleSubmit} disabled={saving || !form.description}
                className="flex-1 rounded-btn text-sm font-extrabold uppercase cursor-pointer"
                style={{ padding: '10px 20px', background: !form.description ? '#d4e8e0' : '#74FB71', color: '#1a2e22', border: 'none', opacity: saving ? 0.6 : 1 }}>
                {saving ? 'Vytvářím...' : 'Vytvořit servisní plán'}
              </button>
              <button onClick={reset}
                className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
                style={{ padding: '10px 20px', background: '#f1faf7', color: '#1a2e22', border: '1px solid #d4e8e0' }}>
                Zrušit
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function getServiceItems(description) {
  const desc = (description || '').toLowerCase()
  if (desc.includes('olej')) return ['Vypustit starý olej', 'Vyměnit olejový filtr', 'Doplnit nový olej dle specifikace', 'Zkontrolovat únik oleje']
  if (desc.includes('pneumat')) return ['Demontovat kola', 'Namontovat nové pneumatiky', 'Vyvážit kola', 'Zkontrolovat brzdové destičky']
  if (desc.includes('kompletní') || desc.includes('servis')) return ['Výměna oleje a filtru', 'Kontrola brzd', 'Kontrola řetězu/rozvodů', 'Kontrola elektroinstalace', 'Kontrola pneumatik', 'Seřízení ventilů', 'Kontrola chladicí kapaliny', 'Celková vizuální kontrola']
  return ['Provést servisní úkon dle popisu', 'Vizuální kontrola', 'Zkušební jízda']
}

function SectionTitle({ children }) {
  return <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>{children}</h3>
}

function PartsPanel({ parts, inventoryItems, scheduleId, onAdd, onRemove, onUpdateQty }) {
  const [adding, setAdding] = useState(false)
  const [selItem, setSelItem] = useState('')
  const [selQty, setSelQty] = useState(1)
  const usedIds = new Set(parts.map(p => p.inventory_item_id))
  const available = inventoryItems.filter(i => !usedIds.has(i.id))

  return (
    <div className="ml-4 mr-2 mb-2 p-3 rounded-lg" style={{ background: '#eff6ff', border: '1px solid #bfdbfe', fontSize: 12 }}>
      <div className="font-bold text-xs uppercase tracking-wide mb-2" style={{ color: '#2563eb' }}>Díly pro tento servis</div>
      {parts.length === 0 && !adding && (
        <p style={{ color: '#6b7280', fontSize: 12 }}>Žádné díly — klikněte + Přidat díl</p>
      )}
      {parts.map(p => (
        <div key={p.id} className="flex items-center gap-2 mb-1 p-2 rounded" style={{ background: '#fff' }}>
          <span className="flex-1 font-bold">{p.inventory?.name || '—'}</span>
          <span className="font-mono" style={{ color: '#6b7280' }}>{p.inventory?.sku || ''}</span>
          <span style={{ color: (p.inventory?.stock || 0) < p.quantity ? '#dc2626' : '#1a8a18', fontWeight: 700 }}>
            sklad: {p.inventory?.stock ?? '?'}
          </span>
          <span style={{ color: '#1a2e22' }}>×</span>
          <input type="number" min={1} value={p.quantity}
            onChange={e => onUpdateQty(p.id, e.target.value)}
            className="rounded text-xs text-center outline-none" style={{ width: 40, padding: '2px 4px', border: '1px solid #d1d5db' }} />
          <button onClick={() => onRemove(p.id, scheduleId)} className="text-xs font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none' }}>×</button>
        </div>
      ))}
      {adding ? (
        <div className="flex items-center gap-2 mt-2">
          <select value={selItem} onChange={e => setSelItem(e.target.value)}
            className="rounded text-xs outline-none flex-1" style={{ padding: '4px 6px', border: '1px solid #d1d5db', background: '#fff' }}>
            <option value="">— Vyberte díl —</option>
            {available.map(i => (
              <option key={i.id} value={i.id}>{i.name} ({i.sku || '—'}) — sklad: {i.stock}</option>
            ))}
          </select>
          <input type="number" min={1} value={selQty} onChange={e => setSelQty(e.target.value)}
            className="rounded text-xs text-center outline-none" style={{ width: 40, padding: '4px', border: '1px solid #d1d5db' }} />
          <button onClick={() => { if (selItem) { onAdd(scheduleId, selItem, selQty); setAdding(false); setSelItem(''); setSelQty(1) } }}
            disabled={!selItem} className="text-xs font-bold cursor-pointer" style={{ color: '#1a8a18', background: 'none', border: 'none' }}>Přidat</button>
          <button onClick={() => setAdding(false)} className="text-xs cursor-pointer" style={{ color: '#6b7280', background: 'none', border: 'none' }}>Zrušit</button>
        </div>
      ) : (
        <button onClick={() => setAdding(true)} className="text-xs font-bold cursor-pointer mt-1" style={{ color: '#2563eb', background: 'none', border: 'none' }}>+ Přidat díl</button>
      )}
    </div>
  )
}

function Spinner() {
  return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
}
