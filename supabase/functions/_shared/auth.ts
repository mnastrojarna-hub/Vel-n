// Sdílené ověření volajícího pro edge funkce s verify_jwt=false.
// Bezpečnostní fix 2026-06-10 — privilegované funkce (refundy, generování faktur,
// hromadné maily) musí samy ověřit, že volá service_role nebo přihlášený admin,
// protože Supabase gateway u verify_jwt=false neověřuje nic.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const ADMIN_ROLES = ['admin', 'superadmin', 'manager', 'operator']

/** Vytáhne Bearer token z Authorization hlavičky (nebo apikey). */
export function bearerToken(req: Request): string {
  const auth = req.headers.get('Authorization') || ''
  if (auth.toLowerCase().startsWith('bearer ')) return auth.slice(7).trim()
  return req.headers.get('apikey') || ''
}

/**
 * service_role = přesná shoda s env SUPABASE_SERVICE_ROLE_KEY, NEBO s
 * app_settings.service_role_key (DB triggery / pg_net / crony; sb_secret_… se env
 * klíči NEROVNÁ — STATE_6 2026-07-07, dřív helper tato volání odmítal), NEBO JWT,
 * který jako service_role uzná samo Auth API (víc platných klíčů po rotaci).
 * 2026-10-11: payload JWT se NIKDY nedekóduje (verify_jwt=false = podpis nikdo
 * neověřil) — rozhoduje jen shoda klíče nebo server.
 */
export async function isServiceRole(token: string): Promise<boolean> {
  const t = unquote(token)
  if (!t) return false
  if (await isKnownServiceKey(t)) return true
  return await authApiSaysService(t)
}

// ── Pomocné (2026-10-11) ── app_settings.service_role_key čte service klient,
// cache v isolate KEY_TTL_MS; při neshodě nové čtení nejdřív po KEY_RETRY_MS
// (rotace bez minutového výpadku, cizí tokeny nečtou DB u každého requestu);
// souběžná volání sdílí jeden dotaz; chyba čtení = poslední známý klíč.
const KEY_TTL_MS = 60_000
const KEY_RETRY_MS = 10_000
const JWT_SHAPE = /^[\w-]+\.[\w-]+\.[\w-]+$/
let settingsKey = ''
let settingsKeyAt = 0
let settingsKeyLoad: Promise<void> | null = null
let svcClient: ReturnType<typeof createClient> | null = null
const verifiedJwts = new Map<string, number>() // service JWT → ověřeno do (ms)

function svc() {
  svcClient ??= createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  return svcClient
}

/** Klíč mohl přijít jako JSON string (jsonb bez `#>> '{}'`) → obalený "…". */
function unquote(s: string): string {
  const t = (s || '').trim()
  return t.length > 1 && t.startsWith('"') && t.endsWith('"') ? t.slice(1, -1).trim() : t
}

/** Porovnání tajných klíčů v konstantním čase (prázdný klíč se nerovná ničemu). */
function sameKey(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false
  let d = 0
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return d === 0
}

async function readSettingsKey(): Promise<void> {
  try {
    const { data, error } = await svc()
      .from('app_settings').select('value').eq('key', 'service_role_key').maybeSingle()
    if (!error) {
      const v = (data as { value?: unknown } | null)?.value
      settingsKey = typeof v === 'string' ? unquote(v) : ''
    }
  } catch { /* poslední známý klíč */ }
  settingsKeyAt = Date.now()
}

/** Přesná shoda s env service klíčem nebo s app_settings.service_role_key. */
async function isKnownServiceKey(t: string): Promise<boolean> {
  if (sameKey(t, SERVICE_KEY)) return true
  if (!SUPABASE_URL || !SERVICE_KEY) return false
  const age = Date.now() - settingsKeyAt
  if (age < KEY_TTL_MS && sameKey(t, settingsKey)) return true
  if (age >= KEY_RETRY_MS) {
    settingsKeyLoad ??= readSettingsKey().finally(() => { settingsKeyLoad = null })
    await settingsKeyLoad
  }
  return sameKey(t, settingsKey)
}

/** JWT, který Auth API přijme na admin endpointu (= service_role, podpis ověřil server). */
async function authApiSaysService(t: string): Promise<boolean> {
  if (!SUPABASE_URL || t === ANON_KEY || !JWT_SHAPE.test(t)) return false
  if ((verifiedJwts.get(t) ?? 0) > Date.now()) return true
  try {
    const r = await fetch(`${SUPABASE_URL}/auth/v1/admin/users?page=1&per_page=1`, {
      headers: { apikey: ANON_KEY || t, Authorization: `Bearer ${t}` },
    })
    await r.body?.cancel()
    if (!r.ok) return false
    if (verifiedJwts.size >= 8) verifiedJwts.clear()
    verifiedJwts.set(t, Date.now() + KEY_TTL_MS)
    return true
  } catch {
    return false
  }
}

