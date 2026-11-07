// ===== MotoGo24 – Edge Function: Webhook Receiver (Stripe LIVE) =====
// Receives Stripe webhook events and processes payment confirmations server-side.
// Endpoint: POST /functions/v1/webhook-receiver
// Stripe sends: checkout.session.completed, payment_intent.succeeded, charge.refunded, payout.paid

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'
import { confirmBookingPayment, confirmSosPayment, confirmShopPayment, ingestFinancialEvent } from './payment-confirmers.ts'
import { syncCardFromSetupSession, syncCardsForCustomer } from './stripe-card-sync.ts'
import { resolveBookingLanguage } from './customer-lang.ts'
import { applyPaidExtension, chgFromMetadata, type ApplyResult } from '../_shared/extension-apply.ts'
import { handlePaidChangeFailure, changeKindOf } from '../_shared/paid-change-failure.ts'
import { paidChangeEligibility, markApplied, failureRow, type PiLike } from '../_shared/paid-change-guard.ts'
import { applyChargeRounding } from '../_shared/charge-rounding.ts'
import { refundLatePaymentOnCancelled } from './late-payment.ts'
// Oprava i5 (2026-11-07, V6 / R1): nová platba zrušené a už vracené rezervace → vratka / mail obsluze (ne tiché ponechání)
import { handleCancelledPayment } from './cancelled-payment.ts'
import { refundDuplicatePayment, type StripeDupLike } from '../_shared/duplicate-payment.ts'
import { prepareExtensionPayment, refundDuplicateCharges, markPaidAfterChange } from './extension-payment.ts'
import { syncRefundBooking, webhookRecoveryBody } from '../_shared/refund-recovery.ts'
// Storno z více plateb (2026-11-05): částka pojistného storno mailu + „jen část větší vratky" (cancel-mail-amount.ts).
import { cancellationMailRefundCzk, partOfLargerRefund } from './cancel-mail-amount.ts'
// Oprava i2 (2026-11-05): dokončená / selhaná „pending“ vratka (refund-updated.ts), cena 0 Kč před potvrzením (free-verify.ts)
import { onRefundUpdated } from './refund-updated.ts'
import { freeVerifyCheck } from '../_shared/free-verify.ts'
// Měna (oprava 2026-11-05): potvrzuje se jen platba v CZK (_shared/currency.ts).
import { checkoutCzk, paymentCurrencyOk, type CheckoutLike } from '../_shared/currency.ts'
// Oprava i3 (2026-11-07): pojistný storno mail jen k vratce TOHOTO storna, rezervace i podle metadat / historie platby,
// externí vratka rozhoduje podle zůstatku V CENĚ rezervace (refund-scope.ts).
import { bookingRefundedInPriceHaleru, externalBookingBalanceHaleru, resolveRefundBooking, stornoMailEligible } from './refund-scope.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
  maxNetworkRetries: 2,
})

const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET') || ''

/** Oprava i3 (2026-11-07, V26): externí vratka (Stripe dashboard), po které rezervace NENÍ celá vrácená (nebo to nejde
 *  zjistit) → rezervace se neruší, obsluha dostane mail (1× na vratku — Stripe událost doručuje i znovu). */
// deno-lint-ignore no-explicit-any
async function externalRefundOpsMail(supabase: any, a: {
  bookingId: string; refundId: string | null; refundHaleru: number; balanceHaleru: number | null; chargeFully: boolean; via: string; cancelled?: boolean
}): Promise<void> {
  try {
    if (a.refundId) {
      const { data: prev } = await supabase.from('debug_log').select('id').eq('source', 'webhook-receiver')
        .eq('action', 'charge_refunded_external_ops_mail').eq('request_data->>refund_id', a.refundId).limit(1)
      if (prev?.length) return
    }
    await supabase.from('debug_log').insert({ source: 'webhook-receiver', action: 'charge_refunded_external_ops_mail', component: 'stripe',
      status: 'warning', request_data: { booking_id: a.bookingId, refund_id: a.refundId, refund_haleru: a.refundHaleru, balance_haleru: a.balanceHaleru,
        charge_fully_refunded: a.chargeFully, via: a.via } } as never)
    const num = a.bookingId.slice(-8).toUpperCase()
    const left = a.balanceHaleru == null ? 'zůstatek ostatních plateb nejde zjistit (Stripe)' : `na platbách rezervace zbývá ${a.balanceHaleru / 100} Kč`
    await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`, apikey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '' },
      body: JSON.stringify({ to: 'info@motogo24.cz',
        subject: a.cancelled
          ? `⚠️ Vratka ${a.refundHaleru / 100} Kč ze Stripe dashboardu u zrušené rezervace #${num} — vystavte dobropis`
          : `⚠️ Vratka ${a.refundHaleru / 100} Kč ze Stripe dashboardu u rezervace #${num} — rezervace NEzrušena`,
        raw_html: `<p>K rezervaci <strong>#${num}</strong> (${a.bookingId}) proběhla vratka <strong>${a.refundHaleru / 100} Kč</strong> mimo Velín `
          + `(Stripe dashboard${a.refundId ? `, ${a.refundId}` : ''}${a.chargeFully ? ', celá platba' : ''}). `
          + (a.cancelled ? `Rezervace je už zrušená — ${left}; stav platby je „Částečně vráceno“.</p><p>K vratce vystavte dobropis ručně ve Velíně.</p>`
            : `Rezervace se NEzrušila — ${left}; stav platby je „Částečně vráceno“.</p>`
              + '<p>Je-li to storno, stornujte rezervaci ve Velíně (vratka se omezí na nevrácenou část). Jinak k vratce vystavte dobropis ručně.</p>') }),
    })
  } catch (e) { console.warn('[webhook] external refund ops mail failed:', (e as Error).message) }
}

