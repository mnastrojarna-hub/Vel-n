// ===== BOOKING-EDIT-PRICE.JS – Price summary, save reservation, payment flow =====
// Split from original booking-edit.js. See also: booking-edit.js, booking-edit-sos.js

function setEditDateFromInput(type, val){
  if(!val) return;
  var parts = val.split('-');
  var y = parseInt(parts[0]), m = parseInt(parts[1])-1, d = parseInt(parts[2]);

  if(type === 'od'){
    eOd = {d:d, y:y, m:m};
    var odTxt = document.getElementById('edit-od-txt');
    if(odTxt) odTxt.textContent = d+'.'+(m+1)+'.'+y;
  } else {
    eDo = {d:d, y:y, m:m};
    var doTxt = document.getElementById('edit-do-txt');
    if(doTxt) doTxt.textContent = d+'.'+(m+1)+'.'+y;
  }
  calState.e.y = y; calState.e.m = m;
  if(typeof buildECal === 'function') buildECal();
  updateEditPriceSummary();
}

async function updateEditPriceSummary(){
  var priceSum = document.getElementById('edit-price-summary');
  if(!priceSum) return;

  // V SOS režimu speciální cenový souhrn
  if(typeof _sosReplacementMode !== 'undefined' && _sosReplacementMode){
    _sosUpdateEditPrice();
    return;
  }

  var booking = null;
  if(window._editBookingId){
    if(_isSupabaseReady()){
      try { var _r=await supabase.from('bookings').select('*').eq('id',window._editBookingId).single(); booking=_r.data; } catch(e){}
    }
  }
  if(!booking){ priceSum.style.display='none'; return; }

  editOrigPrice = booking.total_price || 0;
  editOrigDeliveryPaid = booking.delivery_fee || 0;

  var origEl = document.getElementById('edit-orig-price');
  if(origEl) origEl.textContent = editOrigPrice.toLocaleString('cs-CZ') + ' Kč';

  var extendPrice = 0, refundAmt = 0, rawRefundTotal = 0, appliedStornoPct = -1;

  if(eOd && eDo){
    var moto = window._editBookingMoto;
    var pricePerDay = moto ? (moto.daily_price || 2600) : 2600;
    // Parse date strings into LOCAL midnight (avoid UTC vs local timezone mismatch)
    var _ps = booking.start_date.substring(0,10).split('-');
    var origStart = new Date(parseInt(_ps[0]), parseInt(_ps[1])-1, parseInt(_ps[2]));
    var _pe = booking.end_date.substring(0,10).split('-');
    var origEnd = new Date(parseInt(_pe[0]), parseInt(_pe[1])-1, parseInt(_pe[2]));
    var newStart = new Date(eOd.y, eOd.m, eOd.d);
    var newEnd = new Date(eDo.y, eDo.m, eDo.d);

    if(newEnd > origEnd){
      var d = new Date(origEnd); d.setDate(d.getDate()+1);
      while(d <= newEnd){ extendPrice += pricePerDay; d.setDate(d.getDate()+1); }
    }
    if(newStart < origStart){
      var d2 = new Date(newStart);
      while(d2 < origStart){ extendPrice += pricePerDay; d2.setDate(d2.getDate()+1); }
    }
    if(newEnd < origEnd){
      var rawRefund = 0;
      var d3 = new Date(newEnd); d3.setDate(d3.getDate()+1);
      while(d3 <= origEnd){ rawRefund += pricePerDay; d3.setDate(d3.getDate()+1); }
      rawRefundTotal += rawRefund;
      // Apply storno conditions: based on hours until the first removed day
      var firstRemovedDay = new Date(newEnd); firstRemovedDay.setDate(firstRemovedDay.getDate()+1);
      var hoursUntil = (firstRemovedDay.getTime() - Date.now()) / (1000*60*60);
      var stornoPct = 0;
      if(hoursUntil > 7*24) stornoPct = 100;
      else if(hoursUntil > 48) stornoPct = 50;
      appliedStornoPct = stornoPct;
      refundAmt += Math.round(rawRefund * stornoPct / 100);
    }
    if(newStart > origStart && !editIsActive){
      var rawRefundStart = 0;
      var d4 = new Date(origStart);
      while(d4 < newStart){ rawRefundStart += pricePerDay; d4.setDate(d4.getDate()+1); }
      rawRefundTotal += rawRefundStart;
      // Apply storno conditions for start-side shortening
      var hoursUntilStart = (newStart.getTime() - Date.now()) / (1000*60*60);
      var stornoPctStart = 0;
      if(hoursUntilStart > 7*24) stornoPctStart = 100;
      else if(hoursUntilStart > 48) stornoPctStart = 50;
      appliedStornoPct = stornoPctStart;
      refundAmt += Math.round(rawRefundStart * stornoPctStart / 100);
    }
  }

  var extRow = document.getElementById('edit-extend-row');
  var extAmt = document.getElementById('edit-extend-price');
  if(extRow) extRow.style.display = extendPrice > 0 ? 'flex' : 'none';
  if(extAmt) extAmt.textContent = '+' + extendPrice.toLocaleString('cs-CZ') + ' Kč';

  var shrRow = document.getElementById('edit-shorten-row');
  var shrAmt = document.getElementById('edit-refund-amt');
  var isShortening = rawRefundTotal > 0;
  if(shrRow) shrRow.style.display = isShortening ? 'flex' : 'none';
  if(shrAmt) shrAmt.textContent = '-' + refundAmt.toLocaleString('cs-CZ') + ' Kč';

  // Update the label to show storno percentage
  var shrLabel = document.getElementById('t-editShortening');
  if(shrLabel && isShortening){
    shrLabel.textContent = 'Zkrácení (vrácení ' + appliedStornoPct + ' %)';
  }

  var shortenNote = document.getElementById('edit-shorten-note');
  if(shortenNote){
    if(isShortening){
      var activePct = appliedStornoPct >= 0 ? appliedStornoPct : 0;
      shortenNote.innerHTML = '⚠️ Storno podmínky: <strong>7+ dní = 100 %</strong> · <strong>2–7 dní = 50 %</strong> · <strong>méně než 2 dny = bez vrácení</strong>.' +
        '<br>➤ Aktuálně platí: <strong>' + activePct + ' % vrácení</strong>' +
        (activePct < 100 && rawRefundTotal > 0 ? ' (z ' + rawRefundTotal.toLocaleString('cs-CZ') + ' Kč)' : '');
      shortenNote.style.display = 'block';
    } else {
      shortenNote.style.display = 'none';
    }
  }

  var retRow = document.getElementById('edit-return-fee-row');
  if(retRow) retRow.style.display = editReturnFee > 0 ? 'flex' : 'none';
  var retAmt = document.getElementById('edit-return-fee');
  if(retAmt) retAmt.textContent = '+' + editReturnFee.toLocaleString('cs-CZ') + ' Kč';

  var motoDiffRow = document.getElementById('edit-moto-diff-row');
  var motoDiffAmt = document.getElementById('edit-moto-diff-price');
  if(motoDiffRow) motoDiffRow.style.display = editMotoDiffPrice !== 0 ? 'flex' : 'none';
  if(motoDiffAmt){
    if(editMotoDiffPrice > 0){ motoDiffAmt.textContent = '+' + editMotoDiffPrice.toLocaleString('cs-CZ') + ' Kč'; motoDiffAmt.style.color = 'var(--red)'; }
    else if(editMotoDiffPrice < 0){ motoDiffAmt.textContent = editMotoDiffPrice.toLocaleString('cs-CZ') + ' Kč'; motoDiffAmt.style.color = 'var(--gd)'; }
    else { motoDiffAmt.textContent = '0 Kč'; }
  }

  var extrasRow = document.getElementById('edit-extras-fee-row');
  if(extrasRow) extrasRow.style.display = editExtrasTotal > 0 ? 'flex' : 'none';
  var extrasAmt = document.getElementById('edit-extras-fee');
  if(extrasAmt) extrasAmt.textContent = '+' + editExtrasTotal.toLocaleString('cs-CZ') + ' Kč';

  var diff = extendPrice - refundAmt + editReturnFee + editExtrasTotal + editMotoDiffPrice;
  var diffEl = document.getElementById('edit-diff-total');
  if(diffEl){
    if(diff > 0){ diffEl.textContent = '+' + diff.toLocaleString('cs-CZ') + ' Kč'; diffEl.style.color = 'var(--red)'; }
    else if(diff < 0){ diffEl.textContent = diff.toLocaleString('cs-CZ') + ' Kč'; diffEl.style.color = 'var(--gd)'; }
    else { diffEl.textContent = '0 Kč'; diffEl.style.color = 'var(--black)'; }
  }

  var saveBtn = document.getElementById('edit-save-btn');
  if(saveBtn){
    if(diff > 0) saveBtn.textContent = 'Pokračovat k platbě (+' + diff.toLocaleString('cs-CZ') + ' Kč) →';
    else if(diff < 0) saveBtn.textContent = 'Uložit a vrátit ' + Math.abs(diff).toLocaleString('cs-CZ') + ' Kč →';
    else saveBtn.textContent = 'Uložit změny →';
  }

  priceSum.style.display = (extendPrice > 0 || isShortening || editReturnFee > 0 || editExtrasTotal > 0 || editMotoDiffPrice !== 0) ? 'block' : 'none';
}

