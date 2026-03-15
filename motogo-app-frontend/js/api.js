// ===== API.JS – Supabase API vrstva pro MotoGo24 =====
// Všechny api* funkce volané z UI. Vyžaduje supabaseClient.js (window.supabase).

// ===== HEADER BANNER =====
function _applyBannerConfig(cfg){
  if(!cfg || !cfg.enabled || !cfg.text) {
    // Banner disabled — skrýt pokud byl viditelný
    var elOff = document.getElementById('header-banner');
    if(elOff) elOff.style.display = 'none';
    document.documentElement.classList.remove('has-banner');
    return;
  }
  var el = document.getElementById('header-banner');
  var track = document.getElementById('header-banner-track');
  if(!el || !track) return;
  var txt = cfg.text;
  track.innerHTML = '<span>' + txt + '</span><span>' + txt + '</span><span>' + txt + '</span><span>' + txt + '</span>';
  el.style.display = 'flex';
  if(cfg.bg) el.style.background = cfg.bg;
  if(cfg.color) track.style.color = cfg.color;
  document.documentElement.classList.add('has-banner');
}

async function apiFetchHeaderBanner(){
  if(!window.supabase) return;
  try {
    var r = await window.supabase.from('app_settings').select('value').eq('key','header_banner').maybeSingle();
    if(!r.data || !r.data.value) return;
    var cfg = typeof r.data.value === 'string' ? JSON.parse(r.data.value) : r.data.value;
    _applyBannerConfig(cfg);

    // Realtime subscription — banner se aktualizuje okamžitě po změně v admin dashboardu
    try {
      window.supabase.channel('header-banner-changes')
        .on('postgres_changes', {event: '*', schema: 'public', table: 'app_settings', filter: 'key=eq.header_banner'}, function(payload){
          try {
            var newVal = payload.new && payload.new.value;
            if(!newVal) return;
            var newCfg = typeof newVal === 'string' ? JSON.parse(newVal) : newVal;
            _applyBannerConfig(newCfg);
          } catch(re){ console.warn('[API] banner realtime:', re); }
        })
        .subscribe();
    } catch(se){ /* realtime optional */ }
  } catch(e){ console.warn('[API] banner:', e); }
}

// ===== HELPERS =====
function _ensureSupabase(){
  if(!window.supabase) console.warn('[API] Supabase není připojen');
}

async function _getUserId(){
  try {
    var r = await window.supabase.auth.getUser();
    return (r.data && r.data.user) ? r.data.user.id : null;
  } catch(e){ return null; }
}

// ===== PROFIL =====
async function apiFetchProfile(){
  _ensureSupabase();
  if(!window.supabase) return null;
  try {
    var uid = await _getUserId();
    if(!uid) return null;
    var r = await window.supabase.from('profiles').select('*').eq('id', uid).single();
    if(r.data){
      // Doplň email z auth
      var u = await window.supabase.auth.getUser();
      if(u.data && u.data.user) r.data.email = u.data.user.email;
    }
    return r.data || null;
  } catch(e){ console.error('[API] apiFetchProfile:', e); return null; }
}

async function apiUpdateProfile(data){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    var r = await window.supabase.from('profiles').update(data).eq('id', uid);
    if(r.error) return {error: r.error.message};
    return {error:null};
  } catch(e){ return {error:'Chyba při ukládání profilu'}; }
}

// ===== MOTORKY =====
async function apiFetchMotos(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var r = await window.supabase.from('motorcycles').select('*, branches(name, address, city, is_open)').eq('status','active');
    return r.data || [];
  } catch(e){ console.error('[API] apiFetchMotos:', e); return []; }
}

// ===== SOS REPLACEMENT CHECK =====
async function apiCheckPendingSosReplacement(){
  _ensureSupabase();
  if(!window.supabase) return null;
  try {
    var uid = await _getUserId();
    if(!uid) return null;
    var r = await window.supabase.from('sos_incidents')
      .select('id, type, status, replacement_status, replacement_data, booking_id, original_moto_id, customer_fault')
      .eq('user_id', uid)
      .in('replacement_status', ['selecting', 'pending_payment'])
      .not('status', 'in', '("resolved","closed")')
      .order('created_at', {ascending: false})
      .limit(1);
    if(r.data && r.data.length > 0) return r.data[0];
    return null;
  } catch(e){ console.error('[API] apiCheckPendingSosReplacement:', e); return null; }
}

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