// ── Server-side aplikace doplatkové změny rezervace po potvrzení platby ──────
// Změnu z Stripe metadat (chg, srv) zapisuje sdílený modul
// _shared/extension-apply.ts (přesunuto odsud 2026-10-16; stejný kód volá
// process-payment `complete_extension`). Výsledek (D6):
//  • applied / already_applied / no_payload → hotovo (200),
//  • retry (přechodná chyba: síť, DB 5xx, souběh) → webhook doběhne ostatní
//    idempotentní kroky a vrátí 500 → Stripe událost doručí znovu (až 3 dny);
//    appka mezitím dokončuje přes complete_extension,
//  • failed (trvale nejde zapsat) → automatické vrácení doplatku + upozornění
//    obsluhy, jednou na platbu (_shared/paid-change-failure.ts).
// Platbu, která je už zapsaná (značka / payment_ref), vyhodnocená jako selhání
// (paid_change_failed) nebo z níž se už vracelo, webhook znovu NEzapisuje
// (_shared/paid-change-guard.ts) — opakovaná událost ani pozdní retry tak nepřepíše
// novější stav rezervace a nezapíše změnu, za kterou peníze už odešly zpět.
async function finishPaidChange(
  supabase: ReturnType<typeof createClient>,
  a: { bookingId: string; chg: string | null; srv: string | null | undefined; paidCzk: number | null; payRef: string; rounding: number;
       eventCreated: number; autoRefund: boolean; failCzk?: number; pi: PiLike | null; since: string | null; closed?: boolean },
): Promise<boolean> {
  if (a.pi) {
    const el = await paidChangeEligibility(supabase, a.pi, { bookingId: a.bookingId, requireNewCode: false, maxAgeH: null, stripe })
    if (!el.ok) {
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver', action: 'paid_change_skipped', component: 'stripe', status: 'info',
          request_data: { booking_id: a.bookingId, payment_ref: a.payRef, kind: el.kind },
        } as never)
      } catch { /* ignore */ }
      return false
    }
  }
  let res: ApplyResult
  try {
    res = await applyPaidExtension(supabase, { bookingId: a.bookingId, chg: a.chg, srv: a.srv ?? null, paidCzk: a.paidCzk, payRef: a.payRef,
      rounding: a.rounding, since: a.since, via: 'webhook' })
  } catch (e) {
    res = { state: 'retry', code: 'apply_exception', detail: (e as Error).message }
  }
  if (res.state === 'applied' || res.state === 'already_applied') {
    await markApplied(stripe, a.pi?.id || a.payRef)
    await markPaidAfterChange(supabase, a.bookingId)
  }
  // Změna se do metadat nevešla → zapíše ji klient; platba prošla (jako dřív → 'paid').
  if (res.state === 'no_payload' && !a.closed) await markPaidAfterChange(supabase, a.bookingId)
  if (res.state === 'no_payload' && a.closed) {
    // Změna se do metadat nevešla (zapsal by ji klient) a rezervace je zrušená / ukončená →
    // zapsat ji nelze ani klientsky → doplatek vrátit.
    res = { state: 'failed', code: 'change_failed', reason: 'booking_cancelled' }
  }
  if (res.state === 'duplicate') {
    // Tutéž změnu už zapsala jiná platba → tahle je navíc: vrátit celou (s přibalenou
    // e-shop objednávkou jen obsluha — zboží je z téže platby).
    await refundDuplicatePayment(supabase, stripe as unknown as StripeDupLike, { piId: a.pi?.id || a.payRef, table: 'bookings',
      refId: a.bookingId, keepRef: res.otherRef, amountCzk: a.failCzk ?? a.paidCzk ?? 0, via: 'webhook', autoRefund: a.autoRefund })
    return false
  }
  if (res.state === 'retry') {
    const ageH = (Date.now() / 1000 - (a.eventCreated || 0)) / 3600
    if (a.eventCreated && ageH > 70) {
      // Stripe po 3 dnech přestane doručovat — předat obsluze (bez automatické vratky).
      await handlePaidChangeFailure(supabase, { bookingId: a.bookingId, payRef: a.payRef, paidCzk: a.failCzk ?? a.paidCzk ?? 0,
        code: res.code, reason: `retry_exhausted:${res.code}`, via: 'webhook', autoRefund: false })
      return false
    }
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver', action: 'paid_change_retry', component: 'stripe', status: 'error',
        error_message: res.detail || res.code,
        request_data: { booking_id: a.bookingId, payment_ref: a.payRef, code: res.code, age_h: Math.round(ageH * 10) / 10 },
      })
    } catch { /* ignore */ }
    return true
  }
  if (res.state === 'failed') {
    await handlePaidChangeFailure(supabase, { bookingId: a.bookingId, payRef: a.payRef, paidCzk: a.failCzk ?? a.paidCzk ?? 0,
      code: res.code, reason: res.reason, via: 'webhook', autoRefund: a.autoRefund, review: res.manual === true, stripe,
      kind: changeKindOf(a.chg) })
  }
  return false
}

/** D1/D2: dorovnání platby kartou do ceny řádku AŽ PO zaplacení (před potvrzením).
 *  true = přechodná chyba DB → webhook vrátí 500 a Stripe událost zopakuje. */
// deno-lint-ignore no-explicit-any
async function chargeRoundingNeedsRetry(supabase: any, table: 'bookings' | 'shop_orders', id: string,
  md: Record<string, string> | null | undefined, payRef: string): Promise<boolean> {
  try {
    return (await applyChargeRounding(supabase, { table, id, md, payRef })) === 'error'
  } catch { return true }
}

/** D1: dorovnání se nepodařilo zapsat (přechodná chyba DB) → 500 HNED, ještě PŘED potvrzením
 *  platby. Jinak by potvrzení vystavilo doklad na cenu bez dorovnání (7 Kč při stržených 15)
 *  a opakovaná událost by pak zvedla cenu už zaplacené rezervace (mail „rezervace upravena
 *  +8 Kč" a další DP). Stripe událost zopakuje — dorovnání i potvrzení proběhnou spolu
 *  (všechny kroky jsou idempotentní). */
