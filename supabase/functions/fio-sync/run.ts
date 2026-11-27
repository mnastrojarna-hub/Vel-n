// ===== fio-sync/run.ts =====
// Jeden běh synchronizace: zámek běhu → stažení pohybů → uložení → zpracování fronty → zápis výsledku.
// S nasazeným SQL 20261130a1 (RPC fio_sync_begin / fio_sync_end / fio_claim_transactions):
//   • nejvýš JEDEN běh najednou (zámek s vypršením) a pohyb zpracovává vždy jen jeden proces (claim),
//   • omezená dávka (10 pohybů / ~40 s na běh), zbytek dotáhne další minuta,
//   • prázdný běh nepíše nic do debug_log; selhání loguje a hlásí SQL jen při ZMĚNĚ stavu,
//   • žádný ztracený pohyb: neplatná odpověď banky nebo neuložený řádek = neúspěšný běh a další běh
//     stáhne pohyby za období (periods — nezávisle na zarážce, kterou banka mezitím posunula);
//     totéž jednou denně preventivně; duplicitní ID se při ukládání přeskakují,
//   • chyba zpracování pohybu se opakuje při dalších bězích (30 minut), pak jde obsluze.
// Bez SQL (RPC neexistuje) = chování před změnou: bez zámku, až 50 pohybů, chyba = stav 'error'.
import { type Caps, type Ctx, debugLog, type Env, isMissing, type Outcome, RetryError, type Row, type Sb, type Tx } from './util.ts'
import { fetchLast, fetchPeriod, type FioTx, mapTx } from './fio-api.ts'
import { dispatch } from './dispatch.ts'
import { settleAbsorbed } from './partials.ts'
import { notifyReview } from './ops-mail.ts'

export type RunOpts = { token: string; env: Env; batch?: number; budgetMs?: number; leaseSeconds?: number }
export type Summary = { fetched: number; processed: number; confirmed: number; surcharge: number; orders: number; changes: number; no_match: number; mismatch: number; review: number; errors: number }

const RETRY_WINDOW_MS = 30 * 60_000
const LEGACY_COLS = 'fio_id, tx_date, amount, currency, vs, counter_account, counter_bank, counter_name, message, tx_type'
const now = (env: Env) => (env.now ? env.now() : Date.now())
const newSummary = (): Summary => ({ fetched: 0, processed: 0, confirmed: 0, surcharge: 0, orders: 0, changes: 0, no_match: 0, mismatch: 0, review: 0, errors: 0 })

async function beginRun(sb: Sb, seconds: number): Promise<{ state: boolean; acquired: boolean; info: Row; error?: string }> {
  try {
    const { data, error } = await sb.rpc('fio_sync_begin', { p_lease_seconds: seconds })
    if (error) return isMissing(error) ? { state: false, acquired: true, info: {} } : { state: true, acquired: false, info: {}, error: error.message }
    const info = (data || {}) as Row
    return { state: true, acquired: info.acquired === true, info }
  } catch (e) { return { state: true, acquired: false, info: {}, error: (e as Error).message } }
}

async function endRun(sb: Sb, caps: Caps, ok: boolean | null, error: string | null, http: number | null, info: Row) {
  if (!caps.state) return
  try { await sb.rpc('fio_sync_end', { p_ok: ok, p_error: error, p_http: http, p_info: info }) } catch { /* zámek vyprší sám */ }
}

/** Uložení pohybů (PK fio_id; duplicity se přeskakují). Vrací počet nově uložených / chybu. */
async function storeRows(ctx: Ctx, txs: FioTx[]): Promise<{ ok: boolean; inserted: number; error?: string }> {
  const rows = txs.map((tx) => mapTx(tx, ctx.caps.state)).filter((r) => Number(r.fio_id) > 0)
  if (!rows.length) return { ok: true, inserted: 0 }
  const up = (list: Row[]) => ctx.sb.from('fio_transactions').upsert(list, { onConflict: 'fio_id', ignoreDuplicates: true }).select('fio_id')
  const { data, error } = await up(rows)
  if (!error) return { ok: true, inserted: Array.isArray(data) ? data.length : 0 }
  if (!ctx.caps.state) return { ok: false, inserted: 0, error: error.message }
  // Hromadný zápis selhal → po jednom (jeden vadný řádek nesmí zahodit ostatní).
  let inserted = 0
  const failed: number[] = []
  for (const r of rows) {
    const one = await up([r])
    if (one.error) failed.push(Number(r.fio_id))
    else inserted += Array.isArray(one.data) ? one.data.length : 0
  }
  return failed.length ? { ok: false, inserted, error: `${error.message} (neuloženo: ${failed.slice(0, 20).join(', ')})` } : { ok: true, inserted }
}