async function apiProcessPayment(bookingId, amount, method){
  _ensureSupabase();
  if(!window.supabase) return {success:false};
  var cfg = window.MOTOGO_CONFIG || {};
  var baseUrl = cfg.SUPABASE_URL;
  var anonKey = cfg.SUPABASE_ANON_KEY;
  var payMethod = method || 'card';

  // Získej auth token
  var token = anonKey;
  try {
    var sess = await window.supabase.auth.getSession();
    if(sess.data && sess.data.session) token = sess.data.session.access_token;
  } catch(e){}

  // 1) Zkus Edge Function (Stripe checkout pro karty, admin client pro cash)
  if(baseUrl){
    try {
      var resp = await fetch(baseUrl + '/functions/v1/process-payment', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + token,
          'apikey': anonKey || ''
        },
        body: JSON.stringify({
          booking_id: bookingId,
          amount: amount,
          method: payMethod
        })
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
    // RPC může vrátit data jako objekt NEBO jako JSON string (záleží na verzi klienta)
    var rpcData = rpcResult.data;
    if(typeof rpcData === 'string'){
      try { rpcData = JSON.parse(rpcData); } catch(pe){}
    }
    if(rpcData && (rpcData.success === true || rpcData === true)){
      return {success:true, transaction_id: rpcData.transaction_id || null};
    }
    // Pokud RPC vrátila data bez chyby = úspěch (funkce provedla UPDATE i bez explicit success)
    if(!rpcResult.error && rpcData !== null && rpcData !== undefined){
      return {success:true};
    }
    if(rpcResult.error){
      console.warn('[API] RPC confirm_payment error:', rpcResult.error.message);
    }
  } catch(e){
    console.warn('[API] RPC fallback failed:', e.message);
  }

  // 3) Poslední fallback: přímý DB update (select pro ověření)
  try {
    // Zjisti start_date pro určení cílového stavu
    var bk = await window.supabase.from('bookings').select('start_date').eq('id', bookingId).single();
    var startsToday = false;
    if(bk.data && bk.data.start_date){
      var sd = new Date(bk.data.start_date); sd.setHours(0,0,0,0);
      var today = new Date(); today.setHours(0,0,0,0);
      startsToday = sd <= today;
    }
    var updateData = {
      payment_status: 'paid',
      payment_method: payMethod,
      status: startsToday ? 'active' : 'reserved',
      confirmed_at: new Date().toISOString()
    };
    if(startsToday) updateData.picked_up_at = new Date().toISOString();
    var r = await window.supabase.from('bookings').update(updateData).eq('id', bookingId).select('id').single();
    if(!r.error && r.data){
      return {success:true};
    }
    // RLS může blokovat – zkus přes service role RPC
    console.warn('[API] Direct DB update failed:', r.error ? r.error.message : 'no rows');
  } catch(e){
    console.warn('[API] Direct DB update exception:', e.message);
  }

  // 4) Záložní RPC pro případ RLS blokace
  try {
    var rpc2 = await window.supabase.rpc('confirm_payment', {
      p_booking_id: bookingId,
      p_method: payMethod
    });
    var rpc2Data = rpc2.data;
    if(typeof rpc2Data === 'string'){
      try { rpc2Data = JSON.parse(rpc2Data); } catch(pe){}
    }
    if(!rpc2.error || (rpc2Data && rpc2Data.success === true)){
      return {success:true};
    }
    console.warn('[API] RPC retry failed:', rpc2.error ? rpc2.error.message : 'unknown');
  } catch(e){
    console.warn('[API] RPC retry exception:', e.message);
  }

  // 5) Poslední záchrana: minimální update jen payment_status (obejde potenciální trigger problém)
  try {
    var minUpdate = await window.supabase.from('bookings')
      .update({ payment_status: 'paid', payment_method: payMethod })
      .eq('id', bookingId)
      .select('id').single();
    if(!minUpdate.error && minUpdate.data){
      // Druhý update pro status (separátně aby trigger nehavaroval na komplexním update)
      var bk2 = await window.supabase.from('bookings').select('start_date').eq('id', bookingId).single();
      var st = false;
      if(bk2.data && bk2.data.start_date){
        var sd2 = new Date(bk2.data.start_date); sd2.setHours(0,0,0,0);
        var td2 = new Date(); td2.setHours(0,0,0,0);
        st = sd2 <= td2;
      }
      await window.supabase.from('bookings')
        .update({ status: st ? 'active' : 'reserved', confirmed_at: new Date().toISOString() })
        .eq('id', bookingId);
      return {success:true};
    }
  } catch(e){
    console.warn('[API] Minimal fallback failed:', e.message);
  }

  console.error('[API] All payment methods failed');
  return {success:false, error: 'Platba se nezdařila – zkuste to znovu'};
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

// ===== SHOP INVOICES – fetch shop order invoices =====
async function apiFetchShopInvoices(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var uid = await _getUserId();
    if(!uid) return [];
    var r = await window.supabase.from('shop_orders')
      .select('*, shop_order_items(*)')
      .eq('customer_id', uid)
      .order('created_at', {ascending: false});
    return r.data || [];
  } catch(e){ console.error('[API] apiFetchShopInvoices:', e); return []; }
}

// ===== AKTIVNÍ VÝPŮJČKA =====
async function apiGetActiveLoan(){
  _ensureSupabase();
  if(!window.supabase) return null;
  try {
    var uid = await _getUserId();
    if(!uid) return null;
    var now = new Date().toISOString();
    var r = await window.supabase.from('bookings')
      .select('*, motorcycles(model, image_url)')
      .eq('user_id', uid)
      .in('status', ['active', 'reserved', 'confirmed', 'pending'])
      .eq('payment_status', 'paid')
      .lte('start_date', now)
      .gte('end_date', now)
      .order('start_date', {ascending: false})
      .limit(1);
    if(r.data && r.data.length > 0){
      r.data[0].moto = r.data[0].motorcycles;
      return r.data[0];
    }
    return null;
  } catch(e){ return null; }
}

// ===== INVOICE GENERATION =====
var _DAY_NAMES = ['ne','po','út','st','čt','pá','so'];
var _MOTO_PRICE_COLS = 'model, spz, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, price_weekday, price_weekend';
function _getDayPrice(m, dow){
  var map = {0:m.price_sun,1:m.price_mon,2:m.price_tue,3:m.price_wed,4:m.price_thu,5:m.price_fri,6:m.price_sat};
  return Number(map[dow] || m.price_weekday || m.price_weekend || 0);
}
function _toDateStr(d){ return d ? String(d).split('T')[0] : ''; }
function _buildDailyItems(m, startDate, endDate){
  var sd = _toDateStr(startDate), ed = _toDateStr(endDate);
  var items = [], s = new Date(sd+'T00:00:00'), e = new Date(ed+'T00:00:00'), c = new Date(s);
  var name = m.model || 'motorky';
  while(c <= e){
    var dow = c.getDay(), p = _getDayPrice(m, dow);
    items.push({description:'Pronájem '+name+' – '+_DAY_NAMES[dow]+' '+c.getDate()+'.'+(c.getMonth()+1)+'.', qty:1, unit_price:p});
    c.setDate(c.getDate()+1);
  }
  return items;
}
function _buildBookingItems(b, m){
  var items = _buildDailyItems(m, b.start_date, b.end_date);
  if(b.extras_price > 0) items.push({description:'Příslušenství / doplňky', qty:1, unit_price:b.extras_price});
  if(b.delivery_fee > 0) items.push({description:'Doručení', qty:1, unit_price:b.delivery_fee});
  if(b.discount_amount > 0) items.push({description:'Sleva'+(b.discount_code?' ('+b.discount_code+')':''), qty:1, unit_price:-b.discount_amount});
  return items;
}
function _calcItemsTotal(items){ return items.reduce(function(s,it){ return s + (it.unit_price||0)*(it.qty||1); }, 0); }

// Storno conditions: 7+ days = 100% refund, 2-7 days = 50%, <2 days = 0%
// refDate = date to measure against (start_date for cancellation, first removed day for shortening)
function _getStornoPercent(refDate){
  var now = new Date(); now.setHours(0,0,0,0);
  var ref = new Date(_toDateStr(refDate)+'T00:00:00');
  var hoursUntil = (ref.getTime() - now.getTime()) / (1000*60*60);
  if(hoursUntil > 7*24) return 100;
  if(hoursUntil > 48) return 50;
  return 0;
}

// Build itemized edit items: original reservation (negative) + new reservation (positive) + storno
function _buildEditItems(editCtx, newBooking, newMoto){
  var items = [];
  var origMoto = editCtx.orig_moto || newMoto;
  // Find original ZF number for reference
  var origRef = editCtx.orig_zf_number ? ' (navazuje na '+editCtx.orig_zf_number+')' : '';
  // Section: Original reservation (negative — odpočet)
  items.push({description:'── Původní rezervace'+origRef+' ──', qty:1, unit_price:0});
  var origItems = _buildDailyItems(origMoto, editCtx.orig_start, editCtx.orig_end);
  origItems.forEach(function(it){ items.push({description:it.description, qty:1, unit_price:-it.unit_price}); });
  if(editCtx.orig_extras > 0) items.push({description:'Příslušenství / doplňky (původní)', qty:1, unit_price:-editCtx.orig_extras});
  if(editCtx.orig_delivery > 0) items.push({description:'Doručení (původní)', qty:1, unit_price:-editCtx.orig_delivery});
  if(editCtx.orig_discount > 0) items.push({description:'Sleva (původní)', qty:1, unit_price:editCtx.orig_discount});
  // Section: New reservation (positive)
  items.push({description:'── Nová rezervace ──', qty:1, unit_price:0});
  var newItems = _buildDailyItems(newMoto, newBooking.start_date, newBooking.end_date);
  newItems.forEach(function(it){ items.push(it); });
  if(newBooking.extras_price > 0) items.push({description:'Příslušenství / doplňky', qty:1, unit_price:newBooking.extras_price});
  if(newBooking.delivery_fee > 0) items.push({description:'Doručení', qty:1, unit_price:newBooking.delivery_fee});
  if(newBooking.discount_amount > 0) items.push({description:'Sleva'+(newBooking.discount_code?' ('+newBooking.discount_code+')':''), qty:1, unit_price:-newBooking.discount_amount});
  // Apply storno conditions for shortened reservations
  var rawTotal = _calcItemsTotal(items);
  if(rawTotal < 0){
    // Determine first removed day for storno calculation (matches UI logic)
    var origEnd = new Date(_toDateStr(editCtx.orig_end)+'T00:00:00');
    var newEnd = new Date(_toDateStr(newBooking.end_date)+'T00:00:00');
    var origStart = new Date(_toDateStr(editCtx.orig_start)+'T00:00:00');
    var newStart = new Date(_toDateStr(newBooking.start_date)+'T00:00:00');
    var stornoRefDate;
    if(newEnd < origEnd){
      // End shortened — first removed day is newEnd + 1
      var frd = new Date(newEnd); frd.setDate(frd.getDate()+1);
      stornoRefDate = frd.toISOString();
    } else if(newStart > origStart){
      // Start shortened — reference is the new start
      stornoRefDate = newStart.toISOString();
    } else {
      stornoRefDate = editCtx.orig_start;
    }
    var stornoPercent = _getStornoPercent(stornoRefDate);
    if(stornoPercent < 100){
      var stornoFee = Math.round(Math.abs(rawTotal) * (100 - stornoPercent) / 100);
      var stornoLabel = stornoPercent === 0
        ? 'Storno poplatek (méně než 2 dny – bez vrácení)'
        : 'Storno poplatek (2–7 dní – vrácení 50 %)';
      items.push({description:stornoLabel, qty:1, unit_price:stornoFee});
    }
  }
  return items;
}

// Generate advance (zálohová) invoice — called on every payment gateway pass
// editCtx (optional for source=edit): {orig_start, orig_end, orig_moto:{model,price_*}, orig_total, orig_extras, orig_delivery, orig_discount, orig_zf_number}
async function apiGenerateAdvanceInvoice(bookingId, amount, source, editCtx){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    var br = await window.supabase.from('bookings')
      .select('*, motorcycles('+_MOTO_PRICE_COLS+')')
      .eq('id', bookingId).single();
    if(br.error || !br.data){ console.error('[API] ZF booking query failed:', br.error ? br.error.message : 'no data'); return {error:'Booking not found: '+(br.error?br.error.message:'no data')}; }
    var b = br.data, m = br.data.motorcycles || {};
    var yr = new Date().getFullYear();
    var lr = await window.supabase.from('invoices').select('number')
      .like('number', 'ZF-' + yr + '-%').order('number', {ascending:false}).limit(1);
    var seq = 1;
    if(lr.data && lr.data.length > 0){
      var mt = lr.data[0].number.match(/-(\d+)$/);
      if(mt) seq = parseInt(mt[1], 10) + 1;
    }
    var invNum = 'ZF-' + yr + '-' + String(seq).padStart(4, '0');
    var items, subtotal;
    if(source === 'edit' && editCtx){
      items = _buildEditItems(editCtx, b, m);
      subtotal = _calcItemsTotal(items);
    } else if(source === 'edit'){
      // Fallback if no editCtx — use amount
      var mName = m.model || 'motorky';
      items = [{description:(amount<0?'Zkrácení':'Prodloužení')+' rezervace – '+mName, qty:1, unit_price:amount}];
      subtotal = amount;
    } else if(source === 'sos'){
      items = [{description:'SOS incident – ' + (m.model||'motorky'), qty:1, unit_price:amount}];
      subtotal = amount;
    } else {
      items = _buildBookingItems(b, m);
      subtotal = _calcItemsTotal(items);
    }
    var tax = 0; // Neplátce DPH
    var total = subtotal;
    var issueDate = new Date().toISOString().slice(0, 10);
    var dueDate = issueDate; // advance = immediate
    var inv = await window.supabase.from('invoices').insert({
      number: invNum, type: 'advance', customer_id: uid, booking_id: bookingId,
      items: items, subtotal: subtotal, tax_amount: tax, total: total,
      issue_date: issueDate, due_date: dueDate, status: 'paid',
      variable_symbol: invNum, source: source || 'booking'
    }).select().single();
    if(inv.error){ console.error('[API] Advance invoice INSERT FAILED:', inv.error.message, inv.error.details, inv.error.hint); return {error: inv.error.message}; }
    // Insert into documents table for app display (type is TEXT column, accepts any value)
    try {
      var docR = await window.supabase.from('documents').insert({
        booking_id: bookingId, user_id: uid, type: 'invoice_advance',
        file_name: 'Zálohová faktura ' + invNum + '.pdf',
        file_path: 'invoices/' + (inv.data ? inv.data.id : bookingId) + '.html'
      });
      if(docR.error) console.warn('[API] ZF doc insert err:', docR.error.message);
    } catch(de){ console.warn('[API] ZF doc insert exception:', de); }
    return {error: null, invoice_number: invNum};
  } catch(e){ console.error('[API] advanceInvoice:', e); return {error: e.message}; }
}

