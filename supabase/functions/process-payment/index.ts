// ===== MotoGo24 – Edge Function: Process Payment (Stripe LIVE) =====
// Supports booking, shop, extension, and SOS payments via Stripe Checkout or inline PaymentIntent.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'
import { stripe, SITE_URL, PRODUCT_NAMES, CORS, PaymentType, PaymentRequest, getOrCreateStripeCustomer, resolveStripeLocale } from './stripe-customer.ts'
import { authClassify } from '../_shared/auth.ts'
import { handleWebBookingCheckout, handleWebShopCheckout, handleSosPaymentLink } from './payment-flows.ts'
import { isTrustedCaller, forbidden } from '../_shared/auth.ts'
// D1–D6 (2026-10-16): minimum karty 15 Kč, ochrana proti dvojí platbě, kódy
// odmítnutí bez kontaktů, dokončení zaplacené změny — logika v modulech:
import { placeFingerprint, applyPaidExtension, chgFromMetadata, swapDone } from '../_shared/extension-apply.ts'
import { handlePaidChangeFailure } from '../_shared/paid-change-failure.ts'
import { paidChangeEligibility, markApplied, historyHasRef, PREVIOUS_MAX_AGE_H } from '../_shared/paid-change-guard.ts'
import { classifyDue, bookingRoundingAvailable, gearRoundingAvailable, round2, CARD_MIN_CZK, type DueClass } from './card-minimum.ts'
import { CS, refuse, respond, declineMessageCs, SWAP_DRY_CODES, cancelledReasonKey } from './refusals.ts'
import { mapStripeError, isUncertainStripeError } from './stripe-errors.ts'
import { sanitizeAttemptId, chgHash, idempotencyKey, guardStoredIntent, storeIntentId, markCheckoutStarted, sameAttempt, findRecentLiveIntent } from './intent-guard.ts'
import { waiveBookingFlow, waiveShopFlow, waiveExtensionFlow, voucherProblem, waiveRef, restoreRefusal } from './pp-waiver.ts'
import { priceAppChange } from './app-change-price.ts'
import { handleCompleteExtension } from './complete-extension.ts'
import { roundingLabel, editLineLabel } from './checkout-labels.ts'
import { refundDuplicatePayment, type StripeDupLike } from '../_shared/duplicate-payment.ts'
import { settleMatchingSessions, type StripeCheckoutLike } from './checkout-guard.ts'
import { floorCheck, freeVerifiedByFloor } from './floor-check.ts'
import { duplicateRow } from '../_shared/duplicate-payment.ts'
import { failureRow } from '../_shared/paid-change-guard.ts'
import { verifyShopSession, type StripeSessionsLike } from './verify-shop-session.ts'

/** Dokončená web session doplatku už zpracovaná (zapsaná / vyhodnocená / vrácená) → další úpravu neblokuje. */
// deno-lint-ignore no-explicit-any
async function extensionSettled(sb: any, bookingId: string, piId: string | null, md: Record<string, string>, sessionId: string): Promise<boolean> {
  if (md.applied_at || md.duplicate_of) return true
  for (const ref of [piId, sessionId]) {
    if (ref && (await historyHasRef(sb, bookingId, ref) || await failureRow(sb, ref) || await duplicateRow(sb, ref))) return true
  }
  return false
}

/** Doprodej v rezervaci (feature flag reservation_upsell, Velín) — zapnutý? Nenačtený = zapnutý
 *  (přebytek nad cenou se pak jako dosud nepovažuje za chybu — raději neodmítnout platbu). */
// deno-lint-ignore no-explicit-any
async function upsellEnabled(sb: any): Promise<boolean> {
  try {
    const { data, error } = await sb.from('feature_flags').select('enabled').eq('key', 'reservation_upsell').maybeSingle()
    if (error) return true
    return !!data && data.enabled === true
  } catch { return true }
}

/** Návratová adresa webu po odpuštěném doplatku (stejná validace jako success_url Checkoutu).
 *  Bez Stripe se zástupný `{CHECKOUT_SESSION_ID}` nedosadí → parametr session_id se vynechá. */
function safeRedirect(u: string | undefined | null): string | null {
  if (!u) return null
  try {
    const p = new URL(u)
    if (p.protocol !== 'https:' && p.protocol !== 'http:') return null
    if (/CHECKOUT_SESSION_ID/.test(p.searchParams.get('session_id') || '')) {
      p.searchParams.delete('session_id')
      return p.toString()
    }
    return u
  } catch { return null }
}

/** Web: odpuštěný doplatek (≤ 1 Kč) server už zapsal — `waived=1` řekne webu, že nic neplatil
 *  a změnu nemá zapisovat znovu ani ukazovat „Platba potvrzena". Starší web parametr ignoruje. */
function waivedRedirect(u: string): string {
  try {
    const p = new URL(u)
    p.searchParams.set('waived', '1')
    return p.toString()
  } catch { return u }
}

/** Web úprava rezervace (hosted Checkout): návrat ze Stripe nese id Checkout Session, aby se web
 *  zeptal serveru na výsledek (`complete_extension` se session_id) — i u jádra webu, které
 *  success_url skládá samo bez session_id. */
