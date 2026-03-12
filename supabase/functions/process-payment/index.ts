// ===== MotoGo24 – Edge Function: Process Payment =====
// Simulated payment gateway (DEV). Real Stripe integration will replace this.
// Endpoint: POST /functions/v1/process-payment
// Body: { booking_id, amount, method }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

interface PaymentRequest {
  booking_id: string
  amount: number
  method?: string
}

interface BookingRow {
  start_date: string
  status: string
  confirmed_at: string | null
  picked_up_at: string | null
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  try {
    const { booking_id, amount, method }: PaymentRequest = await req.json()

    if (!booking_id || amount == null) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing booking_id or amount' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Simulate payment processing delay
    await new Promise((resolve) => setTimeout(resolve, 1000))

    const transactionId = 'TXN-' + Date.now() + '-' + Math.random().toString(36).substr(2, 6).toUpperCase()

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Fetch booking to determine target status
    const { data: booking, error: fetchError } = await supabase
      .from('bookings')
      .select('start_date, status, confirmed_at, picked_up_at')
      .eq('id', booking_id)
      .single<BookingRow>()

    if (fetchError || !booking) {
      return new Response(
        JSON.stringify({ success: false, error: 'Booking not found: ' + (fetchError?.message || 'unknown') }),
        { status: 404, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Determine new status: active if rental starts today or earlier, reserved if future
    let newStatus = booking.status
    if (booking.status === 'pending') {
      const startDate = new Date(booking.start_date)
      startDate.setHours(0, 0, 0, 0)
      const today = new Date()
      today.setHours(0, 0, 0, 0)
      newStatus = startDate <= today ? 'active' : 'reserved'
    }

    const updateData: Record<string, unknown> = {
      payment_status: 'paid',
      payment_method: method || 'card',
      status: newStatus,
    }
    if (!booking.confirmed_at && booking.status === 'pending') {
      updateData.confirmed_at = new Date().toISOString()
    }
    if (newStatus === 'active' && !booking.picked_up_at) {
      updateData.picked_up_at = new Date().toISOString()
    }

    const { error: updateError } = await supabase
      .from('bookings')
      .update(updateData)
      .eq('id', booking_id)

    if (updateError) {
      console.error('DB update error:', updateError)
      // Zkus minimální update (jen payment_status) — obejde potenciální trigger problém
      const { error: minError } = await supabase
        .from('bookings')
        .update({ payment_status: 'paid', payment_method: method || 'card' })
        .eq('id', booking_id)

      if (!minError) {
        // Druhý update pro status (separátně)
        await supabase
          .from('bookings')
          .update({
            status: newStatus,
            ...(updateData.confirmed_at ? { confirmed_at: updateData.confirmed_at } : {}),
            ...(updateData.picked_up_at ? { picked_up_at: updateData.picked_up_at } : {}),
          })
          .eq('id', booking_id)
      } else {
        console.error('Minimal DB update also failed:', minError)
        return new Response(
          JSON.stringify({
            success: false,
            error: 'DB update failed: ' + updateError.message,
            transaction_id: transactionId,
          }),
          { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        transaction_id: transactionId,
        amount,
        method: method || 'card',
        processed_at: new Date().toISOString(),
        error: null,
      }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error: ' + (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})