// Generate final (konečná) invoice — called after ride end, summarizes all ZFs
async function apiGenerateFinalInvoice(bookingId){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    var br = await window.supabase.from('bookings')
      .select('*, motorcycles('+_MOTO_PRICE_COLS+')')
      .eq('id', bookingId).single();
    if(br.error || !br.data){ console.error('[API] KF booking query failed:', br.error ? br.error.message : 'no data'); return {error:'Booking not found: '+(br.error?br.error.message:'no data')}; }
    var b = br.data, m = br.data.motorcycles || {};
    // Fetch all DP (payment_receipt) for this booking — only DP are tax documents
    var dpR = await window.supabase.from('invoices').select('*')
      .eq('booking_id', bookingId).eq('type', 'payment_receipt')
      .neq('status', 'cancelled')
      .order('created_at', {ascending: true});
    var receipts = dpR.data || [];
    var yr = new Date().getFullYear();
    var lr = await window.supabase.from('invoices').select('number')
      .like('number', 'KF-' + yr + '-%').order('number', {ascending:false}).limit(1);
    var seq = 1;
    if(lr.data && lr.data.length > 0){
      var mt = lr.data[0].number.match(/-(\d+)$/);
      if(mt) seq = parseInt(mt[1], 10) + 1;
    }
    var invNum = 'KF-' + yr + '-' + String(seq).padStart(4, '0');
    var items = _buildBookingItems(b, m);
    // Deduct ALL DP (daňové doklady k platbě): reservation, edits, SOS
    receipts.forEach(function(a){
      items.push({description: 'Odpočet dle DP ' + a.number, qty: 1, unit_price: -Number(a.total || 0)});
    });
    var subtotal = _calcItemsTotal(items);
    var tax = 0; // Neplátce DPH
    var total = subtotal;
    var issueDate = new Date().toISOString().slice(0, 10);
    var inv = await window.supabase.from('invoices').insert({
      number: invNum, type: 'final', customer_id: uid, booking_id: bookingId,
      items: items, subtotal: subtotal, tax_amount: tax, total: total,
      issue_date: issueDate, due_date: issueDate, status: 'paid',
      variable_symbol: invNum, source: 'final_summary'
    }).select().single();
    if(inv.error){ console.error('[API] Final invoice INSERT FAILED:', inv.error.message, inv.error.details, inv.error.hint); return {error: inv.error.message}; }
    // Insert into documents table for app display (type is TEXT column, accepts any value)
    try {
      var docR = await window.supabase.from('documents').insert({
        booking_id: bookingId, user_id: uid, type: 'invoice_final',
        file_name: 'Konečná faktura ' + invNum + '.pdf',
        file_path: 'invoices/' + (inv.data ? inv.data.id : bookingId) + '.html'
      });
      if(docR.error) console.warn('[API] KF doc insert err:', docR.error.message);
    } catch(de){ console.warn('[API] KF doc insert exception:', de); }
    return {error: null, invoice_number: invNum};
  } catch(e){ console.error('[API] finalInvoice:', e); return {error: e.message}; }
}

