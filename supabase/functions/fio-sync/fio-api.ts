// ===== fio-sync/fio-api.ts =====
// Fio API Bankovnictví (https://www.fio.cz/docs/cz/API_Bankovnictvi.pdf, verze 16. 10. 2025):
//   last/{token}/transactions.json                 pohyby od posledního stažení — banka si při
//                                                  NEPRÁZDNÉ odpovědi sama posune zarážku
//   periods/{token}/{od}/{do}/transactions.json    pohyby za období — zarážku NEposouvá
//   set-last-date/{token}/{rrrr-mm-dd}/            ruční nastavení zarážky na datum
//   set-last-id/{token}/{id}/                      ruční nastavení zarážky na ID pohybu
// Limit: jeden dotaz na token za 30 s (čtení i zápis) → HTTP 409. HTTP 500 = neplatný / vypršelý token.
// Odpověď, která není platný výpis (není JSON / chybí accountStatement), je CHYBA běhu, ne „prázdný
// výpis“: banka zarážku už posunula a pohyby by se jinak ztratily (dožene je kontrola `periods`).
import type { Row } from './util.ts'

export const FIO_BASE = 'https://fioapi.fio.cz/v1/rest'

type FioColumn = { value: unknown } | null
export type FioTx = Record<string, FioColumn>

const colStr = (tx: FioTx, key: string): string | null => {
  const v = tx[key]?.value
  return v === null || v === undefined || v === '' ? null : String(v)
}
const colNum = (tx: FioTx, key: string): number => Number(tx[key]?.value ?? 0)

/// Datum pohybu (column0) → YYYY-MM-DD v Europe/Prague. JSON vrací epoch ms
/// (starší verze) nebo string „2023-08-25+0200" (novější) — zvládáme obojí.
export function txDate(tx: FioTx): string {
  const v = tx['column0']?.value
  if (typeof v === 'number') return new Date(v).toLocaleDateString('sv-SE', { timeZone: 'Europe/Prague' })
  if (typeof v === 'string' && v.length >= 10) return v.slice(0, 10)
  return new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Prague' })
}

/** Pohyb z Fio → řádek fio_transactions. `withRaw` = uložit i celý pohyb (sloupec raw, SQL 20261130a1). */
export function mapTx(tx: FioTx, withRaw: boolean): Row {
  const amount = colNum(tx, 'column1')
  const row: Row = {
    fio_id: colNum(tx, 'column22'),
    tx_date: txDate(tx),
    amount,
    currency: colStr(tx, 'column14'),
    vs: colStr(tx, 'column5'),
    counter_account: colStr(tx, 'column2'),
    counter_bank: colStr(tx, 'column3'),
    counter_name: colStr(tx, 'column10'),
    message: colStr(tx, 'column16'),
    tx_type: colStr(tx, 'column8'),
    status: amount > 0 ? 'new' : 'outgoing',
  }
  if (withRaw) row.raw = tx
  return row
}

export type FioResult =
  | { ok: true; txs: FioTx[]; iban: string | null; idLastDownload: number | null; idTo: number | null }
  | { ok: false; error: string; http: number; rateLimited?: boolean; body?: string }

/** Výpis z odpovědi. Neplatné tělo = { ok:false, error:'bad_response' } (nikdy „prázdný výpis“). */
export function parseStatement(text: string, http = 200): FioResult {
  let payload: unknown = null
  try { payload = JSON.parse(text) } catch { return { ok: false, error: 'bad_response', http, body: text.slice(0, 300) } }
  const st = (payload as { accountStatement?: Row } | null)?.accountStatement
  if (!st || typeof st !== 'object') return { ok: false, error: 'bad_response', http, body: text.slice(0, 300) }
  const list = (st.transactionList as { transaction?: unknown } | null | undefined)?.transaction
  if (list != null && !Array.isArray(list)) return { ok: false, error: 'bad_response', http, body: text.slice(0, 300) }
  const info = (st.info || {}) as Row
  const num = (v: unknown) => (v != null && Number.isFinite(Number(v)) ? Number(v) : null)
  return {
    ok: true, txs: (list || []) as FioTx[],
    iban: typeof info.iban === 'string' && info.iban ? info.iban.replace(/\s+/g, '').toUpperCase() : null,
    idLastDownload: num(info.idLastDownload), idTo: num(info.idTo),
  }
}

async function get(url: string): Promise<FioResult> {
  let resp: Response
  try { resp = await fetch(url) } catch (e) { return { ok: false, error: 'fio_unreachable', http: 0, body: (e as Error).message } }
  if (resp.status === 409) { try { await resp.body?.cancel() } catch { /* ignore */ } return { ok: false, error: 'rate_limited', http: 409, rateLimited: true } }
  const text = await resp.text().catch(() => '')
  if (!resp.ok) return { ok: false, error: `fio_http_${resp.status}`, http: resp.status, body: text.slice(0, 500) }
  return parseStatement(text, resp.status)
}

export const fetchLast = (token: string) => get(`${FIO_BASE}/last/${token}/transactions.json`)
export const fetchPeriod = (token: string, from: string, to: string) => get(`${FIO_BASE}/periods/${token}/${from}/${to}/transactions.json`)

/** Ruční nastavení zarážky (první spuštění s novým tokenem). */
export async function setMarker(token: string, m: { date?: string; id?: number }): Promise<{ ok: boolean; error?: string; http?: number }> {
  const url = m.id ? `${FIO_BASE}/set-last-id/${token}/${m.id}/` : `${FIO_BASE}/set-last-date/${token}/${m.date}/`
  try {
    const resp = await fetch(url)
    try { await resp.body?.cancel() } catch { /* ignore */ }
    if (resp.status === 409) return { ok: false, error: 'rate_limited', http: 409 }
    return resp.ok ? { ok: true } : { ok: false, error: `fio_http_${resp.status}`, http: resp.status }
  } catch (e) { return { ok: false, error: 'fio_unreachable: ' + (e as Error).message } }
}