function count(s: Summary, out: Outcome) {
  s.processed++
  if (out.status === 'confirmed_booking') s.confirmed++
  else if (out.status === 'confirmed_surcharge') s.surcharge++
  else if (out.status === 'confirmed_order') s.orders++
  else if (out.status === 'confirmed_change') s.changes++
  else if (out.status === 'no_match') s.no_match++
  else if (out.status === 'amount_mismatch') s.mismatch++
  else if (out.status === 'needs_review') s.review++
  else if (out.status === 'error') s.errors++
}

async function finish(ctx: Ctx, p: Tx, out: Outcome) {
  const at = new Date(now(ctx.env)).toISOString()
  const patch: Row = { status: out.status, booking_id: out.bookingId ?? null, note: out.note ?? null, processed_at: at }
  if (ctx.caps.state) {
    Object.assign(patch, {
      order_id: out.orderId ?? null, request_id: out.requestId ?? null, target_type: out.targetType ?? null,
      reason_code: out.reason ?? null, expected_amount: out.expected ?? null,
      followup: out.followup ?? null, followup_done_at: null, claimed_until: null,
    })
  }
  await ctx.sb.from('fio_transactions').update(patch).eq('fio_id', p.fio_id)
  if (out.status.startsWith('confirmed_')) await settleAbsorbed(ctx, out.absorbed, out.status, p.fio_id, at)
}

async function onError(ctx: Ctx, p: Tx, e: unknown, s: Summary): Promise<Outcome> {
  const { sb, caps, env } = ctx
  const msg = String((e as Error)?.message || e).slice(0, 500)
  const at = new Date(now(env)).toISOString()
  s.errors++
  if (!caps.state) {
    await debugLog(sb, 'tx_processing_failed', 'error', { fio_id: p.fio_id }, msg)
    try { await sb.from('fio_transactions').update({ status: 'error', note: msg, processed_at: at }).eq('fio_id', p.fio_id) } catch { /* ignore */ }
    return { status: 'error', note: msg }
  }
  const attempts = (Number(p.attempts) || 0) + 1
  const first = p.first_error_at || at
  const bookingId = e instanceof RetryError ? e.bookingId : null
  if (now(env) - Date.parse(first) < RETRY_WINDOW_MS) {
    // přechodná chyba → pohyb zůstává ve frontě; další pokus nejdřív za 50 s (ne znovu v tomto běhu)
    if (attempts === 1) await debugLog(sb, 'tx_processing_failed', 'error', { fio_id: p.fio_id, will_retry: true }, msg)
    try {
      await sb.from('fio_transactions').update({ status: 'new', attempts, first_error_at: first, note: `chyba zpracování (pokus ${attempts}): ${msg}`.slice(0, 500),
        claimed_until: new Date(now(env) + 50_000).toISOString(), ...(bookingId ? { booking_id: bookingId } : {}) }).eq('fio_id', p.fio_id)
    } catch { /* ignore */ }
    return { status: 'new', note: msg }
  }
  await debugLog(sb, 'tx_processing_gave_up', 'error', { fio_id: p.fio_id, attempts }, msg)
  try {
    await sb.from('fio_transactions').update({ status: 'needs_review', reason_code: 'processing_error', attempts,
      note: `zpracování opakovaně selhalo: ${msg}`.slice(0, 500), processed_at: at, claimed_until: null, ...(bookingId ? { booking_id: bookingId } : {}) }).eq('fio_id', p.fio_id)
  } catch { /* ignore */ }
  if (e instanceof RetryError && e.requestId && caps.requests) {
    try {
      await sb.from('bank_payment_requests').update({ status: 'failed', fio_id: p.fio_id, result: { state: 'failed', code: 'change_failed', reason: 'retry_exhausted' } })
        .eq('id', e.requestId).in('status', ['pending', 'expired'])
    } catch { /* ignore */ }
  }
  await notifyReview(env, p, 'zpracování platby opakovaně selhalo', `Platbu se 30 minut nedařilo zpracovat (${msg}). Nic se nepotvrdilo — zkontrolujte ji a spárujte ručně, nebo vraťte.`)
  s.review++
  return { status: 'needs_review', reason: 'processing_error', note: msg }
}