// Generate payment receipt (doklad k přijaté platbě) — issued alongside ZF after payment
// editCtx (optional for source=edit): same as apiGenerateAdvanceInvoice
async function apiGeneratePaymentReceipt(bookingId, amount, source, editCtx){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    var br = await window.supabase.from('bookings')
      .select('*, motorcycles('+_MOTO_PRICE_COLS+')')
      .eq('id', bookingId).single();
    if(br.error || !br.data){ console.error('[API] DP booking query failed:', br.error ? br.error.message : 'no data'); return {error:'Booking not found: '+(br.error?br.error.message:'no data')}; }
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
    var items, subtotal;
    if(source === 'edit' && editCtx){
      items = _buildEditItems(editCtx, b, m);
      subtotal = _calcItemsTotal(items);
    } else if(source === 'edit'){
      var mName = m.model || 'motorky';
      items = [{description:(amount<0?'Vrácení za zkrácení':'Doplatek za prodloužení')+' rezervace – '+mName, qty:1, unit_price:amount}];
      subtotal = amount;
    } else if(source === 'sos'){
      items = [{description:'SOS incident – ' + (m.model||'motorky'), qty:1, unit_price:amount}];
      subtotal = amount;
    } else {
      items = _buildBookingItems(b, m);
      subtotal = _calcItemsTotal(items);
    }
    var tax = 0; // Neplátce DPH
    var total = subtotal;
    var issueDate = new Date().toISOString().slice(0, 10);
    var inv = await window.supabase.from('invoices').insert({
      number: dpNum, type: 'payment_receipt', customer_id: uid, booking_id: bookingId,
      items: items, subtotal: subtotal, tax_amount: tax, total: total,
      issue_date: issueDate, due_date: issueDate, status: 'paid',
      variable_symbol: dpNum, source: source || 'booking'
    }).select().single();
    if(inv.error){ console.error('[API] Payment receipt INSERT FAILED:', inv.error.message, inv.error.details, inv.error.hint); return {error: inv.error.message}; }
    // Insert into documents table for app display (type is TEXT column, accepts any value)
    try {
      var docR = await window.supabase.from('documents').insert({
        booking_id: bookingId, user_id: uid, type: 'payment_receipt',
        file_name: 'Doklad k přijaté platbě ' + dpNum + '.pdf',
        file_path: 'invoices/' + (inv.data ? inv.data.id : bookingId) + '.html'
      });
      if(docR.error) console.warn('[API] DP doc insert err:', docR.error.message);
    } catch(de){ console.warn('[API] DP doc insert exception:', de); }
    return {error: null, receipt_number: dpNum};
  } catch(e){ console.error('[API] paymentReceipt:', e); return {error: e.message}; }
}

// Legacy alias
var apiAutoGenerateInvoice = apiGenerateAdvanceInvoice;

// force=true: delete existing contract/vop and regenerate (used after booking modification)
async function apiAutoGenerateBookingDocs(bookingId, force){
  _ensureSupabase();
  if(!window.supabase) return;
  try {
    var uid = await _getUserId();
    if(!uid) return;
    // Check if docs already exist for this booking
    var existing = await window.supabase.from('documents')
      .select('id, type').eq('booking_id', bookingId).eq('user_id', uid)
      .in('type', ['contract', 'vop']);
    var existingTypes = (existing.data || []).map(function(d){ return d.type; });

    // Force mode: delete old contract/vop so new ones are generated with updated data
    if(force && existing.data && existing.data.length > 0){
      for(var di=0; di<existing.data.length; di++){
        await window.supabase.from('documents').delete().eq('id', existing.data[di].id);
      }
      // Also delete from generated_documents
      await window.supabase.from('generated_documents').delete().eq('booking_id', bookingId);
      existingTypes = [];
    }

    // Generate contract via edge function (creates generated_documents + syncs to documents via trigger)
    if(existingTypes.indexOf('contract') === -1){
      try {
        await window.supabase.functions.invoke('generate-document', {
          body: { template_slug: 'rental_contract', booking_id: bookingId }
        });
      } catch(e){
        console.warn('[API] Contract edge fn failed, inserting fallback:', e.message);
        await window.supabase.from('documents').insert({
          booking_id: bookingId, user_id: uid, type: 'contract',
          file_name: 'Smlouva o pronájmu.pdf',
          file_path: 'contracts/' + bookingId + '_contract.html'
        });
      }
    }
    // Generate VOP via edge function
    if(existingTypes.indexOf('vop') === -1){
      try {
        await window.supabase.functions.invoke('generate-document', {
          body: { template_slug: 'vop', booking_id: bookingId }
        });

      } catch(e){
        console.warn('[API] VOP edge fn failed, inserting fallback:', e.message);
        await window.supabase.from('documents').insert({
          booking_id: bookingId, user_id: uid, type: 'vop',
          file_name: 'Všeobecné obchodní podmínky.pdf',
          file_path: 'documents/vop_current.html'
        });
      }
    }
  } catch(e){ console.error('[API] autoGenerateBookingDocs:', e); }
}

