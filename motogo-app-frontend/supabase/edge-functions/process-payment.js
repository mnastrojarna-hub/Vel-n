// ===== MotoGo24 – Edge Function: Process Payment =====
// Simulates payment processing with 90% success rate.
// Deploy to Supabase Edge Functions.
// Endpoint: POST /functions/v1/process-payment
// Body: { booking_id, amount, method }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { booking_id, amount, method } = await req.json();

    if (!booking_id || !amount) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing booking_id or amount' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Simulate payment processing delay (1 second)
    await new Promise((resolve) => setTimeout(resolve, 1000));

    // Simulated gateway – always succeeds (real Stripe integration will replace this)
    const success = true;
    const transactionId = 'TXN-' + Date.now() + '-' + Math.random().toString(36).substr(2, 6).toUpperCase();

    // Update booking: payment status + proper status transition
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Fetch booking to determine target status
    const { data: booking, error: fetchError } = await supabase
      .from('bookings')
      .select('start_date, status, confirmed_at, picked_up_at')
      .eq('id', booking_id)
      .single();

    if (fetchError || !booking) {
      return new Response(
        JSON.stringify({ success: false, error: 'Booking not found: ' + (fetchError?.message || 'unknown') }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Determine new status: active if rental starts today or earlier, reserved if future
    let newStatus = booking.status;
    if (booking.status === 'pending') {
      const startDate = new Date(booking.start_date);
      startDate.setHours(0, 0, 0, 0);
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      newStatus = startDate <= today ? 'active' : 'reserved';
    }

    const updateData = {
      payment_status: 'paid',
      payment_method: method || 'card',
      status: newStatus
    };
    if (!booking.confirmed_at && booking.status === 'pending') {
      updateData.confirmed_at = new Date().toISOString();
    }
    if (newStatus === 'active' && !booking.picked_up_at) {
      updateData.picked_up_at = new Date().toISOString();
    }

    const { error: updateError } = await supabase
      .from('bookings')
      .update(updateData)
      .eq('id', booking_id);

    if (updateError) {
      console.error('DB update error:', updateError);
    }

    const response = {
      success,
      transaction_id: transactionId,
      amount,
      method: method || 'card',
      processed_at: new Date().toISOString(),
      error: null
    };

    return new Response(
      JSON.stringify(response),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error: ' + err.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
