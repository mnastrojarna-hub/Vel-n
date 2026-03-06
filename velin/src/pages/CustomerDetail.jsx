import { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import StatusBadge from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'

import Modal from '../components/ui/Modal'

const TABS = ['Profil', 'Rezervace', 'Dokumenty', 'Hodnocení', 'SOS']

export default function CustomerDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [customer, setCustomer] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [tab, setTab] = useState('Profil')
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [showResetPw, setShowResetPw] = useState(false)
  const [resetPwMode, setResetPwMode] = useState('email')
  const [newPassword, setNewPassword] = useState('')
  const [resetPwLoading, setResetPwLoading] = useState(false)
  const [resetPwMsg, setResetPwMsg] = useState(null)

  useEffect(() => { loadCustomer() }, [id])

  async function loadCustomer() {
    setLoading(true)
    try {
      const result = await debugAction('customer.load', 'CustomerDetail', () =>
        supabase.from('profiles').select('*').eq('id', id).single()
      , { customer_id: id })
      if (result?.error) setError(result.error.message)
      else setCustomer(result?.data)
    } catch (e) {
      setError(e.message)
    }
    setLoading(false)
  }

  async function handleSave() {
    setSaving(true)
    setError(null)
    const {
      full_name, phone, street, city, zip, country,
      date_of_birth, license_group, emergency_contact,
      emergency_phone, riding_experience, marketing_consent,
      reliability_score,
    } = customer
    const updateData = { full_name, phone, street, city, zip, country,
      date_of_birth, license_group, emergency_contact,
      emergency_phone, riding_experience, marketing_consent,
      reliability_score }
    const result = await debugAction('customer.save', 'CustomerDetail', () =>
      supabase.from('profiles').update(updateData).eq('id', id)
    , updateData)
    if (result?.error) setError(result.error.message)
    else await logAudit('customer_updated', { customer_id: id })
    setSaving(false)
  }

  async function handleDelete() {
    const { data: bookings } = await debugAction('customer.checkBookings', 'CustomerDetail', () =>
      supabase.from('bookings').select('id').eq('user_id', id).in('status', ['pending', 'active', 'reserved'])
    , { customer_id: id })

    if (bookings && bookings.length > 0) {
      setError('Zákazník má aktivní rezervace. Nejdřív je stornujte.')
      setConfirmDelete(false)
      return
    }

    const result = await debugAction('customer.delete', 'CustomerDetail', () =>
      supabase.from('profiles').delete().eq('id', id)
    , { customer_id: id })
    if (result?.error) {
      setError(result.error.message)
      setConfirmDelete(false)
      return
    }

    await logAudit('customer_deleted', { customer_id: id })
    navigate('/zakaznici')
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action, details,
      })
    } catch {}
  }

  async function handleResetPassword() {
    setResetPwLoading(true)
    setResetPwMsg(null)
    try {
      const reqData = { user_id: id, mode: resetPwMode }
      const result = await debugAction('customer.resetPassword', 'CustomerDetail', async () => {
        const { data: { session } } = await supabase.auth.getSession()
        const token = session?.access_token
        const baseUrl = supabase.supabaseUrl || 'https://vnwnqteskbykeucanlhk.supabase.co'
        const resp = await fetch(`${baseUrl}/functions/v1/admin-reset-password`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}`, 'apikey': supabase.supabaseKey || '' },
          body: JSON.stringify({ user_id: id, ...(resetPwMode === 'manual' && newPassword ? { new_password: newPassword } : {}) }),
        })
        const data = await resp.json()
        return { data }
      }, reqData)
      const r = result?.data
      if (r?.success) {
        setResetPwMsg({ type: 'ok', text: r.method === 'email' ? `Reset email odeslán na ${r.email}` : 'Heslo bylo změněno' })
        setNewPassword('')
      } else {
        setResetPwMsg({ type: 'err', text: r?.error || 'Chyba' })
      }
    } catch (e) {
      setResetPwMsg({ type: 'err', text: e.message })
    }
    setResetPwLoading(false)
  }

  async function handleLoginAsCustomer() {
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const token = session?.access_token
      const baseUrl = supabase.supabaseUrl || 'https://vnwnqteskbykeucanlhk.supabase.co'
      const resp = await fetch(`${baseUrl}/functions/v1/admin-reset-password`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
          'apikey': supabase.supabaseKey || '',
        },
        body: JSON.stringify({ user_id: id }),
      })
      const result = await resp.json()
      if (result.success && result.email) {
        await logAudit('admin_login_as_customer', { customer_id: id, email: result.email })
        setError(`Recovery link odeslán na ${result.email}. Pro impersonaci použijte tento link.`)
      } else {
        setError(result.error || 'Nepodařilo se')
      }
    } catch (e) {
      setError(e.message)
    }
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

      {/* Admin akce */}
      <div className="flex gap-2 mb-4">
        <button
          onClick={() => { setShowResetPw(true); setResetPwMsg(null); setNewPassword(''); setResetPwMode('email') }}
          className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 16px', background: '#fef3c7', color: '#b45309', border: 'none' }}
        >
          Resetovat heslo
        </button>
        <button
          onClick={handleLoginAsCustomer}
          className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 16px', background: '#dbeafe', color: '#1d4ed8', border: 'none' }}
        >
          Prihlasit jako zakaznik
        </button>
      </div>

      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer" style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#4a6357', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {t}
          </button>
        ))}
      </div>

      {tab === 'Profil' && (
        <ProfileTab
          customer={customer}
          set={set}
          error={error}
          saving={saving}
          onSave={handleSave}
          onDelete={() => setConfirmDelete(true)}
        />
      )}
      {tab === 'Rezervace' && <CustomerBookings userId={id} />}
      {tab === 'Dokumenty' && <CustomerDocuments userId={id} />}
      {tab === 'Hodnocení' && <CustomerReviews userId={id} />}
      {tab === 'SOS' && <CustomerSOS userId={id} />}

      {/* Reset hesla modal */}
      {showResetPw && (
        <Modal open title="Resetovat heslo zakaznika" onClose={() => setShowResetPw(false)}>
          <div className="space-y-3">
            <div className="flex gap-2">
              <button
                onClick={() => setResetPwMode('email')}
                className="rounded-btn text-xs font-bold cursor-pointer"
                style={{ padding: '6px 14px', background: resetPwMode === 'email' ? '#74FB71' : '#f1faf7', color: resetPwMode === 'email' ? '#1a2e22' : '#4a6357', border: 'none' }}
              >
                Poslat reset email
              </button>
              <button
                onClick={() => setResetPwMode('manual')}
                className="rounded-btn text-xs font-bold cursor-pointer"
                style={{ padding: '6px 14px', background: resetPwMode === 'manual' ? '#74FB71' : '#f1faf7', color: resetPwMode === 'manual' ? '#1a2e22' : '#4a6357', border: 'none' }}
              >
                Nastavit heslo rucne
              </button>
            </div>

            {resetPwMode === 'email' && (
              <p className="text-sm" style={{ color: '#4a6357' }}>
                Zakaznikovi bude odeslan email s odkazem pro nastaveni noveho hesla.
              </p>
            )}

            {resetPwMode === 'manual' && (
              <div>
                <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Nove heslo</label>
                <input
                  type="text"
                  value={newPassword}
                  onChange={e => setNewPassword(e.target.value)}
                  placeholder="Min. 8 znaku"
                  className="w-full rounded-btn text-sm outline-none"
                  style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
                />
              </div>
            )}

            {resetPwMsg && (
              <p className="text-sm" style={{ color: resetPwMsg.type === 'ok' ? '#1a8a18' : '#dc2626' }}>
                {resetPwMsg.text}
              </p>
            )}

            <div className="flex justify-end gap-2 pt-2">
              <Button onClick={() => setShowResetPw(false)}>Zrusit</Button>
              <Button
                green
                onClick={handleResetPassword}
                disabled={resetPwLoading || (resetPwMode === 'manual' && newPassword.length < 8)}
              >
                {resetPwLoading ? 'Zpracovavam...' : resetPwMode === 'email' ? 'Odeslat email' : 'Nastavit heslo'}
              </Button>
            </div>
          </div>
        </Modal>
      )}

      <ConfirmDialog
        open={confirmDelete}
        title="Smazat zakaznika?"
        message="Tato akce je nevratna. Profil zakaznika bude trvale odstranen."
        danger
        onConfirm={handleDelete}
        onCancel={() => setConfirmDelete(false)}
      />
    </div>
  )
}

function getScoreColor(score) {
  const val = typeof score === 'object' ? score.total : Number(score)
  if (val >= 80) return { color: '#1a8a18', bg: '#dcfce7' }
  if (val >= 50) return { color: '#b45309', bg: '#fef3c7' }
  return { color: '#dc2626', bg: '#fee2e2' }
}

function ProfileTab({ customer, set, error, saving, onSave, onDelete }) {
  return (
    <div className="space-y-5">
      {/* Osobní údaje */}
      <Card>
        <SectionTitle>Osobní údaje</SectionTitle>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Jméno" value={customer.full_name} onChange={v => set('full_name', v)} />
          <Field label="Email" value={customer.email} disabled />
          <Field label="Telefon" value={customer.phone} onChange={v => set('phone', v)} />
          <Field label="Datum narození" value={customer.date_of_birth} onChange={v => set('date_of_birth', v)} type="date" />
          <Field label="Jazyk" value={customer.language} disabled />
          <Field label="Registrace" value={customer.created_at?.slice(0, 10)} disabled />
        </div>
      </Card>

      {/* Adresa */}
      <Card>
        <SectionTitle>Adresa</SectionTitle>
        <div className="grid grid-cols-2 gap-4">
          <div className="col-span-2">
            <Field label="Ulice" value={customer.street} onChange={v => set('street', v)} />
          </div>
          <Field label="Město" value={customer.city} onChange={v => set('city', v)} />
          <Field label="PSČ" value={customer.zip} onChange={v => set('zip', v)} />
          <Field label="Země" value={customer.country || 'CZ'} onChange={v => set('country', v)} />
        </div>
      </Card>

      {/* Řidičák a zkušenosti */}
      <Card>
        <SectionTitle>Řidičák a zkušenosti</SectionTitle>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Řidičské skupiny</label>
            <div className="flex flex-wrap gap-1">
              {(customer.license_group && customer.license_group.length > 0)
                ? customer.license_group.map(g => (
                  <Badge key={g} label={g} color="#1a8a18" bg="#dcfce7" />
                ))
                : <span style={{ color: '#8aab99', fontSize: 13 }}>—</span>
              }
            </div>
          </div>
          <Field label="Jezdecké zkušenosti" value={customer.riding_experience} onChange={v => set('riding_experience', v)} />
        </div>
      </Card>

      {/* Kontakt pro případ nouze */}
      <Card>
        <SectionTitle>Kontakt pro případ nouze</SectionTitle>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Jméno" value={customer.emergency_contact} onChange={v => set('emergency_contact', v)} />
          <Field label="Telefon" value={customer.emergency_phone} onChange={v => set('emergency_phone', v)} />
        </div>
      </Card>

      {/* Vybavení */}
      <Card>
        <SectionTitle>Vybavení</SectionTitle>
        <GearSizes gearSizes={customer.gear_sizes} />
      </Card>

      {/* Spolehlivost — READONLY admin info */}
      <Card>
        <SectionTitle>Spolehlivost</SectionTitle>
        <div className="grid grid-cols-3 gap-4">
          <Field label="Pozdní vrácení" value={customer.reliability_score?.late_returns} disabled />
          <Field label="Nehody" value={customer.reliability_score?.accidents} disabled />
          <div className="col-span-3">
            <Field
              label="Poznámky (admin)"
              value={customer.reliability_score?.notes}
              onChange={v => set('reliability_score', { ...customer.reliability_score, notes: v })}
            />
          </div>
        </div>
      </Card>

      {/* Marketingový souhlas */}
      <Card>
        <div className="flex items-center gap-3">
          <input
            type="checkbox"
            checked={!!customer.marketing_consent}
            onChange={e => set('marketing_consent', e.target.checked)}
            className="w-4 h-4 cursor-pointer"
          />
          <label className="text-sm font-bold" style={{ color: '#0f1a14' }}>Marketingový souhlas</label>
        </div>
      </Card>

      {error && <p className="text-sm" style={{ color: '#dc2626' }}>{error}</p>}
      <div className="flex gap-3">
        <Button green onClick={onSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
        <Button onClick={onDelete} style={{ color: '#dc2626' }}>Smazat zákazníka</Button>
      </div>
    </div>
  )
}

function SectionTitle({ children }) {
  return (
    <h3 className="text-[10px] font-extrabold uppercase tracking-widest mb-4" style={{ color: '#8aab99' }}>
      {children}
    </h3>
  )
}

function GearSizes({ gearSizes }) {
  if (!gearSizes || (typeof gearSizes === 'object' && Object.keys(gearSizes).length === 0)) {
    return <span style={{ color: '#8aab99', fontSize: 13 }}>—</span>
  }
  if (typeof gearSizes === 'object' && !Array.isArray(gearSizes)) {
    return (
      <div className="grid grid-cols-2 gap-2">
        {Object.entries(gearSizes).map(([k, v]) => (
          <div key={k} className="flex items-center gap-2 p-2 rounded-lg" style={{ background: '#f1faf7' }}>
            <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>{k}</span>
            <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{String(v)}</span>
          </div>
        ))}
      </div>
    )
  }
  return <span className="text-sm" style={{ color: '#4a6357' }}>{JSON.stringify(gearSizes)}</span>
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
  const navigate = useNavigate()
  const [bookings, setBookings] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('bookings').select('*, motorcycles(id, model, spz)').eq('user_id', userId).order('start_date', { ascending: false })
      .then(({ data }) => { setBookings(data || []); setLoading(false) })
      .catch(() => { setBookings([]); setLoading(false) })
  }, [userId])

  if (loading) return <LoadingSpinner />

  return (
    <Card>
      {bookings.length === 0 ? <EmptyState text="Žádné rezervace" /> : (
        <div className="space-y-3">
          {bookings.map(b => (
            <div key={b.id} className="flex items-center gap-4 p-3 rounded-lg cursor-pointer hover:bg-[#e8f5e9]"
              style={{ background: '#f1faf7' }} onClick={() => navigate(`/rezervace/${b.id}`)}>
              <div className="flex-1">
                <span className="font-bold text-sm">{b.motorcycles?.model || '—'}</span>
                <span className="text-xs font-mono ml-2" style={{ color: '#8aab99' }}>{b.motorcycles?.spz}</span>
                <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{b.start_date} → {b.end_date}</span>
              </div>
              <StatusBadge status={b.status} />
              <span className="text-sm font-bold">{b.total_price?.toLocaleString('cs-CZ')} Kč</span>
              {b.motorcycles?.id && (
                <button onClick={e => { e.stopPropagation(); navigate(`/flotila/${b.motorcycles.id}`) }}
                  className="text-[10px] font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>
                  → Motorka
                </button>
              )}
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
      .catch(() => { setDocs([]); setLoading(false) })
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
      .catch(() => { setReviews([]); setLoading(false) })
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
    supabase.from('sos_incidents').select('*').eq('user_id', userId).order('created_at', { ascending: false })
      .then(({ data }) => {
        if (data && data.length > 0) { setIncidents(data); setLoading(false); return }
        // Fallback: hledej přes bookings pokud user_id na sos_incidents není
        supabase.from('sos_incidents').select('*, bookings!inner(user_id)').eq('bookings.user_id', userId).order('created_at', { ascending: false })
          .then(({ data: d2 }) => { setIncidents(d2 || []); setLoading(false) })
          .catch(() => { setIncidents([]); setLoading(false) })
      })
      .catch(() => { setIncidents([]); setLoading(false) })
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
