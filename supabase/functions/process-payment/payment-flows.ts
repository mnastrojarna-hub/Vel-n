// ===== process-payment/payment-flows.ts =====
// Web checkout flows: booking checkout + shop (voucher) checkout

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'
import { stripe, SITE_URL, PRODUCT_NAMES, CORS, PaymentRequest, resolveReturnOrigin, resolveSiteLang, resolveStripeLocale, withLangParam } from './stripe-customer.ts'
import { CS, refuse } from './refusals.ts'
import { waiveBooking } from './card-minimum.ts'
import { waiveShopFlow } from './pp-waiver.ts'
import { floorCheck, freeVerifiedByFloor } from './floor-check.ts'
import { settleStoredSession, type StripeCheckoutLike } from './checkout-guard.ts'
import { roundingLabel, webLabels, fillLabel, shippingLabel } from './checkout-labels.ts'
import { webBookingMiss, freeShopPlan, WEB_TXT } from './web-booking-guards.ts'

// D1/D2 (2026-10-16): web (hosted Checkout) — zbytek rezervace / objednávky do 1 Kč se
// neúčtuje (rezervace jde přes ověření karty bez platby, objednávka se potvrdí), 1–15 Kč
// se platí 15 Kč a Stripe stránka ukáže dorovnání jako samostatnou položku (do ceny ho
// zapíše webhook až po zaplacení, metadata due / card_rounding). Bez SQL 20261016p1
// (sloupec card_rounding) a u částek, které nejsou zbytkem (poukaz, odkaz z Velína),
// zůstává srozumitelné odmítnutí below_minimum místo chyby Stripe amount_too_small.
const CARD_MIN = 15
const r2 = (n: number) => Math.round((Number(n) || 0) * 100) / 100
const belowMin = (amountCzk: number, text: string) =>
  refuse(400, 'below_minimum', { due: r2(amountCzk), min: CARD_MIN, charge: CARD_MIN, update_required: false }, text)
// Položka dorovnání na Stripe stránce v jazyce webu (checkout-labels.ts).
// Výpůjčka výbavy (2026-10-23): název položky + návratové adresy gear rezervace (gear-checkout.ts).
import { isGearRow, gearBookingLabel, gearCheckoutUrls } from './gear-checkout.ts'

