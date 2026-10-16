// ===== _shared/paid-change-failure.ts =====
// Zaplacená změna rezervace, kterou TRVALE nejde zapsat (motorku mezitím obsadila
// jiná rezervace — nová rezervace má přednost —, rezervace skončila / byla zrušená,
// den výměny uplynul…) — D6 + odpověď majitele 2026-10-16 (otázka 3): doplatek se
// zákazníkovi AUTOMATICKY vrátí, původní rezervace zůstane beze změny a obsluha dostane
// viditelný záznam: debug_log `paid_change_failed` + interní e-mail na info@ (uloží ho
// send-email do sent_emails s booking_id → Velín, Dokumenty → Zaslané maily / Dashboard).
// Jen JEDNOU na platbu (payRef) — první zapsaný řádek debug_log vyhrává, souběžný
// webhook / complete_extension skončí jako 'duplicate'; Stripe vratka má navíc klíč
// mg-pcf-<pi> a Stripe druhou vratku plně vrácené platby nepřipustí.
// Vratka jde VŽDY přímo ze Stripe z PaymentIntentu TÉTO platby (mg_source
// unapplied_change, charge.refunded ji do stavu rezervace nepromítá). K nezapsané změně
// nevznikl žádný doklad (DP), proto nevzniká ani dobropis, stav platby rezervace se
// nemění. Ukládá-li rezervace jako svou platbu právě tento doplatek (appka — process-payment
// ho uloží už při založení), vrátí se do bookings.stripe_payment_intent_id poslední platba,
// ze které se ještě dá vracet (storno z ní vychází; process-refund si navíc u vyčerpané
// uložené platby najde jinou sám). (Oprava 2026-10-16: dřív šla vratka u živé rezervace přes
// process-refund — ten přepsal bookings.stripe_payment_intent_id na doplatek, označil
// rezervaci jako „vráceno“ a vystavil dobropis bez DP; pozdější storno pak z původní
// platby nevrátilo nic.)
// `review` = nejednoznačný stav (stará platba mimo lhůtu / z doby před nasazením,
// rezervace už jezdí na nové motorce bez záznamu této platby) → žádná automatická
// vratka, obsluha zkontroluje, jestli je změna zapsaná, a případně vrátí ručně.
import type { Sb } from './extension-apply-types.ts'
import { lastRefundableIntent, type BookingIntentsStripe } from './booking-intents.ts'

type StripeRefundLike = {
  refunds: {
    create: (p: Record<string, unknown>, o?: Record<string, unknown>) => Promise<{ id: string }>
    list?: BookingIntentsStripe['refunds']['list']
  }
  checkout?: { sessions: { retrieve: (id: string) => Promise<{ payment_intent?: string | { id?: string } | null; metadata?: Record<string, string> | null }> } }
  paymentIntents?: BookingIntentsStripe['paymentIntents']
}

/** Po vrácení doplatku: když rezervace jako „svou" platbu ukládá právě vrácený doplatek
 *  (process-payment ho uložil při založení, appka), vrátit tam poslední platbu, ze které se
 *  ještě dá vracet (storno / vratka obsluhy z ní vychází). Jen když tam pořád je tenhle doplatek. */
async function restoreStoredIntent(sb: Sb, stripe: StripeRefundLike, bookingId: string, piId: string): Promise<string | null> {
  if (!stripe.paymentIntents?.search || !stripe.refunds.list) return null
  try {
    const { data } = await sb.from('bookings').select('stripe_payment_intent_id').eq('id', bookingId).maybeSingle()
    if (!data || data.stripe_payment_intent_id !== piId) return null
    const keep = await lastRefundableIntent(stripe as unknown as BookingIntentsStripe, sb, bookingId, piId)
    if (!keep) return null
    await sb.from('bookings').update({ stripe_payment_intent_id: keep }).eq('id', bookingId).eq('stripe_payment_intent_id', piId)
    return keep
  } catch { return null }
}

