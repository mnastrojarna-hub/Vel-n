// ===== MotoGo24 – Edge Function: Process Payment (Stripe LIVE) =====
// Supports booking, shop, extension, and SOS payments via Stripe Checkout or inline PaymentIntent.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'
import { stripe, SITE_URL, PRODUCT_NAMES, CORS, PaymentType, PaymentRequest, getOrCreateStripeCustomer } from './stripe-customer.ts'
import { handleWebBookingCheckout, handleWebShopCheckout } from './payment-flows.ts'

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
              .select('booking_source, start_date, end_date, total_price, motorcycles(model, manual_url), profiles(full_name, email)')
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

    const { booking_id, order_id, incident_id, amount, currency, method, type, mode, payment_method_id } = body
    const paymentType: PaymentType = type || 'booking'
    const paymentMode = mode || 'intent'
    const explicitSuccessUrl = (body as Record<string, unknown>).success_url as string | undefined
    const explicitCancelUrl = (body as Record<string, unknown>).cancel_url as string | undefined

    // Validate required fields
    if ((paymentType === 'booking' || paymentType === 'extension' || paymentType === 'sos') && !booking_id) {
      return new Response(
        JSON.stringify({ success: false, error: `Missing booking_id for ${paymentType} payment` }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
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
        return new Response(
          JSON.stringify({ success: false, error: 'Tato rezervace je již zaplacena.' }),
          { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
    }
    if (paymentType === 'shop' && !order_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing order_id for shop payment' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }
    if (amount == null) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing amount' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
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

    // -- FREE BOOKING (100% discount) — POUZE pokud je sleva skutečně 100% --
    if (amount <= 0 && booking_id) {
      const { data: dbBooking } = await supabase.from('bookings')
        .select('total_price, payment_status, promo_code_id, voucher_id, discount_amount')
        .eq('id', booking_id)
        .single()

      if (dbBooking?.payment_status === 'paid') {
        return new Response(
          JSON.stringify({ success: false, error: 'Tato rezervace je již zaplacena.' }),
          { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      if (dbBooking && dbBooking.total_price > 0) {
        return new Response(
          JSON.stringify({ success: false, error: 'Částka neodpovídá ceně rezervace (' + dbBooking.total_price + ' Kč). Obnovte stránku a zkuste znovu.' }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
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

      if (!isTrue100) {
        console.error('Free booking rejected — discount is not truly 100%:', {
          booking_id, total_price: dbBooking?.total_price,
          discount_amount: dbBooking?.discount_amount, promo_code_id: dbBooking?.promo_code_id
        })
        return new Response(
          JSON.stringify({ success: false, error: 'Chyba kalkulace ceny. Sleva není 100%. Obnovte stránku a zkuste znovu.' }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      const { error: rpcError } = await supabase.rpc('confirm_payment', {
        p_booking_id: booking_id,
        p_method: 'free'
      })

      if (rpcError) {
        console.error('confirm_payment RPC failed for free booking:', rpcError.message)
        return new Response(
          JSON.stringify({ success: false, error: 'Potvrzení rezervace selhalo. Zkuste to znovu.' }),
          { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      try {
        await supabase.from('debug_log').insert({
          source: 'process-payment', action: 'free_booking_confirmed',
          component: paymentType, status: 'ok',
          request_data: { booking_id, amount, type: paymentType },
        })
      } catch { /* ignore */ }

      return new Response(
        JSON.stringify({ success: true, free: true, booking_id }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // -- MODE: INTENT --
    if (paymentMode === 'intent') {
      const amountCents = Math.round(amount * 100)

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
          const intent = await stripe.paymentIntents.create(offSessionParams)
          try {
            if (booking_id) await supabase.from('bookings').update({ stripe_payment_intent_id: intent.id }).eq('id', booking_id)
            if (order_id) await supabase.from('shop_orders').update({ stripe_payment_intent_id: intent.id }).eq('id', order_id)
          } catch { /* non-blocking */ }
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
            return new Response(
              JSON.stringify({
                success: true, off_session: true, status: 'succeeded',
                payment_intent_id: intent.id, amount, currency: currency || 'czk',
              }),
              { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
            )
          }
          // requires_action → klient musí dokončit SCA (3DS) přes Stripe SDK
          if (intent.status === 'requires_action' || intent.status === 'requires_confirmation') {
            return new Response(
              JSON.stringify({
                success: true, off_session: true, status: intent.status,
                client_secret: intent.client_secret,
                payment_intent_id: intent.id, amount, currency: currency || 'czk',
              }),
              { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
            )
          }
          // jiný stav (canceled/processing/requires_payment_method) — vrátíme jako fallback,
          // klient ukáže Payment Sheet
          return new Response(
            JSON.stringify({
              success: false, off_session: true, status: intent.status,
              error: 'off_session_unexpected_status',
              payment_intent_id: intent.id,
            }),
            { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
          )
        } catch (e) {
          // Typicky `authentication_required`, `card_declined`, `insufficient_funds`,
          // `expired_card`. Pro authentication_required obsahuje err.raw.payment_intent
          // klientův PI — vrátíme ho, aby klient pokračoval přes handleNextAction.
          const stripeErr = e as Stripe.StripeRawError & { payment_intent?: { id: string, client_secret: string, status: string } }
          const piFromError = (stripeErr.raw as Record<string, unknown> | undefined)?.payment_intent as { id: string, client_secret: string, status: string } | undefined
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
            return new Response(
              JSON.stringify({
                success: true, off_session: true, status: 'requires_action',
                client_secret: piFromError.client_secret,
                payment_intent_id: piFromError.id, amount, currency: currency || 'czk',
              }),
              { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
            )
          }
          return new Response(
            JSON.stringify({
              success: false, off_session: true,
              error: 'off_session_charge_failed',
              error_code: stripeErr.code || null,
              decline_code: stripeErr.decline_code || null,
              message: stripeErr.message || 'Strhnutí uložené karty selhalo.',
            }),
            { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
          )
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
      const intent = await stripe.paymentIntents.create(intentParams as Stripe.PaymentIntentCreateParams)

      // Create ephemeral key for Payment Sheet (saved cards support)
      let ephemeralKey: string | null = null
      if (customerId) {
        try {
          const ek = await stripe.ephemeralKeys.create(
            { customer: customerId },
            { apiVersion: '2024-04-10' }
          )
          ephemeralKey = ek.secret ?? null
        } catch (e) { /* non-blocking — Payment Sheet works without it */ }
      }

      try {
        if (booking_id) {
          await supabase.from('bookings').update({ stripe_payment_intent_id: intent.id }).eq('id', booking_id)
        }
        if (order_id) {
          await supabase.from('shop_orders').update({ stripe_payment_intent_id: intent.id }).eq('id', order_id)
        }
      } catch (e) { /* non-blocking */ }

      try {
        await supabase.from('debug_log').insert({
          source: 'process-payment', action: 'stripe_intent_created',
          component: paymentType, status: 'ok',
          request_data: { booking_id, order_id, incident_id, amount, currency, type: paymentType, mode: 'intent' },
          response_data: { payment_intent_id: intent.id },
        })
      } catch (e) { /* ignore */ }

      return new Response(
        JSON.stringify({
          success: true, client_secret: intent.client_secret,
          payment_intent_id: intent.id, amount, currency: currency || 'czk',
          // Payment Sheet support — Flutter uses these for saved cards
          customer_id: customerId || null,
          ephemeral_key: ephemeralKey,
        }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // -- MODE: CHECKOUT --
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
    const finalSuccessUrl = isValidHttpsUrl(explicitSuccessUrl) ? explicitSuccessUrl! : SITE_URL + successPath
    const finalCancelUrl  = isValidHttpsUrl(explicitCancelUrl)  ? explicitCancelUrl!  : SITE_URL + cancelPath

    const sessionParams: Record<string, unknown> = {
      line_items: [{
        price_data: {
          currency: currency || 'czk',
          product_data: { name: productName },
          unit_amount: Math.round(amount * 100),
        },
        quantity: 1,
      }],
      mode: 'payment',
      payment_method_types: ['card', 'link'],
      success_url: finalSuccessUrl,
      cancel_url: finalCancelUrl,
      metadata,
      locale: 'cs',
    }

    if (customerId) {
      sessionParams.customer = customerId
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
        amount, currency: currency || 'czk',
      }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('Stripe payment error:', err)

    try {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      )
      await supabase.from('debug_log').insert({
        source: 'process-payment', action: 'stripe_error',
        component: 'stripe', status: 'error',
        error_message: (err as Error).message,
      })
    } catch (e) { /* ignore */ }

    return new Response(
      JSON.stringify({ success: false, error: 'Payment processing failed: ' + (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})
