// ===== MotoGo24 – Edge Function: Webhook Receiver (Stripe LIVE) =====
// Receives Stripe webhook events and processes payment confirmations server-side.
// Endpoint: POST /functions/v1/webhook-receiver
// Stripe sends: checkout.session.completed, payment_intent.succeeded, charge.refunded, payout.paid
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'https://esm.sh/stripe@14';
import { confirmBookingPayment, confirmSosPayment, confirmShopPayment, ingestFinancialEvent } from './payment-confirmers.ts';
import { syncCardFromSetupSession, syncCardsForCustomer } from './stripe-card-sync.ts';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY'), {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient()
});
const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET') || '';
// ── Server-side aplikace doplatkové změny rezervace po potvrzení platby ──────
// Web „Upravit rezervaci" u změny s doplatkem (prodloužení / změna místa, času,
// motorky) dříve aplikoval změnu AŽ v prohlížeči po návratu ze Stripe
// (_applyPendingAfterPayment z localStorage). Když se zákazník nevrátil (platba
// na jiném zařízení, vyčištěné úložiště, zavřená záložka), změna se nikdy
// neuložila → rezervace zaplacena, ale neprodloužena a mail web_booking_modified
// nedorazil. Tady ji aplikujeme server-side z payloadu v Stripe metadatech
// (`metadata.chg`), což spustí trigger trg_send_booking_modified_email
// nezávisle na klientovi. Mapování polí je 1:1 s klientským fallbackem; update
// je idempotentní (stejné hodnoty + absolutní total_price z new_total), takže
// případný druhý Stripe event ani souběžný klientský apply nezpůsobí duplicitu
// (mail navíc dedupuje 5min okno v triggeru).
async function applyExtensionChange(supabase, bookingId, chgStr) {
  if (!chgStr) return;
  let a;
  try {
    a = JSON.parse(chgStr);
  } catch  {
    return;
  }
  if (!a || typeof a !== 'object') return;
  // ── Výměna motorky (swap) — server-side COMMIT po zaplacení doplatku ─────────
  // Appka commit volá klientsky po platbě (payment_screen `_swap_commit`), ale
  // když selže / je zabita, výměna se tiše neprovede a peníze jsou strženy
  // (incident #EEC9CA33). Webhook je proto pojistka: `_swap` metadata → zavolej
  // COMMIT RPC (service_role — pouští ho rev.5 split_booking_moto_swap).
  // Idempotence s appkou: `already_split` (split už vznikl) a `invalid_new_moto`
  // (replace už proběhl → moto_id == nová) znamenají „appka byla rychlejší" = OK.
  const swap = a._swap;
  if (swap && typeof swap === 'object' && swap.m && swap.d) {
    const { data, error } = await supabase.rpc('split_booking_moto_swap', {
      p_booking_id: bookingId,
      p_new_moto_id: swap.m,
      p_swap_date: swap.d,
      p_swap_time: swap.t || null,
      p_dry_run: false
    });
    const res = data || {};
    const ok = !error && (res.success === true || res.error === 'already_split' || res.error === 'invalid_new_moto');
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: ok ? 'swap_commit_applied' : 'swap_commit_failed',
        component: 'stripe',
        status: ok ? 'ok' : 'error',
        error_message: error?.message || (res.success !== true ? String(res.error || '') : null),
        request_data: {
          booking_id: bookingId,
          swap,
          rpc_result: res
        }
      });
    } catch  {}
    return;
  }
  // ── Změna výbavy (placená gear) — řeší vlastní SECURITY DEFINER RPC ──────────
  // gear se neukládá pouhým bookings.update (mění i booking_extras + extras_price).
  // apply_paid_gear_change(p_booking_id, p_sizes) je service-role wrapper, který
  // impersonuje vlastníka a volá existující update_booking_gear (idempotentní:
  // net_diff se počítá vůči aktuálnímu stavu → druhý běh = 0). Změna total_price
  // spustí trg_send_booking_modified_email → web_booking_modified. Když RPC ještě
  // neexistuje (SQL nenasazena), chyba se zaloguje a gear padá zpět na klientský
  // _applyPendingAfterPayment (žádná regrese).
  const gear = a._gear;
  if (gear && typeof gear === 'object') {
    const { error } = await supabase.rpc('apply_paid_gear_change', {
      p_booking_id: bookingId,
      p_sizes: gear.sizes || {}
    });
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: error ? 'gear_change_apply_failed' : 'gear_change_applied',
        component: 'stripe',
        status: error ? 'error' : 'ok',
        error_message: error?.message || null,
        request_data: {
          booking_id: bookingId
        }
      });
    } catch  {}
    return;
  }
  const def = (v)=>v !== undefined;
  const defNN = (v)=>v !== undefined && v !== null;
  const d = {};
  if (a.p_new_start) d.start_date = a.p_new_start;
  if (a.p_new_end) d.end_date = a.p_new_end;
  if (a.p_new_moto_id) d.moto_id = a.p_new_moto_id;
  if (a.p_new_pickup_method) d.pickup_method = a.p_new_pickup_method;
  if (def(a.p_new_pickup_address)) d.pickup_address = a.p_new_pickup_address;
  if (defNN(a.p_new_pickup_lat)) d.pickup_lat = a.p_new_pickup_lat;
  if (defNN(a.p_new_pickup_lng)) d.pickup_lng = a.p_new_pickup_lng;
  if (a.p_new_return_method) d.return_method = a.p_new_return_method;
  if (def(a.p_new_return_address)) d.return_address = a.p_new_return_address;
  if (defNN(a.p_new_return_lat)) d.return_lat = a.p_new_return_lat;
  if (defNN(a.p_new_return_lng)) d.return_lng = a.p_new_return_lng;
  if (def(a.p_new_pickup_fee) || def(a.p_new_return_fee)) {
    d.delivery_fee = Number(a.p_new_pickup_fee || 0) + Number(a.p_new_return_fee || 0);
  }
  // Time-only úprava z webu posílá pickup_time jako p_new_pickup_time (RPC arg),
  // ne v _time_update — bez tohoto mapování zákazník zaplatil ztrátu late-pickup
  // slevy, ale čas vyzvednutí se po platbě nikdy nezapsal.
  if (a.p_new_pickup_time) d.pickup_time = a.p_new_pickup_time;
  const tu = a._time_update;
  if (tu && typeof tu === 'object') {
    if (def(tu.pickup_time)) d.pickup_time = tu.pickup_time;
    if (def(tu.return_time)) d.return_time = tu.return_time;
  }
  // App formát (Flutter posílá kompaktní `change` přímo s DB názvy sloupců —
  // payment_screen.dart) — stejná záchranná síť jako web: doplatková změna se
  // uloží server-side, i když je appka po platbě zabita / spadne před apply.
  // delivery_fee/extras_price appka do metadat posílá — bez nich by rozpis KF
  // po webhook-aplikované změně neseděl (generate_final_invoice čte delivery_fee).
  for (const col of [
    'start_date',
    'end_date',
    'moto_id',
    'pickup_method',
    'pickup_address',
    'return_method',
    'return_address',
    'pickup_time',
    'return_time',
    'discount_amount',
    'delivery_fee',
    'extras_price',
    'loyalty_discount_amount'
  ]){
    if (def(a[col]) && d[col] === undefined) d[col] = a[col];
  }
  // Absolutní cílová cena (z dry-run RPC) — idempotentní, na rozdíl od klienta,
  // který total_price vůbec nenastavoval (doplatek se nepropisoval do ceny).
  if (a.new_total != null && Number.isFinite(Number(a.new_total))) {
    d.total_price = Number(a.new_total);
  } else if (a.total_price != null && Number.isFinite(Number(a.total_price))) {
    d.total_price = Number(a.total_price) // app formát
    ;
  }
  if (Object.keys(d).length === 0) return;
  // Změna termínu → zapiš modification_history (+ original_* při prvním zásahu),
  // stejně jako RPC cesty. Bez záznamu by rozdílový doklad (generate-invoice
  // source='edit') neměl čerstvý podklad pro denní rozpis přidaných dnů a Velín
  // by webhook-aplikované prodloužení neviděl v historii úprav.
  if (d.start_date || d.end_date) {
    try {
      const { data: cur } = await supabase.from('bookings').select('start_date, end_date, original_start_date, modification_history').eq('id', bookingId).maybeSingle();
      if (cur) {
        const day = (v)=>String(v || '').slice(0, 10);
        const fromS = day(cur.start_date);
        const fromE = day(cur.end_date);
        const toS = d.start_date ? day(d.start_date) : fromS;
        const toE = d.end_date ? day(d.end_date) : fromE;
        if (toS !== fromS || toE !== fromE) {
          const hist = Array.isArray(cur.modification_history) ? cur.modification_history : [];
          hist.push({
            at: new Date().toISOString(),
            from_start: fromS,
            from_end: fromE,
            to_start: toS,
            to_end: toE,
            source: 'stripe_webhook'
          });
          d.modification_history = hist;
          if (!cur.original_start_date) {
            d.original_start_date = fromS;
            d.original_end_date = fromE;
          }
        }
      }
    } catch  {}
  }
  const { error } = await supabase.from('bookings').update(d).eq('id', bookingId);
  try {
    await supabase.from('debug_log').insert({
      source: 'webhook-receiver',
      action: error ? 'extension_change_apply_failed' : 'extension_change_applied',
      component: 'stripe',
      status: error ? 'error' : 'ok',
      error_message: error?.message || null,
      request_data: {
        booking_id: bookingId,
        fields: Object.keys(d)
      }
    });
  } catch  {}
}
Deno.serve(async (req)=>{
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: CORS
    });
  }
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  try {
    const body = await req.text();
    const signature = req.headers.get('stripe-signature');
    let event;
    // Verify Stripe signature — REQUIRED in production
    if (!STRIPE_WEBHOOK_SECRET) {
      console.error('STRIPE_WEBHOOK_SECRET not configured');
      return new Response(JSON.stringify({
        error: 'Webhook secret not configured'
      }), {
        status: 500,
        headers: {
          ...CORS,
          'Content-Type': 'application/json'
        }
      });
    }
    if (!signature) {
      return new Response(JSON.stringify({
        error: 'Missing stripe-signature header'
      }), {
        status: 400,
        headers: {
          ...CORS,
          'Content-Type': 'application/json'
        }
      });
    }
    try {
      event = await stripe.webhooks.constructEventAsync(body, signature, STRIPE_WEBHOOK_SECRET);
    } catch (err) {
      console.error('Webhook signature verification failed:', err.message);
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver',
          action: 'signature_verification_failed',
          component: 'stripe',
          status: 'error',
          error_message: err.message
        });
      } catch (e) {}
      return new Response(JSON.stringify({
        error: 'Invalid signature'
      }), {
        status: 400,
        headers: {
          ...CORS,
          'Content-Type': 'application/json'
        }
      });
    }
    // Log incoming webhook
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'webhook_received',
        component: 'stripe',
        status: 'ok',
        request_data: {
          event_type: event.type,
          event_id: event.id
        }
      });
    } catch (e) {}
    // Handle events
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      const metadata = session.metadata || {};
      let paymentType = metadata.type || 'booking';
      let resolvedOrderId = metadata.order_id || null;
      let resolvedBookingId = metadata.booking_id || null;
      const stripePaymentIntentId = typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id || null;
      // Fallback: pokud Stripe metadata chybí (Apple Pay, Link, edge cases),
      // použij client_reference_id (process-payment ho nastavuje na booking_id/order_id).
      const clientRef = session.client_reference_id;
      if (!resolvedOrderId && !resolvedBookingId && clientRef) {
        try {
          const { data: shopMatch } = await supabase.from('shop_orders').select('id').eq('id', clientRef).maybeSingle();
          if (shopMatch?.id) {
            resolvedOrderId = shopMatch.id;
            paymentType = 'shop';
          } else {
            const { data: bkMatch } = await supabase.from('bookings').select('id').eq('id', clientRef).maybeSingle();
            if (bkMatch?.id) {
              resolvedBookingId = bkMatch.id;
              paymentType = 'booking';
            }
          }
        } catch (e) {
          console.warn('[webhook] client_reference_id lookup failed:', e);
        }
      }
      // Druhý fallback: dohledej podle stripe_session_id (process-payment ho ukládá do shop_orders/bookings)
      if (!resolvedOrderId && !resolvedBookingId) {
        try {
          const { data: shopMatch } = await supabase.from('shop_orders').select('id').eq('stripe_session_id', session.id).maybeSingle();
          if (shopMatch?.id) {
            resolvedOrderId = shopMatch.id;
            paymentType = 'shop';
          } else {
            const { data: bkMatch } = await supabase.from('bookings').select('id').eq('stripe_session_id', session.id).maybeSingle();
            if (bkMatch?.id) {
              resolvedBookingId = bkMatch.id;
              paymentType = 'booking';
            }
          }
        } catch (e) {
          console.warn('[webhook] session_id lookup failed:', e);
        }
      }
      if (session.mode === 'setup' && metadata.action === 'add_card') {
        await syncCardFromSetupSession(supabase, session);
      } else if (session.mode === 'setup' && metadata.action === 'verify_free_booking' && resolvedBookingId) {
        // 0 Kč rezervace přes Stripe Checkout setup — karta ověřena, žádný charge.
        // Spustíme stejný flow jako u placené rezervace: confirm_payment + booking_reserved mail
        // + door codes (trigger) + KF generace. Bez tohoto by zákazník nedostal mail ani doklady.
        try {
          await confirmBookingPayment(supabase, resolvedBookingId, session.id, stripePaymentIntentId);
          try {
            await supabase.from('debug_log').insert({
              source: 'webhook-receiver',
              action: 'free_verify_confirmed',
              component: 'stripe',
              status: 'ok',
              request_data: {
                session_id: session.id,
                booking_id: resolvedBookingId
              }
            });
          } catch  {}
        } catch (e) {
          console.error('[webhook] free verify exception:', e.message);
          try {
            await supabase.from('debug_log').insert({
              source: 'webhook-receiver',
              action: 'free_verify_confirm_failed',
              component: 'stripe',
              status: 'error',
              error_message: e.message,
              request_data: {
                session_id: session.id,
                booking_id: resolvedBookingId
              }
            });
          } catch  {}
        }
        if (session.customer) {
          try {
            await syncCardsForCustomer(supabase, session.customer);
          } catch (e) {
            console.warn('[webhook] card sync failed:', e.message);
          }
        }
      } else if ((paymentType === 'booking' || paymentType === 'extension') && resolvedBookingId) {
        // extension = doplatek za úpravu → potvrdit platbu, ale bez booking_reserved
        // mailu (mail úpravy pošle trigger po aplikaci změny níže)
        await confirmBookingPayment(supabase, resolvedBookingId, session.id, stripePaymentIntentId, paymentType === 'extension');
        // Doplatková změna rezervace — aplikuj server-side (spustí web_booking_modified)
        if (paymentType === 'extension') {
          try {
            await applyExtensionChange(supabase, resolvedBookingId, metadata.chg);
          } catch (e) {
            console.warn('[webhook] extension change apply failed:', e.message);
          }
        }
        // Bundled e-shop upsell paid in the same session — confirm shop side too (separate invoice + email)
        if (metadata.shop_order_id) {
          try {
            await confirmShopPayment(supabase, metadata.shop_order_id, session.id, stripePaymentIntentId);
          } catch (e) {
            console.warn('[webhook] bundled shop confirm failed:', e);
          }
        }
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer);
        }
      } else if (paymentType === 'shop' && resolvedOrderId) {
        await confirmShopPayment(supabase, resolvedOrderId, session.id, stripePaymentIntentId);
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer);
        }
      } else if (paymentType === 'sos' && resolvedBookingId) {
        await confirmSosPayment(supabase, resolvedBookingId, metadata.incident_id, session.id, stripePaymentIntentId);
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer);
        }
      } else {
        try {
          await supabase.from('debug_log').insert({
            source: 'webhook-receiver',
            action: 'unmatched_session_completed',
            component: 'stripe',
            status: 'warning',
            request_data: {
              session_id: session.id,
              metadata,
              client_reference_id: clientRef
            }
          });
        } catch  {}
      }
    } else if (event.type === 'payment_intent.succeeded') {
      const paymentIntent = event.data.object;
      const metadata = paymentIntent.metadata || {};
      let paymentType = metadata.type || 'booking';
      let resolvedOrderId = metadata.order_id || null;
      let resolvedBookingId = metadata.booking_id || null;
      // Fallback: pokud Stripe Checkout Session metadata neproteklo do PaymentIntent,
      // dohledej order/booking podle stripe_payment_intent_id v DB.
      if (!resolvedOrderId && !resolvedBookingId) {
        try {
          const { data: shopMatch } = await supabase.from('shop_orders').select('id').eq('stripe_payment_intent_id', paymentIntent.id).maybeSingle();
          if (shopMatch?.id) {
            resolvedOrderId = shopMatch.id;
            paymentType = 'shop';
          } else {
            const { data: bkMatch } = await supabase.from('bookings').select('id').eq('stripe_payment_intent_id', paymentIntent.id).maybeSingle();
            if (bkMatch?.id) {
              resolvedBookingId = bkMatch.id;
              paymentType = 'booking';
            }
          }
        } catch (e) {
          console.warn('[webhook] PI fallback lookup failed:', e);
        }
      }
      if ((paymentType === 'booking' || paymentType === 'extension') && resolvedBookingId) {
        await confirmBookingPayment(supabase, resolvedBookingId, paymentIntent.id, null, paymentType === 'extension');
        if (paymentType === 'extension') {
          try {
            await applyExtensionChange(supabase, resolvedBookingId, metadata.chg);
          } catch (e) {
            console.warn('[webhook] extension change apply (intent) failed:', e.message);
          }
        }
        if (metadata.shop_order_id) {
          try {
            await confirmShopPayment(supabase, metadata.shop_order_id, paymentIntent.id);
          } catch (e) {
            console.warn('[webhook] bundled shop confirm (intent) failed:', e);
          }
        }
      } else if (paymentType === 'shop' && resolvedOrderId) {
        await confirmShopPayment(supabase, resolvedOrderId, paymentIntent.id);
      } else if (paymentType === 'sos' && resolvedBookingId) {
        await confirmSosPayment(supabase, resolvedBookingId, metadata.incident_id, paymentIntent.id);
      }
      // Capture card brand + last4 from the underlying Charge so Velín booking detail
      // can show "Visa **** 4242" without an on-demand Stripe call.
      if (resolvedBookingId) {
        try {
          const chargeId = typeof paymentIntent.latest_charge === 'string' ? paymentIntent.latest_charge : paymentIntent.latest_charge?.id || null;
          if (chargeId) {
            const ch = await stripe.charges.retrieve(chargeId);
            const brand = ch?.payment_method_details?.card?.brand || null;
            const last4 = ch?.payment_method_details?.card?.last4 || null;
            if (brand || last4) {
              await supabase.from('bookings').update({
                card_brand: brand,
                card_last4: last4
              }).eq('id', resolvedBookingId);
            }
          }
        } catch (e) {
          console.warn('[webhook] card brand/last4 capture failed:', e.message);
        }
      }
      // Auto-save card: attach PM to customer and sync to Supabase
      if (paymentIntent.customer && paymentIntent.payment_method) {
        const custId = typeof paymentIntent.customer === 'string' ? paymentIntent.customer : paymentIntent.customer?.id;
        const pmId = typeof paymentIntent.payment_method === 'string' ? paymentIntent.payment_method : paymentIntent.payment_method?.id;
        if (custId && pmId) {
          try {
            await stripe.paymentMethods.attach(pmId, {
              customer: custId
            });
          } catch (e) {
          // Already attached — ignore
          }
          await syncCardsForCustomer(supabase, custId);
        }
      }
      // Enrich financial event with booking/order details
      const feMetadata = {
        stripe_payment_intent_id: paymentIntent.id,
        stripe_customer: paymentIntent.customer,
        payment_type: paymentType,
        payment_method: 'card',
        received_date: new Date(paymentIntent.created * 1000).toISOString().slice(0, 10)
      };
      // Auto-fill supplier (= our company) and document details
      feMetadata.supplier_name = 'Bc. Petra Semorádová';
      feMetadata.supplier_ico = '21874263';
      feMetadata.supplier_bank_account = '670100-2225851630/6210';
      if ((paymentType === 'booking' || paymentType === 'extension') && metadata.booking_id) {
        try {
          const { data: bk } = await supabase.from('bookings').select('id, start_date, end_date, total_price, user_id, motorcycles!moto_id(model, spz), profiles:user_id(full_name, email)').eq('id', metadata.booking_id).single();
          if (bk) {
            const { data: inv } = await supabase.from('invoices').select('number, variable_symbol').eq('booking_id', metadata.booking_id).in('type', [
              'payment_receipt',
              'advance',
              'proforma'
            ]).order('issue_date', {
              ascending: false
            }).limit(1);
            feMetadata.invoice_number = inv?.[0]?.number || `RES-${metadata.booking_id.slice(-8).toUpperCase()}`;
            feMetadata.variable_symbol = inv?.[0]?.variable_symbol || inv?.[0]?.number || '';
            feMetadata.customer_name = bk.profiles?.full_name || '';
            feMetadata.customer_email = bk.profiles?.email || '';
            feMetadata.booking_model = bk.motorcycles?.model || '';
            feMetadata.booking_spz = bk.motorcycles?.spz || '';
            feMetadata.booking_dates = `${bk.start_date} – ${bk.end_date}`;
            feMetadata.due_date = new Date(paymentIntent.created * 1000).toISOString().slice(0, 10);
          }
        } catch (e) {}
      } else if (paymentType === 'shop' && metadata.order_id) {
        try {
          const { data: ord } = await supabase.from('shop_orders').select('order_number, total_amount, profiles:customer_id(full_name, email)').eq('id', metadata.order_id).single();
          if (ord) {
            feMetadata.invoice_number = ord.order_number || `OBJ-${metadata.order_id.slice(-8).toUpperCase()}`;
            feMetadata.variable_symbol = ord.order_number || '';
            feMetadata.customer_name = ord.profiles?.full_name || '';
            feMetadata.due_date = new Date(paymentIntent.created * 1000).toISOString().slice(0, 10);
          }
        } catch (e) {}
      }
      await ingestFinancialEvent(supabase, {
        event_type: 'revenue',
        source: 'stripe',
        amount_czk: paymentIntent.amount / 100,
        vat_rate: 0,
        duzp: new Date(paymentIntent.created * 1000).toISOString().slice(0, 10),
        linked_entity_type: paymentType || 'booking',
        linked_entity_id: metadata.booking_id || metadata.order_id || null,
        confidence_score: 1.0,
        status: 'validated',
        metadata: feMetadata
      });
    } else if (event.type === 'charge.refunded') {
      const charge = event.data.object;
      // Seznam refundů na charge — v event payloadu nemusí být expandovaný,
      // pak si ho dotáhneme přes API (nejnovější refund je první).
      let refundsOnCharge = charge.refunds?.data || [];
      if (!refundsOnCharge.length) {
        try {
          refundsOnCharge = (await stripe.refunds.list({
            charge: charge.id,
            limit: 10
          })).data;
        } catch (e) {
          console.warn('[webhook] refunds.list failed:', e.message);
        }
      }
      const latestRefund = refundsOnCharge[0] || null;
      const refundReason = latestRefund?.reason || null;
      // Enrich refund with booking details
      const refundFeMeta = {
        refund_reason: refundReason,
        original_payment_intent: charge.payment_intent,
        stripe_charge_id: charge.id,
        stripe_refund_id: latestRefund?.id || null,
        payment_method: 'card',
        supplier_name: 'Bc. Petra Semorádová',
        supplier_ico: '21874263',
        received_date: new Date().toISOString().slice(0, 10)
      };
      let linkedId = null;
      let linkedType = null;
      // Try to find linked booking via payment_intent
      let linkedBooking = null;
      if (charge.payment_intent) {
        try {
          const piId = typeof charge.payment_intent === 'string' ? charge.payment_intent : charge.payment_intent?.id;
          if (piId) {
            const { data: bk } = await supabase.from('bookings').select('id, status, payment_status, total_price, start_date, end_date, booking_source, cancelled_by_source, cancellation_reason, stripe_refund_id, motorcycles!moto_id(model), profiles:user_id(full_name, email)').eq('stripe_payment_intent_id', piId).single();
            if (bk) {
              linkedBooking = bk;
              linkedId = bk.id;
              linkedType = 'booking';
              refundFeMeta.customer_name = bk.profiles?.full_name || '';
              refundFeMeta.booking_model = bk.motorcycles?.model || '';
              refundFeMeta.invoice_number = `Refund RES-${bk.id.slice(-8).toUpperCase()}`;
            }
          }
        } catch (e) {}
      }
      // Účetní event = částka TOHOTO refundu, ne kumulativní amount_refunded.
      // charge.refunded chodí za KAŽDÝ refund na charge a amount_refunded je
      // součet — druhý částečný refund by se jinak zaúčtoval i s prvním znovu.
      await ingestFinancialEvent(supabase, {
        event_type: 'revenue',
        source: 'stripe',
        amount_czk: -((latestRefund?.amount ?? charge.amount_refunded) / 100),
        vat_rate: 0,
        duzp: new Date().toISOString().slice(0, 10),
        linked_entity_type: linkedType,
        linked_entity_id: linkedId,
        confidence_score: 1.0,
        status: 'validated',
        metadata: refundFeMeta
      });
      // Refund handling — NEJDŘÍV rozlišit PŮVOD refundu (incident #DDC5A69D
      // 2026-08-12: částečná vratka výměny motorky z Velína → webhook rezervaci
      // chybně „zacanceloval jako Stripe portál storno", doprovodný cancel flow
      // vrátil i zbytek platby, vystavil druhý 100% dobropis a poslal 4 storno maily):
      //
      // A) INTERNÍ refund (vytvořil ho náš process-refund — pozná se podle
      //    metadata.mg_source, bookings.stripe_refund_id nebo existujícího
      //    dobropisu s tímto refund id): dobropis, mail i stavy řeší flow, které
      //    refund vyvolalo (zkrácení/výměna/úprava/storno). Webhook NIKDY neruší
      //    rezervaci; jen dosynchronizuje payment_status a bezpečně (bez amount →
      //    process-refund už žádný Stripe refund nevytvoří) dohraje credit_note,
      //    pokud process-refund spadl po refunds.create(). Storno mail jen pokud
      //    už rezervace cancelled JE (safety-net původního scénáře 2).
      // B) EXTERNÍ refund (Stripe portál) na PLNOU částku: skutečné storno zvenku
      //    → zacancelovat + dohrát dobropis + mail (původní scénář 1).
      // C) EXTERNÍ ČÁSTEČNÝ refund: nikdy nerušit rezervaci — jen payment_status
      //    + debug_log warning k ručnímu prověření (dobropis vystaví admin).
      if (linkedBooking) {
        try {
          const refundCzk = charge.amount_refunded / 100;
          const total = Number(linkedBooking.total_price || 0);
          const refundPct = total > 0 ? Math.round(refundCzk / total * 100) : 0;
          const fullyRefunded = charge.amount_refunded >= (charge.amount_captured || charge.amount);
          const alreadyCancelled = linkedBooking.status === 'cancelled';
          // Interní = refund vytvořený naším process-refund
          const refundIds = refundsOnCharge.map((r)=>r.id).filter(Boolean);
          let internalRefund = refundsOnCharge.some((r)=>!!r.metadata?.mg_source);
          if (!internalRefund && linkedBooking.stripe_refund_id && refundIds.includes(linkedBooking.stripe_refund_id)) {
            internalRefund = true;
          }
          if (!internalRefund && refundIds.length) {
            try {
              const { data: cnMatch } = await supabase.from('invoices').select('id').in('stripe_refund_id', refundIds).limit(1);
              if (cnMatch?.length) internalRefund = true;
            } catch  {}
          }
          const shouldCancel = !internalRefund && fullyRefunded && !alreadyCancelled;
          // 1) UPDATE booking: payment_status dle reality na Stripe (plně/částečně
          //    vráceno) + stripe_refund_id; cancellation pole JEN u externího
          //    plného refundu (skutečné storno přes Stripe portál).
          const bkPatch = {
            payment_status: fullyRefunded ? 'refunded' : 'partial_refund'
          };
          if (latestRefund?.id) bkPatch.stripe_refund_id = latestRefund.id;
          if (shouldCancel) {
            bkPatch.status = 'cancelled';
            bkPatch.cancelled_at = new Date().toISOString();
            bkPatch.cancelled_by_source = 'stripe_portal';
            bkPatch.cancellation_reason = refundReason ? `Refund přes Stripe portál (${refundReason})` : 'Refund přes Stripe portál';
          }
          await supabase.from('bookings').update(bkPatch).eq('id', linkedBooking.id);
          await supabase.from('debug_log').insert({
            source: 'webhook-receiver',
            action: internalRefund ? 'charge_refunded_internal' : shouldCancel ? 'charge_refunded_portal_cancel' : 'charge_refunded_external_partial',
            component: 'stripe',
            status: !internalRefund && !fullyRefunded ? 'warning' : 'info',
            request_data: {
              booking_id: linkedBooking.id,
              refund_id: latestRefund?.id || null,
              internal: internalRefund,
              fully_refunded: fullyRefunded,
              cancelled_now: shouldCancel,
              refund_pct: refundPct
            }
          }).then(()=>{}, ()=>{});
          // 2) Dohrát credit_note (safety-net pro spadlý process-refund) — BEZ
          //    amount: payment_status je teď 'partial_refund'/'refunded', takže
          //    process-refund jde do idempotentní already-refunded větve (jen
          //    ensureCreditNotePdf / createCreditNoteForExistingRefund, žádný
          //    nový Stripe refund). U externího ČÁSTEČNÉHO refundu nevoláme —
          //    dobropis k ručnímu vystavení (viz debug_log warning výše).
          if (internalRefund || fullyRefunded) {
            await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/process-refund`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`
              },
              body: JSON.stringify({
                booking_id: linkedBooking.id
              })
            }).catch((e)=>console.warn('Webhook process-refund recovery failed:', e?.message));
          }
          // 3) Storno mail s dobropisem — JEN když je rezervace zrušená (teď
          //    portálem, nebo už dřív storno flow, jehož mail mohl spadnout).
          //    send-cancellation-email má idempotency (sent_emails 30 min).
          //    Interní refund na ŽIVÉ rezervaci mail NEposílá — potvrzení úpravy
          //    řeší trg_booking_modified_email / příslušné flow.
          if ((shouldCancel || alreadyCancelled) && linkedBooking.profiles?.email) {
            await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-cancellation-email`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`
              },
              body: JSON.stringify({
                booking_id: linkedBooking.id,
                customer_email: linkedBooking.profiles.email,
                customer_name: linkedBooking.profiles.full_name || '',
                motorcycle: linkedBooking.motorcycles?.model || '',
                start_date: linkedBooking.start_date,
                end_date: linkedBooking.end_date,
                cancellation_reason: shouldCancel ? refundReason ? `Refund přes Stripe portál (${refundReason})` : 'Refund přes Stripe portál' : linkedBooking.cancellation_reason || 'Storno rezervace',
                cancelled_by_source: shouldCancel ? 'stripe_portal' : linkedBooking.cancelled_by_source || 'customer',
                refund_amount: refundCzk,
                refund_percent: refundPct,
                source: linkedBooking.booking_source || 'app'
              })
            }).catch((e)=>console.warn('Webhook safety-net mail failed:', e?.message));
          }
        } catch (e) {
          console.warn('charge.refunded safety-net failed:', e.message);
        }
      }
    } else if (event.type === 'payout.paid') {
      const payout = event.data.object;
      await ingestFinancialEvent(supabase, {
        event_type: 'revenue',
        source: 'stripe',
        amount_czk: payout.amount / 100,
        vat_rate: 0,
        duzp: new Date(payout.arrival_date * 1000).toISOString().slice(0, 10),
        linked_entity_type: null,
        linked_entity_id: null,
        confidence_score: 1.0,
        status: 'validated',
        metadata: {
          stripe_payout_id: payout.id,
          arrival_date: payout.arrival_date
        }
      });
    }
    return new Response(JSON.stringify({
      received: true
    }), {
      status: 200,
      headers: {
        ...CORS,
        'Content-Type': 'application/json'
      }
    });
  } catch (err) {
    console.error('Webhook error:', err);
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'webhook_error',
        component: 'stripe',
        status: 'error',
        error_message: err.message
      });
    } catch (e) {}
    return new Response(JSON.stringify({
      error: 'Webhook processing failed'
    }), {
      status: 500,
      headers: {
        ...CORS,
        'Content-Type': 'application/json'
      }
    });
  }
});
