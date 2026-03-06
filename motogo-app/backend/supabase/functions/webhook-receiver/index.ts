/**
 * MotoGo24 — Edge Function: Webhook Receiver
 * Router pro příchozí webhooky z externích služeb (Stripe, WhatsApp, Instagram).
 *
 * POST /functions/v1/webhook-receiver?source=stripe|whatsapp|instagram
 */

import { corsHeaders, corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/supabase-client.ts';
import type { WebhookSource, WebhookResponse } from '../_shared/types.ts';

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

/** Zpracuje Stripe webhook event. */
async function handleStripeWebhook(
  admin: ReturnType<typeof getAdminClient>,
  rawBody: string,
  headers: Headers,
): Promise<WebhookResponse> {
  const signature = headers.get('stripe-signature') ?? '';
  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '';

  const isValid = await verifyStripeSignature(rawBody, signature, webhookSecret);
  if (!isValid) {
    return { success: false, processed: false, error: 'Invalid Stripe signature' };
  }

  const event = JSON.parse(rawBody) as { id: string; type: string; data: { object: Record<string, unknown> } };

  // Kontrola duplicitních eventů
  const { data: existing } = await admin
    .from('webhook_events')
    .select('id')
    .eq('event_id', event.id)
    .maybeSingle();

  if (existing) {
    return { success: true, processed: false, error: 'Event already processed' };
  }

  // Ulož event
  await admin.from('webhook_events').insert({
    event_id: event.id,
    source: 'stripe',
    event_type: event.type,
    payload: event,
    processed: false,
  });

  // Zpracuj event
  switch (event.type) {
    case 'checkout.session.completed': {
      const session = event.data.object;
      const bookingId = (session.metadata as Record<string, string>)?.booking_id;
      if (bookingId) {
        // Přesměruj na process-payment endpoint
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
        const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

        await fetch(`${supabaseUrl}/functions/v1/process-payment?webhook=true`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${serviceRoleKey}`,
            'Content-Type': 'application/json',
            'stripe-signature': signature,
          },
          body: rawBody,
        });
      }
      break;
    }

    case 'payment_intent.payment_failed': {
      const intent = event.data.object;
      console.error('Payment failed:', intent.id);
      break;
    }

    case 'charge.refunded': {
      const charge = event.data.object;
      const bookingId = (charge.metadata as Record<string, string>)?.booking_id;
      if (bookingId) {
        await admin
          .from('bookings')
          .update({ payment_status: 'refunded' })
          .eq('id', bookingId);
      }
      break;
    }
  }

  // Označ event jako zpracovaný
  await admin
    .from('webhook_events')
    .update({ processed: true, processed_at: new Date().toISOString() })
    .eq('event_id', event.id);

  return { success: true, processed: true };
}

/** Zpracuje WhatsApp webhook. */
async function handleWhatsAppWebhook(
  admin: ReturnType<typeof getAdminClient>,
  rawBody: string,
): Promise<WebhookResponse> {
  const data = JSON.parse(rawBody) as {
    entry?: Array<{
      changes?: Array<{
        value?: {
          messages?: Array<{
            id: string;
            from: string;
            timestamp: string;
            type: string;
            text?: { body: string };
          }>;
          contacts?: Array<{
            wa_id: string;
            profile: { name: string };
          }>;
        };
      }>;
    }>;
  };

  const entries = data.entry ?? [];
  let processedCount = 0;

  for (const entry of entries) {
    for (const change of entry.changes ?? []) {
      const messages = change.value?.messages ?? [];
      const contacts = change.value?.contacts ?? [];

      for (const message of messages) {
        // Kontrola duplicity
        const { data: existing } = await admin
          .from('webhook_events')
          .select('id')
          .eq('event_id', `wa_${message.id}`)
          .maybeSingle();

        if (existing) continue;

        // Ulož event
        await admin.from('webhook_events').insert({
          event_id: `wa_${message.id}`,
          source: 'whatsapp',
          event_type: 'message',
          payload: { message, contacts },
          processed: false,
        });

        const senderPhone = message.from;
        const senderName = contacts.find((c) => c.wa_id === senderPhone)?.profile.name ?? senderPhone;
        const messageText = message.text?.body ?? '';

        // Najdi nebo vytvoř message_thread
        let threadId: string;
        const { data: existingThread } = await admin
          .from('message_threads')
          .select('id')
          .eq('channel', 'whatsapp')
          .eq('external_id', senderPhone)
          .maybeSingle();

        if (existingThread) {
          threadId = existingThread.id as string;
          await admin
            .from('message_threads')
            .update({
              last_message_at: new Date().toISOString(),
              unread_count: (existingThread as Record<string, unknown>).unread_count as number + 1,
            })
            .eq('id', threadId);
        } else {
          const { data: newThread } = await admin
            .from('message_threads')
            .insert({
              channel: 'whatsapp',
              external_id: senderPhone,
              contact_name: senderName,
              contact_phone: senderPhone,
              status: 'open',
              last_message_at: new Date().toISOString(),
              unread_count: 1,
            })
            .select('id')
            .single();
          threadId = newThread?.id as string;
        }

        // Ulož zprávu
        await admin.from('messages').insert({
          thread_id: threadId,
          direction: 'inbound',
          channel: 'whatsapp',
          content: messageText,
          sender_name: senderName,
          sender_phone: senderPhone,
          external_id: message.id,
          received_at: new Date(Number(message.timestamp) * 1000).toISOString(),
        });

        // Označ event jako zpracovaný
        await admin
          .from('webhook_events')
          .update({ processed: true, processed_at: new Date().toISOString() })
          .eq('event_id', `wa_${message.id}`);

        processedCount++;
      }
    }
  }

  return { success: true, processed: processedCount > 0 };
}

/** Zpracuje Instagram DM webhook. */
async function handleInstagramWebhook(
  admin: ReturnType<typeof getAdminClient>,
  rawBody: string,
): Promise<WebhookResponse> {
  const data = JSON.parse(rawBody) as {
    entry?: Array<{
      messaging?: Array<{
        sender: { id: string };
        recipient: { id: string };
        timestamp: number;
        message?: {
          mid: string;
          text: string;
        };
      }>;
    }>;
  };

  const entries = data.entry ?? [];
  let processedCount = 0;

  for (const entry of entries) {
    for (const messaging of entry.messaging ?? []) {
      if (!messaging.message) continue;

      const messageId = messaging.message.mid;

      // Kontrola duplicity
      const { data: existing } = await admin
        .from('webhook_events')
        .select('id')
        .eq('event_id', `ig_${messageId}`)
        .maybeSingle();

      if (existing) continue;

      // Ulož event
      await admin.from('webhook_events').insert({
        event_id: `ig_${messageId}`,
        source: 'instagram',
        event_type: 'message',
        payload: messaging,
        processed: false,
      });

      const senderId = messaging.sender.id;
      const messageText = messaging.message.text;

      // Najdi nebo vytvoř message_thread
      let threadId: string;
      const { data: existingThread } = await admin
        .from('message_threads')
        .select('id')
        .eq('channel', 'instagram')
        .eq('external_id', senderId)
        .maybeSingle();

      if (existingThread) {
        threadId = existingThread.id as string;
        await admin
          .from('message_threads')
          .update({
            last_message_at: new Date().toISOString(),
            unread_count: (existingThread as Record<string, unknown>).unread_count as number + 1,
          })
          .eq('id', threadId);
      } else {
        const { data: newThread } = await admin
          .from('message_threads')
          .insert({
            channel: 'instagram',
            external_id: senderId,
            contact_name: `IG User ${senderId}`,
            status: 'open',
            last_message_at: new Date().toISOString(),
            unread_count: 1,
          })
          .select('id')
          .single();
        threadId = newThread?.id as string;
      }

      // Ulož zprávu
      await admin.from('messages').insert({
        thread_id: threadId,
        direction: 'inbound',
        channel: 'instagram',
        content: messageText,
        sender_name: `IG User ${senderId}`,
        external_id: messageId,
        received_at: new Date(messaging.timestamp).toISOString(),
      });

      // Označ event jako zpracovaný
      await admin
        .from('webhook_events')
        .update({ processed: true, processed_at: new Date().toISOString() })
        .eq('event_id', `ig_${messageId}`);

      processedCount++;
    }
  }

  return { success: true, processed: processedCount > 0 };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  // WhatsApp verification challenge (GET request)
  if (req.method === 'GET') {
    const url = new URL(req.url);
    const mode = url.searchParams.get('hub.mode');
    const token = url.searchParams.get('hub.verify_token');
    const challenge = url.searchParams.get('hub.challenge');

    if (mode === 'subscribe' && token === Deno.env.get('WHATSAPP_VERIFY_TOKEN')) {
      return new Response(challenge ?? '', { status: 200, headers: corsHeaders });
    }
    return errorResponse('Verification failed', 403);
  }

  try {
    const url = new URL(req.url);
    const source = url.searchParams.get('source') as WebhookSource | null;

    if (!source || !['stripe', 'whatsapp', 'instagram'].includes(source)) {
      return errorResponse('Missing or invalid source query parameter. Valid: stripe, whatsapp, instagram');
    }

    const admin = getAdminClient();
    const rawBody = await req.text();
    let result: WebhookResponse;

    switch (source) {
      case 'stripe':
        result = await handleStripeWebhook(admin, rawBody, req.headers);
        break;
      case 'whatsapp':
        result = await handleWhatsAppWebhook(admin, rawBody);
        break;
      case 'instagram':
        result = await handleInstagramWebhook(admin, rawBody);
        break;
      default:
        return errorResponse('Unknown webhook source');
    }

    return jsonResponse(result, result.success ? 200 : 400);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('webhook-receiver error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
