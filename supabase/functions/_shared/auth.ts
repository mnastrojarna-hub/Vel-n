// Sdílené ověření volajícího pro edge funkce s verify_jwt=false.
// Bezpečnostní fix 2026-06-10 — privilegované funkce (refundy, generování faktur,
// hromadné maily) musí samy ověřit, že volá service_role nebo přihlášený admin,
// protože Supabase gateway u verify_jwt=false neověřuje nic.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''

/** Vytáhne Bearer token z Authorization hlavičky (nebo apikey). */
export function bearerToken(req: Request): string {
  const auth = req.headers.get('Authorization') || ''
  if (auth.toLowerCase().startsWith('bearer ')) return auth.slice(7).trim()
  return req.headers.get('apikey') || ''
}

/**
 * service_role = přesná shoda s env klíčem (fast-path), NEBO JWT s claim
 * role:service_role, jehož PODPIS ověřil PostgREST (projekt může mít víc
 * platných service_role klíčů po rotaci JWT secretu / migraci API klíčů).
 *
 * BEZPEČNOSTNÍ FIX 2026-09-22 (5. kolo review vozíku): dřív stačilo payload
 * jen DEKÓDOVAT — u verify_jwt=false gateway podpis neověřuje, takže
 * nepodepsaný token `x.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.y` prošel jako
 * service_role do každé funkce nad tímto helperem (refundy, maily, push,
 * doplatky…). Teď se claim-only token ověří HEAD dotazem přes PostgREST:
 * podvržený / expirovaný → 401 (PGRST301) → false. Přesná shoda s env klíčem
 * (interní volání) síť nepotřebuje.
 */
export async function isServiceRole(token: string): Promise<boolean> {
  if (!token) return false
  if (SERVICE_KEY && token === SERVICE_KEY) return true
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return false
    const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/')
    const payload = JSON.parse(atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4)))
    if (payload?.role !== 'service_role') return false
  } catch {
    return false
  }
  try {
    const probe = createClient(SUPABASE_URL, ANON_KEY || token, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    })
    const { error } = await probe.from('admin_users').select('id', { head: true, count: 'exact' })
    return !error
  } catch {
    return false
  }
}

/**
 * Ověří, že volající je service_role NEBO přihlášený admin (admin_users).
 * Vrací { ok, reason } — při ok=false má funkce vrátit 401/403.
 */
export async function requireAdminOrService(
  req: Request,
  opts: { roles?: string[] } = {},
): Promise<{ ok: boolean; userId?: string; reason?: string }> {
  const token = bearerToken(req)
  if (!token) return { ok: false, reason: 'missing_token' }
  if (await isServiceRole(token)) return { ok: true }

  const allowed = opts.roles ?? ['admin', 'superadmin', 'manager', 'operator']
  try {
    const admin = createClient(SUPABASE_URL, SERVICE_KEY)
    const { data: { user }, error } = await admin.auth.getUser(token)
    if (error || !user) return { ok: false, reason: 'invalid_token' }
    const { data: row } = await admin
      .from('admin_users')
      .select('id, role')
      .eq('id', user.id)
      .maybeSingle()
    if (!row || !allowed.includes(row.role)) return { ok: false, reason: 'not_admin' }
    return { ok: true, userId: user.id }
  } catch (e) {
    return { ok: false, reason: 'auth_error' }
  }
}

/** Standardní 403 odpověď. */
export function forbidden(corsHeaders: Record<string, string>, reason = 'forbidden'): Response {
  return new Response(JSON.stringify({ error: 'unauthorized', reason }), {
    status: 403,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

/**
 * Zařadí volajícího: 'service' | 'admin' | 'user' | 'none'.
 * Pro funkce, které smí volat i přihlášený ZÁKAZNÍK (appka) — funkce si pak
 * sama ověří vlastnictví booking_id/order_id přes vrácené userId.
 */
export async function authClassify(
  req: Request,
  opts: { adminRoles?: string[] } = {},
): Promise<{ kind: 'service' | 'admin' | 'user' | 'none'; userId?: string }> {
  const token = bearerToken(req)
  if (!token) return { kind: 'none' }
  if (await isServiceRole(token)) return { kind: 'service' }
  const adminRoles = opts.adminRoles ?? ['admin', 'superadmin', 'manager', 'operator']
  try {
    const admin = createClient(SUPABASE_URL, SERVICE_KEY)
    const { data: { user }, error } = await admin.auth.getUser(token)
    if (error || !user) return { kind: 'none' }
    const { data: row } = await admin
      .from('admin_users')
      .select('role')
      .eq('id', user.id)
      .maybeSingle()
    if (row && adminRoles.includes(row.role)) return { kind: 'admin', userId: user.id }
    return { kind: 'user', userId: user.id }
  } catch {
    return { kind: 'none' }
  }
}
