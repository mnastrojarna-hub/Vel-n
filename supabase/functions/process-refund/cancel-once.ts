// HOTFIX storno 2026-10-29 — vratka storna nejvýš JEDNOU za storno rezervace.
// Dřív dostalo DRUHÉ volání téže storno vratky (send-cancellation-email po Velínu, když Stripe
// vratka čekala „pending“ nebo process-refund spadl po refunds.create; webhook charge.refunded
// doručený znovu po 30min okně claimu mailu; ruční vratka v Stripe dashboardu později) NOVÝ Stripe
// idempotency klíč (`refundable` už první vratku odečetl) a vrátilo peníze podruhé.
//  • Zámek: claim_email_send(booking, 'refund_cancellation') — souběžná storno volání téže
//    rezervace jdou po sobě (uvolní se po doběhnutí, jinak vyprší za LOCK_WINDOW_MIN).
//  • Značka: každá storno vratka nese v metadatech mg_cancel_at = bookings.cancelled_at (identita
//    storna; po obnovení a novém stornu je jiná). Porovnává se OKAMŽIK, ne text.
//  • Server (send-cancellation-email → reason 'cancellation'): ke stornu, ke kterému už naše storno
//    vratka existuje (succeeded/pending), žádnou další nevytvoří — jen dorovná stav platby a dobropis.
//  • Obsluha (Velín): vědomá další vratka („Potvrdit vrácení“ jiné částky) projde; zastaví se jen
//    DUPLICITA téhož požadavku — stejná částka ≤ 3 min (dvojité odeslání, i když první vratka čeká
//    „pending“), nebo vratka vzniklá, zatímco volání čekalo na zámek (souběžný dvojklik / dvě okna).
//    Dřív (bez zámku) duplicitu srazil stejný Stripe idempotency klíč; zámek ji jinak rozbil.
//  • Vratka z více plateb (dev f1–f3, sloučeno 2026-11-05): storno = HLAVNÍ vratka (mg_cancel_at, mg_target =
//    požadovaná částka celého storna, mg_cancel_total = vráceno k tomuto stornu celkem vč. této vratky —
//    pro pojistný mail webhooku) + zbytek z ostatních plateb rezervace (mg_part 'remainder', mg_main_refund,
//    též mg_cancel_at). Hlavní vratka může jít z JINÉ platby než z uložené (mainSource), proto se kontrola
//    dělá nad vratkami VŠECH plateb rezervace (cancel-once-pool.ts) a „vratka tohoto storna" = hlavní vratka;
//    opakované volání nevrácený zbytek TÉHOŽ storna jen dovrátí do mg_target (idempotentně) — žádná nová vratka.

type Md = Record<string, string | undefined>
export type StripeRefundLike = { id: string; amount: number; status: string; created: number; metadata?: Md | null; charge?: unknown; payment_intent?: unknown }
type CnResult = { creditNoteId: string | null; pdfPath: string | null; refundId: string | null }
type Card = { brand: string | null; last4: string | null }
// deno-lint-ignore no-explicit-any
type Db = any

export const CANCEL_LOCK_SLUG = 'refund_cancellation'
const LOCK_WINDOW_MIN = 3
const LOCK_WAIT_MS = 8000
const LOCK_POLL_MS = 250
// Vratka z verze před hotfixem (bez mg_cancel_at): k tomuto stornu patří, vznikla-li nejdřív hodinu
// před bookings.cancelled_at (Velín zapisuje čas prohlížeče — tolerance posunutých hodin).
const LEGACY_SLACK_MS = 60 * 60_000
const CLOCK_SLACK_S = 2 // hodiny Stripe vs. edge
const DUP_WINDOW_S = LOCK_WINDOW_MIN * 60
// Vratka mladší než tohle, zatímco zámek drží jiné volání = to ji ještě dokončuje (stav, dobropis).
const FRESH_MS = 60_000

/** Identita storna = bookings.cancelled_at (timestamptz z PostgRESTu). */
export function cancelToken(cancelledAt: unknown): string {
  return typeof cancelledAt === 'string' ? cancelledAt : ''
}

/** timestamptz → klíč okamžiku na mikrosekundy ('Z' i '+00:00', ořezané koncové nuly). */
export function instantKey(s: unknown): string | null {
  if (typeof s !== 'string' || !s) return null
  const ms = Date.parse(s)
  if (!Number.isFinite(ms)) return null
  return `${ms}.${((/\.(\d+)/.exec(s)?.[1]) || '').padEnd(6, '0').slice(3, 6)}`
}