// ===== DOKUMENTY =====
async function apiFetchDocuments(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var uid = await _getUserId();
    if(!uid) return [];
    var results = [];
    // 1) documents table (local auto-generated)
    var r = await window.supabase.from('documents')
      .select('*, bookings(start_date, total_price, motorcycles(model))')
      .eq('user_id', uid)
      .order('created_at', {ascending: false});
    if(r.data) r.data.forEach(function(d){
      // Skip invoice_shop from documents table — step 4 (shop_orders) handles these with correct IDs
      if(d.type === 'invoice_shop') return;
      // Dedup within documents table by file_path (sync trigger can create duplicate rows)
      // Allow multiple invoices of same type per booking (e.g. original ZF + edit ZF)
      var existingDoc = results.find(function(ex){
        return ex.file_path && d.file_path && ex.file_path === d.file_path;
      });
      if(existingDoc) return;
      var b = d.bookings;
      d.date = d.created_at;
      d.moto_name = (b && b.motorcycles) ? b.motorcycles.model : '';
      d.amount = b ? b.total_price : 0;
      d.res_num = b ? '#' + d.booking_id.substr(-8).toUpperCase() : '';
      results.push(d);
    });
    // 2) invoices table (Velín-generated)
    var ir = await window.supabase.from('invoices')
      .select('*, bookings:booking_id(start_date, total_price, motorcycles(model))')
      .eq('customer_id', uid)
      .order('created_at', {ascending: false});
    if(ir.data) ir.data.forEach(function(inv){
      // Skip shop_final invoices — step 4 (shop_orders) handles these with correct IDs
      if(inv.type === 'shop_final') return;
      var b = inv.bookings;
      var iType = inv.type === 'payment_receipt' ? 'payment_receipt'
        : (inv.type === 'proforma' || inv.type === 'advance') ? 'invoice_advance'
        : 'invoice_final';
      // Dedup by invoice id or file_path (allow multiple invoices of same type per booking)
      var invFilePath = 'invoices/' + inv.id + '.html';
      var existing = results.find(function(d){
        return d.id === inv.id || (d.file_path && d.file_path === invFilePath);
      });
      if(existing){
        // Enrich existing doc entry with invoice data (source, number, total)
        if(!existing._invoice) existing._invoice = inv;
        if(!existing.amount || existing.amount === 0) existing.amount = inv.total || 0;
        return;
      }
      results.push({
        id: inv.id, booking_id: inv.booking_id,
        type: iType, _invoice: inv,
        date: inv.created_at,
        moto_name: (b && b.motorcycles) ? b.motorcycles.model : '',
        amount: inv.total || (b ? b.total_price : 0),
        res_num: b ? '#' + inv.booking_id.substr(-8).toUpperCase() : '',
        file_name: inv.number || ''
      });
    });
    // 3) generated_documents (Velín contracts/protocols/VOP)
    var gr = await window.supabase.from('generated_documents')
      .select('*, document_templates:template_id(type, name), bookings:booking_id(start_date, total_price, motorcycles(model))')
      .eq('customer_id', uid)
      .order('created_at', {ascending: false});
    if(gr.data) gr.data.forEach(function(gd){
      var b = gd.bookings;
      var tplType = (gd.document_templates && gd.document_templates.type) || '';
      var mappedType = tplType === 'handover_protocol' ? 'protocol'
        : tplType === 'vop' ? 'vop' : 'contract';
      var hasDup = results.find(function(d){
        return d.booking_id === gd.booking_id && d.type === mappedType;
      });
      if(hasDup) return;
      results.push({
        id: gd.id, booking_id: gd.booking_id,
        type: mappedType, _genDoc: gd,
        date: gd.created_at,
        moto_name: (b && b.motorcycles) ? b.motorcycles.model : '',
        amount: b ? b.total_price : 0,
        res_num: b ? '#' + gd.booking_id.substr(-8).toUpperCase() : '',
        file_path: gd.pdf_path || ''
      });
    });
    // 4) shop_orders – faktury z e-shopu
    try {
      var sr = await window.supabase.from('shop_orders')
        .select('*, shop_order_items(*)')
        .eq('customer_id', uid)
        .in('payment_status', ['paid','pending'])
        .order('created_at', {ascending: false});
      if(sr.data) sr.data.forEach(function(so){
        var itemNames = (so.shop_order_items||[]).map(function(i){ return i.product_name; }).join(', ');
        results.push({
          id: so.id, booking_id: null,
          type: 'invoice_shop', _shopOrder: so,
          date: so.created_at,
          moto_name: '',
          shop_items: itemNames || 'Shop',
          amount: so.total || 0,
          res_num: '#OBJ-' + (so.order_number || so.id.substr(-6).toUpperCase()),
          file_name: 'Faktura objednávka ' + (so.order_number || '')
        });
      });
    } catch(se){ console.error('[API] shop_orders fetch:', se); }
    // Attach debug info for visible diagnostics
    results._debug = {
      docs: r.error ? 'ERR: '+r.error.message : (r.data||[]).length,
      invoices: ir.error ? 'ERR: '+ir.error.message : (ir.data||[]).length,
      docsTypes: (r.data||[]).map(function(d){return d.type;}),
      invTypes: (ir.data||[]).map(function(i){return i.type+'/'+i.number;})
    };
    return results;
  } catch(e){ console.error('[API] apiFetchDocuments:', e); return []; }
}

// Fetch invoices for a specific booking (from invoices table)
async function apiFetchBookingInvoices(bookingId){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var r = await window.supabase.from('invoices')
      .select('*').eq('booking_id', bookingId)
      .order('created_at', {ascending: false});
    return r.data || [];
  } catch(e){ return []; }
}

// Fetch generated documents for a specific booking
async function apiFetchBookingGenDocs(bookingId){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var r = await window.supabase.from('generated_documents')
      .select('*').eq('booking_id', bookingId)
      .order('created_at', {ascending: false});
    return r.data || [];
  } catch(e){ return []; }
}

async function apiUploadDocument(bookingId, fileData, docType){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    var r = await window.supabase.from('documents').insert({
      booking_id: bookingId,
      user_id: uid,
      type: docType,
      file_path: 'signatures/' + bookingId + '_' + docType + '.png',
      file_name: docType + '_' + bookingId.substr(-8) + '.png'
    });
    if(r.error) return {error: r.error.message};
    return {error:null};
  } catch(e){ return {error:'Chyba při nahrávání dokumentu'}; }
}

async function apiSendDocumentEmail(docId){
  // Supabase nemá email service – simulace pro UI
  try {
    var profile = await apiFetchProfile();
    var email = profile ? profile.email : 'email@email.cz';
    return {success:true, email: email};
  } catch(e){ return {success:false}; }
}

// ===== SOS =====
async function apiCreateSosIncident(type, bookingId, lat, lng, desc, critical, motoId){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline – Supabase nepřipojen'};
  try {
    var uid = await _getUserId();
    if(!uid){
      console.error('[SOS] apiCreateSosIncident: user_id is null — session expired?');
      return {error:'Nepřihlášen – přihlaste se znovu'};
    }
    var data = {user_id: uid, type: type, status: 'reported'};
    if(bookingId) data.booking_id = bookingId;
    if(motoId) data.moto_id = motoId;
    if(lat != null && !isNaN(lat)) data.latitude = lat;
    if(lng != null && !isNaN(lng)) data.longitude = lng;
    if(desc) data.description = desc;
    var r = await window.supabase.from('sos_incidents').insert(data).select().single();
    if(r.error){
      console.error('[SOS] INSERT error:', r.error.code, r.error.message, r.error.details, r.error.hint, 'status:', r.status);
      var errMsg = r.error.message || 'Neznámá chyba';
      // Pokud je to 403/RLS error, přidej nápovědu
      if(r.status === 403 || (errMsg && errMsg.indexOf('policy') >= 0)){
        errMsg = 'Nemáte oprávnění — zkuste se odhlásit a přihlásit znovu. (' + errMsg + ')';
      }
      return {error: errMsg, code: r.error.code, details: r.error.details, status: r.status};
    }
    return r.data || {};
  } catch(e){
    console.error('[SOS] apiCreateSosIncident exception:', e);
    return {error:'Výjimka: ' + (e.message || e)};
  }
}

