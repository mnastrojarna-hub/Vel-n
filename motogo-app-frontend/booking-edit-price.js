// ===== BOOKING-EDIT-PRICE.JS – Price summary for edit reservation =====
// Split from original. See also: booking-edit-price-2.js (saveEditReservation)

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

  // V SOS re\u017eimu speci\u00e1ln\u00ed cenov\u00fd souhrn
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
  if(origEl) origEl.textContent = editOrigPrice.toLocaleString('cs-CZ') + ' K\u010d';

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
  if(extAmt) extAmt.textContent = '+' + extendPrice.toLocaleString('cs-CZ') + ' K\u010d';

  var shrRow = document.getElementById('edit-shorten-row');
  var shrAmt = document.getElementById('edit-refund-amt');
  var isShortening = rawRefundTotal > 0;
  if(shrRow) shrRow.style.display = isShortening ? 'flex' : 'none';
  if(shrAmt) shrAmt.textContent = '-' + refundAmt.toLocaleString('cs-CZ') + ' K\u010d';

  // Update the label to show storno percentage
  var h=_t('hc');
  var shrLabel = document.getElementById('t-editShortening');
  if(shrLabel && isShortening){
    shrLabel.textContent = h.shortenReturn.replace('{pct}',appliedStornoPct);
  }

  var shortenNote = document.getElementById('edit-shorten-note');
  if(shortenNote){
    if(isShortening){
      var activePct = appliedStornoPct >= 0 ? appliedStornoPct : 0;
      shortenNote.innerHTML = '\u26a0\ufe0f ' + h.stornoNote + '<br>\u27a4 ' + h.stornoApplied.replace('{pct}',activePct) +
        (activePct < 100 && rawRefundTotal > 0 ? h.stornoFrom.replace('{amt}',rawRefundTotal.toLocaleString('cs-CZ')) : '');
      shortenNote.style.display = 'block';
    } else {
      shortenNote.style.display = 'none';
    }
  }

  var retRow = document.getElementById('edit-return-fee-row');
  if(retRow) retRow.style.display = editReturnFee > 0 ? 'flex' : 'none';
  var retAmt = document.getElementById('edit-return-fee');
  if(retAmt) retAmt.textContent = '+' + editReturnFee.toLocaleString('cs-CZ') + ' K\u010d';

  var motoDiffRow = document.getElementById('edit-moto-diff-row');
  var motoDiffAmt = document.getElementById('edit-moto-diff-price');
  if(motoDiffRow) motoDiffRow.style.display = editMotoDiffPrice !== 0 ? 'flex' : 'none';
  if(motoDiffAmt){
    if(editMotoDiffPrice > 0){ motoDiffAmt.textContent = '+' + editMotoDiffPrice.toLocaleString('cs-CZ') + ' K\u010d'; motoDiffAmt.style.color = 'var(--red)'; }
    else if(editMotoDiffPrice < 0){ motoDiffAmt.textContent = editMotoDiffPrice.toLocaleString('cs-CZ') + ' K\u010d'; motoDiffAmt.style.color = 'var(--gd)'; }
    else { motoDiffAmt.textContent = '0 K\u010d'; }
  }

  var extrasRow = document.getElementById('edit-extras-fee-row');
  if(extrasRow) extrasRow.style.display = editExtrasTotal > 0 ? 'flex' : 'none';
  var extrasAmt = document.getElementById('edit-extras-fee');
  if(extrasAmt) extrasAmt.textContent = '+' + editExtrasTotal.toLocaleString('cs-CZ') + ' K\u010d';

  var diff = extendPrice - refundAmt + editReturnFee + editExtrasTotal + editMotoDiffPrice;
  var diffEl = document.getElementById('edit-diff-total');
  if(diffEl){
    if(diff > 0){ diffEl.textContent = '+' + diff.toLocaleString('cs-CZ') + ' K\u010d'; diffEl.style.color = 'var(--red)'; }
    else if(diff < 0){ diffEl.textContent = diff.toLocaleString('cs-CZ') + ' K\u010d'; diffEl.style.color = 'var(--gd)'; }
    else { diffEl.textContent = '0 K\u010d'; diffEl.style.color = 'var(--black)'; }
  }

  var saveBtn = document.getElementById('edit-save-btn');
  if(saveBtn){
    if(diff > 0) saveBtn.textContent = h.payAndContinue.replace('{amt}',diff.toLocaleString('cs-CZ'));
    else if(diff < 0) saveBtn.textContent = h.saveAndRefund.replace('{amt}',Math.abs(diff).toLocaleString('cs-CZ'));
    else saveBtn.textContent = h.saveChanges;
  }

  priceSum.style.display = (extendPrice > 0 || isShortening || editReturnFee > 0 || editExtrasTotal > 0 || editMotoDiffPrice !== 0) ? 'block' : 'none';
}
