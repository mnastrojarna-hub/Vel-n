import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import StatusBadge from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import Modal from '../components/ui/Modal'
import BookingDocumentsTab from './booking/BookingDocumentsTab'
import BookingPaymentsTab from './booking/BookingPaymentsTab'
import BookingsCalendar from '../components/fleet/BookingsCalendar'

const TABS = ['Detail', 'Kalendář motorky', 'Dokumenty', 'Platby']

const ACTIONS = {
  pending: [
    { label: 'Potvrdit', status: 'reserved', green: true },
    { label: 'Zrušit', status: 'cancelled', danger: true },
  ],
  reserved: [
    { label: 'Vydat motorku', status: 'active', green: true },
    { label: 'Zrušit', status: 'cancelled', danger: true },
  ],
  active: [
    { label: 'Přijmout zpět', status: 'completed', green: true },
  ],
}

const CANCEL_REASONS = [
  { value: 'customer_app', label: 'Zrušeno zákazníkem v aplikaci' },
  { value: 'customer_web', label: 'Zrušeno zákazníkem na webu' },
  { value: 'velin', label: 'Zrušeno ve Velínu' },
  { value: 'admin', label: 'Zrušeno administrátorem (vlastní důvod)' },
  { value: 'unpaid_4h', label: 'Zrušeno pro nezaplacení po 4h' },
]

