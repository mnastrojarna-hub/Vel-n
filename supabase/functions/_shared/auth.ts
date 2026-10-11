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

// ═══ Doklady zákazníka: save-verification-document + scan-document (2026-10-11) ═══
// verify_jwt=false (host webu nemá JWT) → kdo smí za koho nahrát / skenovat doklad:
//   • service_role a aktivní admin (admin_users.active = true, každá role — jako is_admin())
//     za kohokoli; booking_id musí patřit cílovému zákazníkovi,
//   • přihlášený zákazník (JWT) sám za sebe,
//   • bez session (nebo přihlášený někdo jiný) nositel booking_id ŽIVÉ rezervace
//     (pending/reserved/active, konec dle Prahy dnes či později, jakýkoli zdroj)
//     → cíl = vlastník rezervace (user_id z těla musí sedět nebo chybět),
//   • jen scan-document (opts.legacyUser) PŘECHODNĚ: bez session a bez booking_id
//     samotné user_id zákazníka s živou rezervací (živý web zatím booking_id ani
//     JWT neposílá; via 'legacy_user' — po nasazení nového webového JS zrušit).
// Odmítnutí: 401 auth_required (bez session i bez booking_id) / 403 forbidden —
// bez rozlišení „neexistuje" × „nesedí" (žádné orákulum existence účtu/rezervace).

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const LIVE_STATUSES = ['pending', 'reserved', 'active']

/** Datum v Praze YYYY-MM-DD (= (ts AT TIME ZONE 'Europe/Prague')::date). */
export function pragueDate(d: Date): string {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Prague', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(d)
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? ''
  return `${get('year')}-${get('month')}-${get('day')}`
}

/** Živá rezervace: pending/reserved/active a konec (Praha) dnes nebo později. */
export function bookingIsLive(b: { status?: unknown; end_date?: unknown } | null | undefined): boolean {
  if (!b || !LIVE_STATUSES.includes(String(b.status ?? ''))) return false
  const end = new Date(String(b.end_date ?? ''))
  return !isNaN(end.getTime()) && pragueDate(end) >= pragueDate(new Date())
}

export type DocBooking = { id: string; user_id: string; status: string; end_date: string; created_at: string }
export type DocVia = 'service' | 'admin' | 'owner' | 'booking' | 'legacy_user'
export type DocCaller =
  | { ok: true; via: DocVia; userId: string | null; bookingId: string | null; callerId: string | null; booking: DocBooking | null }
  | { ok: false; status: 400 | 401 | 403 | 500; reason: string }

export async function resolveDocCaller(
  req: Request,
  wantUserId: string | null,
  bookingId: string | null,
  opts: { targetOptional?: boolean; legacyUser?: boolean } = {},
): Promise<DocCaller> {
  if (wantUserId && !UUID_RE.test(wantUserId)) return { ok: false, status: 400, reason: 'invalid_user_id' }
  if (bookingId && !UUID_RE.test(bookingId)) return { ok: false, status: 400, reason: 'invalid_booking_id' }
  try {
    const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { autoRefreshToken: false, persistSession: false } })
    let bk: DocBooking | null = null
    if (bookingId) {
      const { data, error } = await sb.from('bookings')
        .select('id, user_id, status, end_date, created_at').eq('id', bookingId).maybeSingle()
      if (error) return { ok: false, status: 500, reason: 'auth_check_failed' }
      bk = (data as DocBooking | null) ?? null
    }

    // service / aktivní admin: libovolný zákazník (důvody odmítnutí smí znát)
    const privileged = (via: DocVia, callerId: string | null): DocCaller => {
      if (bookingId && !bk) return { ok: false, status: 403, reason: 'booking_not_found' }
      const uid = wantUserId || bk?.user_id || null
      if (bk && uid !== bk.user_id) return { ok: false, status: 403, reason: 'booking_user_mismatch' }
      if (!uid && !opts.targetOptional) return { ok: false, status: 400, reason: 'missing_user_id' }
      return { ok: true, via, userId: uid, bookingId, callerId, booking: bk }
    }

    const token = bearerToken(req)
    if (token && await isServiceRole(token)) return privileged('service', null)

    // přihlášený uživatel (anon / publishable / secret klíč není session)
    let callerId: string | null = null
    if (token && token !== ANON_KEY && !token.startsWith('sb_')) {
      const { data, error } = await sb.auth.getUser(token)
      if (!error) callerId = data?.user?.id ?? null
    }
    if (callerId) {
      const { data: au } = await sb.from('admin_users').select('active').eq('id', callerId).maybeSingle()
      if ((au as { active?: boolean } | null)?.active === true) return privileged('admin', callerId)
      if ((!wantUserId || wantUserId === callerId) && (!bookingId || bk?.user_id === callerId)) {
        return { ok: true, via: 'owner', userId: callerId, bookingId, callerId, booking: bk }
      }
      // přihlášen jako někdo jiný (sdílený PC) → dál jen přes rezervaci
    }

    // nositel booking_id živé rezervace → vlastník rezervace
    if (bk?.user_id && bookingIsLive(bk) && (!wantUserId || wantUserId === bk.user_id)) {
      return { ok: true, via: 'booking', userId: bk.user_id, bookingId, callerId, booking: bk }
    }

    // PŘECHOD (jen scan-document — zápis jen do debug_log): user_id s živou rezervací
    if (opts.legacyUser && !bookingId && !callerId && wantUserId) {
      const { data: rows } = await sb.from('bookings').select('status, end_date')
        .eq('user_id', wantUserId).in('status', LIVE_STATUSES)
        .order('end_date', { ascending: false }).limit(1)
      if (bookingIsLive((rows as { status: string; end_date: string }[] | null)?.[0])) {
        return { ok: true, via: 'legacy_user', userId: wantUserId, bookingId: null, callerId: null, booking: null }
      }
    }

    return (callerId || bookingId)
      ? { ok: false, status: 403, reason: 'forbidden' }
      : { ok: false, status: 401, reason: 'auth_required' }
  } catch {
    return { ok: false, status: 500, reason: 'auth_check_failed' }
  }
}
