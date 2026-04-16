
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

