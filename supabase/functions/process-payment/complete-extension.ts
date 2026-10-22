// ===== process-payment/complete-extension.ts =====
// D6 (2026-10-16): `action: 'complete_extension'` — appka (trvalá fronta
// PaidChangeQueue) po zaplacení výměny / úpravy požádá server, ať změnu dokončí.
// Stejná idempotentní logika jako webhook (payment_ref v historii, značka platby
// u výměny), takže webhook i appka mohou dokončovat současně bez dvojího zápisu.
// Starou / vrácenou / už vyhodnocenou platbu NEzapisuje (paid-change-guard):
// jinak by šlo přehrát výměnu po bezplatné výměně zpět (motorka zdarma) nebo zapsat
// změnu, za kterou se peníze už vrátily.
// Web (odpověď majitele 2026-10-16, otázka 3): po návratu z hosted Checkoutu pošle
// `session_id` (cs_…) místo `payment_intent_id` — metadata změny nese Checkout Session
// (PaymentIntent webové platby je nemá). Web tak dostane autoritativní výsledek
// včetně „motorka je mezitím obsazená" (reason new_moto_unavailable + vratka).
// Odpovědi (HTTP 200, není-li uvedeno jinak):
//   {success:true,  state:'applied'|'already_applied', booking_id, new_booking_id?, total_price?}
//   {success:true,  state:'already_applied', duplicate_refunded:true}  tutéž změnu zaplatila a zapsala
//     JINÁ platba → změna platí, tahle druhá platba se vrací celá (duplicate-payment)
//   {success:true,  state:'client_apply'}                 změna se do metadat nevešla (stará cesta)
//   {success:false, state:'pending',  code:'payment_processing' | 'payment_unconfirmed'}  HTTP 202
//     (unconfirmed = requires_action / requires_confirmation: 3D Secure ještě běží —
//      appka položku fronty NEmaže, dokud platba neskončí zaplacením nebo zrušením)
//   {success:false, state:'retry',    code:'apply_failed' | 'rounding_unavailable'}  HTTP 503
//   {success:false, state:'failed',   code:'change_failed', reason, refund:'auto'|'staff', amount, change_kind?}
//     (reason new_moto_unavailable = motorku mezitím obsadila jiná rezervace — ta má přednost;
//      change_kind 'swap' | 'moto' | 'edit' = co se nezapsalo — web podle toho nabídne další krok)
//   {success:false, state:'failed',   code:'stale_payment', reason:'refunded'|'stale_payment', refund}  HTTP 409
//   {success:false, state:'not_paid', code:'not_paid'}
//   chyby: 401 auth_required · 403 forbidden · 404 not_found · 409 not_extension · 503 stripe_unavailable
import { stripe as stripeLive } from './stripe-customer.ts'
import { authClassify } from '../_shared/auth.ts'
import { applyPaidExtension, chgFromMetadata } from '../_shared/extension-apply.ts'
import { handlePaidChangeFailure, TAKEN_REASONS } from '../_shared/paid-change-failure.ts'
import { paidChangeEligibility, markApplied, markPaidAfterChange, QUEUE_MAX_AGE_H, PREVIOUS_MAX_AGE_H } from '../_shared/paid-change-guard.ts'
import { refundDuplicatePayment, type StripeDupLike } from '../_shared/duplicate-payment.ts'
import { CS, refuse, respond } from './refusals.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
// deno-lint-ignore no-explicit-any
type StripeAny = any
type Who = { kind: string; userId?: string | null }
export type CompleteDeps = { stripe?: StripeAny; auth?: (req: Request) => Promise<Who> }

/** Text trvalého selhání: obsazená motorka má vlastní větu (nová rezervace má přednost) —
 *  i když doplatek vrací obsluha (vratka ze Stripe selhala / přibalená e-shop objednávka). */
export const failedText = (reason: string | null | undefined, staff: boolean) => {
  const taken = !!reason && TAKEN_REASONS.has(reason)
  return staff ? (taken ? CS.change_failed_taken_staff : CS.change_failed_staff) : (taken ? CS.change_failed_taken : CS.change_failed)
}

/** Druh zaplacené změny z metadat (web podle něj nabídne „Vybrat jinou motorku" na správné
 *  záložce i bez lokálního záznamu prohlížeče): výměna (`_swap`), změna motorky v termínu
 *  (`p_new_moto_id`), jiná úprava. Bez čitelného payloadu → null (pole se neposílá). */
