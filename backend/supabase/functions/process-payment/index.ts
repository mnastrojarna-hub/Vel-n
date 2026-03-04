/**
 * MotoGo24 — Edge Function: Process Payment
 * Zpracování plateb kartou (Stripe Checkout), hotovostí, nebo převodem.
 * Stripe webhook pro automatické potvrzení platby.
 *
 * POST /functions/v1/process-payment
 * Body: { booking_id, amount, method: 'card'|'cash'|'transfer' }
 *
 * POST /functions/v1/process-payment (webhook path via query ?webhook=true)
 * Body: Stripe webhook event
 */

import { corsHeaders, corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import { bookingConfirmation } from '../_shared/email-templates.ts';
import type { PaymentRequest, PaymentResponse, StripeWebhookEvent } from '../_shared/types.ts';

/** Vytvoří Stripe Checkout Session. */
async function createStripeCheckout(
  bookingId: string,
  amount: number,
  customerEmail: string,
): Promise<{ url: string; session_id: string }> {
  const stripeKey = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
  const successUrl = Deno.env.get('PAYMENT_SUCCESS_URL') ?? 'https://motogo24.cz/payment/success';
  const cancelUrl = Deno.env.get('PAYMENT_CANCEL_URL') ?? 'https://motogo24.cz/payment/cancel';

  const resp = await fetch('https://api.stripe.com/v1/checkout/sessions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${stripeKey}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      'mode': 'payment',
      'success_url': `${successUrl}?session_id={CHECKOUT_SESSION_ID}`,
      'cancel_url': cancelUrl,
      'customer_email': customerEmail,
      'metadata[booking_id]': bookingId,
      'line_items[0][price_data][currency]': 'czk',
      'line_items[0][price_data][product_data][name]': `MotoGo24 — Rezervace ${bookingId.substring(0, 8)}`,
      'line_items[0][price_data][unit_amount]': String(Math.round(amount * 100)),
      'line_items[0][quantity]': '1',
    }),
  });

  if (!resp.ok) {
    const errBody = await resp.text();
    throw new Error(`Stripe error: ${errBody}`);
  }

  const session = await resp.json() as { url: string; id: string };
  return { url: session.url, session_id: session.id };
}

/** Ověří Stripe webhook signature. */
async function verifyStripeSignature(
  body: string,
  signature: string,
  secret: string,
): Promise<boolean> {
  const parts = signature.split(',');
  const timestampPart = parts.find((p) => p.startsWith('t='));
  const signaturePart = parts.find((p) => p.startsWith('v1='));

  if (!timestampPart || !signaturePart) return false;

  const timestamp = timestampPart.substring(2);
  const expectedSig = signaturePart.substring(3);

  const payload = `${timestamp}.${body}`;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signed = await crypto.subtle.sign('HMAC', key, encoder.encode(payload));
  const computedSig = Array.from(new Uint8Array(signed))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  return computedSig === expectedSig;
}

