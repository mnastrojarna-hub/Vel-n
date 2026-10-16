// ===== _shared/extension-apply.ts =====
// Dokončení ZAPLACENÉ změny rezervace server-side (D6, 2026-10-16) — sdílí
// webhook-receiver (payment_intent.succeeded / checkout.session.completed) a
// process-payment (action complete_extension, odpuštění doplatku do 1 Kč).
// Idempotentní: změna sloupců se deduplikuje přes payment_ref v historii, výměna
// motorky přes trvalou značku platby (payment_ref v historii — split_booking_moto_swap
// rev.12, SQL 20261016p3) a důkaz provedení OD vytvoření platby (záznam výměny /
// navazující rezervace B), NIKDY jen podle aktuální motorky rezervace.
import type { ApplyArgs, ApplyResult, Sb } from './extension-apply-types.ts'
import { chgDigest, isMissingFunction, logDebug, otherPaymentEntry, round2 } from './extension-apply-types.ts'
import { applyColumnChange } from './extension-apply-columns.ts'

export type { ApplyArgs, ApplyResult, Sb } from './extension-apply-types.ts'
export { chgDigest, chgFromMetadata, placeFingerprint, round2 } from './extension-apply-types.ts'

/** Kódy split_booking_moto_swap, které znamenají, že výměnu už nejde provést. */
const SWAP_PERMANENT = new Set(['new_moto_unavailable', 'wrong_status', 'not_paid', 'swap_date_out_of_range',
  'not_found', 'forbidden', 'license_insufficient', 'trailer_staffed_only'])
/** Rezervace už jezdí na nové motorce / už rozdělená, ale bez důkazu z TÉTO platby
 *  → nejednoznačné (výměnu mohla udělat obsluha) → bez automatické vratky. */
const SWAP_AMBIGUOUS = new Set(['invalid_new_moto', 'already_split'])

export async function applyPaidExtension(sb: Sb, args: ApplyArgs): Promise<ApplyResult> {
  if (!args.chg) return { state: 'no_payload' }
  let a: Record<string, unknown>
  try { a = JSON.parse(args.chg) as Record<string, unknown> } catch { return { state: 'no_payload' } }
  if (!a || typeof a !== 'object') return { state: 'no_payload' }
  let srv: Record<string, unknown> = {}
  try { if (args.srv) srv = (JSON.parse(args.srv) || {}) as Record<string, unknown> } catch { srv = {} }

  const swap = a._swap as { m?: string; d?: string; t?: string } | undefined
  if (swap && typeof swap === 'object' && swap.m && swap.d) {
    return await commitSwap(sb, args, { m: swap.m, d: swap.d, t: swap.t })
  }
  const hash = await chgDigest(args.chg)
  const gear = a._gear as { sizes?: Record<string, unknown> } | undefined
  if (gear && typeof gear === 'object') return await applyGear(sb, args, gear.sizes || {}, hash)
  return await applyColumnChange(sb, a, args, srv, hash)
}

/** Je TATO výměna už provedená? Důkaz: (1) záznam s payment_ref této platby v historii
 *  rezervace A; (2) od vytvoření platby (`since`) záznam REPLACE na novou motorku, nebo
 *  navazující rezervace B (i zrušená) na nové motorce od dne výměny. Aktuální motorka
 *  rezervace sama o sobě důkazem NENÍ (mohla ji změnit bezplatná výměna / obsluha). */
export async function swapDone(sb: Sb, bookingId: string, swap: { m: string; d: string },
  payRef: string | null | undefined, since: string | null | undefined): Promise<string | null> {
  return (await swapEvidence(sb, bookingId, swap, payRef, since))?.id ?? null
}

/** Jako swapDone + `own` = výměnu zapsala TATO platba (značka payment_ref, rev.12 —
 *  dorovnání je v ní); `other` = zapsala ji JINÁ platba od vytvoření této (značka jiné
 *  platby → tahle je navíc, duplicita); jinak ji provedl klient bez značky (web po
 *  návratu ze Stripe / appka ≤ 4.1.3). */
