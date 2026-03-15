import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { generateAdvanceInvoice, generatePaymentReceipt, generateFinalInvoice } from '../lib/invoiceUtils'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import StatusBadge, { getDisplayStatus } from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import Modal from '../components/ui/Modal'
import BookingDocumentsTab from './booking/BookingDocumentsTab'
import BookingPaymentsTab from './booking/BookingPaymentsTab'
import BookingsCalendar from '../components/fleet/BookingsCalendar'

const TABS = ['Detail', 'Kalendář motorky', 'Dokumenty', 'Platby', 'Reklamace']

// Helper: describe a single date modification step
function describeModification(fromStart, fromEnd, toStart, toEnd) {
  // Normalize to local midnight to avoid timezone-caused fractional days
  const fs = new Date(fromStart); fs.setHours(0,0,0,0)
  const fe = new Date(fromEnd); fe.setHours(0,0,0,0)
  const ts = new Date(toStart); ts.setHours(0,0,0,0)
  const te = new Date(toEnd); te.setHours(0,0,0,0)
  const startDelta = Math.round((ts - fs) / 86400000)
  const endDelta = Math.round((te - fe) / 86400000)
  const origDays = Math.max(1, Math.round((fe - fs) / 86400000) + 1)
  const newDays = Math.max(1, Math.round((te - ts) / 86400000) + 1)
  const durationDelta = newDays - origDays

  const parts = []
  if (startDelta < 0) parts.push(`začátek dříve o ${Math.abs(startDelta)} d`)
  else if (startDelta > 0) parts.push(`začátek později o ${startDelta} d`)
  if (endDelta > 0) parts.push(`konec později o ${endDelta} d`)
  else if (endDelta < 0) parts.push(`konec dříve o ${Math.abs(endDelta)} d`)

  let type, color, bg
  if (durationDelta > 0) { type = `prodlouženo o ${durationDelta} d`; color = '#2563eb'; bg = '#dbeafe' }
  else if (durationDelta < 0) { type = `zkráceno o ${Math.abs(durationDelta)} d`; color = '#dc2626'; bg = '#fee2e2' }
  else if (startDelta !== 0 || endDelta !== 0) { type = 'přesunuto'; color = '#92400e'; bg = '#fef3c7' }
  else { type = 'beze změny'; color = '#1a2e22'; bg = '#f1faf7' }

  const detail = parts.length > 0 ? parts.join(', ') : type
  return { type, detail, parts, durationDelta, startDelta, endDelta, origDays, newDays, color, bg }
}

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
  { value: 'unpaid_auto', label: 'Automaticky zrušeno pro nezaplacení' },
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

  const [promoUsage, setPromoUsage] = useState([])
  const [voucherUsed, setVoucherUsed] = useState(null)

  async function loadBooking() {
    setLoading(true)
    const result = await debugAction('booking.load', 'BookingDetail', () =>
      supabase.from('bookings')
        .select('*, motorcycles(id, model, spz, status, branch_id, branches(name)), profiles(id, full_name, email, phone, city)')
        .eq('id', id).single()
    , { booking_id: id })
    if (result?.error) setError(result.error.message)
    else {
      const d = result?.data
      if (d) {
        // Normalize TIMESTAMPTZ dates to YYYY-MM-DD local for correct date input display
        const normDate = v => v && v.length > 10 ? new Date(v).toLocaleDateString('sv-SE') : v
        if (d.start_date) d.start_date = normDate(d.start_date)
        if (d.end_date) d.end_date = normDate(d.end_date)
        if (d.original_start_date) d.original_start_date = normDate(d.original_start_date)
        if (d.original_end_date) d.original_end_date = normDate(d.original_end_date)
      }
      // Auto-fix: pending + paid → reserved/active
      if (d && d.status === 'pending' && d.payment_status === 'paid') {
        const today = new Date().toISOString().slice(0, 10)
        const startLocal = d.start_date ? d.start_date.slice(0, 10) : ''
        const newStatus = startLocal <= today ? 'active' : 'reserved'
        const update = { status: newStatus }
        if (newStatus === 'active') update.picked_up_at = new Date().toISOString()
        else update.confirmed_at = new Date().toISOString()
        const { error: fixErr } = await supabase.from('bookings').update(update).eq('id', d.id)
        if (!fixErr) {
          d.status = newStatus
          if (newStatus === 'active') d.picked_up_at = update.picked_up_at
          else d.confirmed_at = update.confirmed_at
          console.log(`[AutoFix] Booking ${d.id} pending+paid → ${newStatus}`)
        }
      }
      setBooking(d)
    }
    setLoading(false)

    // Load promo code usage for this booking
    supabase.from('promo_code_usage')
      .select('*, promo_codes(code, type, value)')
      .eq('booking_id', id)
      .then(({ data }) => { if (data) setPromoUsage(data) })
      .catch(() => {})

    // Load voucher applied to this booking
    supabase.from('vouchers')
      .select('code, amount, currency, status')
      .eq('booking_id', id)
      .limit(1)
      .then(({ data }) => { if (data && data.length) setVoucherUsed(data[0]) })
      .catch(() => {})
  }

  async function changeStatus(newStatus) {
    setSaving(true)
    const now = new Date().toISOString()
    const update = { status: newStatus }
    if (newStatus === 'reserved') update.confirmed_at = now
    if (newStatus === 'active') update.picked_up_at = now
    if (newStatus === 'completed') update.returned_at = now

    const result = await debugAction(`booking.status.${newStatus}`, 'BookingDetail', () =>
      supabase.from('bookings').update(update).eq('id', id)
    , { booking_id: id, newStatus })
    if (result?.error) { setError(result.error.message); setSaving(false); return }
    await logAudit(`booking_${newStatus}`, { booking_id: id })

    // Auto-triggers per status
    const emailBody = {
      booking_id: id,
      customer_email: booking.profiles?.email,
      customer_name: booking.profiles?.full_name,
      motorcycle: booking.motorcycles?.model,
      start_date: booking.start_date,
      end_date: booking.end_date,
      total_price: booking.total_price,
    }
    // Generate invoices directly in DB (primary) + edge functions for docs/emails (secondary)
    const invoiceErrors = []
    try {
      if (newStatus === 'reserved') {
        // Generate advance invoice (ZF) directly in DB
        try {
          await generateAdvanceInvoice(id, 'booking')
        } catch (e) {
          console.error('[Invoice] ZF error:', e.message)
          invoiceErrors.push(`ZF: ${e.message}`)
        }
        // Generate payment receipt (DP) directly in DB
        try {
          await generatePaymentReceipt(id, 'booking')
        } catch (e) {
          console.error('[Invoice] DP error:', e.message)
          invoiceErrors.push(`DP: ${e.message}`)
        }
        // Edge functions for rental contract + VOP + confirmation email (non-blocking)
        Promise.allSettled([
          supabase.functions.invoke('generate-document', { body: { template_slug: 'rental_contract', booking_id: id } }),
          supabase.functions.invoke('generate-document', { body: { template_slug: 'vop', booking_id: id } }),
          supabase.functions.invoke('send-booking-email', { body: { ...emailBody, type: 'booking_reserved' } }),
        ]).catch(() => {})
      } else if (newStatus === 'active') {
        // Check if ZF/DP already exist — generate if missing (covers pending→active skip)
        try {
          const { data: existingInv } = await supabase.from('invoices').select('type').eq('booking_id', id)
            .in('type', ['advance', 'proforma', 'payment_receipt']).neq('status', 'cancelled')
          const hasZF = (existingInv || []).some(i => i.type === 'advance' || i.type === 'proforma')
          const hasDP = (existingInv || []).some(i => i.type === 'payment_receipt')
          if (!hasZF) {
            try { await generateAdvanceInvoice(id, 'booking') } catch (e) {
              console.error('[Invoice] ZF (active) error:', e.message)
              invoiceErrors.push(`ZF: ${e.message}`)
            }
          }
          if (!hasDP) {
            try { await generatePaymentReceipt(id, 'booking') } catch (e) {
              console.error('[Invoice] DP (active) error:', e.message)
              invoiceErrors.push(`DP: ${e.message}`)
            }
          }
        } catch (e) { console.error('[Invoice] check existing:', e.message) }
        // Generate rental contract + VOP + handover protocol if not already generated (non-blocking)
        Promise.allSettled([
          supabase.functions.invoke('generate-document', { body: { template_slug: 'rental_contract', booking_id: id } }),
          supabase.functions.invoke('generate-document', { body: { template_slug: 'vop', booking_id: id } }),
          supabase.functions.invoke('generate-document', { body: { template_slug: 'handover_protocol', booking_id: id } }),
        ]).catch(() => {})
      } else if (newStatus === 'completed') {
        // Ensure ZF/DP exist before generating KF (covers edge cases where earlier steps were skipped)
        try {
          const { data: existingInv } = await supabase.from('invoices').select('type').eq('booking_id', id)
            .in('type', ['advance', 'proforma', 'payment_receipt']).neq('status', 'cancelled')
          const hasZF = (existingInv || []).some(i => i.type === 'advance' || i.type === 'proforma')
          const hasDP = (existingInv || []).some(i => i.type === 'payment_receipt')
          if (!hasZF) {
            try { await generateAdvanceInvoice(id, 'booking') } catch (e) {
              console.error('[Invoice] ZF (completed) error:', e.message)
              invoiceErrors.push(`ZF: ${e.message}`)
            }
          }
          if (!hasDP) {
            try { await generatePaymentReceipt(id, 'booking') } catch (e) {
              console.error('[Invoice] DP (completed) error:', e.message)
              invoiceErrors.push(`DP: ${e.message}`)
            }
          }
        } catch (e) { console.error('[Invoice] check existing (completed):', e.message) }
        // Generate final invoice (KF) directly in DB
        try {
          await generateFinalInvoice(id)
        } catch (e) {
          console.error('[Invoice] KF error:', e.message)
          invoiceErrors.push(`KF: ${e.message}`)
        }
        // Send completion email (edge function, non-blocking)
        supabase.functions.invoke('send-booking-email', { body: { ...emailBody, type: 'booking_completed' } }).catch(() => {})
      }
    } catch (e) { console.error('[Auto-triggers]', e.message) }

    // Show invoice errors to admin so they know what went wrong
    if (invoiceErrors.length > 0) {
      setError(`Stav změněn, ale generování faktur selhalo: ${invoiceErrors.join('; ')}`)
    }

    // Auto in-app message to customer
    await sendBookingMessage(newStatus, booking)

    setBooking(b => ({ ...b, ...update }))
    setConfirm(null); setSaving(false)
  }

  const MSG_TEMPLATES = {
    reserved: (b) => `Vaše rezervace motorky ${b.motorcycles?.model || ''} (${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}) byla potvrzena. Smlouvu a fakturu najdete v sekci Dokumenty.`,
    active: (b) => `Motorka ${b.motorcycles?.model || ''} byla vydána. Přejeme příjemnou jízdu! V případě problému nás kontaktujte nebo použijte SOS tlačítko.`,
    completed: (b) => `Vaše jízda na ${b.motorcycles?.model || ''} byla dokončena. Děkujeme a těšíme se na příště! Konečnou fakturu najdete v sekci Dokumenty.`,
  }

  async function sendBookingMessage(status, bk) {
    const template = MSG_TEMPLATES[status]
    if (!template || !bk.user_id) return
    try {
      // Find or create thread
      let { data: thread } = await supabase.from('message_threads')
        .select('id').eq('customer_id', bk.user_id).limit(1).single()
      if (!thread) {
        const { data: newThread } = await supabase.from('message_threads')
          .insert({ customer_id: bk.user_id, subject: 'Rezervace', channel: 'app' })
          .select('id').single()
        thread = newThread
      }
      if (!thread) return
      await supabase.from('messages').insert({
        thread_id: thread.id, direction: 'admin', sender_name: 'MotoGo',
        content: template(bk),
      })
      await supabase.from('message_threads').update({ last_message_at: new Date().toISOString() }).eq('id', thread.id)
    } catch {}
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

    const cancelResult = await debugAction('booking.cancel', 'BookingDetail', () =>
      supabase.from('bookings').update(updatePayload).eq('id', id)
    , { booking_id: id, reason, source: cancelReason })
    if (cancelResult?.error) { setError(cancelResult.error.message); setSaving(false); return }
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

    // Build save data — record date changes in modification_history
    const saveData = { start_date, end_date, total_price, extras, notes, moto_id, user_id }

    // Fetch current DB state to detect date changes
    const { data: dbBooking } = await supabase.from('bookings')
      .select('start_date, end_date, original_start_date, original_end_date, modification_history')
      .eq('id', id).single()

    if (dbBooking) {
      const toLD = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
      const dateChanged = toLD(dbBooking.start_date) !== toLD(start_date) || toLD(dbBooking.end_date) !== toLD(end_date)

      if (dateChanged) {
        // Set original dates on first-ever modification (YYYY-MM-DD to avoid UTC truncation on DATE column)
        if (!dbBooking.original_start_date) {
          saveData.original_start_date = toLD(dbBooking.start_date)
          saveData.original_end_date = toLD(dbBooking.end_date)
        }
        // Append to modification_history
        const history = Array.isArray(dbBooking.modification_history) ? [...dbBooking.modification_history] : []
        history.push({
          at: new Date().toISOString(),
          from_start: toLD(dbBooking.start_date),
          from_end: toLD(dbBooking.end_date),
          to_start: toLD(start_date),
          to_end: toLD(end_date),
          source: 'admin'
        })
        saveData.modification_history = history
      }
    }

    const saveResult = await debugAction('booking.save', 'BookingDetail', () =>
      supabase.from('bookings').update(saveData).eq('id', id)
    , saveData)
    if (saveResult?.error) { setError(saveResult.error.message); setSaving(false); return }
    await logAudit('booking_updated', { booking_id: id })

    // Send modification email if booking is reserved or active
    if (['reserved', 'active'].includes(booking.status) && booking.profiles?.email) {
      try {
        await supabase.functions.invoke('send-booking-email', {
          body: {
            type: 'booking_modified', booking_id: id,
            customer_email: booking.profiles.email,
            customer_name: booking.profiles.full_name,
            motorcycle: booking.motorcycles?.model,
            start_date, end_date, total_price,
          },
        })
      } catch {}
    }
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
  if (!booking) return <div className="p-4" style={{ color: '#1a2e22' }}>{error || 'Rezervace nenalezena'}</div>

  const actions = ACTIONS[booking.status] || []

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => navigate('/rezervace')} className="cursor-pointer" style={{ background: 'none', border: 'none', fontSize: 18, color: '#1a2e22' }}>←</button>
        <h2 className="font-extrabold text-lg" style={{ color: '#0f1a14' }}>Rezervace</h2>
        <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>#{id?.slice(-8).toUpperCase()}</span>
        <StatusBadge status={getDisplayStatus(booking)} />
        {booking.payment_status && (
          <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
            style={{ padding: '3px 8px', background: booking.payment_status === 'paid' ? '#dcfce7' : '#fee2e2', color: booking.payment_status === 'paid' ? '#1a8a18' : '#dc2626' }}>
            {booking.payment_status === 'paid' ? 'Zaplaceno' : 'Nezaplaceno'}
          </span>
        )}
        <span className="text-sm" style={{ color: '#1a2e22' }}>
          Vytvořena: {booking.created_at ? new Date(booking.created_at).toLocaleString('cs-CZ') : '—'}
        </span>
      </div>
      <div className="flex gap-2 mb-5 flex-wrap">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#1a2e22', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>{t}</button>
        ))}
      </div>
      {/* DIAGNOSTIKA */}
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA BookingDetail (#{id?.slice(-8)})</strong><br/>
        <div>booking: status={booking.status}, payment={booking.payment_status}, price={booking.total_price} Kč</div>
        <div>customer: {booking.profiles?.full_name || '—'} ({booking.profiles?.email || '—'})</div>
        <div>moto: {booking.motorcycles?.model || '—'} ({booking.motorcycles?.spz || '—'})</div>
        <div>dates: {booking.start_date} → {booking.end_date}</div>
        <div>promo_usage: {promoUsage.length}, voucher: {voucherUsed ? voucherUsed.code : 'žádný'}</div>
        <div>flags: sos_replacement={String(!!booking.sos_replacement)}, ended_by_sos={String(!!booking.ended_by_sos)}</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      {tab === 'Detail' && <DetailTab booking={booking} set={set} error={error} saving={saving} onSave={handleSave} actions={actions} onAction={handleAction} navigate={navigate} promoUsage={promoUsage} voucherUsed={voucherUsed} />}
      {tab === 'Kalendář motorky' && booking.motorcycles?.id && <BookingsCalendar motoId={booking.motorcycles.id} />}
      {tab === 'Dokumenty' && <BookingDocumentsTab bookingId={id} />}
      {tab === 'Platby' && <BookingPaymentsTab bookingId={id} />}
      {tab === 'Reklamace' && <ComplaintsTab bookingId={id} booking={booking} setBooking={setBooking} />}

      {confirm && (
        <ConfirmDialog open title={`${confirm.label}?`} message={`Změnit stav na "${confirm.label}"?`}
          danger={confirm.danger} onConfirm={() => changeStatus(confirm.status)} onCancel={() => setConfirm(null)} />
      )}

      {showCancelModal && (
        <Modal open title="Zrušit rezervaci" onClose={() => setShowCancelModal(false)}>
          <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
            Zákazník bude informován emailem. Vyberte důvod zrušení:
          </p>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Důvod zrušení</label>
          <select value={cancelReason} onChange={e => setCancelReason(e.target.value)}
            className="w-full rounded-btn text-sm outline-none mb-3"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">— Vyberte důvod —</option>
            {CANCEL_REASONS.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
          </select>
          {cancelReason === 'admin' && (
            <>
              <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Vlastní důvod</label>
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

function calcPriceFromDayPrices(dayPrices, startDate, endDate) {
  if (!dayPrices || !startDate || !endDate) return null
  const start = new Date(startDate)
  const end = new Date(endDate)
  if (isNaN(start) || isNaN(end) || end < start) return null
  const dayKeys = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']
  let total = 0
  const cur = new Date(start)
  while (cur <= end) {
    const key = `price_${dayKeys[cur.getDay()]}`
    total += Number(dayPrices[key]) || 0
    cur.setDate(cur.getDate() + 1)
  }
  return total
}

function DetailTab({ booking, set, error, saving, onSave, actions, onAction, navigate, promoUsage, voucherUsed }) {
  const [priceBreakdown, setPriceBreakdown] = useState(null)
  const [recalculating, setRecalculating] = useState(false)
  const [sosIncidents, setSosIncidents] = useState([])
  const [bookingExtras, setBookingExtras] = useState([])
  const [cancellation, setCancellation] = useState(null)

  useEffect(() => {
    if (!booking?.id) return
    supabase.from('sos_incidents').select('id,type,title,status,severity,created_at,resolved_at,description,damage_severity,customer_fault,replacement_booking_id,original_booking_id,replacement_status,replacement_data')
      .eq('booking_id', booking.id).order('created_at', { ascending: false })
      .then(({ data }) => { if (data) setSosIncidents(data) }).catch(() => {})
    supabase.from('booking_extras').select('*, extras_catalog(name, price)')
      .eq('booking_id', booking.id)
      .then(({ data }) => { if (data) setBookingExtras(data) }).catch(() => {})
    if (booking.status === 'cancelled') {
      supabase.from('booking_cancellations').select('*')
        .eq('booking_id', booking.id).limit(1).single()
        .then(({ data }) => { if (data) setCancellation(data) }).catch(() => {})
    }
  }, [booking?.id])

  function handleRecalcPrice() {
    if (!booking.moto_id || !booking.start_date || !booking.end_date) return
    setRecalculating(true)
    supabase.from('moto_day_prices').select('*').eq('moto_id', booking.moto_id).single()
      .then(({ data }) => {
        if (data) {
          const total = calcPriceFromDayPrices(data, booking.start_date, booking.end_date)
          if (total !== null && total > 0) {
            set('total_price', total)
            const days = Math.max(1, Math.round((new Date(booking.end_date) - new Date(booking.start_date)) / 86400000) + 1)
            setPriceBreakdown(`${days} dní × denní sazba = ${total.toLocaleString('cs-CZ')} Kč`)
          }
        } else {
          setPriceBreakdown('Ceník není nastaven')
        }
        setRecalculating(false)
      }).catch(() => setRecalculating(false))
  }

  return (
    <div className="grid grid-cols-2 gap-5">
      <Card>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Zákazník</h3>
          {booking.profiles?.id && (
            <button onClick={() => navigate(`/zakaznici/${booking.profiles.id}`)}
              className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>
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
          <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Motorka</h3>
          {booking.motorcycles?.id && (
            <button onClick={() => navigate(`/flotila/${booking.motorcycles.id}`)}
              className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>
              → Detail motorky
            </button>
          )}
        </div>
        <InfoRow label="Model" value={booking.motorcycles?.model} />
        <InfoRow label="SPZ" value={booking.motorcycles?.spz} />
        <InfoRow label="Stav" value={booking.motorcycles?.status} />
        <InfoRow label="Pobočka" value={booking.motorcycles?.branches?.name} />
      </Card>

      {/* SOS Replacement info */}
      {(booking.sos_replacement || booking.ended_by_sos) && (
        <Card className="col-span-2">
          <div className="p-4 rounded-lg" style={{
            background: booking.sos_replacement ? '#dcfce7' : '#fee2e2',
            border: `2px solid ${booking.sos_replacement ? '#86efac' : '#fca5a5'}`,
          }}>
            <h3 className="text-sm font-extrabold mb-2" style={{ color: booking.sos_replacement ? '#1a8a18' : '#b91c1c' }}>
              {booking.sos_replacement ? '🏍️ Náhradní motorka (SOS)' : '🆘 Ukončeno kvůli SOS incidentu'}
            </h3>
            <div className="grid grid-cols-2 gap-2 text-sm">
              {booking.replacement_for_booking_id && (
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 65 }}>Nahrazuje rezervaci</span>
                  <button onClick={() => navigate(`/rezervace/${booking.replacement_for_booking_id}`)}
                    className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none', fontFamily: 'monospace' }}>
                    #{booking.replacement_for_booking_id.slice(-8).toUpperCase()}
                  </button>
                </div>
              )}
              {booking.sos_incident_id && (
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 65 }}>SOS incident</span>
                  <button onClick={() => navigate('/sos', { state: { openIncidentId: booking.sos_incident_id } })}
                    className="text-sm font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none', fontFamily: 'monospace' }}>
                    #{booking.sos_incident_id.slice(-8).toUpperCase()}
                  </button>
                </div>
              )}
              {booking.ended_by_sos && sosIncidents.length > 0 && sosIncidents[0].replacement_booking_id && (
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 65 }}>Náhradní rezervace</span>
                  <button onClick={() => navigate(`/rezervace/${sosIncidents[0].replacement_booking_id}`)}
                    className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none', fontFamily: 'monospace' }}>
                    #{sosIncidents[0].replacement_booking_id.slice(-8).toUpperCase()}
                  </button>
                </div>
              )}
              {booking.ended_by_sos && sosIncidents.length > 0 && !sosIncidents[0].replacement_booking_id && (
                <div className="flex items-center gap-2 mb-1 p-2 rounded" style={{ background: '#fef3c7', border: '1px solid #fbbf24' }}>
                  <span className="text-sm font-extrabold" style={{ color: '#92400e' }}>⚠️ Zákazník dosud nevybral náhradní motorku</span>
                  <span className="text-xs px-2 py-0.5 rounded-full font-bold" style={{ background: '#f59e0b', color: '#fff' }}>
                    {sosIncidents[0].replacement_status || 'selecting'}
                  </span>
                </div>
              )}
              <InfoRow label="Stav" value={booking.sos_replacement ? 'Náhradní motorka aktivní' : 'Původní rezervace ukončena'} />
            </div>
          </div>
        </Card>
      )}

      {(booking.discount_amount > 0 || booking.discount_code || (promoUsage && promoUsage.length > 0) || voucherUsed) && (
        <Card className="col-span-2">
          <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#b45309' }}>Uplatněné slevy a kódy</h3>
          <div className="p-4 rounded-lg" style={{ background: '#fffbeb', border: '1px solid #fde68a' }}>
            <div className="grid grid-cols-3 gap-3">
              {booking.discount_code && (
                <InfoRow label="Slevový kód" value={booking.discount_code} />
              )}
              {booking.discount_amount > 0 && (
                <InfoRow label="Sleva" value={`-${Number(booking.discount_amount).toLocaleString('cs-CZ')} Kč`} />
              )}
              {promoUsage && promoUsage.map((pu, i) => (
                <div key={pu.id || i}>
                  <InfoRow
                    label={`Promo kód ${i + 1}`}
                    value={`${pu.promo_codes?.code || '—'} (${pu.promo_codes?.type === 'percent' ? pu.promo_codes.value + '%' : pu.promo_codes?.value + ' Kč'}) → sleva ${Number(pu.discount_applied || 0).toLocaleString('cs-CZ')} Kč`}
                  />
                </div>
              ))}
              {voucherUsed && (
                <InfoRow
                  label="Dárkový poukaz"
                  value={`${voucherUsed.code} — ${Number(voucherUsed.amount).toLocaleString('cs-CZ')} ${voucherUsed.currency}`}
                />
              )}
            </div>
          </div>
        </Card>
      )}

      <Card className="col-span-2">
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#1a2e22' }}>Termín a platba</h3>
        {booking.original_start_date && booking.original_end_date && (() => {
          const _ld = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
          return _ld(booking.start_date) !== _ld(booking.original_start_date) || _ld(booking.end_date) !== _ld(booking.original_end_date)
        })() && (() => {
          const mod = describeModification(booking.original_start_date, booking.original_end_date, booking.start_date, booking.end_date)
          const history = Array.isArray(booking.modification_history) ? booking.modification_history : []
          return (
            <div className="mb-3 space-y-1">
              <div className="p-2 rounded-lg flex items-center gap-3" style={{ background: mod.bg, fontSize: 13 }}>
                <span className="font-extrabold" style={{ color: mod.color }}>
                  {mod.type}
                </span>
                <span style={{ color: '#1a2e22' }}>
                  {mod.detail} · Původní: {new Date(booking.original_start_date).toLocaleDateString('cs-CZ')} – {new Date(booking.original_end_date).toLocaleDateString('cs-CZ')} ({mod.origDays}d)
                </span>
              </div>
              {history.length > 0 && (
                <div className="text-sm px-2 py-1 rounded" style={{ background: '#f1faf7', color: '#1a2e22' }}>
                  <span className="font-extrabold">Historie úprav ({history.length}×):</span>
                  {history.map((h, i) => {
                    const m = describeModification(h.from_start, h.from_end, h.to_start, h.to_end)
                    return (
                      <div key={i} className="ml-2">
                        {i + 1}. {new Date(h.at).toLocaleString('cs-CZ')} — <span className="font-bold" style={{ color: m.color }}>{m.type}</span> ({m.detail}) · {h.from_start} → {h.to_end} · {h.source === 'admin' ? 'admin' : 'zákazník'}
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          )
        })()}
        <div className="grid grid-cols-4 gap-4">
          <FieldInput label="Od" type="date" value={booking.start_date} onChange={v => set('start_date', v)} />
          <FieldInput label="Do" type="date" value={booking.end_date} onChange={v => set('end_date', v)} />
          <div>
            <FieldInput label="Celkem (Kč)" type="number" value={booking.total_price} onChange={v => set('total_price', Number(v))} />
            <button onClick={handleRecalcPrice} disabled={recalculating}
              className="text-sm font-bold mt-1 cursor-pointer"
              style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}>
              {recalculating ? 'Počítám...' : 'Přepočítat dle ceníku'}
            </button>
            {priceBreakdown && <p className="text-sm font-bold" style={{ color: '#1a8a18' }}>{priceBreakdown}</p>}
          </div>
          <FieldInput label="Poznámky" value={booking.notes} onChange={v => set('notes', v)} />
        </div>

        {/* Pickup / Return / Insurance / Extras */}
        <div className="grid grid-cols-3 gap-4 mt-4 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Přistavení</div>
            <div className="text-sm">{booking.pickup_method === 'delivery' ? 'Přistavení na adresu' : 'Na pobočce'} — {booking.pickup_address || booking.motorcycles?.branches?.name || '—'}</div>
          </div>
          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Vrácení</div>
            <div className="text-sm">{booking.return_method === 'delivery' ? 'Svoz z adresy' : 'Na pobočce'} — {booking.return_address || booking.motorcycles?.branches?.name || '—'}</div>
          </div>
          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Pojištění</div>
            <div className="text-sm">{booking.insurance_type || '—'}</div>
          </div>
        </div>

        {/* Price breakdown */}
        <div className="grid grid-cols-4 gap-4 mt-3 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Příslušenství</div>
            <div className="text-sm font-bold">{booking.extras_price > 0 ? `${Number(booking.extras_price).toLocaleString('cs-CZ')} Kč` : '—'}</div>
            {bookingExtras.length > 0 && bookingExtras.map((ex, i) => (
              <div key={i} className="text-sm" style={{ color: '#1a2e22' }}>{ex.extras_catalog?.name || `Extra ${i + 1}`}: {Number(ex.extras_catalog?.price || 0).toLocaleString('cs-CZ')} Kč</div>
            ))}
          </div>
          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Doručení</div>
            <div className="text-sm font-bold">{booking.delivery_fee > 0 ? `${Number(booking.delivery_fee).toLocaleString('cs-CZ')} Kč` : '—'}</div>
          </div>
          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Sleva</div>
            <div className="text-sm font-bold" style={{ color: booking.discount_amount > 0 ? '#1a8a18' : undefined }}>{booking.discount_amount > 0 ? `-${Number(booking.discount_amount).toLocaleString('cs-CZ')} Kč` : '—'}{booking.discount_code ? ` (${booking.discount_code})` : ''}</div>
          </div>
          <div>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Kauce</div>
            <div className="text-sm font-bold">{booking.deposit > 0 ? `${Number(booking.deposit).toLocaleString('cs-CZ')} Kč` : '—'}</div>
          </div>
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
          <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#dc2626' }}>Informace o zrušení</h3>
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
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#1a2e22' }}>Kompletní přehled rezervace</h3>
        <BookingSummary booking={booking} sosIncidents={sosIncidents} bookingExtras={bookingExtras} cancellation={cancellation} promoUsage={promoUsage} voucherUsed={voucherUsed} />
      </Card>

      <Card className="col-span-2">
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-4" style={{ color: '#1a2e22' }}>Timeline</h3>
        <Timeline booking={booking} />
      </Card>
    </div>
  )
}

const CANCEL_SOURCE_LABELS = Object.fromEntries(CANCEL_REASONS.map(r => [r.value, r.label]))

const STATUS_LABELS = { pending: 'Čeká na platbu', reserved: 'Nadcházející', active: 'Aktivní', completed: 'Dokončená', cancelled: 'Zrušená' }

function fmtDT(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('cs-CZ')
}

function SumRow({ label, value, color }) {
  if (!value) return null
  return (
    <div className="flex gap-2 py-[3px]" style={{ borderBottom: '1px solid #f1faf7', fontSize: 12 }}>
      <span className="font-bold" style={{ color: '#1a2e22', minWidth: 160, flexShrink: 0 }}>{label}</span>
      <span className="font-medium" style={{ color: color || '#0f1a14' }}>{value}</span>
    </div>
  )
}

function BookingSummary({ booking, sosIncidents, bookingExtras, cancellation, promoUsage, voucherUsed }) {
  const b = booking
  // Normalize to local midnight to avoid timezone-caused fractional days
  const _sd = new Date(b.start_date); _sd.setHours(0,0,0,0)
  const _ed = new Date(b.end_date); _ed.setHours(0,0,0,0)
  const days = Math.max(1, Math.round((_ed - _sd) / 86400000) + 1)
  const branchName = b.motorcycles?.branches?.name || '—'

  const toLD = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
  const hasModification = b.original_start_date && b.original_end_date &&
    (toLD(b.start_date) !== toLD(b.original_start_date) || toLD(b.end_date) !== toLD(b.original_end_date))
  let mod
  if (hasModification) {
    mod = describeModification(b.original_start_date, b.original_end_date, b.start_date, b.end_date)
  }
  const history = Array.isArray(b.modification_history) ? b.modification_history : []

  return (
    <div className="space-y-1">
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Základní údaje</div>
      <SumRow label="Stav" value={STATUS_LABELS[b.status] || b.status} color={b.status === 'cancelled' ? '#dc2626' : b.status === 'active' ? '#1a8a18' : undefined} />
      <SumRow label="ID" value={`#${b.id?.slice(-8).toUpperCase()}`} />
      <SumRow label="Motorka" value={`${b.motorcycles?.model || '—'}${b.motorcycles?.spz ? ` (${b.motorcycles.spz})` : ''}`} />
      <SumRow label="Pobočka" value={branchName} />
      <SumRow label="Zákazník" value={`${b.profiles?.full_name || '—'} (${b.profiles?.email || '—'}, ${b.profiles?.phone || '—'})`} />

      <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Termín</div>
      <SumRow label="Začátek" value={`${new Date(b.start_date).toLocaleDateString('cs-CZ')} v ${b.pickup_time || '9:00'}`} />
      <SumRow label="Konec" value={`${new Date(b.end_date).toLocaleDateString('cs-CZ')} v 9:00`} />
      <SumRow label="Délka" value={`${days} ${days === 1 ? 'den' : days < 5 ? 'dny' : 'dní'}`} />

      {hasModification && (
        <>
          <SumRow label="Původní termín" value={`${new Date(b.original_start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.original_end_date).toLocaleDateString('cs-CZ')} (${mod.origDays} dní)`} color="#b45309" />
          <SumRow label="Úprava rozsahu" value={`${mod.type} (${mod.detail}) → nový: ${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}`} color={mod.color} />
          {history.length > 0 && history.map((h, i) => {
            const hm = describeModification(h.from_start, h.from_end, h.to_start, h.to_end)
            return <SumRow key={i} label={`Úprava #${i + 1}`} value={`${new Date(h.at).toLocaleString('cs-CZ')} — ${hm.type} (${hm.detail}) · ${h.source === 'admin' ? 'admin' : 'zákazník'}`} color={hm.color} />
          })}
        </>
      )}

      <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Vyzvednutí a vrácení</div>
      <SumRow label="Přistavení" value={`${b.pickup_method === 'delivery' ? 'Přistavení na adresu' : 'Na pobočce'} — ${b.pickup_address || branchName}`} />
      <SumRow label="Vrácení" value={`${b.return_method === 'delivery' ? 'Svoz z adresy' : 'Na pobočce'} — ${b.return_address || branchName}`} />

      {(b.boots_size || b.helmet_size || b.jacket_size) && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Výbava</div>
          <SumRow label="Boty" value={b.boots_size ? `vel. ${b.boots_size}` : null} />
          <SumRow label="Helma" value={b.helmet_size ? `vel. ${b.helmet_size}` : null} />
          <SumRow label="Bunda" value={b.jacket_size ? `vel. ${b.jacket_size}` : null} />
        </>
      )}

      {b.insurance_type && <SumRow label="Pojištění" value={b.insurance_type} />}

      {bookingExtras.length > 0 && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Příslušenství</div>
          {bookingExtras.map((ex, i) => (
            <SumRow key={i} label={ex.extras_catalog?.name || `Extra ${i + 1}`} value={`${Number(ex.extras_catalog?.price || 0).toLocaleString('cs-CZ')} Kč`} />
          ))}
        </>
      )}

      <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Platba</div>
      <SumRow label="Celkem" value={`${Number(b.total_price || 0).toLocaleString('cs-CZ')} Kč`} />
      {b.extras_price > 0 && <SumRow label="Příslušenství" value={`${b.extras_price.toLocaleString('cs-CZ')} Kč`} />}
      {b.delivery_fee > 0 && <SumRow label="Doručení" value={`${b.delivery_fee.toLocaleString('cs-CZ')} Kč`} />}
      {b.discount_amount > 0 && <SumRow label="Sleva" value={`-${Number(b.discount_amount).toLocaleString('cs-CZ')} Kč${b.discount_code ? ` (${b.discount_code})` : ''}`} color="#1a8a18" />}
      <SumRow label="Stav platby" value={b.payment_status === 'paid' ? 'Zaplaceno' : 'Nezaplaceno'} color={b.payment_status === 'paid' ? '#1a8a18' : '#dc2626'} />
      {b.payment_method && <SumRow label="Způsob platby" value={b.payment_method} />}
      {b.deposit > 0 && <SumRow label="Kauce" value={`${Number(b.deposit).toLocaleString('cs-CZ')} Kč`} />}

      {promoUsage?.length > 0 && promoUsage.map((pu, i) => (
        <SumRow key={pu.id || i} label={`Promo kód ${i + 1}`} value={`${pu.promo_codes?.code || '—'} → sleva ${Number(pu.discount_applied || 0).toLocaleString('cs-CZ')} Kč`} />
      ))}
      {voucherUsed && <SumRow label="Dárkový poukaz" value={`${voucherUsed.code} — ${Number(voucherUsed.amount).toLocaleString('cs-CZ')} ${voucherUsed.currency}`} />}

      {(b.mileage_start || b.mileage_end) && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Nájezd</div>
          {b.mileage_start && <SumRow label="Při převzetí" value={`${b.mileage_start} km`} />}
          {b.mileage_end && <SumRow label="Při vrácení" value={`${b.mileage_end} km`} />}
          {b.mileage_start && b.mileage_end && <SumRow label="Najeto" value={`${b.mileage_end - b.mileage_start} km`} />}
        </>
      )}

      {b.damage_report && <SumRow label="Poškození" value={b.damage_report} color="#dc2626" />}

      {(b.sos_replacement || b.ended_by_sos || sosIncidents.length > 0) && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#dc2626' }}>SOS</div>
          {b.sos_replacement && (
            <div className="flex items-center gap-2 py-1" style={{ borderBottom: '1px solid #e5e7eb', fontSize: 13 }}>
              <span className="font-extrabold" style={{ color: '#1a2e22', minWidth: 130 }}>SOS náhrada</span>
              <span style={{ color: '#1a8a18' }}>Ano</span>
              {b.replacement_for_booking_id && (
                <button onClick={() => navigate(`/rezervace/${b.replacement_for_booking_id}`)}
                  className="font-bold cursor-pointer ml-1" style={{ color: '#2563eb', background: 'none', border: 'none', fontFamily: 'monospace', fontSize: 13 }}>
                  (za #{b.replacement_for_booking_id.slice(-8).toUpperCase()})
                </button>
              )}
            </div>
          )}
          {b.ended_by_sos && (
            <div className="flex items-center gap-2 py-1 flex-wrap" style={{ borderBottom: '1px solid #e5e7eb', fontSize: 13 }}>
              <span className="font-extrabold" style={{ color: '#1a2e22', minWidth: 130 }}>Ukončeno SOS</span>
              <span style={{ color: '#dc2626' }}>Ano</span>
              {b.sos_incident_id && (
                <button onClick={() => navigate('/sos', { state: { openIncidentId: b.sos_incident_id } })}
                  className="font-bold cursor-pointer ml-1" style={{ color: '#dc2626', background: 'none', border: 'none', fontFamily: 'monospace', fontSize: 13 }}>
                  (incident #{b.sos_incident_id.slice(-8).toUpperCase()})
                </button>
              )}
            </div>
          )}
          {b.ended_by_sos && sosIncidents.length > 0 && !sosIncidents[0].replacement_booking_id && (
            <div className="flex items-center gap-2 py-1 px-2 rounded" style={{ borderBottom: '1px solid #e5e7eb', fontSize: 13, background: '#fef3c7' }}>
              <span className="font-extrabold" style={{ color: '#92400e', minWidth: 130 }}>⚠️ Náhrada</span>
              <span style={{ color: '#92400e' }}>Zákazník dosud nevybral náhradní motorku ({sosIncidents[0].replacement_status || 'selecting'})</span>
            </div>
          )}
          {b.ended_by_sos && sosIncidents.length > 0 && sosIncidents[0].replacement_booking_id && (
            <div className="flex items-center gap-2 py-1" style={{ borderBottom: '1px solid #e5e7eb', fontSize: 13 }}>
              <span className="font-extrabold" style={{ color: '#1a2e22', minWidth: 130 }}>Náhradní rezervace</span>
              <button onClick={() => navigate(`/rezervace/${sosIncidents[0].replacement_booking_id}`)}
                className="font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none', fontFamily: 'monospace', fontSize: 13, padding: 0 }}>
                #{sosIncidents[0].replacement_booking_id.slice(-8).toUpperCase()}
              </button>
            </div>
          )}
          {sosIncidents.map(inc => (
            <div key={inc.id} className="py-1 flex items-center flex-wrap gap-x-2" style={{ borderBottom: '1px solid #fef2f2', fontSize: 13 }}>
              <button onClick={() => navigate('/sos', { state: { openIncidentId: inc.id } })}
                className="font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none', fontFamily: 'monospace', fontSize: 13, padding: 0 }}>
                #{inc.id.slice(-6)}
              </button>
              <span>{inc.type} ({inc.severity}) — {inc.status}</span>
              {inc.title && <span>— {inc.title}</span>}
              <span style={{ color: '#1a2e22' }}>{fmtDT(inc.created_at)}</span>
              {inc.resolved_at && <span style={{ color: '#1a8a18' }}>→ vyřešeno {fmtDT(inc.resolved_at)}</span>}
              {inc.customer_fault && <span className="font-bold" style={{ color: '#b91c1c' }}>[vina zákazníka]</span>}
              {inc.damage_severity && inc.damage_severity !== 'none' && <span style={{ color: '#b45309' }}>[{inc.damage_severity}]</span>}
            </div>
          ))}
        </>
      )}

      {b.status === 'cancelled' && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#dc2626' }}>Zrušení</div>
          <SumRow label="Zrušeno" value={fmtDT(b.cancelled_at)} color="#dc2626" />
          <SumRow label="Zdroj" value={CANCEL_SOURCE_LABELS[b.cancelled_by_source] || b.cancelled_by_source || '—'} />
          <SumRow label="Důvod" value={b.cancellation_reason || '—'} />
          <SumRow label="Email odeslán" value={b.cancellation_notified ? 'Ano' : 'Ne'} />
          {cancellation && (
            <>
              <SumRow label="Vráceno" value={cancellation.refund_amount ? `${Number(cancellation.refund_amount).toLocaleString('cs-CZ')} Kč (${cancellation.refund_percent}%)` : 'Bez refundu'} />
            </>
          )}
        </>
      )}

      <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Průběh</div>
      <SumRow label="Vytvořeno" value={fmtDT(b.created_at)} />
      <SumRow label="Potvrzeno" value={fmtDT(b.confirmed_at)} />
      <SumRow label="Vydáno" value={fmtDT(b.picked_up_at)} />
      <SumRow label="Vráceno" value={fmtDT(b.returned_at)} />
      {b.actual_return_date && <SumRow label="Skutečné vrácení" value={fmtDT(b.actual_return_date)} />}
      {b.cancelled_at && <SumRow label="Zrušeno" value={fmtDT(b.cancelled_at)} color="#dc2626" />}
      {b.rated_at && <SumRow label="Hodnoceno" value={`${fmtDT(b.rated_at)} (${b.rating}/5)`} />}

      {b.notes && (
        <>
          <div className="text-sm font-extrabold uppercase tracking-wide mt-4 mb-2" style={{ color: '#1a2e22' }}>Poznámky</div>
          <p className="text-sm" style={{ color: '#1a2e22' }}>{b.notes}</p>
        </>
      )}

      {b.contract_url && <SumRow label="Smlouva" value={b.signed_contract ? 'Podepsána' : 'Nepodepsána'} />}
      {b.complaint_status && <SumRow label="Reklamace" value={b.complaint_status} color="#b45309" />}
    </div>
  )
}

function InfoRow({ label, value }) {
  return (
    <div className="flex items-center gap-2 mb-1">
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 65 }}>{label}</span>
      <span className="text-sm font-medium" style={{ color: '#0f1a14' }}>{value || '—'}</span>
    </div>
  )
}

function ComplaintsTab({ bookingId, booking, setBooking }) {
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
        booking_id: bookingId,
        customer_id: booking?.user_id || null,
        subject: form.subject,
        description: form.description,
      })
      if (err) throw err
      // Update booking complaint_status
      await supabase.from('bookings').update({ complaint_status: 'open' }).eq('id', bookingId)
      if (setBooking) setBooking(b => ({ ...b, complaint_status: 'open' }))
      setForm({ subject: '', description: '' })
      setShowAdd(false)
      load()
    } catch (e) { setError(e.message) } finally { setSaving(false) }
  }

  async function updateStatus(complaintId, status) {
    await supabase.from('booking_complaints').update({ status, updated_at: new Date().toISOString(), ...(status === 'resolved' ? { resolved_at: new Date().toISOString() } : {}) }).eq('id', complaintId)
    // Update booking complaint_status
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

function SmallActionBtn({ children, onClick, color, bg }) {
  return (
    <button onClick={onClick} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
      style={{ padding: '3px 8px', background: bg, color, border: 'none' }}>{children}</button>
  )
}

function FieldInput({ label, type = 'text', value, onChange }) {
  // For date inputs, convert TIMESTAMPTZ to YYYY-MM-DD in local timezone
  let displayValue = value || ''
  if (type === 'date' && value && value.length > 10) {
    displayValue = new Date(value).toLocaleDateString('sv-SE')
  }
  return (
    <div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
      <input type={type} value={displayValue} onChange={e => onChange(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
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
              <span className="text-sm font-extrabold uppercase tracking-wide mt-1" style={{ color: '#1a8a18' }}>{s.label}</span>
              {s.time && <span className="text-[9px] mt-0.5" style={{ color: '#1a2e22' }}>{new Date(s.time).toLocaleString('cs-CZ')}</span>}
            </div>
          ))}
        </div>
        <div className="p-4 rounded-lg" style={{ background: '#fee2e2' }}>
          <span style={{ color: '#dc2626', fontWeight: 700, fontSize: 13 }}>Zrušena</span>
          {booking.cancelled_at && <span className="ml-3 text-sm" style={{ color: '#dc2626' }}>{new Date(booking.cancelled_at).toLocaleString('cs-CZ')}</span>}
          {sourceLabel && <span className="ml-3 text-sm font-bold" style={{ color: '#991b1b' }}>— {sourceLabel}</span>}
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
            <span className="text-sm font-extrabold uppercase tracking-wide mt-1" style={{ color: s.done ? '#1a8a18' : '#1a2e22' }}>{s.label}</span>
            {s.time && <span className="text-[9px] mt-0.5" style={{ color: '#1a2e22' }}>{new Date(s.time).toLocaleString('cs-CZ')}</span>}
          </div>
          {i < steps.length - 1 && <div style={{ width: 60, height: 2, background: s.done ? '#74FB71' : '#d4e8e0', margin: '0 4px', marginBottom: 20 }} />}
        </div>
      ))}
    </div>
  )
}
