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

    // Simulate payment processing delay (2 seconds)
    await new Promise((resolve) => setTimeout(resolve, 2000));

    // 90% success rate
    const success = Math.random() < 0.9;
    const transactionId = success ? 'TXN-' + Date.now() + '-' + Math.random().toString(36).substr(2, 6).toUpperCase() : null;

    if (success) {
      // Update booking payment status in database
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      );

      const { error: updateError } = await supabase
        .from('bookings')
        .update({
          payment_status: 'paid',
          payment_method: method || 'card'
        })
        .eq('id', booking_id);

      if (updateError) {
        console.error('DB update error:', updateError);
      }
    }

    const response = {
      success,
      transaction_id: transactionId,
      amount,
      method: method || 'card',
      processed_at: new Date().toISOString(),
      error: success ? null : 'Payment declined by processor. Please try again or use a different payment method.'
    };

    return new Response(
      JSON.stringify(response),
      {
        status: success ? 200 : 402,
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