export function changeKind(md: Record<string, string | undefined>): 'swap' | 'moto' | 'edit' | null {
  try {
    const c = JSON.parse(chgFromMetadata(md) || 'null') as Record<string, unknown> | null
    if (!c || typeof c !== 'object') return null
    if (c._swap && typeof c._swap === 'object') return 'swap'
    return c.p_new_moto_id ? 'moto' : 'edit'
  } catch { return null }
}

/** Web: Checkout Session doplatku → {piId, metadata, paidCzk} nebo hotová odpověď (nezaplaceno / cizí). */
export async function resolveWebSession(stripe: StripeAny, sessionId: string):
  Promise<{ piId: string; md: Record<string, string>; paidCzk: number | null } | { response: Response }> {
  let sess
  try {
    sess = await stripe.checkout.sessions.retrieve(sessionId)
  } catch (e) {
    const err = e as { code?: string; statusCode?: number }
    if (err.code === 'resource_missing' || err.statusCode === 404) return { response: refuse(404, 'not_found', {}, CS.payment_not_found) }
    return { response: refuse(503, 'stripe_unavailable') }
  }
  const md = (sess?.metadata || {}) as Record<string, string>
  if (md.type !== 'extension' || !md.booking_id) return { response: refuse(409, 'not_extension') }
  const piId = typeof sess.payment_intent === 'string' ? sess.payment_intent : sess.payment_intent?.id
  if (sess.payment_status !== 'paid' || !piId) {
    // otevřená session = platba ještě běží (zákazník je na stránce Stripe); prošlá = nezaplaceno
    return { response: sess.status === 'open'
      ? respond(202, { success: false, state: 'pending', code: 'payment_processing', error: CS.payment_processing, booking_id: md.booking_id })
      : respond(200, { success: false, state: 'not_paid', code: 'not_paid', error: CS.payment_not_paid, booking_id: md.booking_id }) }
  }
  return { piId, md, paidCzk: sess.amount_total != null ? Number(sess.amount_total) / 100 : null }
}

