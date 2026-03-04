import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { isDemoMode, CUSTOMERS } from '../lib/demoData'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import StatusBadge from '../components/ui/StatusBadge'

const TABS = ['Profil', 'Rezervace', 'Dokumenty', 'Hodnocení', 'SOS']

export default function CustomerDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [customer, setCustomer] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [tab, setTab] = useState('Profil')

  useEffect(() => { loadCustomer() }, [id])

  async function loadCustomer() {
    setLoading(true)
    if (isDemoMode()) {
      const found = CUSTOMERS.find(c => String(c.id) === String(id)) || CUSTOMERS[0]
      setCustomer({ ...found, full_name: found.name })
      setLoading(false)
      return
    }
    try {
      const { data, error: err } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', id)
        .single()
      if (err) setError(err.message)
      else setCustomer(data)
    } catch (e) {
      const found = CUSTOMERS.find(c => String(c.id) === String(id)) || CUSTOMERS[0]
      setCustomer({ ...found, full_name: found.name })
    }
    setLoading(false)
  }

  async function handleSave() {
    setSaving(true)
    setError(null)
    const { full_name, email, phone, address, driver_license } = customer
    const { error: err } = await supabase
      .from('profiles')
      .update({ full_name, email, phone, address, driver_license })
      .eq('id', id)
    if (err) setError(err.message)
    else {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'customer_updated', details: { customer_id: id },
      })
    }
    setSaving(false)
  }

  const set = (k, v) => setCustomer(c => ({ ...c, [k]: v }))

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (error && !customer) return <div className="p-4 rounded-card" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>
  if (!customer) return <div className="p-4" style={{ color: '#8aab99' }}>Zákazník nenalezen</div>

  const score = customer.reliability_score

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => navigate('/zakaznici')} className="cursor-pointer" style={{ background: 'none', border: 'none', fontSize: 18, color: '#8aab99' }}>←</button>
        <h2 className="font-extrabold text-lg" style={{ color: '#0f1a14' }}>{customer.full_name || 'Zákazník'}</h2>
        {score && (
          <span className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide" style={{ padding: '4px 12px', background: getScoreColor(score).bg, color: getScoreColor(score).color }}>
            Skóre: {typeof score === 'object' ? score.total || '—' : score}
          </span>
        )}
      </div>

      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer" style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#4a6357', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {t}
          </button>
        ))}
      </div>

      {tab === 'Profil' && <ProfileTab customer={customer} set={set} error={error} saving={saving} onSave={handleSave} />}
      {tab === 'Rezervace' && <CustomerBookings userId={id} />}
      {tab === 'Dokumenty' && <CustomerDocuments userId={id} />}
      {tab === 'Hodnocení' && <CustomerReviews userId={id} />}
      {tab === 'SOS' && <CustomerSOS userId={id} />}
    </div>
  )
}

function getScoreColor(score) {
  const val = typeof score === 'object' ? score.total : Number(score)
  if (val >= 80) return { color: '#1a8a18', bg: '#dcfce7' }
  if (val >= 50) return { color: '#b45309', bg: '#fef3c7' }
  return { color: '#dc2626', bg: '#fee2e2' }
}