function withSessionParam(u: string): string {
  if (u.includes('{CHECKOUT_SESSION_ID}')) return u
  return u + (u.includes('?') ? '&' : '?') + 'session_id={CHECKOUT_SESSION_ID}'
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  try {
    const body: PaymentRequest = await req.json()

    // --- Sync fallback: ověř Stripe setup-mode session a potvrď free booking ---
    // Volá /potvrzeni page, pokud webhook ještě nepotvrdil booking. Nezávislé na
    // event delivery — jistota, že 0 Kč rezervace dojde do paid stavu i bez webhooku.
    if ((body as Record<string, unknown>).action === 'verify_setup_session') {
      const sessionId = (body as Record<string, unknown>).session_id as string | undefined
      if (!sessionId) {
        return new Response(JSON.stringify({ success: false, error: 'Missing session_id' }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      )
      try {
        const session = await stripe.checkout.sessions.retrieve(sessionId)
        const md = (session.metadata || {}) as Record<string, string>
        if (session.status !== 'complete' || session.mode !== 'setup' || md.action !== 'verify_free_booking') {
          return new Response(JSON.stringify({ success: false, status: session.status, mode: session.mode }),
            { headers: { ...CORS, 'Content-Type': 'application/json' } })
        }
        const bookingId = md.booking_id || (session.client_reference_id as string | null) || null
        if (!bookingId) {
          return new Response(JSON.stringify({ success: false, error: 'No booking_id in session' }),
            { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
        }
        const { data: bk } = await supabaseAdmin.from('bookings')
          .select('payment_status').eq('id', bookingId).single()
        if (bk?.payment_status === 'paid') {
          return new Response(JSON.stringify({ success: true, already_paid: true, booking_id: bookingId }),
            { headers: { ...CORS, 'Content-Type': 'application/json' } })
        }
        // ATOMIC confirm_payment — RPC vrací was_already_paid, takže paralelní webhook
        // + naše fallback volání se navzájem nezduplikují (jen jeden pošle mail).
        const { data: confirmData, error: rpcErr } = await supabaseAdmin.rpc('confirm_payment', {
          p_booking_id: bookingId, p_method: 'card',
        })
        if (rpcErr) {
          try {
            await supabaseAdmin.from('debug_log').insert({
              source: 'process-payment', action: 'verify_setup_session_failed',
              component: 'free_booking', status: 'error',
              error_message: rpcErr.message,
              request_data: { session_id: sessionId, booking_id: bookingId },
            })
          } catch { /* ignore */ }
          return new Response(JSON.stringify({ success: false, error: rpcErr.message }),
            { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } })
        }
        const wasAlreadyPaid = !!(confirmData as Record<string, unknown> | null)?.was_already_paid
        try {
          await supabaseAdmin.from('debug_log').insert({
            source: 'process-payment', action: 'verify_setup_session_confirmed',
            component: 'free_booking', status: 'ok',
            request_data: { session_id: sessionId, booking_id: bookingId, was_already_paid: wasAlreadyPaid },
          })
        } catch { /* ignore */ }
        // Jen jedna paralelní cesta posílá mail — pokud webhook stihl dřív (was_already_paid=true),
        // skipujeme. Jinak posíláme booking_reserved (stejný flow jako confirmBookingPayment).
        if (!wasAlreadyPaid) {
          try {
            const { data: booking } = await supabaseAdmin.from('bookings')
              .select('booking_source, start_date, end_date, total_price, motorcycles!moto_id(model, manual_url), profiles(full_name, email)')
              .eq('id', bookingId).single()
            const profile = (booking?.profiles ?? null) as { full_name?: string; email?: string } | null
            if (profile?.email) {
              const moto = (booking?.motorcycles ?? null) as { model?: string; manual_url?: string } | null
              const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
              const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
              await fetch(`${SUPABASE_URL}/functions/v1/send-booking-email`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY },
                body: JSON.stringify({
                  type: 'booking_reserved',
                  booking_id: bookingId,
                  customer_email: profile.email,
                  customer_name: profile.full_name || '',
                  motorcycle: moto?.model || '',
                  start_date: booking?.start_date,
                  end_date: booking?.end_date,
                  total_price: booking?.total_price,
                  source: booking?.booking_source || 'web',
                  manual_url: moto?.manual_url || '',
                }),
              })
            }
          } catch (e) {
            try {
              await supabaseAdmin.from('debug_log').insert({
                source: 'process-payment', action: 'verify_setup_session_mail_failed',
                component: 'free_booking', status: 'error',
                error_message: (e as Error).message,
                request_data: { session_id: sessionId, booking_id: bookingId },
              })
            } catch { /* ignore */ }
          }
        }
        return new Response(JSON.stringify({ success: true, confirmed: true, booking_id: bookingId, already_paid: wasAlreadyPaid }),
          { headers: { ...CORS, 'Content-Type': 'application/json' } })
      } catch (e) {
        return new Response(JSON.stringify({ success: false, error: (e as Error).message }),
          { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }
    }

    // --- Sync fallback: ověř Stripe SHOP session a potvrď voucher/e-shop objednávku ---
    // (stránka /potvrzeni; logika + D2 dorovnání před potvrzením ve verify-shop-session.ts)
    if ((body as Record<string, unknown>).action === 'verify_shop_session') {
      return await verifyShopSession(body as unknown as Record<string, unknown>, {
        sb: createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!),
        stripe: stripe as unknown as StripeSessionsLike,
        supabaseUrl: Deno.env.get('SUPABASE_URL') ?? '',
        serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      })
    }

    // --- Velín operátor: Stripe odkaz pro placenou SOS náhradu ---
    // BEZPEČNOST 2026-10-11: jen aktivní admin libovolné role (Velín NewIncidentModal,
    // pravidlo jako is_admin()) nebo service klíč — částka je z požadavku a zaplacení
    // odkazu označí rezervaci paid + active (webhook confirmSosPayment).
    if ((body as Record<string, unknown>).action === 'create_sos_payment_link') {
      if (!(await isTrustedCaller(req))) return forbidden(CORS, 'trusted_caller_only')
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      )
      return await handleSosPaymentLink(body, supabaseAdmin)
    }

    // --- D6 (2026-10-16): dokončení zaplacené změny rezervace (appka, trvalá fronta) ---
    if ((body as unknown as Record<string, unknown>).action === 'complete_extension') {
      const sbCx = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')
      return await handleCompleteExtension(req, body as unknown as Record<string, unknown>, sbCx)
    }

    // --- Web anonymous checkout (no auth required) ---
    if (body.source === 'web' && body.booking_id) {
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      )
      return await handleWebBookingCheckout(body, supabaseAdmin)
    }

    // --- Web anonymous SHOP checkout (voucher purchase, no auth required) ---
    if (body.source === 'web' && (body as Record<string, unknown>).customer_email && body.type === 'shop') {
      return await handleWebShopCheckout(body)
    }

    const { incident_id, amount, currency, method, type, mode, payment_method_id, change } = body
    const paymentType: PaymentType = type || 'booking'
    // BEZPEČNOST 2026-10-11: jen známé typy (appka booking/extension/sos/shop, web
    // booking/extension/shop). Neznámý typ dřív bez přihlášení založil PI a přepsal
    // libovolné rezervaci bookings.stripe_payment_intent_id. U 'shop' se booking_id
    // ignoruje (appka ho neposílá; vlastník se ověřuje jen u objednávky).
    if (!['booking', 'shop', 'extension', 'sos'].includes(paymentType)) {
      return refuse(400, 'invalid_type')
    }
    const booking_id = paymentType === 'shop' ? undefined : body.booking_id
    // `let` — u rezervačních typů se cizí/nečekající order_id zahodí (viz níže).
    let order_id = body.order_id
    const paymentMode = mode || 'intent'
    const explicitSuccessUrl = (body as Record<string, unknown>).success_url as string | undefined
    const explicitCancelUrl = (body as Record<string, unknown>).cancel_url as string | undefined
    // D1/D4 (2026-10-16): nová appka posílá `card_min: true` (umí dorovnání na 15 Kč
    // a odpuštění do 1 Kč) a `attempt_id` (jedno klepnutí „Zaplatit" = jeden klíč).
    // `card_min` platí jen pro PaymentIntent appky. Hosted Checkout (web) dorovnává sám na
    // serveru (po SQL 20261016p1): `checkoutRounding` + samostatná položka „Dorovnání…" na
    // stránce Stripe; odpuštění do 1 Kč zapíše změnu bez platby (waiveExtensionFlow).
    const rawBody = body as unknown as Record<string, unknown>
    const cardMin = rawBody.card_min === true && paymentMode === 'intent'
    const attemptId = sanitizeAttemptId(rawBody.attempt_id)
    const savedCardReq = !!payment_method_id
    let dueClass: DueClass | null = null
    // D1/D2: dorovnání k zápisu do ceny AŽ PO zaplacení (webhook) — due = cena řádku, r = dorovnání.
    let chargeRounding: { due: number; r: number } | null = null
    // D1 (web hosted Checkout, doplatek 1–15 Kč): Stripe stránka ukáže doplatek + dorovnání.
    let checkoutRounding: { due: number; r: number } | null = null

    // Validate required fields
    if ((paymentType === 'booking' || paymentType === 'extension' || paymentType === 'sos') && !booking_id) {
      return refuse(400, 'missing_booking_id')
    }

    // -- Duplicate payment guard --
    if (paymentType === 'booking' && booking_id) {
      const tmpSupabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      )
      const { data: bk } = await tmpSupabase.from('bookings')
        .select('payment_status, status')
        .eq('id', booking_id)
        .single()
      if (bk?.payment_status === 'paid') {
        // „už zaplaceno" = pro appku úspěch (already_paid), pro starou appku jasný text.
        return refuse(409, 'already_paid', { already_paid: true, booking_id })
      }
    }
    if (paymentType === 'shop' && !order_id) {
      return refuse(400, 'missing_order_id')
    }
    if (amount == null || !Number.isFinite(Number(amount))) {
      return refuse(400, 'invalid_amount')
    }

    // ── E-shop z appky: částku určuje SERVER (2026-09-24) ─────────────────
    // Dřív se strhla částka poslaná appkou a k libovolnému order_id — cenu
    // tak určoval klient. Nově: jen vlastník, jen čekající objednávka a částka
    // MUSÍ odpovídat shop_orders.total (počítá create_shop_order ze serverových
    // cen, 20260924b). Jiná částka = odmítnuto (nedoplatek se nesmí stát).
    // Web (source 'web' + customer_email) sem nechodí — handleWebShopCheckout
    // výše si cenu bere z DB sám.
    if (paymentType === 'shop') {
      const who = await authClassify(req)
      if (who.kind === 'none') return refuse(401, 'auth_required')
      const sbShop = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      )
      // `*`: sloupec card_rounding existuje až po SQL 20261016p1 (detekce nasazení).
      const { data: ord } = await sbShop.from('shop_orders')
        .select('*')
        .eq('id', order_id!).maybeSingle()
      if (!ord) return refuse(404, 'order_not_found')
      const owner = who.kind === 'service' || who.kind === 'admin' ||
        (who.kind === 'user' && !!who.userId && who.userId === ord.customer_id)
      if (!owner) return refuse(403, 'forbidden', {}, CS.forbidden_shop)
      if (ord.payment_status === 'paid') return refuse(409, 'already_paid', { already_paid: true, order_id }, CS.already_paid_shop)
      if (ord.payment_status !== 'pending') return refuse(409, 'wrong_status', {}, CS.wrong_status_shop)
      const due = round2(Number(ord.total) || 0)
      if (due <= 0) return refuse(409, 'no_payment_needed')
      const shopRounding = 'card_rounding' in ord
      // D2 (2026-10-16): objednávka do 1 Kč se neúčtuje, 1–15 Kč se platí 15 Kč
      // (cenu objednávky počítá server — create_shop_order — takže ji není třeba ověřovat).
      dueClass = classifyDue(due, Number(amount), cardMin)
      if (dueClass.kind === 'waive') {
        const g = await guardStoredIntent(stripe, { storedPiId: ord.stripe_payment_intent_id, type: 'shop', refKey: 'order_id',
          refId: order_id!, sheet: false, chargeCents: 0, chg: null, reuseOpen: false })
        if (g.action === 'refuse') return refuse(409, 'payment_in_progress', { payment_intent_id: g.piId, pi_status: g.status })
        return await waiveShopFlow(sbShop, order_id!, due, savedCardReq)
      }
      if (dueClass.kind === 'below') {
        return refuse(400, 'below_minimum', { due, min: CARD_MIN_CZK, charge: CARD_MIN_CZK, update_required: !cardMin },
          cardMin ? CS.below_minimum_app : undefined)
      }
      if (dueClass.kind === 'round') {
        // Dorovnání se do objednávky zapíše až PO zaplacení (webhook, metadata due/card_rounding).
        if (!shopRounding) return refuse(409, 'rounding_unavailable')
        chargeRounding = { due, r: dueClass.rounding }
      } else if (Math.round(Number(amount)) !== Math.round(due)) {
        return refuse(409, 'amount_mismatch', { server_total: Math.round(due) }, CS.amount_mismatch_shop)
      } else if (shopRounding) {
        // Platba v celých Kč u ceny s haléři (99,50 → 100) — rozdíl jako zaokrouhlení na dokladu.
        const sub = round2(Math.round(Number(amount) * 100) / 100 - due)
        if (sub !== 0 && Math.abs(sub) < 1) chargeRounding = { due, r: sub }
      }
    }

    // ── Rezervace / SOS / doplatek: kdo platí a kolik hlídá SERVER (2026-10-11) ──
    // Dřív šlo BEZ přihlášení poslat {type:'booking'|'sos', booking_id, amount:15}
    // (nebo 'extension' bez `change`) a zaplacením 15 Kč rezervaci označit paid
    // (webhook confirm_payment / confirmSosPayment částku nekontroluje). Nově:
    //  • 'extension' jen s payloadem změny — ten ocení validátor níže (fail closed),
    //  • 'booking'/'sos': přihlášený VLASTNÍK (nebo admin / service_role) a částka
    //    NESMÍ být nižší než bookings.total_price. Vyšší smí: appka k nové rezervaci
    //    přičítá upsell z e-shopu (payment_screen _amount) a objednávku zakládá až
    //    po platbě. 0 Kč / 100% sleva jde dál do FREE větve (ověřuje si ji sama),
    //  • 'sos' jen pro náhradní rezervaci ze SOS výměny (sos_replacement),
    //  • order_id u těchto typů jen čekající objednávka TÉHOŽ zákazníka — jinak se
    //    zahodí (dřív se cizí objednávce přepsal stripe_payment_intent_id).
    if (paymentType === 'booking' || paymentType === 'sos' || paymentType === 'extension') {
      if (paymentType === 'extension' && !(change && typeof change === 'object')) {
        return refuse(409, 'validation_unavailable')
      }
      const amt = Number(amount)
      if (!Number.isFinite(amt)) return refuse(400, 'invalid_amount')
      const sbChk = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      )
      // `*`: sloupce card_rounding / restore_count existují až po SQL 20261016p1/p2 (detekce nasazení).
      const { data: bkc, error: bkcErr } = await sbChk.from('bookings')
        .select('*')
        .eq('id', booking_id!).maybeSingle()
      if (bkcErr) return refuse(503, 'validation_unavailable')
      if (!bkc) return refuse(404, 'booking_not_found')
      // order_id u rezervačních typů jen čekající objednávka TÉHOŽ zákazníka — jinak se
      // zahodí (dřív se cizí objednávce přepsal stripe_payment_intent_id).
      let orderDue = 0
      if (order_id) {
        const { data: ordc } = await sbChk.from('shop_orders')
          .select('customer_id, payment_status, total').eq('id', order_id).maybeSingle()
        if (!ordc || ordc.payment_status !== 'pending' || !bkc.user_id || ordc.customer_id !== bkc.user_id) {
          order_id = undefined
        } else {
          orderDue = round2(Math.max(Number(ordc.total) || 0, 0))
        }
      }
      if (paymentType !== 'extension') {
        // (doplatek si vlastníka ověřuje ve validátoru níže)
        const who = await authClassify(req)
        if (who.kind === 'none') return refuse(401, 'auth_required')
        const owner = who.kind === 'service' || who.kind === 'admin' ||
          (who.kind === 'user' && !!who.userId && who.userId === bkc.user_id)
        if (!owner) return refuse(403, 'forbidden')
        if (paymentType === 'sos' && bkc.sos_replacement !== true) return refuse(409, 'not_sos_replacement')
        // D3/D4 (2026-10-16): zrušená rezervace (cron 30 min / zákazník / obsluha) se platbou
        // tiše „neoživuje" — appka ji nejdřív obnoví (customer_restore_booking). Jen když je
        // nasazené SQL 20261016p2 (sloupec restore_count); do té doby beze změny. Když obnovení
        // odmítla pojistka v DB (stará appka), text řekne proč.
        if (bkc.status === 'cancelled' && 'restore_count' in bkc) {
          const why = await restoreRefusal(sbChk, booking_id!, bkc.cancelled_at || null)
          return refuse(409, 'booking_cancelled', { booking_id, ...(why ? { reason: why.reason } : {}),
            ...(why?.code ? { voucher_code: why.code } : {}) }, CS[cancelledReasonKey(why?.reason)])
        }
        if (bkc.payment_status === 'paid') return refuse(409, 'already_paid', { already_paid: true, booking_id })
        // Poukaz rezervace mezitím použitý jinde / vypršelý → neplatit (po zaplacení by se uplatnil podruhé).
        const vcode = await voucherProblem(sbChk, booking_id!)
        if (vcode) return refuse(409, 'voucher_unavailable', { voucher_code: vcode, booking_id })
        // D1 (2026-10-16): zbývá do 1 Kč → neúčtuje se; 1–15 Kč → platí se 15 Kč. S přibalenou
        // objednávkou e-shopu se minimum posuzuje na celou platbu (dorovnání jde k rezervaci).
        const due = round2(Number(bkc.total_price) || 0)
        const payDue = round2(due + orderDue)
        dueClass = classifyDue(payDue, amt, cardMin)
        if (dueClass.kind === 'waive' && (paymentType === 'sos' || order_id)) {
          // SOS náhradu (cenu určuje obsluha / appka) ani platbu s objednávkou server neumí
          // ověřit na odpuštění → kartou 15 Kč.
          dueClass = Math.round(amt) === CARD_MIN_CZK
            ? { kind: 'round', due: payDue, charge: CARD_MIN_CZK, rounding: round2(CARD_MIN_CZK - payDue) }
            : { kind: 'below', due: payDue, charge: CARD_MIN_CZK, rounding: round2(CARD_MIN_CZK - payDue) }
          if (dueClass.kind === 'below') {
            return refuse(400, 'below_minimum', { due: payDue, min: CARD_MIN_CZK, charge: CARD_MIN_CZK, update_required: false, waiver_unverified: true },
              CS.waiver_unverified)
          }
        }
        // Cenu rezervace zapisuje klient → odpustit / dorovnat jen zbytek, který server doloží
        // (D1, vynuceno); u běžné platby zatím jen záznam do debug_log (PP_FLOOR_ENFORCE=1 vynutí).
        // Nesoulad = `price_outdated`: nabídnout jinou částku nejde (zaplaceno ≠ doklady).
        if (paymentType === 'booking' || paymentType === 'sos') {
          const fc = await floorCheck(sbChk, bkc, { due, kind: dueClass.kind, type: paymentType })
          if (fc === 'unavailable') return refuse(503, 'validation_unavailable')
          if (fc === 'outdated') return refuse(409, 'price_outdated', { booking_id })
        }
        if (dueClass.kind === 'waive') {
          const g = await guardStoredIntent(stripe, { storedPiId: bkc.stripe_payment_intent_id, type: paymentType, refKey: 'booking_id',
            refId: booking_id!, sheet: false, chargeCents: 0, chg: null, reuseOpen: false })
          if (g.action === 'refuse') return refuse(409, 'payment_in_progress', { payment_intent_id: g.piId, pi_status: g.status })
          return await waiveBookingFlow(sbChk, booking_id!, due, savedCardReq)
        }
        if (dueClass.kind === 'below') {
          return refuse(400, 'below_minimum', { due: payDue, min: CARD_MIN_CZK, charge: CARD_MIN_CZK, update_required: !cardMin },
            cardMin ? CS.below_minimum_app : undefined)
        }
        if (dueClass.kind === 'round') {
          // Dorovnání se do ceny zapíše až PO zaplacení (webhook, metadata due/card_rounding) —
          // opuštěná platba tak nezanechá dorovnání, které se nestrhlo.
          if (!('card_rounding' in bkc)) return refuse(409, 'rounding_unavailable')
          chargeRounding = { due, r: dueClass.rounding }
        } else if (amt > 0 && Math.round(amt) < Math.round(payDue) - 1) {
          return refuse(409, 'amount_mismatch', { server_total: Math.round(payDue) })
        } else if (amt > 0 && !order_id && Math.round(amt) > Math.round(payDue) + 1 && !(await upsellEnabled(sbChk))) {
          // Víc, než je cena, se smí strhnout jen s přibaleným doprodejem (appka ho přičítá
          // k platbě a objednávku zakládá až po ní) — doprodej je vypnutý (D7), takže přebytek
          // by nikde nebyl zapsaný (doklady = cena rezervace). Dorovnání na 15 Kč má vlastní
          // cestu (card_min → 'round', zapisuje se do ceny).
          return refuse(409, 'amount_mismatch', { server_total: Math.round(payDue) })
        } else if (amt > 0 && 'card_rounding' in bkc) {
          // Platba v celých Kč u ceny s haléři (15,40 → 15) — rozdíl jako zaokrouhlení na dokladu.
          const sub = round2(Math.round(amt * 100) / 100 - payDue)
          if (sub !== 0 && Math.abs(sub) < 1) chargeRounding = { due, r: sub }
        }
      }
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const customerId = await getOrCreateStripeCustomer(supabase, req)

    const referenceId = paymentType === 'shop' ? order_id! : booking_id!
    const productName = PRODUCT_NAMES[paymentType]

    const metadata: Record<string, string> = {
      type: paymentType,
      source: 'motogo24',
    }
    if (booking_id) metadata.booking_id = booking_id
    if (order_id) metadata.order_id = order_id
    if (incident_id) metadata.incident_id = incident_id

    // -- Doplatková změna rezervace (prodloužení / změna místa-času-motorky) --
    // Payload změny doputuje do Stripe metadat, aby ji webhook-receiver po
    // potvrzení platby aplikoval SERVER-SIDE (nezávisle na tom, zda se zákazník
    // vrátí do prohlížeče s živým localStorage). Tím se spolehlivě spustí
    // trigger trg_send_booking_modified_email → web_booking_modified.
    // Stripe metadata: hodnota max 500 znaků — delší payload (změna místa se
    // dvěma adresami ~450–600 zn.) se od 2026-10-01 dělí do klíčů chg, chg_2…
    // chg_8 (webhook je spojí); dřív se nevešel a změnu aplikoval jen klientský
    // fallback (_applyPendingAfterPayment), který nenastavoval total_price.
    if (paymentType === 'extension' && change && typeof change === 'object') {
      try {
        const chars = Array.from(JSON.stringify(change))
        const parts: string[] = []
        for (let i = 0; i < chars.length; i += 500) parts.push(chars.slice(i, i + 500).join(''))
        if (parts.length >= 1 && parts.length <= 8) {
          metadata.chg = parts[0]
          parts.slice(1).forEach((p, i) => { metadata[`chg_${i + 2}`] = p })
        }
      } catch (_e) { /* neserializovatelný payload → klientský fallback */ }
    }

    // -- Serverová validace částky doplatku (2026-08-04) --
    // `amount` u type='extension' dřív určoval čistě klient — šlo zaplatit 1 Kč
    // za drahou změnu. Když payload změny umíme přepočítat dry-run RPC (pod
    // JWT volajícího → vlastnictví a stavy hlídá RPC sama), částku vynucujeme:
    //   change._swap → split_booking_moto_swap, change._gear → update_booking_gear,
    //   p_new_* klíče (web) → apply_booking_changes.
    // Vrátí-li dry-run chybu (overlap po závodě, wrong_status…), platbu
    // odmítneme rovnou — zákazník by platil změnu, která se nedá aplikovat.
    // App formát (DB názvy sloupců): validujeme částku proti aktuální ceně
    // a navíc vozík × samoobslužná pobočka (appka žádné z těch RPC nevolá).
    if (paymentType === 'extension' && booking_id && change && typeof change === 'object') {
      const c = change as Record<string, unknown>
      let expected: number | null = null
      // D1: přesný doplatek (haléře) pro zařazení pod minimum karty; `expected` je pro kontrolu ±1 Kč.
      let dueExact: number | null = null
      // D1: je nasazená split_booking_moto_swap rev.12 (p_card_rounding, SQL 20261016p3)?
      let swapS3 = false
      let dryErr: string | null = null
      // D1: app formát (DB názvy sloupců) cenu NEověřuje dry-runem — odpuštění do 1 Kč
      // jen po serverovém přecenění (viz níže), jinak se platí kartou 15 Kč.
      let appFormat = false
      const day = (v: unknown) => String(v || '').slice(0, 10)
      const hm = (v: unknown) => (v == null ? '' : String(v).slice(0, 5))

      // ── 0) Rezervace se načte JEDNOU (service client, nezávisle na RLS) pro
      // všechny kontroly níže. Nenačtená / neexistující → platbu odmítnout
      // (fail closed) — bez řádku nevíme nic o vlastníkovi, ceně ani vozíku.
      type CurRow = {
        user_id: string | null; status: string | null; total_price: number | null; trailer_moto_id: string | null
        moto_id: string | null; start_date: string | null; end_date: string | null; pickup_time: string | null
        delivery_fee: number | null; pickup_method: string | null; pickup_address: string | null
        return_method: string | null; return_address: string | null
        extras_price: number | null; discount_amount: number | null; loyalty_discount_amount: number | null
        motorcycles: { is_trailer: boolean | null } | { is_trailer: boolean | null }[] | null
      }
      let cur: CurRow | null = null
      try {
        const { data, error } = await supabase.from('bookings')
          .select('user_id, status, total_price, trailer_moto_id, moto_id, start_date, end_date, pickup_time, delivery_fee, pickup_method, pickup_address, return_method, return_address, extras_price, discount_amount, loyalty_discount_amount, motorcycles!moto_id(is_trailer)')
          .eq('id', booking_id).maybeSingle()
        if (error) dryErr = 'validation_unavailable'
        else if (!data) dryErr = 'booking_not_found'
        else cur = data as unknown as CurRow
      } catch (_e) { dryErr = 'validation_unavailable' }

      // ── 1) Vlastnictví rezervace (5. kolo review, 2026-09-22) ──────────────
      // verify_jwt=false → gateway neověřuje nic. RPC větve (_swap/_gear/p_new_*)
      // si vlastníka hlídají samy (běží pod JWT volajícího), ale app formát
      // (DB názvy sloupců) šel dosud rovnou přes service klienta: kdokoli, kdo
      // zná UUID cizí rezervace, mohl za 1 Kč koupit server-side zápis změny
      // do ní (webhook-receiver aplikuje metadata.chg pod service_role).
      // Podepsaný JWT ověřuje authClassify přes auth.getUser — nepodepsaný
      // `sub` z hlavičky by šel podvrhnout. service_role / admin (Velín)
      // smí vždy; zákazník jen svou rezervaci.
      if (!dryErr && cur) {
        const who = await authClassify(req)
        if (who.kind === 'none') {
          // Chybějící / neplatný / expirovaný token → 401 (appka spustí re-login
          // flow authExpired a rezervaci si nechá; web ukáže výzvu k přihlášení).
          // 403 níže je jen pro PŘIHLÁŠENÉHO ne-vlastníka.
          return refuse(401, 'auth_required', {}, CS.auth_required_edit)
        }
        // `service` = podepsaný service_role JWT (isServiceRole ověřuje podpis
        // přes PostgREST; pouhý claim v payloadu by šel podvrhnout).
        const owner = who.kind === 'service' || who.kind === 'admin' ||
          (who.kind === 'user' && !!who.userId && who.userId === cur.user_id)
        if (!owner) return refuse(403, 'forbidden', {}, CS.forbidden_edit)
      }

      // Stornovaná / ukončená rezervace se neupravuje (a nesmí se za ni platit —
      // confirm_payment by ji jinak „oživil“). RPC větve to hlídají samy
      // (wrong_status), app formát dosud ne.
      if (!dryErr && cur && ['cancelled', 'completed'].includes(String(cur.status || ''))) dryErr = 'wrong_status'

      // D1/D6: opakované odeslání TÉHOŽ odpuštěného doplatku (ztracená odpověď) — změna už
      // je zapsaná (značka waive:attempt_id v historii) → stejná úspěšná odpověď, ne chyba.
      const waiverRetryDone = async (): Promise<Response | null> => {
        if (!cardMin || Number(amount) > 1 || !attemptId) return null
        const ref = await waiveRef(attemptId, booking_id, change)
        const sw = c._swap as { m?: string; d?: string } | undefined
        const done = sw && sw.m && sw.d ? await swapDone(supabase, booking_id, { m: sw.m, d: sw.d }, ref, null)
          : ((await historyHasRef(supabase, booking_id, ref)) ? booking_id : null)
        if (!done) return null
        return respond(200, { success: true, free: true, waived: true, applied: true, state: 'already_applied', charge: 0,
          booking_id, new_booking_id: done !== booking_id ? done : null, ...(savedCardReq ? { off_session: true, status: 'succeeded' } : {}) })
      }

      // ── 2) Výchozí stav klienta (`_base`: s/e = termín, t = čas vyzvednutí,
      // p = cena) musí odpovídat AKTUÁLNÍ rezervaci. Změna naceněná proti
      // zastaralému stavu (mezitím posun z webu / jiného zařízení — incident
      // 0DC12164) se nesmí zaplatit: klient rezervaci znovu načte a úpravu zopakuje.
      const base = c._base as { s?: string; e?: string; t?: string | null; p?: number } | undefined
      if (!dryErr && cur && base && typeof base === 'object') {
        if (
          (base.s && day(base.s) !== day(cur.start_date)) ||
          (base.e && day(base.e) !== day(cur.end_date)) ||
          (base.t !== undefined && hm(base.t) !== hm(cur.pickup_time)) ||
          (base.p != null && Math.round(Number(base.p)) !== Math.round(Number(cur.total_price || 0)))
        ) {
          const again = await waiverRetryDone()
          if (again) return again
          return new Response(
            JSON.stringify({ success: false, error: 'Rezervace se mezitím změnila (jiné zařízení nebo web). Načti ji prosím znovu a úpravu zopakuj – nic jsme nestrhli.', code: 'stale_booking' }),
            { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } }
          )
        }
      }

      // ── 3) Dry-run RPC pod JWT volajícího (částka + proveditelnost změny) ──
      // FAIL CLOSED ve všech větvích: chyba RPC, vyhozená výjimka i odpověď,
      // která není ani success, ani error → `validation_unavailable`. Dřív
      // vnější catch platbu „kompatibilně bez validace" pustil.
      if (!dryErr && cur) {
        try {
          const userClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } }
          )
          const sw = c._swap as { m?: string; d?: string; t?: string } | undefined
          const gear = c._gear as { sizes?: Record<string, unknown> } | undefined
          if (sw && typeof sw === 'object' && sw.m && sw.d) {
            const swArgs = {
              p_booking_id: booking_id, p_new_moto_id: sw.m, p_swap_date: sw.d,
              p_swap_time: sw.t || null, p_dry_run: true,
            }
            // Nová appka (card_min) i web (hosted Checkout dorovnává sám): dry-run s 7. parametrem
            // zároveň ověří nasazení rev.12.
            const probeS3 = cardMin || paymentMode === 'checkout'
            let { data, error } = await userClient.rpc('split_booking_moto_swap', probeS3 ? { ...swArgs, p_card_rounding: 0 } : swArgs)
            if (probeS3) {
              if (error && /PGRST202|42883|could not find the function/i.test(`${error.code || ''} ${error.message || ''}`)) {
                ({ data, error } = await userClient.rpc('split_booking_moto_swap', swArgs))
              } else if (!error) swapS3 = true
            }
            if (!error && data?.success === true) expected = Number(data.net || 0)
            else if (!error && data?.error) dryErr = String(data.error)
            else dryErr = 'validation_unavailable'
          } else if (gear && typeof gear === 'object') {
            const { data, error } = await userClient.rpc('update_booking_gear', {
              p_booking_id: booking_id, p_sizes: gear.sizes || {}, p_dry_run: true,
            })
            if (!error && data?.success === true) expected = Number(data.net_diff || 0)
            else if (!error && data?.error) dryErr = String(data.error)
            else dryErr = 'validation_unavailable'
          } else if (Object.keys(c).some((k) => k.startsWith('p_new_'))) {
            const params: Record<string, unknown> = { p_booking_id: booking_id, p_dry_run: true }
            for (const [k, v] of Object.entries(c)) if (k.startsWith('p_new_')) params[k] = v
            const { data, error } = await userClient.rpc('apply_booking_changes', params)
            if (!error && data?.success === true) {
              expected = Number(data.net_diff || 0)
              // 2026-10-01 (incident „vratka −11 Kč"): výsledek SERVEROVÉHO
              // dry-runu do metadat — webhook-receiver po platbě zapíše cenu
              // a delivery_fee odsud, ne z klientského payloadu (klient posílal
              // u zamčené strany vyzvednutí poplatek 0 → delivery_fee bez
              // přistavení). Podíly stran (pf/rf) jdou do historie úprav.
              const num = (v: unknown) => (v != null && Number.isFinite(Number(v)) ? Number(v) : null)
              const bd = (data.breakdown || {}) as Record<string, unknown>
              // l = SKUTEČNĚ přiznaná late sleva (20261001h: získaná sleva krácená
              // stornem se ukládá jen v proplacené výši) — webhook ji zapíše místo
              // přepočtu _late_pickup_discount.
              const srv = { t: num(data.new_total), df: num(data.new_delivery_fee), pf: num(bd.pickup_fee_to), rf: num(bd.return_fee_to), x: bd.fee_split_exact === true, l: num(bd.late_pickup_to), f: placeFingerprint(cur) }
              if (srv.t != null || srv.df != null) metadata.srv = JSON.stringify(srv)
            }
            else if (!error && data?.error) dryErr = String(data.error)
            else dryErr = 'validation_unavailable'
          } else if (c.total_price != null && Number.isFinite(Number(c.total_price))) {
            appFormat = true
            // App formát (DB názvy sloupců, payment_screen.dart): appka účtuje
            // effectivePriceDiff = nová total_price − total_price rezervace, takže
            // doplatek MUSÍ sedět na rozdíl vůči AKTUÁLNÍ ceně v DB.
            expected = Math.round(Number(c.total_price) - Number(cur.total_price || 0))
            dueExact = round2(Number(c.total_price) - Number(cur.total_price || 0))
            // Vozík vydává jen OBSLUŽNÁ pobočka (20260921b–h). Appka mění motorku
            // PŘÍMÝM UPDATE, takže `_apply_booking_changes_core` ani jeho guard
            // nikdy nezavolá — jediné místo PŘED platbou, kudy tahle cesta projde,
            // je tenhle validátor. Jen při SKUTEČNÉ změně motorky u rezervace
            // s vozíkem (legacy rezervace s vozíkem na samoobsluze jde dál
            // prodloužit). Fail closed.
            // Přistavení/odvoz (2026-10-01): webhook zapíše změnu appky jako
            // service_role mimo DB pojistku trg_guard_booking_delivery — tatáž
            // pravidla proto PŘED platbou (přidání přistavení musí poplatek
            // zvýšit, bez změny místa neklesne, vyzvednutí aktivní rezervace
            // neměnné). Chybějící funkce (SQL ještě nenasazené) = bez kontroly.
            const placeKeys = ['delivery_fee', 'pickup_method', 'pickup_address', 'pickup_lat', 'pickup_lng',
              'return_method', 'return_address', 'return_lat', 'return_lng']
            if (!dryErr && placeKeys.some((k) => k in c)) {
              const { data: dv, error: dvErr } = await supabase.rpc('check_booking_delivery_change', { p_booking_id: booking_id, p_change: c })
              if (dvErr) {
                const missing = /check_booking_delivery_change|PGRST202|42883|does not exist/i.test(`${dvErr.code || ''} ${dvErr.message || ''}`)
                if (!missing) dryErr = 'validation_unavailable'
              } else if (typeof dv === 'string' && dv) {
                dryErr = 'delivery_fee_guard'
              }
            }
            // Čas vyzvednutí AKTIVNÍ (převzaté) rezervace je neměnný — stejně jako
            // server (`active_pickup_time_locked`, 20261001h); webhook by změnu
            // zahodil a zákazník by zaplatil za nic. Výjimka: stará „bez času“
            // (00:01) → čas před 12:00 = jen výchozí hodnota formuláře, nic nestojí.
            if (!dryErr && cur.status === 'active' && c.pickup_time != null) {
              const nt = hm(c.pickup_time), ot = hm(cur.pickup_time)
              if (nt !== ot && !((ot === '00:01' || ot === '') && nt < '12:00')) dryErr = 'active_pickup_time_locked'
            }
            if (typeof c.moto_id === 'string' && c.moto_id && c.moto_id !== cur.moto_id && cur.trailer_moto_id) {
              const { data: selfSvc, error: selfErr } = await supabase.rpc('moto_is_self_service', { p_moto_id: c.moto_id })
              if (selfErr || typeof selfSvc !== 'boolean') dryErr = 'trailer_check_unavailable'
              else if (selfSvc === true) dryErr = 'trailer_staffed_only'
            }
            // Proveditelnost změny pro app formát (5. kolo): appka žádný dry-run
            // RPC nevolá, takže překryv NOVÉ motorky / termínu (jiný zákazník
            // mezitím rezervoval) nebo zavřenou pobočku odhalil až trigger na
            // zápisu PO zaplacení (třída incidentu #EEC9CA33). Stejná kontrola,
            // jakou appka dělá klientsky před nacením — tady těsně před
            // PaymentIntentem. check_moto_availability = SECURITY DEFINER,
            // hlídá i moto_branch_closed. Fail closed.
            // Jen když se motorka nebo termín SKUTEČNĚ mění (stejný záběr jako
            // triggery check_booking_overlap / check_booking_branch_open) — appka
            // posílá end_date vždy, i u čistě výbavové změny.
            const nm = (typeof c.moto_id === 'string' && c.moto_id) ? c.moto_id : cur.moto_id
            const ns2 = day(c.start_date ?? cur.start_date), ne2 = day(c.end_date ?? cur.end_date)
            const motoOrDatesChanged = nm !== cur.moto_id || ns2 !== day(cur.start_date) || ne2 !== day(cur.end_date)
            if (!dryErr && nm && motoOrDatesChanged) {
              const { data: free, error: freeErr } = await supabase.rpc('check_moto_availability', {
                p_moto_id: nm, p_start: ns2, p_end: ne2, p_exclude_booking_id: booking_id,
              })
              if (freeErr || typeof free !== 'boolean') dryErr = 'validation_unavailable'
              else if (free === false) dryErr = 'moto_unavailable'
            }
          }
        } catch (_e) { dryErr = dryErr || 'validation_unavailable' }
      }

      // ── 4) Posun termínu u rezervace s VOZÍKOVÝM KUSEM: obsazenost kusu se
      // dosud zjistila až triggerem (trailer_unavailable) na zápisu PO
      // zaplacení — stejná třída jako incident #EEC9CA33. Ověřit PŘED
      // PaymentIntentem přes trailer_unit_busy (20260921h). Kusy jako v
      // check_trailer_overlap: gear add-on (trailer_moto_id) I samostatně
      // půjčený vozík (moto_id s is_trailer — 5. kolo). `_swap` rezervaci A
      // jen zkracuje, nový překryv vozíku tam vzniknout nemůže. Fail closed.
      if (!dryErr && cur) {
        try {
          const ns = (c.p_new_start ?? c.start_date) as string | undefined
          const ne = (c.p_new_end ?? c.end_date) as string | undefined
          if ((ns || ne) && !c._swap) {
            const mt = Array.isArray(cur.motorcycles) ? cur.motorcycles[0] : cur.motorcycles
            const units = [cur.trailer_moto_id, mt?.is_trailer === true ? cur.moto_id : null]
              .filter((u): u is string => typeof u === 'string' && u.length > 0)
            for (const unit of units) {
              const { data: busy, error: busyErr } = await supabase.rpc('trailer_unit_busy', {
                p_unit: unit, p_start: day(ns ?? cur.start_date), p_end: day(ne ?? cur.end_date), p_exclude: booking_id,
              })
              if (busyErr || typeof busy !== 'boolean') { dryErr = 'trailer_check_unavailable'; break }
              if (busy) { dryErr = 'trailer_unavailable'; break }
            }
          }
        } catch (_te) { dryErr = 'trailer_check_unavailable' }
      }

      // Fail closed (2026-10-01): změnu, kterou žádná větev neocenila (expected
      // zůstal null — neznámý tvar payloadu), nelze zaplatit: webhook by její
      // sloupce (delivery_fee, místo, slevy…) zapsal jako service_role bez
      // jakékoli kontroly a za libovolnou částku.
      if (!dryErr && expected == null) dryErr = 'validation_unavailable'

      // Otisk místa pro app formát (web ho dává do srv výše) — webhook podle
      // něj pozná, že se místo mezi naceněním a platbou změnilo.
      if (!dryErr && cur && !metadata.srv) metadata.srv = JSON.stringify({ f: placeFingerprint(cur) })

      if (dryErr) {
        // Kód (`code`) je stabilní API pro klienty → web i appka ho překládají
        // (editRez.pay.* / PaymentErrorMapper); `error` je český fallback.
        const dryMsgs: Record<string, string> = {
          trailer_staffed_only: 'Vozík lze půjčit jen k motorce z obslužné pobočky — samoobslužná ho nevydává. Vyberte motorku z obslužné pobočky, nebo z rezervace odeberte vozík. Platba doplatku zrušena.',
          trailer_unavailable: 'Vozík je v novém termínu už obsazený jinou rezervací. Zvolte jiný termín, nebo z rezervace odeberte vozík. Platba doplatku zrušena.',
          trailer_check_unavailable: 'Nepodařilo se ověřit vozík u rezervace — platba doplatku zrušena, zkuste to prosím za chvíli znovu.',
          validation_unavailable: 'Nepodařilo se ověřit změnu rezervace — platba doplatku zrušena, zkuste to prosím za chvíli znovu.',
          booking_not_found: 'Rezervace nebyla nalezena — platba doplatku zrušena. Obnovte stránku a zkuste znovu.',
          moto_unavailable: 'Motorka je v novém termínu už obsazená, nebo je pobočka zavřená — platba doplatku zrušena. Zvolte jiný termín nebo motorku.',
          wrong_status: 'Rezervaci v tomto stavu už nelze upravit (stornovaná nebo ukončená) — platba doplatku zrušena.',
          delivery_fee_guard: 'Poplatek za přistavení/odvoz neodpovídá změně místa (chybí adresa nebo cena trasy) — platba doplatku zrušena. Zadejte adresu a zkuste to znovu.',
          active_pickup_time_locked: 'Motorka už byla vyzvednuta — čas vyzvednutí už nelze změnit. Platba doplatku zrušena.',
          location_requires_route: 'Přistavení nebo vrácení na novou adresu se počítá podle trasy — zadejte prosím adresu znovu, aby se trasa ocenila.',
        }
        if (c._swap) {
          const again = await waiverRetryDone()
          if (again) return again
        }
        // D5 (2026-10-16): žádný surový kód v textu — kódy výměny mají vlastní větu,
        // ostatní neznámé → change_not_applicable (+ reason = původní kód).
        if (dryMsgs[dryErr]) return refuse(409, dryErr, {}, dryMsgs[dryErr])
        if (SWAP_DRY_CODES.includes(dryErr)) return refuse(409, dryErr)
        return refuse(409, 'change_not_applicable', { reason: dryErr })
      }

      // D4/D6: předchozí zaplacená úprava této rezervace, kterou webhook ještě nezapsal →
      // nejdřív ji dokonči (jinak by nová úprava nacenila starý stav); zpracovávaná → čekat.
      // Jen platba, kterou smí zapsat (paid-change-guard): nová (attempt_id / chg_hash),
      // do 72 h, nevrácená, ještě nevyhodnocená a nezapsaná — jinak je vyřízená a pokračuje se.
      {
        const { data: spi } = await supabase.from('bookings').select('stripe_payment_intent_id').eq('id', booking_id).maybeSingle()
        const g = await guardStoredIntent(stripe, { storedPiId: spi?.stripe_payment_intent_id, type: 'extension', refKey: 'booking_id',
          refId: booking_id, sheet: false, chargeCents: 0, chg: null, liveOnly: true })
        // previous_change: platba PŘEDCHOZÍ úpravy (appka: „tuhle novou jsme nezaplatili").
        if (g.action === 'refuse') return refuse(409, 'payment_in_progress', { payment_intent_id: g.piId, pi_status: g.status, previous_change: true })
        if (g.action === 'paid_extension') {
          // Znovuodeslaný TENTÝŽ pokus (nejistý výsledek) → zaplaceno: appka ověří a dokončí (fronta).
          if (sameAttempt(g.pi, attemptId)) {
            return refuse(409, 'payment_in_progress', { payment_intent_id: g.pi.id, pi_status: 'succeeded',
              pending_change: !(await historyHasRef(supabase, booking_id, g.pi.id)) })
          }
          const el = await paidChangeEligibility(supabase, g.pi, { bookingId: booking_id, requireNewCode: true, maxAgeH: PREVIOUS_MAX_AGE_H, stripe })
          if (el.ok) {
            const pmd = (g.pi.metadata || {}) as Record<string, string>
            const paidPrev = (g.pi.amount_received || g.pi.amount || 0) / 100
            const prev = await applyPaidExtension(supabase, { bookingId: booking_id, chg: chgFromMetadata(pmd), srv: pmd.srv || null,
              paidCzk: paidPrev, payRef: g.pi.id, rounding: Number(pmd.card_rounding || 0) || 0,
              since: new Date(g.pi.created * 1000).toISOString(), via: 'process-payment' })
            if (prev.state === 'applied' || prev.state === 'already_applied') await markApplied(stripe, g.pi.id)
            if (prev.state === 'duplicate') {
              // Předchozí platba byla druhá platba za už zapsanou změnu → vrátit ji, nová úprava pokračuje.
              await refundDuplicatePayment(supabase, stripe as unknown as StripeDupLike, { piId: g.pi.id, table: 'bookings', refId: booking_id,
                keepRef: prev.otherRef, amountCzk: paidPrev, via: 'process-payment', autoRefund: !pmd.shop_order_id })
            }
            if (prev.state === 'applied') return refuse(409, 'stale_booking', { previous_change: true }, CS.previous_change_applied)
            if (prev.state === 'retry') {
              // Předchozí zaplacenou úpravu teď nejde dopsat → dokončí ji webhook / fronta v appce
              // (change_kind + paid_amount jí řeknou, co dokončuje); tahle nová se nezaplatila.
              return refuse(409, 'payment_in_progress', { payment_intent_id: g.pi.id, pi_status: 'succeeded', pending_change: true,
                previous_change: true, change_kind: (chgFromMetadata(pmd) || '').includes('"_swap"') ? 'swap' : 'edit',
                paid_amount: paidPrev })
            }
            if (prev.state === 'failed') {
              await handlePaidChangeFailure(supabase, { bookingId: booking_id, payRef: g.pi.id, paidCzk: paidPrev, code: prev.code,
                reason: prev.reason, via: 'process-payment', review: prev.manual === true, autoRefund: !pmd.shop_order_id, stripe })
            }
          }
        }
      }

      // D1 (2026-10-16): doplatek do 1 Kč se neúčtuje (změna se zapíše hned, bez platby),
      // 1–15 Kč se platí 15 Kč (dorovnání jde do metadat → webhook / complete_extension
      // ho zapíše do ceny i card_rounding). Nová appka (card_min) i web (hosted Checkout:
      // částku určuje server, dorovnání je na Stripe stránce samostatná položka); staré
      // appky pod 15 Kč dostanou below_minimum (nic se nestrhne).
      const isSwap = !!(c._swap && typeof c._swap === 'object')
      const extDue = round2(dueExact ?? expected ?? 0)
      const webCheckout = paymentMode === 'checkout'
      if (webCheckout && expected != null && Math.abs(Number(amount) - extDue) > 1) {
        return refuse(400, 'amount_mismatch', { expected }, CS.amount_mismatch_edit)
      }
      const reqAmount = webCheckout ? (extDue <= 1 ? 0 : extDue < CARD_MIN_CZK ? CARD_MIN_CZK : Number(amount)) : Number(amount)
      dueClass = classifyDue(extDue, reqAmount, cardMin || webCheckout)
      let waiveSrv = metadata.srv || null
      if (dueClass.kind === 'waive' && appFormat) {
        // App formát: cenu spočítal klient → odpustit jen po serverovém přecenění.
        const userClient = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_ANON_KEY') ?? '',
          { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } })
        const v = cur ? await priceAppChange(userClient, booking_id, c, cur as unknown as Record<string, unknown>) : null
        if (v && v.net > 0 && v.net <= 1 && Math.abs(v.net - extDue) <= 1) {
          dueClass = { kind: 'waive', due: v.net, charge: 0, rounding: round2(-v.net) }
          if (v.newTotal != null) waiveSrv = JSON.stringify({ t: v.newTotal, f: placeFingerprint(cur as unknown as Record<string, unknown>) })
        } else if (Math.round(reqAmount) === CARD_MIN_CZK) {
          dueClass = { kind: 'round', due: extDue, charge: CARD_MIN_CZK, rounding: round2(CARD_MIN_CZK - extDue) }
        } else {
          return refuse(400, 'below_minimum', { due: extDue, min: CARD_MIN_CZK, charge: CARD_MIN_CZK, update_required: false, waiver_unverified: true, expected },
            CS.waiver_unverified)
        }
      }
      if (dueClass.kind === 'waive' || dueClass.kind === 'round') {
        // Bez payloadu v metadatech by změnu (a dorovnání) nemohl zapsat server.
        if (!metadata.chg) return refuse(409, 'change_too_large')
        // Výbava: dorovnání jen s apply_paid_gear_change rev.2 (SQL 20261016p4) — jinak by šlo
        // dorovnání druhým zápisem a mail o úpravě / DP by ho nezachytil.
        const isGear = !isSwap && !!(c._gear && typeof c._gear === 'object')
        if (isSwap ? !swapS3 : (!(await bookingRoundingAvailable(supabase, booking_id)) || (isGear && !(await gearRoundingAvailable(supabase))))) {
          return dueClass.kind === 'waive' ? refuse(409, 'rounding_unavailable', { waiver: true }, CS.rounding_unavailable_waiver) : refuse(409, 'rounding_unavailable')
        }
        if (dueClass.kind === 'waive') {
          if (webCheckout) {
            // Starší otevřená session téže úpravy nesmí zůstat zaplatitelná vedle odpuštění (D4).
            const pg = await settleMatchingSessions(stripe as unknown as StripeCheckoutLike, { customerId: null,
              refKey: 'booking_id', refId: booking_id, type: 'extension',
              settled: (piId, md, sid) => extensionSettled(supabase, booking_id, piId, md, sid) })
            if (pg.action === 'refuse') return refuse(409, 'payment_in_progress', { session_id: pg.sessionId, previous_change: true })
          }
          return await waiveExtensionFlow(supabase, { bookingId: booking_id, change: c, srv: waiveSrv,
            due: dueClass.due, saved: savedCardReq, attemptId,
            redirect: webCheckout ? waivedRedirect(safeRedirect(explicitSuccessUrl) || `${SITE_URL}/upravit-rezervaci?paid_booking=${booking_id}`) : null })
        }
        metadata.due = String(dueClass.due)
        metadata.card_rounding = String(dueClass.rounding)
        if (webCheckout) checkoutRounding = { due: dueClass.due, r: dueClass.rounding }
      } else if (dueClass.kind === 'below') {
        return refuse(400, 'below_minimum', { due: dueClass.due, min: CARD_MIN_CZK, charge: CARD_MIN_CZK, update_required: !cardMin, expected },
          webCheckout ? CS.below_minimum_web : (cardMin ? CS.below_minimum_app : undefined))
      } else if (expected != null && Math.abs(Number(amount) - expected) > 1) {
        return refuse(400, 'amount_mismatch', { expected }, CS.amount_mismatch_edit)
      } else if (!isSwap && dueClass.kind === 'ok' && (await bookingRoundingAvailable(supabase, booking_id))) {
        // Platba v celých Kč u doplatku s haléři (14,60 → 15) — rozdíl jako zaokrouhlení na
        // dokladu (u výměny ho z p_paid spočítá split_booking_moto_swap sama).
        const sub = round2(Math.round(Number(amount) * 100) / 100 - extDue)
        if (sub !== 0 && Math.abs(sub) < 1) { metadata.due = String(extDue); metadata.card_rounding = String(sub) }
      }
    }

    // Doplatek úpravy s nulovou / zápornou částkou se neplatí (appka ho platbou neřeší).
    if (amount <= 0 && paymentType === 'extension') return refuse(400, 'invalid_amount')

    // -- FREE BOOKING (100% discount) — POUZE pokud je sleva skutečně 100% --
    if (amount <= 0 && booking_id) {
      // `*`: card_rounding existuje až po SQL 20261016p1.
      const { data: dbBooking } = await supabase.from('bookings')
        .select('*')
        .eq('id', booking_id)
        .single()

      if (dbBooking?.payment_status === 'paid') {
        return refuse(409, 'already_paid', { already_paid: true, booking_id })
      }

      if (dbBooking && dbBooking.total_price > 0) {
        return refuse(400, 'free_mismatch', { server_total: Number(dbBooking.total_price) })
      }

      // Ověření, že sleva pokryje 100% ceny (percent=100, fixed >= originalPrice, nebo voucher >= originalPrice)
      let isTrue100 = false
      const originalPrice = (dbBooking?.total_price || 0) + (dbBooking?.discount_amount || 0)
      if (dbBooking?.promo_code_id) {
        const { data: promo } = await supabase.from('promo_codes')
          .select('type, value')
          .eq('id', dbBooking.promo_code_id)
          .single()
        if (promo && promo.type === 'percent' && promo.value >= 100) {
          isTrue100 = true
        } else if (promo && promo.type === 'fixed' && promo.value >= originalPrice && originalPrice > 0) {
          isTrue100 = true
        }
      }
      if (!isTrue100 && dbBooking?.voucher_id) {
        const { data: voucher } = await supabase.from('vouchers')
          .select('amount')
          .eq('id', dbBooking.voucher_id)
          .single()
        if (voucher && voucher.amount >= originalPrice && originalPrice > 0) {
          isTrue100 = true
        }
      }
      // D1 (oprava 2026-10-16): zdarma i když slevy (víc poukazů / kódů v booking_discounts) nebo
      // odpuštění do 1 Kč pokryjí cenu, kterou server DOLOŽÍ (spodní mez z ceníku). Dřív stačilo
      // uložené card_rounding < 0 — zastaralé po změně motorky / termínu přímo z klienta.
      if (dbBooking) isTrue100 = await freeVerifiedByFloor(supabase, dbBooking as Record<string, unknown>, isTrue100)

      if (!isTrue100) {
        console.error('Free booking rejected — discount is not truly 100%:', {
          booking_id, total_price: dbBooking?.total_price,
          discount_amount: dbBooking?.discount_amount, promo_code_id: dbBooking?.promo_code_id
        })
        return refuse(400, 'free_mismatch', { server_total: 0 }, CS.free_unverified)
      }

      const { error: rpcError } = await supabase.rpc('confirm_payment', {
        p_booking_id: booking_id,
        p_method: 'free'
      })

      if (rpcError) {
        console.error('confirm_payment RPC failed for free booking:', rpcError.message)
        return refuse(500, 'free_confirm_failed')
      }

      try {
        await supabase.from('debug_log').insert({
          source: 'process-payment', action: 'free_booking_confirmed',
          component: paymentType, status: 'ok',
          request_data: { booking_id, amount, type: paymentType },
        })
      } catch { /* ignore */ }

      // Požadavek s uloženou kartou dostane i tvar „off-session succeeded" (appka ≤ 4.1.3).
      return respond(200, { success: true, free: true, booking_id, ...(savedCardReq ? { off_session: true, status: 'succeeded' } : {}) })
    }

    // -- MODE: INTENT --
    if (paymentMode === 'intent') {
      const amountCents = Math.round(amount * 100)

      // D4 (2026-10-16): identita pokusu + nejvýš jeden strhnutelný PaymentIntent.
      const chg = paymentType === 'extension' ? await chgHash(change) : null
      if (chg) metadata.chg_hash = chg
      if (attemptId) metadata.attempt_id = attemptId
      // D1/D2: dorovnání do metadat — do ceny rezervace / objednávky ho zapíše webhook AŽ PO
      // zaplacení (u doplatku webhook / complete_extension spolu se změnou).
      if (chargeRounding) {
        metadata.due = String(chargeRounding.due)
        metadata.card_rounding = String(chargeRounding.r)
      }
      const respExtra = {
        charge: amountCents / 100,
        due: dueClass ? dueClass.due : null,
        card_rounding: dueClass && dueClass.kind === 'round' ? dueClass.rounding : Number(metadata.card_rounding || 0) || 0,
      }
      const refId = paymentType === 'shop' ? order_id! : booking_id!
      const { data: storedRow } = await supabase.from(paymentType === 'shop' ? 'shop_orders' : 'bookings')
        .select('stripe_payment_intent_id').eq('id', refId).maybeSingle()
      const guard = await guardStoredIntent(stripe, {
        storedPiId: storedRow?.stripe_payment_intent_id, type: paymentType,
        refKey: paymentType === 'shop' ? 'order_id' : 'booking_id', refId,
        sheet: !payment_method_id, chargeCents: amountCents, chg, attemptId,
        matchMeta: { due: metadata.due, card_rounding: metadata.card_rounding },
      })
      if (guard.action === 'refuse') {
        return refuse(409, 'payment_in_progress', { payment_intent_id: guard.piId, pi_status: guard.status,
          ...(paymentType === 'extension' ? { previous_change: true } : {}) })
      }
      // Zaplacený doplatek: předchozí úpravu dokončila kontrola výše; jen TENTÝŽ pokus = čekat.
      if (guard.action === 'paid_extension' && sameAttempt(guard.pi, attemptId)) {
        return refuse(409, 'payment_in_progress', { payment_intent_id: guard.pi.id, pi_status: guard.pi.status })
      }
      const ephemeralKeyFor = async (): Promise<string | null> => {
        if (!customerId) return null
        try {
          const ek = await stripe.ephemeralKeys.create({ customer: customerId }, { apiVersion: '2024-04-10' })
          return ek.secret ?? null
        } catch { return null } // non-blocking — Payment Sheet works without it
      }
      // Platba probíhá (i znovu otevřený list s existujícím PaymentIntentem) → cron ji 10 min neruší.
      if (paymentType === 'booking' || paymentType === 'sos') await markCheckoutStarted(supabase, booking_id!)
      if (guard.action === 'reuse' && payment_method_id) {
        // Uložená karta, znovuodeslaný TENTÝŽ pokus: vrať stav původního PaymentIntentu.
        const p = guard.pi
        if (p.status === 'requires_action' || p.status === 'requires_confirmation') {
          return respond(200, { success: true, off_session: true, status: p.status, client_secret: p.client_secret,
            payment_intent_id: p.id, amount, currency: currency || 'czk', reused: true, ...respExtra })
        }
        const le = (p.last_payment_error || {}) as { code?: string; decline_code?: string }
        return respond(200, {
          success: false, off_session: true, error: 'off_session_charge_failed', code: 'off_session_charge_failed',
          error_code: le.code || null, decline_code: le.decline_code || null,
          message: declineMessageCs(le.code, le.decline_code), payment_intent_id: p.id,
        })
      }
      if (guard.action === 'reuse') {
        try {
          await supabase.from('debug_log').insert({
            source: 'process-payment', action: 'stripe_intent_reused', component: paymentType, status: 'ok',
            request_data: { booking_id, order_id, amount, type: paymentType }, response_data: { payment_intent_id: guard.pi.id },
          })
        } catch { /* ignore */ }
        return respond(200, {
          success: true, client_secret: guard.pi.client_secret, payment_intent_id: guard.pi.id, amount,
          currency: currency || 'czk', customer_id: customerId || null, ephemeral_key: await ephemeralKeyFor(),
          reused: true, ...respExtra,
        })
      }
      // Uložená karta (stržení hned) bez uloženého živého PaymentIntentu: nedávná zaplacená /
      // zpracovávaná platba téže rezervace / objednávky (ztracená odpověď, neuložené id) → nestrhnout znovu.
      if (payment_method_id && guard.action === 'proceed' && paymentType !== 'extension') {
        const recent = await findRecentLiveIntent(stripe, { refKey: paymentType === 'shop' ? 'order_id' : 'booking_id', refId, type: paymentType })
        if (recent) return refuse(409, 'payment_in_progress', { payment_intent_id: recent.piId, pi_status: recent.status })
      }
      const idemKey = idempotencyKey({ type: paymentType, refId, chargeCents: amountCents, pm: payment_method_id || null, attemptId, chg })

      // -- SAVED CARD (one-tap charge, customer PRESENT) --
      // Když klient pošle payment_method_id, strhneme uloženou kartu rovnou
      // (confirm:true) — BEZ Payment Sheetu. Zákazník je u toho (klepl na
      // „Zaplatit"), takže jde o ON-SESSION platbu: `off_session` ZÁMĚRNĚ
      // nenastavujeme.
      //
      // Pozn.: dřív zde bylo `off_session:true`. To je ale jen pro platby, kdy
      // zákazník NENÍ přítomen (merchant-initiated). U přítomného zákazníka
      // Stripe v off-session režimu vyžaduje předchozí SetupIntent a u karty,
      // která tak uložena nebyla, vrací `authentication_required` → platba
      // selhala a appka spadla zpět do Payment Sheetu (přesně ten „další
      // screen", co překáží). On-session: karta bez SCA projde rovnou
      // (succeeded), karta se SCA vrátí requires_action a klient 3DS dotáhne
      // interaktivně přes handleNextAction (zákazník je u toho).
      //
      // V JSON odpovědi necháváme `off_session: true` jako routovací příznak
      // „přímé stržení uložené karty" — čte ho appka (i nasazená 1.0.1), aby
      // odlišila tento flow od běžného intentu s Payment Sheetem.
      if (payment_method_id && customerId) {
        const offSessionParams: Stripe.PaymentIntentCreateParams = {
          amount: amountCents,
          currency: currency || 'czk',
          metadata,
          customer: customerId,
          payment_method: payment_method_id,
          confirm: true,
          // žádné redirect metody (voucher/Klarna/…), jen karta + případné 3DS
          automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
          description: productName,
        }
        try {
          const intent = await stripe.paymentIntents.create(offSessionParams, { idempotencyKey: idemKey })
          await storeIntentId(supabase, booking_id, order_id, intent.id)
          try {
            await supabase.from('debug_log').insert({
              source: 'process-payment', action: 'stripe_off_session_attempt',
              component: paymentType, status: 'ok',
              request_data: { booking_id, order_id, amount, type: paymentType, payment_method_id },
              response_data: { payment_intent_id: intent.id, status: intent.status },
            })
          } catch { /* ignore */ }
          // succeeded → hotovo, webhook potvrdí v DB
          if (intent.status === 'succeeded') {
            // client_secret i u succeeded (D6): appka podle něj po restartu ověří PI.
            return respond(200, {
              success: true, off_session: true, status: 'succeeded', client_secret: intent.client_secret,
              payment_intent_id: intent.id, amount, currency: currency || 'czk', ...respExtra,
            })
          }
          // requires_action → klient musí dokončit SCA (3DS) přes Stripe SDK
          if (intent.status === 'requires_action' || intent.status === 'requires_confirmation') {
            return respond(200, {
              success: true, off_session: true, status: intent.status,
              client_secret: intent.client_secret,
              payment_intent_id: intent.id, amount, currency: currency || 'czk', ...respExtra,
            })
          }
          // jiný stav (canceled/processing/requires_payment_method) — vrátíme jako fallback,
          // klient ukáže Payment Sheet
          return respond(200, {
            success: false, off_session: true, status: intent.status,
            error: 'off_session_unexpected_status', code: 'off_session_unexpected_status',
            payment_intent_id: intent.id,
          })
        } catch (e) {
          // Typicky `authentication_required`, `card_declined`, `insufficient_funds`,
          // `expired_card`. Pro authentication_required obsahuje err.raw.payment_intent
          // klientův PI — vrátíme ho, aby klient pokračoval přes handleNextAction.
          const stripeErr = e as Stripe.StripeRawError & { payment_intent?: { id: string, client_secret: string, status: string } }
          const piFromError = (stripeErr.raw as Record<string, unknown> | undefined)?.payment_intent as { id: string, client_secret: string, status: string } | undefined
          // Ne-karetní chyba: spojení / 5xx PO odeslání (SDK už opakovalo se stejným klíčem)
          // → výsledek NEJISTÝ (karta mohla být stržena) → payment_uncertain 502, appka ověří
          // a neplatí znovu. Ostatní (idempotence, neplatný požadavek) → vnější catch
          // (mapStripeError: duplicate_request / server_error).
          const errType = String((e as { type?: string }).type || '')
          const rawType = String((e as { rawType?: string }).rawType || (stripeErr.raw as { type?: string } | undefined)?.type || '')
          if (errType !== 'StripeCardError' && rawType !== 'card_error' && !piFromError) {
            if (isUncertainStripeError(e)) {
              try {
                await supabase.from('debug_log').insert({
                  source: 'process-payment', action: 'stripe_off_session_uncertain', component: paymentType, status: 'error',
                  request_data: { booking_id, order_id, amount, payment_method_id, idempotency_key: idemKey },
                  error_message: (e as Error).message,
                })
              } catch { /* ignore */ }
              return refuse(502, 'payment_uncertain', { uncertain: true, booking_id: booking_id || null, order_id: order_id || null })
            }
            throw e
          }
          // PI neúspěšného pokusu se k rezervaci NEukládá (process-refund vrací z uloženého PI);
          // znovuodeslání téhož pokusu vrátí Stripe idempotence (stejný klíč = stejná odpověď).
          try {
            await supabase.from('debug_log').insert({
              source: 'process-payment', action: 'stripe_off_session_failed',
              component: paymentType, status: 'error',
              request_data: { booking_id, order_id, amount, payment_method_id },
              error_message: (e as Error).message,
              response_data: { code: stripeErr.code, type: stripeErr.type, decline_code: stripeErr.decline_code, pi_status: piFromError?.status },
            })
          } catch { /* ignore */ }
          if (stripeErr.code === 'authentication_required' && piFromError?.client_secret) {
            return respond(200, {
              success: true, off_session: true, status: 'requires_action',
              client_secret: piFromError.client_secret,
              payment_intent_id: piFromError.id, amount, currency: currency || 'czk', ...respExtra,
            })
          }
          // D5: `message` česky a bez kontaktů (appka ≤ 4.1.3 ho zobrazuje); anglický text Stripe jen do debug_log.
          return respond(200, {
            success: false, off_session: true,
            error: 'off_session_charge_failed', code: 'off_session_charge_failed',
            error_code: stripeErr.code || null,
            decline_code: stripeErr.decline_code || null,
            message: declineMessageCs(stripeErr.code, stripeErr.decline_code),
            payment_intent_id: piFromError?.id || null,
          })
        }
      }

      // App nativní Payment Sheet (mode:'intent' používá POUZE Flutter app — web jede
      // přes hosted Checkout ve `handleWeb*Checkout`).
      //
      // 2026-05-30 — PRODUKTOVÝ POŽADAVEK: Link MUSÍ být dostupný jako plnohodnotná
      // platební metoda (vedle karty a Google/Apple Pay). Proto `payment_method_types`
      // zahrnuje `'card'` i `'link'` (stejně jako web hosted Checkout). Dřívější
      // vyřazení Linku (`['card']`) bylo workaroundem na zaseknutí na `checkout.link.com`,
      // což ale odporuje požadavku, aby si zákazník mohl Link zvolit a aby u něj
      // viděl korektní výsledek (úspěch / nedostatek prostředků / …).
      //
      // Proti zaseknutí (kdyby návrat z Linku/3DS selhal) chrání DVĚ věci na klientu:
      //   1) `returnURL: motogo24://payment` + registrovaný deep link (AndroidManifest)
      //      → Stripe SDK dotáhne Payment Sheet zpět do appky,
      //   2) `PaymentScreen` resume-recovery — po návratu appky do popředí ověří stav
      //      platby v DB (webhook) a buď dotáhne děkovací stránku, nebo uvolní UI
      //      pro opakování. Zákazník tak nikdy nezůstane viset.
      //
      // Google Pay / Apple Pay zůstávají (card wallets, vykreslené `initPaymentSheet`
      // přes `googlePay`/`applePay`). Uložené karty (customer + ephemeral key) fungují
      // beze změny. Web hosted Checkout má vlastní konfiguraci metod a tato větev se
      // ho NEDOTÝKÁ.
      const intentParams: Record<string, unknown> = {
        amount: amountCents,
        currency: currency || 'czk',
        metadata,
        payment_method_types: ['card', 'link'],
        description: productName,
      }
      if (customerId) {
        intentParams.customer = customerId
      }
      const intent = await stripe.paymentIntents.create(intentParams as Stripe.PaymentIntentCreateParams, { idempotencyKey: idemKey })

      // Create ephemeral key for Payment Sheet (saved cards support)
      const ephemeralKey = await ephemeralKeyFor()

      await storeIntentId(supabase, booking_id, order_id, intent.id)

      try {
        await supabase.from('debug_log').insert({
          source: 'process-payment', action: 'stripe_intent_created',
          component: paymentType, status: 'ok',
          request_data: { booking_id, order_id, incident_id, amount, currency, type: paymentType, mode: 'intent' },
          response_data: { payment_intent_id: intent.id },
        })
      } catch (e) { /* ignore */ }

      return respond(200, {
        success: true, client_secret: intent.client_secret,
        payment_intent_id: intent.id, amount, currency: currency || 'czk',
        // Payment Sheet support — Flutter uses these for saved cards
        customer_id: customerId || null,
        ephemeral_key: ephemeralKey,
        ...respExtra,
      })
    }

    // -- MODE: CHECKOUT --
    // D1 (2026-10-16): doplatek úpravy 1–15 Kč se na webu platí 15 Kč (checkoutRounding,
    // dorovnání jako samostatná položka na Stripe stránce); jiná drobná částka = odmítnutí.
    if (!checkoutRounding && Number(amount) > 0 && Number(amount) < CARD_MIN_CZK) {
      return refuse(400, 'below_minimum', { due: Number(amount), min: CARD_MIN_CZK, charge: CARD_MIN_CZK, update_required: false }, CS.below_minimum_web)
    }
    // Jazyk stránky Stripe: z requestu (locale), jinak jazyk rezervace/objednávky — dřív
    // natvrdo 'cs' (web „upravit rezervaci“ locale neposílá).
    const checkoutLang = async (): Promise<string> => {
      if (body.locale) return body.locale
      try {
        const sb = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')
        const { data } = paymentType === 'shop'
          ? await sb.from('shop_orders').select('language').eq('id', order_id!).maybeSingle()
          : await sb.from('bookings').select('language').eq('id', booking_id!).maybeSingle()
        return (data as { language?: string } | null)?.language || 'cs'
      } catch { return 'cs' }
    }
    let successPath: string
    let cancelPath: string

    if (paymentType === 'shop') {
      successPath = `/payment-success?order_id=${referenceId}`
      cancelPath = `/payment-cancel?order_id=${referenceId}`
    } else if (paymentType === 'sos') {
      successPath = `/payment-success?booking_id=${referenceId}&type=sos` + (incident_id ? `&incident_id=${incident_id}` : '')
      cancelPath = `/payment-cancel?booking_id=${referenceId}&type=sos`
    } else if (paymentType === 'extension') {
      successPath = `/payment-success?booking_id=${referenceId}&type=extension`
      cancelPath = `/payment-cancel?booking_id=${referenceId}&type=extension`
    } else {
      successPath = `/payment-success?booking_id=${referenceId}`
      cancelPath = `/payment-cancel?booking_id=${referenceId}`
    }

    // Klient (web `upravit-rezervaci` flow) může explicitně předat success/cancel URL,
    // aby se po platbě vrátil zpět na `upravit-rezervaci?paid_booking=…` místo
    // hardcoded `/payment-success`. Validujeme jen formát URL — autorizace je už
    // vyřešená přes auth token v requestu.
    const isValidHttpsUrl = (u?: string): boolean => {
      if (!u) return false
      try { const p = new URL(u); return p.protocol === 'https:' || p.protocol === 'http:' } catch { return false }
    }
    const finalSuccessUrl = isValidHttpsUrl(explicitSuccessUrl)
      ? (paymentType === 'extension' ? withSessionParam(explicitSuccessUrl!) : explicitSuccessUrl!)
      : SITE_URL + successPath
    const finalCancelUrl  = isValidHttpsUrl(explicitCancelUrl)  ? explicitCancelUrl!  : SITE_URL + cancelPath

    // Položky v jazyce zákazníka: jazyk webu (locale), jinak jazyk rezervace. Doplatek úpravy
    // podle druhu změny (výměna / výbava / úprava) — dřív vždy „Prodloužení rezervace".
    const siteLang = await checkoutLang()
    const stripeLocale = resolveStripeLocale(siteLang)
    const lineName = paymentType === 'extension' ? editLineLabel(change, siteLang) : productName
    const sessionParams: Record<string, unknown> = {
      line_items: checkoutRounding ? [
        { price_data: { currency: currency || 'czk', product_data: { name: lineName }, unit_amount: Math.round(checkoutRounding.due * 100) }, quantity: 1 },
        { price_data: { currency: currency || 'czk', product_data: { name: roundingLabel(siteLang) },
          unit_amount: Math.round(checkoutRounding.r * 100) }, quantity: 1 },
      ] : [{
        price_data: {
          currency: currency || 'czk',
          product_data: { name: lineName },
          unit_amount: Math.round(amount * 100),
        },
        quantity: 1,
      }],
      mode: 'payment',
      // Hosted Checkout „stránka stripe" (web, např. úprava rezervace): JEN karta +
      // Apple Pay/Google Pay (card wallets), bez Linku — aby default nebyla matoucí
      // „Link-first" přihlašovací obrazovka. Shodné s handleWeb*Checkout v payment-flows.ts.
      // (App native Payment Sheet výše, mode:'intent', Link ZÁMĚRNĚ drží.)
      payment_method_types: ['card'],
      success_url: finalSuccessUrl,
      cancel_url: finalCancelUrl,
      metadata,
      locale: stripeLocale,
    }

    if (customerId) {
      sessionParams.customer = customerId
    }

    // D4 (oprava 2026-10-16): nejvýš jedna zaplatitelná session na rezervaci / objednávku / doplatek —
    // starší otevřenou zrušit, čerstvě zaplacenou (webhook ještě běží) = neplatit znovu.
    const prevSess = await settleMatchingSessions(stripe as unknown as StripeCheckoutLike, { customerId: customerId || null,
      refKey: paymentType === 'shop' ? 'order_id' : 'booking_id', refId: referenceId, type: paymentType,
      settled: paymentType === 'extension' ? (piId, md, sid) => extensionSettled(supabase, referenceId, piId, md, sid) : undefined })
    if (prevSess.action === 'refuse') {
      return refuse(409, 'payment_in_progress', { session_id: prevSess.sessionId, ...(paymentType === 'extension' ? { previous_change: true } : {}) })
    }

    const session = await stripe.checkout.sessions.create(sessionParams as Stripe.Checkout.SessionCreateParams)

    try {
      await supabase.from('debug_log').insert({
        source: 'process-payment', action: 'stripe_session_created',
        component: paymentType, status: 'ok',
        request_data: { booking_id, order_id, incident_id, amount, currency, type: paymentType },
        response_data: { session_id: session.id, checkout_url: session.url },
      })
    } catch (e) { /* ignore */ }

    return new Response(
      JSON.stringify({
        success: true, checkout_url: session.url, session_id: session.id,
        amount: checkoutRounding ? CARD_MIN_CZK : amount, currency: currency || 'czk',
        ...(checkoutRounding ? { due: checkoutRounding.due, card_rounding: checkoutRounding.r, charge: CARD_MIN_CZK } : {}),
      }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('Stripe payment error:', err)
    // D4/D5 (2026-10-16): stabilní kód + český text; anglický text Stripe jen do logu.
    const mapped = mapStripeError(err)

    try {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      )
      await supabase.from('debug_log').insert({
        source: 'process-payment', action: 'stripe_error',
        component: 'stripe', status: 'error',
        error_message: (err as Error).message,
        response_data: { code: mapped.code, stripe_code: mapped.stripe_code },
      })
    } catch (e) { /* ignore */ }

    return respond(mapped.status, { success: false, code: mapped.code, error: mapped.error, stripe_code: mapped.stripe_code })
  }
})