export async function handleCompleteExtension(req: Request, body: Record<string, unknown>, sb: Sb, deps: CompleteDeps = {}): Promise<Response> {
  const stripe = deps.stripe ?? stripeLive
  const who = await (deps.auth ?? authClassify)(req)
  if (who.kind === 'none') return refuse(401, 'auth_required')
  let piId = String(body.payment_intent_id || '')
  const sessionId = String(body.session_id || '')
  let web: { md: Record<string, string>; paidCzk: number | null } | null = null
  if (!piId && /^cs_[A-Za-z0-9_]+$/.test(sessionId)) {
    const ws = await resolveWebSession(stripe, sessionId)
    if ('response' in ws) return ws.response
    piId = ws.piId
    web = { md: ws.md, paidCzk: ws.paidCzk }
  }
  if (!/^pi_[A-Za-z0-9_]+$/.test(piId)) return refuse(404, 'not_found', {}, CS.payment_not_found)

  let pi
  try {
    pi = await stripe.paymentIntents.retrieve(piId, { expand: ['latest_charge'] })
  } catch (e) {
    const err = e as { code?: string; statusCode?: number }
    if (err.code === 'resource_missing' || err.statusCode === 404) return refuse(404, 'not_found', {}, CS.payment_not_found)
    return refuse(503, 'stripe_unavailable')
  }
  // Web: metadata změny jsou na session (PaymentIntent je nemá) — značky platby (applied_at,
  // duplicate_of) z PaymentIntentu mají přednost.
  const md = { ...(web ? web.md : {}), ...((pi.metadata || {}) as Record<string, string>) } as Record<string, string>
  const bookingId = md.booking_id
  if (md.type !== 'extension' || !bookingId) return refuse(409, 'not_extension')

  const { data: bk, error: bkErr } = await sb.from('bookings').select('user_id').eq('id', bookingId).maybeSingle()
  if (bkErr) return refuse(503, 'server_error')
  if (!bk) return refuse(404, 'not_found', {}, CS.not_found)
  const owner = who.kind === 'service' || who.kind === 'admin' || (who.kind === 'user' && !!who.userId && who.userId === bk.user_id)
  if (!owner) return refuse(403, 'forbidden', {}, CS.forbidden_edit)

  if (pi.status === 'processing' || pi.status === 'requires_capture') {
    return respond(202, { success: false, state: 'pending', code: 'payment_processing', error: CS.payment_processing, booking_id: bookingId })
  }
  if (pi.status === 'requires_action' || pi.status === 'requires_confirmation') {
    // Ověření u banky (3D Secure) ještě běží — „nezaplaceno" by appce smazalo pojistku
    // ve frontě přesně ve chvíli, kdy ji potřebuje (zabití appky během 3DS).
    return respond(202, { success: false, state: 'pending', code: 'payment_unconfirmed', error: CS.payment_unconfirmed, booking_id: bookingId })
  }
  // requires_payment_method (zamítnuto / opuštěno) | canceled → nezaplaceno.
  if (pi.status !== 'succeeded') {
    return respond(200, { success: false, state: 'not_paid', code: 'not_paid', error: CS.payment_not_paid, booking_id: bookingId })
  }

  const paidCzk = web?.paidCzk ?? (pi.amount_received || pi.amount || 0) / 100
  const kind = changeKind(md)
  const kindField = kind ? { change_kind: kind } : {}
  // Web Checkout nenese attempt_id / chg_hash (ty má jen PaymentIntent z appky) → lhůta 72 h.
  const el = await paidChangeEligibility(sb, { ...pi, metadata: md }, { bookingId, requireNewCode: !web,
    maxAgeH: web ? PREVIOUS_MAX_AGE_H : QUEUE_MAX_AGE_H, stripe })
  if (!el.ok) {
    if (el.kind === 'applied') {
      return respond(200, { success: true, state: 'already_applied', booking_id: bookingId, new_booking_id: null, total_price: null })
    }
    if (el.kind === 'duplicate') {
      return respond(200, { success: true, state: 'already_applied', duplicate_refunded: true, booking_id: bookingId, new_booking_id: null, total_price: null })
    }
    if (el.kind === 'failed') {
      const staff = el.refund === 'staff' || el.refund === 'none'
      return respond(200, {
        success: false, state: 'failed', code: 'change_failed', reason: el.reason,
        error: failedText(el.reason, staff), refund: staff ? 'staff' : 'auto', amount: paidCzk, booking_id: bookingId, ...kindField,
      })
    }
    if (el.kind === 'refunded') {
      return respond(409, { success: false, state: 'failed', code: 'stale_payment', reason: 'refunded', error: CS.stale_payment_refunded,
        refund: 'auto', amount: paidCzk, booking_id: bookingId })
    }
    // Platba z doby před nasazením nebo mimo lhůtu fronty → nic automaticky, obsluha zkontroluje.
    await handlePaidChangeFailure(sb, { bookingId, payRef: pi.id, paidCzk, code: 'stale_payment', reason: `stale_payment:${el.why}`,
      via: 'complete_extension', review: true })
    return respond(409, { success: false, state: 'failed', code: 'stale_payment', reason: 'stale_payment', error: CS.stale_payment,
      refund: 'staff', amount: paidCzk, booking_id: bookingId })
  }

  const r = await applyPaidExtension(sb, {
    bookingId, chg: chgFromMetadata(md), srv: md.srv || null, paidCzk, payRef: pi.id,
    rounding: Number(md.card_rounding || 0) || 0, since: new Date(pi.created * 1000).toISOString(), via: 'complete_extension',
  })
  if (r.state === 'duplicate') {
    // Tutéž změnu už zapsala jiná platba → změna platí; tahle platba se vrací celá.
    await refundDuplicatePayment(sb, stripe as unknown as StripeDupLike, { piId: pi.id, table: 'bookings', refId: bookingId,
      keepRef: r.otherRef, amountCzk: paidCzk, via: 'complete_extension', autoRefund: !md.shop_order_id })
    return respond(200, { success: true, state: 'already_applied', duplicate_refunded: true, booking_id: bookingId,
      new_booking_id: r.newBookingId ?? null, total_price: null })
  }
  if (r.state === 'applied' || r.state === 'already_applied') {
    await markApplied(stripe, pi.id)
    await markPaidAfterChange(sb, bookingId)
    return respond(200, { success: true, state: r.state, booking_id: bookingId, new_booking_id: r.newBookingId ?? null, total_price: r.totalPrice ?? null })
  }
  if (r.state === 'no_payload') return respond(200, { success: true, state: 'client_apply', booking_id: bookingId })
  if (r.state === 'retry') {
    const code = r.code === 'rounding_unavailable' ? 'rounding_unavailable' : 'apply_failed'
    return respond(503, { success: false, state: 'retry', code, error: CS.apply_failed, booking_id: bookingId })
  }
  const mode = await handlePaidChangeFailure(sb, {
    bookingId, payRef: pi.id, paidCzk, code: r.code, reason: r.reason, via: 'complete_extension', review: r.manual === true,
    autoRefund: !md.shop_order_id, stripe,
  })
  const staff = mode === 'staff' || mode === 'none'
  return respond(200, {
    success: false, state: 'failed', code: 'change_failed', reason: r.reason, error: failedText(r.reason, staff),
    refund: staff ? 'staff' : 'auto', amount: paidCzk, booking_id: bookingId, ...kindField,
  })
}
