/* === API-BOOKINGS.JS — Booking CRUD, payment, status, availability === */

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
    if(r.error) return {error: r.error.message, booking:null};
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

  // Získej auth token
  var token = anonKey;
  try {
    var sess = await window.supabase.auth.getSession();
    if(sess.data && sess.data.session) token = sess.data.session.access_token;
  } catch(e){}

  // 1) Zkus Edge Function (Stripe checkout pro karty, admin client pro cash)
  if(baseUrl){
    try {
      var payload = {
        booking_id: bookingId,
        amount: amount,
        method: payMethod,
        type: payType
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
        if(result.success){
          if(result.checkout_url) return {success:true, checkout_url: result.checkout_url};
          return {success:true, transaction_id: result.transaction_id};
        }
        console.warn('[API] Edge fn returned error:', result.error);
      } else {
        console.warn('[API] Edge fn HTTP '+resp.status+' – using RPC fallback');
      }
    } catch(e){
      console.warn('[API] Edge fn unreachable:', e.message, '– using RPC fallback');
    }
  }

  // 2) Fallback: RPC funkce confirm_payment (SECURITY DEFINER, obchází RLS)
  try {
    var rpcResult = await window.supabase.rpc('confirm_payment', {
      p_booking_id: bookingId,
      p_method: payMethod
    });
    var rpcData = rpcResult.data;
    if(typeof rpcData === 'string'){
      try { rpcData = JSON.parse(rpcData); } catch(pe){}
    }
    if(rpcData && (rpcData.success === true || rpcData === true)){
      return {success:true, transaction_id: rpcData.transaction_id || null};
    }
    if(!rpcResult.error && rpcData !== null && rpcData !== undefined){
      return {success:true};
    }
    if(rpcResult.error){
      console.warn('[API] RPC confirm_payment error:', rpcResult.error.message);
    }
  } catch(e){
    console.warn('[API] RPC fallback failed:', e.message);
  }

  // Obě vrstvy selhaly — jasná chyba uživateli
  console.error('[API] Payment failed (Edge Function + RPC)');
  return {success:false, error: 'Platba se nepodařila. Kontaktujte podporu: info@motogo24.cz'};
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
    return {error:null, refund_percent: refundPct, refund_amount: refundAmt};
  } catch(e){ return {error:'Chyba při rušení rezervace'}; }
}

// Generate cancellation receipt (storno doklad) — called after booking cancellation
async function apiGenerateCancellationReceipt(bookingId, refundPercent, refundAmount){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    var br = await window.supabase.from('bookings')
      .select('*, motorcycles('+_MOTO_PRICE_COLS+')')
      .eq('id', bookingId).single();
    if(br.error || !br.data) return {error:'Booking not found'};
    var b = br.data, m = br.data.motorcycles || {};
    var yr = new Date().getFullYear();
    var lr = await window.supabase.from('invoices').select('number')
      .like('number', 'DP-' + yr + '-%').order('number', {ascending:false}).limit(1);
    var seq = 1;
    if(lr.data && lr.data.length > 0){
      var mt = lr.data[0].number.match(/-(\d+)$/);
      if(mt) seq = parseInt(mt[1], 10) + 1;
    }
    var dpNum = 'DP-' + yr + '-' + String(seq).padStart(4, '0');
    // Find original ZF for reference
    var origZf = await window.supabase.from('invoices').select('number')
      .eq('booking_id', bookingId).eq('type','advance').eq('source','booking')
      .order('created_at',{ascending:true}).limit(1);
    var origRef = (origZf.data && origZf.data.length > 0) ? ' (storno k '+origZf.data[0].number+')' : '';
    // Build items: original booking (negative) + storno fee if applicable
    var items = [];
    items.push({description:'── Storno rezervace'+origRef+' ──', qty:1, unit_price:0});
    var bookingItems = _buildDailyItems(m, b.start_date, b.end_date);
    bookingItems.forEach(function(it){ items.push({description:it.description, qty:1, unit_price:-it.unit_price}); });
    if(b.extras_price > 0) items.push({description:'Příslušenství / doplňky', qty:1, unit_price:-b.extras_price});
    if(b.delivery_fee > 0) items.push({description:'Doručení', qty:1, unit_price:-b.delivery_fee});
    if(b.discount_amount > 0) items.push({description:'Sleva'+(b.discount_code?' ('+b.discount_code+')':''), qty:1, unit_price:b.discount_amount});
    var rawRefund = _calcItemsTotal(items);
    if(refundPercent < 100 && rawRefund < 0){
      var stornoFee = Math.round(Math.abs(rawRefund) * (100 - refundPercent) / 100);
      var stornoLabel = refundPercent === 0
        ? 'Storno poplatek (méně než 2 dny – bez vrácení)'
        : 'Storno poplatek (2–7 dní – vrácení 50 %)';
      items.push({description:stornoLabel, qty:1, unit_price:stornoFee});
    }
    var subtotal = _calcItemsTotal(items);
    var issueDate = new Date().toISOString().slice(0, 10);
    var inv = await window.supabase.from('invoices').insert({
      number: dpNum, type: 'payment_receipt', customer_id: uid, booking_id: bookingId,
      items: items, subtotal: subtotal, tax_amount: 0, total: subtotal,
      issue_date: issueDate, due_date: issueDate, status: 'paid',
      variable_symbol: dpNum, source: 'cancellation'
    }).select().single();
    if(inv.error) return {error: inv.error.message};
    try {
      await window.supabase.from('documents').insert({
        booking_id: bookingId, user_id: uid, type: 'payment_receipt',
        file_name: 'Storno doklad ' + dpNum + '.pdf',
        file_path: 'invoices/' + (inv.data ? inv.data.id : bookingId) + '.html'
      });
    } catch(de){}
    return {error: null, receipt_number: dpNum};
  } catch(e){ return {error: e.message}; }
}