/** Handle web anonymous booking checkout (no auth required) */
export async function handleWebBookingCheckout(
  body: PaymentRequest,
  supabaseAdmin: ReturnType<typeof createClient>
): Promise<Response> {
  const { data: booking, error: bErr } = await supabaseAdmin
    .from('bookings')
    .select('*, profiles:user_id(full_name, email, phone, stripe_customer_id)')
    .eq('id', body.booking_id!)
    .eq('booking_source', 'web')
    .eq('payment_status', 'unpaid')
    .single()

  if (bErr || !booking) {
    console.error('Web booking lookup failed:', bErr?.message, 'booking_id:', body.booking_id)
    // f1 (2026-10-22): proč — s kódem (web-booking-guards.ts; zaplaceno = potvrzení).
    return await webBookingMiss(supabaseAdmin, body.booking_id!)
  }
  // Výpůjčka výbavy (2026-10-23): položka „MotoGo24 — Půjčení výbavy“ + návrat na /pujceni-obleceni
  // (booking_kind = 'gear'; motorka beze změny).
  const gearBk = isGearRow(booking)

  // Pojistka jazyka (audit 2026-10-10): web volá set_booking_language hned po vytvoření
  // rezervace; kdyby to selhalo, zůstala by 'cs' a smlouva, VOP i e-maily po zaplacení
  // by šly česky. Jen čerstvá nezaplacená webová rezervace, jen z výchozí 'cs'.
  const siteLang = resolveSiteLang(body.locale)
  const bkLang = booking as unknown as { created_at?: string; language?: string }
  const fresh = Date.now() - new Date(bkLang.created_at || 0).getTime() < 2 * 3600_000
  if (siteLang !== 'cs' && (bkLang.language || 'cs') === 'cs' && fresh) {
    const { error: langErr } = await supabaseAdmin.from('bookings')
      .update({ language: siteLang } as never).eq('id', body.booking_id!).eq('language', 'cs')
    if (langErr) console.warn('[WebBookingCheckout] language update failed:', langErr.message)
    else bkLang.language = siteLang
  }

  // D4 (oprava 2026-10-16): nejvýš jedna zaplatitelná session na rezervaci — předchozí otevřenou
  // (druhá záložka, zpět + znovu zaplatit) zrušit, čerstvě zaplacenou neplatit znovu. PŘED
  // odpuštěním / ověřením karty, aby stará session nezůstala zaplatitelná vedle nich.
  const prevSess = await settleStoredSession(stripe as unknown as StripeCheckoutLike,
    (booking as unknown as { stripe_session_id?: string | null }).stripe_session_id)
  if (prevSess.action === 'refuse') return refuse(409, 'payment_in_progress', { booking_id: body.booking_id, session_id: prevSess.sessionId })

  let amountCzk = booking.total_price || body.amount || 0
  const currency = body.currency || 'czk'

  // D1: přibalená objednávka e-shopu se do minima karty počítá (jedna platba).
  const shopOrderIdPre = (body as unknown as Record<string, unknown>).shop_order_id as string | undefined
  let shopSum = 0
  if (shopOrderIdPre) {
    const { data: so } = await supabaseAdmin.from('shop_orders')
      .select('payment_status, shipping_cost, shop_order_items(quantity, unit_price)').eq('id', shopOrderIdPre).maybeSingle()
    if (so && (so as Record<string, unknown>).payment_status !== 'paid') {
      for (const it of (((so as Record<string, unknown>).shop_order_items as Array<Record<string, unknown>>) || [])) {
        if (Number(it.unit_price) > 0) shopSum += Number(it.unit_price) * (Number(it.quantity) || 1)
      }
      shopSum += Math.max(Number((so as Record<string, unknown>).shipping_cost) || 0, 0)
    }
  }
  let rounding: { due: number; r: number } | null = null
  // Odpuštění zbytku do 1 Kč právě ověřené proti ceníku → bez platby (ověření karty) jako 100% sleva.
  let waiverVerified = false
  const payDue = r2(Number(amountCzk) + shopSum)
  if (Number(amountCzk) > 0 && payDue < CARD_MIN) {
    if (!('card_rounding' in (booking as Record<string, unknown>))) return belowMin(payDue, CS.below_minimum_web)
    // Cenu rezervace zapisuje klient → odpustit / dorovnat jen zbytek, který server doloží.
    // Nesoulad = price_outdated (jinou částku nenabízet — zaplaceno by se lišilo od dokladů).
    const fc = await floorCheck(supabaseAdmin, booking as Record<string, unknown>,
      { due: r2(Number(amountCzk)), kind: payDue <= 1 && !shopSum ? 'waive' : 'round', type: 'booking' })
    if (fc === 'unavailable') return refuse(503, 'validation_unavailable')
    if (fc === 'outdated') return refuse(409, 'price_outdated', { booking_id: body.booking_id })
    if (payDue <= 1 && !shopSum) {
      const cas = await waiveBooking(supabaseAdmin, body.booking_id!, r2(Number(amountCzk)))
      if (cas === 'unavailable') return refuse(409, 'rounding_unavailable', { waiver: true }, CS.rounding_unavailable_waiver)
      if (cas === 'error') return refuse(500, 'server_error')
      amountCzk = 0 // odpuštěno → ověření karty bez platby (setup) jako u 100% slevy
      waiverVerified = true
      const bkw = booking as unknown as Record<string, unknown>
      if (cas === 'done') {
        bkw.card_rounding = r2(Number(bkw.card_rounding || 0) - Number(bkw.total_price || 0))
        bkw.total_price = 0
      } else {
        // Souběh / už odpuštěno dřív (opuštěné ověření karty) → stav z DB.
        const { data: re } = await supabaseAdmin.from('bookings').select('total_price, card_rounding, payment_status')
          .eq('id', body.booking_id!).maybeSingle()
        const rw = (re || {}) as Record<string, unknown>
        if (!re || rw.payment_status === 'paid') return refuse(409, 'already_paid', { already_paid: true, booking_id: body.booking_id })
        if (Number(rw.total_price) > 0) return refuse(409, 'amount_mismatch', { server_total: Math.round(Number(rw.total_price)) })
        bkw.total_price = Number(rw.total_price) || 0
        bkw.card_rounding = Number(rw.card_rounding) || 0
      }
    } else {
      rounding = { due: r2(Number(amountCzk)), r: r2(CARD_MIN - payDue) }
    }
  } else if (Number(amountCzk) >= CARD_MIN) {
    // D4: běžná platba — spodní mez ceny zatím jen do debug_log (PP_FLOOR_ENFORCE=1 vynutí).
    const fc = await floorCheck(supabaseAdmin, booking as Record<string, unknown>, { due: r2(Number(amountCzk)), kind: 'ok', type: 'booking' })
    if (fc === 'outdated') return refuse(409, 'price_outdated', { booking_id: body.booking_id })
  }
  const amount = Math.round(amountCzk * 100)

  // 100% sleva pro web — Stripe nestrhne nic, ale projde se přes Stripe Checkout v setup módu
  // (ověření karty, žádný charge). Po session.completed webhook potvrdí rezervaci jako paid.
  const isFreeBooking = amount < 1
  let isTrue100 = false
  if (isFreeBooking) {
    const originalPrice = (booking.total_price || 0) + (booking.discount_amount || 0)

    // Ověření promo kódu — percent=100 NEBO fixed value pokrývající celou původní cenu
    if (booking.promo_code_id) {
      const { data: promo } = await supabaseAdmin.from('promo_codes')
        .select('type, value')
        .eq('id', booking.promo_code_id)
        .single()
      if (promo && promo.type === 'percent' && promo.value >= 100) {
        isTrue100 = true
      } else if (promo && promo.type === 'fixed' && promo.value >= originalPrice && originalPrice > 0) {
        isTrue100 = true
      }
    }

    // Ověření voucheru — musí pokrýt celou původní cenu
    if (!isTrue100 && booking.voucher_id) {
      const { data: voucher } = await supabaseAdmin.from('vouchers')
        .select('amount')
        .eq('id', booking.voucher_id)
        .single()
      if (voucher && voucher.amount >= originalPrice && originalPrice > 0) {
        isTrue100 = true
      }
    }

    // D1 (oprava 2026-10-16): zbytek do 1 Kč právě odpuštěný a ověřený výše, nebo slevy (víc poukazů /
    // kódů) či dřívější odpuštění pokryjí cenu, kterou server DOLOŽÍ z ceníku. Dřív stačilo uložené
    // card_rounding < 0 — zastaralé, když zákazník mezitím změnil motorku / termín přímo.
    isTrue100 = waiverVerified || await freeVerifiedByFloor(supabaseAdmin, booking as unknown as Record<string, unknown>, isTrue100)

    if (!isTrue100) {
      console.error('Free booking rejected — discount is not truly 100%:', {
        booking_id: body.booking_id, total_price: booking.total_price,
        discount_amount: booking.discount_amount, promo_code_id: booking.promo_code_id
      })
      return refuse(400, 'free_unverified', { booking_id: body.booking_id }, WEB_TXT.free_unverified)
    }
  }

  // f1 (2026-10-22): rezervace zdarma s přibaleným zbožím z doprodeje → platba jen za zboží
  // (± dorovnání na 15 Kč), ne ověření karty bez platby (web-booking-guards.ts).
  const fsp = freeShopPlan({ isFree: isFreeBooking, shopSum, roundingCol: 'card_rounding' in (booking as Record<string, unknown>),
    bookingTotal: Number((booking as Record<string, unknown>).total_price) || 0 })
  if (fsp.kind === 'below') return belowMin(shopSum, CS.below_minimum_web)
  const freeWithShop = fsp.kind === 'pay'
  if (fsp.kind === 'pay' && fsp.rounding) rounding = fsp.rounding

  const profile = booking.profiles as { full_name?: string; email?: string; phone?: string; stripe_customer_id?: string } | null
  const customerEmail = profile?.email || ''
  const customerName = profile?.full_name || ''

  let customerId = profile?.stripe_customer_id || null
  if (!customerId && customerEmail) {
    const customers = await stripe.customers.list({ email: customerEmail, limit: 1 })
    customerId = customers.data.length > 0 ? customers.data[0].id : null
  }
  if (!customerId) {
    const newCust = await stripe.customers.create({
      email: customerEmail || undefined,
      name: customerName || undefined,
      metadata: { source: 'web', booking_id: body.booking_id! }
    })
    customerId = newCust.id
    if (booking.user_id) {
      await supabaseAdmin.from('profiles').update({ stripe_customer_id: customerId }).eq('id', booking.user_id)
    }
  }

  // -- 0 Kč rezervace: Stripe Checkout v `setup` módu (ověření karty bez stržení) --
  // Po dokončení webhook `checkout.session.completed` (mode=setup) potvrdí rezervaci.
  if (isFreeBooking && !freeWithShop) {
    const setupMetadata: Record<string, string> = {
      booking_id: body.booking_id!, type: 'booking', source: 'web', action: 'verify_free_booking'
    }
    const returnOriginFree = resolveReturnOrigin(body.origin, body.locale)
    // Výpůjčka výbavy (2026-10-23): úspěch/zrušení → /pujceni-obleceni.
    const gearUrlsFree = gearBk ? gearCheckoutUrls(returnOriginFree, body.booking_id!, body.locale) : null
    const freeSession = await stripe.checkout.sessions.create({
      customer: customerId,
      mode: 'setup',
      payment_method_types: ['card'],
      metadata: setupMetadata,
      setup_intent_data: { metadata: setupMetadata },
      client_reference_id: body.booking_id!,
      // Výpůjčka výbavy (2026-10-23): gear → /pujceni-obleceni (gearUrlsFree), motorka beze změny.
      success_url: gearUrlsFree ? gearUrlsFree.success : withLangParam(`${returnOriginFree}/potvrzeni?session_id={CHECKOUT_SESSION_ID}`, body.locale),
      cancel_url: gearUrlsFree ? gearUrlsFree.cancel : withLangParam(`${returnOriginFree}/rezervace?resume=${body.booking_id}&payfail=1`, body.locale),
      locale: resolveStripeLocale(body.locale) as Stripe.Checkout.SessionCreateParams.Locale,
    })

    await supabaseAdmin.from('bookings').update({
      stripe_session_id: freeSession.id,
      stripe_checkout_url: freeSession.url,
      checkout_started_at: new Date().toISOString(),
    }).eq('id', body.booking_id!)

    // ZF (zálohová faktura) — generujeme stejně jako u placené rezervace, aby měl zákazník
    // doklad o ceně i o slevě (dobropis nepotřebujeme, žádné peníze se nehýbou).
    try {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
      const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY },
        body: JSON.stringify({ type: 'proforma', booking_id: body.booking_id, send_email: false }),
      })
    } catch (e) { console.warn('[WebBookingCheckout free] ZF generation failed:', e) }

    return new Response(JSON.stringify({ checkout_url: freeSession.url, session_id: freeSession.id, free: true }), {
      headers: { ...CORS, 'Content-Type': 'application/json' }
    })
  }

  // -- Bundled e-shop order (upsell from step 2): one Stripe session, two invoices --
  // Popisky v jazyce webu (checkout-labels.ts); rezervace zdarma se zbožím → bez řádku pronájmu.
  const L = webLabels(body.locale)
  const lineItems: Stripe.Checkout.SessionCreateParams.LineItem[] = amount > 0 ? [{
    price_data: {
      currency,
      unit_amount: amount,
      // Výpůjčka výbavy (2026-10-23): název položky v jazyce webu (gear-checkout.ts).
      product_data: { name: gearBk ? gearBookingLabel(body.locale) : L.booking, description: fillLabel(L.bookingDesc, { num: body.booking_id!.slice(-8).toUpperCase() }) }
    },
    quantity: 1
  }] : []
  const sessionMetadata: Record<string, string> = { booking_id: body.booking_id!, type: 'booking', source: 'web',
    ...(rounding ? { due: String(rounding.due), card_rounding: String(rounding.r) } : {}) }

  const shopOrderId = (body as Record<string, unknown>).shop_order_id as string | undefined
  if (shopOrderId) {
    const { data: shopOrder } = await supabaseAdmin
      .from('shop_orders')
      .select('id, payment_status, shipping_cost, shop_order_items(product_name, quantity, unit_price, size)')
      .eq('id', shopOrderId)
      .single()
    if (shopOrder && (shopOrder as Record<string, unknown>).payment_status !== 'paid') {
      const items = ((shopOrder as Record<string, unknown>).shop_order_items as Array<Record<string, unknown>>) || []
      for (const it of items) {
        const qty = Number(it.quantity) || 1
        const unit = Number(it.unit_price) || 0
        if (unit <= 0) continue
        const sizeLbl = it.size ? ` ${fillLabel(L.size, { size: String(it.size) })}` : ''
        lineItems.push({
          price_data: {
            currency,
            unit_amount: Math.round(unit * 100),
            product_data: { name: `${it.product_name}${sizeLbl}` }
          },
          quantity: qty
        })
      }
      const ship = Number((shopOrder as Record<string, unknown>).shipping_cost) || 0
      if (ship > 0) {
        lineItems.push({
          price_data: {
            currency,
            unit_amount: Math.round(ship * 100),
            product_data: { name: L.shipping }
          },
          quantity: 1
        })
      }
      sessionMetadata.shop_order_id = shopOrderId
    }
  }
  // Dorovnání až za přibalené zboží a dopravu — počítá se z celé platby (rezervace + e-shop),
  // na stránce Stripe tak nevypadá, že patří jen k rezervaci.
  if (rounding) {
    lineItems.push({ price_data: { currency, unit_amount: Math.round(rounding.r * 100), product_data: { name: roundingLabel(body.locale) } }, quantity: 1 })
  }

  // Platební metody hosted Checkoutu (webová „stránka stripe"): JEN `['card']`.
  // `payment_method_types: ['card']` (2026-07-09) — na webu chceme primárně KARTU +
  // Apple Pay / Google Pay a NE Link. Apple Pay / Google Pay jsou card wallets → Stripe je
  // pod typem `card` vykreslí automaticky (nutná aktivace + ověření domény v Dashboardu),
  // takže je NEuvádíme zvlášť. Link byl dřív ve výčtu (`['card','link']`, 2026-06-06), ale i tak
  // Stripe u vrácených Link uživatelů otevíral „Link-first" přihlašovací obrazovku jako default
  // (matoucí — lidé nevěděli, jak zaplatit kartou). Odebráním `link` z výčtu se Link jako
  // metoda na hosted stránce nenabízí a rovnou naskočí zadání karty / peněženky. Shodné
  // s voucher/shop/SOS Session níže. (App native Payment Sheet v index.ts Link ZÁMĚRNĚ drží.)
  const returnOrigin = resolveReturnOrigin(body.origin, body.locale)
  // Výpůjčka výbavy (2026-10-23): úspěch/zrušení → /pujceni-obleceni.
  const gearUrls = gearBk ? gearCheckoutUrls(returnOrigin, body.booking_id!, body.locale) : null
  const session = await stripe.checkout.sessions.create({
    customer: customerId,
    mode: 'payment',
    payment_method_types: ['card'],
    line_items: lineItems,
    metadata: sessionMetadata,
    payment_intent_data: { metadata: sessionMetadata },
    client_reference_id: body.booking_id!,
    // Výpůjčka výbavy (2026-10-23): gear → /pujceni-obleceni (gearUrls), motorka beze změny.
    success_url: gearUrls ? gearUrls.success : withLangParam(`${returnOrigin}/potvrzeni?session_id={CHECKOUT_SESSION_ID}`, body.locale),
    cancel_url: gearUrls ? gearUrls.cancel : withLangParam(`${returnOrigin}/rezervace?resume=${body.booking_id}&payfail=1`, body.locale),
    locale: resolveStripeLocale(body.locale) as Stripe.Checkout.SessionCreateParams.Locale,
  })

  await supabaseAdmin.from('bookings').update({
    stripe_session_id: session.id,
    stripe_payment_intent_id: session.payment_intent as string,
    stripe_checkout_url: session.url,
    checkout_started_at: new Date().toISOString(),
  }).eq('id', body.booking_id!)

  if (sessionMetadata.shop_order_id) {
    await supabaseAdmin.from('shop_orders').update({
      stripe_session_id: session.id,
      stripe_payment_intent_id: session.payment_intent as string,
    }).eq('id', sessionMetadata.shop_order_id)
  }

  // ZF (zálohová faktura) — generujeme při kliknutí na "Zaplatit" / přesměrování na Stripe.
  // DP zůstává vázaná na webhook-receiver po reálné Stripe platbě. Generate-invoice má
  // dedup per booking_id, takže opakované kliknutí ZF nezdvojí; webhook-receiver po platbě
  // existující ZF přeskočí a jen ji připne k potvrzovacímu emailu.
  // D1 (oprava 2026-10-16): s dorovnáním na 15 Kč ZF PŘED platbou NEvzniká — dorovnání zapíše
  // do ceny až webhook po zaplacení a ZF (s řádkem dorovnání = stržená částka) pak vygeneruje
  // potvrzovací e-mail (send-booking-email, booking_advance). Jinak by ZF ukázala 10 Kč
  // a strženo by bylo 15 Kč.
  if (!rounding) try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY },
      body: JSON.stringify({ type: 'proforma', booking_id: body.booking_id, send_email: false }),
    })
  } catch (e) { console.warn('[WebBookingCheckout] ZF generation failed:', e) }

  // due / card_rounding / charge: web (i jiný klient) vidí, že Stripe stránka ukáže dorovnání (D1).
  return new Response(JSON.stringify({ checkout_url: session.url, session_id: session.id,
    ...(rounding ? { due: rounding.due, card_rounding: rounding.r, charge: CARD_MIN } : {}) }), {
    headers: { ...CORS, 'Content-Type': 'application/json' }
  })
}

