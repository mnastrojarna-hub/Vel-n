import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'
const SITE_URL = Deno.env.get('SITE_URL') || 'https://motogo24.cz'

const SOURCE_LABELS: Record<string, string> = {
  velin: 'administrátorem',
  web: 'vámi přes web',
  app: 'vámi přes aplikaci',
  system: 'automaticky systémem (nezaplacení do 4 hodin)',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    })
  }

  try {
    const {
      booking_id,
      customer_email,
      customer_name,
      motorcycle,
      start_date,
      end_date,
      cancellation_reason,
      cancelled_by_source,
    } = await req.json()

    if (!customer_email) {
      return new Response(JSON.stringify({ error: 'No customer email' }), { status: 400 })
    }

    const sourceText = SOURCE_LABELS[cancelled_by_source] || cancelled_by_source || 'neznámo'
    const restoreUrl = `${SITE_URL}/rezervace/obnovit/${booking_id}`

    const html = `
<!DOCTYPE html>
<html lang="cs">
<head><meta charset="UTF-8"></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f4f7f5; padding: 32px;">
  <div style="max-width: 560px; margin: 0 auto; background: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 24px rgba(0,0,0,.08);">
    <div style="background: #1a2e22; padding: 28px 32px; text-align: center;">
      <h1 style="margin: 0; color: #74FB71; font-size: 22px; font-weight: 900;">MOTO GO 24</h1>
    </div>
    <div style="padding: 32px;">
      <h2 style="color: #dc2626; font-size: 18px; margin-top: 0;">Vaše rezervace byla zrušena</h2>
      <p style="color: #374151; line-height: 1.6;">
        Dobrý den${customer_name ? ` ${customer_name}` : ''},
      </p>
      <p style="color: #374151; line-height: 1.6;">
        Vaše rezervace byla zrušena <strong>${sourceText}</strong>.
      </p>

      <div style="background: #fef2f2; border: 1px solid #fecaca; border-radius: 12px; padding: 16px; margin: 20px 0;">
        <table style="width: 100%; border-collapse: collapse; font-size: 14px; color: #374151;">
          <tr><td style="padding: 4px 0; font-weight: 700;">Motorka:</td><td>${motorcycle || '—'}</td></tr>
          <tr><td style="padding: 4px 0; font-weight: 700;">Termín:</td><td>${start_date || '—'} — ${end_date || '—'}</td></tr>
          <tr><td style="padding: 4px 0; font-weight: 700;">Důvod:</td><td>${cancellation_reason || 'Neuvedeno'}</td></tr>
        </table>
      </div>

      <p style="color: #374151; line-height: 1.6;">
        Pokud si přejete rezervaci obnovit, klikněte na tlačítko níže:
      </p>

      <div style="text-align: center; margin: 28px 0;">
        <a href="${restoreUrl}" style="display: inline-block; background: #74FB71; color: #1a2e22; padding: 14px 36px; border-radius: 12px; text-decoration: none; font-weight: 800; font-size: 15px; box-shadow: 0 4px 16px rgba(116,251,113,.35);">
          Obnovit rezervaci
        </a>
      </div>

      <p style="color: #6b7280; font-size: 13px; line-height: 1.5;">
        Pokud máte jakékoli dotazy, neváhejte nás kontaktovat na
        <a href="mailto:info@motogo24.cz" style="color: #2563eb;">info@motogo24.cz</a>
        nebo volejte na naši zákaznickou linku.
      </p>
    </div>
    <div style="background: #f9fafb; padding: 16px 32px; text-align: center; border-top: 1px solid #e5e7eb;">
      <p style="color: #9ca3af; font-size: 11px; margin: 0;">
        MOTO GO 24 — Pronájem motorek po celé ČR
      </p>
    </div>
  </div>
</body>
</html>`

    // Send via Resend API
    const emailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: customer_email,
        subject: `Vaše rezervace byla zrušena — MOTO GO 24`,
        html,
      }),
    })

    if (!emailRes.ok) {
      const errBody = await emailRes.text()
      console.error('Resend error:', errBody)
      return new Response(JSON.stringify({ error: 'Email send failed', details: errBody }), { status: 500 })
    }

    // Mark booking as notified
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    await supabase.from('bookings').update({ cancellation_notified: true }).eq('id', booking_id)

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Error:', err)
    return new Response(JSON.stringify({ error: err.message }), { status: 500 })
  }
})
