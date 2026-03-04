/**
 * MotoGo24 — Edge Function: Send Email
 * Odesílání emailů přes šablony z email-templates.ts.
 * Podporuje autentizaci JWT (uživatel/admin) i SERVICE_ROLE_KEY.
 *
 * POST /functions/v1/send-email
 * Auth: Bearer JWT nebo SERVICE_ROLE_KEY
 * Body: { type, recipient_email, data }
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import { getEmailTemplate } from '../_shared/email-templates.ts';
import type { EmailRequest, EmailResponse, EmailTemplateType } from '../_shared/types.ts';

const VALID_TYPES: EmailTemplateType[] = [
  'booking_confirmation',
  'booking_reminder',
  'sos_admin_alert',
  'document_send',
  'password_reset',
  'invoice_send',
];

/** Odešle email přes konfigurovaného providera. */
async function dispatchEmail(
  to: string,
  subject: string,
  html: string,
): Promise<{ success: boolean; message_id?: string }> {
  const apiKey = Deno.env.get('EMAIL_API_KEY') ?? '';
  const emailFrom = Deno.env.get('EMAIL_FROM') ?? 'noreply@motogo24.cz';
  const emailProvider = Deno.env.get('EMAIL_PROVIDER') ?? 'resend';

  if (emailProvider === 'resend') {
    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from: emailFrom, to: [to], subject, html }),
    });

    if (!resp.ok) {
      const errBody = await resp.text();
      throw new Error(`Resend error: ${errBody}`);
    }

    const result = await resp.json() as { id: string };
    return { success: true, message_id: result.id };
  }

  // Mailgun
  const mailgunDomain = Deno.env.get('MAILGUN_DOMAIN') ?? '';
  const resp = await fetch(
    `https://api.mailgun.net/v3/${mailgunDomain}/messages`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${btoa(`api:${apiKey}`)}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ from: emailFrom, to, subject, html }),
    },
  );

  if (!resp.ok) {
    const errBody = await resp.text();
    throw new Error(`Mailgun error: ${errBody}`);
  }

  const result = await resp.json() as { id: string };
  return { success: true, message_id: result.id };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return errorResponse('Missing Authorization header', 401);
    }

    // Ověř autorizaci — buď JWT uživatel, nebo service role key
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const isServiceRole = authHeader === `Bearer ${serviceRoleKey}`;

    if (!isServiceRole) {
      const userClient = getUserClient(authHeader);
      const { data: { user }, error: authError } = await userClient.auth.getUser();
      if (authError || !user) {
        return errorResponse('Unauthorized', 401);
      }
    }

    const body = await req.json() as EmailRequest;

    if (!body.type || !body.recipient_email || !body.data) {
      return errorResponse('Missing required fields: type, recipient_email, data');
    }

    if (!VALID_TYPES.includes(body.type)) {
      return errorResponse(`Invalid email type. Valid types: ${VALID_TYPES.join(', ')}`);
    }

    // Validace email formátu
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(body.recipient_email)) {
      return errorResponse('Invalid recipient_email format');
    }

    // Vygeneruj šablonu
    const template = getEmailTemplate(body.type, body.data);

    // Odešli email
    const result = await dispatchEmail(body.recipient_email, template.subject, template.html);

    // Loguj odeslání
    const admin = getAdminClient();
    await admin.from('notification_log').insert({
      type: 'email',
      template: body.type,
      recipient: body.recipient_email,
      status: result.success ? 'sent' : 'failed',
      metadata: { message_id: result.message_id },
    });

    const response: EmailResponse = {
      success: result.success,
      message_id: result.message_id,
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('send-email error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