async function swapEvidence(sb: Sb, bookingId: string, swap: { m: string; d: string },
  payRef: string | null | undefined, since: string | null | undefined): Promise<{ id: string; own: boolean; other?: string } | null> {
  try {
    const { data: bk } = await sb.from('bookings').select('id, modification_history').eq('id', bookingId).maybeSingle()
    const hist = Array.isArray(bk?.modification_history) ? (bk.modification_history as Array<Record<string, unknown> | null>) : []
    const ms = (v: unknown) => { const t = Date.parse(String(v || '')); return Number.isFinite(t) ? t : 0 }
    const nextB = async (sinceMs: number | null) => {
      const { data: next } = await sb.from('bookings').select('id, moto_id, start_date, created_at')
        .eq('continues_booking_id', bookingId).limit(10)
      const hit = (next || []).find((b: Record<string, unknown>) => b.moto_id === swap.m
        && String(b.start_date || '').slice(0, 10) === swap.d.slice(0, 10)
        && (sinceMs == null || ms(b.created_at) >= sinceMs))
      return hit ? String(hit.id) : null
    }
    const own = payRef ? hist.find((h) => !!h && h.payment_ref === payRef) : undefined
    if (own) return { id: own.type === 'moto_swap_shorten' ? ((await nextB(null)) || bookingId) : bookingId, own: true }
    if (!since || !ms(since)) return null
    const s = ms(since) - 60_000 // rezerva na rozdíl hodin Stripe ↔ DB
    // Záznam výměny na TUTÉŽ motorku od vytvoření platby; nese-li značku jiné platby → duplicita.
    const otherRef = (type: string) => {
      const e = hist.find((h) => !!h && h.type === type && h.new_moto_id === swap.m && otherPaymentEntry(h, payRef, ms(since)))
      return e ? String(e.payment_ref) : undefined
    }
    const rep = hist.find((h) => !!h && h.type === 'moto_swap_replace' && h.new_moto_id === swap.m && ms(h.at) >= s)
    if (rep) return { id: bookingId, own: false, other: otherRef('moto_swap_replace') }
    const b = await nextB(s)
    return b ? { id: b, own: false, other: otherRef('moto_swap_shorten') } : null
  } catch { return null }
}

async function commitSwap(sb: Sb, args: ApplyArgs, swap: { m: string; d: string; t?: string }): Promise<ApplyResult> {
  const bookingId = args.bookingId
  const r = round2(Number(args.rounding || 0))
  const ev0 = await swapEvidence(sb, bookingId, swap, args.payRef, args.since)
  if (ev0) return await settleEvidence(sb, args, swap, ev0, r, 'pre')
  const base: Record<string, unknown> = {
    p_booking_id: bookingId, p_new_moto_id: swap.m, p_swap_date: swap.d,
    p_swap_time: swap.t || null, p_dry_run: false,
  }
  // rev.12 (SQL 20261016p3): zaplacená částka (dorovnání spočítá RPC z ceny při zápisu)
  // + značka platby (opakovaný COMMIT téže platby se neprovede podruhé).
  const full: Record<string, unknown> = { ...base, p_payment_ref: args.payRef || null }
  if (args.paidCzk != null && Number.isFinite(args.paidCzk)) full.p_paid = round2(args.paidCzk)
  else if (r !== 0) full.p_card_rounding = r
  const call = async (p: Record<string, unknown>) => {
    try {
      const res = await sb.rpc('split_booking_moto_swap', p)
      return { data: (res.data || null) as Record<string, unknown> | null, error: (res.error || null) as { code?: string; message?: string } | null }
    } catch (e) { return { data: null, error: { message: (e as Error).message } } }
  }
  let { data, error } = await call(full)
  let legacy = false
  if (error && isMissingFunction(error) && r === 0) {
    if ((args.via || 'webhook') !== 'webhook') {
      // rev.12 ještě nenasazená: 6parametrová verze nemá značku platby ani zámek řádku —
      // webhook a appka by tutéž výměnu zapsaly současně dvakrát (cena + doplatek 2×).
      // Zapisuje ji proto JEN webhook; appka (fronta) / process-payment to zkusí později.
      await logDebug(sb, 'swap_commit_deferred', 'info', { booking_id: bookingId, swap, payment_ref: args.payRef, via: args.via })
      return { state: 'retry', code: 'swap_webhook_only', detail: 'split_booking_moto_swap rev.12 not deployed' }
    }
    // rev.12 ještě nenasazená a není co dorovnat → 6parametrová verze (bez značky platby;
    // opakování hlídá důkaz výše).
    legacy = true
    ;({ data, error } = await call(base))
  }

  let out: ApplyResult
  if (error) {
    out = !legacy && isMissingFunction(error)
      ? { state: 'retry', code: 'rounding_unavailable', detail: error.message }
      : { state: 'retry', code: 'apply_failed', detail: error.message }
  } else if (data?.success === true) {
    out = { state: data.already_applied === true ? 'already_applied' : 'applied', bookingId,
      newBookingId: data.new_booking_id && String(data.new_booking_id) !== bookingId ? String(data.new_booking_id) : undefined }
  } else {
    const code = String(data?.error || 'unknown')
    const ev = await swapEvidence(sb, bookingId, swap, args.payRef, args.since)
    if (ev) out = await settleEvidence(sb, args, swap, ev, r, 'post')
    else if (SWAP_AMBIGUOUS.has(code)) out = { state: 'failed', code: 'change_failed', reason: code, manual: true }
    else if (SWAP_PERMANENT.has(code)) out = { state: 'failed', code: 'change_failed', reason: code }
    else out = { state: 'retry', code: 'apply_failed', detail: code }
  }
  const ok = out.state === 'applied' || out.state === 'already_applied' || out.state === 'duplicate'
  await logDebug(sb, ok ? 'swap_commit_applied' : 'swap_commit_failed', ok ? 'ok' : 'error',
    { booking_id: bookingId, swap, card_rounding: r, paid_czk: args.paidCzk, payment_ref: args.payRef, legacy, state: out.state, rpc_result: data },
    error?.message || (data && data.success !== true ? String(data.error || '') : null))
  return out
}