const live = (r: StripeRefundLike) => r.status === 'succeeded' || r.status === 'pending'
/** Naše storno vratka této rezervace (hlavní i zbytek z jiné platby). */
function oursAny(r: StripeRefundLike, bookingId: string): boolean {
  const md = r.metadata || {}
  return live(r) && md.mg_source === 'process-refund' && md.mg_reason === 'cancellation' && md.mg_booking_id === bookingId
}
/** Naše HLAVNÍ storno vratka (zbytek z ostatních plateb — mg_part 'remainder' — patří k ní). */
function ours(r: StripeRefundLike, bookingId: string): boolean {
  return oursAny(r, bookingId) && r.metadata?.mg_part !== 'remainder'
}

/** Celá vratka storna k hlavní vratce (haléře): hlavní + zbytek z ostatních plateb (mg_main_refund). */
export function logicalRefundHaleru(main: StripeRefundLike, refunds: StripeRefundLike[] | null | undefined): number {
  return Number(main.amount || 0) + (refunds || []).filter((r) => live(r) && r.id !== main.id && r.metadata?.mg_main_refund === main.id)
    .reduce((s, r) => s + Number(r.amount || 0), 0)
}

/** Požadovaná částka celého storna z metadat hlavní vratky (mg_target, haléře); null = neznámá (starší vratka). */
export function cancelTargetHaleru(main: StripeRefundLike): number | null {
  const t = Number(main.metadata?.mg_target)
  return Number.isFinite(t) && t > 0 ? Math.round(t) : null
}

/** Už vráceno k TOMUTO stornu (haléře): hlavní vratky storna + jejich zbytky z ostatních plateb. */
export function cancellationRefundedHaleru(refunds: StripeRefundLike[] | null | undefined, bookingId: string, token: string): number {
  return priorCancellationRefunds(refunds, bookingId, token).reduce((s, m) => s + logicalRefundHaleru(m, refunds), 0)
}

/** Cíl celého storna (haléře) = mg_cancel_total NEJNOVĚJŠÍ hlavní vratky tohoto storna (poslední rozhodnutí —
 *  obsluha mohla chybějící zbytek po pádu vrátit vědomě sama; oprava i1 2026-11-05: dovrácení staršího mg_target
 *  by ho vrátilo podruhé). null = neznámý (starší vratky bez mg_cancel_total). */
export function cancellationGoalHaleru(refunds: StripeRefundLike[] | null | undefined, bookingId: string, token: string): number | null {
  const newest = priorCancellationRefunds(refunds, bookingId, token)[0]
  const t = Number(newest?.metadata?.mg_cancel_total)
  return Number.isFinite(t) && t > 0 ? Math.round(t) : null
}

/** Kolik k TOMUTO stornu jako celku ještě chybí (haléře); null = cíl neznámý. */
export function cancellationMissingHaleru(refunds: StripeRefundLike[] | null | undefined, bookingId: string, token: string): number | null {
  const goal = cancellationGoalHaleru(refunds, bookingId, token)
  return goal == null ? null : Math.max(0, goal - cancellationRefundedHaleru(refunds, bookingId, token))
}

/** Hlavní vratky storna s nedokončeným zbytkem (mg_target > vráceno k ní) — jen dokud stornu jako celku něco chybí
 *  (cíl = nejnovější rozhodnutí); nejnovější první. */
export function openCancelMains(refunds: StripeRefundLike[] | null | undefined, bookingId: string, token: string): StripeRefundLike[] {
  if (cancellationMissingHaleru(refunds, bookingId, token) === 0) return []
  return priorCancellationRefunds(refunds, bookingId, token)
    .filter((m) => { const t = cancelTargetHaleru(m); return t != null && logicalRefundHaleru(m, refunds) < t })
}

/** Zámek drží jiné volání a vratka je čerstvá → to ji právě dokončuje (nebo isolate zabitý — viz respondExistingCancelRefund). */
export function cancelBusy(prior: StripeRefundLike, lockHeld: boolean, nowMs = Date.now()): boolean {
  return !lockHeld && nowMs - Number(prior.created) * 1000 < FRESH_MS
}

/** Naše HLAVNÍ vratky TOHOTO storna (succeeded/pending), v pořadí ze Stripe (nejnovější první). */
export function priorCancellationRefunds(refunds: StripeRefundLike[] | null | undefined, bookingId: string, token: string): StripeRefundLike[] {
  const t = Date.parse(token), key = instantKey(token)
  return (refunds || []).filter((r) => {
    if (!ours(r, bookingId)) return false
    const at = r.metadata?.mg_cancel_at
    if (typeof at === 'string') return at === token || (key != null && instantKey(at) === key)
    return !token || !Number.isFinite(t) || Number(r.created) * 1000 >= t - LEGACY_SLACK_MS
  })
}

