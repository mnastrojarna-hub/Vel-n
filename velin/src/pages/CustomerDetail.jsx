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
import ProfileTab from './CustomerProfileTab'
import { CustomerBookings, CustomerReviews } from './CustomerSubTabs'

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