function ProfileTab({ customer, set, error, saving, onSave }) {
  return (
    <Card>
      <div className="grid grid-cols-2 gap-4">
        <Field label="Jméno" value={customer.full_name} onChange={v => set('full_name', v)} />
        <Field label="Email" value={customer.email} onChange={v => set('email', v)} />
        <Field label="Telefon" value={customer.phone} onChange={v => set('phone', v)} />
        <Field label="Řidičský průkaz" value={customer.driver_license} onChange={v => set('driver_license', v)} />
        <div className="col-span-2">
          <Field label="Adresa" value={customer.address} onChange={v => set('address', v)} />
        </div>
        <Field label="Registrace" value={customer.created_at?.slice(0, 10)} disabled />
      </div>
      {error && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{error}</p>}
      <div className="flex gap-3 mt-6">
        <Button green onClick={onSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Card>
  )
}

function Field({ label, value, onChange, type = 'text', disabled = false }) {
  return (
    <div>
      <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{label}</label>
      <input type={type} value={value || ''} onChange={e => onChange?.(e.target.value)} disabled={disabled} className="w-full rounded-btn text-sm outline-none disabled:opacity-50" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}

function CustomerBookings({ userId }) {
  const [bookings, setBookings] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('bookings').select('*, motorcycles(model, spz)').eq('user_id', userId).order('start_date', { ascending: false })
      .then(({ data }) => { setBookings(data || []); setLoading(false) })
  }, [userId])

  if (loading) return <LoadingSpinner />

  return (
    <Card>
      {bookings.length === 0 ? <EmptyState text="Žádné rezervace" /> : (
        <div className="space-y-3">
          {bookings.map(b => (
            <div key={b.id} className="flex items-center gap-4 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
              <div className="flex-1">
                <span className="font-bold text-sm">{b.motorcycles?.model || '—'}</span>
                <span className="text-xs font-mono ml-2" style={{ color: '#8aab99' }}>{b.motorcycles?.spz}</span>
                <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{b.start_date} → {b.end_date}</span>
              </div>
              <StatusBadge status={b.status} />
              <span className="text-sm font-bold">{b.total_price?.toLocaleString('cs-CZ')} Kč</span>
            </div>
          ))}
        </div>
      )}
    </Card>
  )
}

function CustomerDocuments({ userId }) {
  const [docs, setDocs] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('documents').select('*').eq('user_id', userId).order('created_at', { ascending: false })
      .then(({ data }) => { setDocs(data || []); setLoading(false) })
  }, [userId])

  if (loading) return <LoadingSpinner />

  return (
    <Card>
      {docs.length === 0 ? <EmptyState text="Žádné dokumenty" /> : (
        <div className="space-y-3">
          {docs.map(d => (
            <div key={d.id} className="flex items-center gap-4 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
              <span className="font-bold text-sm">{d.name || d.type || 'Dokument'}</span>
              <span className="text-xs" style={{ color: '#8aab99' }}>{d.created_at?.slice(0, 10)}</span>
            </div>
          ))}
        </div>
      )}
    </Card>
  )
}

function CustomerReviews({ userId }) {
  const [reviews, setReviews] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('reviews').select('*').eq('user_id', userId).order('created_at', { ascending: false })
      .then(({ data }) => { setReviews(data || []); setLoading(false) })
  }, [userId])

  if (loading) return <LoadingSpinner />

  return (
    <Card>
      {reviews.length === 0 ? <EmptyState text="Žádná hodnocení" /> : (
        <div className="space-y-3">
          {reviews.map(r => (
            <div key={r.id} className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
              <div className="flex items-center gap-2 mb-1">
                <span className="font-bold text-sm">{'★'.repeat(r.rating || 0)}{'☆'.repeat(5 - (r.rating || 0))}</span>
                <span className="text-xs" style={{ color: '#8aab99' }}>{r.created_at?.slice(0, 10)}</span>
              </div>
              <p className="text-sm" style={{ color: '#4a6357' }}>{r.comment || '—'}</p>
            </div>
          ))}
        </div>
      )}
    </Card>
  )
}

function CustomerSOS({ userId }) {
  const [incidents, setIncidents] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('sos_incidents').select('*, bookings!inner(user_id)').eq('bookings.user_id', userId).order('created_at', { ascending: false })
      .then(({ data }) => { setIncidents(data || []); setLoading(false) })
  }, [userId])

  if (loading) return <LoadingSpinner />

  return (
    <Card>
      {incidents.length === 0 ? <EmptyState text="Žádné SOS incidenty" /> : (
        <div className="space-y-3">
          {incidents.map(s => (
            <div key={s.id} className="flex items-center gap-4 p-3 rounded-lg" style={{ background: '#fee2e2' }}>
              <div className="flex-1">
                <span className="font-bold text-sm" style={{ color: '#dc2626' }}>{s.type || 'SOS'}</span>
                <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{s.created_at?.slice(0, 16)}</span>
              </div>
              <span className="text-sm" style={{ color: '#4a6357' }}>{s.description || '—'}</span>
              <StatusBadge status={s.status || 'pending'} />
            </div>
          ))}
        </div>
      )}
    </Card>
  )
}

function LoadingSpinner() {
  return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
}

function EmptyState({ text }) {
  return <p style={{ color: '#8aab99', fontSize: 13 }}>{text}</p>
}
