import { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import StatusBadge, { getDisplayStatus } from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import Modal from '../components/ui/Modal'
import CustomerDocumentsTab from './customer/CustomerDocumentsTab'
import CustomerSOSTab from './customer/CustomerSOSTab'
import CustomerScoreWidget, { ScoreBadge } from './customer/CustomerScoreWidget'
import CustomerComplaintsTab from './customer/CustomerComplaintsTab'

const TABS = ['Profil', 'Skóre', 'Rezervace', 'Dokumenty', 'Hodnocení', 'SOS', 'Reklamace']

export default function CustomerDetail() {
  const debugMode = useDebugMode()
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
  const [confirmBlock, setConfirmBlock] = useState(false)
  const [blockReason, setBlockReason] = useState('')

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
      reliability_score, is_blocked, blocked_at, blocked_reason,
      consent_gdpr, consent_vop, consent_email, consent_sms,
      consent_push, consent_data_processing, consent_photo,
      consent_whatsapp, consent_contract,
    } = customer
    const updateData = { full_name, phone, street, city, zip, country,
      date_of_birth, license_group, emergency_contact,
      emergency_phone, riding_experience, marketing_consent,
      reliability_score, is_blocked, blocked_at, blocked_reason,
      consent_gdpr, consent_vop, consent_email, consent_sms,
      consent_push, consent_data_processing, consent_photo,
      consent_whatsapp, consent_contract }
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

    // Delete profile + auth.users atomically via RPC (SECURITY DEFINER)
    const result = await debugAction('customer.delete', 'CustomerDetail', () =>
      supabase.rpc('delete_customer_account', { p_user_id: id })
    , { customer_id: id })
    if (result?.error) {
      // Fallback: try profile-only delete if RPC doesn't exist yet
      if (result.error.message?.includes('does not exist') || result.error.code === '42883') {
        const fallback = await supabase.from('profiles').delete().eq('id', id)
        if (fallback?.error) {
          setError(fallback.error.message)
          setConfirmDelete(false)
          return
        }
      } else {
        setError(result.error.message)
        setConfirmDelete(false)
        return
      }
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
        const { data, error } = await supabase.functions.invoke('admin-reset-password', {
          body: { user_id: id, ...(resetPwMode === 'manual' && newPassword ? { new_password: newPassword } : {}) },
        })
        if (error) {
          // FunctionsHttpError — přečti skutečnou chybovou zprávu z response body
          if (error.context && typeof error.context.json === 'function') {
            const body = await error.context.json()
            return { data: body }
          }
          throw error
        }
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

  async function handleToggleBlock() {
    const isBlocking = !customer.is_blocked
    const updateData = {
      is_blocked: isBlocking,
      blocked_at: isBlocking ? new Date().toISOString() : null,
      blocked_reason: isBlocking ? blockReason : null,
    }
    const result = await debugAction('customer.block', 'CustomerDetail', () =>
      supabase.from('profiles').update(updateData).eq('id', id)
    , updateData)
    if (result?.error) { setError(result.error.message); setConfirmBlock(false); return }
    setCustomer(c => ({ ...c, ...updateData }))
    await logAudit(isBlocking ? 'customer_blocked' : 'customer_unblocked', { customer_id: id, reason: blockReason })
    setConfirmBlock(false)
    setBlockReason('')
  }

  const set = (k, v) => setCustomer(c => ({ ...c, [k]: v }))

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (error && !customer) return <div className="p-4 rounded-card" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>
  if (!customer) return <div className="p-4" style={{ color: '#1a2e22' }}>Zákazník nenalezen</div>

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => navigate('/zakaznici')} className="cursor-pointer" style={{ background: 'none', border: 'none', fontSize: 18, color: '#1a2e22' }}>←</button>
        <h2 className="font-extrabold text-lg" style={{ color: '#0f1a14' }}>{customer.full_name || 'Zákazník'}</h2>
        <ScoreBadge userId={id} />
      </div>

      {/* Blocked banner */}
      {customer.is_blocked && (
        <div className="p-3 rounded-card mb-4 flex items-center gap-3" style={{ background: '#fee2e2', border: '2px solid #dc2626' }}>
          <span style={{ fontSize: 20 }}>🚫</span>
          <div>
            <div className="text-sm font-bold" style={{ color: '#dc2626' }}>Zakaznik je ZABLOKOVANY</div>
            {customer.blocked_reason && <div className="text-sm" style={{ color: '#7f1d1d' }}>Duvod: {customer.blocked_reason}</div>}
            {customer.blocked_at && <div className="text-sm" style={{ color: '#7f1d1d' }}>Od: {new Date(customer.blocked_at).toLocaleString('cs-CZ')}</div>}
          </div>
          <div className="flex-1" />
          <button onClick={() => setConfirmBlock(true)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '6px 14px', background: '#dcfce7', color: '#1a8a18', border: 'none' }}>
            Odblokovat
          </button>
        </div>
      )}

      {/* Admin akce */}
      <div className="flex gap-2 mb-4">
        <button
          onClick={() => { setShowResetPw(true); setResetPwMsg(null); setNewPassword(''); setResetPwMode('email') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 16px', background: '#fef3c7', color: '#b45309', border: 'none' }}
        >
          Resetovat heslo
        </button>
      </div>

      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer" style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#1a2e22', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {t}
          </button>
        ))}
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA CustomerDetail (#{id?.slice(-8)})</strong><br/>
        <div>profile: {customer.full_name || '—'} ({customer.email || '—'})</div>
        <div>phone: {customer.phone || '—'}, city: {customer.city || '—'}, country: {customer.country || '—'}</div>
        <div>license_group: {(customer.license_group || []).join(', ') || 'žádné'}, marketing_consent: {String(!!customer.marketing_consent)}</div>
        <div>reliability_score: {typeof customer.reliability_score === 'object' ? JSON.stringify(customer.reliability_score) : customer.reliability_score || '—'}</div>
        <div>tab: {tab}</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

      {tab === 'Profil' && (
        <ProfileTab
          customer={customer}
          set={set}
          error={error}
          saving={saving}
          onSave={handleSave}
          onDelete={() => setConfirmDelete(true)}
          onBlock={() => { setConfirmBlock(true); setBlockReason('') }}
        />
      )}
      {tab === 'Skóre' && <CustomerScoreWidget userId={id} />}
      {tab === 'Rezervace' && <CustomerBookings userId={id} />}
      {tab === 'Dokumenty' && <CustomerDocumentsTab userId={id} />}
      {tab === 'Hodnocení' && <CustomerReviews userId={id} />}
      {tab === 'SOS' && <CustomerSOSTab userId={id} />}
      {tab === 'Reklamace' && <CustomerComplaintsTab userId={id} />}

      {/* Reset hesla modal */}
      {showResetPw && (
        <Modal open title="Resetovat heslo zakaznika" onClose={() => setShowResetPw(false)}>
          <div className="space-y-3">
            <div className="flex gap-2">
              <button
                onClick={() => setResetPwMode('email')}
                className="rounded-btn text-sm font-bold cursor-pointer"
                style={{ padding: '6px 14px', background: resetPwMode === 'email' ? '#74FB71' : '#f1faf7', color: resetPwMode === 'email' ? '#1a2e22' : '#1a2e22', border: 'none' }}
              >
                Poslat reset email
              </button>
              <button
                onClick={() => setResetPwMode('manual')}
                className="rounded-btn text-sm font-bold cursor-pointer"
                style={{ padding: '6px 14px', background: resetPwMode === 'manual' ? '#74FB71' : '#f1faf7', color: resetPwMode === 'manual' ? '#1a2e22' : '#1a2e22', border: 'none' }}
              >
                Nastavit heslo rucne
              </button>
            </div>

            {resetPwMode === 'email' && (
              <p className="text-sm" style={{ color: '#1a2e22' }}>
                Zakaznikovi bude odeslan email s odkazem pro nastaveni noveho hesla.
              </p>
            )}

            {resetPwMode === 'manual' && (
              <div>
                <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Nove heslo</label>
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

      {/* Block modal */}
      {confirmBlock && (
        <Modal open title={customer.is_blocked ? 'Odblokovat zakaznika' : 'Zablokovat zakaznika'} onClose={() => setConfirmBlock(false)}>
          <div className="space-y-3">
            {!customer.is_blocked ? (
              <>
                <p className="text-sm" style={{ color: '#dc2626' }}>Zablokovany zakaznik si nemuze pujcit motorku.</p>
                <div>
                  <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Duvod blokovani</label>
                  <input type="text" value={blockReason} onChange={e => setBlockReason(e.target.value)} placeholder="Duvod…" className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
                </div>
              </>
            ) : (
              <p className="text-sm" style={{ color: '#1a2e22' }}>Zakaznik bude odblokovany a bude si moci opet pujcit motorku.</p>
            )}
            <div className="flex justify-end gap-2 pt-2">
              <Button onClick={() => setConfirmBlock(false)}>Zrusit</Button>
              <Button green={customer.is_blocked} onClick={handleToggleBlock} style={!customer.is_blocked ? { background: '#dc2626', color: '#fff' } : {}}>
                {customer.is_blocked ? 'Odblokovat' : 'Zablokovat'}
              </Button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}

function ProfileTab({ customer, set, error, saving, onSave, onDelete, onBlock }) {
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
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Řidičské skupiny</label>
            <div className="flex flex-wrap gap-1">
              {(customer.license_group && customer.license_group.length > 0)
                ? customer.license_group.map(g => (
                  <Badge key={g} label={g} color="#1a8a18" bg="#dcfce7" />
                ))
                : <span style={{ color: '#1a2e22', fontSize: 13 }}>—</span>
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

      {/* Poznámky admin */}
      <Card>
        <SectionTitle>Admin poznamky</SectionTitle>
        <div>
          <Field
            label="Poznamky k zakaznikovi"
            value={customer.reliability_score?.notes}
            onChange={v => set('reliability_score', { ...customer.reliability_score, notes: v })}
          />
        </div>
      </Card>

      {/* Souhlasy */}
      <Card>
        <SectionTitle>Souhlasy</SectionTitle>
        <div className="grid grid-cols-2 gap-3">
          <ConsentRow label="Marketingovy souhlas" checked={!!customer.marketing_consent} onChange={v => set('marketing_consent', v)} />
          <ConsentRow label="GDPR — zpracovani osobnich udaju" checked={!!customer.consent_gdpr} onChange={v => set('consent_gdpr', v)} />
          <ConsentRow label="VOP — vseobecne obchodni podminky" checked={!!customer.consent_vop} onChange={v => set('consent_vop', v)} />
          <ConsentRow label="Zpracovani dat pro provoz sluzby" checked={!!customer.consent_data_processing} onChange={v => set('consent_data_processing', v)} />
          <ConsentRow label="Navrh smlouvy na motogo24.cz" checked={!!customer.consent_contract} onChange={v => set('consent_contract', v)} />
          <ConsentRow label="Email komunikace" checked={!!customer.consent_email} onChange={v => set('consent_email', v)} />
          <ConsentRow label="SMS komunikace" checked={!!customer.consent_sms} onChange={v => set('consent_sms', v)} />
          <ConsentRow label="WhatsApp komunikace" checked={!!customer.consent_whatsapp} onChange={v => set('consent_whatsapp', v)} />
          <ConsentRow label="Push notifikace" checked={!!customer.consent_push} onChange={v => set('consent_push', v)} />
          <ConsentRow label="Fotografovani dokladu a motorky" checked={!!customer.consent_photo} onChange={v => set('consent_photo', v)} />
        </div>
      </Card>

      {error && <p className="text-sm" style={{ color: '#dc2626' }}>{error}</p>}
      <div className="flex gap-3">
        <Button green onClick={onSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
        <Button onClick={onDelete} style={{ color: '#dc2626' }}>Smazat zákazníka</Button>
        <button onClick={onBlock}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 16px', background: customer.is_blocked ? '#dcfce7' : '#7f1d1d', color: customer.is_blocked ? '#1a8a18' : '#fff', border: 'none' }}>
          {customer.is_blocked ? 'Odblokovat zákazníka' : 'Zablokovat zákazníka'}
        </button>
      </div>
    </div>
  )
}

function SectionTitle({ children }) {
  return (
    <h3 className="text-sm font-extrabold uppercase tracking-widest mb-4" style={{ color: '#1a2e22' }}>
      {children}
    </h3>
  )
}

function GearSizes({ gearSizes }) {
  if (!gearSizes || (typeof gearSizes === 'object' && Object.keys(gearSizes).length === 0)) {
    return <span style={{ color: '#1a2e22', fontSize: 13 }}>—</span>
  }
  if (typeof gearSizes === 'object' && !Array.isArray(gearSizes)) {
    return (
      <div className="grid grid-cols-2 gap-2">
        {Object.entries(gearSizes).map(([k, v]) => (
          <div key={k} className="flex items-center gap-2 p-2 rounded-lg" style={{ background: '#f1faf7' }}>
            <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{k}</span>
            <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{String(v)}</span>
          </div>
        ))}
      </div>
    )
  }
  return <span className="text-sm" style={{ color: '#1a2e22' }}>{JSON.stringify(gearSizes)}</span>
}

function Field({ label, value, onChange, type = 'text', disabled = false }) {
  return (
    <div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
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
                <span className="text-sm font-mono ml-2" style={{ color: '#1a2e22' }}>{b.motorcycles?.spz}</span>
                <span className="text-sm ml-3" style={{ color: '#1a2e22' }}>{b.start_date} → {b.end_date}</span>
              </div>
              <StatusBadge status={getDisplayStatus(b)} />
              <span className="text-sm font-bold">{b.total_price?.toLocaleString('cs-CZ')} Kč</span>
              {b.motorcycles?.id && (
                <button onClick={e => { e.stopPropagation(); navigate(`/flotila/${b.motorcycles.id}`) }}
                  className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>
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
                <span className="text-sm" style={{ color: '#1a2e22' }}>{r.created_at?.slice(0, 10)}</span>
              </div>
              <p className="text-sm" style={{ color: '#1a2e22' }}>{r.comment || '—'}</p>
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
  return <p style={{ color: '#1a2e22', fontSize: 13 }}>{text}</p>
}

function ConsentRow({ label, checked, onChange }) {
  return (
    <div className="flex items-center gap-3 p-2 rounded-lg" style={{ background: '#f1faf7' }}>
      <input type="checkbox" checked={checked} onChange={e => onChange(e.target.checked)} className="w-4 h-4 cursor-pointer" />
      <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{label}</span>
      <span className="text-xs ml-auto" style={{ color: checked ? '#1a8a18' : '#dc2626' }}>{checked ? 'Ano' : 'Ne'}</span>
    </div>
  )
}
