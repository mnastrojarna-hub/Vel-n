import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction, debugLog } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import StatusBadge from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import Modal from '../components/ui/Modal'
import MotoActionModal from '../components/fleet/MotoActionModal'
import BookingsCalendar from '../components/fleet/BookingsCalendar'
import ServiceTab from '../components/fleet/ServiceTab'
import PricingTab from '../components/fleet/PricingTab'
import MotoMap from '../components/shared/MotoMap'
import InfoTab from './FleetDetailInfoTab'
import { PerformanceTab } from './FleetDetailPhotos'
import { autoTranslateRow } from '../lib/autoTranslate'

const TABS = ['Info', 'Rezervace', 'Ceník', 'Servis', 'Mapa', 'Výkon']

export default function FleetDetail() {
  const debugMode = useDebugMode()
  const { id } = useParams()
  const navigate = useNavigate()
  const [moto, setMoto] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [tab, setTab] = useState('Info')
  const [confirm, setConfirm] = useState(null)
  const [showActionModal, setShowActionModal] = useState(false)

  useEffect(() => { loadMoto() }, [id])

  async function loadMoto() {
    setLoading(true)
    const result = await debugAction('fleet.load', 'FleetDetail', () =>
      supabase.from('motorcycles').select('*, branches(id, name)').eq('id', id).single()
    , { moto_id: id })
    if (result?.error) setError(result.error.message)
    else setMoto(result?.data)
    setLoading(false)
  }

  async function handleSave() {
    setSaving(true); setError(null)
    const toInt = v => {
      if (v === null || v === undefined || v === '') return null
      const n = Number(v)
      return Number.isFinite(n) ? Math.round(n) : null
    }
    const toNum = v => {
      if (v === null || v === undefined || v === '') return null
      const n = Number(v)
      return Number.isFinite(n) ? n : null
    }
    const { model, spz, vin, category, branch_id, mileage, purchase_mileage, status, year, engine_cc, color, acquired_at,
      power_kw, torque_nm, weight_kg, fuel_tank_l, seat_height_mm, license_required,
      has_abs, has_asc, description, ideal_usage, features, engine_type, brand, purchase_price, tracking_unit, stk_valid_until } = moto
    const updateData = { model, spz, vin, category, branch_id,
      mileage: toInt(mileage) ?? 0,
      purchase_mileage: toInt(purchase_mileage),
      status,
      year: toInt(year),
      engine_cc: toInt(engine_cc),
      color, acquired_at,
      power_kw: toNum(power_kw),
      torque_nm: toNum(torque_nm),
      weight_kg: toInt(weight_kg),
      fuel_tank_l: toNum(fuel_tank_l),
      seat_height_mm: seat_height_mm || null,
      license_required: license_required || null,
      has_abs, has_asc, description,
      ideal_usage: Array.isArray(ideal_usage) ? ideal_usage.map(s => s?.trim()).filter(Boolean) : ideal_usage,
      features: Array.isArray(features) ? features.map(s => s?.trim()).filter(Boolean) : features,
      engine_type,
      brand: brand?.trim() || null,
      purchase_price: toNum(purchase_price) ?? 0,
      tracking_unit: tracking_unit || 'km', stk_valid_until: stk_valid_until || null }
    const result = await debugAction('fleet.save', 'FleetDetail', () =>
      supabase.from('motorcycles').update(updateData).eq('id', id)
    , updateData)
    if (result?.error) setError(result.error.message)
    await logAudit('motorcycle_updated', { moto_id: id })
    // Auto-překlad popisku motorky pro web (na pozadí, neblokuje UI)
    if (!result?.error && description && description.trim().length > 0) {
      autoTranslateRow({ table: 'motorcycles', id, row: { description } })
    }
    setSaving(false)
  }

  async function handleDeactivate() {
    const { data: activeBookings } = await debugAction('fleet.checkBookings', 'FleetDetail', () =>
      supabase.from('bookings').select('id, user_id, start_date, end_date, status, profiles(full_name)')
        .eq('moto_id', id).in('status', ['pending', 'active', 'reserved'])
    , { moto_id: id })
    if (activeBookings?.length > 0) {
      setConfirm({ type: 'deactivate', title: `${activeBookings.length} aktivních rezervací`, message: 'Při deaktivaci budou stornovány. Pokračovat?',
        action: async () => {
          const newStatus = moto.status === 'unavailable' ? 'active' : 'unavailable'
          await debugAction('fleet.deactivate', 'FleetDetail', async () => {
            await supabase.from('motorcycles').update({ status: newStatus }).eq('id', id)
            if (newStatus !== 'active') {
              for (const b of activeBookings) await supabase.from('bookings').update({ status: 'cancelled', notes: 'Motorka vyřazena' }).eq('id', b.id)
            }
            return { data: { status: newStatus, affected: activeBookings.length } }
          }, { moto_id: id, newStatus })
          await logAudit('motorcycle_status_changed', { moto_id: id, status: newStatus, affected: activeBookings.length })
          setMoto(m => ({ ...m, status: newStatus })); setConfirm(null)
        },
      })
      return
    }
    const newStatus = moto.status === 'unavailable' ? 'active' : 'unavailable'
    await debugAction('fleet.toggleStatus', 'FleetDetail', () =>
      supabase.from('motorcycles').update({ status: newStatus }).eq('id', id)
    , { moto_id: id, newStatus })
    await logAudit('motorcycle_status_changed', { moto_id: id, status: newStatus })
    setMoto(m => ({ ...m, status: newStatus }))
  }

  async function handleDelete() {
    await debugAction('fleet.delete', 'FleetDetail', () =>
      supabase.from('motorcycles').delete().eq('id', id)
    , { moto_id: id })
    await logAudit('motorcycle_deleted', { moto_id: id })
    navigate('/flotila')
  }

  async function logAudit(action, details) {
    try { const { data: { user } } = await supabase.auth.getUser(); await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details }) } catch {}
  }

  const set = (k, v) => setMoto(m => ({ ...m, [k]: v }))

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (!moto) return <div className="p-4" style={{ color: '#1a2e22' }}>{error || 'Motorka nenalezena'}</div>

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => navigate('/flotila')} className="cursor-pointer" style={{ background: 'none', border: 'none', fontSize: 18, color: '#1a2e22' }}>←</button>
        <h2 className="font-extrabold text-lg" style={{ color: '#0f1a14' }}>{moto.model}</h2>
        <StatusBadge status={moto.status} />
        <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>{moto.spz}</span>
        <button onClick={() => setShowActionModal(true)}
          className="rounded-btn text-sm font-extrabold uppercase cursor-pointer ml-auto"
          style={{ padding: '6px 14px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
          Správa motorky
        </button>
      </div>
      <div className="flex gap-2 mb-5 flex-wrap">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#1a2e22', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>{t}</button>
        ))}
      </div>
      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA FleetDetail (#{id?.slice(-8)})</strong><br/>
        <div>moto: {moto.model} ({moto.spz}), status={moto.status}, category={moto.category || '—'}</div>
        <div>branch: {moto.branches?.name || '—'}, mileage: {moto.mileage?.toLocaleString('cs-CZ') || 0} {moto.tracking_unit === 'mh' ? 'MH' : 'km'}</div>
        <div>year: {moto.year || '—'}, engine: {moto.engine_cc || '—'}cc, power: {moto.power_kw || '—'}kW</div>
        <div>STK: {moto.stk_valid_until || '—'}, tab: {tab}</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

      {tab === 'Info' && <InfoTab moto={moto} set={set} error={error} saving={saving} onSave={handleSave} onDeactivate={handleDeactivate} onDelete={() => setConfirm({ type: 'delete' })} onMotoReload={loadMoto} />}
      {tab === 'Rezervace' && <BookingsCalendar motoId={id} onSwitchTab={setTab} />}
      {tab === 'Ceník' && <PricingTab motoId={id} />}
      {tab === 'Servis' && <ServiceTab motoId={id} motoMileage={moto.mileage} purchaseMileage={moto.purchase_mileage} trackingUnit={moto.tracking_unit || 'km'} logAudit={logAudit} />}
      {tab === 'Mapa' && <MotoMap singleMotoId={id} />}
      {tab === 'Výkon' && <PerformanceTab motoId={id} />}
      <ConfirmDialog open={confirm?.type === 'deactivate'} title={confirm?.title || ''} message={confirm?.message || ''} onConfirm={() => confirm?.action?.()} onCancel={() => setConfirm(null)} danger />
      <ConfirmDialog open={confirm?.type === 'delete'} title="Smazat motorku?" message="Tato akce je nevratná." danger onConfirm={handleDelete} onCancel={() => setConfirm(null)} />
      <MotoActionModal open={showActionModal} moto={moto} onClose={() => setShowActionModal(false)} onUpdated={() => { loadMoto(); setShowActionModal(false) }} />
    </div>
  )
}
