// Sdílené ověření volajícího pro edge funkce s verify_jwt=false.
// Bezpečnostní fix 2026-06-10 — privilegované funkce (refundy, generování faktur,
// hromadné maily) musí samy ověřit, že volá service_role nebo přihlášený admin,
// protože Supabase gateway u verify_jwt=false neověřuje nic.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
/** Vytáhne Bearer token z Authorization hlavičky (nebo apikey). */ export function bearerToken(req) {
  const auth = req.headers.get('Authorization') || '';
  if (auth.toLowerCase().startsWith('bearer ')) return auth.slice(7).trim();
  return req.headers.get('apikey') || '';
}
/**
 * service_role = buď přesná shoda s env klíčem (fast-path), nebo jakýkoli JWT
 * s claim role:service_role (projekt může mít víc platných service_role klíčů
 * po rotaci JWT secretu / migraci API klíčů).
 */ export function isServiceRole(token) {
  if (!token) return false;
  if (SERVICE_KEY && token === SERVICE_KEY) return true;
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return false;
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    return payload?.role === 'service_role';
  } catch  {
    return false;
  }
}
/**
 * Ověří, že volající je service_role NEBO přihlášený admin (admin_users).
 * Vrací { ok, reason } — při ok=false má funkce vrátit 401/403.
 */ export async function requireAdminOrService(req, opts = {}) {
  const token = bearerToken(req);
  if (!token) return {
    ok: false,
    reason: 'missing_token'
  };
  if (isServiceRole(token)) return {
    ok: true
  };
  const allowed = opts.roles ?? [
    'admin',
    'superadmin',
    'manager',
    'operator'
  ];
  try {
    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: { user }, error } = await admin.auth.getUser(token);
    if (error || !user) return {
      ok: false,
      reason: 'invalid_token'
    };
    const { data: row } = await admin.from('admin_users').select('id, role').eq('id', user.id).maybeSingle();
    if (!row || !allowed.includes(row.role)) return {
      ok: false,
      reason: 'not_admin'
    };
    return {
      ok: true,
      userId: user.id
    };
  } catch (e) {
    return {
      ok: false,
      reason: 'auth_error'
    };
  }
}
/** Standardní 403 odpověď. */ export function forbidden(corsHeaders, reason = 'forbidden') {
  return new Response(JSON.stringify({
    error: 'unauthorized',
    reason
  }), {
    status: 403,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json'
    }
  });
}
/**
 * Zařadí volajícího: 'service' | 'admin' | 'user' | 'none'.
 * Pro funkce, které smí volat i přihlášený ZÁKAZNÍK (appka) — funkce si pak
 * sama ověří vlastnictví booking_id/order_id přes vrácené userId.
 */ export async function authClassify(req, opts = {}) {
  const token = bearerToken(req);
  if (!token) return {
    kind: 'none'
  };
  if (isServiceRole(token)) return {
    kind: 'service'
  };
  const adminRoles = opts.adminRoles ?? [
    'admin',
    'superadmin',
    'manager',
    'operator'
  ];
  try {
    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: { user }, error } = await admin.auth.getUser(token);
    if (error || !user) return {
      kind: 'none'
    };
    const { data: row } = await admin.from('admin_users').select('role').eq('id', user.id).maybeSingle();
    if (row && adminRoles.includes(row.role)) return {
      kind: 'admin',
      userId: user.id
    };
    return {
      kind: 'user',
      userId: user.id
    };
  } catch  {
    return {
      kind: 'none'
    };
  }
}
