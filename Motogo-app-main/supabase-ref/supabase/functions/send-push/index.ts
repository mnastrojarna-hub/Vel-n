import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * Edge Function: send-push
 * Sends FCM push notifications to a user's registered devices.
 * Called from SQL triggers via send_push_via_edge().
 *
 * Required env vars:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 *   FCM_PROJECT_ID  — Firebase project ID
 *   FCM_SERVICE_ACCOUNT_JSON — Firebase service account JSON (base64 encoded)
 */

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FCM_PROJECT_ID = Deno.env.get('FCM_PROJECT_ID') || ''
const FCM_SA_JSON_B64 = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

/** Base64url encode for JWT */
function base64url(input: string): string {
  return btoa(input).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

/** Create a signed JWT for Google OAuth2 using service account */
async function createGoogleJWT(serviceAccount: {
  client_email: string
  private_key: string
}): Promise<string> {
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const now = Math.floor(Date.now() / 1000)
  const claim = base64url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))

  const signInput = `${header}.${claim}`

  // Parse PEM private key
  const pemContent = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '')

  const keyBinary = Uint8Array.from(atob(pemContent), c => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBinary,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signInput),
  )

  const sigB64 = base64url(String.fromCharCode(...new Uint8Array(signature)))
  return `${signInput}.${sigB64}`
}

/** Get OAuth2 access token from Google */
async function getAccessToken(serviceAccount: {
  client_email: string
  private_key: string
}): Promise<string> {
  const jwt = await createGoogleJWT(serviceAccount)

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  if (!res.ok) {
    const err = await res.text()
    throw new Error(`Google OAuth2 failed: ${res.status} ${err}`)
  }

  const data = await res.json()
  return data.access_token
}

/** Send FCM v1 push notification */
async function sendFCM(
  accessToken: string,
  projectId: string,
  deviceToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ success: boolean; error?: string }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: deviceToken,
          notification: { title, body },
          data,
          android: {
            priority: 'high',
            notification: {
              channel_id: 'motogo_door_codes',
              sound: 'default',
              priority: 'HIGH',
            },
          },
          apns: {
            payload: {
              aps: {
                alert: { title, body },
                sound: 'default',
                badge: 1,
              },
            },
          },
        },
      }),
    })

    if (res.ok) return { success: true }

    const errBody = await res.text()
    return { success: false, error: `FCM ${res.status}: ${errBody}` }
  } catch (e) {
    return { success: false, error: `FCM fetch error: ${(e as Error).message}` }
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    // Auth: only service_role key allowed
    const authHeader = req.headers.get('authorization') || ''
    const token = authHeader.replace('Bearer ', '')
    if (token !== SUPABASE_SERVICE_KEY) {
      return jsonResponse({ success: false, error: 'Unauthorized — service_role only' }, 401)
    }

    const { user_id, title, body: msgBody, data = {} } = await req.json()

    if (!user_id || !title) {
      return jsonResponse({ success: false, error: 'user_id and title required' }, 400)
    }

    // Check FCM config
    if (!FCM_PROJECT_ID || !FCM_SA_JSON_B64) {
      console.warn('FCM not configured — skipping push')
      return jsonResponse({ success: true, skipped: true, reason: 'FCM not configured' })
    }

    // Parse service account
    let serviceAccount: { client_email: string; private_key: string }
    try {
      const decoded = atob(FCM_SA_JSON_B64)
      serviceAccount = JSON.parse(decoded)
    } catch {
      return jsonResponse({ success: false, error: 'Invalid FCM_SERVICE_ACCOUNT_JSON' }, 500)
    }

    // Get user's active push tokens
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    const { data: tokens, error: tokErr } = await supabase
      .from('push_tokens')
      .select('token, platform')
      .eq('user_id', user_id)
      .eq('active', true)

    if (tokErr || !tokens || tokens.length === 0) {
      return jsonResponse({ success: true, sent: 0, reason: 'No active push tokens' })
    }

    // Get OAuth2 access token
    const accessToken = await getAccessToken(serviceAccount)

    // Convert data values to strings (FCM requires string values)
    const stringData: Record<string, string> = {}
    for (const [k, v] of Object.entries(data)) {
      stringData[k] = String(v)
    }

    // Send to each token
    let sent = 0
    let failed = 0
    const errors: string[] = []

    for (const { token: deviceToken } of tokens) {
      const result = await sendFCM(accessToken, FCM_PROJECT_ID, deviceToken, title, msgBody || '', stringData)
      if (result.success) {
        sent++
      } else {
        failed++
        errors.push(result.error || 'unknown')

        // Deactivate invalid tokens
        if (result.error?.includes('NOT_FOUND') || result.error?.includes('UNREGISTERED')) {
          await supabase
            .from('push_tokens')
            .update({ active: false })
            .eq('token', deviceToken)
        }
      }
    }

    return jsonResponse({ success: true, sent, failed, errors: errors.length > 0 ? errors : undefined })
  } catch (err) {
    console.error('send-push error:', err)
    return jsonResponse({ success: false, error: (err as Error).message }, 500)
  }
})