async function apiGetMySosIncidents(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var uid = await _getUserId();
    if(!uid) return [];
    var r = await window.supabase.from('sos_incidents')
      .select('*')
      .eq('user_id', uid)
      .order('created_at', {ascending: false})
      .limit(10);
    return r.data || [];
  } catch(e){ return []; }
}

async function apiSosRequestReplacement(incidentId){
  _ensureSupabase();
  if(!window.supabase) return {};
  try {
    await window.supabase.from('sos_timeline').insert({
      incident_id: incidentId,
      action: 'replacement_requested',
      data: { note: 'Zákazník žádá náhradní motorku' }
    });
    return {success:true};
  } catch(e){ return {}; }
}

async function apiSosRequestTow(incidentId){
  _ensureSupabase();
  if(!window.supabase) return {};
  try {
    await window.supabase.from('sos_timeline').insert({
      incident_id: incidentId,
      action: 'tow_requested',
      data: { note: 'Zákazník žádá odtahovou službu' }
    });
    return {success:true};
  } catch(e){ return {}; }
}

async function apiSosShareLocation(incidentId, lat, lng){
  _ensureSupabase();
  if(!window.supabase) return {};
  try {
    await window.supabase.from('sos_timeline').insert({
      incident_id: incidentId,
      action: 'location_shared',
      data: { note: 'GPS: ' + lat + ', ' + lng, latitude: lat, longitude: lng }
    });
    return {success:true};
  } catch(e){ return {}; }
}

// ===== ADMIN MESSAGES (Zprávy z velínu) =====
async function apiFetchAdminMessages(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var uid = await _getUserId();
    if(!uid) return [];
    var r = await window.supabase.from('admin_messages')
      .select('*')
      .eq('user_id', uid)
      .order('created_at', {ascending: false})
      .limit(50);
    return r.data || [];
  } catch(e){ console.error('[API] apiFetchAdminMessages:', e); return []; }
}

async function apiMarkMessageRead(msgId){
  _ensureSupabase();
  if(!window.supabase) return;
  try {
    await window.supabase.from('admin_messages')
      .update({read: true})
      .eq('id', msgId);
  } catch(e){}
}

async function apiGetUnreadMessageCount(){
  _ensureSupabase();
  if(!window.supabase) return 0;
  try {
    var uid = await _getUserId();
    if(!uid) return 0;
    var r = await window.supabase.from('admin_messages')
      .select('id', {count: 'exact', head: true})
      .eq('user_id', uid)
      .eq('read', false);
    return r.count || 0;
  } catch(e){ return 0; }
}

function apiSubscribeAdminMessages(callback){
  if(!window.supabase) return null;
  _getUserId().then(function(uid){
    if(!uid) return;
    window.supabase
      .channel('admin_messages_' + uid)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'admin_messages',
        filter: 'user_id=eq.' + uid
      }, function(payload){
        if(payload.new) callback(payload.new);
      })
      .subscribe();
  });
}

// ===== REALTIME SUBSCRIPTIONS — auto-update when admin changes data =====
var _realtimeChannel = null;
var _realtimeRefreshTimer = null;

function apiSubscribeRealtimeUpdates(){
  if(!window.supabase) return;
  if(_realtimeChannel) return; // already subscribed

  _realtimeChannel = window.supabase
    .channel('motogo-realtime')
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'motorcycles'
    }, function(payload){
      _scheduleRealtimeRefresh('motos');
    })
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'bookings'
    }, function(payload){
      _scheduleRealtimeRefresh('bookings');
    })
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'moto_day_prices'
    }, function(payload){
      _scheduleRealtimeRefresh('motos');
    })
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'documents'
    }, function(payload){
    })
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'invoices'
    }, function(payload){
    })
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'sos_incidents'
    }, function(payload){
      _scheduleRealtimeRefresh('sos');
    })
    .subscribe();
}

function _scheduleRealtimeRefresh(type){
  // Debounce: wait 500ms then refresh to batch rapid changes
  if(_realtimeRefreshTimer) clearTimeout(_realtimeRefreshTimer);
  _realtimeRefreshTimer = setTimeout(function(){
    _realtimeRefreshTimer = null;
    if(type === 'motos' || type === 'all'){
      if(typeof enrichMOTOS === 'function'){
        enrichMOTOS().then(function(){
          if(typeof initMotoAvailability === 'function') initMotoAvailability();
          if(typeof applyFilters === 'function') applyFilters();
        });
      }
    }
    if(type === 'bookings' || type === 'all'){
      if(typeof renderMyReservations === 'function' && typeof cur !== 'undefined' && cur === 's-res'){
        renderMyReservations();
      }
      if(typeof _currentResId !== 'undefined' && _currentResId && typeof cur !== 'undefined' && cur === 's-res-detail'){
        if(typeof openResDetailById === 'function') openResDetailById(_currentResId);
      }
    }
  }, 500);
}

// Periodic background refresh (every 4 seconds) as fallback
var _bgRefreshInterval = null;
function apiStartBackgroundRefresh(){
  if(_bgRefreshInterval) return;
  _bgRefreshInterval = setInterval(function(){
    if(typeof enrichMOTOS === 'function'){
      enrichMOTOS().then(function(){
        if(typeof initMotoAvailability === 'function') initMotoAvailability();
      });
    }
  }, 4000);
}

function apiStopBackgroundRefresh(){
  if(_bgRefreshInterval){ clearInterval(_bgRefreshInterval); _bgRefreshInterval = null; }
}

// ===== PROMO KÓDY — zalogování použití při platbě =====
async function apiUsePromoCode(code, bookingId, baseAmount){
  _ensureSupabase();
  if(!window.supabase || !code) return {valid:false};
  try {
    var r = await window.supabase.rpc('use_promo_code', {
      p_code: code,
      p_booking_id: bookingId || null,
      p_base_amount: baseAmount || 0
    });
    if(r.data) return r.data;
    if(r.error) console.warn('[API] usePromoCode error:', r.error.message);
    return {valid:false};
  } catch(e){ console.error('[API] apiUsePromoCode:', e); return {valid:false}; }
}

// ===== CUSTOMER → ADMIN ZPRÁVY =====
async function apiSendCustomerMessage(threadId, content){
  _ensureSupabase();
  if(!window.supabase) return {error:'Offline'};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    var profile = await apiFetchProfile();
    var senderName = profile ? profile.full_name : 'Zákazník';
    var r = await window.supabase.from('messages').insert({
      thread_id: threadId,
      direction: 'customer',
      sender_name: senderName,
      content: content
    });
    if(r.error) return {error: r.error.message};
    // Update thread last_message_at
    await window.supabase.from('message_threads').update({
      last_message_at: new Date().toISOString(),
      status: 'open'
    }).eq('id', threadId);
    return {error:null};
  } catch(e){ return {error:'Chyba při odesílání zprávy'}; }
}

