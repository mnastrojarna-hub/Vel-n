import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'
import Button from '../ui/Button'
import ServicePlanCard from './ServicePlanCard'
import ServiceBookCard from './ServiceBookCard'
import ServiceLogCard from '../../pages/service/ServiceLogCard'
import ServiceLogModal from '../../pages/service/ServiceLogModal'
import { fetchServiceDue, fetchServiceInvoicesMap, unitLabel, logState, LOG_STATE, fmtDate, fmtKm, audit } from '../../lib/serviceBookData'
import { useAdminIdentity } from '../../hooks/useAdminIdentity'
import { technicianLocked } from '../../pages/service/ServiceFormFields'

/**
 * Servisní knížka motorky — jedna komponenta pro detail motorky (Flotila → Servis) i Servis → Servisní knížka
 * (/servis/motorka/:id, přístup i účtu jen se sekcí Servis). Obsah: otevřené / naplánované servisy (karty technika),
 * plán údržby s hlídáním intervalů, kniha dokončených servisů. Realtime na maintenance_log motorky.
 */
export default function ServiceBook({ motoId, logAudit: logAuditProp, headerExtra }) {
  const [moto, setMoto] = useState(null)
  const [logs, setLogs] = useState([])
  const [schedules, setSchedules] = useState([])
  const [due, setDue] = useState([])
  const [invoicesByLog, setInvoicesByLog] = useState({})
  const [partsBySchedule, setPartsBySchedule] = useState({})
  const [inventoryItems, setInventoryItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [modal, setModal] = useState(null)   // { entry } | { status }
  const [saving, setSaving] = useState(false)
  const logAudit = logAuditProp || ((action, details) => audit(action, details))
  const me = useAdminIdentity()
  // běžný (servisní) účet smí upravit jen otevřené servisy a své dokončené; cizí dokončené ne (hlídá i DB trigger)
  const canEdit = (l) => !technicianLocked(me) || logState(l) !== 'completed' || (l.technician_admin_id ? l.technician_admin_id === me.id : !l.performed_by || l.performed_by === me.name)

  const loadAll = useCallback(async () => {
    const [motoRes, logRes, schedRes, invRes] = await Promise.all([
      supabase.from('motorcycles').select('id, model, spz, brand, year, status, mileage, purchase_mileage, acquired_at, tracking_unit, drivetrain, engine_type, branch_id, stk_valid_until, branches(name)').eq('id', motoId).single(),
      supabase.from('maintenance_log').select('*').eq('moto_id', motoId).order('service_date', { ascending: false }).order('created_at', { ascending: false }),
      supabase.from('maintenance_schedules').select('*').eq('moto_id', motoId).eq('active', true),
      supabase.from('inventory').select('id, name, sku, stock, unit_price, supplier_id').order('name'),
    ])
    setMoto(motoRes.data || null)
    const ls = logRes.data || []
    setLogs(ls)
    setSchedules(schedRes.data || [])
    setInventoryItems(invRes.data || [])
    const [dueRows, invMap] = await Promise.all([fetchServiceDue(motoId).catch(() => []), fetchServiceInvoicesMap(ls.map(l => l.id))])
    setDue(dueRows); setInvoicesByLog(invMap)
    const ids = (schedRes.data || []).map(s => s.id)
    if (ids.length) {
      const { data: parts } = await supabase.from('service_parts').select('*, inventory(name, sku, stock, unit_price)').in('schedule_id', ids)
      const map = {}; for (const p of (parts || [])) { (map[p.schedule_id] ||= []).push(p) }
      setPartsBySchedule(map)
    } else setPartsBySchedule({})
    setLoading(false)
  }, [motoId])

  useEffect(() => { setLoading(true); loadAll() }, [loadAll])
  useEffect(() => {
    let timer = null
    const ch = supabase.channel(`service-book-${motoId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'maintenance_log', filter: `moto_id=eq.${motoId}` }, () => { clearTimeout(timer); timer = setTimeout(loadAll, 500) })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'maintenance_schedules', filter: `moto_id=eq.${motoId}` }, () => { clearTimeout(timer); timer = setTimeout(loadAll, 500) })
      .subscribe()
    return () => { clearTimeout(timer); supabase.removeChannel(ch) }
  }, [motoId, loadAll])

  const partsApi = {
    add: async (scheduleId, itemId, qty) => { await supabase.from('service_parts').upsert({ schedule_id: scheduleId, inventory_item_id: itemId, quantity: Number(qty) || 1 }, { onConflict: 'schedule_id,inventory_item_id' }); await logAudit('service_part_added', { schedule_id: scheduleId, item_id: itemId }); loadAll() },
    remove: async (partId, scheduleId) => { await supabase.from('service_parts').delete().eq('id', partId); await logAudit('service_part_removed', { part_id: partId, schedule_id: scheduleId }); loadAll() },
    updateQty: async (partId, qty) => { await supabase.from('service_parts').update({ quantity: Number(qty) || 1 }).eq('id', partId); loadAll() },
  }

  async function handleAddSchedule(form) {
    setSaving(true)
    const intervalDays = Number(form.interval_days) || null, intervalKm = Number(form.interval_km) || null
    const { error } = await supabase.from('maintenance_schedules').insert({
      moto_id: motoId, description: form.description, interval_km: intervalKm, interval_days: intervalDays,
      schedule_type: intervalKm && intervalDays ? 'both' : intervalKm ? 'mileage' : 'time', active: true, source: 'manual',
      task_key: form.task_key || null, first_service_km: Number(form.first_service_km) || null, first_service_desc: form.first_service_desc || null,
      // baseline doplní DB trigger: poslední servis s úkonem, jinak dnešní stav / dnes
    })
    setSaving(false)
    if (error) { alert(error.code === '23505' ? 'Tento úkon už má motorka v plánu.' : `Nepodařilo se vytvořit servisní plán: ${error.message}`); return }
    await logAudit('schedule_created', { moto_id: motoId, task_key: form.task_key || null })
    loadAll()
  }

  if (loading && !moto) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
  if (!moto) return <Card><p style={{ color: '#dc2626', fontSize: 13 }}>Motorka nenalezena.</p></Card>
  const unit = unitLabel(moto)
  const open = logs.filter(l => logState(l) !== 'completed')
  const stkDays = moto.stk_valid_until ? Math.ceil((new Date(moto.stk_valid_until) - new Date()) / 86400000) : null

  return (
    <div className="space-y-5">
      <Card>
        <div className="flex items-center gap-4 flex-wrap">
          <div><div className="text-xs font-extrabold uppercase" style={{ color: '#1a2e22' }}>Stav tachometru</div><div className="text-lg font-extrabold" style={{ color: '#0f1a14' }}>{fmtKm(moto.mileage, unit)}</div></div>
          <div><div className="text-xs font-extrabold uppercase" style={{ color: '#1a2e22' }}>Pořízeno</div><div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{fmtDate(moto.acquired_at)} · {fmtKm(moto.purchase_mileage, unit)}</div></div>
          <div><div className="text-xs font-extrabold uppercase" style={{ color: '#1a2e22' }}>STK</div><div className="text-sm font-bold" style={{ color: stkDays === null ? '#6b7280' : stkDays < 30 ? '#dc2626' : stkDays < 90 ? '#b45309' : '#1a8a18' }}>{moto.stk_valid_until ? `${fmtDate(moto.stk_valid_until)} (${stkDays < 0 ? `${-stkDays} dní po` : `${stkDays} dní`})` : 'nenastaveno'}</div></div>
          <div><div className="text-xs font-extrabold uppercase" style={{ color: '#1a2e22' }}>Pohon</div><div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{{ chain: 'řetěz', shaft: 'kardan', belt: 'řemen' }[moto.drivetrain] || '—'}</div></div>
          <div className="ml-auto flex gap-2">{headerExtra}<Button green onClick={() => setModal({ status: 'pending' })}>+ Nový servisní záznam</Button></div>
        </div>
      </Card>

      {open.length > 0 && (
        <Card>
          <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#b45309' }}>Otevřené a naplánované servisy ({open.length})</h3>
          <div className="space-y-3">
            {open.map(l => {
              const st = LOG_STATE[logState(l)]
              return (
                <div key={l.id}>
                  <div className="text-xs font-bold mb-1" style={{ color: st.color }}>{st.label}{logState(l) === 'planned' ? ` · od ${fmtDate(l.service_date)}` : ''}</div>
                  <ServiceLogCard log={l} moto={moto} onReload={loadAll} />
                </div>
              )
            })}
          </div>
        </Card>
      )}

      <ServicePlanCard moto={moto} due={due} schedules={schedules} partsBySchedule={partsBySchedule} inventoryItems={inventoryItems} unitLabel={unit}
        onChanged={loadAll} logAudit={logAudit} partsApi={partsApi} onAddSchedule={handleAddSchedule} saving={saving} existingTaskKeys={schedules.map(s => s.task_key).filter(Boolean)} />

      <ServiceBookCard logs={logs} unitLabel={unit} invoicesByLog={invoicesByLog} onEdit={(l) => setModal({ entry: l })} canEdit={canEdit} />

      {modal && <ServiceLogModal entry={modal.entry || null} motoId={motoId} defaultStatus={modal.status || 'pending'} onClose={() => setModal(null)} onSaved={() => { setModal(null); loadAll() }} />}
    </div>
  )
}