/** Výměna už je provedená (důkaz) → výsledek: TATO platba = already_applied; JINÁ platba
 *  (značka jiné platby) = duplicate (bez dorovnání — to patří té první platbě); klient bez
 *  značky (web po návratu ze Stripe) = dopsat dorovnání této platby jednou + already_applied. */
async function settleEvidence(sb: Sb, args: ApplyArgs, swap: { m: string; d: string },
  ev: { id: string; own: boolean; other?: string }, r: number, phase: string): Promise<ApplyResult> {
  const bookingId = args.bookingId
  const newBookingId = ev.id !== bookingId ? ev.id : undefined
  if (!ev.own && ev.other) {
    await logDebug(sb, 'swap_commit_duplicate', 'error', { booking_id: bookingId, swap, payment_ref: args.payRef, other_ref: ev.other, phase })
    return { state: 'duplicate', bookingId, otherRef: ev.other, newBookingId }
  }
  if (r !== 0 && !ev.own) {
    const fx = await roundingFixup(sb, ev.id, r, args, null)
    if (fx) return fx
  }
  await logDebug(sb, 'swap_commit_applied', 'ok', { booking_id: bookingId, swap, payment_ref: args.payRef, state: 'already_applied', evidence: phase })
  return { state: 'already_applied', bookingId, newBookingId }
}

/** Placená změna výbavy (web) — apply_paid_gear_change je idempotentní (net vůči aktuálnímu
 *  stavu). D1: dorovnání / odpuštění (r) se zapíše hned po ní do ceny i card_rounding se
 *  záznamem v historii (payment_ref = deduplikace opakování, chg_hash = pozná se tatáž
 *  změna zaplacená JINOU platbou → duplicate, dorovnání se nepřičte podruhé). */