async function saveEditReservation(){
  // SOS replacement flow — přesměrovat na SOS potvrzení
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
      // Check customer's own bookings date overlap (new dates must not clash with another reservation)
      if(typeof apiCheckBookingOverlap === 'function'){
        var oc = await apiCheckBookingOverlap(checkStart, checkEnd, bookingId);
        if(oc.overlap){
          var ocCf = oc.conflicting;
          var ocFrom = _fmtDatePayment ? _fmtDatePayment(ocCf.start_date) : ocCf.start_date;
          var ocTo = _fmtDatePayment ? _fmtDatePayment(ocCf.end_date) : ocCf.end_date;
          showT('⚠️',_t('pay').overlapTitle||'Termín obsazen',
            (_t('pay').overlapMsg||'Již máte rezervaci v tomto termínu')+' ('+ocFrom+' – '+ocTo+'). '+(_t('pay').overlapHint||'Zvolte jiný termín nebo upravte stávající rezervaci.'));
          return;
        }
      }
      // Check motorcycle availability (other bookings for same moto)
      if(typeof apiCheckMotoAvailability === 'function'){
        // If user changed the moto, check the NEW moto; otherwise check the original
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
            showT('⚠️',_t('res').motoOccupied||'Motorka obsazena',_t('res').motoOccupiedMsg||'Motorka je v požadovaném termínu již rezervována. Zvolte jinou motorku nebo jiný termín.');
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
    // Always persist cumulative delivery_fee so next edit knows what was already paid
    changes.delivery_fee = (editOrigDeliveryPaid || 0) + (editReturnFee || 0);
    // Handle moto change
    if(editNewMotoId){
      var newMotoDb = null;
      if(_isSupabaseReady() && typeof MOTOS !== 'undefined'){
        for(var mi=0;mi<MOTOS.length;mi++){
          if(MOTOS[mi].id === editNewMotoId){
            // Použij _db.id z enrichMOTOS místo dalšího Supabase dotazu
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

    // Detect if dates were actually shortened (even if diff=0 due to storno conditions)
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
        if(res.error){ showT('✗',_t('common').error,res.error); return; }
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
        // Generate ZF + DP with itemized breakdown (original vs new) + contract + VOP
        if(typeof apiGenerateAdvanceInvoice === 'function'){
          apiGenerateAdvanceInvoice(bookingId, diff, 'edit', editCtxShort).catch(function(e){ console.warn('[EDIT] ZF err:', e); });
        }
        if(typeof apiGeneratePaymentReceipt === 'function'){
          apiGeneratePaymentReceipt(bookingId, diff, 'edit', editCtxShort).catch(function(e){ console.warn('[EDIT] DP err:', e); });
        }
        if(typeof apiAutoGenerateBookingDocs === 'function'){
          apiAutoGenerateBookingDocs(bookingId, true).catch(function(e){ console.warn('[EDIT] docs err:', e); });
        }
      }
    } else if(diff > 0){
      // For extensions that require payment: calculate new price, but DON'T save yet.
      // Changes will be saved AFTER successful payment in doEditPayment.
      if(_isSupabaseReady()){
        try { var _rb=await supabase.from('bookings').select('total_price').eq('id',bookingId).single(); if(_rb.data) changes.total_price = (_rb.data.total_price || 0) + diff; } catch(e){}
      }
    } else {
      // diff == 0: no price change, save immediately
      if(typeof apiModifyBooking === 'function'){
        var saveRes = await apiModifyBooking(bookingId, changes);
        if(saveRes && saveRes.error){ showT('✗',_t('common').error,saveRes.error); return; }
      }
      // Regenerate contract + VOP with updated data (new dates/location/moto)
      if(typeof apiAutoGenerateBookingDocs === 'function'){
        apiAutoGenerateBookingDocs(bookingId, true).catch(function(e){ console.warn('[EDIT] docs err:', e); });
      }
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
    // Shortening with storno conditions — show appropriate message
    if(diff < 0 && confirmBanner){
      confirmBanner.innerHTML='✓ '+_t('res').dateConfirmed+' · '+_t('res').refundToCard.replace('{amt}',Math.abs(diff).toLocaleString('cs-CZ'));
    } else if(confirmBanner){
      confirmBanner.innerHTML='✓ '+(_t('res').dateConfirmed||'Termín upraven')+' · '+(_t('res').shortenNoRefund||'Zkráceno dle storno podmínek (bez vrácení)');
    }
    if(confirmBanner){ setTimeout(function(){histBack();},1500); } else {histBack();}
  } else if(diff>0){
    // Set up proper payment flow for edit (banner not needed — payment screen shows amount)
    _currentBookingId = bookingId;
    _currentPaymentAmount = diff;
    _isEditPayment = true;
    _editPaymentBookingId = bookingId;
    _paymentAttempts = 0;

    goTo('s-payment');
    setTimeout(function(){
      var payBtn=document.getElementById('pay-btn');
      if(payBtn){
        payBtn.textContent='Zaplatit '+diff.toLocaleString('cs-CZ')+' Kč →';
        payBtn.onclick = function(){ doEditPayment(bookingId, diff, changes); };
      }
      var appleBtn=document.getElementById('apple-pay-btn');
      if(appleBtn)appleBtn.textContent='🍎 Pay '+diff.toLocaleString('cs-CZ')+' Kč';
    },50);
  } else if(diff<0){
    if(confirmBanner){
      confirmBanner.innerHTML='✓ '+_t('res').dateConfirmed+' · '+_t('res').refundToCard.replace('{amt}',Math.abs(diff).toLocaleString('cs-CZ'));
      setTimeout(function(){histBack();},1500);
    } else {histBack();}
  } else {
    if(confirmBanner){
      confirmBanner.innerHTML='✓ '+_t('res').dateConfirmed+' · '+_t('res').changesSavedShort;
      setTimeout(function(){histBack();},1500);
    } else {histBack();}
  }
}