/** Důvody, kdy rezervace už neběží (zrušená / ukončená / vrácená). */
export const CLOSED_BOOKING_REASONS = new Set(['booking_cancelled', 'booking_completed', 'wrong_status', 'not_paid', 'not_found'])
/** Vybranou motorku mezitím obsadila jiná rezervace (ta má přednost). */
export const TAKEN_REASONS = new Set(['new_moto_unavailable', 'moto_unavailable'])

export type FailureMode = 'auto' | 'staff' | 'none' | 'duplicate'

const OPS_EMAIL = 'info@motogo24.cz'

/** Proč změnu nešlo zapsat — věta pro obsluhu (interní e-mail). */
export function failureReasonCs(reason: string): string {
  if (TAKEN_REASONS.has(reason)) {
    return 'Vybranou motorku mezitím obsadila jiná rezervace — nová rezervace má přednost, výměnu (změnu) proto nešlo zapsat.'
  }
  if (CLOSED_BOOKING_REASONS.has(reason)) return 'Rezervace mezitím skončila nebo byla zrušená.'
  if (reason === 'swap_date_out_of_range') return 'Den výměny mezitím uplynul (je mimo termín rezervace).'
  if (reason === 'license_insufficient') return 'Zákazník nemá na vybranou motorku potřebné řidičské oprávnění.'
  if (reason.startsWith('stale_payment')) return 'Platba je starší než lhůta automatického dokončení (nebo z doby před nasazením).'
  if (reason.startsWith('retry_exhausted')) return 'Změnu se ani po opakovaných pokusech (3 dny) nepodařilo zapsat.'
  return `Rezervace se mezitím změnila tak, že změnu nešlo zapsat (${reason}).`
}

/** PaymentIntent platby: `pi_…` přímo, Checkout Session `cs_…` přes Stripe. */
async function intentOf(stripe: StripeRefundLike | null | undefined, payRef: string): Promise<string | null> {
  if (payRef.startsWith('pi_')) return payRef
  if (!payRef.startsWith('cs_') || !stripe?.checkout) return null
  try {
    const s = await stripe.checkout.sessions.retrieve(payRef)
    const pi = typeof s.payment_intent === 'string' ? s.payment_intent : s.payment_intent?.id
    return pi && pi.startsWith('pi_') ? pi : null
  } catch { return null }
}

