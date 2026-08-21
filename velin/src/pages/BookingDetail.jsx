import { useState, useEffect, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import { generateAdvanceInvoice, generatePaymentReceipt, generateFinalInvoice, renderAndStoreInvoicePdf } from '../lib/invoiceUtils'
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
import { TABS, ACTIONS, CANCEL_REASONS, paymentStatusInfo } from './booking/bookingConstants'
import { sendBookingMessage, logAudit, cancelBookingFromVelin } from './booking/bookingMessageHelpers'
import BookingCancelModal from './booking/BookingCancelModal'
import PaymentConfirmModal from './booking/PaymentConfirmModal'
import AppInstallBadge, { loadAppInstalls } from '../components/AppInstallBadge'

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
  const [showPaymentModal, setShowPaymentModal] = useState(false)
  const [surchargeMode, setSurchargeMode] = useState(false)
  const [cancelReason, setCancelReason] = useState('')
  const [cancelReasonCustom, setCancelReasonCustom] = useState('')
  const [showModifyModal, setShowModifyModal] = useState(false)
  const [promoUsage, setPromoUsage] = useState([])
  const [voucherUsed, setVoucherUsed] = useState(null)
  const [hasCreditNote, setHasCreditNote] = useState(false)
  const [creditNotes, setCreditNotes] = useState([])
  // Navazující rezervace (prodloužení): rezervace, které navazují na tuto
  const [extendedBy, setExtendedBy] = useState([])
  // Indikátor „zákazník má nainstalovanou appku" (app_installations, aktivní do 30 dní)
  const [appInstall, setAppInstall] = useState(null)

  useEffect(() => {
    const uid = booking?.user_id
    if (!uid) { setAppInstall(null); return }
    loadAppInstalls(supabase, [uid]).then(m => setAppInstall(m[uid] || null), () => setAppInstall(null))
  }, [booking?.user_id])

  // Refy pro realtime subscription — callback se vytvoří jen jednou (deps [id]),
  // takže potřebuje vždy aktuální stav (status/platba) i příznak probíhajícího uložení.
  const bookingRef = useRef(null)
  const savingRef = useRef(false)
  useEffect(() => { bookingRef.current = booking }, [booking])
  useEffect(() => { savingRef.current = saving }, [saving])

  useEffect(() => { loadBooking() }, [id])

  // Prodloužení: zjisti, jestli na tuto rezervaci navazuje jiná (extends_booking_id → tato).
  // Jen zobrazení — při chybě (např. sloupec ještě nenasazen) se badge prostě neukáže.
  useEffect(() => {
    if (!id) return
    supabase.from('bookings').select('id, start_date, end_date, status')
      .eq('extends_booking_id', id).neq('status', 'cancelled')
      .then(({ data }) => setExtendedBy(data || []), () => setExtendedBy([]))
  }, [id])

  // Realtime: tabulka `bookings` je v supabase_realtime publikaci, ale detail rezervace
  // se dosud načítal jen jednou při otevření. Když admin nechal kartu otevřenou,
  // potvrzení platby ze Stripe webhooku, storno z appky i auto-přechody z cronu se
  // nikdy nepropsaly — Velín ukazoval „zamrzlý" stav z okamžiku vytvoření.
  // Přihlásíme se na UPDATE/DELETE právě této rezervace a při změně stavu/platby
  // znovu načteme (loadBooking navíc spustí self-heal pending+paid → reserved/active).
  useEffect(() => {
    if (!id) return
    const channel = supabase.channel(`booking-detail-${id}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'bookings', filter: `id=eq.${id}` }, (payload) => {
        // Nereagujeme na vlastní právě probíhající uložení (optimistický update už proběhl)
        // — jinak by reload přepsal rozdělané editace v detailu.
        if (savingRef.current) return
        const cur = bookingRef.current
        const n = payload.new || {}
        if (!cur) return
        if (n.status !== cur.status || n.payment_status !== cur.payment_status) loadBooking()
      })
      .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'bookings', filter: `id=eq.${id}` }, () => {
        setBooking(null)
        setError('Rezervace byla mezitím smazána.')
      })
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [id])

  async function loadBooking() {
    setLoading(true)
    const result = await debugAction('booking.load', 'BookingDetail', () =>
      supabase.from('bookings')
        .select('*, motorcycles!moto_id(id, model, spz, status, branch_id, branches(name)), profiles(id, full_name, email, phone, city)')
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
      // Storno bez vratky: paid + cancelled by paymentStatusInfo odvodilo „Čeká na
      // vrácení". Když ale záznam storna nese vratku 0 (admin „Nevracet peníze",
      // příp. zákaznické storno <48 h), žádné vrácení se nechystá → refund_none.
      if (d && d.status === 'cancelled' && d.payment_status === 'paid') {
        try {
          const { data: cans } = await supabase.from('booking_cancellations')
            .select('refund_amount').eq('booking_id', d.id)
            .order('created_at', { ascending: false }).limit(1)
          if (cans && cans.length) d.refund_none = Number(cans[0].refund_amount || 0) === 0
        } catch { /* bez záznamu ponech odvozené chování */ }
      }
      setBooking(d)
    }
    setLoading(false)
    supabase.from('promo_code_usage').select('*, promo_codes(code, type, value)').eq('booking_id', id)
      .then(({ data }) => { if (data) setPromoUsage(data) }).catch(() => {})
    supabase.from('vouchers').select('code, amount, currency, status').eq('booking_id', id).limit(1)
      .then(({ data }) => { if (data && data.length) setVoucherUsed(data[0]) }).catch(() => {})
    // Plné řádky dobropisů (ne jen bool): manuální vratka (stripe_refund_id NULL)
    // = „Vrátit X Kč na účet zákazníka" — banner + akce „Vratka odeslána".
    supabase.from('invoices').select('id, number, total, stripe_refund_id, notes, issue_date, pdf_path')
      .eq('booking_id', id).eq('type', 'credit_note').neq('status', 'cancelled')
      .order('created_at', { ascending: false })
      .then(({ data }) => { setCreditNotes(data || []); setHasCreditNote(!!(data && data.length)) }).catch(() => {})
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

  // refund = { amount } ze storno modalu (výše vratky v Kč zvolená adminem;
  // undefined u nezaplacené rezervace).
  async function handleCancel(refund) {
    setSaving(true)
    const reasonObj = CANCEL_REASONS.find(r => r.value === cancelReason)
    const reason = cancelReason === 'admin' ? cancelReasonCustom : (reasonObj?.label || cancelReason)
    if (!reason) { setError('Vyplňte důvod zrušení'); setSaving(false); return }

    const result = await debugAction('booking.cancel', 'BookingDetail',
      () => cancelBookingFromVelin(booking, reason, cancelReason, { refundAmount: refund?.amount }),
      { booking_id: id, reason, source: cancelReason, refund_amount: refund?.amount })
    if (result?.error) { setError(result.error); setSaving(false); return }
    setBooking(b => ({ ...b, ...(result.updatePayload || {}) }))
    setShowCancelModal(false); setCancelReason(''); setCancelReasonCustom('')
    // Reload z DB: u rezervace bez Stripe platby (QR/převod/hotově) vystavil
    // process-refund právě MANUÁLNÍ dobropis — bez znovunačtení creditNotes by se
    // banner „VRÁTIT NA ÚČET" a tlačítko „Vratka odeslána" ukázaly až po ručním
    // refreshi stránky.
    await loadBooking()
    setSaving(false)
  }

  async function handleSave() {
    setSaving(true); setError(null)
    const { start_date, end_date, total_price, extras, notes, moto_id, user_id } = booking
    const saveData = { start_date, end_date, total_price, extras, notes, moto_id, user_id }
    const { data: dbBooking } = await supabase.from('bookings')
      .select('start_date, end_date, total_price, pickup_method, pickup_address, return_method, return_address, original_start_date, original_end_date, modification_history, motorcycles!moto_id(model)').eq('id', id).single()
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
    // booking_modified email se posílá automaticky DB triggerem trg_booking_modified_email
    // (po UPDATE bookings) — netřeba volat send-booking-email z Velinu. Trigger detekuje
    // změnu polí (moto, datumy, cena, místo, čas) a pošle mail s diff tabulkou + autoGenerateAttachments
    // fetchne již existující DP úpravy / dobropis.
    setSaving(false)
  }

  const set = (k, v) => setBooking(b => ({ ...b, [k]: v }))
  function handleAction(action) {
    if (action.status === 'cancelled') { setShowCancelModal(true); return }
    // „Potvrdit doplatek" (úprava zaplacené rezervace): potvrzuje se JEN nezaplacená
    // část (doplatek) — původní platba zůstává. RPC confirm_booking_surcharge pak
    // odešle odložený booking_modified mail. Rozlišeno od potvrzení celé rezervace.
    if (action.surcharge) { setSurchargeMode(true); setShowPaymentModal(true); return }
    // „Potvrdit platbu" u nezaplacené Nadcházející/Aktivní rezervace (např. obnovená
    // zrušená rezervace → reserved+unpaid) → stejný ruční platební modal jako u pending.
    if (action.confirmPayment) { setSurchargeMode(false); setShowPaymentModal(true); return }
    // Potvrzení NEZAPLACENÉ rezervace → ruční potvrzení platby (parita se Stripe):
    // vyber způsob platby (QR/převod/hotově…), VS, datum, č. transakce → confirm_payment.
    if (booking.payment_status !== 'paid' && booking.status === 'pending') { setSurchargeMode(false); setShowPaymentModal(true); return }
    setConfirm(action)
  }

  // Obnovení ZRUŠENÉ rezervace → Čeká na platbu (pending) + Nezaplaceno. Podmínky:
  // termín nesmí být v minulosti (dnešek a budoucnost OK) a motorku mezitím nesmí
  // nikdo zabookovat na daný termín ani jeho část. Kolizi kontrolujeme tady ZÁMĚRNĚ —
  // DB trigger check_booking_overlap se spouští jen při UPDATE start_date/end_date/moto_id,
  // samotnou změnu statusu cancelled→reserved nehlídá. (Vozík check_trailer_overlap
  // a per-user check_user_booking_overlap na status reagují — jejich chybu zobrazíme.)
  // Záměrně BEZ mailů a generování dokladů — rezervace je nezaplacená, ZF/DP/smlouva
  // vzniknou standardní cestou až při potvrzení platby. `restored_at` je marker pro
  // cron auto_cancel_expired_pending() (a abandoned mail): obnovenou pending+unpaid
  // rezervaci NIKDY neruší automaticky — created_at je hodiny starý, bez markeru by
  // ji cron do 2 minut zase zrušil. Obnovenou rezervaci řeší admin ručně.
  async function handleRestore() {
    setSaving(true); setError(null)
    try {
      const today = new Date().toLocaleDateString('sv-SE')
      const startLocal = (booking.start_date || '').slice(0, 10)
      const endLocal = (booking.end_date || '').slice(0, 10) || startLocal
      if (!startLocal || startLocal < today) {
        setError('Rezervaci nelze obnovit — termín zapůjčení je v minulosti.')
        setConfirm(null); setSaving(false); return
      }
      // Živá rezervace (pending/reserved/active) stejné motorky překrývající se byť jen
      // jedním dnem — včetně případu, kdy je kus u jiné rezervace přiřazen jako vozík
      // (trailer_moto_id). Sdílený den = kolize (shodně s check_booking_overlap).
      const endNext = new Date(endLocal); endNext.setDate(endNext.getDate() + 1)
      const endExclusive = endNext.toLocaleDateString('sv-SE')
      const { data: conflicts, error: confErr } = await supabase.from('bookings')
        .select('id, start_date, end_date, status')
        .neq('id', id)
        .in('status', ['pending', 'reserved', 'active'])
        .or(`moto_id.eq.${booking.moto_id},trailer_moto_id.eq.${booking.moto_id}`)
        .lt('start_date', endExclusive)
        .gte('end_date', startLocal)
        .limit(1)
      if (confErr) { setError(confErr.message); setConfirm(null); setSaving(false); return }
      if (conflicts && conflicts.length > 0) {
        const c = conflicts[0]
        const fmt = d => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
        setError(`Rezervaci nelze obnovit — motorka je mezitím zabookovaná ${fmt(c.start_date)} – ${fmt(c.end_date)} (rezervace #${c.id.slice(-8).toUpperCase()}).`)
        setConfirm(null); setSaving(false); return
      }

      const update = {
        status: 'pending',
        payment_status: 'unpaid',
        restored_at: new Date().toISOString(),
        cancelled_at: null,
        cancelled_by: null,
        cancelled_by_source: null,
        cancellation_reason: null,
        cancellation_notified: false,
      }
      const res = await debugAction('booking.restore', 'BookingDetail', () =>
        supabase.from('bookings').update(update).eq('id', id)
      , { booking_id: id })
      if (res?.error) { setError(res.error.message); setConfirm(null); setSaving(false); return }
      await logAudit('booking_restored', { booking_id: id, restored_to: 'pending/unpaid' })
      setConfirm(null)
      await loadBooking()
    } catch (e) { setError(e.message) }
    setSaving(false)
  }

  // Manuální vratka odeslána — rezervace bez Stripe platby má po úpravě/stornu
  // vystavený dobropis (stripe_refund_id NULL) a payment_status='refund_pending';
  // po ručním odeslání peněz na účet zákazníka admin potvrdí a stav přejde na
  // 'refunded'. Auditní stopa s částkou a číslem dobropisu.
  async function confirmManualRefundSent() {
    setSaving(true); setError(null)
    try {
      const cn = creditNotes.find(c => !c.stripe_refund_id)
      const amount = cn ? Math.abs(Number(cn.total) || 0) : null
      // Částečná manuální vratka (dobropis < celková cena) → 'partial_refund',
      // plná → 'refunded'.
      const newStatus = amount != null && Number(booking.total_price) > 0 && amount < Number(booking.total_price)
        ? 'partial_refund' : 'refunded'
      const res = await debugAction('booking.manual_refund_sent', 'BookingDetail', () =>
        supabase.from('bookings').update({ payment_status: newStatus }).eq('id', id)
      , { booking_id: id, amount, new_status: newStatus })
      if (res?.error) { setError(res.error.message); setSaving(false); return }
      await logAudit('booking_manual_refund_sent', { booking_id: id, amount, credit_note: cn?.number || null })
      setConfirm(null)
      await loadBooking()
    } catch (e) { setError(e.message) }
    setSaving(false)
  }

  // Potvrzení DOPLATKU za úpravu rezervace — nezaplacená část se označí jako
  // uhrazená a RPC odešle odložený booking_modified mail (+ in-app zprávu).
  async function confirmSurchargePayment(payment) {
    setSaving(true); setError(null)
    try {
      const res = await debugAction('booking.confirm_surcharge', 'BookingDetail', () =>
        supabase.rpc('confirm_booking_surcharge', {
          p_booking_id: id, p_method: payment.method, p_vs: payment.vs,
          p_paid_date: payment.paid_date, p_transaction_ref: payment.transaction_ref,
        })
      , { booking_id: id, method: payment.method })
      if (res?.error) { setError(res.error.message); setSaving(false); return }
      if (res?.data && res.data.success === false) { setError(res.data.error || 'Potvrzení doplatku selhalo'); setSaving(false); return }
      await logAudit('booking_surcharge_confirmed', {
        booking_id: id, amount: res?.data?.amount, method: payment.method,
        vs: payment.vs, paid_date: payment.paid_date, transaction_ref: payment.transaction_ref,
      })
      setShowPaymentModal(false); setSurchargeMode(false)
      await loadBooking()
    } catch (e) { setError(e.message) }
    setSaving(false)
  }

  // Ruční potvrzení platby — projde STEJNÉ flow jako Stripe webhook (confirm_payment RPC
  // + booking_reserved mail). Navíc zapíše ručně zadané platební údaje do rezervace a do
  // ZF/DP. ZF+DP vygenerujeme a uložíme jejich PDF, aby je send-booking-email znovupoužil
  // jako přílohu (místo regenerace bez ručních údajů).
  async function confirmManualPayment(payment) {
    setSaving(true); setError(null)
    try {
      // 1) Reference transakce na rezervaci (payment_method nastaví confirm_payment).
      if (payment.transaction_ref) {
        try { await supabase.from('bookings').update({ payment_reference: payment.transaction_ref }).eq('id', id) } catch { /* nepovinné */ }
      }

      // 2) confirm_payment — payment_status='paid', přechod stavu + timestamps + DB triggery
      //    (přístupové kódy, účetní záznam). Stejné RPC jako Stripe webhook.
      const cp = await debugAction('booking.confirm_payment_manual', 'BookingDetail', () =>
        supabase.rpc('confirm_payment', { p_booking_id: id, p_method: payment.method })
      , { booking_id: id, method: payment.method })
      if (cp?.error) { setError(cp.error.message); setSaving(false); return }
      if (cp?.data && cp.data.success === false) { setError(cp.data.error || 'Potvrzení platby selhalo'); setSaving(false); return }

      // 3) Cílový stav (stejná logika jako confirm_payment): dnes a dříve → active, jinak reserved.
      const today = new Date().toISOString().slice(0, 10)
      const startLocal = booking.start_date ? booking.start_date.slice(0, 10) : today
      const newStatus = startLocal <= today ? 'active' : 'reserved'

      // 4) Doklady ZF + DP s ručními platebními údaji (dedup proti existujícím).
      //    Pokud admin vybral existující ZF, DP se na ni naváže; jinak vznikne nová ZF
      //    a DP se naváže na ni (spárování platby a dokladů).
      const invoiceErrors = []
      let advanceId = payment.advance_invoice_id || null
      let advanceNumber = payment.advance_number || null
      try {
        const { data: existingInv } = await supabase.from('invoices').select('id, type')
          .eq('booking_id', id).in('type', ['advance', 'proforma', 'payment_receipt']).neq('status', 'cancelled')
        if (!(existingInv || []).some(i => i.type === 'advance' || i.type === 'proforma')) {
          try {
            const zf = await generateAdvanceInvoice(id, 'booking', payment)
            await renderAndStoreInvoicePdf(zf.id)
            advanceId = zf.id; advanceNumber = zf.number
          } catch (e) { invoiceErrors.push(`ZF: ${e.message}`) }
        }
        if (!(existingInv || []).some(i => i.type === 'payment_receipt')) {
          try {
            // DP nese stejné VS jako ZF a naváže se na ni (original_invoice_id + poznámka).
            const dpPayment = { ...payment, vs: payment.vs || advanceNumber, advance_invoice_id: advanceId, advance_number: advanceNumber }
            const dp = await generatePaymentReceipt(id, 'booking', dpPayment)
            await renderAndStoreInvoicePdf(dp.id)
          } catch (e) { invoiceErrors.push(`DP: ${e.message}`) }
        }
      } catch (e) { console.error('[manualPay] invoices:', e.message) }

      // 5) Potvrzovací e-mail. NOVÝ FLOW (WEB, platba PŘED doklady): pokud zákazník ještě
      //    nedokončil krok dokladů (čísla) a doklady nejsou ověřené, pošli JEN potvrzení
      //    platby `invoice_payment_receipt` (ZF+DP). Kompletní `web_booking_reserved`
      //    (smlouva+VOP+kódy) dorazí po dokladech přes reserved cron. Doklady OK (přihlášený
      //    s ověřenými doklady / dokončený krok) → booking_reserved rovnou. APP beze změny.
      let mailType = 'booking_reserved'
      if ((booking.booking_source || 'app') === 'web') {
        // REAL-TIME stav dokladů: NEČTI ze zastaralého `booking` z mountu — QR/převod se
        // potvrzuje ručně klidně hodinu po platbě a zákazník mohl doklady mezitím dokončit.
        // Nejdřív čerstvě přečti `docs_completed_at` (vyplněná čísla = povinná část smlouvy),
        // teprve když chybí, ověř scan přes check_booking_docs_status.
        let docsOk = false
        try {
          const { data: fresh } = await supabase.from('bookings').select('docs_completed_at').eq('id', id).maybeSingle()
          docsOk = !!fresh?.docs_completed_at
        } catch { /* ignore → padne na docs-check níže */ }
        if (!docsOk) {
          try {
            const { data: ds } = await supabase.rpc('check_booking_docs_status', {
              p_user_id: booking.user_id, p_end_date: (booking.end_date || '').slice(0, 10), p_moto_id: booking.moto_id,
            })
            docsOk = (ds == null)
          } catch { /* ponech false → invoice_payment_receipt */ }
        }
        // docsOk → zákazník má vše splněné (čísla vyplněná NEBO scan ověřený) → kompletní
        // web_booking_reserved (smlouva+VOP+kódy; kódy se vykreslí, jsou-li uvolněné).
        // Jinak invoice_payment_receipt (ZF+DP + výzva doplnit údaje). Reserved cron
        // dohlídne pozdější doplnění dokladů; message_log dedup zabrání duplicitě.
        mailType = docsOk ? 'booking_reserved' : 'invoice_payment_receipt'
      }
      supabase.functions.invoke('send-booking-email', { body: {
        type: mailType, booking_id: id,
        customer_email: booking.profiles?.email, customer_name: booking.profiles?.full_name,
        motorcycle: booking.motorcycles?.model, start_date: booking.start_date, end_date: booking.end_date,
        total_price: booking.total_price, source: booking.booking_source || 'app',
      } }).catch(() => {})

      await logAudit('booking_payment_confirmed_manual', {
        booking_id: id, method: payment.method, vs: payment.vs,
        paid_date: payment.paid_date, transaction_ref: payment.transaction_ref,
      })
      await sendBookingMessage(newStatus, booking)

      if (invoiceErrors.length > 0) setError(`Platba potvrzena, ale generování dokladů selhalo: ${invoiceErrors.join('; ')}`)
      setShowPaymentModal(false)
      await loadBooking()
    } catch (e) {
      setError(e.message)
    }
    setSaving(false)
  }

  if (loading && !booking) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (!booking) return <div className="p-4" style={{ color: '#1a2e22' }}>{error || 'Rezervace nenalezena'}</div>

  const actionsRaw = (booking.status === 'completed' && booking.sos_replacement && !booking.ended_by_sos)
    ? ACTIONS.completed_sos_replacement || [] : ACTIONS[booking.status] || []
  // „Obnovit" u zrušené rezervace jen když termín zapůjčení není v minulosti
  // (dnešek a budoucnost OK) — jinak nemá obnovení smysl a tlačítko se skryje.
  const todayLocal = new Date().toLocaleDateString('sv-SE')
  const actions = actionsRaw.filter(a => !a.restore || (booking.start_date || '').slice(0, 10) >= todayLocal)
  // Nezaplacený doplatek za úpravu (zaplacená rezervace) → samostatná akce.
  const surchargeDue = Number(booking.mod_surcharge_due) || 0
  const actionsWithSurcharge = (surchargeDue > 0 && ['reserved', 'active'].includes(booking.status))
    ? [{ label: `Potvrdit doplatek (${surchargeDue.toLocaleString('cs-CZ')} Kč)`, status: 'confirm_surcharge', green: true, surcharge: true }, ...actions]
    : actions
  // „Potvrdit platbu" u NEZAPLACENÉ Nadcházející/Aktivní rezervace — typicky zrušená
  // rezervace obnovená tlačítkem Obnovit (reserved+unpaid), kterou zákazník mezitím
  // zaplatil převodem. U status='pending' modal otevírá už akce „Potvrdit" (handleAction);
  // pro reserved/active dosud žádná cesta k potvrzení platby neexistovala. confirm_payment
  // RPC status mimo pending/cancelled nemění — rezervace zůstane reserved/active, jen paid.
  const actionsWithPayment = (booking.payment_status === 'unpaid' && ['reserved', 'active'].includes(booking.status))
    ? [{ label: 'Potvrdit platbu', status: 'confirm_payment', green: true, confirmPayment: true }, ...actionsWithSurcharge]
    : actionsWithSurcharge
  // Manuální vratka (bez Stripe platby): refund_pending bez stripe_refund_id +
  // dobropis bez Stripe refund id = peníze se vrací PŘEVODEM NA ÚČET zákazníka.
  const manualRefundCn = (booking.payment_status === 'refund_pending' && !booking.stripe_refund_id)
    ? creditNotes.find(c => !c.stripe_refund_id) : null
  const manualRefundDue = manualRefundCn ? Math.abs(Number(manualRefundCn.total) || 0) : 0
  const actionsWithRefund = manualRefundDue > 0
    ? [{ label: `Vratka odeslána (${manualRefundDue.toLocaleString('cs-CZ')} Kč)`, status: 'confirm_manual_refund', green: true, refund: true }, ...actionsWithPayment]
    : actionsWithPayment

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
        <AppInstallBadge install={appInstall} />
        {booking.payment_status && (() => {
          const pay = paymentStatusInfo(booking)
          return (
            <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
              style={{ padding: '3px 8px', background: pay.bg, color: pay.color }}>
              {pay.label}
            </span>
          )
        })()}
        {booking.extends_booking_id && (
          <span onClick={() => navigate(`/rezervace/${booking.extends_booking_id}`)}
            className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase cursor-pointer"
            style={{ padding: '3px 8px', background: '#e0e7ff', color: '#4338ca', border: '1px solid #c7d2fe' }}
            title="Navazující rezervace stejného zákazníka na stejnou motorku — jde o úpravu/prodloužení původní rezervace, ne o novou. Kliknutím otevřeš původní.">
            PRODLOUŽENÍ · #{booking.extends_booking_id.slice(-8).toUpperCase()}
          </span>
        )}
        {extendedBy.length > 0 && (
          <span onClick={() => navigate(`/rezervace/${extendedBy[0].id}`)}
            className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase cursor-pointer"
            style={{ padding: '3px 8px', background: '#e0e7ff', color: '#4338ca', border: '1px solid #c7d2fe' }}
            title={`Na tuto rezervaci navazuje prodloužení #${extendedBy[0].id.slice(-8).toUpperCase()} (${extendedBy.length}×). Kliknutím otevřeš navazující.`}>
            PRODLOUŽENO · #{extendedBy[0].id.slice(-8).toUpperCase()}
          </span>
        )}
        {surchargeDue > 0 && (
          <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
            style={{ padding: '3px 8px', background: '#fef3c7', color: '#b45309', border: '1px solid #fcd34d' }}
            title="Úprava rezervace čeká na doplatek — po připsání potvrď tlačítkem Potvrdit doplatek; teprve pak zákazníkovi odejde potvrzení úpravy">
            DOPLATEK — ČEKÁ · {surchargeDue.toLocaleString('cs-CZ')} Kč{booking.mod_surcharge_vs ? ` · VS ${booking.mod_surcharge_vs}` : ''}
          </span>
        )}
        {manualRefundDue > 0 && (
          <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
            style={{ padding: '3px 8px', background: '#fee2e2', color: '#dc2626', border: '1px solid #fca5a5' }}
            title={`Rezervace bez Stripe platby — vratku z úpravy/storna pošli ručně PŘEVODEM na účet zákazníka (do 14 dnů) a potvrď tlačítkem Vratka odeslána. Dobropis ${manualRefundCn?.number || ''}`}>
            VRÁTIT NA ÚČET · {manualRefundDue.toLocaleString('cs-CZ')} Kč
          </span>
        )}
        {booking.pay_channel === 'qr' && booking.payment_status !== 'paid' && (
          <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
            style={{ padding: '3px 8px', background: '#fef3c7', color: '#b45309', border: '1px solid #fcd34d' }}
            title="Zákazník zvolil platbu QR / bankovním převodem — zkontroluj připsání na účtu a potvrď platbu">
            QR/PŘEVOD — ČEKÁ{booking.payment_vs ? ` · VS ${booking.payment_vs}` : ''}
          </span>
        )}
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
      {tab === 'Detail' && <DetailTab booking={booking} set={set} error={error} saving={saving} actions={actionsWithRefund} onAction={handleAction} navigate={navigate} promoUsage={promoUsage} voucherUsed={voucherUsed} onModify={() => setShowModifyModal(true)} />}
      {showModifyModal && booking && <BookingModifyModal booking={booking} onClose={() => setShowModifyModal(false)} onSaved={() => { setShowModifyModal(false); loadBooking() }} />}
      {tab === 'Kalendář motorky' && booking.motorcycles?.id && <BookingsCalendar motoId={booking.motorcycles.id} />}
      {tab === 'Dokumenty' && <BookingDocumentsTab bookingId={id} userId={booking?.user_id} />}
      {tab === 'Platby' && <BookingPaymentsTab bookingId={id} />}
      {tab === 'Reklamace' && <ComplaintsTab bookingId={id} booking={booking} setBooking={setBooking} />}
      {confirm && <ConfirmDialog open title={`${confirm.label}?`}
        message={confirm.refund
          ? 'Potvrď, že vratka byla ODESLÁNA převodem na účet zákazníka — rezervace se označí jako Vráceno (u částečné vratky jako Částečně vráceno).'
          : confirm.restore
            ? 'Rezervace se obnoví do stavu Čeká na platbu / Nezaplaceno (bez automatického zrušení — platbu potvrď tlačítkem Potvrdit, nebo rezervaci zruš ručně). Před obnovením se ověří, že motorka není na termín (ani jeho část) mezitím zabookovaná.'
            : `Změnit stav na "${confirm.label}"?`}
        danger={confirm.danger}
        onConfirm={() => confirm.refund ? confirmManualRefundSent() : confirm.restore ? handleRestore() : changeStatus(confirm.status)}
        onCancel={() => setConfirm(null)} />}
      <BookingCancelModal open={showCancelModal} onClose={() => setShowCancelModal(false)} cancelReason={cancelReason} setCancelReason={setCancelReason} cancelReasonCustom={cancelReasonCustom} setCancelReasonCustom={setCancelReasonCustom} onCancel={handleCancel} saving={saving} error={error}
        paid={booking.payment_status === 'paid'} totalPrice={booking.total_price} />
      <PaymentConfirmModal open={showPaymentModal} onClose={() => { setShowPaymentModal(false); setSurchargeMode(false); setError(null) }}
        onConfirm={surchargeMode ? confirmSurchargePayment : confirmManualPayment} saving={saving} error={error}
        total={surchargeMode ? surchargeDue : booking?.total_price} bookingId={id} payChannel={booking?.pay_channel} paymentVs={booking?.payment_vs}
        surcharge={surchargeMode} surchargeVs={booking?.mod_surcharge_vs} />
    </div>
  )
}
