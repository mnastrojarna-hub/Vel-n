// ===== fio-sync/util.ts =====
// Společné typy a drobné pomůcky synchronizace Fio účtu (bez vzdálených importů — testovatelné).
// „Stav“ (caps.state) = SQL 20261130a1 je nasazené (fio_sync_state, nové sloupce fio_transactions,
// RPC fio_sync_begin/end, fio_claim_transactions); „requests“ = SQL 20261130b (bank_payment_requests).
// Bez nich se funkce chová PŘESNĚ jako před změnou (jen staré sloupce a stavy).

// deno-lint-ignore no-explicit-any
export type Sb = any
export type Row = Record<string, unknown>

export type Caps = { state: boolean; requests: boolean }

/** Řádek fio_transactions (příchozí platba ke zpracování). */
export type Tx = {
  fio_id: number; tx_date: string; amount: number; currency: string | null
  vs: string | null; counter_account: string | null; counter_bank: string | null
  counter_name: string | null; message: string | null; tx_type: string | null
  status?: string | null
  manual_target_type?: string | null; manual_target_id?: string | null; manual_accept_amount?: boolean | null
  attempts?: number | null; first_error_at?: string | null
}

export type TargetType = 'booking' | 'surcharge' | 'order' | 'request'

/** Výsledek zpracování jednoho pohybu → zápis do fio_transactions. */
export type Outcome = {
  status: string
  bookingId?: string | null; orderId?: string | null; requestId?: string | null
  targetType?: TargetType | null
  reason?: string | null
  note?: string | null
  expected?: number | null
  followup?: 'overpaid' | null
  /** dřívější částečné platby téhož cíle, které tato platba dorovnala */
  absorbed?: number[]
}

/** Přechodná chyba — pohyb zůstane ve frontě a zkusí se znovu (nejdéle 30 minut). */
export class RetryError extends Error {
  constructor(msg: string, public bookingId: string | null = null, public requestId: string | null = null) { super(msg) }
}

export type Env = { url: string; key: string; now?: () => number }
export type Ctx = { sb: Sb; caps: Caps; env: Env }

export const fmtAmount = (n: number) => (Math.round((Number(n) || 0) * 100) / 100).toFixed(2)
export const round2 = (n: number) => Math.round((Number(n) || 0) * 100) / 100
export const short = (id: string | null | undefined) => String(id || '').slice(-8).toUpperCase()
export const nowIso = (env?: Env) => new Date(env?.now ? env.now() : Date.now()).toISOString()

/** VS plátce → jen číslice bez úvodních nul (banky VS doplňují nulami; naše VS nulou nezačínají). */
export const vsDigits = (vs: unknown) => String(vs ?? '').replace(/\D/g, '').replace(/^0+/, '')

/** Chybí tabulka / sloupec / funkce (SQL ještě není nasazené)? */
export function isMissing(e: { code?: string | null; message?: string | null } | null | undefined): boolean {
  if (!e) return false
  return /PGRST20[245]|42P01|42703|42883|could not find the (function|table|'?\w+'? column)|does not exist/i
    .test(`${e.code || ''} ${e.message || ''}`)
}

export async function debugLog(sb: Sb, action: string, status: string, data: Row, err?: string | null) {
  try {
    await sb.from('debug_log').insert({
      source: 'fio-sync', action, component: 'fio', status,
      request_data: data, error_message: err || null,
    })
  } catch { /* ignore */ }
}

/** Volání jiné edge funkce service klíčem (generate-invoice, send-booking-email, send-email). */
export function edgePost(env: Env, fn: string, body: Row): Promise<Response> {
  return fetch(env.url + '/functions/v1/' + fn, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + env.key, apikey: env.key },
    body: JSON.stringify(body),
  })
}

export async function audit(sb: Sb, action: string, entityType: string, entityId: string, data: Row) {
  try {
    await sb.from('admin_audit_log').insert({ admin_id: null, action, entity_type: entityType, entity_id: entityId, new_data: data })
  } catch { /* ignore */ }
}
