// Replacement for https://esm.sh/@supabase/supabase-js@2 — createClient returns a proxy to the CURRENT fake DB
// (auth.ts caches its service client per isolate, tests swap the DB per scenario).
// deno-lint-ignore-file no-explicit-any
export function createClient(_u?: string, _k?: string, _o?: unknown): any {
  return new Proxy({}, { get: (_t, k) => { const db = (globalThis as any).__DB; const v = db[k as any]; return typeof v === 'function' ? v.bind(db) : v } })
}
export type SupabaseClient = any