async function apiFetchMyThreads(){
  _ensureSupabase();
  if(!window.supabase) return [];
  try {
    var uid = await _getUserId();
    if(!uid) return [];
    var r = await window.supabase.from('message_threads')
      .select('*, messages(id, content, direction, created_at)')
      .eq('customer_id', uid)
      .order('last_message_at', {ascending: false});
    return r.data || [];
  } catch(e){ console.error('[API] apiFetchMyThreads:', e); return []; }
}

// ===== ENRICHMENT: propojení lokálního katalogu s Supabase =====

// Originální kopie MOTOS — uloží se při prvním volání enrichMOTOS.
// Díky tomu lze enrichMOTOS volat opakovaně (návrat na home/search)
// bez ztráty motorek co byly mezitím znovu aktivovány.
var _MOTOS_ORIG = null;

/**
 * Obohatí globální pole MOTOS o data ze Supabase.
 * Přiřadí _db objekt (UUID, status, ceny, km) ke každé motorce.
 * Odstraní z MOTOS motorky co nejsou v DB jako 'active'.
 * Bezpečné volat opakovaně — vždy staví z _MOTOS_ORIG.
 */
async function enrichMOTOS(){
  if(typeof MOTOS === 'undefined' || !window.supabase) return;
  try {
    // Ulož originál při prvním volání
    if(!_MOTOS_ORIG){
      _MOTOS_ORIG = MOTOS.map(function(m){
        return JSON.parse(JSON.stringify(m));
      });
    }

    // Načti VŠECHNY motorky z DB
    var r = await window.supabase
      .from('motorcycles')
      .select('id, model, status, mileage, year, category, price_weekday, price_weekend, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, branch_id, image_url, images, stk_valid_until, engine_type, engine_cc, power_kw, power_hp, torque_nm, weight_kg, fuel_tank_l, seat_height_mm, license_required, has_abs, has_asc, description, ideal_usage, features, manual_url, branches(name, address, city, is_open)');
    var dbMotos = (r.data || []);

    // Vytvoř mapu podle normalizovaného jména
    var dbMap = {};
    dbMotos.forEach(function(dm){
      var key = dm.model.toLowerCase().replace(/\s+/g, '');
      dbMap[key] = dm;
    });

    // Přebuduj MOTOS z originálu — jen aktivní motorky
    var fresh = [];
    for(var i = 0; i < _MOTOS_ORIG.length; i++){
      var m = JSON.parse(JSON.stringify(_MOTOS_ORIG[i]));
      var key = m.name.toLowerCase().replace(/\s+/g, '');
      var db = dbMap[key];

      // Motorka není v DB nebo není active → přeskoč
      if(!db || db.status !== 'active') continue;
      // Pobočka je zavřená → přeskoč
      if(db.branches && db.branches.is_open === false) continue;

      // Přiřaď _db objekt
      m._db = {
        id: db.id,
        status: db.status,
        mileage: db.mileage,
        branch_id: db.branch_id,
        branch_name: db.branches ? db.branches.name : null,
        branch_address: db.branches ? db.branches.address : null,
        branch_city: db.branches ? db.branches.city : null,
        branch_is_open: db.branches ? db.branches.is_open : null,
        image_url: db.image_url,
        images: db.images,
        stk_valid_until: db.stk_valid_until,
      };

      // Fotky z Velínu (Supabase storage) mají přednost před statickými
      if(db.image_url) m.img = db.image_url;
      if(db.images && db.images.length) m.imgs = db.images;

      // Aktualizuj specs z DB (pokud jsou vyplněny ve Velínu)
      if(db.engine_type || db.power_kw || db.torque_nm || db.weight_kg){
        var dbSpecs = [];
        if(db.engine_type || db.engine_cc) dbSpecs.push({l:'Motor', v: (db.engine_cc ? db.engine_cc+' cc ' : '')+(db.engine_type||'')});
        if(db.power_kw) dbSpecs.push({l:'Výkon', v: db.power_kw+' kW'+(db.power_hp ? ' / '+db.power_hp+' k' : '')});
        if(db.torque_nm) dbSpecs.push({l:'Točivý moment', v: db.torque_nm+' Nm'});
        if(db.weight_kg) dbSpecs.push({l:'Hmotnost', v: db.weight_kg+' kg'});
        if(db.fuel_tank_l) dbSpecs.push({l:'Nádrž', v: db.fuel_tank_l+' L'});
        if(db.seat_height_mm) dbSpecs.push({l:'Sedlo', v: db.seat_height_mm+' mm'});
        if(db.license_required) dbSpecs.push({l:'ŘP kategorie', v: db.license_required});
        var absAsc = [];
        if(db.has_abs !== null) absAsc.push(db.has_abs ? 'ABS' : '—');
        if(db.has_asc !== null) absAsc.push(db.has_asc ? 'ASC' : '—');
        if(absAsc.length) dbSpecs.push({l:'ABS / ASC', v: absAsc.join(' / ')});
        if(dbSpecs.length > 0) m.specs = dbSpecs;
      }
      // Aktualizuj kategorii, ŘP a výkon z DB (přepiš hardcoded)
      if(db.category){ var _nc=db.category.toLowerCase().replace(/[íé]/g,function(c){return c==='í'?'i':'e';}); m.cat=_nc; }
      if(db.license_required) m.rp = db.license_required;
      if(db.power_kw) m.vykon = db.power_kw;

      if(db.description) m.desc = db.description;
      if(db.ideal_usage && db.ideal_usage.length) m.vyuziti = db.ideal_usage;
      if(db.features && db.features.length) m.feats = db.features;
      if(db.manual_url) m.manual = db.manual_url;

      // Aktualizuj pobočku z DB (přepiš hardcoded loc)
      if(db.branches){
        m.loc = (db.branches.address || '') + ', ' + (db.branches.city || '') + (db.year ? ' · ' + db.year : '');
        m.branch = db.branch_id;
        m._db.branch_name = db.branches.name;
        m._db.branch_address = db.branches.address;
        m._db.branch_city = db.branches.city;
      }

      // Aktualizuj ceny z DB (přepiš hardcoded pricing)
      if(db.price_weekday || db.price_weekend){
        m.pricing = {
          po: Number(db.price_mon || db.price_weekday) || m.pricing.po,
          ut: Number(db.price_tue || db.price_weekday) || m.pricing.ut,
          st: Number(db.price_wed || db.price_weekday) || m.pricing.st,
          ct: Number(db.price_thu || db.price_weekday) || m.pricing.ct,
          pa: Number(db.price_fri || db.price_weekend) || m.pricing.pa,
          so: Number(db.price_sat || db.price_weekend) || m.pricing.so,
          ne: Number(db.price_sun || db.price_weekend) || m.pricing.ne,
        };
      }

      fresh.push(m);
    }

    // Přidej motorky z DB které NEMAJÍ lokální protějšek (přidány přes Velín)
    var usedKeys = {};
    for(var ui = 0; ui < fresh.length; ui++){
      usedKeys[fresh[ui].name.toLowerCase().replace(/\s+/g, '')] = true;
    }
    dbMotos.forEach(function(db){
      if(db.status !== 'active') return;
      var key = db.model.toLowerCase().replace(/\s+/g, '');
      if(usedKeys[key]) return; // již máme z lokálních dat
      // Vytvoř novou motorku čistě z DB dat
      var nm = {
        id: 'db-' + db.id.substr(0,8),
        name: db.model,
        loc: (db.branches ? db.branches.address + ', ' + db.branches.city : 'Mezná') + (db.year ? ' · ' + db.year : ''),
        img: db.image_url || '',
        imgs: db.images && db.images.length ? db.images : (db.image_url ? [db.image_url] : []),
        avail: true,
        cat: (db.category || 'cestovni').toLowerCase().replace(/[íé]/g,function(c){return c==='í'?'i':'e';}),
        rp: db.license_required || 'A',
        vykon: db.power_kw || 0,
        desc: db.description || db.model,
        specs: [],
        feats: db.features || [],
        vyuziti: db.ideal_usage || [],
        pricing: {
          po: Number(db.price_mon || db.price_weekday) || 2000,
          ut: Number(db.price_tue || db.price_weekday) || 2000,
          st: Number(db.price_wed || db.price_weekday) || 2000,
          ct: Number(db.price_thu || db.price_weekday) || 2000,
          pa: Number(db.price_fri || db.price_weekend) || 2500,
          so: Number(db.price_sat || db.price_weekend) || 2500,
          ne: Number(db.price_sun || db.price_weekend) || 2500,
        },
        branch: db.branch_id || 'mezna',
        manual: db.manual_url || '',
        price: (Number(db.price_weekday) || 2000).toLocaleString('cs-CZ') + ' Kč',
        _db: {
          id: db.id,
          status: db.status,
          mileage: db.mileage,
          branch_id: db.branch_id,
          branch_name: db.branches ? db.branches.name : null,
          branch_address: db.branches ? db.branches.address : null,
          branch_city: db.branches ? db.branches.city : null,
          image_url: db.image_url,
          images: db.images,
          stk_valid_until: db.stk_valid_until,
        }
      };
      // Build specs
      var ds = [];
      if(db.engine_type || db.engine_cc) ds.push({l:'Motor', v: (db.engine_cc ? db.engine_cc+' cc ' : '')+(db.engine_type||'')});
      if(db.power_kw) ds.push({l:'Výkon', v: db.power_kw+' kW'+(db.power_hp ? ' / '+db.power_hp+' k' : '')});
      if(db.torque_nm) ds.push({l:'Točivý moment', v: db.torque_nm+' Nm'});
      if(db.weight_kg) ds.push({l:'Hmotnost', v: db.weight_kg+' kg'});
      if(db.fuel_tank_l) ds.push({l:'Nádrž', v: db.fuel_tank_l+' L'});
      if(db.seat_height_mm) ds.push({l:'Sedlo', v: db.seat_height_mm+' mm'});
      if(db.license_required) ds.push({l:'ŘP kategorie', v: db.license_required});
      var absAsc = [];
      if(db.has_abs !== null) absAsc.push(db.has_abs ? 'ABS' : '—');
      if(db.has_asc !== null) absAsc.push(db.has_asc ? 'ASC' : '—');
      if(absAsc.length) ds.push({l:'ABS / ASC', v: absAsc.join(' / ')});
      nm.specs = ds;
      fresh.push(nm);
    });

    // Nahraď MOTOS čerstvým polem (in-place pro zachování reference)
    MOTOS.length = 0;
    for(var j = 0; j < fresh.length; j++) MOTOS.push(fresh[j]);

    window._enrichMOTOSDone = true;
  } catch(e){
    console.error('[API] enrichMOTOS chyba:', e);
  }
}