async function apiRestoreBooking(bookingId){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    // Fetch the booking to get amount for payment
    var br = await window.supabase.from('bookings')
      .select('*, motorcycles(model, image_url)')
      .eq('id', bookingId).single();
    if(!br.data) return {error:'Rezervace nenalezena'};
    return {error:null, booking: br.data};
  } catch(e){ return {error:'Chyba při obnovení rezervace'}; }
}

async function apiConfirmRestoreBooking(bookingId){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var r = await window.supabase.from('bookings').update({
      status:'active',
      payment_status:'paid'
    }).eq('id', bookingId);
    if(r.error) return {error: r.error.message};
    return {error:null};
  } catch(e){ return {error:'Chyba při obnovení rezervace'}; }
}

async function apiExtendBooking(bookingId, newEndISO){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    // Fetch current state before RPC call
    var cur = await window.supabase.from('bookings').select('start_date, end_date, original_start_date, original_end_date, modification_history').eq('id', bookingId).single();
    var r = await window.supabase.rpc('extend_booking', {
      p_booking_id: bookingId,
      p_new_end_date: newEndISO
    });
    if(r.data && r.data.error) return {error: r.data.error};
    if(r.error) return {error: r.error.message};
    // Save original dates and modification_history
    if(cur.data){
      var _ld = function(d){ return d ? new Date(d).toLocaleDateString('sv-SE') : ''; };
      var changes = {};
      if(!cur.data.original_start_date){
        // Use YYYY-MM-DD in local timezone to avoid UTC truncation bug
        changes.original_start_date = _ld(cur.data.start_date);
        changes.original_end_date = _ld(cur.data.end_date);
      }
      var hist = Array.isArray(cur.data.modification_history) ? cur.data.modification_history.slice() : [];
      hist.push({at:new Date().toISOString(), from_start:_ld(cur.data.start_date), from_end:_ld(cur.data.end_date), to_start:_ld(cur.data.start_date), to_end:_ld(newEndISO), source:'customer'});
      changes.modification_history = hist;
      await window.supabase.from('bookings').update(changes).eq('id', bookingId);
    }
    return r.data || {error:null};
  } catch(e){ return {error:'Chyba při prodloužení'}; }
}

async function apiShortenBooking(bookingId, newEndISO, newStartISO){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var cur = await window.supabase.from('bookings').select('start_date, end_date, original_start_date, original_end_date, modification_history').eq('id', bookingId).single();
    if(!cur.data) return {error:'Rezervace nenalezena'};
    var changes = {};
    // Store original dates on first-ever modification (YYYY-MM-DD to avoid UTC truncation)
    var _ld = function(d){ return d ? new Date(d).toLocaleDateString('sv-SE') : ''; };
    if(!cur.data.original_start_date){
      changes.original_start_date = _ld(cur.data.start_date);
      changes.original_end_date = _ld(cur.data.end_date);
    }
    if(newEndISO) changes.end_date = newEndISO;
    if(newStartISO) changes.start_date = newStartISO;
    // Append to modification_history
    var hist = Array.isArray(cur.data.modification_history) ? cur.data.modification_history.slice() : [];
    var _ld = function(d){ return d ? new Date(d).toLocaleDateString('sv-SE') : ''; };
    hist.push({at:new Date().toISOString(), from_start:_ld(cur.data.start_date), from_end:_ld(cur.data.end_date), to_start:_ld(newStartISO||cur.data.start_date), to_end:_ld(newEndISO||cur.data.end_date), source:'customer'});
    changes.modification_history = hist;
    var r = await window.supabase.from('bookings').update(changes).eq('id', bookingId);
    if(r.error) return {error: r.error.message};
    return {error:null};
  } catch(e){ return {error:'Chyba při zkrácení'}; }
}

