// ===== _tests/operator-flow-helpers.ts =====
// Společné pomůcky flow testů změny provozovatele (operator_flow_test.ts, operator_flow_pay_test.ts):
// zachycení handlerů přes import mapu gear-flow-map.json, volání handleru nad LooseDb, čtení uloženého
// dokladu ze storage, nastavení company_info a simulace staré DB (sloupec issuer_snapshot neexistuje).
// deno-lint-ignore-file no-explicit-any
import { LooseDb } from './gear-fake.ts'

export function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
export function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }
export type Row = Record<string, any>
type Handler = (req: Request) => Response | Promise<Response>

export const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/@supabase/supabase-js@2').endsWith('gear-flow-stubs.ts') } catch { return false } })()
const SVC = 'svc-test-key'
if (MAPPED) {
  Deno.env.set('SUPABASE_URL', 'https://fake.supabase.test')
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SVC)
  Deno.env.delete('PDFSHIFT_API_KEY') // doklady se ukládají jako HTML (čitelné v testu)
  Deno.env.set('RESEND_API_KEY', 're_test') // send-invoice-email (odeslání zachytí stubFetch)
}
const g = globalThis as unknown as { __gearHandlers?: Handler[]; __gearFakeDb?: unknown }
const handlers: Record<string, Handler> = {}
async function handlerOf(path: string): Promise<Handler> {
  if (handlers[path]) return handlers[path]
  const before = (g.__gearHandlers || []).length
  await import(path)
  const h = (g.__gearHandlers || [])[before]
  if (!h) throw new Error(`handler ${path} se nezaregistroval`)
  return (handlers[path] = h)
}
export async function post(path: string, db: LooseDb, body: Row) {
  g.__gearFakeDb = db
  const h = await handlerOf(path)
  const res = await h(new Request('http://x/fn', { method: 'POST', headers: { Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) }))
  const txt = await res.text()
  let json: any = null
  try { json = JSON.parse(txt) } catch { /* text */ }
  return { status: res.status, json, txt }
}
export const fileText = async (db: LooseDb, path: string) => { const b = db.files[path]; if (!b) throw new Error(`soubor ${path} není ve storage: ${Object.keys(db.files)}`); return await (b as Blob).text() }

export const BID = '11111111-2222-3333-4444-555566667777'
export const settings = (v?: Row) => (v ? [{ key: 'company_info', value: v }] : [])
/** jmenovitý výběr neexistujícího sloupce = chyba PostgREST 42703 (stará DB) */
export const noIssuerColumn = (db: LooseDb) => {
  db.failSelect = (t, cols) => t === 'invoices' && cols.includes('issuer_snapshot') ? { code: '42703', message: 'column invoices.issuer_snapshot does not exist' } : null
}
export const NEW_MARKS = ['MotoGo24 s.r.o.', '29909864', 'Mezná 9, 393 01 Mezná', '2303580494/2010', 'Fio banka', 'oddíl C, vložka 36876', 'Nejsme plátci DPH.']
export const OLD_MARKS = ['Jan Novák', '12345678', 'Dlouhá 1, 110 00 Praha', '19-2000145399/0800']
export const has = (h: string, marks: string[], label: string) => { for (const m of marks) ok(h.includes(m), `${label}: chybí „${m}“`) }
export const hasNot = (h: string, marks: string[], label: string) => { for (const m of marks) ok(!h.includes(m), `${label}: nesmí obsahovat „${m}“`) }

export const storedInvoice = (o: Row = {}): Row => ({ id: 'inv-1', number: 'ZF-2026-0007', type: 'proforma', booking_id: BID, source: 'booking', status: 'issued',
  customer_id: 'u1', items: [{ description: 'Pronájem BMW R 1250 GS — 10. 11. 2026 – 12. 11. 2026', qty: 2, unit_price: 1500 }], subtotal: 3000, total: 3000,
  issue_date: '2026-10-01', due_date: '2026-10-01', created_at: '2026-10-01T08:00:00+00:00', paid_date: null, pdf_path: null, variable_symbol: '20260007', customer_snapshot: null, ...o })
