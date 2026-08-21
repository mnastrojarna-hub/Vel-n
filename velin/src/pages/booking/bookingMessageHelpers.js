import { supabase } from '../../lib/supabase'

export const MSG_TEMPLATES = {
  reserved: (b) => `Vaše rezervace motorky ${b.motorcycles?.model || ''} (${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}) byla potvrzena. Smlouvu a fakturu najdete v sekci Dokumenty.`,
  active: (b) => `Motorka ${b.motorcycles?.model || ''} byla vydána. Přejeme příjemnou jízdu! V případě problému nás kontaktujte nebo použijte SOS tlačítko.`,
  completed: (b) => `Vaše jízda na ${b.motorcycles?.model || ''} byla dokončena. Děkujeme a těšíme se na příště! Konečnou fakturu najdete v sekci Dokumenty.`,
}

// Rozbalí skutečnou chybu z edge funkce — supabase.functions.invoke vrací jen
// generické „Edge Function returned a non-2xx status code"; tělo odpovědi
// s {error, code} je schované v error.context (Response).
export async function edgeErrorDetail(error) {
  try {
    if (error?.context && typeof error.context.json === 'function') {
      const j = await error.context.json()
      if (j?.error || j?.code) return [j.error, j.code && j.error !== j.code ? `(${j.code})` : null].filter(Boolean).join(' ')
    }
  } catch { /* tělo odpovědi nejde přečíst — fallback níže */ }
  return error?.message || String(error)
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
// opts.refundAmount (Kč) → výše vratky zadaná adminem ve storno modalu:
// undefined/null = plných 100 % (historické chování), 0 = storno BEZ vratky
// (peníze zůstávají u nás, refund/dobropis se přeskočí, payment_status zůstává
// 'paid'), jinak ČÁSTEČNÁ vratka (clamp 0..total_price) — process-refund umí
// partial Stripe refund i manuální dobropis na částku (QR/převod/hotově).
export async function cancelBookingFromVelin(booking, reasonText, sourceCode, opts = {}) {
  if (!booking?.id) return { error: 'Chybí ID rezervace' }
  if (!reasonText) return { error: 'Vyplňte důvod zrušení' }

  const { data: { user } } = await supabase.auth.getUser()
  const wasPaid = booking.payment_status === 'paid'
  const total = Math.max(0, Math.round(Number(booking.total_price) || 0))
  let refundAmount = wasPaid ? total : 0
  if (wasPaid && opts.refundAmount != null && Number.isFinite(Number(opts.refundAmount))) {
    refundAmount = Math.min(total, Math.max(0, Math.round(Number(opts.refundAmount))))
  }
  if (wasPaid && opts.noRefund === true) refundAmount = 0
  const refundPercent = wasPaid && total > 0 ? Math.round(refundAmount / total * 100) : 0
  const isFull = wasPaid && refundAmount >= total
  // Vratka 0 (storno bez vratky): peníze zůstávají u nás — žádný Stripe refund,
  // žádný dobropis, payment_status zůstává 'paid'. booking_cancellations dostane
  // refund 0 % (auditní stopa, stejně jako zákaznické storno <48 h) a
  // refund_percent: 0 se posílá i do send-cancellation-email — bez toho by si
  // edge fn vratku dopočítala sama (fallback dle storno tabulky běží jen při
  // refund_percent == null) a peníze by přes process-refund vrátila proti vůli
  // admina.
  const noRefund = wasPaid && refundAmount === 0
  // POZOR: payment_status='refunded' tu ZÁMĚRNĚ NENASTAVUJEME před refundem.
  // process-refund musí načíst booking ve stavu, který umožní reálný Stripe refund
  // ('paid' nebo 'refund_pending'); kdyby viděl 'refunded'/'partial_refund', spadne do
  // idempotentní "already refunded" větve a Stripe vůbec nezavolá (peníze by se nikdy
  // nevrátily). Stav 'refunded'/'partial_refund' do DB zapíše až process-refund po
  // potvrzení Stripe. Zaplacenou rezervaci proto rovnou označíme 'refund_pending'
  // (= „Čeká na vrácení") — peníze jsou pořád u nás, jen je storno a čeká se na vrácení.
  // Tím už nikdy nezobrazíme „Nezaplaceno" u stornované zaplacené rezervace.
  const updatePayload = {
    status: 'cancelled',
    cancelled_by: user?.id || null,
    cancelled_by_source: sourceCode,
    cancellation_reason: reasonText,
    cancelled_at: new Date().toISOString(),
    ...(wasPaid && !noRefund ? { payment_status: 'refund_pending' } : {}),
  }

  const { error: updErr } = await supabase.from('bookings').update(updatePayload).eq('id', booking.id)
  if (updErr) return { error: updErr.message }

  if (wasPaid && booking.total_price) {
    try {
      await supabase.from('booking_cancellations').insert({
        booking_id: booking.id,
        cancelled_by: user?.id || null,
        reason: reasonText,
        refund_amount: refundAmount,
        refund_percent: refundPercent,
      })
    } catch {}

    // Reálný Stripe refund dle zvolené výše (plná = bez amount, částečná =
    // s amount; process-refund si clampne na skutečně stržené). Voláme vždy,
    // i když objekt booking nemá načtený stripe_payment_intent_id — process-refund
    // si ho umí dohledat ze stripe_session_id. Je idempotentní, takže následné
    // volání ze send-cancellation-email už jen dohraje dobropis (Stripe podruhé
    // nestrhne).
    if (!noRefund) {
      try {
        await supabase.functions.invoke('process-refund', {
          body: { booking_id: booking.id, reason: 'cancellation', ...(isFull ? {} : { amount: refundAmount }) },
        })
      } catch (e) { console.error('[Stripe refund]', e.message) }
    }

    // Dobropis (PDF) generuje send-cancellation-email níže — má vlastní idempotentní flow
    // přes generate-invoice s extra_items (negativní cena = dobropis). Přidá ho i jako přílohu mailu.
    // Žádné samostatné generování ve Velínu — jeden zdroj pravdy.
  }

  await logAudit('booking_cancelled', { booking_id: booking.id, reason: reasonText, source: sourceCode, refund: wasPaid ? (noRefund ? '0% (bez vratky)' : `${refundPercent}% (${refundAmount} Kč)`) : 'n/a' })

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
          ...(wasPaid ? { refund_amount: refundAmount, refund_percent: refundPercent } : {}),
        },
      })
      await supabase.from('bookings').update({ cancellation_notified: true }).eq('id', booking.id)
      emailNotified = true
    } catch {}
  }

  // Optimistický UI update musí odrážet REALITU, ne přání. Po doběhnutí process-refund
  // (volá se výše synchronně) si proto skutečný stav platby přečteme z DB — bude to
  // 'refunded' (Stripe potvrdil plné vrácení), 'partial_refund' (částečně, např. 50 %),
  // nebo zůstane 'refund_pending' (Stripe ještě nepotvrdil / refund se nepovedl).
  // Fallback: když read selže, držíme 'refund_pending' (nikdy ne falešné 'refunded').
  // Storno bez vratky žádný refund nespouští — payment_status zůstává 'paid'.
  let finalPaymentStatus = wasPaid && !noRefund ? 'refund_pending' : undefined
  if (wasPaid && !noRefund) {
    try {
      const { data: fresh } = await supabase.from('bookings').select('payment_status').eq('id', booking.id).single()
      if (fresh?.payment_status) finalPaymentStatus = fresh.payment_status
    } catch {}
  }
  return { success: true, no_refund: noRefund, updatePayload: { ...updatePayload, ...(finalPaymentStatus ? { payment_status: finalPaymentStatus } : {}), ...(noRefund ? { refund_none: true } : {}), ...(emailNotified ? { cancellation_notified: true } : {}) } }
}