async function processRow(ctx: Ctx, p: Tx, s: Summary): Promise<Outcome> {
  try {
    const out = await dispatch(ctx, p)
    await finish(ctx, p, out)
    count(s, out)
    return out
  } catch (e) {
    return await onError(ctx, p, e, s)
  }
}

/** Vezme si jeden pohyb ke zpracování (atomicky v DB; souběžný běh / ruční „zpracovat“ ho nedostane). */
async function claim(ctx: Ctx, fioId: number | null): Promise<{ row: Tx | null; missing?: boolean }> {
  const { data, error } = await ctx.sb.rpc('fio_claim_transactions', { p_limit: 1, p_fio_id: fioId })
  if (error) { if (isMissing(error)) return { row: null, missing: true }; throw new Error(error.message) }
  return { row: ((data as Tx[] | null) || [])[0] || null }
}

async function processQueue(ctx: Ctx, s: Summary, o: RunOpts, t0: number) {
  if (!ctx.caps.state) {
    // ── Zpracuj VŠECHNY nezpracované příchozí platby (i z dřívějšího běhu,
    //    kdyby předchozí invokace spadla uprostřed — crash-safe re-scan). ──
    const { data: pending } = await ctx.sb.from('fio_transactions').select(LEGACY_COLS)
      .eq('status', 'new').order('fio_id', { ascending: true }).limit(50)
    for (const p of (pending || []) as Tx[]) await processRow(ctx, p, s)
    return
  }
  const max = o.batch ?? 10
  const deadline = t0 + (o.budgetMs ?? 40_000)
  for (let i = 0; i < max && now(o.env) < deadline; i++) {
    const c = await claim(ctx, null)
    if (!c.row) break
    await processRow(ctx, c.row, s)
  }
}

