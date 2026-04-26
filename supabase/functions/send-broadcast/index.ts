import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const RATE_LIMIT_MS = 100 // 10 msgs/sec max
const FAILURE_THRESHOLD = 0.2 // stop if > 20% fail

/** Replace {{var}} placeholders in template */
function renderTemplate(template: string, vars: Record<string, string>): string {
  if (!template) return ''
  let result = template
  for (const [key, val] of Object.entries(vars)) {
    result = result.replaceAll(`{{${key}}}`, val || '')
  }
  return result
}

/** Send email via Resend with retry */
async function sendEmail(to: string, subject: string, html: string): Promise<boolean> {
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': 'Bearer ' + RESEND_API_KEY,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ from: FROM_EMAIL, to, subject, html }),
      })
      if (res.ok) return true
      if (attempt === 3) {
        const errBody = await res.text()
        console.error(`Email to ${to} failed: ${res.status} ${errBody}`)
        return false
      }
    } catch (e) {
      if (attempt === 3) {
        console.error(`Email to ${to} error:`, e)
        return false
      }
    }
    await new Promise(r => setTimeout(r, 1000 * Math.pow(2, attempt)))
  }
  return false
}

/** Send SMS/WA via send-message edge function (internal call) */
async function sendSmsOrWa(
  channel: string,
  to: string,
  body: string,
  customerId: string,
  campaignId: string,
  templateSlug?: string,
  templateVars?: Record<string, string>,
): Promise<boolean> {
  try {
    const sendMessageUrl = `${SUPABASE_URL}/functions/v1/send-message`
    const res = await fetch(sendMessageUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        channel,
        to,
        raw_body: body,
        customer_id: customerId,
        template_slug: templateSlug || undefined,
        template_vars: templateVars || undefined,
      }),
    })
    if (res.ok) {
      const data = await res.json()
      return data.success === true
    }
    const errText = await res.text()
    console.error(`send-message ${channel} to ${to} failed: ${res.status} ${errText}`)
    return false
  } catch (e) {
    console.error(`${channel} to ${to} error:`, e)
    return false
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  try {
    const { campaign_id } = await req.json()
    if (!campaign_id) {
      return new Response(JSON.stringify({ error: 'Missing campaign_id' }), {
        status: 400,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // 1. Load campaign
    const { data: campaign, error: campErr } = await supabase
      .from('broadcast_campaigns')
      .select('*, message_templates(name, slug, body_template, subject_template, wa_template_id)')
      .eq('id', campaign_id)
      .in('status', ['draft', 'scheduled'])
      .single()

    if (campErr || !campaign) {
      return new Response(JSON.stringify({ error: 'Campaign not found or not in draft/scheduled status' }), {
        status: 404,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // 2. Mark as sending
    await supabase
      .from('broadcast_campaigns')
      .update({ status: 'sending' })
      .eq('id', campaign_id)

    const channel = campaign.channel as string
    const segment = campaign.segment as string
    const templateVars = (campaign.template_vars || {}) as Record<string, string>
    const template = campaign.message_templates
    const bodyTemplate = template?.body_template || ''
    const subjectTemplate = template?.subject_template || ''
    const templateSlug = template?.slug || template?.name || ''
    const contactField = channel === 'email' ? 'email' : 'phone'

    // 3. Load recipients based on segment
    let query = supabase
      .from('profiles')
      .select('id, full_name, email, phone')
      .eq('marketing_consent', true)
      .not(contactField, 'is', null)

    if (segment === 'vip') {
      query = query.or('reliability_score->>score.gt.80')
    } else if (segment === 'past_customers') {
      const { data: bookingUsers } = await supabase
        .from('bookings')
        .select('user_id')
        .eq('status', 'completed')
      const ids = [...new Set((bookingUsers || []).map((b: { user_id: string }) => b.user_id))].filter(Boolean)
      if (ids.length === 0) {
        await supabase.from('broadcast_campaigns').update({
          status: 'completed',
          completed_at: new Date().toISOString(),
          total_recipients: 0,
          sent_count: 0,
          failed_count: 0,
        }).eq('id', campaign_id)
        return new Response(JSON.stringify({ success: true, sent: 0, failed: 0 }), {
          headers: { ...CORS, 'Content-Type': 'application/json' },
        })
      }
      query = query.in('id', ids)
    } else if (segment === 'new_no_booking') {
      const { data: allBookingUsers } = await supabase
        .from('bookings')
        .select('user_id')
      const ids = [...new Set((allBookingUsers || []).map((b: { user_id: string }) => b.user_id))].filter(Boolean)
      if (ids.length > 0) {
        query = query.not('id', 'in', `(${ids.join(',')})`)
      }
    }
    // segment === 'all' → no extra filter

    const { data: recipients, error: recipErr } = await query
    if (recipErr) throw recipErr

    const allRecipients = recipients || []
    const totalCount = allRecipients.length

    // Update total_recipients
    await supabase
      .from('broadcast_campaigns')
      .update({ total_recipients: totalCount })
      .eq('id', campaign_id)

    if (totalCount === 0) {
      await supabase.from('broadcast_campaigns').update({
        status: 'completed',
        completed_at: new Date().toISOString(),
        sent_count: 0,
        failed_count: 0,
      }).eq('id', campaign_id)
      return new Response(JSON.stringify({ success: true, sent: 0, failed: 0 }), {
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // 4. Send to each recipient
    let sentCount = 0
    let failedCount = 0

    for (const recipient of allRecipients) {
      // Check if campaign was cancelled mid-send
      if ((sentCount + failedCount) % 50 === 0 && (sentCount + failedCount) > 0) {
        const { data: check } = await supabase
          .from('broadcast_campaigns')
          .select('status')
          .eq('id', campaign_id)
          .single()
        if (check?.status === 'cancelled') {
          console.log(`Campaign ${campaign_id} cancelled mid-send`)
          break
        }
      }

      // Per-recipient template vars (can include customer name)
      const perRecipientVars: Record<string, string> = {
        ...templateVars,
        customer_name: recipient.full_name || '',
        first_name: (recipient.full_name || '').split(' ')[0] || '',
      }

      const renderedBody = renderTemplate(bodyTemplate, perRecipientVars)
      const renderedSubject = renderTemplate(subjectTemplate || 'Novinka od MOTO GO 24', perRecipientVars)

      let success = false

      if (channel === 'email') {
        // Wrap in branded HTML
        const html = buildMarketingHtml(renderedBody, renderedSubject)
        success = await sendEmail(recipient.email, renderedSubject, html)

        // Log to message_log
        try {
          await supabase.from('message_log').insert({
            channel: 'email',
            recipient_email: recipient.email,
            body: renderedBody,
            status: success ? 'sent' : 'failed',
            direction: 'outbound',
            is_marketing: true,
            template_slug: templateSlug,
            metadata: { campaign_id },
            customer_id: recipient.id,
          })
        } catch (e) { /* ignore */ }
      } else {
        // SMS or WhatsApp
        success = await sendSmsOrWa(
          channel,
          recipient.phone,
          renderedBody,
          recipient.id,
          campaign_id,
          templateSlug,
          perRecipientVars,
        )
      }

      if (success) {
        sentCount++
      } else {
        failedCount++
      }

      // Update counts every 10 messages
      if ((sentCount + failedCount) % 10 === 0) {
        await supabase.from('broadcast_campaigns').update({
          sent_count: sentCount,
          failed_count: failedCount,
        }).eq('id', campaign_id)
      }

      // Check failure threshold — stop if > 20% failed (after at least 10 sent)
      const processed = sentCount + failedCount
      if (processed >= 10 && failedCount / processed > FAILURE_THRESHOLD) {
        console.error(`Campaign ${campaign_id} cancelled: failure rate ${(failedCount / processed * 100).toFixed(1)}% exceeds ${FAILURE_THRESHOLD * 100}%`)

        await supabase.from('broadcast_campaigns').update({
          status: 'cancelled',
          sent_count: sentCount,
          failed_count: failedCount,
          completed_at: new Date().toISOString(),
        }).eq('id', campaign_id)

        // Notify admin
        try {
          await supabase.from('admin_messages').insert({
            type: 'info',
            content: `Kampaň "${campaign.name}" zastavena — ${failedCount}/${processed} zpráv selhalo (${(failedCount / processed * 100).toFixed(0)}%). Odesláno: ${sentCount}, Selhalo: ${failedCount}.`,
          })
        } catch (e) { /* ignore */ }

        return new Response(JSON.stringify({
          success: false,
          error: 'Campaign stopped due to high failure rate',
          sent: sentCount,
          failed: failedCount,
        }), {
          headers: { ...CORS, 'Content-Type': 'application/json' },
        })
      }

      // Rate limiting: 100ms between messages
      await new Promise(r => setTimeout(r, RATE_LIMIT_MS))
    }

    // 5. Mark as completed
    await supabase.from('broadcast_campaigns').update({
      status: 'completed',
      completed_at: new Date().toISOString(),
      sent_count: sentCount,
      failed_count: failedCount,
    }).eq('id', campaign_id)

    // Notify admin
    try {
      await supabase.from('admin_messages').insert({
        type: 'info',
        content: `Kampaň "${campaign.name}" dokončena. Odesláno: ${sentCount}/${totalCount}, Selhalo: ${failedCount}.`,
      })
    } catch (e) { /* ignore */ }

    return new Response(JSON.stringify({
      success: true,
      sent: sentCount,
      failed: failedCount,
      total: totalCount,
    }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('send-broadcast error:', err)

    // Log to debug_log
    try {
      await supabase.from('debug_log').insert({
        source: 'send-broadcast',
        action: 'broadcast_error',
        component: 'edge-function',
        status: 'error',
        error_message: (err as Error).message,
      })
    } catch (e) { /* ignore */ }

    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})

/** Build branded marketing HTML email — unified design (1:1 with invoice + screen) */
function buildMarketingHtml(body: string, subject: string): string {
  const SITE_URL = Deno.env.get('SITE_URL') || 'https://motogo24.cz'
  const header = `<div style="background:#0a1f15;padding:24px 32px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:middle;padding-right:14px;width:52px"><img src="${SITE_URL}/gfx/logo-icon.png" alt="MotoGo24" width="52" height="52" style="display:block;border:0"/></td>
      <td style="vertical-align:middle">
        <div style="color:#74FB71;font-size:20px;font-weight:900;letter-spacing:1px;line-height:1">MOTO GO 24</div>
        <div style="color:#74FB71;font-size:9px;font-weight:700;letter-spacing:2px;margin-top:4px">PŮJČOVNA MOTOREK</div>
      </td>
    </tr></table>
  </div>`
  const helpCard = `<div style="margin:24px 32px 0;background:#0a1f15;border:2px solid #74FB71;border-radius:8px;padding:24px">
    <div style="color:#74FB71;font-size:18px;font-weight:800;margin:0 0 8px">Máte dotaz?</div>
    <div style="color:#ffffff;font-size:13px;margin:0 0 16px">Pokud budete mít jakýkoliv dotaz, jsme vám k dispozici.</div>
    <a href="mailto:info@motogo24.cz" style="display:inline-block;background:#74FB71;color:#0a1f15;font-size:13px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:24px">info@motogo24.cz</a>
  </div>`
  const footer = `<div style="background:#0a1f15;padding:24px 32px;margin-top:24px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:top;padding-right:16px">
        <div style="border:1px solid #74FB71;border-radius:6px;padding:16px;color:#ffffff;font-size:12px;line-height:1.7">
          <div style="font-size:14px;font-weight:800;color:#ffffff">Motogo24</div>
          <div style="font-size:14px;font-weight:800;color:#ffffff;margin-bottom:6px">Bc. Petra Semorádová</div>
          <div style="color:#9ca3af">Mezná 9, 393 01 Mezná</div>
          <div style="color:#9ca3af">IČO: 21874263</div>
          <div><span style="color:#9ca3af">Telefon:</span> <span style="color:#74FB71">+420 774 256 271</span></div>
          <div><span style="color:#9ca3af">E-mail:</span> <span style="color:#74FB71">info@motogo24.cz</span></div>
          <div><span style="color:#9ca3af">Web:</span> <span style="color:#74FB71">www.motogo24.cz</span></div>
        </div>
      </td>
      <td style="vertical-align:top;width:120px;text-align:center">
        <img src="${SITE_URL}/gfx/qr-motogo24.png" alt="QR" width="110" height="110" style="display:block;background:#ffffff;padding:6px;border-radius:4px"/>
      </td>
    </tr></table>
    <div style="color:#9ca3af;font-size:10px;margin-top:16px;line-height:1.5;text-align:center">Tento email jste obdrželi, protože jste souhlasili se zasíláním marketingových sdělení od MOTO GO 24. Pro odhlášení odpovězte na tento email s textem &quot;ODHLÁSIT&quot;.</div>
  </div>`

  // Convert newlines to <br> for plain-text templates
  const htmlBody = body.replace(/\n/g, '<br>')

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#d9dee2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f1a14;-webkit-font-smoothing:antialiased">
  <div style="max-width:780px;margin:0 auto;background:#ffffff">
    ${header}
    <div style="padding:32px;color:#0f1a14;font-size:14px;line-height:1.7">${htmlBody}</div>
    ${helpCard}
    ${footer}
  </div>
</body></html>`
}
