/**
 * MotoGo24 — Edge Function: Send SOS
 * Kritická funkce volaná z mobilní app při SOS incidentu.
 * Odesílá email + SMS administrátorovi, aktualizuje status incidentu.
 *
 * POST /functions/v1/send-sos
 * Auth: Bearer JWT (zákazník)
 * Body: { incident_id: UUID }
 */

import { corsHeaders, corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import { sosAdminAlert } from '../_shared/email-templates.ts';
import type { SendSosRequest, SendSosResponse, SosIncident } from '../_shared/types.ts';

/** Odešle SMS přes konfigurovaného providera (smsbrana.cz nebo Twilio). */
async function sendSms(phone: string, message: string): Promise<boolean> {
  const provider = Deno.env.get('SMS_PROVIDER') ?? 'smsbrana';

  try {
    if (provider === 'twilio') {
      const accountSid = Deno.env.get('TWILIO_ACCOUNT_SID') ?? '';
      const authToken = Deno.env.get('TWILIO_AUTH_TOKEN') ?? '';
      const fromNumber = Deno.env.get('TWILIO_FROM_NUMBER') ?? '';

      const resp = await fetch(
        `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Basic ${btoa(`${accountSid}:${authToken}`)}`,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: new URLSearchParams({
            To: phone,
            From: fromNumber,
            Body: message,
          }),
        },
      );

      if (!resp.ok) {
        const errBody = await resp.text();
        console.error('Twilio SMS error:', errBody);
        return false;
      }
      return true;
    }

    // Default: smsbrana.cz
    const smsLogin = Deno.env.get('SMSBRANA_LOGIN') ?? '';
    const smsPassword = Deno.env.get('SMSBRANA_PASSWORD') ?? '';

    const resp = await fetch('https://http-api.smsconnect.cz/lw/send', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        login: smsLogin,
        password: smsPassword,
        recipient: phone,
        message: message,
      }),
    });

    if (!resp.ok) {
      const errBody = await resp.text();
      console.error('SMS Brana error:', errBody);
      return false;
    }
    return true;
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('SMS send failed:', errorMessage);
    return false;
  }
}