export default function BookingDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [booking, setBooking] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [tab, setTab] = useState('Detail')
  const [confirm, setConfirm] = useState(null)
  const [saving, setSaving] = useState(false)
  const [showCancelModal, setShowCancelModal] = useState(false)
  const [cancelReason, setCancelReason] = useState('')
  const [cancelReasonCustom, setCancelReasonCustom] = useState('')

  useEffect(() => { loadBooking() }, [id])

  async function loadBooking() {
    setLoading(true)
    const { data, error: err } = await supabase
      .from('bookings')
      .select('*, motorcycles(id, model, spz, status, branch_id, branches(name)), profiles(id, full_name, email, phone, city)')
      .eq('id', id).single()
    if (err) setError(err.message)
    else setBooking(data)
    setLoading(false)
  }

  async function changeStatus(newStatus) {
    setSaving(true)
    const now = new Date().toISOString()
    const update = { status: newStatus }
    if (newStatus === 'reserved') update.confirmed_at = now
    if (newStatus === 'active') update.picked_up_at = now
    if (newStatus === 'completed') update.returned_at = now

    const { error: err } = await supabase.from('bookings').update(update).eq('id', id)
    if (err) { setError(err.message); setSaving(false); return }
    await logAudit(`booking_${newStatus}`, { booking_id: id })
    setBooking(b => ({ ...b, ...update }))
    setConfirm(null); setSaving(false)
  }

  async function handleCancel() {
    setSaving(true)
    const reasonObj = CANCEL_REASONS.find(r => r.value === cancelReason)
    const reason = cancelReason === 'admin' ? cancelReasonCustom : (reasonObj?.label || cancelReason)
    if (!reason) { setError('Vyplňte důvod zrušení'); setSaving(false); return }

    const { data: { user } } = await supabase.auth.getUser()
    const updatePayload = {
      status: 'cancelled',
      cancelled_by: user?.id || null,
      cancelled_by_source: cancelReason,
      cancellation_reason: reason,
      cancelled_at: new Date().toISOString(),
    }

    const { error: err } = await supabase.from('bookings').update(updatePayload).eq('id', id)
    if (err) { setError(err.message); setSaving(false); return }
    await logAudit('booking_cancelled', { booking_id: id, reason, source: cancelReason })

    if (booking.profiles?.email) {
      try {
        await supabase.functions.invoke('send-cancellation-email', {
          body: {
            booking_id: id, customer_email: booking.profiles?.email,
            customer_name: booking.profiles?.full_name, motorcycle: booking.motorcycles?.model,
            start_date: booking.start_date, end_date: booking.end_date,
            cancellation_reason: reason, cancelled_by_source: cancelReason,
          },
        })
        await supabase.from('bookings').update({ cancellation_notified: true }).eq('id', id)
        updatePayload.cancellation_notified = true
      } catch {}
    }

    setBooking(b => ({ ...b, ...updatePayload }))
    setShowCancelModal(false); setCancelReason(''); setCancelReasonCustom(''); setSaving(false)
  }

  async function handleSave() {
    setSaving(true); setError(null)
    const { start_date, end_date, total_price, extras, notes, moto_id, user_id } = booking
    const { error: err } = await supabase.from('bookings')
      .update({ start_date, end_date, total_price, extras, notes, moto_id, user_id }).eq('id', id)
    if (err) setError(err.message)
    else await logAudit('booking_updated', { booking_id: id })
    setSaving(false)
  }

  async function logAudit(action, details) {
    try { const { data: { user } } = await supabase.auth.getUser(); await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details }) } catch {}
  }

  const set = (k, v) => setBooking(b => ({ ...b, [k]: v }))

  function handleAction(action) {
    if (action.status === 'cancelled') setShowCancelModal(true)
    else setConfirm(action)
  }

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (!booking) return <div className="p-4" style={{ color: '#8aab99' }}>{error || 'Rezervace nenalezena'}</div>

  const actions = ACTIONS[booking.status] || []

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => navigate('/rezervace')} className="cursor-pointer" style={{ background: 'none', border: 'none', fontSize: 18, color: '#8aab99' }}>←</button>
        <h2 className="font-extrabold text-lg" style={{ color: '#0f1a14' }}>Rezervace</h2>
        <span className="text-xs font-mono" style={{ color: '#8aab99' }}>#{id?.slice(0, 8)}</span>
        <StatusBadge status={booking.status} />
        <span className="text-xs" style={{ color: '#8aab99' }}>
          Vytvořena: {booking.created_at ? new Date(booking.created_at).toLocaleString('cs-CZ') : '—'}
        </span>
      </div>
      <div className="flex gap-2 mb-5 flex-wrap">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#4a6357', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>{t}</button>
        ))}
      </div>
      {tab === 'Detail' && <DetailTab booking={booking} set={set} error={error} saving={saving} onSave={handleSave} actions={actions} onAction={handleAction} navigate={navigate} />}
      {tab === 'Kalendář motorky' && booking.motorcycles?.id && <BookingsCalendar motoId={booking.motorcycles.id} />}
      {tab === 'Dokumenty' && <BookingDocumentsTab bookingId={id} />}
      {tab === 'Platby' && <BookingPaymentsTab bookingId={id} />}

      {confirm && (
        <ConfirmDialog open title={`${confirm.label}?`} message={`Změnit stav na "${confirm.label}"?`}
          danger={confirm.danger} onConfirm={() => changeStatus(confirm.status)} onCancel={() => setConfirm(null)} />
      )}

      {showCancelModal && (
        <Modal open title="Zrušit rezervaci" onClose={() => setShowCancelModal(false)}>
          <p className="text-sm mb-4" style={{ color: '#4a6357' }}>
            Zákazník bude informován emailem. Vyberte důvod zrušení:
          </p>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Důvod zrušení</label>
          <select value={cancelReason} onChange={e => setCancelReason(e.target.value)}
            className="w-full rounded-btn text-sm outline-none mb-3"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">— Vyberte důvod —</option>
            {CANCEL_REASONS.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
          </select>
          {cancelReason === 'admin' && (
            <>
              <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Vlastní důvod</label>
              <textarea value={cancelReasonCustom} onChange={e => setCancelReasonCustom(e.target.value)} rows={3}
                className="w-full rounded-btn text-sm outline-none mb-3"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
                placeholder="Popište důvod zrušení…" />
            </>
          )}
          {error && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{error}</p>}
          <div className="flex justify-end gap-3 mt-2">
            <Button onClick={() => setShowCancelModal(false)}>Zpět</Button>
            <Button onClick={handleCancel}
              disabled={saving || !cancelReason || (cancelReason === 'admin' && !cancelReasonCustom)}
              style={{ background: '#dc2626', color: '#fff', boxShadow: '0 4px 16px rgba(220,38,38,.25)' }}>
              {saving ? 'Ruším…' : 'Zrušit rezervaci'}
            </Button>
          </div>
        </Modal>
      )}
    </div>
  )
}

