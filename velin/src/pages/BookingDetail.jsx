import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import { generateAdvanceInvoice, generatePaymentReceipt, generateFinalInvoice, generateCreditNote } from '../lib/invoiceUtils'
import Button from '../components/ui/Button'
import StatusBadge, { getDisplayStatus } from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import Modal from '../components/ui/Modal'
import BookingDocumentsTab from './booking/BookingDocumentsTab'
import BookingPaymentsTab from './booking/BookingPaymentsTab'
import BookingsCalendar from '../components/fleet/BookingsCalendar'
import BookingModifyModal from './booking/BookingModifyModal'
import DetailTab from './booking/DetailTab'
import ComplaintsTab from './booking/ComplaintsTab'
import { TABS, ACTIONS, CANCEL_REASONS } from './booking/bookingConstants'
import { sendBookingMessage, logAudit } from './booking/bookingMessageHelpers'
import BookingCancelModal from './booking/BookingCancelModal'

export default function BookingDetail() {
  const debugMode = useDebugMode()
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
  const [showModifyModal, setShowModifyModal] = useState(false)
  const [promoUsage, setPromoUsage] = useState([])
  const [voucherUsed, setVoucherUsed] = useState(null)
  const [hasCreditNote, setHasCreditNote] = useState(false)

  useEffect(() => { loadBooking() }, [id])

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
        const normDate = v => v && v.length > 10 ? new Date(v).toLocaleDateString('sv-SE') : v
        if (d.start_date) d.start_date = normDate(d.start_date)
        if (d.end_date) d.end_date = normDate(d.end_date)
        if (d.original_start_date) d.original_start_date = normDate(d.original_start_date)
        if (d.original_end_date) d.original_end_date = normDate(d.original_end_date)
      }
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
          Promise.allSettled([
            supabase.functions.invoke('generate-document', { body: { template_slug: 'rental_contract', booking_id: d.id } }),
            supabase.functions.invoke('generate-document', { body: { template_slug: 'vop', booking_id: d.id } }),
          ]).catch(() => {})
        }
      }
      if (d && (d.status === 'active' || d.status === 'reserved') && d.payment_status === 'paid') {
        const { data: genDocs } = await supabase.from('generated_documents').select('id').eq('booking_id', d.id).limit(1)
        if (!genDocs || genDocs.length === 0) {
          Promise.allSettled([
            supabase.functions.invoke('generate-document', { body: { template_slug: 'rental_contract', booking_id: d.id } }),
            supabase.functions.invoke('generate-document', { body: { template_slug: 'vop', booking_id: d.id } }),
          ]).catch(() => {})
        }
      }
      setBooking(d)
    }
    setLoading(false)
    supabase.from('promo_code_usage').select('*, promo_codes(code, type, value)').eq('booking_id', id)
      .then(({ data }) => { if (data) setPromoUsage(data) }).catch(() => {})
    supabase.from('vouchers').select('code, amount, currency, status').eq('booking_id', id).limit(1)
      .then(({ data }) => { if (data && data.length) setVoucherUsed(data[0]) }).catch(() => {})
    supabase.from('invoices').select('id').eq('booking_id', id).eq('type', 'credit_note').limit(1)
      .then(({ data }) => { setHasCreditNote(data && data.length > 0) }).catch(() => {})
  }

  async function changeStatus(newStatus) {
    setSaving(true)

    // Kontrola dokladů před aktivací
    if (newStatus === 'active' && booking?.user_id) {
      const { data: prof } = await supabase.from('profiles')
        .select('license_group, docs_verified_at, docs_verification_status')
        .eq('id', booking.user_id).single()
      const docsOk = prof?.license_group?.length > 0 && (prof?.docs_verified_at || prof?.docs_verification_status === 'verified')
      if (!docsOk) {
        if (!window.confirm('POZOR: Zákazník nemá ověřené doklady! Opravdu chcete aktivovat rezervaci bez dokladů?')) {
          setSaving(false); return
        }
      }
    }

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

    const emailBody = {
      booking_id: id, customer_email: booking.profiles?.email, customer_name: booking.profiles?.full_name,
      motorcycle: booking.motorcycles?.model, start_date: booking.start_date, end_date: booking.end_date, total_price: booking.total_price,
    }
    const invoiceErrors = []
    try {
      if (newStatus === 'reserved') {
        try { await generateAdvanceInvoice(id, 'booking') } catch (e) { invoiceErrors.push(`ZF: ${e.message}`) }
        try { await generatePaymentReceipt(id, 'booking') } catch (e) { invoiceErrors.push(`DP: ${e.message}`) }
        Promise.allSettled([
          supabase.functions.invoke('generate-document', { body: { template_slug: 'rental_contract', booking_id: id } }),
          supabase.functions.invoke('generate-document', { body: { template_slug: 'vop', booking_id: id } }),
          supabase.functions.invoke('send-booking-email', { body: { ...emailBody, type: 'booking_reserved' } }),
        ]).catch(() => {})
      } else if (newStatus === 'active') {
        try {
          const { data: existingInv } = await supabase.from('invoices').select('type').eq('booking_id', id)
            .in('type', ['advance', 'proforma', 'payment_receipt']).neq('status', 'cancelled')
          if (!(existingInv || []).some(i => i.type === 'advance' || i.type === 'proforma')) {
            try { await generateAdvanceInvoice(id, 'booking') } catch (e) { invoiceErrors.push(`ZF: ${e.message}`) }
          }
          if (!(existingInv || []).some(i => i.type === 'payment_receipt')) {
            try { await generatePaymentReceipt(id, 'booking') } catch (e) { invoiceErrors.push(`DP: ${e.message}`) }
          }
        } catch (e) { console.error('[Invoice] check existing:', e.message) }
        Promise.allSettled([
          supabase.functions.invoke('generate-document', { body: { template_slug: 'rental_contract', booking_id: id } }),
          supabase.functions.invoke('generate-document', { body: { template_slug: 'vop', booking_id: id } }),
          supabase.functions.invoke('generate-document', { body: { template_slug: 'handover_protocol', booking_id: id } }),
        ]).catch(() => {})
      } else if (newStatus === 'completed') {
        try {
          const { data: existingInv } = await supabase.from('invoices').select('type').eq('booking_id', id)
            .in('type', ['advance', 'proforma', 'payment_receipt']).neq('status', 'cancelled')
          if (!(existingInv || []).some(i => i.type === 'advance' || i.type === 'proforma')) {
            try { await generateAdvanceInvoice(id, 'booking') } catch (e) { invoiceErrors.push(`ZF: ${e.message}`) }
          }
          if (!(existingInv || []).some(i => i.type === 'payment_receipt')) {
            try { await generatePaymentReceipt(id, 'booking') } catch (e) { invoiceErrors.push(`DP: ${e.message}`) }
          }
        } catch (e) { console.error('[Invoice] check existing (completed):', e.message) }
        try { await generateFinalInvoice(id) } catch (e) { invoiceErrors.push(`KF: ${e.message}`) }
        supabase.functions.invoke('send-booking-email', { body: { ...emailBody, type: 'booking_completed' } }).catch(() => {})
      }
    } catch (e) { console.error('[Auto-triggers]', e.message) }

    if (invoiceErrors.length > 0) setError(`Stav změněn, ale generování faktur selhalo: ${invoiceErrors.join('; ')}`)
    await sendBookingMessage(newStatus, booking)
    setBooking(b => ({ ...b, ...update }))
    setConfirm(null); setSaving(false)
  }

  async function handleCancel() {
    setSaving(true)
    const reasonObj = CANCEL_REASONS.find(r => r.value === cancelReason)
    const reason = cancelReason === 'admin' ? cancelReasonCustom : (reasonObj?.label || cancelReason)
    if (!reason) { setError('Vyplňte důvod zrušení'); setSaving(false); return }

    const { data: { user } } = await supabase.auth.getUser()
    const wasPaid = booking.payment_status === 'paid'
    const updatePayload = {
      status: 'cancelled', cancelled_by: user?.id || null, cancelled_by_source: cancelReason,
      cancellation_reason: reason, cancelled_at: new Date().toISOString(),
      ...(wasPaid ? { payment_status: 'refunded' } : {}),
    }

    const cancelResult = await debugAction('booking.cancel', 'BookingDetail', () =>
      supabase.from('bookings').update(updatePayload).eq('id', id)
    , { booking_id: id, reason, source: cancelReason })
    if (cancelResult?.error) { setError(cancelResult.error.message); setSaving(false); return }

    if (wasPaid && booking.total_price) {
      try { await supabase.from('booking_cancellations').insert({ booking_id: id, cancelled_by: user?.id || null, reason, refund_amount: booking.total_price, refund_percent: 100 }) } catch {}

      // Stripe refund + credit note generation
      let stripeRefundId = null
      if (booking.stripe_payment_intent_id) {
        try {
          const { data: refundResult } = await supabase.functions.invoke('process-refund', {
            body: { booking_id: id, reason: 'cancellation' },
          })
          if (refundResult?.success) stripeRefundId = refundResult.refund_id
        } catch (e) { console.error('[Stripe refund]', e.message) }
      }

      // Generate credit note (dobropis)
      try {
        await generateCreditNote(id, {
          refundAmount: booking.total_price,
          refundPercent: 100,
          reason,
          stripeRefundId,
        })
      } catch (e) { console.error('[Credit note]', e.message) }
    }
    await logAudit('booking_cancelled', { booking_id: id, reason, source: cancelReason, refund: wasPaid ? '100%' : 'n/a' })

    if (booking.profiles?.email) {
      try {
        await supabase.functions.invoke('send-cancellation-email', {
          body: { booking_id: id, customer_email: booking.profiles?.email, customer_name: booking.profiles?.full_name, motorcycle: booking.motorcycles?.model,
            start_date: booking.start_date, end_date: booking.end_date, cancellation_reason: reason, cancelled_by_source: cancelReason,
            ...(wasPaid ? { refund_amount: booking.total_price, refund_percent: 100 } : {}),
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
    const saveData = { start_date, end_date, total_price, extras, notes, moto_id, user_id }
    const { data: dbBooking } = await supabase.from('bookings')
      .select('start_date, end_date, total_price, pickup_method, pickup_address, return_method, return_address, original_start_date, original_end_date, modification_history, motorcycles(model)').eq('id', id).single()
    if (dbBooking) {
      const toLD = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
      const dateChanged = toLD(dbBooking.start_date) !== toLD(start_date) || toLD(dbBooking.end_date) !== toLD(end_date)
      if (dateChanged) {
        if (!dbBooking.original_start_date) { saveData.original_start_date = toLD(dbBooking.start_date); saveData.original_end_date = toLD(dbBooking.end_date) }
        const history = Array.isArray(dbBooking.modification_history) ? [...dbBooking.modification_history] : []
        history.push({ at: new Date().toISOString(), from_start: toLD(dbBooking.start_date), from_end: toLD(dbBooking.end_date), to_start: toLD(start_date), to_end: toLD(end_date), source: 'admin' })
        saveData.modification_history = history
      }
    }
    const saveResult = await debugAction('booking.save', 'BookingDetail', () => supabase.from('bookings').update(saveData).eq('id', id), saveData)
    if (saveResult?.error) { setError(saveResult.error.message); setSaving(false); return }
    await logAudit('booking_updated', { booking_id: id })
    if (['reserved', 'active'].includes(booking.status) && booking.profiles?.email) {
      try {
        await supabase.functions.invoke('send-booking-email', {
          body: {
            type: 'booking_modified',
            booking_id: id,
            customer_email: booking.profiles.email,
            customer_name: booking.profiles.full_name,
            source: booking.booking_source || 'app',
            motorcycle:    booking.motorcycles?.model,
            start_date,
            end_date,
            total_price,
            pickup_method:  booking.pickup_method || '',
            pickup_address: booking.pickup_address || '',
            return_method:  booking.return_method || '',
            return_address: booking.return_address || '',
            // Původní hodnoty z DB (před UPDATEm)
            original_motorcycle:     dbBooking.motorcycles?.model || booking.motorcycles?.model || '',
            original_start_date:     dbBooking.start_date,
            original_end_date:       dbBooking.end_date,
            original_total_price:    dbBooking.total_price,
            original_pickup_method:  dbBooking.pickup_method || '',
            original_pickup_address: dbBooking.pickup_address || '',
            original_return_method:  dbBooking.return_method || '',
            original_return_address: dbBooking.return_address || '',
          },
        })
      } catch {}
    }
    setSaving(false)
  }

  const set = (k, v) => setBooking(b => ({ ...b, [k]: v }))
  function handleAction(action) {
    if (action.status === 'cancelled') setShowCancelModal(true)
    else setConfirm(action)
  }

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (!booking) return <div className="p-4" style={{ color: '#1a2e22' }}>{error || 'Rezervace nenalezena'}</div>

  const actions = (booking.status === 'completed' && booking.sos_replacement && !booking.ended_by_sos)
    ? ACTIONS.completed_sos_replacement || [] : ACTIONS[booking.status] || []

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => navigate('/rezervace')} className="cursor-pointer" style={{ background: 'none', border: 'none', fontSize: 18, color: '#1a2e22' }}>←</button>
        <h2 className="font-extrabold text-lg" style={{ color: '#0f1a14' }}>Rezervace</h2>
        <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>#{id?.slice(-8).toUpperCase()}</span>
        <StatusBadge status={getDisplayStatus(booking)} />
        {booking.booking_source && (
          <span className="inline-flex items-center gap-1 rounded-btn text-sm font-extrabold tracking-wide uppercase"
            style={{ padding: '3px 8px', background: booking.booking_source === 'web' ? '#dbeafe' : '#dcfce7', color: booking.booking_source === 'web' ? '#2563eb' : '#16a34a' }}>
            {booking.booking_source === 'web' ? 'WEB' : 'APP'}
            {booking.created_via_ai && (
              <span title="Vytvořeno přes AI asistenta" style={{ background: '#fef3c7', color: '#92400e', padding: '1px 5px', borderRadius: 6, fontSize: 11, fontWeight: 800 }}>🤖 AI</span>
            )}
          </span>
        )}
        {booking.payment_status && (() => {
          const isPaid = booking.payment_status === 'paid' && booking.status !== 'pending'
          const isRefunded = booking.payment_status === 'refunded'
          return (
            <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
              style={{ padding: '3px 8px', background: isPaid ? '#dcfce7' : isRefunded ? '#fee2e2' : '#fee2e2', color: isPaid ? '#1a8a18' : '#dc2626' }}>
              {isPaid ? 'Zaplaceno' : isRefunded ? 'Refundováno' : 'Nezaplaceno'}
            </span>
          )
        })()}
        {hasCreditNote && (
          <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
            style={{ padding: '3px 8px', background: '#fee2e2', color: '#dc2626', border: '1px solid #fca5a5' }}>
            DOBROPIS
          </span>
        )}
        <span className="text-sm" style={{ color: '#1a2e22' }}>Vytvořena: {booking.created_at ? new Date(booking.created_at).toLocaleString('cs-CZ') : '—'}</span>
      </div>
      <div className="flex gap-2 mb-5 flex-wrap">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>{t}</button>
        ))}
      </div>
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA BookingDetail (#{id?.slice(-8)})</strong><br/>
        <div>booking: status={booking.status}, payment={booking.payment_status}, price={booking.total_price} Kč</div>
        <div>customer: {booking.profiles?.full_name || '—'} ({booking.profiles?.email || '—'})</div>
        <div>moto: {booking.motorcycles?.model || '—'} ({booking.motorcycles?.spz || '—'})</div>
        <div>dates: {booking.start_date} → {booking.end_date}</div>
        <div>promo_usage: {promoUsage.length}, voucher: {voucherUsed ? voucherUsed.code : 'žádný'}</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}
      {tab === 'Detail' && <DetailTab booking={booking} set={set} error={error} saving={saving} actions={actions} onAction={handleAction} navigate={navigate} promoUsage={promoUsage} voucherUsed={voucherUsed} onModify={() => setShowModifyModal(true)} />}
      {showModifyModal && booking && <BookingModifyModal booking={booking} onClose={() => setShowModifyModal(false)} onSaved={() => { setShowModifyModal(false); loadBooking() }} />}
      {tab === 'Kalendář motorky' && booking.motorcycles?.id && <BookingsCalendar motoId={booking.motorcycles.id} />}
      {tab === 'Dokumenty' && <BookingDocumentsTab bookingId={id} />}
      {tab === 'Platby' && <BookingPaymentsTab bookingId={id} />}
      {tab === 'Reklamace' && <ComplaintsTab bookingId={id} booking={booking} setBooking={setBooking} />}
      {confirm && <ConfirmDialog open title={`${confirm.label}?`} message={`Změnit stav na "${confirm.label}"?`} danger={confirm.danger} onConfirm={() => changeStatus(confirm.status)} onCancel={() => setConfirm(null)} />}
      <BookingCancelModal open={showCancelModal} onClose={() => setShowCancelModal(false)} cancelReason={cancelReason} setCancelReason={setCancelReason} cancelReasonCustom={cancelReasonCustom} setCancelReasonCustom={setCancelReasonCustom} onCancel={handleCancel} saving={saving} error={error} />
    </div>
  )
}
