// ===== REZERVACE =====
async function apiFetchMyBookings(filter){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var uid = await _getUserId();
    if(!uid) return [];
    var q = window.supabase.from('bookings')
      .select('*, motorcycles(model, image_url, images, category, branch_id, branches(name, address, city, is_open))')
      .eq('user_id', uid)
      .order('start_date', {ascending: false});
    if(filter === 'pending'){
      q = q.in('status', ['pending','active']).gte('start_date', new Date().toISOString());
    }
    var r = await q;
    if(!r.data) return [];
    // Doplň moto_name a moto_image pro UI
    return r.data.map(function(b){
      var m = b.motorcycles;
      b.moto_name = m ? m.model : 'Motorka';
      b.moto_image = m ? (m.image_url || (m.images && m.images[0]) || '') : '';
      return b;
    });
  } catch(e){ console.error('[API] apiFetchMyBookings:', e); return []; }
}

async function apiCreateBooking(data){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline', booking:null};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen', booking:null};
    // Block booking if motorcycle's branch is closed
    if(data.motorcycle_id){
      var br = await window.supabase.from('motorcycles').select('branch_id, branches(is_open)').eq('id', data.motorcycle_id).single();
      if(br.data && br.data.branches && br.data.branches.is_open === false){
        return {error:'Pobočka je momentálně zavřená. Rezervaci nelze vytvořit.', booking:null};
      }
    }
    // Final overlap guard — block creation if user has overlapping booking
    if(data.start_date && data.end_date){
      var oc = await apiCheckBookingOverlap(data.start_date, data.end_date);
      if(oc.overlap){
        var cf = oc.conflicting;
        return {error:'Již máte rezervaci v tomto termínu: '+(cf.moto_name||'motorka')+' ('+cf.start_date?.slice(0,10)+' – '+cf.end_date?.slice(0,10)+')', booking:null};
      }
    }
    data.user_id = uid;
    data.status = 'pending';
    data.payment_status = 'unpaid';
    var r = await window.supabase.from('bookings').insert(data).select().single();
    if(r.error){
      var msg = r.error.message || '';
      // Translate DB trigger errors to user-friendly Czech
      if(msg.indexOf('Booking overlap') !== -1){
        return {error:'Tuto motorku právě rezervoval jiný zákazník ve stejném termínu. Zvolte prosím jiný termín nebo jinou motorku.', booking:null};
      }
      if(msg.indexOf('overlapping booking') !== -1){
        return {error:'V tomto termínu již máte jinou aktivní rezervaci. Upravte stávající rezervaci nebo zvolte jiný termín.', booking:null};
      }
      return {error: msg, booking:null};
    }
    return {error:null, booking: r.data};
  } catch(e){ return {error:'Chyba při vytváření rezervace', booking:null}; }
}

async function apiCalcBookingPrice(motoId, startISO, endISO){
  _ensureSupabase();
  if(!window.supabase) return 0;
  try {
    var r = await window.supabase.rpc('calc_booking_price_v2', {
      p_moto_id: motoId,
      p_start: startISO.split('T')[0],
      p_end: endISO.split('T')[0],
      p_promo: null
    });
    if(r.data && r.data.total_price) return Number(r.data.total_price);
    return 0;
  } catch(e){ console.error('[API] apiCalcBookingPrice:', e); return 0; }
}

