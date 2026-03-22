import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import { SmallActionBtn } from './BookingUIHelpers'

export default function ComplaintsTab({ bookingId, booking, setBooking }) {
  const [complaints, setComplaints] = useState([])
  const [loading, setLoading] = useState(true)
  const [showAdd, setShowAdd] = useState(false)
  const [form, setForm] = useState({ subject: '', description: '' })
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => { load() }, [bookingId])

  async function load() {
    setLoading(true)
    const { data } = await supabase.from('booking_complaints').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false })
    setComplaints(data || [])
    setLoading(false)
  }

  async function handleAdd() {
    if (!form.subject.trim()) return
    setSaving(true); setError(null)
    try {
      const { error: err } = await supabase.from('booking_complaints').insert({
        booking_id: bookingId, customer_id: booking?.user_id || null,
        subject: form.subject, description: form.description,
      })
      if (err) throw err
      await supabase.from('bookings').update({ complaint_status: 'open' }).eq('id', bookingId)
      if (setBooking) setBooking(b => ({ ...b, complaint_status: 'open' }))
      setForm({ subject: '', description: '' })
      setShowAdd(false)
      load()
    } catch (e) { setError(e.message) } finally { setSaving(false) }
  }

  async function updateStatus(complaintId, status) {
    await supabase.from('booking_complaints').update({ status, updated_at: new Date().toISOString(), ...(status === 'resolved' ? { resolved_at: new Date().toISOString() } : {}) }).eq('id', complaintId)
    const newBookingStatus = status === 'resolved' || status === 'rejected' ? null : status
    await supabase.from('bookings').update({ complaint_status: newBookingStatus }).eq('id', bookingId)
    if (setBooking) setBooking(b => ({ ...b, complaint_status: newBookingStatus }))
    load()
  }

  const statusLabels = { open: 'Otevřeno', in_progress: 'Řeší se', resolved: 'Vyřešeno', rejected: 'Zamítnuto' }
  const statusColors = { open: '#b45309', in_progress: '#2563eb', resolved: '#1a8a18', rejected: '#6b7280' }
  const statusBgs = { open: '#fef3c7', in_progress: '#dbeafe', resolved: '#dcfce7', rejected: '#f3f4f6' }

  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Reklamace</h3>
        <Button green onClick={() => setShowAdd(!showAdd)}>+ Nová reklamace</Button>
      </div>

      {showAdd && (
        <div className="mb-4 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="space-y-2">
            <input value={form.subject} onChange={e => setForm(f => ({ ...f, subject: e.target.value }))} placeholder="Předmět reklamace" className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#fff', border: '1px solid #d4e8e0' }} />
            <textarea value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} placeholder="Popis reklamace…" rows={3} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#fff', border: '1px solid #d4e8e0', resize: 'vertical' }} />
          </div>
          {error && <p className="text-sm mt-2" style={{ color: '#dc2626' }}>{error}</p>}
          <div className="flex gap-2 mt-3">
            <Button green onClick={handleAdd} disabled={saving || !form.subject.trim()}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
            <Button onClick={() => setShowAdd(false)}>Zrušit</Button>
          </div>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
      ) : complaints.length === 0 ? (
        <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné reklamace</p>
      ) : (
        <div className="space-y-3">
          {complaints.map(c => (
            <div key={c.id} className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <div className="flex items-center gap-2 mb-2">
                <span className="font-bold text-sm" style={{ color: '#0f1a14' }}>{c.subject}</span>
                <span className="text-sm font-extrabold uppercase px-2 py-0.5 rounded-btn" style={{ background: statusBgs[c.status] || '#f3f4f6', color: statusColors[c.status] || '#6b7280' }}>
                  {statusLabels[c.status] || c.status}
                </span>
                <span className="text-sm ml-auto" style={{ color: '#1a2e22' }}>{c.created_at ? new Date(c.created_at).toLocaleString('cs-CZ') : ''}</span>
              </div>
              {c.description && <p className="text-sm mb-2" style={{ color: '#1a2e22' }}>{c.description}</p>}
              {c.resolution && <p className="text-sm mb-2" style={{ color: '#1a8a18' }}><strong>Řešení:</strong> {c.resolution}</p>}
              {c.status !== 'resolved' && c.status !== 'rejected' && (
                <div className="flex gap-1 mt-2">
                  {c.status === 'open' && <SmallActionBtn onClick={() => updateStatus(c.id, 'in_progress')} color="#2563eb" bg="#dbeafe">Řešit</SmallActionBtn>}
                  <SmallActionBtn onClick={() => updateStatus(c.id, 'resolved')} color="#1a8a18" bg="#dcfce7">Vyřešeno</SmallActionBtn>
                  <SmallActionBtn onClick={() => updateStatus(c.id, 'rejected')} color="#6b7280" bg="#f3f4f6">Zamítnout</SmallActionBtn>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </Card>
  )
}
