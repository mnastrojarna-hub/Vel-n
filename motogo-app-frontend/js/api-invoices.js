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
// Logika začátku výpůjčky:
//   'delivery' (přistavení) → přesný čas start_date
//   'store' (pobočka):
//     - dnes → ihned aktivní (zákazník si může vyzvednout hned)
//     - jiný den → přesný čas start_date
function _hasBookingStarted(booking){
  if(!booking || !booking.start_date) return false;
  var now = new Date();
  var startDate = new Date(booking.start_date);
  if(booking.pickup_method === 'store'){
    // Pobočka + start_date je dnes → ihned aktivní
    var today = new Date();
    today.setHours(0,0,0,0);
    var startDay = new Date(startDate);
    startDay.setHours(0,0,0,0);
    if(startDay.getTime() === today.getTime()) return true;
    // Pobočka + jiný den → přesný čas
  }
  return now >= startDate;
}

function _isBookingStillActive(booking){
  if(!booking || !booking.end_date) return true;
  var now = new Date();
  var endDate = new Date(booking.end_date);
  if(booking.return_method === 'store'){
    // Zákazník vrací sám → do půlnoci posledního dne
    var midnight = new Date(endDate);
    midnight.setHours(23,59,59,999);
    return now <= midnight;
  }
  // Svoz → přesný čas
  return now <= endDate;
}

// Vrací true pokud do konce výpůjčky zbývá 30 min nebo méně
function _isNearReturnTime(booking){
  if(!booking || !booking.end_date) return false;
  var now = new Date();
  var endDate = new Date(booking.end_date);
  if(booking.return_method === 'store'){
    var midnight = new Date(endDate);
    midnight.setHours(23,59,59,999);
    var diff = midnight.getTime() - now.getTime();
    return diff >= 0 && diff <= 30 * 60 * 1000;
  }
  var diff = endDate.getTime() - now.getTime();
  return diff >= 0 && diff <= 30 * 60 * 1000;
}

async function apiGetActiveLoan(){
  _ensureSupabase();
  if(!window.supabase) return null;
  try {
    var uid = await _getUserId();
    if(!uid) return null;
    // 1) Priorita: booking se statusem 'active' (motorka je venku)
    var r = await window.supabase.from('bookings')
      .select('*, motorcycles(model, image_url)')
      .eq('user_id', uid)
      .eq('status', 'active')
      .order('start_date', {ascending: false})
      .limit(5);
    if(r.data && r.data.length > 0){
      // Preferuj booking co reálně začal a běží
      var best = null;
      for(var j = 0; j < r.data.length; j++){
        var bk = r.data[j];
        bk.moto = bk.motorcycles;
        if(_hasBookingStarted(bk)){
          bk._pastEndTime = !_isBookingStillActive(bk);
          bk._nearReturnTime = _isNearReturnTime(bk);
          if(!best) best = bk;
          // Preferuj ten co ještě běží (není past end)
          if(!bk._pastEndTime){ best = bk; break; }
        }
      }
      if(best) return best;
    }
    // 2) Fallback: reserved/confirmed — zkontroluj s ohledem na pickup/return method
    r = await window.supabase.from('bookings')
      .select('*, motorcycles(model, image_url)')
      .eq('user_id', uid)
      .in('status', ['reserved', 'active'])
      .eq('payment_status', 'paid')
      .order('start_date', {ascending: true})
      .limit(10);
    if(r.data && r.data.length > 0){
      var nextUpcoming = null;
      for(var i = 0; i < r.data.length; i++){
        var b2 = r.data[i];
        b2.moto = b2.motorcycles;
        if(_hasBookingStarted(b2) && _isBookingStillActive(b2)){
          return b2; // Aktivní booking co začal a běží
        }
        // Zapamatuj si první nadcházející (start v budoucnu)
        if(!nextUpcoming && !_hasBookingStarted(b2)){
          nextUpcoming = b2;
        }
      }
      // Žádný aktivní → vrať nadcházející s příznakem
      if(nextUpcoming){
        nextUpcoming._isUpcoming = true;
        return nextUpcoming;
      }
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
  // Skip ZF generation for zero-amount operations (free modifications, SOS without payment)
  if(source === 'edit' && amount === 0) return {error: null, skipped: true};
  try {
    var uid = await _getUserId();
    if(!uid) return {error:'Nepřihlášen'};
    // Dedup: check if a ZF with same source already exists for this booking
    var existingZf = await window.supabase.from('invoices').select('id, number')
      .eq('booking_id', bookingId).eq('type', 'advance').eq('source', source || 'booking')
      .neq('status', 'cancelled').limit(1);
    if(existingZf.data && existingZf.data.length > 0){
      return {error: null, invoice_number: existingZf.data[0].number, existing: true};
    }
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