/** Zpracuje úspěšnou platbu — aktualizuje DB, vytvoří účetní záznam, odešle email. */
async function handleSuccessfulPayment(
  bookingId: string,
  amount: number,
  method: string,
  transactionId: string,
): Promise<void> {
  const admin = getAdminClient();

  // Update booking payment status
  const { error: updateError } = await admin
    .from('bookings')
    .update({
      payment_status: 'paid',
      payment_method: method,
    })
    .eq('id', bookingId);

  if (updateError) {
    console.error('Booking update error:', updateError);
    throw updateError;
  }

  // Načti booking data pro accounting entry a email
  const { data: booking, error: fetchError } = await admin
    .from('bookings')
    .select(`
      id, start_date, end_date, total_price, user_id,
      profiles!inner ( full_name, email ),
      motorcycles!inner ( model, license_plate, branch_id,
        branches!inner ( name, address )
      )
    `)
    .eq('id', bookingId)
    .single();

  if (fetchError || !booking) {
    console.error('Booking fetch for payment processing error:', fetchError);
    return;
  }

  const profile = booking.profiles as unknown as { full_name: string; email: string };
  const moto = booking.motorcycles as unknown as {
    model: string;
    license_plate: string;
    branch_id: string;
    branches: { name: string; address: string };
  };

  // Vytvoř accounting_entry (příjem za pronájem)
  const { error: accountingError } = await admin
    .from('accounting_entries')
    .insert({
      type: 'income',
      amount: amount,
      category: 'pronájem',
      description: `Platba za rezervaci ${bookingId.substring(0, 8)} — ${moto.model}`,
      reference_type: 'booking',
      reference_id: bookingId,
      branch_id: moto.branch_id,
      date: new Date().toISOString().split('T')[0],
      payment_method: method,
      transaction_id: transactionId,
    });

  if (accountingError) {
    console.error('Accounting entry error:', accountingError);
  }

  // Odešli potvrzovací email
  const emailTemplate = bookingConfirmation({
    customer_name: profile.full_name,
    moto_model: moto.model,
    moto_spz: moto.license_plate,
    start_date: booking.start_date as string,
    end_date: booking.end_date as string,
    total_price: amount,
    branch_name: moto.branches.name,
    branch_address: moto.branches.address,
    booking_id: bookingId.substring(0, 8).toUpperCase(),
  });

  const apiKey = Deno.env.get('EMAIL_API_KEY') ?? '';
  const emailFrom = Deno.env.get('EMAIL_FROM') ?? 'noreply@motogo24.cz';

  try {
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: emailFrom,
        to: [profile.email],
        subject: emailTemplate.subject,
        html: emailTemplate.html,
      }),
    });
  } catch (emailErr: unknown) {
    const msg = emailErr instanceof Error ? emailErr.message : String(emailErr);
    console.error('Confirmation email failed:', msg);
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    const url = new URL(req.url);
    const isWebhook = url.searchParams.get('webhook') === 'true';

    // ─── Stripe Webhook Handler ────────────────────────
    if (isWebhook) {
      const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '';
      const signature = req.headers.get('stripe-signature') ?? '';
      const rawBody = await req.text();

      const isValid = await verifyStripeSignature(rawBody, signature, webhookSecret);
      if (!isValid) {
        console.error('Invalid Stripe webhook signature');
        return errorResponse('Invalid signature', 401);
      }

      const event = JSON.parse(rawBody) as StripeWebhookEvent;

      // Kontrola duplicitních eventů
      const admin = getAdminClient();
      const { data: existingEvent } = await admin
        .from('webhook_events')
        .select('id')
        .eq('event_id', event.id)
        .maybeSingle();

      if (existingEvent) {
        return jsonResponse({ success: true, message: 'Event already processed' });
      }

      // Ulož event pro idempotenci
      await admin
        .from('webhook_events')
        .insert({ event_id: event.id, source: 'stripe', payload: event });

      if (event.type === 'checkout.session.completed') {
        const session = event.data.object;
        const bookingId = session.metadata.booking_id;
        const amount = (session.amount_total ?? 0) / 100;

        await handleSuccessfulPayment(bookingId, amount, 'card', session.id);
      }

      return jsonResponse({ success: true });
    }

    // ─── Standard Payment Request ──────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return errorResponse('Missing Authorization header', 401);
    }

    const userClient = getUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return errorResponse('Unauthorized', 401);
    }

    const body = await req.json() as PaymentRequest;
    if (!body.booking_id || !body.amount) {
      return errorResponse('Missing booking_id or amount');
    }

    const method = body.method ?? 'card';

    // Ověř že booking patří uživateli
    const admin = getAdminClient();
    const { data: booking, error: bookingError } = await admin
      .from('bookings')
      .select('id, user_id, payment_status, total_price, profiles!inner(email)')
      .eq('id', body.booking_id)
      .single();

    if (bookingError || !booking) {
      return errorResponse('Booking not found', 404);
    }

    if (booking.user_id !== user.id) {
      return errorResponse('Unauthorized — booking does not belong to user', 403);
    }

    if (booking.payment_status === 'paid') {
      return errorResponse('Booking is already paid');
    }

    // Pro platbu kartou → Stripe Checkout
    if (method === 'card') {
      const profile = booking.profiles as unknown as { email: string };
      const checkout = await createStripeCheckout(
        body.booking_id,
        body.amount,
        profile.email,
      );

      const response: PaymentResponse = {
        success: true,
        checkout_url: checkout.url,
        amount: body.amount,
        method: 'card',
        processed_at: new Date().toISOString(),
      };
      return jsonResponse(response);
    }

    // Pro hotovost / převod → rovnou update
    const transactionId = `TXN-${Date.now()}-${crypto.randomUUID().substring(0, 6).toUpperCase()}`;
    await handleSuccessfulPayment(body.booking_id, body.amount, method, transactionId);

    const response: PaymentResponse = {
      success: true,
      transaction_id: transactionId,
      amount: body.amount,
      method,
      processed_at: new Date().toISOString(),
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('process-payment error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
