// ===== webhook-receiver/payment-confirmers.ts =====
// Payment confirmation functions for booking, shop, SOS + financial event ingestion

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/** Confirm booking payment via existing RPC */
export async function confirmBookingPayment(
  supabase: ReturnType<typeof createClient>,
  bookingId: string,
  transactionId: string,
  stripePaymentIntentId?: string | null
) {
  try {
    const { data, error } = await supabase.rpc('confirm_payment', {
      p_booking_id: bookingId,
      p_method: 'card',
    })

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'confirm_booking_payment',
        component: 'stripe',
        status: error ? 'error' : 'ok',
        request_data: { booking_id: bookingId, transaction_id: transactionId },
        response_data: data,
        error_message: error?.message || null,
      })
    } catch (e) { /* ignore */ }

    if (error) {
      console.error('confirm_payment RPC failed:', error.message)
      const { data: bk } = await supabase.from('bookings')
        .select('start_date')
        .eq('id', bookingId)
        .single()
      const today = new Date().toISOString().slice(0, 10)
      const startDate = bk?.start_date || today
      const isToday = startDate <= today
      await supabase.from('bookings')
        .update({
          payment_status: 'paid',
          payment_method: 'card',
          status: isToday ? 'active' : 'reserved',
          ...(isToday
            ? { picked_up_at: new Date().toISOString() }
            : { confirmed_at: new Date().toISOString() }),
        })
        .eq('id', bookingId)
    }

    // Save Stripe IDs for future refunds
    if (stripePaymentIntentId) {
      try {
        await supabase.from('bookings')
          .update({
            stripe_payment_intent_id: stripePaymentIntentId,
            stripe_session_id: transactionId,
          })
          .eq('id', bookingId)
      } catch (e) { /* ignore */ }
    }

    // Auto-generate documents (non-blocking, best-effort)
    try {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
      const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }

      const { data: existingZf } = await supabase.from('invoices')
        .select('id').eq('booking_id', bookingId)
        .in('type', ['advance', 'proforma']).limit(1)
      if (!existingZf?.length) {
        try {
          await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
            method: 'POST', headers,
            body: JSON.stringify({ type: 'advance', booking_id: bookingId }),
          })
        } catch (e) { /* ignore */ }
      }

      try {
        await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', booking_id: bookingId }),
        })
      } catch (e) { /* ignore */ }

      try {
        await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'rental_contract', booking_id: bookingId }),
        })
      } catch (e) { /* ignore */ }
      try {
        await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'vop', booking_id: bookingId }),
        })
      } catch (e) { /* ignore */ }

      const { data: booking } = await supabase.from('bookings')
        .select('booking_source, user_id, moto_id, start_date, end_date, total_price, motorcycles(model, manual_url), profiles(full_name, email)')
        .eq('id', bookingId).single()

      if (booking?.profiles?.email) {
        const source = booking.booking_source || 'app'
        const moto = booking.motorcycles as { model?: string; manual_url?: string } | null
        const profile = booking.profiles as { full_name?: string; email?: string }

        try {
          await fetch(`${SUPABASE_URL}/functions/v1/send-booking-email`, {
            method: 'POST', headers,
            body: JSON.stringify({
              type: 'booking_reserved',
              booking_id: bookingId,
              customer_email: profile.email,
              customer_name: profile.full_name || '',
              motorcycle: moto?.model || '',
              start_date: booking.start_date,
              end_date: booking.end_date,
              total_price: booking.total_price,
              source: source,
              manual_url: moto?.manual_url || '',
            }),
          })
        } catch (e) { /* ignore */ }
      }
    } catch (e) { /* doc gen is best-effort */ }
  } catch (err) {
    console.error('confirmBookingPayment error:', err)
  }
}

/** Confirm SOS replacement booking payment */
export async function confirmSosPayment(
  supabase: ReturnType<typeof createClient>,
  bookingId: string,
  incidentId: string | undefined,
  transactionId: string,
  stripePaymentIntentId?: string | null
) {
  try {
    const updateData: Record<string, any> = {
      payment_status: 'paid',
      payment_method: 'card',
      status: 'active',
      confirmed_at: new Date().toISOString(),
      picked_up_at: new Date().toISOString(),
    }
    if (stripePaymentIntentId) {
      updateData.stripe_payment_intent_id = stripePaymentIntentId
      updateData.stripe_session_id = transactionId
    }
    const { error } = await supabase.from('bookings')
      .update(updateData)
      .eq('id', bookingId)

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'confirm_sos_payment',
        component: 'stripe',
        status: error ? 'error' : 'ok',
        request_data: { booking_id: bookingId, incident_id: incidentId, transaction_id: transactionId },
        error_message: error?.message || null,
      })
    } catch (e) { /* ignore */ }

    if (error) {
      console.error('SOS booking update failed:', error.message)
    }
  } catch (err) {
    console.error('confirmSosPayment error:', err)
  }
}

/** Confirm shop payment via existing RPC */
export async function confirmShopPayment(
  supabase: ReturnType<typeof createClient>,
  orderId: string,
  transactionId: string,
  stripePaymentIntentId?: string | null
) {
  try {
    const { data, error } = await supabase.rpc('confirm_shop_payment', {
      p_order_id: orderId,
      p_method: 'card',
    })

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'confirm_shop_payment',
        component: 'stripe',
        status: error ? 'error' : 'ok',
        request_data: { order_id: orderId, transaction_id: transactionId },
        response_data: data,
        error_message: error?.message || null,
      })
    } catch (e) { /* ignore */ }

    if (error) {
      console.error('confirm_shop_payment RPC failed:', error.message)
      await supabase.from('shop_orders')
        .update({ payment_status: 'paid', payment_method: 'card' })
        .eq('id', orderId)
    }

    if (stripePaymentIntentId) {
      try {
        await supabase.from('shop_orders')
          .update({
            stripe_payment_intent_id: stripePaymentIntentId,
            stripe_session_id: transactionId,
          })
          .eq('id', orderId)
      } catch (e) { /* ignore */ }
    }
  } catch (err) {
    console.error('confirmShopPayment error:', err)
  }
}

/** Idempotent insert into financial_events */
export async function ingestFinancialEvent(
  supabase: ReturnType<typeof createClient>,
  eventData: {
    event_type: string
    source: string
    amount_czk: number
    vat_rate: number
    duzp: string
    linked_entity_type: string | null
    linked_entity_id: string | null
    confidence_score: number
    status: string
    metadata: Record<string, any>
  }
) {
  try {
    const stripeId = eventData.metadata.stripe_payment_intent_id
      || eventData.metadata.stripe_charge_id
      || eventData.metadata.stripe_payout_id

    if (stripeId) {
      const idempotencyKey = eventData.metadata.stripe_payment_intent_id
        ? 'stripe_payment_intent_id'
        : eventData.metadata.stripe_charge_id
          ? 'stripe_charge_id'
          : 'stripe_payout_id'

      const { data: existing } = await supabase
        .from('financial_events')
        .select('id')
        .eq(`metadata->>${idempotencyKey}`, stripeId)
        .maybeSingle()

      if (existing) {
        console.log(`Financial event already exists for ${idempotencyKey}=${stripeId}, skipping`)
        return
      }
    }

    const { error } = await supabase.from('financial_events').insert(eventData)

    if (error) {
      console.error('Failed to insert financial_event:', error.message)
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver',
          action: 'financial_event_insert_failed',
          component: 'stripe',
          status: 'error',
          request_data: eventData,
          error_message: error.message,
        })
      } catch (e) { /* ignore */ }
    }
  } catch (err) {
    console.error('ingestFinancialEvent error:', err)
  }
}