/** Obsluha: duplicita téhož požadavku — stejná částka ≤ 3 min, nebo (bez částky) vratka vzniklá při čekání na zámek. */
export function duplicateAdminRefunds(refunds: StripeRefundLike[] | null | undefined, bookingId: string,
  o: { amountHaleru: number | null; nowS: number; lock: CancelLock | null }): StripeRefundLike[] {
  const since = o.lock?.waited ? o.lock.sinceS : null
  return (refunds || []).filter((r) => {
    if (!ours(r, bookingId)) return false
    const c = Number(r.created)
    if (o.amountHaleru != null && o.amountHaleru > 0) {
      // stejná částka = hlavní vratka (jedna platba), požadavek celého storna (mg_target, více plateb), nebo požadavek
      // vč. části zaplacené převodem (mg_requested — i2: ruční dobropis vedle vratky kartou)
      const same = Number(r.amount) === o.amountHaleru || cancelTargetHaleru(r) === o.amountHaleru
        || Number(r.metadata?.mg_requested) === o.amountHaleru
      return same && c >= Math.min(o.nowS - DUP_WINDOW_S, since ?? Infinity)
    }
    return since != null && c >= since
  })
}

export type CancelLock = { held: boolean; waited: boolean; sinceS: number | null }

/** Od kdy drží zámek jiné volání (jeho vratka vznikla až potom); bez údaje = teď. */
async function lockSinceS(supabase: Db, bookingId: string): Promise<number> {
  const now = Math.floor(Date.now() / 1000) - CLOCK_SLACK_S
  try {
    const { data } = await supabase.from('email_send_locks').select('locked_at')
      .eq('booking_id', bookingId).eq('template_slug', CANCEL_LOCK_SLUG).maybeSingle()
    const v = data?.locked_at
    const ms = typeof v === 'number' ? v : Date.parse(String(v ?? ''))
    return Number.isFinite(ms) ? Math.min(now, Math.floor(ms / 1000) - CLOCK_SLACK_S) : now
  } catch { return now }
}

/** Zámek storno vratky rezervace (čeká až LOCK_WAIT_MS). held=false = bez zámku (RPC chybí / stále drženo). */
export async function acquireCancelLock(supabase: Db, bookingId: string): Promise<CancelLock> {
  const until = Date.now() + LOCK_WAIT_MS
  let sinceS: number | null = null
  const out = (held: boolean): CancelLock => ({ held, waited: sinceS != null, sinceS })
  for (;;) {
    try {
      const { data, error } = await supabase.rpc('claim_email_send', {
        p_booking_id: bookingId, p_slug: CANCEL_LOCK_SLUG, p_window_minutes: LOCK_WINDOW_MIN,
      })
      if (error) return out(false)
      if (data === true) return out(true)
    } catch { return out(false) }
    if (sinceS == null) sinceS = await lockSinceS(supabase, bookingId)
    if (Date.now() >= until) return out(false)
    await new Promise((r) => setTimeout(r, LOCK_POLL_MS))
  }
}

export async function releaseCancelLock(supabase: Db, bookingId: string): Promise<void> {
  try {
    await supabase.from('email_send_locks').delete().eq('booking_id', bookingId).eq('template_slug', CANCEL_LOCK_SLUG)
  } catch { /* vyprší samo */ }
}

/** Stav platby nezná vratku storna (process-refund spadl po refunds.create): uložená vratka chybí nebo je STARŠÍ.
 *  Oprava i2 (2026-11-05): 'refund_pending' u vratky, kterou Stripe mezitím dokončil (status 'succeeded'; vznikla
 *  „pending“ při nízkém zůstatku a refund.updated se dřív nezpracovával) = také zaostává → každé další volání ho
 *  dorovná. Výjimka `manualPending`: k rezervaci je živý RUČNÍ dobropis (část ceny placená převodem — obsluha ji
 *  teprve posílá), 'refund_pending' je správně („Čeká na vrácení“ ve Velíně). */
export function statusLags(cur: Record<string, any>, prior: StripeRefundLike, refunds: StripeRefundLike[] | null | undefined,
  manualPending = false): boolean {
  if (!['paid', 'refund_pending', 'partial_refund'].includes(cur.payment_status)) return false
  const stored = cur.stripe_refund_id || null
  // i4: čekající zbytek z jiné platby (mg_main_refund) → 'refund_pending' je správně, dokud ho Stripe nedokončí
  if (stored === prior.id) return cur.payment_status === 'refund_pending' && prior.status === 'succeeded' && !manualPending
    && !remainderPending(prior, refunds)
  if (!stored) return true
  const s = (refunds || []).find((r) => r.id === stored)
  return !!s && Number(s.created) <= Number(prior.created)
}