// ===== AUTO-GENERATE PROTOCOL ON RENTAL START DATE =====
async function apiAutoGenerateProtocolForToday(){
  if(!window.supabase) return;
  try {
    var uid = await _getUserId();
    if(!uid) return;
    var today = new Date().toISOString().slice(0,10);
    // Find bookings starting today that don't have a protocol yet
    var bks = await window.supabase.from('bookings').select('id')
      .eq('user_id', uid).eq('payment_status','paid')
      .gte('start_date', today + 'T00:00:00')
      .lte('start_date', today + 'T23:59:59');
    if(!bks.data) return;
    for(var i=0;i<bks.data.length;i++){
      var bid = bks.data[i].id;
      var existing = await window.supabase.from('documents').select('id')
        .eq('booking_id', bid).eq('user_id', uid).eq('type','protocol').limit(1);
      if(existing.data && existing.data.length > 0) continue;
      await window.supabase.from('documents').insert({
        booking_id: bid, user_id: uid, type: 'protocol',
        file_name: 'Předávací protokol.pdf',
        file_path: 'protocols/' + bid + '_protocol.html'
      });
    }
  } catch(e){ console.warn('[API] protocolAutoGen:', e); }
}

// ===== AUTO-GENERATE FINAL INVOICE FOR ENDED BOOKINGS =====
async function apiAutoGenerateFinalInvoiceForEnded(){
  if(!window.supabase) return;
  try {
    var uid = await _getUserId();
    if(!uid) return;
    var today = new Date().toISOString().slice(0,10);
    // Find completed/active/reserved bookings that are paid and ended (end_date < today or status=completed)
    var bks = await window.supabase.from('bookings').select('id, status, end_date')
      .eq('user_id', uid).eq('payment_status','paid')
      .in('status', ['completed','active','reserved'])
      .lte('end_date', today + 'T23:59:59');
    if(!bks.data) return;
    for(var i=0;i<bks.data.length;i++){
      var b = bks.data[i];
      // Only process if status=completed or end_date < today
      var endDate = new Date(b.end_date); endDate.setHours(0,0,0,0);
      var todayDate = new Date(today); todayDate.setHours(0,0,0,0);
      if(b.status !== 'completed' && endDate >= todayDate) continue;
      // Check if final invoice exists
      var existing = await window.supabase.from('invoices').select('id')
        .eq('booking_id', b.id).eq('type','final').limit(1);
      if(existing.data && existing.data.length > 0) continue;
      await apiGenerateFinalInvoice(b.id);
    }
  } catch(e){ console.warn('[API] finalInvoiceAutoGen:', e); }
}

// ===== FETCH DOCUMENT TEMPLATE (from Velín-uploaded PDFs) =====
async function apiFetchDocTemplate(templateType){
  if(!window.supabase) return null;
  // Map legacy type names to DB template types
  var typeMap = { 'contract': 'rental_contract', 'protocol': 'handover_protocol' };
  var dbType = typeMap[templateType] || templateType;
  try {
    var r = await window.supabase.from('document_templates')
      .select('content_html, name, version')
      .eq('type', dbType).eq('active', true)
      .order('version', {ascending:false}).limit(1);
    return (r.data && r.data[0]) || null;
  } catch(e){ return null; }
}
