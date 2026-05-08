import { supabase } from '../../lib/supabase'

export const MSG_TEMPLATES = {
  reserved: (b) => `Vaše rezervace motorky ${b.motorcycles?.model || ''} (${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}) byla potvrzena. Smlouvu a fakturu najdete v sekci Dokumenty.`,
  active: (b) => `Motorka ${b.motorcycles?.model || ''} byla vydána. Přejeme příjemnou jízdu! V případě problému nás kontaktujte nebo použijte SOS tlačítko.`,
  completed: (b) => `Vaše jízda na ${b.motorcycles?.model || ''} byla dokončena. Děkujeme a těšíme se na příště! Konečnou fakturu najdete v sekci Dokumenty.`,
}

export async function logAudit(action, details) {
  try { const { data: { user } } = await supabase.auth.getUser(); await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details }) } catch {}
}

export async function sendBookingMessage(status, bk) {
  const template = MSG_TEMPLATES[status]
  if (!template || !bk.user_id) return
  try {
    let { data: thread } = await supabase.from('message_threads').select('id').eq('customer_id', bk.user_id).limit(1).single()
    if (!thread) {
      const { data: newThread } = await supabase.from('message_threads').insert({ customer_id: bk.user_id, subject: 'Rezervace', channel: 'app' }).select('id').single()
      thread = newThread
    }
    if (!thread) return
    await supabase.from('messages').insert({ thread_id: thread.id, direction: 'admin', sender_name: 'MotoGo', content: template(bk) })
    await supabase.from('message_threads').update({ last_message_at: new Date().toISOString() }).eq('id', thread.id)
  } catch {}
}

// Společný flow pro storno rezervace ze Velínu (BookingDetail i Bookings list).
// Provádí: UPDATE bookings (status, cancellation_reason, cancelled_by_source...),
// zápis booking_cancellations, Stripe refund (process-refund) a generování dobropisu
// pokud byla rezervace zaplacená, audit log a finálně send-cancellation-email
// (důvod se posílá v emailu i zobrazí ve Velínu z bookings.cancellation_reason).
export async function cancelBookingFromVelin(booking, reasonText, sourceCode) {
  if (!booking?.id) return { error: 'Chybí ID rezervace' }
  if (!reasonText) return { error: 'Vyplňte důvod zrušení' }

  const { data: { user } } = await supabase.auth.getUser()
  const wasPaid = booking.payment_status === 'paid'
  const updatePayload = {
    status: 'cancelled',
    cancelled_by: user?.id || null,
    cancelled_by_source: sourceCode,
    cancellation_reason: reasonText,
    cancelled_at: new Date().toISOString(),
    ...(wasPaid ? { payment_status: 'refunded' } : {}),
  }

  const { error: updErr } = await supabase.from('bookings').update(updatePayload).eq('id', booking.id)
  if (updErr) return { error: updErr.message }

  if (wasPaid && booking.total_price) {
    try {
      await supabase.from('booking_cancellations').insert({
        booking_id: booking.id,
        cancelled_by: user?.id || null,
        reason: reasonText,
        refund_amount: booking.total_price,
        refund_percent: 100,
      })
    } catch {}

    if (booking.stripe_payment_intent_id) {
      try {
        await supabase.functions.invoke('process-refund', {
          body: { booking_id: booking.id, reason: 'cancellation' },
        })
      } catch (e) { console.error('[Stripe refund]', e.message) }
    }

    // Dobropis (PDF) generuje send-cancellation-email níže — má vlastní idempotentní flow
    // přes generate-invoice s extra_items (negativní cena = dobropis). Přidá ho i jako přílohu mailu.
    // Žádné samostatné generování ve Velínu — jeden zdroj pravdy.
  }

  await logAudit('booking_cancelled', { booking_id: booking.id, reason: reasonText, source: sourceCode, refund: wasPaid ? '100%' : 'n/a' })

  let emailNotified = false
  if (booking.profiles?.email || booking.customer_email) {
    try {
      await supabase.functions.invoke('send-cancellation-email', {
        body: {
          booking_id: booking.id,
          customer_email: booking.profiles?.email || booking.customer_email,
          customer_name: booking.profiles?.full_name || booking.customer_name,
          motorcycle: booking.motorcycles?.model,
          start_date: booking.start_date,
          end_date: booking.end_date,
          cancellation_reason: reasonText,
          cancelled_by_source: sourceCode,
          source: booking.booking_source || 'app',
          ...(wasPaid ? { refund_amount: booking.total_price, refund_percent: 100 } : {}),
        },
      })
      await supabase.from('bookings').update({ cancellation_notified: true }).eq('id', booking.id)
      emailNotified = true
    } catch {}
  }

  return { success: true, updatePayload: { ...updatePayload, ...(emailNotified ? { cancellation_notified: true } : {}) } }
}