async function apiModifyBooking(bookingId, changes){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    // Record date/moto changes in modification_history
    if(changes.start_date || changes.end_date || changes.moto_id){
      var cur = await window.supabase.from('bookings').select('start_date, end_date, moto_id, original_start_date, original_end_date, modification_history, motorcycles(model)').eq('id', bookingId).single();
      if(cur.data){
        var _ld = function(d){ return d ? new Date(d).toLocaleDateString('sv-SE') : ''; };
        // Store original dates on first-ever modification (YYYY-MM-DD to avoid UTC truncation)
        if(!cur.data.original_start_date){
          changes.original_start_date = _ld(cur.data.start_date);
          changes.original_end_date = _ld(cur.data.end_date);
        }
        // Append to modification_history
        var hist = Array.isArray(cur.data.modification_history) ? cur.data.modification_history.slice() : [];
        var entry = {at:new Date().toISOString(), from_start:_ld(cur.data.start_date), from_end:_ld(cur.data.end_date), to_start:_ld(changes.start_date||cur.data.start_date), to_end:_ld(changes.end_date||cur.data.end_date), source:'customer'};
        // Track motorcycle change
        if(changes.moto_id && changes.moto_id !== cur.data.moto_id){
          entry.from_moto = (cur.data.motorcycles && cur.data.motorcycles.model) || cur.data.moto_id;
          // Fetch new moto name
          try {
            var _nm = await window.supabase.from('motorcycles').select('model').eq('id', changes.moto_id).single();
            entry.to_moto = (_nm.data && _nm.data.model) || changes.moto_id;
          } catch(e){ entry.to_moto = changes.moto_id; }
        }
        hist.push(entry);
        changes.modification_history = hist;
      }
    }
    var r = await window.supabase.from('bookings').update(changes).eq('id', bookingId);
    if(r.error) return {error: r.error.message};
    return {error:null};
  } catch(e){ return {error:'Chyba při úpravě rezervace'}; }
}

// ===== ACTIVE BOOKING CHECK – zákazník smí mít max 1 aktivní/rezervovanou rezervaci =====
async function apiCheckActiveBookingExists(excludeBookingId){
  _ensureSupabase();
  if(!window.supabase) return {exists:false};
  try {
    var uid = await _getUserId();
    if(!uid) return {exists:false};
    var q = window.supabase.from('bookings')
      .select('id, start_date, end_date, status')
      .eq('user_id', uid)
      .in('status', ['reserved','active']);
    if(excludeBookingId) q = q.neq('id', excludeBookingId);
    var r = await q;
    if(r.data && r.data.length > 0){
      return {exists:true, existing: r.data[0]};
    }
    return {exists:false};
  } catch(e){ console.error('[API] apiCheckActiveBookingExists:', e); return {exists:false}; }
}

// ===== OVERLAP CHECK – zákazník nesmí mít překrývající se rezervace =====
// Výjimka: dětské motorky (license_required = 'N') se nepočítají
async function apiCheckBookingOverlap(startISO, endISO, excludeBookingId){
  _ensureSupabase();
  if(!window.supabase) return {overlap:false};
  try {
    var uid = await _getUserId();
    if(!uid) return {overlap:false};
    var q = window.supabase.from('bookings')
      .select('id, start_date, end_date, status, moto_id, motorcycles(model, license_required)')
      .eq('user_id', uid)
      .in('status', ['pending','reserved','active'])
      .lte('start_date', endISO)
      .gte('end_date', startISO);
    if(excludeBookingId){
      q = q.neq('id', excludeBookingId);
    }
    var r = await q;
    if(r.error){ console.error('[API] apiCheckBookingOverlap query error:', r.error.message); }
    if(r.data && r.data.length > 0){
      // Filter out children's motorcycles (license_required = 'N')
      var nonKids = r.data.filter(function(b){
        return !(b.motorcycles && b.motorcycles.license_required === 'N');
      });
      if(nonKids.length > 0){
        var cf = nonKids[0];
        cf.moto_name = (cf.motorcycles && cf.motorcycles.model) || '';
        return {overlap:true, conflicting: cf};
      }
    }
    return {overlap:false};
  } catch(e){ console.error('[API] apiCheckBookingOverlap:', e); return {overlap:false}; }
}

// ===== MOTO AVAILABILITY CHECK – motorka nesmí být v daném termínu u jiného zákazníka =====
async function apiCheckMotoAvailability(motoId, startISO, endISO, excludeBookingId){
  _ensureSupabase();
  if(!window.supabase || !motoId) return {available:true};
  try {
    var q = window.supabase.from('bookings')
      .select('id, start_date, end_date, user_id, status')
      .eq('moto_id', motoId)
      .in('status', ['pending','reserved','active'])
      .lte('start_date', endISO)
      .gte('end_date', startISO);
    if(excludeBookingId) q = q.neq('id', excludeBookingId);
    var r = await q;
    if(r.data && r.data.length > 0){
      return {available:false, conflicting: r.data[0]};
    }
    return {available:true};
  } catch(e){ console.error('[API] apiCheckMotoAvailability:', e); return {available:true}; }
}
