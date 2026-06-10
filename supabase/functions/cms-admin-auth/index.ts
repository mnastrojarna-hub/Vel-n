// ===== MotoGo24 — Edge Function: cms-admin-auth =====
// Bezpečnostní fix 2026-06-10 (#5): odstraní potřebu posílat `cms_admin_token`
// do prohlížeče / číst ho anon klíčem z `app_settings`.
//
// Tok: Velín admin přijde na web s ?cms_admin=<raw_token> (jednorázový bootstrap).
// PHP zavolá tuto funkci, ta token ověří proti app_settings (service_role) a
// vrátí PODEPSANOU capability `cap` = "r1.<exp>.<base64url(RSA-SHA256 sig)>".
// PHP i cms-save pak ověřují `cap` VEŘEJNÝM klíčem lokálně — raw token už nikdy
// neopustí server a smí se v RLS skrýt z anon čtení.
//
// Secret (nastavit v Supabase, NE na hostingu):
//   CMS_ADMIN_SIGN_KEY = privátní RSA klíč (PEM PKCS8) — pár k veřejnému klíči v PHP configu.
// JWT: verify_jwt=false (anon-callable; vlastní ověření tokenu uvnitř).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const SIGN_KEY_PEM = Deno.env.get('CMS_ADMIN_SIGN_KEY') ?? ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, authorization, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const TTL_SECONDS = 30 * 24 * 3600 // 30 dní

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

function base64UrlFromBytes(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf)
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----BEGIN [^-]+-----/g, '').replace(/-----END [^-]+-----/g, '').replace(/\s+/g, '')
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out.buffer
}

let cachedKey: CryptoKey | null = null
async function getSignKey(): Promise<CryptoKey> {
  if (cachedKey) return cachedKey
  cachedKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(SIGN_KEY_PEM),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  return cachedKey
}

async function signCap(exp: number): Promise<string> {
  const msg = new TextEncoder().encode(`cms|${exp}`)
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', await getSignKey(), msg)
  return `r1.${exp}.${base64UrlFromBytes(sig)}`
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)
  if (!SIGN_KEY_PEM) return json({ error: 'sign_key_not_configured' }, 503)

  let body: { token?: string }
  try { body = await req.json() } catch { return json({ error: 'invalid_json' }, 400) }
  const token = typeof body.token === 'string' ? body.token : ''
  if (!token) return json({ error: 'missing_token' }, 400)

  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
  const { data } = await sb.from('app_settings').select('value').eq('key', 'cms_admin_token').maybeSingle()
  let expected = ''
  try {
    const v = (data as { value?: unknown } | null)?.value
    expected = typeof v === 'string' ? v : (v == null ? '' : String(v).replace(/^"|"$/g, ''))
  } catch { expected = '' }
  if (!expected) return json({ error: 'token_not_configured' }, 503)

  if (!timingSafeEqual(expected, token)) return json({ error: 'invalid_token' }, 403)

  const exp = Math.floor(Date.now() / 1000) + TTL_SECONDS
  const cap = await signCap(exp)
  return json({ ok: true, cap, exp })
})
