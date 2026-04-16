// ===== BOOKING-EDIT-PRICE-2.JS – Save reservation logic & payment flow =====
// Split from booking-edit-price.js. All functions remain global.

async function saveEditReservation(){
  // SOS replacement flow
  if(typeof _sosReplacementMode !== 'undefined' && _sosReplacementMode){
    return _sosSaveReplacement();
  }

  var bookingId = window._editBookingId;
  var diff=0;
  var diffEl=document.getElementById('edit-diff-total');
  if(diffEl){
    var parsed=parseInt(diffEl.textContent.replace(/[^0-9-]/g,''));
    if(!isNaN(parsed))diff=parsed;
  }

  // Collect time and location (from hour:min selects)
  var pickupTime = getTimePickerValue('edit-pickup-time-hour','edit-pickup-time-min');
  var returnTime = getTimePickerValue('edit-return-time-hour','edit-return-time-min');
  var pickupAddr = document.getElementById('edit-pickup-address');
  var pickupLoc = (pickupAddr && pickupAddr.value.trim()) ? pickupAddr.value.trim() : null;
  // Collect return address
  var returnAddr = document.getElementById('edit-return-address');
  var returnLoc = (returnAddr && returnAddr.value.trim()) ? returnAddr.value.trim() : null;
  // Collect pickup/return method (store vs delivery)
  var pickupRadio = document.querySelector('input[name="edit-pickup"]:checked');
  var pickupMethod = pickupRadio ? (pickupRadio.value === 'other' ? 'delivery' : 'branch') : null;
  var returnRadio = document.querySelector('input[name="edit-return"]:checked');
  var returnMethod = returnRadio ? (returnRadio.value === 'other' ? 'delivery' : 'branch') : null;

  // Save to backend
  if(bookingId){
    // Use date-only ISO format (YYYY-MM-DD) to avoid timezone drift
    var _isoD=function(o){return o.y+'-'+String(o.m+1).padStart(2,'0')+'-'+String(o.d).padStart(2,'0');};
    var newEndISO = (typeof eDo !== 'undefined' && eDo) ? _isoD(eDo) : null;
    var newStartISO = (typeof eOd !== 'undefined' && eOd && !editIsActive) ? _isoD(eOd) : null;

    // Check for overlapping reservations with new dates
    var checkStart = newStartISO || (typeof origResStart !== 'undefined' ? new Date(origResStart.y, origResStart.m, origResStart.d).toISOString() : null);
    var checkEnd = newEndISO || (typeof origResEnd !== 'undefined' ? new Date(origResEnd.y, origResEnd.m, origResEnd.d).toISOString() : null);
    if(checkStart && checkEnd){
      // Check customer's own bookings date overlap
      if(typeof apiCheckBookingOverlap === 'function'){
        var oc = await apiCheckBookingOverlap(checkStart, checkEnd, bookingId);
        if(oc.overlap){
          var ocCf = oc.conflicting;
          var ocFrom = _fmtDatePayment ? _fmtDatePayment(ocCf.start_date) : ocCf.start_date;
          var ocTo = _fmtDatePayment ? _fmtDatePayment(ocCf.end_date) : ocCf.end_date;
          showT('\u26a0\ufe0f',_t('pay').overlapTitle||'Term\u00edn obsazen',
            (_t('pay').overlapMsg||'Ji\u017e m\u00e1te rezervaci v tomto term\u00ednu')+' ('+ocFrom+' \u2013 '+ocTo+'). '+(_t('pay').overlapHint||'Zvolte jin\u00fd term\u00edn nebo upravte st\u00e1vaj\u00edc\u00ed rezervaci.'));
          return;
        }
      }
      // Check motorcycle availability (other bookings for same moto)
      if(typeof apiCheckMotoAvailability === 'function'){
        var motoIdToCheck = null;
        if(editNewMotoId && typeof MOTOS !== 'undefined'){
          for(var _mi=0;_mi<MOTOS.length;_mi++){
            if(MOTOS[_mi].id === editNewMotoId){
              if(MOTOS[_mi]._db && MOTOS[_mi]._db.id) motoIdToCheck = MOTOS[_mi]._db.id;
              else {
                try { var _mr2=await supabase.from('motorcycles').select('id').or('model.eq.'+MOTOS[_mi].name).limit(1).single(); if(_mr2.data) motoIdToCheck=_mr2.data.id; } catch(e){}
              }
              break;
            }
          }
        }
        if(!motoIdToCheck) motoIdToCheck = window._editBookingMoto ? window._editBookingMoto.id : null;
        if(motoIdToCheck){
          var ma = await apiCheckMotoAvailability(motoIdToCheck, checkStart, checkEnd, bookingId);
          if(!ma.available){
            showT('\u26a0\ufe0f',_t('res').motoOccupied||'Motorka obsazena',_t('res').motoOccupiedMsg||'Motorka je v po\u017eadovan\u00e9m term\u00ednu ji\u017e rezervov\u00e1na. Zvolte jinou motorku nebo jin\u00fd term\u00edn.');
            return;
          }
        }
      }
    }
    var changes = {};
    if(newEndISO) changes.end_date = newEndISO;
    if(newStartISO) changes.start_date = newStartISO;
    if(pickupTime) changes.pickup_time = pickupTime;

    if(pickupLoc) changes.pickup_location = pickupLoc;
    if(pickupLoc) changes.pickup_address = pickupLoc;
    if(returnLoc) changes.return_address = returnLoc;
    if(pickupMethod) changes.pickup_method = pickupMethod;
    if(returnMethod) changes.return_method = returnMethod;
    // Always persist cumulative delivery_fee
    changes.delivery_fee = (editOrigDeliveryPaid || 0) + (editReturnFee || 0);
    // Handle moto change
    if(editNewMotoId){
      var newMotoDb = null;
      if(_isSupabaseReady() && typeof MOTOS !== 'undefined'){
        for(var mi=0;mi<MOTOS.length;mi++){
          if(MOTOS[mi].id === editNewMotoId){
            if(MOTOS[mi]._db && MOTOS[mi]._db.id){
              newMotoDb = { id: MOTOS[mi]._db.id };
            } else {
              try {
                var _mr=await supabase.from('motorcycles').select('id').or('model.eq.'+MOTOS[mi].name).limit(1).single();
                if(_mr.data) newMotoDb=_mr.data;
              } catch(e){}
            }
            break;
          }
        }
      }
      if(newMotoDb) changes.moto_id = newMotoDb.id;
    }

    // Detect if dates were actually shortened
    var isDateShortened = false;
    try {
      if(eDo && typeof origResEnd !== 'undefined' && origResEnd){
        var _newEndD = new Date(eDo.y, eDo.m, eDo.d);
        var _origEndD = new Date(origResEnd.y, origResEnd.m, origResEnd.d);
        if(_newEndD < _origEndD) isDateShortened = true;
      }
      if(eOd && typeof origResStart !== 'undefined' && origResStart && !editIsActive){
        var _newStartD = new Date(eOd.y, eOd.m, eOd.d);
        var _origStartD = new Date(origResStart.y, origResStart.m, origResStart.d);
        if(_newStartD > _origStartD) isDateShortened = true;
      }
    } catch(dce){ console.warn('[EDIT] date shortening detect err:', dce); }

    if(diff < 0 || (diff === 0 && isDateShortened)){
      if(typeof apiShortenBooking === 'function'){
        // Fetch OLD booking state BEFORE shortening (for itemized invoice)
        var editCtxShort = null;
        try {
          var _cols = typeof _MOTO_PRICE_COLS !== 'undefined' ? _MOTO_PRICE_COLS : 'model, spz, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, price_weekday, price_weekend';
          var _oldBs = await supabase.from('bookings').select('*, motorcycles('+_cols+')').eq('id', bookingId).single();
          if(_oldBs.data){
            var _obs = _oldBs.data, _oms = _oldBs.data.motorcycles || {};
            var _origZfs = await supabase.from('invoices').select('number')
              .eq('booking_id', bookingId).eq('type','advance').eq('source','booking')
              .order('created_at',{ascending:true}).limit(1);
            editCtxShort = {
              orig_start: _obs.start_date, orig_end: _obs.end_date,
              orig_moto: _oms, orig_total: _obs.total_price || 0,
              orig_extras: _obs.extras_price || 0, orig_delivery: _obs.delivery_fee || 0,
              orig_discount: _obs.discount_amount || 0,
              orig_zf_number: (_origZfs.data && _origZfs.data.length > 0) ? _origZfs.data[0].number : null
            };
          }
        } catch(ece){ console.warn('[EDIT] editCtx fetch err:', ece); }

        var res = await apiShortenBooking(bookingId, newEndISO, newStartISO);
        if(res.error){ showT('\u2717',_t('common').error,res.error); return; }
        // Also save time/location/return address
        var extraChanges = {};
        if(pickupTime) extraChanges.pickup_time = pickupTime;
        if(pickupLoc){ extraChanges.pickup_location = pickupLoc; extraChanges.pickup_address = pickupLoc; }
        if(returnLoc) extraChanges.return_address = returnLoc;
        if(pickupMethod) extraChanges.pickup_method = pickupMethod;
        if(returnMethod) extraChanges.return_method = returnMethod;
        extraChanges.delivery_fee = (editOrigDeliveryPaid || 0) + (editReturnFee || 0);
        if(Object.keys(extraChanges).length > 0){
          var ecRes = await apiModifyBooking(bookingId, extraChanges);
          if(ecRes && ecRes.error) console.warn('[EDIT] Extra changes err:', ecRes.error);
        }
        // Generate ZF + DP ONLY when there is actual money movement (diff != 0)
        // For free modifications (diff === 0), only regenerate contract + VOP
        if(diff !== 0){
          if(typeof apiGenerateAdvanceInvoice === 'function'){
            apiGenerateAdvanceInvoice(bookingId, diff, 'edit', editCtxShort).catch(function(e){ console.warn('[EDIT] ZF err:', e); });
          }
          if(typeof apiGeneratePaymentReceipt === 'function'){
            apiGeneratePaymentReceipt(bookingId, diff, 'edit', editCtxShort).catch(function(e){ console.warn('[EDIT] DP err:', e); });
          }
        }
        if(typeof apiAutoGenerateBookingDocs === 'function'){
          apiAutoGenerateBookingDocs(bookingId, true).catch(function(e){ console.warn('[EDIT] docs err:', e); });
        }
        // Send modification email
        _sendModifiedEmail(bookingId, diff);
      }
    } else if(diff > 0){
      // For extensions that require payment: calculate new price, but DON'T save yet.
      if(_isSupabaseReady()){
        try { var _rb=await supabase.from('bookings').select('total_price').eq('id',bookingId).single(); if(_rb.data) changes.total_price = (_rb.data.total_price || 0) + diff; } catch(e){}
      }
    } else {
      // diff == 0: no price change, save immediately
      if(typeof apiModifyBooking === 'function'){
        var saveRes = await apiModifyBooking(bookingId, changes);
        if(saveRes && saveRes.error){ showT('\u2717',_t('common').error,saveRes.error); return; }
      }
      // Regenerate contract + VOP with updated data
      if(typeof apiAutoGenerateBookingDocs === 'function'){
        apiAutoGenerateBookingDocs(bookingId, true).catch(function(e){ console.warn('[EDIT] docs err:', e); });
      }
      // Send modification email (no price change)
      _sendModifiedEmail(bookingId, 0);
    }
    if(typeof initMotoAvailability === 'function') initMotoAvailability();
  }

  // Invalidate cached bookings so the list/detail reload fresh data
  if(typeof _cachedBookings !== 'undefined') _cachedBookings = null;

  // Show inline confirmation
  var confirmBanner=document.getElementById('edit-confirm-banner');
  if(!confirmBanner){
    var saveBtnEl=document.getElementById('edit-save-btn');
    if(saveBtnEl){
      confirmBanner=document.createElement('div');
      confirmBanner.id='edit-confirm-banner';
      confirmBanner.style.cssText='background:var(--gp);border:2px solid var(--green);border-radius:var(--rsm);padding:12px 14px;margin-bottom:12px;text-align:center;font-size:13px;font-weight:700;color:var(--gd);';
      saveBtnEl.parentNode.insertBefore(confirmBanner,saveBtnEl);
    }
  }
  if(isDateShortened && diff <= 0){
    if(diff < 0 && confirmBanner){
      confirmBanner.innerHTML='\u2713 '+_t('res').dateConfirmed+' \u00b7 '+_t('res').refundToCard.replace('{amt}',Math.abs(diff).toLocaleString('cs-CZ'));
    } else if(confirmBanner){
      confirmBanner.innerHTML='\u2713 '+(_t('res').dateConfirmed||'Term\u00edn upraven')+' \u00b7 '+(_t('res').shortenNoRefund||'Zkr\u00e1ceno dle storno podm\u00ednek (bez vr\u00e1cen\u00ed)');
    }
    if(confirmBanner){ setTimeout(function(){histBack();},1500); } else {histBack();}
  } else if(diff>0){
    _currentBookingId = bookingId;
    _currentPaymentAmount = diff;
    _isEditPayment = true;
    _editPaymentBookingId = bookingId;
    _paymentAttempts = 0;

    goTo('s-payment');
    if(typeof _showSavedCardPreview === 'function') _showSavedCardPreview();
    setTimeout(function(){
      var payBtn=document.getElementById('pay-btn');
      if(payBtn){
        payBtn.textContent='Zaplatit '+diff.toLocaleString('cs-CZ')+' K\u010d \u2192';
        payBtn.onclick = function(){ doEditPayment(bookingId, diff, changes); };
      }
      var appleBtn=document.getElementById('apple-pay-btn');
      if(appleBtn)appleBtn.textContent='\ud83c\udf4e Pay '+diff.toLocaleString('cs-CZ')+' K\u010d';
    },50);
  } else if(diff<0){
    if(confirmBanner){
      confirmBanner.innerHTML='\u2713 '+_t('res').dateConfirmed+' \u00b7 '+_t('res').refundToCard.replace('{amt}',Math.abs(diff).toLocaleString('cs-CZ'));
      setTimeout(function(){histBack();},1500);
    } else {histBack();}
  } else {
    if(confirmBanner){
      confirmBanner.innerHTML='\u2713 '+_t('res').dateConfirmed+' \u00b7 '+_t('res').changesSavedShort;
      setTimeout(function(){histBack();},1500);
    } else {histBack();}
  }
}

// Send booking_modified email after app-side edit
async function _sendModifiedEmail(bookingId, priceDiff){
  if(!_isSupabaseReady()) return;
  try {
    var b = await supabase.from('bookings')
      .select('start_date, end_date, total_price, booking_source, profiles(full_name, email), motorcycles(model)')
      .eq('id', bookingId).single();
    if(!b.data || !b.data.profiles || !b.data.profiles.email) return;
    var p = b.data.profiles, m = b.data.motorcycles;
    await supabase.functions.invoke('send-booking-email', {
      body: {
        type: 'booking_modified', booking_id: bookingId,
        customer_email: p.email, customer_name: p.full_name || '',
        motorcycle: (m && m.model) || '',
        start_date: b.data.start_date, end_date: b.data.end_date,
        total_price: b.data.total_price,
        price_difference: priceDiff || 0,
        source: b.data.booking_source || 'app'
      }
    });
  } catch(e){ console.warn('[EDIT] email err:', e); }
}
