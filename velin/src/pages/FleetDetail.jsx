import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { purgeWebCache } from '../lib/webCache'
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
import { fetchBlockingBookings, blockingBookingsMessage } from '../components/fleet/bookingGuard'

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
    const _today = new Date().toLocaleDateString('sv-SE')
    if (moto.acquired_at && moto.acquired_at > _today) {
      setError('Datum pořízení nesmí být v budoucnu.')
      setSaving(false)
      return
    }
    const normalize = v => typeof v === 'string' ? v.replace(',', '.').trim() : v
    const toInt = v => {
      const s = normalize(v)
      if (s === null || s === undefined || s === '') return null
      const n = Number(s)
      return Number.isFinite(n) ? Math.round(n) : null
    }
    const toNum = v => {
      const s = normalize(v)
      if (s === null || s === undefined || s === '') return null
      const n = Number(s)
      return Number.isFinite(n) ? n : null
    }
    const {
      // Identifikace + zařazení
      model, spz, vin, brand, category, branch_id, color, year, acquired_at, stk_valid_until, sort_order,
      // Provoz
      mileage, purchase_mileage, tracking_unit, status, purchase_price,
      // Motor / výkon
      engine_cc, engine_type, transmission, drivetrain,
      power_kw, power_hp, torque_nm, top_speed_kmh,
      // Spotřeba / palivo
      fuel_type, fuel_consumption_l100km, fuel_tank_l,
      // Brzdy / hmotnost / rozměry / komfort
      brake_type, has_abs, has_asc, weight_kg, seat_height_mm, seats_count,
      is_trailer,
      // Oprávnění + délka pronájmu
      license_required, license_groups, min_rental_days, max_rental_days,
      // Texty (auto-překládají se po uložení)
      description, features,
      // Výběr parametrů do krátkého popisu na webu
      short_desc_fields,
    } = moto
    const updateData = {
      model, spz, vin,
      brand: brand?.trim() || null,
      category, branch_id, color,
      year: toInt(year),
      acquired_at,
      stk_valid_until: stk_valid_until || null,
      sort_order: toInt(sort_order),
      mileage: toInt(mileage) ?? 0,
      purchase_mileage: toInt(purchase_mileage),
      tracking_unit: tracking_unit || 'km',
      status,
      purchase_price: toNum(purchase_price) ?? 0,
      engine_cc: toInt(engine_cc),
      engine_type,
      transmission: transmission || null,
      drivetrain: drivetrain || null,
      power_kw: toNum(power_kw),
      power_hp: toInt(power_hp),
      torque_nm: toNum(torque_nm),
      top_speed_kmh: toInt(top_speed_kmh),
      fuel_type: fuel_type || null,
      fuel_consumption_l100km: toNum(fuel_consumption_l100km),
      fuel_tank_l: toNum(fuel_tank_l),
      brake_type: brake_type || null,
      has_abs, has_asc,
      is_trailer: !!is_trailer,
      weight_kg: toInt(weight_kg),
      seat_height_mm: seat_height_mm || null,
      seats_count: toInt(seats_count),
      license_required: license_required || null,
      license_groups: Array.isArray(license_groups)
        ? license_groups.map(x => String(x).toUpperCase()).filter(Boolean)
        : (license_required ? [String(license_required).toUpperCase()] : []),
      min_rental_days: toInt(min_rental_days),
      max_rental_days: toInt(max_rental_days),
      description,
      features: Array.isArray(features) ? features.map(s => s?.trim()).filter(Boolean) : features,
      short_desc_fields: Array.isArray(short_desc_fields) ? short_desc_fields.filter(Boolean) : [],
    }
    const result = await debugAction('fleet.save', 'FleetDetail', () =>
      supabase.from('motorcycles').update(updateData).eq('id', id)
    , updateData)
    if (result?.error) setError(result.error.message)
    else purgeWebCache()
    await logAudit('motorcycle_updated', { moto_id: id })
    // Auto-překlad textových polí motorky pro web (na pozadí, neblokuje UI).
    // Web čte translations jsonb pro `description` přes localized().
    if (!result?.error) {
      const translateFields = {}
      if (description && description.trim().length > 0) translateFields.description = description
      if (Object.keys(translateFields).length > 0) {
        autoTranslateRow({ table: 'motorcycles', id, row: translateFields })
      }
    }
    setSaving(false)
  }

  async function handleDeactivate() {
    const newStatus = moto.status === 'unavailable' ? 'active' : 'unavailable'
    // Vyřazení NESMÍ rušit rezervace. Pokud má motorka aktivní/nadcházející/pending
    // rezervaci, deaktivaci zablokuj — admin každou vyřeší individuálně (úprava
    // rezervace dle dohody se zákazníkem). Aktivace zpět žádné brání.
    if (newStatus !== 'active') {
      const blocking = await fetchBlockingBookings(id)
      if (blocking.length > 0) {
        setError(blockingBookingsMessage(blocking))
        return
      }
    }
    await debugAction('fleet.toggleStatus', 'FleetDetail', () =>
      supabase.from('motorcycles').update({ status: newStatus }).eq('id', id)
    , { moto_id: id, newStatus })
    await logAudit('motorcycle_status_changed', { moto_id: id, status: newStatus })
    purgeWebCache()
    setMoto(m => ({ ...m, status: newStatus }))
  }

  async function handleDelete() {
    // Motorku s aktivní/nadcházející/pending rezervací NELZE smazat — smazáním by
    // se ztratila i zákaznická rezervace. Admin musí každou rezervaci nejdřív
    // vyřešit individuálně (úprava rezervace dle dohody se zákazníkem).
    const blocking = await fetchBlockingBookings(id)
    if (blocking.length > 0) {
      setConfirm(null)
      setError(blockingBookingsMessage(blocking))
      return
    }
    await debugAction('fleet.delete', 'FleetDetail', () =>
      supabase.from('motorcycles').delete().eq('id', id)
    , { moto_id: id })
    await logAudit('motorcycle_deleted', { moto_id: id })
    purgeWebCache()
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
        {error && <div style={{ color: '#dc2626', whiteSpace: 'pre-line' }}>{error}</div>}
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