export async function runSync(sb: Sb, o: RunOpts): Promise<{ status: number; body: Row }> {
  const t0 = now(o.env)
  const begin = await beginRun(sb, o.leaseSeconds ?? 180)
  if (begin.error) return { status: 200, body: { success: false, error: 'state_unavailable' } }
  if (!begin.acquired) return { status: 200, body: { success: true, skipped: 'busy' } }
  const caps: Caps = { state: begin.state, requests: begin.state }
  const ctx: Ctx = { sb, caps, env: o.env }
  const s = newSummary()
  const periods = caps.state && begin.info.reconcile_due === true
  const mode = periods ? 'periods' : 'last'
  let fetched = false
  try {
    if (!o.token) {
      if (!caps.state) { await debugLog(sb, 'missing_fio_token', 'warning', {}); return { status: 200, body: { success: false, error: 'missing_fio_token' } } }
      await processQueue(ctx, s, o, t0) // ručně spárované pohyby se potvrdí i bez tokenu
      await endRun(sb, caps, false, 'missing_fio_token', null, { reconcile: periods })
      return { status: 200, body: { success: false, error: 'missing_fio_token', ...s } }
    }

    // ── 1) Stáhni pohyby: od posledního stažení (Fio si posouvá zarážku), nebo za období ──
    const res = periods ? await fetchPeriod(o.token, String(begin.info.reconcile_from), String(begin.info.reconcile_to)) : await fetchLast(o.token)
    let txs: FioTx[] = []
    if (!res.ok) {
      if (res.rateLimited) {
        // Dotaz dřív než 30 s po předchozím — příští cron tick to dožene.
        if (!caps.state) return { status: 200, body: { success: true, skipped: 'rate_limited' } }
        await processQueue(ctx, s, o, t0)
        await endRun(sb, caps, null, 'rate_limited', 409, { reconcile: periods })
        return { status: 200, body: { success: true, skipped: 'rate_limited', ...s } }
      }
      if (!caps.state) {
        if (res.error === 'bad_response') {
          // dřív: neplatná odpověď = „prázdný výpis“ (beze stopy) — chování zůstává, přibyl jen záznam
          await debugLog(sb, 'fio_bad_response', 'warning', { http_status: res.http }, res.body || null)
        } else if (res.http > 0) {
          await debugLog(sb, 'fio_fetch_failed', 'error', { http_status: res.http }, (res.body || '').slice(0, 500))
          return { status: 200, body: { success: false, error: res.error } }
        } else throw new Error(res.body || res.error)
      } else {
        await processQueue(ctx, s, o, t0)
        await endRun(sb, caps, false, res.error, res.http || null, { reconcile: periods, recover: res.error === 'bad_response' })
        return { status: 200, body: { success: false, error: res.error, mode, ...s } }
      }
    } else txs = res.txs
    fetched = true
    s.fetched = txs.length

    // ── 2) Idempotentní zápis do fio_transactions (PK fio_id; duplicity skip) ──
    const st = await storeRows(ctx, txs)
    if (!st.ok) {
      if (!caps.state) {
        await debugLog(sb, 'fio_tx_insert_failed', 'error', { count: txs.length }, st.error)
        return { status: 200, body: { success: false, error: 'insert_failed' } }
      }
      await processQueue(ctx, s, o, t0)
      await endRun(sb, caps, false, 'insert_failed', 200, { reconcile: periods, recover: true, detail: st.error })
      return { status: 200, body: { success: false, error: 'insert_failed', mode, ...s } }
    }
    if (periods && st.inserted > 0) {
      // kontrola za období našla pohyby, které ve fio_transactions chyběly (jinak by se ztratily)
      await debugLog(sb, 'reconcile_recovered', 'warning', { inserted: st.inserted, from: begin.info.reconcile_from, to: begin.info.reconcile_to })
    }

    // ── 3) Zpracuj frontu ──
    await processQueue(ctx, s, o, t0)
    await endRun(sb, caps, true, null, 200, {
      iban: res.ok ? res.iban : null, id_last_download: res.ok ? (res.idTo ?? res.idLastDownload) : null,
      reconcile: periods, reconciled: periods,
    })
    return { status: 200, body: caps.state ? { success: true, mode, ...s } : legacySummary(s) }
  } catch (err) {
    console.error('[fio-sync] error:', err)
    const msg = (err as Error).message
    if (!caps.state) await debugLog(sb, 'sync_failed', 'error', {}, msg)
    await endRun(sb, caps, false, 'exception', null, { reconcile: periods, recover: fetched, detail: msg })
    return { status: 500, body: { success: false, error: msg } }
  }
}

/** Odpověď běhu ve tvaru před změnou (bez nových čítačů). */
const legacySummary = (s: Summary): Row => ({ success: true, fetched: s.fetched, confirmed: s.confirmed, surcharge: s.surcharge, no_match: s.no_match, mismatch: s.mismatch, review: s.review, errors: s.errors })

/** Zpracování JEDNOHO pohybu hned (Velín: po ručním spárování / vrácení ke zpracování). */
export async function processOne(sb: Sb, env: Env, fioId: number): Promise<Row> {
  const ctx: Ctx = { sb, caps: { state: true, requests: true }, env }
  let c: { row: Tx | null; missing?: boolean }
  try { c = await claim(ctx, fioId) } catch (e) { return { success: false, error: 'claim_failed', detail: (e as Error).message } }
  if (c.missing) return { success: false, error: 'bank_unavailable' }
  if (!c.row) {
    const { data } = await sb.from('fio_transactions').select('fio_id, status').eq('fio_id', fioId).maybeSingle()
    if (!data) return { success: false, error: 'not_found' }
    return { success: false, error: (data as { status?: string }).status === 'new' ? 'busy' : 'not_pending', status: (data as { status?: string }).status }
  }
  await processRow(ctx, c.row, newSummary())
  const { data: row } = await sb.from('fio_transactions')
    .select('fio_id, status, reason_code, note, target_type, booking_id, order_id, request_id, expected_amount, followup').eq('fio_id', fioId).maybeSingle()
  return { success: true, result: row || null }
}