/** Oprava i4 (2026-11-07): zbytek storna z jiné platby (mg_main_refund = hlavní vratka) Stripe ještě nedokončil. */
export function remainderPending(main: StripeRefundLike, refunds: StripeRefundLike[] | null | undefined): boolean {
  return (refunds || []).some((r) => r.id !== main.id && r.status === 'pending' && r.metadata?.mg_main_refund === main.id)
}

/** Živý ruční dobropis rezervace (bez Stripe vratky) = část vratky posílá obsluha převodem (i2). Chyba → false. */
export async function hasLiveManualCreditNote(supabase: Db, bookingId: string): Promise<boolean> {
  try {
    const { data, error } = await supabase.from('invoices').select('id').eq('booking_id', bookingId).eq('type', 'credit_note')
      .neq('status', 'cancelled').is('stripe_refund_id', null).limit(1)
    return !error && Array.isArray(data) && data.length > 0
  } catch { return false }
}

async function findCn(supabase: Db, bookingId: string, refundId: string): Promise<CnResult> {
  try {
    const { data } = await supabase.from('invoices').select('id, pdf_path')
      .eq('booking_id', bookingId).eq('type', 'credit_note').eq('stripe_refund_id', refundId).neq('status', 'cancelled').limit(1)
    return { creditNoteId: data?.[0]?.id ?? null, pdfPath: data?.[0]?.pdf_path ?? null, refundId }
  } catch { return { creditNoteId: null, pdfPath: null, refundId } }
}