function DetailTab({ booking, set, error, saving, onSave, actions, onAction, navigate }) {
  return (
    <div className="grid grid-cols-2 gap-5">
      <Card>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Zákazník</h3>
          {booking.profiles?.id && (
            <button onClick={() => navigate(`/zakaznici/${booking.profiles.id}`)}
              className="text-[10px] font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>
              → Detail zákazníka
            </button>
          )}
        </div>
        <InfoRow label="Jméno" value={booking.profiles?.full_name} />
        <InfoRow label="Email" value={booking.profiles?.email} />
        <InfoRow label="Telefon" value={booking.profiles?.phone} />
        <InfoRow label="Město" value={booking.profiles?.city} />
      </Card>

      <Card>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Motorka</h3>
          {booking.motorcycles?.id && (
            <button onClick={() => navigate(`/flotila/${booking.motorcycles.id}`)}
              className="text-[10px] font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>
              → Detail motorky
            </button>
          )}
        </div>
        <InfoRow label="Model" value={booking.motorcycles?.model} />
        <InfoRow label="SPZ" value={booking.motorcycles?.spz} />
        <InfoRow label="Stav" value={booking.motorcycles?.status} />
        <InfoRow label="Pobočka" value={booking.motorcycles?.branches?.name} />
      </Card>

      <Card className="col-span-2">
        <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-4" style={{ color: '#8aab99' }}>Termín a platba</h3>
        <div className="grid grid-cols-4 gap-4">
          <FieldInput label="Od" type="date" value={booking.start_date} onChange={v => set('start_date', v)} />
          <FieldInput label="Do" type="date" value={booking.end_date} onChange={v => set('end_date', v)} />
          <FieldInput label="Celkem (Kč)" type="number" value={booking.total_price} onChange={v => set('total_price', Number(v))} />
          <FieldInput label="Poznámky" value={booking.notes} onChange={v => set('notes', v)} />
        </div>
        {error && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{error}</p>}
        <div className="flex gap-3 mt-5">
          <Button green onClick={onSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit změny'}</Button>
          {actions.map(a => (
            <Button key={a.status} onClick={() => onAction(a)} green={a.green}
              style={a.danger ? { background: '#dc2626', color: '#fff', boxShadow: '0 4px 16px rgba(220,38,38,.25)' } : undefined}>
              {a.label}
            </Button>
          ))}
        </div>
      </Card>

      {booking.status === 'cancelled' && (
        <Card className="col-span-2">
          <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-4" style={{ color: '#dc2626' }}>Informace o zrušení</h3>
          <div className="p-4 rounded-lg" style={{ background: '#fef2f2', border: '1px solid #fecaca' }}>
            <div className="grid grid-cols-2 gap-3">
              <InfoRow label="Zdroj" value={CANCEL_REASONS.find(r => r.value === booking.cancelled_by_source)?.label || booking.cancelled_by_source || '—'} />
              <InfoRow label="Kdy" value={booking.cancelled_at ? new Date(booking.cancelled_at).toLocaleString('cs-CZ') : '—'} />
              <div className="col-span-2"><InfoRow label="Důvod" value={booking.cancellation_reason || '—'} /></div>
              <InfoRow label="Email odeslán" value={booking.cancellation_notified ? 'Ano' : 'Ne'} />
            </div>
          </div>
        </Card>
      )}

      <Card className="col-span-2">
        <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-4" style={{ color: '#8aab99' }}>Timeline</h3>
        <Timeline booking={booking} />
      </Card>
    </div>
  )
}

const CANCEL_SOURCE_LABELS = Object.fromEntries(CANCEL_REASONS.map(r => [r.value, r.label]))

function InfoRow({ label, value }) {
  return (
    <div className="flex items-center gap-2 mb-1">
      <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99', minWidth: 65 }}>{label}</span>
      <span className="text-sm font-medium" style={{ color: '#0f1a14' }}>{value || '—'}</span>
    </div>
  )
}

function FieldInput({ label, type = 'text', value, onChange }) {
  return (
    <div>
      <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{label}</label>
      <input type={type} value={value || ''} onChange={e => onChange(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
    </div>
  )
}

function Timeline({ booking }) {
  const steps = [
    { label: 'Vytvořeno', done: true, time: booking.created_at },
    { label: 'Rezervováno', done: ['reserved', 'active', 'completed'].includes(booking.status), time: booking.confirmed_at },
    { label: 'Vydáno', done: ['active', 'completed'].includes(booking.status), time: booking.picked_up_at },
    { label: 'Vráceno', done: booking.status === 'completed', time: booking.returned_at },
  ]

  if (booking.status === 'cancelled') {
    const sourceLabel = CANCEL_SOURCE_LABELS[booking.cancelled_by_source] || booking.cancelled_by_source || ''
    return (
      <div>
        <div className="flex items-center gap-6 mb-4">
          {steps.filter(s => s.done || s.time).map((s, i) => (
            <div key={s.label} className="flex flex-col items-center">
              <div className="rounded-full flex items-center justify-center" style={{ width: 28, height: 28, background: '#74FB71' }}>
                <span style={{ fontSize: 14 }}>✓</span>
              </div>
              <span className="text-[10px] font-extrabold uppercase tracking-wide mt-1" style={{ color: '#1a8a18' }}>{s.label}</span>
              {s.time && <span className="text-[9px] mt-0.5" style={{ color: '#8aab99' }}>{new Date(s.time).toLocaleString('cs-CZ')}</span>}
            </div>
          ))}
        </div>
        <div className="p-4 rounded-lg" style={{ background: '#fee2e2' }}>
          <span style={{ color: '#dc2626', fontWeight: 700, fontSize: 13 }}>Zrušena</span>
          {booking.cancelled_at && <span className="ml-3 text-xs" style={{ color: '#dc2626' }}>{new Date(booking.cancelled_at).toLocaleString('cs-CZ')}</span>}
          {sourceLabel && <span className="ml-3 text-xs font-bold" style={{ color: '#991b1b' }}>— {sourceLabel}</span>}
        </div>
      </div>
    )
  }
  return (
    <div className="flex items-start">
      {steps.map((s, i) => (
        <div key={s.label} className="flex items-center">
          <div className="flex flex-col items-center">
            <div className="rounded-full flex items-center justify-center" style={{ width: 28, height: 28, background: s.done ? '#74FB71' : '#f1faf7', border: s.done ? 'none' : '2px solid #d4e8e0' }}>
              {s.done && <span style={{ fontSize: 14 }}>✓</span>}
            </div>
            <span className="text-[10px] font-extrabold uppercase tracking-wide mt-1" style={{ color: s.done ? '#1a8a18' : '#8aab99' }}>{s.label}</span>
            {s.time && <span className="text-[9px] mt-0.5" style={{ color: '#8aab99' }}>{new Date(s.time).toLocaleString('cs-CZ')}</span>}
          </div>
          {i < steps.length - 1 && <div style={{ width: 60, height: 2, background: s.done ? '#74FB71' : '#d4e8e0', margin: '0 4px', marginBottom: 20 }} />}
        </div>
      ))}
    </div>
  )
}