/** Odešle email přes SMTP API (Resend, Mailgun, nebo jiný provider). */
async function sendEmail(
  to: string,
  subject: string,
  html: string,
): Promise<boolean> {
  const apiKey = Deno.env.get('EMAIL_API_KEY') ?? '';
  const emailFrom = Deno.env.get('EMAIL_FROM') ?? 'noreply@motogo24.cz';
  const emailProvider = Deno.env.get('EMAIL_PROVIDER') ?? 'resend';

  try {
    if (emailProvider === 'resend') {
      const resp = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: emailFrom,
          to: [to],
          subject,
          html,
        }),
      });

      if (!resp.ok) {
        const errBody = await resp.text();
        console.error('Resend email error:', errBody);
        return false;
      }
      return true;
    }

    // Mailgun fallback
    const mailgunDomain = Deno.env.get('MAILGUN_DOMAIN') ?? '';
    const resp = await fetch(
      `https://api.mailgun.net/v3/${mailgunDomain}/messages`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${btoa(`api:${apiKey}`)}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          from: emailFrom,
          to,
          subject,
          html,
        }),
      },
    );

    if (!resp.ok) {
      const errBody = await resp.text();
      console.error('Mailgun email error:', errBody);
      return false;
    }
    return true;
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('Email send failed:', errorMessage);
    return false;
  }
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

    // Ověř JWT a získej user_id
    const userClient = getUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return errorResponse('Unauthorized', 401);
    }

    const body = await req.json() as SendSosRequest;
    if (!body.incident_id) {
      return errorResponse('Missing incident_id');
    }

    // Načti incident z DB s JOIN na profiles, motorcycles, bookings
    const admin = getAdminClient();
    const { data: incident, error: fetchError } = await admin
      .from('sos_incidents')
      .select(`
        id, type, latitude, longitude, description, is_fault, status, created_at,
        user_id,
        profiles!inner ( full_name, phone ),
        bookings!inner (
          id,
          motorcycles!inner ( model, license_plate )
        )
      `)
      .eq('id', body.incident_id)
      .eq('user_id', user.id)
      .single();

    if (fetchError || !incident) {
      console.error('Incident fetch error:', fetchError);
      return errorResponse('Incident not found', 404);
    }

    // Bezpečně extrahuj nested data
    const profile = incident.profiles as unknown as { full_name: string; phone: string };
    const booking = incident.bookings as unknown as {
      id: string;
      motorcycles: { model: string; license_plate: string };
    };

    const incidentData: SosIncident = {
      id: incident.id as string,
      user_id: incident.user_id as string,
      booking_id: booking.id,
      type: incident.type as SosIncident['type'],
      latitude: incident.latitude as number,
      longitude: incident.longitude as number,
      description: incident.description as string,
      is_fault: incident.is_fault as boolean,
      status: incident.status as SosIncident['status'],
      created_at: incident.created_at as string,
      customer_name: profile.full_name,
      customer_phone: profile.phone,
      moto_model: booking.motorcycles.model,
      moto_spz: booking.motorcycles.license_plate,
    };

    // Sestav a odešli email administrátorovi
    const adminEmail = Deno.env.get('ADMIN_EMAIL') ?? '';
    const emailTemplate = sosAdminAlert({
      incident_type: incidentData.type,
      customer_name: incidentData.customer_name,
      customer_phone: incidentData.customer_phone,
      moto_model: incidentData.moto_model,
      moto_spz: incidentData.moto_spz,
      latitude: incidentData.latitude,
      longitude: incidentData.longitude,
      description: incidentData.description,
      is_fault: incidentData.is_fault,
      reported_at: new Date(incidentData.created_at).toLocaleString('cs-CZ'),
      incident_id: incidentData.id,
    });

    const emailSent = await sendEmail(adminEmail, emailTemplate.subject, emailTemplate.html);
    if (!emailSent) {
      console.error('SOS email failed for incident:', incidentData.id);
    }

    // Odešli SMS administrátorovi
    const adminPhone = Deno.env.get('ADMIN_PHONE') ?? '';
    const typeLabels: Record<string, string> = {
      accident_minor: 'Drobná nehoda',
      accident_major: 'Vážná nehoda',
      theft: 'Krádež',
      breakdown_minor: 'Drobná porucha',
      breakdown_major: 'Vážná porucha',
      location_share: 'Sdílení polohy',
    };
    const typeLabel = typeLabels[incidentData.type] ?? incidentData.type;
    const mapsUrl = `maps.google.com/?q=${incidentData.latitude},${incidentData.longitude}`;
    const smsMessage = `SOS MotoGo24: ${typeLabel} - ${incidentData.customer_name} - ${incidentData.moto_spz} - ${mapsUrl}`;

    const smsSent = await sendSms(adminPhone, smsMessage);
    if (!smsSent) {
      console.error('SOS SMS failed for incident:', incidentData.id);
    }

    // Update incident status → 'acknowledged'
    const { error: updateError } = await admin
      .from('sos_incidents')
      .update({ status: 'acknowledged' })
      .eq('id', body.incident_id);

    if (updateError) {
      console.error('Incident status update error:', updateError);
    }

    // Přidej záznam do sos_timeline
    const { error: timelineError } = await admin
      .from('sos_timeline')
      .insert({
        incident_id: body.incident_id,
        action: 'acknowledged',
        note: `Automatická notifikace odeslána (email: ${emailSent ? 'OK' : 'FAIL'}, SMS: ${smsSent ? 'OK' : 'FAIL'})`,
        performed_by: user.id,
      });

    if (timelineError) {
      console.error('Timeline insert error:', timelineError);
    }

    const response: SendSosResponse = { success: true };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('send-sos error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