/** Velín operátor → vygeneruje Stripe Checkout ODKAZ pro PLACENOU SOS náhradu.
 *
 *  Volá se z Velína (Nový incident / detail incidentu) přes
 *  `action: 'create_sos_payment_link'`. Zrcadlí placené SOS flow z aplikace:
 *  `amount` = nájem náhrady + přistavení (od 2026-10-10 BEZ kauce/spoluúčasti
 *  30 000 Kč — „bez kauce“ platí i u náhradní motorky, VOP 4d).
 *  Metadata `type:'sos'` → po zaplacení webhook-receiver zavolá `confirmSosPayment`
 *  a označí náhradní rezervaci jako `paid` (stejná cesta jako aplikace). */
export async function handleSosPaymentLink(
  body: PaymentRequest,
  supabaseAdmin: ReturnType<typeof createClient>
): Promise<Response> {
  const bookingId = body.booking_id
  const incidentId = body.incident_id
  const amountCzk = Number(body.amount) || 0
  if (!bookingId || amountCzk <= 0) {
    return new Response(JSON.stringify({ success: false, error: 'Missing booking_id or amount' }), {
      status: 400, headers: { ...CORS, 'Content-Type': 'application/json' }
    })
  }
  if (amountCzk < CARD_MIN) return belowMin(amountCzk, CS.below_minimum_operator)

  const { data: booking, error: bErr } = await supabaseAdmin
    .from('bookings')
    .select('id, payment_status, user_id, sos_replacement, profiles:user_id(full_name, email, stripe_customer_id)')
    .eq('id', bookingId)
    .single()
  if (bErr || !booking) {
    return new Response(JSON.stringify({ success: false, error: 'Booking not found' }), {
      status: 404, headers: { ...CORS, 'Content-Type': 'application/json' }
    })
  }
  // Odkaz type 'sos' (webhook → paid + active + picked_up_at) JEN pro náhradní
  // rezervaci ze SOS výměny (sos_swap_bookings), ne pro libovolnou nezaplacenou.
  if ((booking as { sos_replacement?: boolean | null }).sos_replacement !== true) {
    return new Response(JSON.stringify({ success: false, error: 'Rezervace není SOS náhradou.', code: 'not_sos_replacement' }), {
      status: 409, headers: { ...CORS, 'Content-Type': 'application/json' }
    })
  }
  if (booking.payment_status === 'paid') {
    return new Response(JSON.stringify({ success: false, error: 'Tato rezervace je již zaplacena.' }), {
      status: 409, headers: { ...CORS, 'Content-Type': 'application/json' }
    })
  }

  const profile = booking.profiles as { full_name?: string; email?: string; stripe_customer_id?: string } | null
  const customerEmail = profile?.email || ''
  const customerName = profile?.full_name || ''
  let customerId = profile?.stripe_customer_id || null
  if (!customerId && customerEmail) {
    const customers = await stripe.customers.list({ email: customerEmail, limit: 1 })
    customerId = customers.data.length > 0 ? customers.data[0].id : null
  }
  if (!customerId && customerEmail) {
    const newCust = await stripe.customers.create({
      email: customerEmail || undefined,
      name: customerName || undefined,
      metadata: { source: 'velin_sos', booking_id: bookingId },
    })
    customerId = newCust.id
    if (booking.user_id) {
      await supabaseAdmin.from('profiles').update({ stripe_customer_id: customerId }).eq('id', booking.user_id)
    }
  }

  const currency = body.currency || 'czk'
  const metadata: Record<string, string> = { type: 'sos', source: 'velin', booking_id: bookingId }
  if (incidentId) metadata.incident_id = incidentId

  const session = await stripe.checkout.sessions.create({
    customer: customerId || undefined,
    mode: 'payment',
    // JEN karta + Apple Pay/Google Pay (card wallets), bez Linku — viz booking checkout.
    payment_method_types: ['card'],
    line_items: [{
      price_data: {
        currency,
        unit_amount: Math.round(amountCzk * 100),
        product_data: { name: PRODUCT_NAMES.sos, description: `SOS náhrada #${bookingId.slice(-8).toUpperCase()}` },
      },
      quantity: 1,
    }],
    metadata,
    payment_intent_data: { metadata },
    client_reference_id: bookingId,
    success_url: `${SITE_URL}/potvrzeni?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${SITE_URL}`,
  })

  await supabaseAdmin.from('bookings').update({
    stripe_session_id: session.id,
    stripe_payment_intent_id: session.payment_intent as string,
    stripe_checkout_url: session.url,
    checkout_started_at: new Date().toISOString(),
  }).eq('id', bookingId)

  return new Response(JSON.stringify({ success: true, checkout_url: session.url, session_id: session.id }), {
    headers: { ...CORS, 'Content-Type': 'application/json' }
  })
}

