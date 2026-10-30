// ===== _tests/storno-stubs.ts =====
// Náhrady vzdálených modulů pro flow testy storna (import mapa _tests/storno-flow-map.json):
//  • `serve` (deno.land/std http/server) jen zachytí handler, žádný port se neotevírá,
//  • `createClient` (esm.sh supabase-js) = proxy na aktuální falešnou DB (globalThis.__STORNO_DB;
//    _shared/auth.ts si service klienta cachuje, testy DB mění pro každý scénář),
//  • výchozí export Stripe (esm.sh stripe@14) = proxy na aktuální falešný Stripe svět.
// deno-lint-ignore-file no-explicit-any
import { world } from './storno-fake-stripe.ts'

const g = globalThis as any

export function serve(h: (req: Request) => Response | Promise<Response>): void { g.__STORNO_CAPTURE?.(h) }

export function createClient(..._args: unknown[]): any {
  return new Proxy({}, { get: (_t, k) => { const db = g.__STORNO_DB; const v = db[k as any]; return typeof v === 'function' ? v.bind(db) : v } })
}
export type SupabaseClient = any

class Stripe {
  static createFetchHttpClient() { return {} }
  constructor(_k?: string, _o?: unknown) {}
  get paymentIntents() { return world().api().paymentIntents }
  get refunds() { return world().api().refunds }
  get charges() { return world().api().charges }
  get checkout() { return world().api().checkout }
  get webhooks() { return world().api().webhooks }
  get customers() { return world().api().customers }
}
export default Stripe