async function apiProcessPayment(bookingId, amount, method, opts){
  _ensureSupabase();
  if(!window.supabase) return {success:false};
  var cfg = window.MOTOGO_CONFIG || {};
  var baseUrl = cfg.SUPABASE_URL;
  var anonKey = cfg.SUPABASE_ANON_KEY;
  var payMethod = method || 'card';
  var payType = (opts && opts.type) || 'booking';
  var orderId = (opts && opts.order_id) || null;
  var incidentId = (opts && opts.incident_id) || null;

  // Získej auth token — vždy čerstvý
  var token = null;
  try {
    var sess = await window.supabase.auth.getSession();
    if(sess.data && sess.data.session) token = sess.data.session.access_token;
  } catch(e){}
  if(!token){
    // Token chybí — refresh + setSession pro propagaci
    try {
      var ref = await window.supabase.auth.refreshSession();
      if(ref.data && ref.data.session){
        await window.supabase.auth.setSession({
          access_token: ref.data.session.access_token,
          refresh_token: ref.data.session.refresh_token
        });
        token = ref.data.session.access_token;
      }
    } catch(e){}
  }
  if(!token){
    return {success:false, error: 'Nejste přihlášeni. Přihlaste se prosím znovu.'};
  }

  // Stripe — inline PaymentIntent (default) or fallback Checkout Session
  if(!baseUrl){
    return {success:false, error: 'Chyba konfigurace. Kontaktujte podporu: info@motogo24.cz'};
  }

  var payMode = (opts && opts.mode) || 'intent';

  try {
    var payload = {
      booking_id: bookingId,
      amount: amount,
      method: payMethod,
      type: payType,
      mode: payMode
    };
    if(orderId) payload.order_id = orderId;
    if(incidentId) payload.incident_id = incidentId;
    var resp = await fetch(baseUrl + '/functions/v1/process-payment', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + token,
        'apikey': anonKey || ''
      },
      body: JSON.stringify(payload)
    });
    if(resp.ok){
      var result = await resp.json();
      // 100% sleva — potvrzeno na serveru bez Stripe
      if(result.success && result.free){
        return {success:true, free:true, booking_id: result.booking_id};
      }
      if(result.success && result.client_secret){
        return {success:true, client_secret: result.client_secret, payment_intent_id: result.payment_intent_id};
      }
      if(result.success && result.checkout_url){
        return {success:true, checkout_url: result.checkout_url};
      }
      if(result.error) return {success:false, error: result.error};
    } else {
      // Read error body for diagnostics
      var errBody = null;
      try { errBody = await resp.json(); } catch(e){}
      var errMsg = (errBody && errBody.error) ? errBody.error : 'Platba selhala (HTTP ' + resp.status + ')';
      console.error('[API] Stripe HTTP ' + resp.status, errBody);
      if(resp.status === 409) return {success:false, error: errMsg};
      return {success:false, error: errMsg};
    }
  } catch(e){
    console.warn('[API] Stripe unreachable:', e.message);
  }

  console.error('[API] Payment failed (Stripe)');
  return {success:false, error: 'Platba se nepodařila. Zkuste to znovu nebo kontaktujte podporu: info@motogo24.cz'};
}

async function apiCancelBooking(bookingId, reason){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    // Zkus RPC s cancellation tracking
    var rpc = await window.supabase.rpc('cancel_booking_tracked', {
      p_booking_id: bookingId,
      p_reason: reason || null
    });
    if(rpc.data && rpc.data.success){
      // Stripe refund — pokud je nárok na vrácení peněz
      if(rpc.data.refund_amount > 0){
        apiProcessRefund(bookingId, null, rpc.data.refund_amount, 'cancellation').catch(function(e){
          console.warn('[API] Stripe refund failed (will be processed manually):', e);
        });
      }
      return {error:null, refund_percent: rpc.data.refund_percent, refund_amount: rpc.data.refund_amount};
    }
    if(rpc.data && rpc.data.error){
      return {error: rpc.data.error};
    }

    // Fallback: přímý update
    var br = await window.supabase.from('bookings').select('*').eq('id', bookingId).single();
    if(!br.data) return {error:'Rezervace nenalezena'};
    var b = br.data;
    var refundPct = _getStornoPercent(b.start_date);
    var refundAmt = Math.round((b.total_price || 0) * refundPct / 100);
    var r = await window.supabase.from('bookings').update({status:'cancelled'}).eq('id', bookingId);
    if(r.error) return {error: r.error.message};
    // Stripe refund
    if(refundAmt > 0){
      apiProcessRefund(bookingId, null, refundAmt, 'cancellation').catch(function(e){
        console.warn('[API] Stripe refund failed (will be processed manually):', e);
      });
    }
    return {error:null, refund_percent: refundPct, refund_amount: refundAmt};
  } catch(e){ return {error:'Chyba při rušení rezervace'}; }
}

// Stripe refund — volá Edge Function process-refund
async function apiProcessRefund(bookingId, orderId, amount, reason){
  _ensureSupabase();
  var cfg = window.MOTOGO_CONFIG || {};
  var baseUrl = cfg.SUPABASE_URL;
  var anonKey = cfg.SUPABASE_ANON_KEY;
  if(!baseUrl) return {success:false, error:'No config'};

  var token = anonKey;
  try {
    var sess = await window.supabase.auth.getSession();
    if(sess.data && sess.data.session) token = sess.data.session.access_token;
  } catch(e){}

  try {
    var payload = { reason: reason || 'requested_by_customer' };
    if(bookingId) payload.booking_id = bookingId;
    if(orderId) payload.order_id = orderId;
    if(amount > 0) payload.amount = amount;

    var resp = await fetch(baseUrl + '/functions/v1/process-refund', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + token,
        'apikey': anonKey || ''
      },
      body: JSON.stringify(payload)
    });
    var result = await resp.json();
    if(result.success){
      console.log('[API] Stripe refund OK:', result.refund_id, result.amount_refunded + ' CZK');
    } else {
      console.warn('[API] Stripe refund error:', result.error);
    }
    return result;
  } catch(e){
    console.error('[API] apiProcessRefund error:', e);
    return {success:false, error: e.message};
  }
}