/** Vratka tohoto storna už existuje → žádný nový Stripe refund; dorovnat stav + dobropis a vrátit ji. */
export async function respondExistingCancelRefund(o: {
  supabase: Db; bookingId: string; token: string; prior: StripeRefundLike; refunds: StripeRefundLike[] | null
  refundableHaleru: number | null; lockHeld: boolean
  /** kdo volá: služba (send-cancellation-email, trigger, webhook — smí dostat 503 a zkusit to znovu) / obsluha (Velín) */
  callerKind?: 'service' | 'admin'
  /** zámek drží jiné volání (nebo zabitý isolate) a stornu chybí zbytek → upozornit obsluhu (oprava i1 2026-11-05) */
  onDeferred?: (a: { refundId: string; targetHaleru: number; refundedHaleru: number }) => Promise<void>
  /** více plateb: dovrátí nevrácený zbytek TÉHOŽ storna do mg_target (vrací haléře vrácené teď, 0 = nic) — cancel-once-pool.ts */
  complete?: (prior: StripeRefundLike) => Promise<number>
  /** více plateb: co po vratce zbývá na platbách V CENĚ rezervace (haléře; null = nevím) — místo refundableHaleru */
  remaining?: () => Promise<number | null>
  createCn: (supabase: Db, bookingId: string, bk: { stripe_refund_id: string }) => Promise<CnResult>
  ensureCn: (supabase: Db, bookingId: string, bk: { stripe_refund_id: string }) => Promise<CnResult>
  cardOf: (r: StripeRefundLike) => Promise<Card | null>
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown
  headers: Record<string, string>
}): Promise<Response> {
  const { supabase, bookingId, prior } = o
  const { data: cur } = await supabase.from('bookings')
    .select('payment_status, stripe_refund_id, card_brand, card_last4').eq('id', bookingId).maybeSingle()
  // Zámek drží jiné volání a vratka je čerstvá → to ji právě dokončuje (stav, dobropis): nesahat,
  // jen vrátit existující dobropis (souběžný INSERT by vystavil druhý; attach smyčka mailu počká).
  const busy = cancelBusy(prior, o.lockHeld)
  const card: Card = { brand: cur?.card_brand ?? null, last4: cur?.card_last4 ?? null }
  // Oprava i1 (2026-11-05): zámek po ZABITÉM isolatu (finally neproběhl, řádek email_send_locks zůstal až 3 min) —
  // každé další volání do 60 s od vratky vypadalo jako souběh a stornu s nevráceným zbytkem (mg_target > vráceno)
  // nikdo nic neřekl ani nic nezkusilo znovu. Teď: chyba do debug_log + mail obsluze (dedup) a službě 503, ať
  // webhook (charge.refunded → retryNeeded) / send-cancellation-email zkusí znovu po vypršení zámku.
  const target = cancelTargetHaleru(prior)
  const refundedH = logicalRefundHaleru(prior, o.refunds)
  // Oprava i2 (2026-11-05): částky celého storna pro volajícího (webhook charge.refunded → pojistný storno mail):
  // vráceno k tomuto stornu celkem (všechny hlavní vratky + zbytky) a cíl storna (mg_cancel_total nejnovější hlavní
  // vratky). Dřív si webhook bral mg_cancel_total = „už vráceno + POŽADAVEK“ a po selhání zbytku tvrdil zákazníkovi
  // celou částku, i když odešla jen část.
  const amounts = (fresh: number) => {
    const done = cancellationRefundedHaleru(o.refunds, o.bookingId, o.token) + fresh
    const goal = cancellationGoalHaleru(o.refunds, o.bookingId, o.token) ?? (target != null ? Math.max(target, done) : null)
    return { refunded_haleru: refundedH + fresh, target_haleru: target, cancel_refunded_haleru: done, cancel_goal_haleru: goal,
      refund_deferred: goal != null && done < goal }
  }
  if (busy && target != null && refundedH < target) {
    await o.dlog('cancellation_remainder_deferred', 'error', { refund_id: prior.id, target_haleru: target, refunded_haleru: refundedH,
      cancel_token: o.token, caller: o.callerKind || null })
    if (o.onDeferred) await o.onDeferred({ refundId: prior.id, targetHaleru: target, refundedHaleru: refundedH }).catch(() => {})
    if (o.callerKind === 'service') {
      return new Response(JSON.stringify({ success: false, code: 'cancellation_in_progress', retry: true, refund_id: prior.id, status: prior.status,
        ...amounts(0), error: 'Vratka storna se právě dokončuje — zkuste to znovu za chvíli.' }), { status: 503, headers: o.headers })
    }
  }
  let repaired = false
  // Pád mezi hlavní vratkou a zbytkem z ostatních plateb → dovrátit (idempotentně) a stav / dobropis dorovnat.
  const fresh = !busy && o.complete ? await o.complete(prior).catch(() => 0) : 0
  const completed = fresh > 0
  const open = !!cur && ['paid', 'refund_pending', 'partial_refund'].includes(cur.payment_status)
  // i2: 'refund_pending' s dokončenou vratkou = zaostává, pokud obsluha neposílá ruční část převodem (živý ruční dobropis)
  const manualPending = !!cur && cur.payment_status === 'refund_pending' && (cur.stripe_refund_id || null) === prior.id
    && prior.status === 'succeeded' ? await hasLiveManualCreditNote(supabase, bookingId) : false
  if (!busy && cur && (statusLags(cur, prior, o.refunds, manualPending) || (completed && open))) {
    // process-refund spadl po refunds.create a před zápisem stavu → dopsat, co by zapsal sám.
    const left = o.remaining ? await o.remaining().catch(() => null) : o.refundableHaleru
    const patch: Record<string, unknown> = { stripe_refund_id: prior.id,
      payment_status: prior.status === 'pending' || remainderPending(prior, o.refunds) ? 'refund_pending' : (left === 0 ? 'refunded' : 'partial_refund') }
    if (!card.brand || !card.last4) {
      const c = await o.cardOf(prior).catch(() => null)
      if (c?.brand && !card.brand) patch.card_brand = card.brand = c.brand
      if (c?.last4 && !card.last4) patch.card_last4 = card.last4 = c.last4
    }
    await supabase.from('bookings').update(patch).eq('id', bookingId)
    repaired = true
  }
  let cn: CnResult
  if (busy) cn = await findCn(supabase, bookingId, prior.id)
  else {
    cn = await o.createCn(supabase, bookingId, { stripe_refund_id: prior.id })
    if (cn.creditNoteId && !cn.pdfPath) cn = await o.ensureCn(supabase, bookingId, { stripe_refund_id: prior.id })
  }
  await o.dlog('cancellation_refund_exists', 'info', {
    refund_id: prior.id, refund_status: prior.status, cancel_token: o.token, credit_note_id: cn.creditNoteId, busy, repaired, completed,
  })
  return new Response(JSON.stringify({
    success: true, already_refunded: true, cancellation_refund_exists: true,
    refund_id: prior.id, status: prior.status, credit_note_id: cn.creditNoteId, credit_note_pdf_path: cn.pdfPath,
    card_brand: card.brand, card_last4: card.last4, ...amounts(fresh),
  }), { status: 200, headers: o.headers })
}