/** Handle web anonymous PRODUCT checkout (e-shop produkty z motogo24.cz). */
async function handleWebProductCheckout(
  body: PaymentRequest,
  webBody: Record<string, unknown>
): Promise<Response> {
  const orderId = body.order_id as string
  const customerEmail = (webBody.customer_email as string) || ''
  const customerName  = (webBody.customer_name as string)  || ''
  const customerPhone = (webBody.customer_phone as string) || ''
  const currency = body.currency || 'czk'

  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Načti objednávku + položky (RPC create_web_shop_order je už vytvořilo)
  // `*`: sloupec card_rounding existuje až po SQL 20261016p1 (D2, detekce nasazení).
  const { data: order, error: orderErr } = await supabaseAdmin
    .from('shop_orders')
    .select('*')
    .eq('id', orderId)
    .single()
  if (orderErr || !order) {
    return new Response(JSON.stringify({ success: false, error: 'Objednávka nenalezena.' }),
      { status: 404, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }
  if (order.payment_status === 'paid') {
    return new Response(JSON.stringify({ success: false, error: 'Tato objednávka je již zaplacena.' }),
      { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }

  // D4 (oprava 2026-10-16): předchozí otevřenou session objednávky zrušit, čerstvě zaplacenou
  // neplatit znovu (i před odpuštěním do 1 Kč — stará session nesmí zůstat zaplatitelná).
  const prevSess = await settleStoredSession(stripe as unknown as StripeCheckoutLike,
    (order as unknown as { stripe_session_id?: string | null }).stripe_session_id)
  if (prevSess.action === 'refuse') return refuse(409, 'payment_in_progress', { order_id: orderId, session_id: prevSess.sessionId })

  const orderTotal = r2(Number(order.total) || 0)
  // D2: cenu objednávky počítá server (create_web_shop_order) → do 1 Kč se neúčtuje, 1–15 Kč = 15 Kč.
  let shopRounding: { due: number; r: number } | null = null
  if (orderTotal > 0 && orderTotal < CARD_MIN) {
    if (!('card_rounding' in (order as Record<string, unknown>))) return belowMin(orderTotal, CS.below_minimum_web)
    if (order.payment_status !== 'pending') return refuse(409, 'wrong_status', {}, CS.wrong_status_shop)
    if (orderTotal <= 1) {
      const back = withLangParam(`${resolveReturnOrigin(body.origin, body.locale)}/potvrzeni?order_id=${orderId}`, body.locale)
      return await waiveShopFlow(supabaseAdmin, orderId, orderTotal, false, back)
    }
    shopRounding = { due: orderTotal, r: r2(CARD_MIN - orderTotal) }
  }

  const { data: items } = await supabaseAdmin
    .from('shop_order_items')
    .select('product_name, product_sku, size, quantity, unit_price, total_price')
    .eq('order_id', orderId)
  const orderItems = items || []
  if (orderItems.length === 0) {
    return new Response(JSON.stringify({ success: false, error: 'Objednávka neobsahuje žádné položky.' }),
      { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }
  // Půjčení výbavy bez motorky (2026-10-22, create_gear_rental_order): návrat na
  // stránku výbavy (potvrzení s termínem a pobočkou) místo košíku e-shopu a ZF bez
  // e-mailu (potvrzení výpůjčky + DP přijde po zaplacení, jako u poukazu).
  const { data: gearRow } = await supabaseAdmin.from('gear_rentals')
    .select('order_id').eq('order_id', orderId).maybeSingle()
  const isGear = !!gearRow

  // Stripe customer (re-use po e-mailu)
  const email = customerEmail || order.customer_email || ''
  const name  = customerName  || order.customer_name  || ''
  const customers = email ? await stripe.customers.list({ email, limit: 1 }) : { data: [] }
  let custId = customers.data.length > 0 ? customers.data[0].id : null
  if (!custId && email) {
    const newCust = await stripe.customers.create({
      email, name, phone: customerPhone || order.customer_phone || undefined,
      metadata: { source: 'web_shop_products' }
    })
    custId = newCust.id
  }

  // Sestavit Stripe line items z DB (cena pochází z DB, ne z klienta)
  const lineItems: Record<string, unknown>[] = orderItems.map((it: Record<string, unknown>) => {
    const baseName = String(it.product_name || 'Produkt')
    const size = it.size ? ` ${fillLabel(webLabels(body.locale).size, { size: String(it.size) })}` : ''
    return {
      price_data: {
        currency,
        unit_amount: Math.round(Number(it.unit_price) * 100),
        product_data: {
          name: baseName + size,
          ...(it.product_sku ? { metadata: { sku: String(it.product_sku) } } : {})
        }
      },
      quantity: Number(it.quantity) || 1
    }
  })

  // Doprava jako samostatný line item (Stripe ji tak ukáže na účtence)
  const shipCost = Number(order.shipping_cost) || 0
  if (shipCost > 0) {
    const shipName = shippingLabel(order.shipping_method, body.locale)
    lineItems.push({
      price_data: {
        currency,
        unit_amount: Math.round(shipCost * 100),
        product_data: { name: shipName }
      },
      quantity: 1
    })
  }

  // Sleva přes Stripe coupon (jen ad-hoc, neukládáme)
  let discounts: Record<string, unknown>[] | undefined
  const discount = Number(order.discount) || 0
  if (discount > 0) {
    const coupon = await stripe.coupons.create({
      amount_off: Math.round(discount * 100),
      currency,
      duration: 'once',
      name: webLabels(body.locale).discount,
    })
    discounts = [{ coupon: coupon.id }]
  }

  if (shopRounding) {
    lineItems.push({ price_data: { currency, unit_amount: Math.round(shopRounding.r * 100), product_data: { name: roundingLabel(body.locale) } }, quantity: 1 })
  }

  const returnOrigin = resolveReturnOrigin(body.origin, body.locale)
  const productMetadata: Record<string, string> = { order_id: orderId, type: 'shop', source: 'web',
    ...(isGear ? { kind: 'gear_rental' } : {}),
    ...(shopRounding ? { due: String(shopRounding.due), card_rounding: String(shopRounding.r) } : {}) }
  const sessionParams: Record<string, unknown> = {
    mode: 'payment',
    // Jen karta + Apple Pay/Google Pay (card wallets), bez Linku — viz booking checkout.
    payment_method_types: ['card'],
    line_items: lineItems as Stripe.Checkout.SessionCreateParams.LineItem[],
    metadata: productMetadata,
    payment_intent_data: { metadata: productMetadata },
    client_reference_id: orderId,
    success_url: withLangParam(isGear
      ? `${returnOrigin}/pujceni-obleceni?order_id=${orderId}&session_id={CHECKOUT_SESSION_ID}`
      : `${returnOrigin}/potvrzeni?order_id=${orderId}&session_id={CHECKOUT_SESSION_ID}`, body.locale),
    cancel_url: withLangParam(isGear ? `${returnOrigin}/pujceni-obleceni?order_id=${orderId}&payfail=1` : `${returnOrigin}/kosik`, body.locale),
    locale: resolveStripeLocale(body.locale),
  }
  if (custId) sessionParams.customer = custId
  if (discounts) sessionParams.discounts = discounts

  const session = await stripe.checkout.sessions.create(sessionParams as Stripe.Checkout.SessionCreateParams)

  await supabaseAdmin.from('shop_orders').update({
    stripe_session_id: session.id,
    stripe_payment_intent_id: session.payment_intent as string,
  }).eq('id', orderId)

  // ZF (proforma) — best-effort, neblokuje. D2 (oprava 2026-10-16): s dorovnáním na 15 Kč ne —
  // dorovnání zapíše do objednávky až webhook po zaplacení a doklady po platbě ho obsahují
  // (jinak by e-mailem odešla ZF na 10 Kč, zatímco strženo by bylo 15 Kč).
  if (!shopRounding) try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY },
      body: JSON.stringify({ type: 'shop_proforma', order_id: orderId, send_email: !isGear }),
    })
  } catch (e) { console.warn('[WebProductCheckout] ZF generation failed:', e) }

  return new Response(JSON.stringify({
    success: true,
    url: session.url,           // alias pro web (kompatibilita s checkout.js)
    checkout_url: session.url,
    session_id: session.id,
    order_id: orderId,
    ...(shopRounding ? { due: shopRounding.due, card_rounding: shopRounding.r, charge: CARD_MIN } : {}),
  }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
}

/** Handle web anonymous SHOP checkout — produkty (kind=products) NEBO voucher (default). */
export async function handleWebShopCheckout(
  body: PaymentRequest
): Promise<Response> {
  const webBody = body as Record<string, unknown>

  // Větvení: produkty z e-shopu (mají order_id z create_web_shop_order, nemají voucher_amount)
  // vs. dárkový poukaz (existující flow).
  // BEZPEČNOST 2026-10-11: KAŽDÝ požadavek s order_id jde do produktové větve (cena
  // z DB). Voucher větev dřív existující order_id převzala a session za klientem
  // zvolenou `voucher_amount` k ní připnula → zaplacením 15 Kč šlo potvrdit
  // libovolnou čekající objednávku. Web poukaz (poukazy-objednat.php) order_id
  // neposílá — voucher větev tak vždy zakládá VLASTNÍ novou objednávku.
  if (webBody.kind === 'products' || body.order_id) {
    return await handleWebProductCheckout(body, webBody)
  }

  const customerEmail = webBody.customer_email as string
  const customerName = (webBody.customer_name as string) || ''
  const customerPhone = (webBody.customer_phone as string) || ''
  const isPrint = !!(webBody.is_print)
  const voucherAmount = (webBody.voucher_amount as number) || body.amount
  const printFee = isPrint ? 180 : 0
  const shippingAddress = (webBody.shipping_address as string) || ''
  // Fakturační údaje z web formuláře poukazu (poukazy-objednat.php) — uloží se na
  // shop_orders, aby je generate-invoice dostal na DP/fakturu i u anonymní objednávky.
  const billingAddress = (webBody.billing_address as string) || ''
  const customerCompany = (webBody.customer_company as string) || ''
  const customerIco = (webBody.customer_ico as string) || ''
  const customerDic = (webBody.customer_dic as string) || ''
  const amountCzk = body.amount
  const amountCents = Math.round(amountCzk * 100)
  const currency = body.currency || 'czk'
  if (Number(amountCzk) > 0 && Number(amountCzk) < CARD_MIN) return belowMin(Number(amountCzk), CS.below_minimum_web)

  const customers = await stripe.customers.list({ email: customerEmail, limit: 1 })
  let custId = customers.data.length > 0 ? customers.data[0].id : null
  if (!custId) {
    const newCust = await stripe.customers.create({
      email: customerEmail,
      name: customerName,
      metadata: { source: 'web_shop' }
    })
    custId = newCust.id
  }

  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const orderId = body.order_id || crypto.randomUUID()
  if (!body.order_id) {
    // payment_status musí matchovat CHECK constraint shop_orders → pending/paid/refunded/failed.
    // Dříve zde bylo 'unpaid' (legacy z bookings.payment_status enum), což CHECK porušuje a INSERT
    // tiše selhal — voucher se pak nikdy nevytvořil a po Stripe platbě nedorazil mail.
    const { error: insertOrderError } = await supabaseAdmin.from('shop_orders').insert({
      id: orderId,
      customer_name: customerName,
      customer_email: customerEmail,
      customer_phone: customerPhone,
      shipping_address: shippingAddress || null,
      billing_address: billingAddress || null,
      customer_company: customerCompany || null,
      customer_ico: customerIco || null,
      customer_dic: customerDic || null,
      status: 'new',
      payment_status: 'pending',
      payment_method: 'stripe',
      total: amountCzk,
      subtotal: voucherAmount,
      // POZN: printFee NEDÁVÁME do shipping_cost — jinak generate-invoice
      // ho zobrazí 2× (jako "Doprava" + jako shop_order_item "Tisk a poštovné").
      // Položka "Tisk a poštovné" je v shop_order_items níže (isPrint branch).
      shipping_cost: 0,
      discount: 0,
      notes: isPrint ? 'Fyzický poukaz (tisk + poštovné)' : 'Elektronický poukaz',
      // i18n: jazyk zákazníka z webu (cs/en/de/nl/es/fr/pl) → voucher_purchased mail
      // i SMS dorazí přeložené (detect_customer_language čte shop_orders.language).
      language: resolveSiteLang(body.locale),
    })
    if (insertOrderError) {
      console.error('[WebShopCheckout] shop_orders insert failed:', insertOrderError.message)
      try {
        await supabaseAdmin.from('debug_log').insert({
          source: 'process-payment',
          action: 'web_shop_order_insert_failed',
          component: 'voucher_checkout',
          status: 'error',
          error_message: insertOrderError.message,
          request_data: { order_id: orderId, customer_email: customerEmail, voucher_amount: voucherAmount, is_print: isPrint },
        })
      } catch { /* ignore */ }
      return new Response(JSON.stringify({ error: 'Order creation failed', details: insertOrderError.message }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Hlavní položka: dárkový poukaz
    const orderItems: Record<string, unknown>[] = [{
      order_id: orderId,
      product_name: 'Dárkový poukaz',
      quantity: 1,
      unit_price: voucherAmount,
      total_price: voucherAmount,
    }]

    // Fyzický tisk + poštovné (název BEZ "poukaz" aby trigger negeneroval voucher)
    if (isPrint) {
      orderItems.push({
        order_id: orderId,
        product_name: 'Tisk a poštovné',
        quantity: 1,
        unit_price: printFee,
        total_price: printFee,
      })
    }

    await supabaseAdmin.from('shop_order_items').insert(orderItems)
  }

  // Stripe line items (separate for clarity on Stripe receipt)
  const lineItems: Record<string, unknown>[] = [{
    price_data: {
      currency,
      unit_amount: Math.round(voucherAmount * 100),
      product_data: { name: 'MotoGo24 — Dárkový poukaz' }
    },
    quantity: 1
  }]
  if (isPrint) {
    lineItems.push({
      price_data: {
        currency,
        unit_amount: Math.round(printFee * 100),
        product_data: { name: 'Tisk a poštovné' }
      },
      quantity: 1
    })
  }

  const voucherReturnOrigin = resolveReturnOrigin(body.origin, body.locale)
  const voucherMetadata = { order_id: orderId, type: 'shop', source: 'web' }
  const session = await stripe.checkout.sessions.create({
    customer: custId,
    mode: 'payment',
    // Jen karta + Apple Pay/Google Pay (card wallets), bez Linku — viz booking checkout.
    payment_method_types: ['card'],
    line_items: lineItems as Stripe.Checkout.SessionCreateParams.LineItem[],
    metadata: voucherMetadata,
    payment_intent_data: { metadata: voucherMetadata },
    client_reference_id: orderId,
    success_url: withLangParam(`${voucherReturnOrigin}/potvrzeni?order_id=${orderId}&session_id={CHECKOUT_SESSION_ID}`, body.locale),
    cancel_url: withLangParam(`${voucherReturnOrigin}/poukazy`, body.locale),
    locale: resolveStripeLocale(body.locale) as Stripe.Checkout.SessionCreateParams.Locale,
  })

  await supabaseAdmin.from('shop_orders').update({
    stripe_session_id: session.id,
    stripe_payment_intent_id: session.payment_intent as string,
  }).eq('id', orderId)

  // ZF doklad pro voucher objednávku ANO (účetní doklad), ale e-mail s ním NE.
  // Voucher objednávky jsou speciální — zákazník dostane jen "Váš dárkový poukaz od MotoGo24"
  // mail po platbě (z webhook-receiver/confirmShopPayment) s DP + HTML voucher přílohami.
  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }

    await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
      method: 'POST', headers,
      body: JSON.stringify({ type: 'shop_proforma', order_id: orderId, send_email: false }),
    })
  } catch (e) { console.warn('[WebShopCheckout] ZF generation failed:', e) }

  return new Response(JSON.stringify({ checkout_url: session.url, session_id: session.id, order_id: orderId }), {
    headers: { ...CORS, 'Content-Type': 'application/json' }
  })
}