// deno-lint-ignore no-explicit-any
async function roundingRetry(supabase: any, ref: string | null, id: string): Promise<Response> {
  try {
    await supabase.from('debug_log').insert({ source: 'webhook-receiver', action: 'charge_rounding_retry', component: 'stripe',
      status: 'error', request_data: { id, payment_ref: ref } })
  } catch { /* ignore */ }
  return new Response(JSON.stringify({ received: true, retry: 'charge_rounding_pending' }), {
    status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

/** Platba v jiné měně než CZK (oprava 2026-11-05): process-payment ji už nezaloží (odmítá
 *  `currency` ≠ czk), takže jde o starší / podvržený požadavek — rezervaci ani objednávku
 *  NEpotvrzovat (částka by se brala jako Kč), jen záznam + e-mail obsluze (vratka ve Stripe).
 *  200 = Stripe událost neopakuje. */
// deno-lint-ignore no-explicit-any
async function nonCzkIgnored(supabase: any, eventType: string, id: string, currency: unknown, amount: unknown,
  md: Record<string, string>): Promise<Response> {
  const data = { event_type: eventType, id, currency: String(currency ?? ''), amount, booking_id: md.booking_id || null,
    order_id: md.order_id || null, type: md.type || null }
  try {
    await supabase.from('debug_log').insert({ source: 'webhook-receiver', action: 'non_czk_payment_ignored', component: 'stripe',
      status: 'error', error_message: `Platba v měně ${String(currency ?? '')} — nepotvrzeno, prověřte ve Stripe (vratka).`, request_data: data })
  } catch { /* ignore */ }
  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ to: 'info@motogo24.cz', subject: `⚠️ Platba v cizí měně (${String(currency ?? '')}) — nepotvrzeno`,
        raw_html: `<p style="margin:0 0 8px">Stripe doručil ${eventType} ${id} v měně ${String(currency ?? '')} (částka ${String(amount ?? '')} v nejmenších jednotkách měny) k ${md.type || 'booking'} ${md.booking_id || md.order_id || '—'}.</p>`
          + '<p style="margin:0">Platby přijímáme jen v CZK — rezervace / objednávka NEBYLA potvrzena. Prověřte platbu ve Stripe a vraťte ji.</p>' }),
    })
  } catch { /* ignore */ }
  return new Response(JSON.stringify({ received: true, ignored: 'non_czk' }), { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

/** i4: PaymentIntent patří Checkout Session s cenou v CZK převedenou do měny zákazníka (Adaptive Pricing)? Chyba → false. */
// deno-lint-ignore no-explicit-any
async function adaptiveCzkSession(stripe: any, piId: string): Promise<boolean> {
  try {
    const list = await stripe.checkout.sessions.list({ payment_intent: piId, limit: 1 })
    const s = list?.data?.[0]
    return !!s && checkoutCzk(s).converted
  } catch { return false }
}

/** Byl řádek zaplacený už PŘED touto událostí? (pak jde o druhou událost téže platby,
 *  nebo o druhou platbu — refundDuplicateCharges rozliší podle Stripe). */
// deno-lint-ignore no-explicit-any
async function rowPaid(supabase: any, table: 'bookings' | 'shop_orders', id: string): Promise<boolean> {
  try {
    const { data } = await supabase.from(table).select('payment_status').eq('id', id).maybeSingle()
    return (data as { payment_status?: string } | null)?.payment_status === 'paid'
  } catch { return false }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // D6: zaplacenou změnu se nepodařilo zapsat kvůli přechodné chybě → na konci 500 (Stripe zopakuje).
  let retryNeeded = false

  try {
    const body = await req.text()
    const signature = req.headers.get('stripe-signature')

    let event: Stripe.Event

    // Verify Stripe signature — REQUIRED in production
    if (!STRIPE_WEBHOOK_SECRET) {
      console.error('STRIPE_WEBHOOK_SECRET not configured')
      return new Response(
        JSON.stringify({ error: 'Webhook secret not configured' }),
        { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }
    if (!signature) {
      return new Response(
        JSON.stringify({ error: 'Missing stripe-signature header' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }
    try {
      event = await stripe.webhooks.constructEventAsync(
        body, signature, STRIPE_WEBHOOK_SECRET
      )
    } catch (err) {
      console.error('Webhook signature verification failed:', (err as Error).message)
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver', action: 'signature_verification_failed',
          component: 'stripe', status: 'error',
          error_message: (err as Error).message,
        })
      } catch (e) { /* ignore */ }
      return new Response(
        JSON.stringify({ error: 'Invalid signature' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Log incoming webhook
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver', action: 'webhook_received',
        component: 'stripe', status: 'ok',
        request_data: { event_type: event.type, event_id: event.id },
      })
    } catch (e) { /* ignore */ }

    // Handle events
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object as Stripe.Checkout.Session
      const metadata = session.metadata || {}
      // Platba v jiné měně než CZK → nepotvrzovat (setup session bez platby měnu nemá). i4: cena v CZK převedená Stripem
      // do měny zákazníka (Adaptive Pricing — currency_conversion.source_currency 'czk') JE platba v CZK (checkoutCzk).
      const sessCzk = checkoutCzk(session as unknown as CheckoutLike)
      if (session.mode !== 'setup' && !sessCzk.ok) {
        return await nonCzkIgnored(supabase, event.type, session.id, session.currency, session.amount_total, metadata as Record<string, string>)
      }
      if (sessCzk.converted) {
        try {
          await supabase.from('debug_log').insert({ source: 'webhook-receiver', action: 'checkout_adaptive_pricing', component: 'stripe', status: 'warning',
            request_data: { session_id: session.id, currency: session.currency, amount_total: session.amount_total, czk_haleru: sessCzk.amountTotalH, metadata } })
        } catch { /* ignore */ }
      }
      let paymentType = metadata.type || 'booking'
      let resolvedOrderId: string | null = metadata.order_id || null
      let resolvedBookingId: string | null = metadata.booking_id || null
      const stripePaymentIntentId = typeof session.payment_intent === 'string'
        ? session.payment_intent
        : (session.payment_intent as any)?.id || null

      // Fallback: pokud Stripe metadata chybí (Apple Pay, Link, edge cases),
      // použij client_reference_id (process-payment ho nastavuje na booking_id/order_id).
      const clientRef = (session as any).client_reference_id as string | null
      if (!resolvedOrderId && !resolvedBookingId && clientRef) {
        try {
          const { data: shopMatch } = await supabase.from('shop_orders')
            .select('id').eq('id', clientRef).maybeSingle()
          if (shopMatch?.id) { resolvedOrderId = shopMatch.id; paymentType = 'shop' }
          else {
            const { data: bkMatch } = await supabase.from('bookings')
              .select('id').eq('id', clientRef).maybeSingle()
            if (bkMatch?.id) { resolvedBookingId = bkMatch.id; paymentType = 'booking' }
          }
        } catch (e) { console.warn('[webhook] client_reference_id lookup failed:', e) }
      }

      // Druhý fallback: dohledej podle stripe_session_id (process-payment ho ukládá do shop_orders/bookings)
      if (!resolvedOrderId && !resolvedBookingId) {
        try {
          const { data: shopMatch } = await supabase.from('shop_orders')
            .select('id').eq('stripe_session_id', session.id).maybeSingle()
          if (shopMatch?.id) { resolvedOrderId = shopMatch.id; paymentType = 'shop' }
          else {
            const { data: bkMatch } = await supabase.from('bookings')
              .select('id').eq('stripe_session_id', session.id).maybeSingle()
            if (bkMatch?.id) { resolvedBookingId = bkMatch.id; paymentType = 'booking' }
          }
        } catch (e) { console.warn('[webhook] session_id lookup failed:', e) }
      }

      if (session.mode === 'setup' && metadata.action === 'add_card') {
        await syncCardFromSetupSession(supabase, session)
      } else if (session.mode === 'setup' && metadata.action === 'verify_free_booking' && resolvedBookingId) {
        // 0 Kč rezervace přes Stripe Checkout setup — karta ověřena, žádný charge.
        // Spustíme stejný flow jako u placené rezervace: confirm_payment + booking_reserved mail
        // + door codes (trigger) + KF generace. Bez tohoto by zákazník nedostal mail ani doklady.
        // Oprava i2 (2026-11-05): cena se mohla mezi vznikem session a ověřením karty změnit → > 0 nepotvrdit (free-verify.ts).
        const fv = await freeVerifyCheck(supabase, { bookingId: resolvedBookingId, sessionId: session.id, source: 'webhook-receiver' })
        if (!fv.ok) {
          return new Response(JSON.stringify({ received: true, ignored: fv.code }), { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } })
        }
        try {
          await confirmBookingPayment(supabase, resolvedBookingId, session.id, stripePaymentIntentId)
          try {
            await supabase.from('debug_log').insert({
              source: 'webhook-receiver', action: 'free_verify_confirmed',
              component: 'stripe', status: 'ok',
              request_data: { session_id: session.id, booking_id: resolvedBookingId },
            })
          } catch { /* ignore */ }
        } catch (e) {
          console.error('[webhook] free verify exception:', (e as Error).message)
          try {
            await supabase.from('debug_log').insert({
              source: 'webhook-receiver', action: 'free_verify_confirm_failed',
              component: 'stripe', status: 'error',
              error_message: (e as Error).message,
              request_data: { session_id: session.id, booking_id: resolvedBookingId },
            })
          } catch { /* ignore */ }
        }
        if (session.customer) {
          try { await syncCardsForCustomer(supabase, session.customer as string) } catch (e) { console.warn('[webhook] card sync failed:', (e as Error).message) }
        }
      } else if ((paymentType === 'booking' || paymentType === 'extension') && resolvedBookingId) {
        if (paymentType === 'booking' && await chargeRoundingNeedsRetry(supabase, 'bookings', resolvedBookingId, metadata, stripePaymentIntentId || session.id)) return await roundingRetry(supabase, stripePaymentIntentId || session.id, resolvedBookingId)
        // D4 (oprava 2026-10-16): doplatek úpravy rezervaci NEpotvrzuje přes confirm_payment
        // (ten zrušenou rezervaci „oživil" — zákazník by ji dostal zpět za cenu doplatku).
        // Zrušená / ukončená rezervace → změna se nezapíše a doplatek se vrátí.
        const ext = paymentType === 'extension'
          ? await prepareExtensionPayment(supabase, resolvedBookingId, stripePaymentIntentId, session.id) : null
        const cb = ext ? null : await confirmBookingPayment(supabase, resolvedBookingId, session.id, stripePaymentIntentId)
        // i5: přijato v Kč ze session (Adaptive Pricing — PaymentIntent v měně zákazníka) pro dělení s přibalenou objednávkou / mail
        if (cb === 'revive_failed' && stripePaymentIntentId) await refundLatePaymentOnCancelled(supabase, stripe, resolvedBookingId, stripePaymentIntentId, { shopOrderId: metadata.shop_order_id || null, czkReceivedH: sessCzk.amountTotalH })
        if (cb === 'skipped' && await handleCancelledPayment(supabase, stripe, resolvedBookingId, stripePaymentIntentId, { shopOrderId: metadata.shop_order_id || null, czkReceivedH: sessCzk.amountTotalH })) retryNeeded = true
        // Druhá platba za tutéž rezervaci (dvě záložky / starší Checkout Session) → vrátit.
        if (cb === 'duplicate' && stripePaymentIntentId) {
          await refundDuplicateCharges(supabase, stripe as unknown as StripeDupLike, { piId: stripePaymentIntentId,
            customer: typeof session.customer === 'string' ? session.customer : null, table: 'bookings', refId: resolvedBookingId, type: 'booking' })
        }
        if (ext === 'retry') retryNeeded = true
        // Doplatková změna rezervace — aplikuj server-side (spustí web_booking_modified)
        if (paymentType === 'extension' && ext !== 'retry') {
          const bundled = !!metadata.shop_order_id
          let piObj: PiLike | null = null
          if (stripePaymentIntentId) {
            try { piObj = await stripe.paymentIntents.retrieve(stripePaymentIntentId, { expand: ['latest_charge'] }) as unknown as PiLike }
            catch { piObj = { id: stripePaymentIntentId, metadata: null } }
          }
          if (await finishPaidChange(supabase, {
            bookingId: resolvedBookingId, chg: chgFromMetadata(metadata), srv: metadata.srv,
            paidCzk: (!bundled && sessCzk.amountTotalH != null) ? sessCzk.amountTotalH / 100 : null,
            payRef: stripePaymentIntentId || session.id, rounding: Number(metadata.card_rounding || 0) || 0,
            eventCreated: event.created, autoRefund: !bundled,
            // s přibalenou e-shop objednávkou částka změny z platby nejde oddělit → vratku řeší obsluha
            failCzk: sessCzk.amountTotalH != null ? sessCzk.amountTotalH / 100 : 0,
            // i4: Adaptive Pricing — PaymentIntent je v měně zákazníka, cena (session) v CZK → strážce měny nesmí doplatek odmítnout
            pi: piObj && sessCzk.converted ? { ...piObj, currency: 'czk' } as PiLike : piObj, since: new Date((session.created || event.created) * 1000).toISOString(), closed: ext === 'closed',
          })) retryNeeded = true
        }
        // Bundled e-shop upsell paid in the same session — confirm shop side too (separate invoice + email)
        if (metadata.shop_order_id) {
          try {
            await confirmShopPayment(supabase, metadata.shop_order_id, session.id, stripePaymentIntentId)
          } catch (e) { console.warn('[webhook] bundled shop confirm failed:', e) }
        }
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer as string)
        }
      } else if (paymentType === 'shop' && resolvedOrderId) {
        if (await chargeRoundingNeedsRetry(supabase, 'shop_orders', resolvedOrderId, metadata, stripePaymentIntentId || session.id)) return await roundingRetry(supabase, stripePaymentIntentId || session.id, resolvedOrderId)
        const wasPaid = await rowPaid(supabase, 'shop_orders', resolvedOrderId)
        await confirmShopPayment(supabase, resolvedOrderId, session.id, stripePaymentIntentId)
        if (wasPaid && stripePaymentIntentId) {
          await refundDuplicateCharges(supabase, stripe as unknown as StripeDupLike, { piId: stripePaymentIntentId,
            customer: typeof session.customer === 'string' ? session.customer : null, table: 'shop_orders', refId: resolvedOrderId, type: 'shop' })
        }
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer as string)
        }
      } else if (paymentType === 'sos' && resolvedBookingId) {
        if (await chargeRoundingNeedsRetry(supabase, 'bookings', resolvedBookingId, metadata, stripePaymentIntentId || session.id)) return await roundingRetry(supabase, stripePaymentIntentId || session.id, resolvedBookingId)
        const wasPaid = await rowPaid(supabase, 'bookings', resolvedBookingId)
        await confirmSosPayment(supabase, resolvedBookingId, metadata.incident_id, session.id, stripePaymentIntentId)
        if (wasPaid && stripePaymentIntentId) {
          await refundDuplicateCharges(supabase, stripe as unknown as StripeDupLike, { piId: stripePaymentIntentId,
            customer: typeof session.customer === 'string' ? session.customer : null, table: 'bookings', refId: resolvedBookingId, type: 'sos' })
        }
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer as string)
        }
      } else {
        try {
          await supabase.from('debug_log').insert({
            source: 'webhook-receiver', action: 'unmatched_session_completed',
            component: 'stripe', status: 'warning',
            request_data: { session_id: session.id, metadata, client_reference_id: clientRef },
          })
        } catch { /* ignore */ }
      }
    } else if (event.type === 'payment_intent.succeeded') {
      const paymentIntent = event.data.object as Stripe.PaymentIntent
      const metadata = paymentIntent.metadata || {}
      // Platba v jiné měně než CZK → nepotvrzovat (částka by se vzala jako Kč).
      // i4: PaymentIntent Checkoutu s Adaptive Pricing (cena v CZK, strženo v měně zákazníka) potvrzuje checkout.session.completed
      // (s částkou v CZK) → tady jen tiše přeskočit, žádný mail „vraťte“.
      if (!paymentCurrencyOk(paymentIntent.currency) && await adaptiveCzkSession(stripe, paymentIntent.id)) {
        try {
          await supabase.from('debug_log').insert({ source: 'webhook-receiver', action: 'pi_adaptive_pricing_skipped', component: 'stripe', status: 'info',
            request_data: { payment_intent_id: paymentIntent.id, currency: paymentIntent.currency, amount: paymentIntent.amount } })
        } catch { /* ignore */ }
        return new Response(JSON.stringify({ received: true, ignored: 'adaptive_pricing_session' }), { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }
      if (!paymentCurrencyOk(paymentIntent.currency)) {
        return await nonCzkIgnored(supabase, event.type, paymentIntent.id, paymentIntent.currency, paymentIntent.amount, metadata as Record<string, string>)
      }
      let paymentType = metadata.type || 'booking'
      let resolvedOrderId: string | null = metadata.order_id || null
      let resolvedBookingId: string | null = metadata.booking_id || null

      // Fallback: pokud Stripe Checkout Session metadata neproteklo do PaymentIntent,
      // dohledej order/booking podle stripe_payment_intent_id v DB.
      if (!resolvedOrderId && !resolvedBookingId) {
        try {
          const { data: shopMatch } = await supabase.from('shop_orders')
            .select('id').eq('stripe_payment_intent_id', paymentIntent.id).maybeSingle()
          if (shopMatch?.id) { resolvedOrderId = shopMatch.id; paymentType = 'shop' }
          else {
            const { data: bkMatch } = await supabase.from('bookings')
              .select('id, payment_status').eq('stripe_payment_intent_id', paymentIntent.id).maybeSingle()
            // Oprava i1 (2026-11-05): PI bez metadat = platba REZERVACE jen u dosud nezaplacené rezervace — uložený
            // doplatek úpravy (prepareExtensionPayment) u zaplacené / částečně vrácené rezervace by ji jinak
            // „potvrdil“ (partial_refund → paid + druhý mail booking_reserved).
            if (bkMatch?.id && bkMatch.payment_status === 'unpaid') { resolvedBookingId = bkMatch.id; paymentType = 'booking' }
            else if (bkMatch?.id) {
              await supabase.from('debug_log').insert({ source: 'webhook-receiver', action: 'pi_fallback_skipped_not_unpaid', component: 'stripe', status: 'info',
                request_data: { booking_id: bkMatch.id, payment_intent_id: paymentIntent.id, payment_status: bkMatch.payment_status } }).then(() => {}, () => {})
            }
          }
        } catch (e) { console.warn('[webhook] PI fallback lookup failed:', e) }
      }

      const piCustomer = typeof paymentIntent.customer === 'string' ? paymentIntent.customer
        : ((paymentIntent.customer as { id?: string } | null)?.id || null)
      if ((paymentType === 'booking' || paymentType === 'extension') && resolvedBookingId) {
        if (paymentType === 'booking' && await chargeRoundingNeedsRetry(supabase, 'bookings', resolvedBookingId, metadata, paymentIntent.id)) return await roundingRetry(supabase, paymentIntent.id, resolvedBookingId)
        // D4: doplatek úpravy NEpotvrzuje rezervaci přes confirm_payment (viz checkout.session.completed).
        const ext = paymentType === 'extension'
          ? await prepareExtensionPayment(supabase, resolvedBookingId, paymentIntent.id, null) : null
        const cb = ext ? null : await confirmBookingPayment(supabase, resolvedBookingId, paymentIntent.id, null)
        if (cb === 'revive_failed') await refundLatePaymentOnCancelled(supabase, stripe, resolvedBookingId, paymentIntent.id, { shopOrderId: metadata.shop_order_id || null })
        if (cb === 'skipped' && await handleCancelledPayment(supabase, stripe, resolvedBookingId, paymentIntent.id, { shopOrderId: metadata.shop_order_id || null })) retryNeeded = true
        if (cb === 'duplicate') {
          await refundDuplicateCharges(supabase, stripe as unknown as StripeDupLike, { piId: paymentIntent.id, customer: piCustomer,
            table: 'bookings', refId: resolvedBookingId, type: 'booking' })
        }
        if (ext === 'retry') retryNeeded = true
        if (paymentType === 'extension' && ext !== 'retry') {
          if (await finishPaidChange(supabase, {
            bookingId: resolvedBookingId, chg: chgFromMetadata(metadata), srv: metadata.srv,
            paidCzk: Number.isFinite(paymentIntent.amount) ? paymentIntent.amount / 100 : null,
            payRef: paymentIntent.id, rounding: Number(metadata.card_rounding || 0) || 0,
            eventCreated: event.created, autoRefund: true,
            pi: paymentIntent as unknown as PiLike, since: new Date(paymentIntent.created * 1000).toISOString(), closed: ext === 'closed',
          })) retryNeeded = true
        }
        if (metadata.shop_order_id) {
          try { await confirmShopPayment(supabase, metadata.shop_order_id, paymentIntent.id) }
          catch (e) { console.warn('[webhook] bundled shop confirm (intent) failed:', e) }
        }
      } else if (paymentType === 'shop' && resolvedOrderId) {
        if (await chargeRoundingNeedsRetry(supabase, 'shop_orders', resolvedOrderId, metadata, paymentIntent.id)) return await roundingRetry(supabase, paymentIntent.id, resolvedOrderId)
        const wasPaid = await rowPaid(supabase, 'shop_orders', resolvedOrderId)
        await confirmShopPayment(supabase, resolvedOrderId, paymentIntent.id)
        if (wasPaid) {
          await refundDuplicateCharges(supabase, stripe as unknown as StripeDupLike, { piId: paymentIntent.id, customer: piCustomer,
            table: 'shop_orders', refId: resolvedOrderId, type: 'shop' })
        }
      } else if (paymentType === 'sos' && resolvedBookingId) {
        if (await chargeRoundingNeedsRetry(supabase, 'bookings', resolvedBookingId, metadata, paymentIntent.id)) return await roundingRetry(supabase, paymentIntent.id, resolvedBookingId)
        const wasPaid = await rowPaid(supabase, 'bookings', resolvedBookingId)
        await confirmSosPayment(supabase, resolvedBookingId, metadata.incident_id, paymentIntent.id)
        if (wasPaid) {
          await refundDuplicateCharges(supabase, stripe as unknown as StripeDupLike, { piId: paymentIntent.id, customer: piCustomer,
            table: 'bookings', refId: resolvedBookingId, type: 'sos' })
        }
      }

      // Capture card brand + last4 from the underlying Charge so Velín booking detail
      // can show "Visa **** 4242" without an on-demand Stripe call.
      // Doplatek změny, kterou nešlo zapsat (vrací se celý, rezervace beze změny — f1 2026-10-22),
      // kartu rezervace nepřepisuje.
      const unappliedChange = paymentType === 'extension' && !!(await failureRow(supabase, paymentIntent.id))
      if (resolvedBookingId && !unappliedChange) {
        try {
          const chargeId = typeof (paymentIntent as any).latest_charge === 'string'
            ? (paymentIntent as any).latest_charge
            : (paymentIntent as any).latest_charge?.id || null
          if (chargeId) {
            const ch = await stripe.charges.retrieve(chargeId)
            const brand = ch?.payment_method_details?.card?.brand || null
            const last4 = ch?.payment_method_details?.card?.last4 || null
            if (brand || last4) {
              await supabase.from('bookings')
                .update({ card_brand: brand, card_last4: last4 })
                .eq('id', resolvedBookingId)
            }
          }
        } catch (e) { console.warn('[webhook] card brand/last4 capture failed:', (e as Error).message) }
      }

      // Auto-save card: attach PM to customer and sync to Supabase
      if (paymentIntent.customer && paymentIntent.payment_method) {
        const custId = typeof paymentIntent.customer === 'string'
          ? paymentIntent.customer : (paymentIntent.customer as any)?.id
        const pmId = typeof paymentIntent.payment_method === 'string'
          ? paymentIntent.payment_method : (paymentIntent.payment_method as any)?.id
        if (custId && pmId) {
          try {
            await stripe.paymentMethods.attach(pmId, { customer: custId })
          } catch (e) {
            // Already attached — ignore
          }
          await syncCardsForCustomer(supabase, custId)
        }
      }

      // Enrich financial event with booking/order details
      const feMetadata: Record<string, any> = {
        stripe_payment_intent_id: paymentIntent.id,
        stripe_customer: paymentIntent.customer,
        payment_type: paymentType,
        payment_method: 'card',
        received_date: new Date(paymentIntent.created * 1000).toISOString().slice(0, 10),
      }

      // Auto-fill supplier (= our company) and document details
      feMetadata.supplier_name = 'Bc. Petra Semorádová'
      feMetadata.supplier_ico = '21874263'
      feMetadata.supplier_bank_account = '670100-2225851630/6210'

      if ((paymentType === 'booking' || paymentType === 'extension') && metadata.booking_id) {
        try {
          const { data: bk } = await supabase.from('bookings')
            .select('id, start_date, end_date, total_price, user_id, motorcycles!moto_id(model, spz), profiles:user_id(full_name, email)')
            .eq('id', metadata.booking_id).single()
          if (bk) {
            const { data: inv } = await supabase.from('invoices')
              .select('number, variable_symbol')
              .eq('booking_id', metadata.booking_id)
              .in('type', ['payment_receipt', 'advance', 'proforma'])
              .order('issue_date', { ascending: false })
              .limit(1)
            feMetadata.invoice_number = inv?.[0]?.number || `RES-${metadata.booking_id.slice(-8).toUpperCase()}`
            feMetadata.variable_symbol = inv?.[0]?.variable_symbol || inv?.[0]?.number || ''
            feMetadata.customer_name = (bk as any).profiles?.full_name || ''
            feMetadata.customer_email = (bk as any).profiles?.email || ''
            feMetadata.booking_model = (bk as any).motorcycles?.model || ''
            feMetadata.booking_spz = (bk as any).motorcycles?.spz || ''
            feMetadata.booking_dates = `${bk.start_date} – ${bk.end_date}`
            feMetadata.due_date = new Date(paymentIntent.created * 1000).toISOString().slice(0, 10)
          }
        } catch (e) { /* ignore enrichment errors */ }
      } else if (paymentType === 'shop' && metadata.order_id) {
        try {
          const { data: ord } = await supabase.from('shop_orders')
            .select('order_number, total_amount, profiles:customer_id(full_name, email)')
            .eq('id', metadata.order_id).single()
          if (ord) {
            feMetadata.invoice_number = ord.order_number || `OBJ-${metadata.order_id.slice(-8).toUpperCase()}`
            feMetadata.variable_symbol = ord.order_number || ''
            feMetadata.customer_name = (ord as any).profiles?.full_name || ''
            feMetadata.due_date = new Date(paymentIntent.created * 1000).toISOString().slice(0, 10)
          }
        } catch (e) { /* ignore */ }
      }

      await ingestFinancialEvent(supabase, {
        event_type: 'revenue', source: 'stripe',
        amount_czk: paymentIntent.amount / 100, vat_rate: 0,
        duzp: new Date(paymentIntent.created * 1000).toISOString().slice(0, 10),
        linked_entity_type: paymentType || 'booking',
        linked_entity_id: metadata.booking_id || metadata.order_id || null,
        confidence_score: 1.0, status: 'validated',
        metadata: feMetadata,
      })
    } else if (event.type === 'charge.refunded') {
      const charge = event.data.object as Stripe.Charge

      // Seznam refundů na charge — v event payloadu nemusí být expandovaný,
      // pak si ho dotáhneme přes API (nejnovější refund je první).
      let refundsOnCharge: Stripe.Refund[] = charge.refunds?.data || []
      if (!refundsOnCharge.length) {
        try { refundsOnCharge = (await stripe.refunds.list({ charge: charge.id, limit: 10 })).data }
        catch (e) { console.warn('[webhook] refunds.list failed:', (e as Error).message) }
      }
      const latestRefund = refundsOnCharge[0] || null
      const refundReason = latestRefund?.reason || null

      // Enrich refund with booking details
      const refundFeMeta: Record<string, any> = {
        refund_reason: refundReason,
        original_payment_intent: charge.payment_intent,
        stripe_charge_id: charge.id,
        stripe_refund_id: latestRefund?.id || null,
        payment_method: 'card',
        supplier_name: 'Bc. Petra Semorádová',
        supplier_ico: '21874263',
        received_date: new Date().toISOString().slice(0, 10),
      }
      let linkedId: string | null = null
      let linkedType: string | null = null

      // Try to find linked booking via payment_intent
      let linkedBooking: any = null
      let linkedVia = 'stored'
      if (charge.payment_intent) {
        try {
          const piId = typeof charge.payment_intent === 'string' ? charge.payment_intent : (charge.payment_intent as any)?.id
          if (piId) {
            // i3: + cancelled_at (pojistný mail jen k vratce tohoto storna), stripe_payment_intent_id (zůstatek rezervace)
            const BK_SELECT = 'id, status, payment_status, total_price, start_date, end_date, booking_source, cancelled_by_source, cancellation_reason, cancelled_at, stripe_refund_id, stripe_payment_intent_id, motorcycles!moto_id(model), profiles:user_id(full_name, email)'
            let { data: bk } = await supabase.from('bookings').select(BK_SELECT).eq('stripe_payment_intent_id', piId).maybeSingle()
            // i3: platba není uložená (původní platba po doplatku, webový doplatek) → metadata / historie úprav
            if (!bk) {
              const r = await resolveRefundBooking(stripe as any, supabase, piId, BK_SELECT)
              if (r) { bk = r.booking as any; linkedVia = r.via }
            }
            if (bk) {
              linkedBooking = bk
              linkedId = bk.id
              linkedType = 'booking'
              refundFeMeta.customer_name = (bk as any).profiles?.full_name || ''
              refundFeMeta.booking_model = (bk as any).motorcycles?.model || ''
              refundFeMeta.invoice_number = `Refund RES-${bk.id.slice(-8).toUpperCase()}`
            }
          }
        } catch (e) { /* ignore */ }
      }

      // Účetní event = částka TOHOTO refundu, ne kumulativní amount_refunded.
      // charge.refunded chodí za KAŽDÝ refund na charge a amount_refunded je
      // součet — druhý částečný refund by se jinak zaúčtoval i s prvním znovu.
      await ingestFinancialEvent(supabase, {
        event_type: 'revenue', source: 'stripe',
        amount_czk: -((latestRefund?.amount ?? charge.amount_refunded) / 100), vat_rate: 0,
        duzp: new Date().toISOString().slice(0, 10),
        linked_entity_type: linkedType, linked_entity_id: linkedId,
        confidence_score: 1.0, status: 'validated',
        metadata: refundFeMeta,
      })

      // Refund handling — NEJDŘÍV rozlišit PŮVOD refundu (incident #DDC5A69D
      // 2026-08-12: částečná vratka výměny motorky z Velína → webhook rezervaci
      // chybně „zacanceloval jako Stripe portál storno", doprovodný cancel flow
      // vrátil i zbytek platby, vystavil druhý 100% dobropis a poslal 4 storno maily):
      //
      // A) INTERNÍ refund (vytvořil ho náš process-refund — pozná se podle
      //    metadata.mg_source, bookings.stripe_refund_id nebo existujícího
      //    dobropisu s tímto refund id): dobropis, mail i stavy řeší flow, které
      //    refund vyvolalo (zkrácení/výměna/úprava/storno). Webhook NIKDY neruší
      //    rezervaci; jen dosynchronizuje payment_status a bezpečně (recovery důvod
      //    `webhook_refund_retry` → process-refund žádný Stripe refund nevytvoří) dohraje credit_note,
      //    pokud process-refund spadl po refunds.create(). Storno mail jen pokud
      //    už rezervace cancelled JE (safety-net původního scénáře 2).
      // B) EXTERNÍ refund (Stripe portál) na PLNOU částku: skutečné storno zvenku
      //    → zacancelovat + dohrát dobropis + mail (původní scénář 1).
      // C) EXTERNÍ ČÁSTEČNÝ refund: nikdy nerušit rezervaci — jen payment_status
      //    + debug_log warning k ručnímu prověření (dobropis vystaví admin).
      // D4: vratka DVOJÍ platby (duplicate-payment) se do stavu rezervace nepromítá —
      // rezervaci platí ponechaná platba; jen finanční událost výše.
      // Totéž u vratky doplatku, který se do rezervace nezapsal (unapplied_change), a u vratky
      // pozdní platby už zrušené rezervace (late_payment — k platbě nevznikl doklad).
      const latestSource = ((latestRefund?.metadata || {}) as Record<string, string>).mg_source || ''
      const dupRefund = ['duplicate_payment', 'unapplied_change', 'late_payment'].includes(latestSource)
      if (linkedBooking && dupRefund) {
        try {
          await supabase.from('debug_log').insert({ source: 'webhook-receiver', action: 'charge_refunded_duplicate', component: 'stripe',
            status: 'info', request_data: { booking_id: linkedBooking.id, refund_id: latestRefund?.id || null } })
        } catch { /* ignore */ }
      }
      if (linkedBooking && !dupRefund) {
        try {
          const refundCzk = charge.amount_refunded / 100
          const total = Number(linkedBooking.total_price || 0)
          const refundPct = total > 0 ? Math.round((refundCzk / total) * 100) : 0
          const fullyRefunded = charge.amount_refunded >= ((charge as any).amount_captured || charge.amount)
          const alreadyCancelled = linkedBooking.status === 'cancelled'

          // Interní = refund vytvořený naším process-refund
          const refundIds = refundsOnCharge.map(r => r.id).filter(Boolean)
          let internalRefund = refundsOnCharge.some(r => !!(r.metadata as any)?.mg_source)
          if (!internalRefund && linkedBooking.stripe_refund_id && refundIds.includes(linkedBooking.stripe_refund_id)) {
            internalRefund = true
          }
          if (!internalRefund && refundIds.length) {
            try {
              const { data: cnMatch } = await supabase.from('invoices')
                .select('id').in('stripe_refund_id', refundIds).limit(1)
              if (cnMatch?.length) internalRefund = true
            } catch { /* ignore — bez match se chová jako externí */ }
          }

          // Oprava i3 (2026-11-07, V26): externí vratka (Stripe dashboard) ruší rezervaci jen když na platbách V CENĚ
          // rezervace nic nezbývá — ne když je celá vrácená jen tahle charge (doplatek 115 Kč z 3 115). Zbývá-li něco /
          // nelze zjistit → 'partial_refund', bez storna, mail obsluze.
          // Rozhoduje NEJNOVĚJŠÍ vratka bez mg_source (i když charge dřív nesla naši vratku — např. zkrácení — a teď
          // obsluha doplatí zbytek v dashboardu): stav podle zůstatku rezervace, ne „tahle charge je celá vrácená“.
          const extLatest = !latestSource
          let bookingFullyRefunded = fullyRefunded
          let extBalanceH: number | null = null
          if (extLatest) {
            extBalanceH = await externalBookingBalanceHaleru(stripe as any, supabase, { bookingId: linkedBooking.id, storedPiId: linkedBooking.stripe_payment_intent_id || null })
            bookingFullyRefunded = extBalanceH === 0
          }
          const shouldCancel = !internalRefund && bookingFullyRefunded && !alreadyCancelled

          // 1) UPDATE booking: payment_status dle reality na Stripe (plně/částečně
          //    vráceno) + stripe_refund_id; cancellation pole JEN u externího
          //    plného refundu (skutečné storno přes Stripe portál).
          //    Vratka z process-refund (mg_source): stav nastavuje process-refund sám — vrací
          //    i z více plateb (storno 50 % = celý malý doplatek + zbytek z původní platby),
          //    takže „tahle charge je celá vrácená" ≠ rezervace vrácená celá. Webhook jen
          //    zastoupí stav, dokud je rezervace stále 'paid' — compare-and-set (oprava f3:
          //    read-then-write přepsal mezitím zapsané 'partial_refund' na 'refunded');
          //    'refund_pending' nepřepisuje; stripe_refund_id jen do prázdného. Viz syncRefundBooking.
          const fromProcessRefund = latestSource === 'process-refund'
          // Více plateb (2026-11-05): naše vratka je jen ČÁST větší vratky (zbytek jde z jiných plateb
          // rezervace — mg_target > částka, nebo je sama zbytkem) → zástupný stav jen partial_refund; konečný
          // stav zapíše process-refund (normálně hned po zbytku, po pádu recovery / další storno volání).
          const partOfLarger = fromProcessRefund && partOfLargerRefund(latestRefund as any)
          // Oprava i2 (2026-11-05): uložená vratka → tahle, je-li novější (a není zbytkem z jiné platby) — po pádu
          // process-refund u DRUHÉ vratky zůstala uložená první a recovery dobropis k druhé nevystavila.
          let newerThanStored = false
          if (fromProcessRefund && latestRefund && linkedBooking.stripe_refund_id && linkedBooking.stripe_refund_id !== latestRefund.id
            && ((latestRefund.metadata || {}) as Record<string, string>).mg_part !== 'remainder') {
            try {
              const stored = refundsOnCharge.find((r) => r.id === linkedBooking.stripe_refund_id) || await stripe.refunds.retrieve(linkedBooking.stripe_refund_id)
              newerThanStored = !!stored && Number((latestRefund as any).created || 0) >= Number((stored as any).created || 0)
            } catch { newerThanStored = false }
          }
          const cancelPatch: Record<string, any> | null = shouldCancel ? {
            status: 'cancelled',
            cancelled_at: new Date().toISOString(),
            cancelled_by_source: 'stripe_portal',
            cancellation_reason: refundReason
              ? `Refund přes Stripe portál (${refundReason})`
              : 'Refund přes Stripe portál',
          } : null
          await syncRefundBooking(supabase, {
            bookingId: linkedBooking.id, currentStatus: linkedBooking.payment_status, currentRefundId: linkedBooking.stripe_refund_id,
            fromProcessRefund, fullyRefunded: (extLatest ? bookingFullyRefunded : fullyRefunded) && !partOfLarger, refundId: latestRefund?.id || null, cancelPatch, newerThanStored,
          })
          if (extLatest && extBalanceH !== 0) await externalRefundOpsMail(supabase, {
            bookingId: linkedBooking.id, refundId: latestRefund?.id || null, refundHaleru: Number(latestRefund?.amount ?? charge.amount_refunded) || 0,
            balanceHaleru: extBalanceH, chargeFully: fullyRefunded, via: linkedVia, cancelled: alreadyCancelled,
          })

          await supabase.from('debug_log').insert({
            source: 'webhook-receiver',
            action: internalRefund
              ? 'charge_refunded_internal'
              : (shouldCancel ? 'charge_refunded_portal_cancel' : 'charge_refunded_external_partial'),
            component: 'stripe',
            status: (!internalRefund && !fullyRefunded) ? 'warning' : 'info',
            request_data: {
              booking_id: linkedBooking.id, refund_id: latestRefund?.id || null,
              internal: internalRefund, fully_refunded: fullyRefunded,
              cancelled_now: shouldCancel, refund_pct: refundPct, booking_balance_haleru: extBalanceH, via: linkedVia,
            },
          }).then(() => {}, () => {})

          // 2) Dohrát credit_note (safety-net pro spadlý process-refund) — RECOVERY-ONLY
          //    volání (důvod `webhook_refund_retry` → větev `/_retry$/`: jen
          //    ensureCreditNotePdf / createCreditNoteForExistingRefund, NIKDY nový Stripe
          //    refund). Oprava f3: dřív bez důvodu — rezervace ve stavu 'refund_pending'
          //    (storno z Velínu, čekající vratka) prošla bránou a process-refund vrátil
          //    PODRUHÉ celý zbytek uložené platby. U externího ČÁSTEČNÉHO refundu nevoláme —
          //    dobropis k ručnímu vystavení (viz debug_log warning výše).
          // Oprava i2 (2026-11-05): částky celého storna z odpovědi recovery (cancel_refunded_haleru / cancel_goal_haleru,
          // cancel-once.ts) → pojistný mail uvádí, co se vrátilo; chybí-li zbytek (selhal / dokončuje se), mail to říká
          // (refund_deferred) místo částky z mg_cancel_total (= už vráceno + POŽADAVEK).
          let recAmounts: { refunded: number; goal: number | null; deferred: boolean } | null = null
          if (internalRefund || (fullyRefunded && bookingFullyRefunded)) {
            const rec = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/process-refund`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
              },
              body: JSON.stringify(webhookRecoveryBody(linkedBooking.id, latestRefund?.id || null)),
            }).catch(e => { console.warn('Webhook process-refund recovery failed:', e?.message); return null })
            try {
              const rj = rec ? await rec.clone().json() : null
              if (rj && Number.isFinite(Number(rj.cancel_refunded_haleru))) {
                const goal = Number.isFinite(Number(rj.cancel_goal_haleru)) && rj.cancel_goal_haleru != null ? Number(rj.cancel_goal_haleru) : null
                recAmounts = { refunded: Number(rj.cancel_refunded_haleru), goal, deferred: rj.refund_deferred === true || rec!.status === 503 }
              }
            } catch { /* bez částek → mg_cancel_total jako dřív */ }
            // Oprava i1 (2026-11-05): storno z více plateb s nevráceným zbytkem, jehož dokončení drží zámek jiného
            // (možná zabitého) volání → process-refund odpoví 503 → Stripe událost doručí znovu po vypršení zámku a
            // recovery zbytek dovrátí (dřív zůstal natrvalo nevrácený bez jediného dalšího pokusu).
            if (rec && rec.status === 503) {
              retryNeeded = true
              await supabase.from('debug_log').insert({
                source: 'webhook-receiver', action: 'charge_refunded_recovery_deferred', component: 'stripe', status: 'warning',
                request_data: { booking_id: linkedBooking.id, refund_id: latestRefund?.id || null },
              }).then(() => {}, () => {})
            }
          }

          // 3) Storno mail s dobropisem — JEN když je rezervace zrušená (teď
          //    portálem, nebo už dřív storno flow, jehož mail mohl spadnout).
          //    send-cancellation-email má idempotency (sent_emails 30 min).
          //    Interní refund na ŽIVÉ rezervaci mail NEposílá — potvrzení úpravy
          //    řeší trg_booking_modified_email / příslušné flow.
          // HOTFIX storno 2026-10-29: storno mail, který odešel AŽ PO vzniku nejnovější vratky, o ní
          //    už zákazníkovi řekl → znovu doručený charge.refunded (Stripe retry po >30 min, kdy
          //    vypršel claim mailu) druhý storno mail neposílá.
          let stornoMailCoversRefund = false
          if (!shouldCancel && alreadyCancelled && (latestRefund as any)?.created) {
            try {
              const { data: ml } = await supabase.from('message_log').select('id')
                .eq('booking_id', linkedBooking.id).eq('template_slug', 'booking_cancelled').eq('channel', 'email')
                .in('status', ['sent', 'delivered'])
                .gte('created_at', new Date(Number((latestRefund as any).created) * 1000).toISOString()).limit(1)
              stornoMailCoversRefund = !!ml?.length
            } catch { /* bez údaje → mail jako dřív */ }
            if (stornoMailCoversRefund) {
              await supabase.from('debug_log').insert({
                source: 'webhook-receiver', action: 'charge_refunded_mail_already_sent', component: 'stripe', status: 'info',
                request_data: { booking_id: linkedBooking.id, refund_id: latestRefund?.id || null },
              }).then(() => {}, () => {})
            }
          }
          // Oprava i3 (2026-11-07, V2): jen vratka TOHOTO storna (ne zkrácení / úprava / výbava / výměna ani dřívější vratka
          // doručená znovu) — mail bere claim 'booking_cancelled' a storno vratka cancel_booking_tracked by se pak neprovedla.
          const mailEligible = stornoMailEligible({ shouldCancel, latest: latestRefund as any, cancelledAt: linkedBooking.cancelled_at })
          if (!mailEligible && alreadyCancelled) {
            await supabase.from('debug_log').insert({
              source: 'webhook-receiver', action: 'charge_refunded_mail_not_this_cancellation', component: 'stripe', status: 'info',
              request_data: { booking_id: linkedBooking.id, refund_id: latestRefund?.id || null, mg_reason: ((latestRefund?.metadata || {}) as any).mg_reason || null,
                cancelled_at: linkedBooking.cancelled_at || null },
            }).then(() => {}, () => {})
          }
          if ((shouldCancel || (alreadyCancelled && mailEligible)) && linkedBooking.profiles?.email && !stornoMailCoversRefund) {
            // Jazyk zákazníka explicitně; undefined → send-cancellation-email dohledá sám.
            const language = await resolveBookingLanguage(supabase, linkedBooking.id)
            // Naše storno vratka z více plateb: částka celého storna (mg_cancel_total), ne jen této charge.
            // i3: externí vratka (Stripe dashboard) → vráceno k rezervaci celkem přes všechny její platby, ne jen tahle charge
            const extTotalH = !((latestRefund?.metadata || {}) as Record<string, string>).mg_source
              ? await bookingRefundedInPriceHaleru(stripe as any, supabase, { bookingId: linkedBooking.id, storedPiId: linkedBooking.stripe_payment_intent_id || null })
              : null
            const stornoCzk = extTotalH != null && extTotalH > 0 ? extTotalH / 100
              : shouldCancel ? null
              : recAmounts ? ((recAmounts.deferred && recAmounts.goal != null ? recAmounts.goal : recAmounts.refunded) / 100)
              : await cancellationMailRefundCzk(stripe as any, latestRefund as any)
            const mailCzk = stornoCzk ?? refundCzk
            const mailPct = stornoCzk == null ? refundPct : (total > 0 ? Math.round((mailCzk / total) * 100) : 0)
            const refundDeferred = !shouldCancel && !!recAmounts?.deferred
            await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-cancellation-email`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
              },
              body: JSON.stringify({
                booking_id: linkedBooking.id,
                customer_email: linkedBooking.profiles.email,
                customer_name: linkedBooking.profiles.full_name || '',
                motorcycle: linkedBooking.motorcycles?.model || '',
                start_date: linkedBooking.start_date,
                end_date: linkedBooking.end_date,
                cancellation_reason: shouldCancel
                  ? (refundReason ? `Refund přes Stripe portál (${refundReason})` : 'Refund přes Stripe portál')
                  : (linkedBooking.cancellation_reason || 'Storno rezervace'),
                cancelled_by_source: shouldCancel ? 'stripe_portal' : (linkedBooking.cancelled_by_source || 'customer'),
                refund_amount: mailCzk,
                refund_percent: mailPct,
                // HOTFIX storno 2026-10-29: peníze z této události už se vrátily (Stripe) — mail nesmí
                // spustit další vratku (dřív: ruční vratka v dashboardu po stornu 0 % / nové cancelled_at
                // → druhá reálná vratka). Dobropis dohledá/dohraje attach smyčka (jen recovery).
                skip_refund: true,
                // i2: zbytek storna ještě chybí → mail neslibuje vrácení celé částky („dokončuje obsluha“)
                ...(refundDeferred ? { refund_deferred: true } : {}),
                source: linkedBooking.booking_source || 'app',
                language,
              }),
            }).catch(e => console.warn('Webhook safety-net mail failed:', e?.message))
          }
        } catch (e) {
          console.warn('charge.refunded safety-net failed:', (e as Error).message)
        }
      }
    } else if (event.type === 'charge.refund.updated' || event.type === 'refund.updated') {
      // Oprava i2 (2026-11-05): vratka „pending“ dokončena / selhala (refund-updated.ts)
      await onRefundUpdated(supabase, stripe as any, event.data.object as any)
    } else if (event.type === 'payout.paid') {
      const payout = event.data.object as Stripe.Payout

      await ingestFinancialEvent(supabase, {
        event_type: 'revenue', source: 'stripe',
        amount_czk: payout.amount / 100, vat_rate: 0,
        duzp: new Date((payout as any).arrival_date * 1000).toISOString().slice(0, 10),
        linked_entity_type: null, linked_entity_id: null,
        confidence_score: 1.0, status: 'validated',
        metadata: {
          stripe_payout_id: payout.id,
          arrival_date: (payout as any).arrival_date,
        },
      })
    }

    if (retryNeeded) {
      // Všechny kroky výše jsou idempotentní (confirm_payment was_already_paid, payment_ref,
      // financial_events dle PI) — Stripe událost doručí znovu a změna se dopíše.
      return new Response(JSON.stringify({ received: true, retry: 'paid_change_pending' }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }
    return new Response(JSON.stringify({ received: true }), {
      status: 200, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Webhook error:', err)
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver', action: 'webhook_error',
        component: 'stripe', status: 'error',
        error_message: (err as Error).message,
      })
    } catch (e) { /* ignore */ }

    return new Response(
      JSON.stringify({ error: 'Webhook processing failed' }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})
