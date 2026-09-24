// ===== MotoGo24 – Edge Function: Process Payment (Stripe LIVE) =====
// Supports booking, shop, extension, and SOS payments via Stripe Checkout or inline PaymentIntent.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'
import { stripe, SITE_URL, PRODUCT_NAMES, CORS, PaymentType, PaymentRequest, getOrCreateStripeCustomer } from './stripe-customer.ts'
import { authClassify } from '../_shared/auth.ts'
import { handleWebBookingCheckout, handleWebShopCheckout, handleSosPaymentLink } from './payment-flows.ts'

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
    // Voucher/e-shop potvrzení dosud záviselo VÝHRADNĚ na asynchronním Stripe webhooku
    // (webhook-receiver → confirmShopPayment). Když webhook nedorazil / zpozdil se, objednávka
    // zůstala `pending`, voucher se nevygeneroval a mail „Váš dárkový poukaz od MotoGo24"
    // nedorazil — zákazník po stržené platbě uvízl na „Platba ještě nebyla potvrzena" (viz
    // bug report). /potvrzeni page teď volá tuto akci se `session_id` (+ `order_id`) ze
    // success_url a potvrdí platbu synchronně, nezávisle na doručení webhooku.
    // Idempotence: confirm_shop_payment je atomic (UPDATE … WHERE payment_status<>'paid'
    // RETURNING) a vrací `was_already_paid` — když webhook (nebo dřívější poll) potvrdil dřív,
    // jen vrátíme already_paid a NEposíláme druhý mail. Když atomic flip vyhrajeme my,
    // dogenerujeme voucher/FV a pošleme mail (stejný flow jako confirmShopPayment v webhooku).
    if ((body as Record<string, unknown>).action === 'verify_shop_session') {
      const sessionId = (body as Record<string, unknown>).session_id as string | undefined
      let orderId = ((body as Record<string, unknown>).order_id as string | undefined) || null
      if (!sessionId && !orderId) {
        return new Response(JSON.stringify({ success: false, error: 'Missing session_id or order_id' }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      )
      try {
        // Dohledej stripe_session_id z objednávky, pokud klient session_id neposlal
        // (starší odkaz / přímá navigace na /potvrzeni?order_id=…).
        let sid = sessionId || null
        if (!sid && orderId) {
          const { data: ord } = await supabaseAdmin.from('shop_orders')
            .select('stripe_session_id').eq('id', orderId).maybeSingle()
          sid = (ord?.stripe_session_id as string | null) || null
        }
        if (!sid) {
          return new Response(JSON.stringify({ success: false, error: 'No session to verify' }),
            { headers: { ...CORS, 'Content-Type': 'application/json' } })
        }
        const session = await stripe.checkout.sessions.retrieve(sid)
        const md = (session.metadata || {}) as Record<string, string>
        // BEZPEČNOST 2026-09-24: objednávku určuje VÝHRADNĚ zaplacená session
        // (metadata.order_id / client_reference_id), ne order_id z požadavku —
        // jinak by šla jednou zaplacenou session potvrdit libovolná jiná
        // objednávka. order_id z požadavku smí jen souhlasit.
        const sessionOrderId = md.order_id || (session.client_reference_id as string | null) || null
        if (sessionOrderId) {
          if (orderId && orderId !== sessionOrderId) {
            return new Response(JSON.stringify({ success: false, error: 'order_mismatch' }),
              { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
          }
          orderId = sessionOrderId
        } else if (orderId && sessionId) {
          // Session bez vazby na objednávku → přijmi jen, když ji má u sebe
          // uloženou sama objednávka (web ji zapisuje při vytvoření session).
          const { data: ord } = await supabaseAdmin.from('shop_orders')
            .select('stripe_session_id').eq('id', orderId).maybeSingle()
          if ((ord?.stripe_session_id as string | null) !== sid) {
            return new Response(JSON.stringify({ success: false, error: 'order_mismatch' }),
              { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
          }
        }
        if (!orderId) {
          return new Response(JSON.stringify({ success: false, error: 'No order_id in session' }),
            { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
        }
        // Dokud Stripe platbu nepotvrdil, vrátíme pending — klient pollne znovu
        // (webhook může dorazit mezitím). Potvrzujeme JEN reálně zaplacenou
        // session (dřív stačilo status 'complete', které nastane i bez platby).
        const freeSession = session.payment_status === 'no_payment_required' &&
          (session.amount_total ?? 0) === 0  // web objednávka celá pokrytá slevou
        if (session.payment_status !== 'paid' && !freeSession) {
          return new Response(JSON.stringify({ success: false, payment_status: session.payment_status, status: session.status }),
            { headers: { ...CORS, 'Content-Type': 'application/json' } })
        }
        const piId = typeof session.payment_intent === 'string'
          ? session.payment_intent
          : ((session.payment_intent as { id?: string } | null)?.id || null)

        // ATOMIC confirm — stejná RPC jako webhook (confirmShopPayment). was_already_paid=true
        // → webhook nebo dřívější poll už potvrdil; skončíme bez druhého mailu.
        const { data: confirmData, error: rpcErr } = await supabaseAdmin.rpc('confirm_shop_payment', {
          p_order_id: orderId, p_method: 'card',
        })
        if (rpcErr) {
          // Fallback přímý UPDATE — BEFORE UPDATE trigger auto_process_voucher_order vygeneruje
          // voucher i tak (OLD.payment_status='pending' → NEW.payment_status='paid').
          await supabaseAdmin.from('shop_orders')
            .update({ payment_status: 'paid', payment_method: 'card', confirmed_at: new Date().toISOString() })
            .eq('id', orderId).neq('payment_status', 'paid')
        }
        const wasAlreadyPaid = !!(confirmData as Record<string, unknown> | null)?.was_already_paid

        if (piId) {
          try {
            await supabaseAdmin.from('shop_orders')
              .update({ stripe_payment_intent_id: piId, stripe_session_id: sid })
              .eq('id', orderId).is('stripe_payment_intent_id', null)
          } catch { /* ignore */ }
        }

        try {
          await supabaseAdmin.from('debug_log').insert({
            source: 'process-payment', action: 'verify_shop_session_confirmed',
            component: 'voucher_checkout', status: 'ok',
            request_data: { session_id: sid, order_id: orderId, was_already_paid: wasAlreadyPaid },
          })
        } catch { /* ignore */ }

        if (wasAlreadyPaid) {
          return new Response(JSON.stringify({ success: true, already_paid: true, order_id: orderId }),
            { headers: { ...CORS, 'Content-Type': 'application/json' } })
        }

        // Vyhráli jsme atomic flip → dogenerujeme voucher (pojistka, kdyby trigger selhal),
        // FV (účetní doklad) a pošleme voucher_purchased mail — zrcadlí confirmShopPayment.
        try {
          const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
          const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
          const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }

          const { data: order } = await supabaseAdmin.from('shop_orders')
            .select('customer_name, customer_email, order_number, status, total')
            .eq('id', orderId).single()
          const { data: items } = await supabaseAdmin.from('shop_order_items')
            .select('product_name').eq('order_id', orderId)
          const hasVoucherItem = (items || []).some((it: { product_name?: string }) =>
            /voucher|poukaz/i.test(String(it.product_name || '')))
          let { data: vouchers } = await supabaseAdmin.from('vouchers')
            .select('code, amount, valid_until').eq('order_id', orderId)
          if (hasVoucherItem && (!vouchers || vouchers.length === 0)) {
            try { await supabaseAdmin.rpc('regen_voucher_for_order', { p_order_id: orderId }) } catch { /* ignore */ }
            const re = await supabaseAdmin.from('vouchers')
              .select('code, amount, valid_until').eq('order_id', orderId)
            vouchers = re.data
          }
          // FV (shop_final) pro doručený elektronický voucher — jen účetní doklad ve Velínu.
          if (order?.status === 'delivered') {
            try {
              await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
                method: 'POST', headers,
                body: JSON.stringify({ type: 'shop_final', order_id: orderId, send_email: false }),
              })
            } catch { /* ignore */ }
          }
          if (order?.customer_email && vouchers && vouchers.length > 0) {
            const orderNum = order.order_number || orderId.slice(-8).toUpperCase()
            const firstVoucher = vouchers[0] as { code: string; amount: number; valid_until: string }
            const allCodes = vouchers
              .map((v: { code: string; amount: number }) => `${v.code} (${v.amount} Kč)`)
              .join(', ')
            await fetch(`${SUPABASE_URL}/functions/v1/send-booking-email`, {
              method: 'POST', headers,
              body: JSON.stringify({
                type: 'voucher_purchased',
                customer_email: order.customer_email,
                customer_name: order.customer_name || '',
                voucher_code: allCodes,
                voucher_value: String(firstVoucher.amount),
                voucher_expiry: firstVoucher.valid_until,
                order_number: orderNum,
                order_id: orderId,
                source: 'web',
              }),
            })
          }
        } catch (e) {
          try {
            await supabaseAdmin.from('debug_log').insert({
              source: 'process-payment', action: 'verify_shop_session_postprocess_failed',
              component: 'voucher_checkout', status: 'error',
              error_message: (e as Error).message,
              request_data: { order_id: orderId },
            })
          } catch { /* ignore */ }
        }

        return new Response(JSON.stringify({ success: true, confirmed: true, order_id: orderId }),
          { headers: { ...CORS, 'Content-Type': 'application/json' } })
      } catch (e) {
        return new Response(JSON.stringify({ success: false, error: (e as Error).message }),
          { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } })
      }
    }

    // --- Velín operátor: Stripe odkaz pro placenou SOS náhradu ---
    if ((body as Record<string, unknown>).action === 'create_sos_payment_link') {
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      )
      return await handleSosPaymentLink(body, supabaseAdmin)
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

    const { booking_id, order_id, incident_id, amount, currency, method, type, mode, payment_method_id, change } = body
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

    // ── E-shop z appky: částku určuje SERVER (2026-09-24) ─────────────────
    // Dřív se strhla částka poslaná appkou a k libovolnému order_id — cenu
    // tak určoval klient. Nově: jen vlastník, jen čekající objednávka a částka
    // MUSÍ odpovídat shop_orders.total (počítá create_shop_order ze serverových
    // cen, 20260924b). Jiná částka = odmítnuto (nedoplatek se nesmí stát).
    // Web (source 'web' + customer_email) sem nechodí — handleWebShopCheckout
    // výše si cenu bere z DB sám.
    if (paymentType === 'shop') {
      const json = (status: number, payload: Record<string, unknown>) => new Response(
        JSON.stringify({ success: false, ...payload }),
        { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
      const who = await authClassify(req)
      if (who.kind === 'none') {
        return json(401, { error: 'Přihlášení chybí nebo vypršelo — přihlaste se prosím znovu.', code: 'auth_required' })
      }
      const sbShop = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      )
      const { data: ord } = await sbShop.from('shop_orders')
        .select('id, customer_id, payment_status, total')
        .eq('id', order_id!).maybeSingle()
      if (!ord) return json(404, { error: 'Objednávka nenalezena.', code: 'order_not_found' })
      const owner = who.kind === 'service' || who.kind === 'admin' ||
        (who.kind === 'user' && !!who.userId && who.userId === ord.customer_id)
      if (!owner) return json(403, { error: 'Tuto objednávku nelze zaplatit z tohoto účtu.', code: 'forbidden' })
      if (ord.payment_status === 'paid') return json(409, { error: 'Objednávka je už zaplacená.', code: 'already_paid' })
      if (ord.payment_status !== 'pending') return json(409, { error: 'Tuto objednávku už nelze zaplatit.', code: 'wrong_status' })
      const serverCzk = Math.round(Number(ord.total) || 0)
      if (serverCzk <= 0) return json(409, { error: 'Objednávka nevyžaduje platbu.', code: 'no_payment_needed' })
      if (serverCzk < 15) return json(400, { error: 'Minimální částka platby kartou je 15 Kč.', code: 'below_minimum' })
      if (Math.round(Number(amount)) !== serverCzk) {
        return json(409, {
          error: `Cena objednávky se přepočítala na ${serverCzk} Kč. Vraťte se prosím do košíku a objednávku odešlete znovu.`,
          code: 'amount_mismatch', server_total: serverCzk,
        })
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
    // Stripe metadata: hodnota max 500 znaků — delší payload (typicky dlouhá
    // adresa přistavení) se do metadat nevejde, v tom případě zůstává původní
    // klientský fallback (_applyPendingAfterPayment z localStorage).
    if (paymentType === 'extension' && change && typeof change === 'object') {
      try {
        const chgStr = JSON.stringify(change)
        if (chgStr.length <= 500) metadata.chg = chgStr
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
      let dryErr: string | null = null
      const day = (v: unknown) => String(v || '').slice(0, 10)
      const hm = (v: unknown) => (v == null ? '' : String(v).slice(0, 5))

      // ── 0) Rezervace se načte JEDNOU (service client, nezávisle na RLS) pro
      // všechny kontroly níže. Nenačtená / neexistující → platbu odmítnout
      // (fail closed) — bez řádku nevíme nic o vlastníkovi, ceně ani vozíku.
      type CurRow = {
        user_id: string | null; status: string | null; total_price: number | null; trailer_moto_id: string | null
        moto_id: string | null; start_date: string | null; end_date: string | null; pickup_time: string | null
        motorcycles: { is_trailer: boolean | null } | { is_trailer: boolean | null }[] | null
      }
      let cur: CurRow | null = null
      try {
        const { data, error } = await supabase.from('bookings')
          .select('user_id, status, total_price, trailer_moto_id, moto_id, start_date, end_date, pickup_time, motorcycles!moto_id(is_trailer)')
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
          return new Response(
            JSON.stringify({ success: false, error: 'Přihlášení chybí nebo vypršelo — přihlaste se prosím znovu a úpravu zopakujte.', code: 'auth_required' }),
            { status: 401, headers: { ...CORS, 'Content-Type': 'application/json' } }
          )
        }
        // `service` = podepsaný service_role JWT (isServiceRole ověřuje podpis
        // přes PostgREST; pouhý claim v payloadu by šel podvrhnout).
        const owner = who.kind === 'service' || who.kind === 'admin' ||
          (who.kind === 'user' && !!who.userId && who.userId === cur.user_id)
        if (!owner) {
          return new Response(
            JSON.stringify({ success: false, error: 'Tuto rezervaci nelze upravit z tohoto účtu. Přihlaste se prosím účtem, kterým byla vytvořena.', code: 'forbidden' }),
            { status: 403, headers: { ...CORS, 'Content-Type': 'application/json' } }
          )
        }
      }

      // Stornovaná / ukončená rezervace se neupravuje (a nesmí se za ni platit —
      // confirm_payment by ji jinak „oživil“). RPC větve to hlídají samy
      // (wrong_status), app formát dosud ne.
      if (!dryErr && cur && ['cancelled', 'completed'].includes(String(cur.status || ''))) dryErr = 'wrong_status'

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
          return new Response(
            JSON.stringify({ success: false, error: 'Rezervace se mezitím změnila (jiné zařízení nebo web). Načtěte ji prosím znovu a úpravu zopakujte.', code: 'stale_booking' }),
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
            const { data, error } = await userClient.rpc('split_booking_moto_swap', {
              p_booking_id: booking_id, p_new_moto_id: sw.m, p_swap_date: sw.d,
              p_swap_time: sw.t || null, p_dry_run: true,
            })
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
            if (!error && data?.success === true) expected = Number(data.net_diff || 0)
            else if (!error && data?.error) dryErr = String(data.error)
            else dryErr = 'validation_unavailable'
          } else if (c.total_price != null && Number.isFinite(Number(c.total_price))) {
            // App formát (DB názvy sloupců, payment_screen.dart): appka účtuje
            // effectivePriceDiff = nová total_price − total_price rezervace, takže
            // doplatek MUSÍ sedět na rozdíl vůči AKTUÁLNÍ ceně v DB.
            expected = Math.round(Number(c.total_price) - Number(cur.total_price || 0))
            // Vozík vydává jen OBSLUŽNÁ pobočka (20260921b–h). Appka mění motorku
            // PŘÍMÝM UPDATE, takže `_apply_booking_changes_core` ani jeho guard
            // nikdy nezavolá — jediné místo PŘED platbou, kudy tahle cesta projde,
            // je tenhle validátor. Jen při SKUTEČNÉ změně motorky u rezervace
            // s vozíkem (legacy rezervace s vozíkem na samoobsluze jde dál
            // prodloužit). Fail closed.
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
        }
        const dryMsg = dryMsgs[dryErr] ?? `Změnu nelze aplikovat (${dryErr}) — platba doplatku zrušena. Obnovte stránku a zkuste znovu.`
        return new Response(
          JSON.stringify({ success: false, error: dryMsg, code: dryErr }),
          { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      if (expected != null && Math.abs(Number(amount) - expected) > 1) {
        return new Response(
          JSON.stringify({ success: false, error: `Částka doplatku neodpovídá výpočtu serveru (${expected} Kč). Obnovte stránku a zkuste znovu.`, code: 'amount_mismatch', expected }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
    }

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
      // Hosted Checkout „stránka stripe" (web, např. úprava rezervace): JEN karta +
      // Apple Pay/Google Pay (card wallets), bez Linku — aby default nebyla matoucí
      // „Link-first" přihlašovací obrazovka. Shodné s handleWeb*Checkout v payment-flows.ts.
      // (App native Payment Sheet výše, mode:'intent', Link ZÁMĚRNĚ drží.)
      payment_method_types: ['card'],
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