async function applyGear(sb: Sb, args: ApplyArgs, sizes: Record<string, unknown>, hash: string | null): Promise<ApplyResult> {
  const bookingId = args.bookingId
  let data: Record<string, unknown> | null = null
  let error: { code?: string; message?: string } | null = null
  try {
    const res = await sb.rpc('apply_paid_gear_change', { p_booking_id: bookingId, p_sizes: sizes })
    data = (res.data || null) as Record<string, unknown> | null
    error = res.error || null
  } catch (e) { error = { message: (e as Error).message } }
  const failed = !error && data && data.success === false
  await logDebug(sb, error || failed ? 'gear_change_apply_failed' : 'gear_change_applied', error || failed ? 'error' : 'ok',
    { booking_id: bookingId, rpc_result: data }, error?.message || (failed ? String(data?.error || '') : null))
  if (error) return isMissingFunction(error) ? { state: 'no_payload' } : { state: 'retry', code: 'apply_failed', detail: error.message }
  if (failed) return { state: 'failed', code: 'change_failed', reason: String(data?.error || 'gear_failed') }
  const r = round2(Number(args.rounding || 0))
  if (r !== 0) {
    // RPC nic nezměnila (net 0) a tutéž změnu (chg_hash) od vytvoření platby zaplatila JINÁ platba → duplicita.
    if (hash && Number(data?.net_diff ?? NaN) === 0) {
      const other = await otherRefWithHash(sb, bookingId, hash, args)
      if (other) {
        await logDebug(sb, 'gear_change_duplicate', 'error', { booking_id: bookingId, payment_ref: args.payRef, other_ref: other })
        return { state: 'duplicate', bookingId, otherRef: other }
      }
    }
    const rr = await roundingFixup(sb, bookingId, r, args, hash)
    if (rr) return rr
  }
  return { state: 'applied', bookingId }
}

async function otherRefWithHash(sb: Sb, bookingId: string, hash: string, args: ApplyArgs): Promise<string | null> {
  try {
    const { data } = await sb.from('bookings').select('modification_history').eq('id', bookingId).maybeSingle()
    const hist = Array.isArray(data?.modification_history) ? (data.modification_history as Array<Record<string, unknown> | null>) : []
    const sinceMs = args.since ? Date.parse(args.since) : NaN
    const e = hist.find((h) => !!h && h.chg_hash === hash && otherPaymentEntry(h, args.payRef, Number.isFinite(sinceMs) ? sinceMs : null))
    return e ? String(e.payment_ref) : null
  } catch { return null }
}

/** Dorovnání (r) do ceny a card_rounding rezervace `targetId` + záznam s payment_ref v její
 *  historii (deduplikace opakování) — u placené výbavy a u výměny, kterou provedl klient
 *  bez dorovnání. null = hotovo (nebo už dřív), jinak výsledek k vrácení (retry). */
async function roundingFixup(sb: Sb, targetId: string, r: number, args: ApplyArgs, hash: string | null): Promise<ApplyResult | null> {
  const bookingId = targetId
  for (let pass = 0; pass < 2; pass++) {
    const { data: cur, error } = await sb.from('bookings').select('*').eq('id', bookingId).maybeSingle()
    if (error || !cur) return { state: 'retry', code: 'read_failed', detail: error?.message }
    const hist = Array.isArray(cur.modification_history) ? [...(cur.modification_history as Array<Record<string, unknown> | null>)] : []
    if (args.payRef && hist.some((h) => !!h && h.payment_ref === args.payRef)) return null
    if (!('card_rounding' in cur)) {
      if (args.paidCzk != null && args.paidCzk > 0 && Math.abs(r) < 1) return null
      return { state: 'retry', code: 'rounding_unavailable' }
    }
    hist.push({ at: new Date().toISOString(), type: 'card_rounding', source: 'stripe_webhook', card_rounding: r,
      ...(args.paidCzk != null ? { price_diff: Math.round(args.paidCzk) } : {}), ...(args.payRef ? { payment_ref: args.payRef } : {}),
      ...(hash ? { chg_hash: hash } : {}) })
    let q = sb.from('bookings').update({ total_price: round2(Number(cur.total_price || 0) + r),
      card_rounding: round2(Number(cur.card_rounding || 0) + r), modification_history: hist }).eq('id', bookingId)
    if (cur.updated_at) q = q.eq('updated_at', cur.updated_at)
    const { data: upd, error: uErr } = await q.select('id')
    if (uErr) return { state: 'retry', code: 'apply_failed', detail: uErr.message }
    if (Array.isArray(upd) && upd.length === 1) return null
  }
  return { state: 'retry', code: 'concurrent_update' }
}
