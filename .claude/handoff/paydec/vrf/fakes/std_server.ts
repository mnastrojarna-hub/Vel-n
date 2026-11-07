// Replacement for deno.land/std http/server.ts — captures the handler.
// deno-lint-ignore-file no-explicit-any
export function serve(h: (req: Request) => Response | Promise<Response>) { (globalThis as any).__CAPTURE?.(h) }
