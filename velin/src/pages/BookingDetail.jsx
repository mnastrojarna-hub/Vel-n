import { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import StatusBadge from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'

const TABS = ['Detail', 'Dokumenty', 'Platby']

const ACTIONS = {
  pending: [
    { label: 'Potvrdit', status: 'confirmed', green: true },
    { label: 'Zrušit', status: 'cancelled', danger: true },
  ],
  confirmed: [
    { label: 'Vydat motorku', status: 'active', green: true },
    { label: 'Zrušit', status: 'cancelled', danger: true },
  ],
  active: [
    { label: 'Přijmout zpět', status: 'completed', green: true },
  ],
}

export default function BookingDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [booking, setBooking] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [tab, setTab] = useState('Detail')
  const [confirm, setConfirm] = useState(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => { loadBooking() }, [id])

  async function loadBooking() {
    setLoading(true)
    const { data, error: err } = await supabase
      .from('bookings')
      .select('*, motorcycles(id, model, spz, price_per_day, status), profiles(id, full_name, email, phone, city)')
      .eq('id', id).single()
    if (err) setError(err.message)
    else setBooking(data)
    setLoading(false)
  }

  async function changeStatus(newStatus) {
    setSaving(true)
    const { error: err } = await supabase.from('bookings').update({ status: newStatus }).eq('id', id)
    if (err) { setError(err.message); setSaving(false); return }
    await logAudit(`booking_${newStatus}`, { booking_id: id })
    setBooking(b => ({ ...b, status: newStatus }))
    setConfirm(null); setSaving(false)
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

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (!booking) return <div className="p-4" style={{ color: '#8aab99' }}>{error || 'Rezervace nenalezena'}</div>

  const actions = ACTIONS[booking.status] || []

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => navigate('/rezervace')} className="cursor-pointer" style={{ background: 'none', border: 'none', fontSize: 18, color: '#8aab99' }}>←</button>
        <h2 className="font-extrabold text-lg" style={{ color: '#0f1a14' }}>Rezervace</h2>
        <span className="text-xs font-mono" style={{ color: '#8aab99' }}>{id?.slice(0, 8)}</span>
        <StatusBadge status={booking.status} />
      </div>
      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#4a6357', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>{t}</button>
        ))}
      </div>
      {tab === 'Detail' && <DetailTab booking={booking} set={set} error={error} saving={saving} onSave={handleSave} actions={actions} onAction={setConfirm} navigate={navigate} />}
      {tab === 'Dokumenty' && <DocumentsTab bookingId={id} />}
      {tab === 'Platby' && <PaymentsTab bookingId={id} />}

      {confirm && (
        <ConfirmDialog open title={`${confirm.label}?`} message={`Změnit stav na "${confirm.label}"?`}
          danger={confirm.danger} onConfirm={() => changeStatus(confirm.status)} onCancel={() => setConfirm(null)} />
      )}
    </div>
  )
}

function DetailTab({ booking, set, error, saving, onSave, actions, onAction, navigate }) {
  return (
    <div className="grid grid-cols-2 gap-5">
      {/* Zákazník — proklik na detail */}
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

      {/* Motorka — proklik na detail */}
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
        <InfoRow label="Cena/den" value={booking.motorcycles?.price_per_day ? `${booking.motorcycles.price_per_day.toLocaleString('cs-CZ')} Kč` : '—'} />
      </Card>

      {/* Termín, platba, poznámky — editovatelné */}
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

      <Card className="col-span-2">
        <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-4" style={{ color: '#8aab99' }}>Timeline</h3>
        <Timeline status={booking.status} createdAt={booking.created_at} />
      </Card>
    </div>
  )
}

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

function Timeline({ status, createdAt }) {
  const steps = [
    { label: 'Vytvořeno', done: true, date: createdAt },
    { label: 'Potvrzeno', done: ['confirmed', 'active', 'completed'].includes(status) },
    { label: 'Vydáno', done: ['active', 'completed'].includes(status) },
    { label: 'Vráceno', done: status === 'completed' },
  ]
  if (status === 'cancelled') return <div className="p-3 rounded-lg" style={{ background: '#fee2e2' }}><span style={{ color: '#dc2626', fontWeight: 700, fontSize: 13 }}>Zrušena</span></div>
  return (
    <div className="flex items-center">
      {steps.map((s, i) => (
        <div key={s.label} className="flex items-center">
          <div className="flex flex-col items-center">
            <div className="rounded-full flex items-center justify-center" style={{ width: 28, height: 28, background: s.done ? '#74FB71' : '#f1faf7', border: s.done ? 'none' : '2px solid #d4e8e0' }}>
              {s.done && <span style={{ fontSize: 14 }}>✓</span>}
            </div>
            <span className="text-[10px] font-extrabold uppercase tracking-wide mt-1" style={{ color: s.done ? '#1a8a18' : '#8aab99' }}>{s.label}</span>
          </div>
          {i < steps.length - 1 && <div style={{ width: 60, height: 2, background: s.done ? '#74FB71' : '#d4e8e0', margin: '0 4px' }} />}
        </div>
      ))}
    </div>
  )
}

function DocumentsTab({ bookingId }) {
  const [docs, setDocs] = useState([])
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    supabase.from('documents').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false })
      .then(({ data }) => { setDocs(data || []); setLoading(false) }).catch(() => { setDocs([]); setLoading(false) })
  }, [bookingId])
  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
  return (
    <Card>
      {docs.length === 0 ? <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné dokumenty</p> :
        docs.map(d => (
          <div key={d.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#f1faf7' }}>
            <span className="text-sm font-bold">{d.name || d.type || 'Dokument'}</span>
            <span className="text-xs" style={{ color: '#8aab99' }}>{d.created_at?.slice(0, 10)}</span>
          </div>
        ))}
    </Card>
  )
}

function PaymentsTab({ bookingId }) {
  const [entries, setEntries] = useState([])
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    supabase.from('accounting_entries').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false })
      .then(({ data }) => { setEntries(data || []); setLoading(false) }).catch(() => { setEntries([]); setLoading(false) })
  }, [bookingId])
  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
  return (
    <Card>
      {entries.length === 0 ? <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné platby</p> :
        entries.map(e => (
          <div key={e.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#f1faf7' }}>
            <div className="flex-1">
              <span className="text-sm font-bold">{e.description || 'Platba'}</span>
              <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{e.created_at?.slice(0, 10)}</span>
            </div>
            <span className="text-sm font-bold" style={{ color: e.amount >= 0 ? '#1a8a18' : '#dc2626' }}>{e.amount?.toLocaleString('cs-CZ')} Kč</span>
          </div>
        ))}
    </Card>
  )
}