type Classified =
  | { kind: 'service' }
  // role jen u AKTIVNÍHO admina; activeAdmin = is_admin() (aktivní řádek i s role NULL)
  | { kind: 'user'; userId: string; adminRole: string | null; activeAdmin: boolean }
  | { kind: 'none'; reason: string }

/** Jádro: klíč → service; relace (ověří VÝHRADNĚ auth.getUser) → user (+ aktivní admin). */
async function classifyCaller(req: Request): Promise<Classified> {
  const t = unquote(bearerToken(req))
  if (!t) return { kind: 'none', reason: 'missing_token' }
  if (await isKnownServiceKey(t)) return { kind: 'service' }
  if (t !== ANON_KEY && JWT_SHAPE.test(t)) {
    const { data: { user }, error } = await svc().auth.getUser(t)
    if (!error && user) {
      const { data: row, error: rowErr } = await svc()
        .from('admin_users').select('role, active').eq('id', user.id).maybeSingle()
      const r = row as { role?: string | null; active?: boolean | null } | null
      // admin_users.active (NOT NULL DEFAULT true) — deaktivovaný účet = zákazník (jako is_admin())
      const activeAdmin = !rowErr && !!r && r.active === true
      const adminRole = activeAdmin && r?.role ? String(r.role) : null
      return { kind: 'user', userId: user.id, adminRole, activeAdmin }
    }
    // service_role JWT nemá `sub` → getUser selže; rozhodne Auth API
    if (await authApiSaysService(t)) return { kind: 'service' }
  }
  return { kind: 'none', reason: 'invalid_token' }
}

/**
 * Ověří, že volající je service_role NEBO přihlášený AKTIVNÍ admin (admin_users,
 * role z opts.roles). Vrací { ok, reason } — při ok=false má funkce vrátit 401/403.
 */
export async function requireAdminOrService(
  req: Request,
  opts: { roles?: string[] } = {},
): Promise<{ ok: boolean; userId?: string; reason?: string }> {
  const allowed = opts.roles ?? ADMIN_ROLES
  try {
    const c = await classifyCaller(req)
    if (c.kind === 'service') return { ok: true }
    if (c.kind === 'none') return { ok: false, reason: c.reason }
    if (!c.adminRole || !allowed.includes(c.adminRole)) return { ok: false, reason: 'not_admin' }
    return { ok: true, userId: c.userId }
  } catch (e) {
    return { ok: false, reason: 'auth_error' }
  }
}

/**
 * Důvěryhodný volající (2026-10-11): service klíč (env / app_settings — DB triggery,
 * pg_net, crony, jiné edge funkce), service JWT uznaný Auth API, nebo přihlášený
 * AKTIVNÍ admin libovolné role (jako SQL is_admin(); opts.roles zúží role).
 * Zákazník ani anon NE — pro funkce bez legitimního zákaznického volajícího.
 */
export async function isTrustedCaller(req: Request, opts: { roles?: string[] } = {}): Promise<boolean> {
  try {
    const c = await classifyCaller(req)
    if (c.kind === 'service') return true
    if (c.kind !== 'user') return false
    // bez opts.roles přesně is_admin(): aktivní řádek admin_users (i role NULL — sloupec je nullable)
    return opts.roles ? !!c.adminRole && opts.roles.includes(c.adminRole) : c.activeAdmin
  } catch {
    return false
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
 * 'admin' = AKTIVNÍ admin_users řádek s rolí z opts.adminRoles; deaktivovaný = 'user'.
 */
export async function authClassify(
  req: Request,
  opts: { adminRoles?: string[] } = {},
): Promise<{ kind: 'service' | 'admin' | 'user' | 'none'; userId?: string }> {
  const adminRoles = opts.adminRoles ?? ADMIN_ROLES
  try {
    const c = await classifyCaller(req)
    if (c.kind === 'service') return { kind: 'service' }
    if (c.kind === 'user') {
      return c.adminRole && adminRoles.includes(c.adminRole)
        ? { kind: 'admin', userId: c.userId }
        : { kind: 'user', userId: c.userId }
    }
    return { kind: 'none' }
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
