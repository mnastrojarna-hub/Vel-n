// ===== _tests/gear-flow-stubs.ts =====
// Náhrady pro flow testy celých edge handlerů (import map _tests/gear-flow-map.json):
//  • `serve` (deno.land/std http/server) jen zachytí handler — žádný port se neotevírá,
//  • `createClient` (esm.sh supabase-js) vrátí aktuální LooseDb z globalThis.__gearFakeDb.
// Bez import mapy se tento modul nepoužije (flow testy se pak přeskočí).
type Handler = (req: Request) => Response | Promise<Response>
const g = globalThis as unknown as { __gearHandlers?: Handler[]; __gearFakeDb?: unknown }

export function serve(h: Handler): void {
  (g.__gearHandlers ||= []).push(h)
}

export function createClient(..._args: unknown[]): unknown {
  if (!g.__gearFakeDb) throw new Error('gear-flow-stubs: chybí globalThis.__gearFakeDb')
  return g.__gearFakeDb
}