export async function handlePaidChangeFailure(sb: Sb, a: {
  bookingId: string; payRef: string; paidCzk: number; code: string; reason: string; via: string; autoRefund?: boolean; review?: boolean
  /** Stripe klient — doplatek se vrací přímo z PaymentIntentu této platby */
  stripe?: StripeRefundLike | null
}): Promise<FailureMode> {
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  // expect_refund: co se s doplatkem stane (souběžný dotaz complete_extension ho ukáže, než
  // první dokončovatel zapíše skutečný výsledek do response_data).
  const expect: FailureMode = a.paidCzk > 0 ? (a.autoRefund !== false && !a.review && !!a.stripe ? 'auto' : 'staff') : 'none'
  const reqData = { booking_id: a.bookingId, payment_ref: a.payRef, paid_czk: a.paidCzk, code: a.code, reason: a.reason, via: a.via, expect_refund: expect }

  // 1) Zámek „jednou na platbu": vlož svůj řádek a ověř, že je PRVNÍ.
  let myId: string | null = null
  try {
    const { data } = await sb.from('debug_log').insert({
      source: 'paid-change', action: 'paid_change_failed', component: 'stripe', status: 'error',
      error_message: `Zaplacenou změnu rezervace nešlo zapsat (${a.reason}).`, request_data: reqData,
    }).select('id').single()
    myId = data?.id ?? null
    const { data: first } = await sb.from('debug_log').select('id, response_data')
      .eq('action', 'paid_change_failed').eq('request_data->>payment_ref', a.payRef)
      .order('created_at', { ascending: true }).order('id', { ascending: true }).limit(1)
    if (first?.length && myId && first[0].id !== myId) {
      try { await sb.from('debug_log').delete().eq('id', myId) } catch { /* ignore */ }
      const prev = (first[0].response_data || {}) as { refund?: FailureMode }
      return prev.refund || 'duplicate'
    }
  } catch { /* bez zámku pokračuj — Stripe klíč mg-pcf + plná vratka druhou vratku nepřipustí */ }

  // 2) Vrácení doplatku přímo ze Stripe (celá tato platba; bez dobropisu, rezervace beze změny).
  let mode: FailureMode = 'none'
  let refundId: string | null = null
  let piId: string | null = null
  if (a.paidCzk > 0) {
    mode = 'staff'
    if (a.autoRefund !== false && !a.review && a.stripe) {
      piId = await intentOf(a.stripe, a.payRef)
      if (piId) {
        try {
          const r = await a.stripe.refunds.create({
            payment_intent: piId, amount: Math.round(a.paidCzk * 100), reason: 'requested_by_customer',
            metadata: { mg_source: 'unapplied_change', booking_id: a.bookingId, mg_reason: a.reason },
          }, { idempotencyKey: `mg-pcf-${piId}` })
          refundId = r?.id ?? null
          mode = 'auto'
        } catch {
          // Platba už je celá vrácená (souběžný dokončovatel bez zámku) → 'auto', jinak 'staff'.
          try {
            const rl = a.stripe.refunds.list ? await a.stripe.refunds.list({ payment_intent: piId, limit: 100 }) : null
            const back = (rl?.data || []).filter((x) => x.status === 'succeeded' || x.status === 'pending').reduce((s2, x) => s2 + Number(x.amount || 0), 0)
            if (back >= Math.round(a.paidCzk * 100)) mode = 'auto'
          } catch { /* zůstává 'staff' */ }
        }
      }
    }
  }
  const keptPi = mode === 'auto' && piId && a.stripe ? await restoreStoredIntent(sb, a.stripe, a.bookingId, piId) : null
  if (myId) {
    try {
      await sb.from('debug_log').update({ response_data: { refund: mode, refund_id: refundId, payment_intent_id: piId, kept_payment_intent_id: keptPi } })
        .eq('id', myId)
    } catch { /* ignore */ }
  }

  // 3) Interní upozornění obsluze (ne zákazníkovi) — uloží se i s booking_id (Velín).
  try {
    const num = a.bookingId.slice(-8).toUpperCase()
    const kc = `${a.paidCzk.toLocaleString('cs-CZ')} Kč`
    const why = failureReasonCs(a.reason)
    const what = a.review && mode === 'staff'
      ? `Platbu ${kc} nešlo zapsat automaticky. Zkontrolujte prosím, jestli je změna v rezervaci zapsaná; pokud ne, doplatek vraťte ručně ve Stripe (platba ${a.payRef}).`
      : mode === 'auto' ? `Doplatek ${kc} byl zákazníkovi automaticky vrácen na kartu (Stripe vratka ${refundId || '—'}; k nezapsané změně nevznikl doklad, proto ani dobropis).`
      : mode === 'staff' ? `Doplatek ${kc} se NEPODAŘILO vrátit automaticky — vraťte ho prosím ručně ve Stripe (platba ${a.payRef}).`
      : 'Nic se nestrhlo (doplatek do 1 Kč se neúčtuje).'
    const subject = TAKEN_REASONS.has(a.reason)
      ? `⚠️ Rezervace #${num}: motorka k výměně byla mezitím obsazená — ${mode === 'auto' ? 'doplatek vrácen' : 'doplatek vraťte'}`
      : `⚠️ Zaplacenou úpravu rezervace #${num} nešlo zapsat (${a.reason})`
    await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({
        to: OPS_EMAIL, booking_id: a.bookingId, subject,
        raw_html: `<h2 style="margin:0 0 8px;font-size:18px">Zaplacená změna rezervace #${num} se nezapsala</h2>`
          + `<p style="margin:0 0 8px">${why}</p>`
          + `<p style="margin:0 0 8px">${what}</p>`
          + `<p style="margin:0;color:#6b7280;font-size:12px">${a.review ? 'Automaticky se nic nezměnilo.' : 'Původní rezervace zůstala beze změny.'} Kód ${a.reason} (${a.via}), platba ${a.payRef}. Detail: debug_log, akce paid_change_failed.</p>`,
      }),
    })
  } catch { /* ignore */ }
  return mode
}
