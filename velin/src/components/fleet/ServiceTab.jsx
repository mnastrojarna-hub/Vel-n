import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'
import Button from '../ui/Button'
import Badge from '../ui/Badge'
import ConfirmDialog from '../ui/ConfirmDialog'
import Modal from '../ui/Modal'

/* ═══ SERVIS TAB — editovatelné intervaly + objednávky pro technika ═══ */
export default function ServiceTab({ motoId, motoMileage, logAudit }) {
  const [logs, setLogs] = useState([])
  const [schedules, setSchedules] = useState([])
  const [loading, setLoading] = useState(true)
  const [confirmService, setConfirmService] = useState(null)
  const [showOrder, setShowOrder] = useState(null)
  const [editing, setEditing] = useState(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => { loadAll() }, [motoId])

  async function loadAll() {
    setLoading(true)
    const [logRes, schedRes] = await Promise.all([
      supabase.from('maintenance_log').select('*').eq('moto_id', motoId).order('created_at', { ascending: false }),
      supabase.from('maintenance_schedules').select('*').eq('moto_id', motoId).eq('active', true),
    ])
    console.log('[ServiceTab] loadAll', { motoId, logs: logRes.data?.length, logsError: logRes.error, scheds: schedRes.data?.length, schedsError: schedRes.error })
    if (logRes.error) console.error('[ServiceTab] logs query failed:', logRes.error)
    if (schedRes.error) console.error('[ServiceTab] schedules query failed:', schedRes.error)
    setLogs(logRes.data || [])
    setSchedules(schedRes.data || [])
    setLoading(false)
  }

  async function handleSaveSchedule(sched) {
    setSaving(true)
    await supabase.from('maintenance_schedules').update({
      description: sched.description,
      interval_km: Number(sched.interval_km) || 0,
      interval_days: Number(sched.interval_days) || null,
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
      moto_id: motoId, service_type: schedule.description,
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
      {/* Servisní plány — editovatelné */}
      <Card>
        <div className="flex items-center justify-between mb-4">
          <SectionTitle>Servisní intervaly</SectionTitle>
          <AddScheduleBtn onAdd={handleAddSchedule} saving={saving} />
        </div>
        {schedules.length === 0 ? <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné servisní plány</p> : (
          <div className="space-y-3">
            {schedules.map(s => {
              const currentKm = Number(motoMileage) || 0
              const nextAt = (s.last_service_km || 0) + (s.interval_km || 0)
              const remaining = nextAt - currentKm
              const overdue = remaining <= 0
              const isEditing = editing === s.id

              if (isEditing) return (
                <ScheduleEditRow key={s.id} schedule={s} saving={saving}
                  onSave={handleSaveSchedule} onCancel={() => setEditing(null)} />
              )

              return (
                <div key={s.id} className="flex items-center gap-3 p-3 rounded-lg" style={{ background: overdue ? '#fee2e2' : '#f1faf7' }}>
                  <div className="flex-1">
                    <span className="font-bold text-sm">{s.description}</span>
                    <span className="text-sm ml-3" style={{ color: '#1a2e22' }}>
                      každých {s.interval_km?.toLocaleString('cs-CZ')} km
                      {s.interval_days ? ` / ${s.interval_days} dní` : ''}
                    </span>
                    <span className="text-sm ml-2" style={{ color: overdue ? '#dc2626' : '#1a8a18', fontWeight: 700 }}>
                      {overdue ? `PO TERMÍNU ${Math.abs(remaining).toLocaleString('cs-CZ')} km` : `za ${remaining.toLocaleString('cs-CZ')} km`}
                    </span>
                  </div>
                  <button onClick={() => setEditing(s.id)} className="text-sm font-bold cursor-pointer" style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Upravit</button>
                  <button onClick={() => handleDeleteSchedule(s.id)} className="text-sm font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none' }}>×</button>
                  <Button green onClick={() => setConfirmService(s)}>Potvrdit servis</Button>
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
                    <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{l.service_type || l.type || 'Servis'}</span>
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
        message={`Bude vytvořena objednávka pro technika. Tachometr: ${Number(motoMileage || 0).toLocaleString('cs-CZ')} km.`}
        onConfirm={() => confirmService && handleConfirmService(confirmService)}
        onCancel={() => setConfirmService(null)}
      />

      {showOrder && (
        <Modal open title="Servisní objednávka" onClose={() => setShowOrder(null)}>
          <div className="p-4 rounded-lg mb-3" style={{ background: '#dcfce7' }}>
            <div className="text-sm font-bold mb-1" style={{ color: '#166534' }}>{showOrder.type}</div>
            <div className="text-sm" style={{ color: '#1a2e22' }}>Km: {showOrder.km.toLocaleString('cs-CZ')} | {showOrder.created_at.slice(0, 10)}</div>
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

function ScheduleEditRow({ schedule, saving, onSave, onCancel }) {
  const [form, setForm] = useState({ ...schedule })
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '2px solid #74FB71' }}>
      <div className="grid grid-cols-3 gap-2 mb-2">
        <input value={form.description || ''} onChange={e => set('description', e.target.value)} placeholder="Popis" className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
        <input type="number" value={form.interval_km || ''} onChange={e => set('interval_km', e.target.value)} placeholder="Interval km" className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
        <input type="number" value={form.interval_days || ''} onChange={e => set('interval_days', e.target.value)} placeholder="Interval dní" className="rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }} />
      </div>
      <div className="flex gap-2">
        <Button green onClick={() => onSave(form)} disabled={saving}>Uložit</Button>
        <Button onClick={onCancel}>Zrušit</Button>
      </div>
    </div>
  )
}

function AddScheduleBtn({ onAdd, saving }) {
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState({ description: '', interval_km: '', interval_days: '' })
  if (!open) return <button onClick={() => setOpen(true)} className="text-sm font-bold cursor-pointer" style={{ color: '#1a8a18', background: 'none', border: 'none' }}>+ Přidat plán</button>
  return (
    <div className="flex gap-2 items-center">
      <input value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} placeholder="Popis" className="rounded-btn text-sm outline-none" style={{ padding: '5px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', width: 120 }} />
      <input type="number" value={form.interval_km} onChange={e => setForm(f => ({ ...f, interval_km: e.target.value }))} placeholder="km" className="rounded-btn text-sm outline-none" style={{ padding: '5px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', width: 70 }} />
      <input type="number" value={form.interval_days} onChange={e => setForm(f => ({ ...f, interval_days: e.target.value }))} placeholder="dní" className="rounded-btn text-sm outline-none" style={{ padding: '5px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', width: 70 }} />
      <Button green onClick={() => { onAdd(form); setOpen(false); setForm({ description: '', interval_km: '', interval_days: '' }) }} disabled={saving || !form.description}>OK</Button>
      <Button onClick={() => setOpen(false)}>×</Button>
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

function Spinner() {
  return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
}
