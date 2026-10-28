import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { bearerToken, isTrustedCaller } from '../_shared/auth.ts';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const TWILIO_SID = Deno.env.get('TWILIO_ACCOUNT_SID') || '';
const TWILIO_API_KEY = Deno.env.get('TWILIO_API_KEY_SID') || '';
const TWILIO_API_SECRET = Deno.env.get('TWILIO_API_KEY_SECRET') || '';
const TWILIO_PHONE = Deno.env.get('TWILIO_PHONE_NUMBER') || '';
const TWILIO_WA = Deno.env.get('TWILIO_WHATSAPP_NUMBER') || '';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS,
      'Content-Type': 'application/json'
    }
  });
}
/** Replace {{var}} placeholders; unknown vars → empty string */ function renderTemplate(template, vars) {
  if (!template) return '';
  let result = template;
  for (const [key, val] of Object.entries(vars)){
    result = result.replaceAll(`{{${key}}}`, val || '');
  }
  // Remove any remaining unreplaced vars
  result = result.replace(/\{\{[^}]+\}\}/g, '');
  return result;
}
/** Send message via Twilio REST API with 2 retries */ async function sendViaTwilio(channel, to, body, waTemplateId, waTemplateVars) {
  if (!TWILIO_SID || !TWILIO_API_KEY || !TWILIO_API_SECRET) {
    return {
      success: false,
      error: 'TWILIO_ACCOUNT_SID, TWILIO_API_KEY_SID or TWILIO_API_KEY_SECRET not configured'
    };
  }
  const fromNumber = channel === 'whatsapp' ? TWILIO_WA : TWILIO_PHONE;
  if (!fromNumber) {
    return {
      success: false,
      error: `TWILIO_${channel === 'whatsapp' ? 'WHATSAPP' : 'PHONE'}_NUMBER not configured`
    };
  }
  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_SID}/Messages.json`;
  const auth = btoa(`${TWILIO_API_KEY}:${TWILIO_API_SECRET}`);
  const toFormatted = channel === 'whatsapp' ? `whatsapp:${to}` : to;
  const fromFormatted = channel === 'whatsapp' ? `whatsapp:${fromNumber}` : fromNumber;
  // Build form params
  const params = new URLSearchParams();
  params.set('To', toFormatted);
  params.set('From', fromFormatted);
  if (channel === 'whatsapp' && waTemplateId) {
    // Meta-approved WA template
    params.set('ContentSid', waTemplateId);
    if (waTemplateVars && Object.keys(waTemplateVars).length > 0) {
      params.set('ContentVariables', JSON.stringify(waTemplateVars));
    }
  } else {
    params.set('Body', body);
  }
  // Retry: 2 attempts with exponential backoff (1s, 2s)
  for(let attempt = 1; attempt <= 2; attempt++){
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${auth}`,
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: params.toString()
      });
      if (res.ok) {
        const data = await res.json();
        return {
          success: true,
          sid: data.sid
        };
      }
      const errBody = await res.text();
      if (attempt === 2) {
        return {
          success: false,
          error: `Twilio ${res.status}: ${errBody}`
        };
      }
    } catch (e) {
      if (attempt === 2) {
        return {
          success: false,
          error: `Twilio fetch error: ${e.message}`
        };
      }
    }
    await new Promise((r)=>setTimeout(r, 1000 * attempt));
  }
  return {
    success: false,
    error: 'Twilio retry exhausted'
  };
}
serve(async (req)=>{
  if (req.method === 'OPTIONS') return new Response('ok', {
    headers: CORS
  });
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  try {
    // Auth (2026-10-11): service klíč (env — send-broadcast, ai-customer-messages-suggest;
    // app_settings.service_role_key — DB send_message_via_edge) nebo AKTIVNÍ účet Velína.
    // Dřív se admin hledal podle neexistujícího admin_users.user_id → Velín vždy 403.
    if (!bearerToken(req)) return jsonResponse({
      success: false,
      error: 'Unauthorized'
    }, 401);
    if (!await isTrustedCaller(req)) {
      return jsonResponse({
        success: false,
        error: 'Forbidden — admin only'
      }, 403);
    }
    const { channel, to, template_slug, template_vars = {}, customer_id, booking_id, language = 'cs', raw_body } = await req.json();
    // Validate required fields
    if (!channel || ![
      'sms',
      'whatsapp'
    ].includes(channel)) {
      return jsonResponse({
        success: false,
        error: 'Invalid channel — must be sms or whatsapp'
      }, 400);
    }
    if (!to || !/^\+\d{6,15}$/.test(to)) {
      return jsonResponse({
        success: false,
        error: 'Invalid "to" — must be E.164 format'
      }, 400);
    }
    // Resolve message body
    let body = '';
    let waTemplateId = null;
    let isMarketing = false;
    let resolvedSlug = template_slug || null;
    if (raw_body) {
      body = raw_body;
    } else if (template_slug) {
      // Šablona v jazyce zákazníka; když pro jazyk ŽÁDNÁ neexistuje (typicky uk), záložně
      // en → cs + debug_log (dřív 404 = zákazník nedostal nic). Existuje-li v jazyce, ale je
      // vypnutá (is_active=false), respektuje se vypnutí — žádná záloha.
      const reqLang = String(language || 'cs').toLowerCase().slice(0, 2);
      let tpl = null;
      let tplErr = null;
      let usedLang = reqLang;
      for (const l of [
        ...new Set([
          reqLang,
          'en',
          'cs'
        ])
      ]){
        const { data: rows, error } = await supabase.from('message_templates').select('body_template, wa_template_id, is_marketing, is_active').eq('slug', template_slug).eq('channel', channel).eq('language', l);
        if (error) {
          tplErr = error;
          break;
        }
        const list = rows || [];
        const active = list.find((r)=>r.is_active);
        if (active) {
          tpl = active;
          usedLang = l;
          break;
        }
        if (list.length) break; // šablona v jazyce existuje, ale je vypnutá → neposílat
      }
      if (tpl && usedLang !== reqLang) {
        try {
          await supabase.from('debug_log').insert({
            source: 'send-message',
            action: 'sms_template_fallback',
            component: channel,
            status: 'warning',
            request_data: {
              template_slug,
              channel,
              requested_language: reqLang,
              used_language: usedLang,
              booking_id: booking_id || null
            }
          });
        } catch  {}
      }
      if (tplErr || !tpl) {
        return jsonResponse({
          success: false,
          error: `Template "${template_slug}" not found for channel=${channel}, language=${language}`
        }, 404);
      }
      body = renderTemplate(tpl.body_template || '', template_vars);
      waTemplateId = tpl.wa_template_id || null;
      isMarketing = tpl.is_marketing || false;
    } else {
      return jsonResponse({
        success: false,
        error: 'Must provide raw_body or template_slug'
      }, 400);
    }
    if (!body && !waTemplateId) {
      return jsonResponse({
        success: false,
        error: 'Resolved message body is empty'
      }, 400);
    }
    // Build WA template variables (positional: "1", "2", ...)
    let waVars = null;
    if (channel === 'whatsapp' && waTemplateId && template_vars) {
      const keys = Object.keys(template_vars).sort();
      waVars = {};
      keys.forEach((k, i)=>{
        waVars[String(i + 1)] = template_vars[k] || '';
      });
    }
    // Send via Twilio
    const result = await sendViaTwilio(channel, to, body, waTemplateId, waVars);
    // Log to message_log
    const logEntry = {
      channel,
      direction: 'outbound',
      recipient_phone: to,
      customer_id: customer_id || null,
      booking_id: booking_id || null,
      template_slug: resolvedSlug,
      content_preview: body.slice(0, 160) || null,
      body,
      external_id: result.sid || null,
      status: result.success ? 'sent' : 'failed',
      error_message: result.error || null,
      is_marketing: isMarketing,
      template_vars: Object.keys(template_vars).length > 0 ? template_vars : null
    };
    const { data: logRow } = await supabase.from('message_log').insert(logEntry).select('id').single();
    if (!result.success) {
      // Log to debug_log
      try {
        await supabase.from('debug_log').insert({
          source: 'send-message',
          action: 'twilio_send_failed',
          component: 'edge-function',
          status: 'error',
          error_message: result.error,
          request_data: {
            channel,
            to,
            template_slug,
            booking_id
          }
        });
      } catch (e) {}
      return jsonResponse({
        success: false,
        error: result.error,
        message_id: logRow?.id || null
      }, 502);
    }
    return jsonResponse({
      success: true,
      message_id: logRow?.id || null,
      external_id: result.sid
    });
  } catch (err) {
    console.error('send-message error:', err);
    try {
      await supabase.from('debug_log').insert({
        source: 'send-message',
        action: 'unhandled_error',
        component: 'edge-function',
        status: 'error',
        error_message: err.message
      });
    } catch (e) {}
    return jsonResponse({
      error: err.message
    }, 500);
  }
});
