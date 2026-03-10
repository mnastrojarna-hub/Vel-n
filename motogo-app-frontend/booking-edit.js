// ===== BOOKING-EDIT.JS – Edit price summary, payment, dynamic dates =====

// ===== REUSABLE TIME PICKER (hour + minute selects, 0-23h) =====
function buildTimePickerHTML(hourId, minId, defaultH, defaultM){
  defaultH = defaultH || 9; defaultM = defaultM || 0;
  var hOpts = '';
  for(var h=0;h<24;h++){
    var sel = h===defaultH ? ' selected' : '';
    hOpts += '<option value="'+h+'"'+sel+'>'+h+'</option>';
  }
  var mOpts = '';
  for(var m=0;m<60;m+=5){
    var mv = m<10?'0'+m:''+m;
    var sel2 = m===defaultM ? ' selected' : '';
    mOpts += '<option value="'+mv+'"'+sel2+'>'+mv+'</option>';
  }
  return '<div style="display:flex;align-items:center;gap:6px;">' +
    '<select id="'+hourId+'" style="flex:1;border:2px solid var(--green);border-radius:10px;padding:11px 8px;font-size:15px;font-weight:800;font-family:var(--font);color:var(--gd);background:var(--gp);outline:none;text-align:center;-webkit-appearance:none;appearance:none;">' + hOpts + '</select>' +
    '<span style="font-size:18px;font-weight:900;color:var(--gd);">:</span>' +
    '<select id="'+minId+'" style="flex:1;border:2px solid var(--green);border-radius:10px;padding:11px 8px;font-size:15px;font-weight:800;font-family:var(--font);color:var(--gd);background:var(--gp);outline:none;text-align:center;-webkit-appearance:none;appearance:none;">' + mOpts + '</select>' +
    '<span style="font-size:12px;font-weight:600;color:var(--g400);margin-left:4px;">hod</span></div>';
}
function getTimePickerValue(hourId, minId){
  var h = document.getElementById(hourId);
  var m = document.getElementById(minId);
  if(!h||!m) return '09:00';
  return h.value + ':' + m.value;
}
function initTimePickers(){
  var pickers = [
    {id:'booking-time-grid', hId:'booking-time-hour', mId:'booking-time-min', dH:9, dM:0},
    {id:'return-time-picker', hId:'return-time-hour', mId:'return-time-min', dH:9, dM:0},
    {id:'edit-pickup-time-picker', hId:'edit-pickup-time-hour', mId:'edit-pickup-time-min', dH:9, dM:0},
    {id:'edit-return-time-picker', hId:'edit-return-time-hour', mId:'edit-return-time-min', dH:9, dM:0}
  ];
  pickers.forEach(function(p){
    var el = document.getElementById(p.id);
    if(el) el.innerHTML = buildTimePickerHTML(p.hId, p.mId, p.dH, p.dM);
  });
}

// Globální stav pro edit
var editExtrasTotal = 0;
var editReturnFee = 0;
var editOrigPrice = 0;
var editOrigDeliveryPaid = 0;
var editMotoDiffPrice = 0;
var editNewMotoId = null;

function setEditReturn(mode){
  var detail = document.getElementById('edit-return-detail');
  var storeLabel = document.getElementById('edit-return-store-label');
  var delivLabel = document.getElementById('edit-return-delivery-label');
  if(mode === 'other'){
    if(detail) detail.style.display = 'block';
    if(storeLabel){ storeLabel.style.background='var(--g100)'; storeLabel.style.borderColor='var(--g200)'; }
    if(delivLabel){ delivLabel.style.background='var(--gp)'; delivLabel.style.borderColor='var(--green)'; }
  } else {
    if(detail) detail.style.display = 'none';
    if(storeLabel){ storeLabel.style.background='var(--gp)'; storeLabel.style.borderColor='var(--green)'; }
    if(delivLabel){ delivLabel.style.background='var(--g100)'; delivLabel.style.borderColor='var(--g200)'; }
    editReturnFee = 0;
  }
  updateEditPriceSummary();
}

function setEditPickup(mode){
  var detail = document.getElementById('edit-pickup-detail');
  var storeLabel = document.getElementById('edit-pickup-store-label');
  var delivLabel = document.getElementById('edit-pickup-delivery-label');
  if(mode === 'other'){
    if(detail) detail.style.display = 'block';
    if(storeLabel){ storeLabel.style.background='var(--g100)'; storeLabel.style.borderColor='var(--g200)'; }
    if(delivLabel){ delivLabel.style.background='var(--gp)'; delivLabel.style.borderColor='var(--green)'; }
  } else {
    if(detail) detail.style.display = 'none';
    if(storeLabel){ storeLabel.style.background='var(--gp)'; storeLabel.style.borderColor='var(--green)'; }
    if(delivLabel){ delivLabel.style.background='var(--g100)'; delivLabel.style.borderColor='var(--g200)'; }
  }
}

function calcEditDelivery(){
  var addr = document.getElementById('edit-return-address');
  var calc = document.getElementById('edit-return-calc');
  var kmTxt = document.getElementById('edit-return-km-txt');
  if(!addr || !addr.value.trim()){ if(calc) calc.style.display='none'; editReturnFee=0; updateEditPriceSummary(); return; }

  // Use OSRM API if available
  if(typeof AddressAPI !== 'undefined'){
    var coords = (addr.dataset.lat && addr.dataset.lng)
      ? {lat: parseFloat(addr.dataset.lat), lng: parseFloat(addr.dataset.lng)}
      : addr.value.trim();
    if(kmTxt) kmTxt.textContent = 'Vypočítávám vzdálenost...';
    if(calc) calc.style.display = 'block';
    AddressAPI.calcDistance(coords, function(result){
      if(!result){ _calcEditDelivFallback(addr, calc, kmTxt); return; }
      var fee = result.fee;
      var diff = Math.max(0, fee - editOrigDeliveryPaid);
      editReturnFee = diff;
      var txt = '~' + result.km + ' km · ' + fee.toLocaleString('cs-CZ') + ' Kč';
      if(result.duration) txt += ' (~' + result.duration + ' min)';
      if(editOrigDeliveryPaid > 0) txt += ' (zaplaceno ' + editOrigDeliveryPaid.toLocaleString('cs-CZ') + ' Kč, doplatek ' + diff.toLocaleString('cs-CZ') + ' Kč)';
      if(kmTxt) kmTxt.textContent = txt;
      updateEditPriceSummary();
    });
    return;
  }

  _calcEditDelivFallback(addr, calc, kmTxt);
}

function _calcEditDelivFallback(addr, calc, kmTxt){
  var km = 50;
  var val = addr.value.toLowerCase();
  if(typeof KM_ESTIMATES!=='undefined'){
    for(var c in KM_ESTIMATES){ if(val.indexOf(c.toLowerCase()) !== -1){ km = KM_ESTIMATES[c]; break; } }
  } else {
    var KM_EST = {praha:160,brno:60,jihlava:40,tabor:35,ceske:90,plzen:200,ostrava:280};
    for(var c2 in KM_EST){ if(val.indexOf(c2) !== -1){ km = KM_EST[c2]; break; } }
  }
  var fee = 1000 + km * 20;
  var diff = Math.max(0, fee - editOrigDeliveryPaid);
  editReturnFee = diff;
  if(calc) calc.style.display='block';
  if(kmTxt) kmTxt.textContent = '~' + km + ' km · ' + fee.toLocaleString('cs-CZ') + ' Kč' +
    (editOrigDeliveryPaid > 0 ? ' (zaplaceno ' + editOrigDeliveryPaid.toLocaleString('cs-CZ') + ' Kč, doplatek ' + diff.toLocaleString('cs-CZ') + ' Kč)' : '') + ' (odhad)';
  updateEditPriceSummary();
}

function toggleEditExtra(label, price){
  var cb = label.querySelector('input[type=checkbox]');
  if(cb.checked){
    label.style.borderColor = 'var(--green)';
    label.style.background = 'var(--gp)';
    editExtrasTotal += price;
  } else {
    label.style.borderColor = 'var(--g200)';
    label.style.background = 'var(--g100)';
    editExtrasTotal -= price;
  }
  updateEditPriceSummary();
}

// ===== ZMĚNA POBOČKY =====
function setEditBranch(branch){
  // Currently only Mezná is active – placeholder for future branches
  if(branch !== 'mezna'){
    showT('ℹ️','Pobočka','Zatím je k dispozici pouze pobočka Mezná');
  }
}

// ===== ZMĚNA MOTORKY =====
async function populateEditMotoList(){
  var listEl = document.getElementById('edit-moto-list');
  var currentNameEl = document.getElementById('edit-moto-current-name');
  var currentPriceEl = document.getElementById('edit-moto-current-price');
  if(!listEl) return;

  var booking = null;
  if(window._editBookingId){
    if(_isSupabaseReady()){
      try { var _r=await supabase.from('bookings').select('*').eq('id',window._editBookingId).single(); booking=_r.data; } catch(e){}
    }
  }
  if(!booking) return;
  var currentMoto = null;
  if(_isSupabaseReady()){
    try { var _mr=await supabase.from('motorcycles').select('*').eq('id',booking.moto_id).single(); currentMoto=_mr.data; } catch(e){}
  }
  var currentMotoKey = currentMoto ? (currentMoto.motoKey || currentMoto.model) : null;

  // Show current moto info
  if(currentNameEl) currentNameEl.textContent = currentMoto ? currentMoto.model : '—';
  if(currentPriceEl && currentMoto){
    var cpd = _getMotoAvgDailyPrice(currentMotoKey);
    currentPriceEl.textContent = cpd ? ('~' + cpd.toLocaleString('cs-CZ') + ' Kč/den') : '';
  }

  // Build list from MOTOS catalogue
  if(typeof MOTOS === 'undefined') return;
  var html = '';
  for(var i = 0; i < MOTOS.length; i++){
    var m = MOTOS[i];
    if(!m.avail) continue;
    var isCurrent = (m.id === currentMotoKey || m.name === (currentMoto ? currentMoto.model : ''));
    var avgPrice = _getMotoAvgDailyPrice(m.id);
    var selected = (editNewMotoId === m.id);
    // Current moto is clickable when another moto is selected (to allow deselection)
    var isCurrentLocked = isCurrent && !editNewMotoId;
    var isCurrentActive = isCurrent && !editNewMotoId;
    var border = selected ? 'var(--green)' : isCurrentActive ? 'var(--green)' : isCurrent ? 'var(--g300)' : 'var(--g200)';
    var bg = selected ? 'var(--gp)' : isCurrentActive ? 'var(--gp)' : isCurrent ? '#fff' : '#fff';
    html += '<div style="display:flex;align-items:center;gap:9px;padding:9px 11px;background:'+bg+';border-radius:var(--rsm);border:2px solid '+border+';cursor:'+(isCurrentLocked?'default':'pointer')+';'+(isCurrentLocked?'opacity:.6;':'')+'" '+
      (isCurrentLocked ? '' : 'onclick="selectEditMoto(\''+m.id+'\')"') + '>' +
      '<img src="'+(m.img||'')+'" style="width:48px;height:36px;object-fit:cover;border-radius:6px;" onerror="this.style.display=\'none\'">' +
      '<div style="flex:1;"><div style="font-size:12px;font-weight:700;">'+m.name+'</div>' +
      '<div style="font-size:11px;color:var(--g400);">'+m.rp+' · '+(avgPrice?avgPrice.toLocaleString('cs-CZ')+' Kč/den':'')+'</div></div>' +
      (isCurrentActive ? '<div style="font-size:10px;font-weight:700;color:var(--gd);">✓ AKTUÁLNÍ</div>' : '') +
      (isCurrent && editNewMotoId ? '<div style="font-size:10px;font-weight:700;color:var(--g400);">AKTUÁLNÍ</div>' : '') +
      (selected ? '<div style="font-size:10px;font-weight:700;color:var(--gd);">✓ VYBRÁNO</div>' : '') +
      '</div>';
  }
  listEl.innerHTML = html;
}

function _getMotoAvgDailyPrice(motoKey){
  if(typeof MOTOS === 'undefined') return 0;
  for(var i = 0; i < MOTOS.length; i++){
    if(MOTOS[i].id === motoKey && MOTOS[i].pricing){
      var p = MOTOS[i].pricing;
      return Math.round((p.po+p.ut+p.st+p.ct+p.pa+p.so+p.ne)/7);
    }
  }
  return 0;
}

function _calcMotoPriceForBooking(motoKey, startDate, endDate){
  if(typeof MOTOS === 'undefined') return 0;
  var pricing = null;
  for(var i = 0; i < MOTOS.length; i++){
    if(MOTOS[i].id === motoKey){ pricing = MOTOS[i].pricing; break; }
  }
  if(!pricing) return 0;
  var dayNames = ['ne','po','ut','st','ct','pa','so'];
  var total = 0;
  var d = new Date(startDate); d.setHours(0,0,0,0);
  var end = new Date(endDate); end.setHours(0,0,0,0);
  while(d <= end){
    var dn = dayNames[d.getDay()];
    total += (pricing[dn] || 0);
    d.setDate(d.getDate() + 1);
  }
  return total;
}

async function selectEditMoto(motoKey){
  var booking = null;
  if(window._editBookingId){
    if(_isSupabaseReady()){
      try { var _r=await supabase.from('bookings').select('*').eq('id',window._editBookingId).single(); booking=_r.data; } catch(e){}
    }
  }
  if(!booking) return;
  var currentMoto = null;
  if(_isSupabaseReady()){
    try { var _mr=await supabase.from('motorcycles').select('*').eq('id',booking.moto_id).single(); currentMoto=_mr.data; } catch(e){}
  }
  var currentKey = currentMoto ? (currentMoto.motoKey || currentMoto.model) : null;

  if(motoKey === currentKey){
    editNewMotoId = null;
    editMotoDiffPrice = 0;
  } else {
    editNewMotoId = motoKey;
    // Calculate price difference for the booking period
    var origPrice = _calcMotoPriceForBooking(currentKey, booking.start_date, booking.end_date);
    var newPrice = _calcMotoPriceForBooking(motoKey, booking.start_date, booking.end_date);
    editMotoDiffPrice = newPrice - origPrice;
  }

  // Update diff display
  var diffEl = document.getElementById('edit-moto-diff');
  if(diffEl){
    if(editNewMotoId){
      diffEl.style.display = 'block';
      if(editMotoDiffPrice > 0){
        diffEl.innerHTML = '💰 '+_t('res').priceDiffPay+': <strong>+' + editMotoDiffPrice.toLocaleString('cs-CZ') + ' Kč</strong>';
        diffEl.style.borderColor = '#fbbf24'; diffEl.style.background = '#fffbeb'; diffEl.style.color = '#92400e';
      } else if(editMotoDiffPrice < 0){
        diffEl.innerHTML = '💰 '+_t('res').priceDiffRefund+': <strong>' + editMotoDiffPrice.toLocaleString('cs-CZ') + ' Kč</strong>';
        diffEl.style.borderColor = 'var(--green)'; diffEl.style.background = 'var(--gp)'; diffEl.style.color = 'var(--gd)';
      } else {
        diffEl.innerHTML = '💰 '+_t('res').priceDiffNone;
        diffEl.style.borderColor = 'var(--g200)'; diffEl.style.background = 'var(--g100)'; diffEl.style.color = 'var(--g600)';
      }
    } else {
      diffEl.style.display = 'none';
    }
  }

  populateEditMotoList();
  updateEditPriceSummary();
}

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
  editOrigDeliveryPaid = booking.return_fee || booking.delivery_price || 0;

  var origEl = document.getElementById('edit-orig-price');
  if(origEl) origEl.textContent = editOrigPrice.toLocaleString('cs-CZ') + ' Kč';

  var extendPrice = 0, refundAmt = 0;

  if(eOd && eDo){
    var moto = window._editBookingMoto;
    var pricePerDay = moto ? (moto.daily_price || 2600) : 2600;
    var origStart = new Date(booking.start_date);
    var origEnd = new Date(booking.end_date);
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
      var d3 = new Date(newEnd); d3.setDate(d3.getDate()+1);
      while(d3 <= origEnd){ refundAmt += pricePerDay; d3.setDate(d3.getDate()+1); }
    }
    if(newStart > origStart && !editIsActive){
      var d4 = new Date(origStart);
      while(d4 < newStart){ refundAmt += pricePerDay; d4.setDate(d4.getDate()+1); }
    }
  }

  var extRow = document.getElementById('edit-extend-row');
  var extAmt = document.getElementById('edit-extend-price');
  if(extRow) extRow.style.display = extendPrice > 0 ? 'flex' : 'none';
  if(extAmt) extAmt.textContent = '+' + extendPrice.toLocaleString('cs-CZ') + ' Kč';

  var shrRow = document.getElementById('edit-shorten-row');
  var shrAmt = document.getElementById('edit-refund-amt');
  if(shrRow) shrRow.style.display = refundAmt > 0 ? 'flex' : 'none';
  if(shrAmt) shrAmt.textContent = '-' + refundAmt.toLocaleString('cs-CZ') + ' Kč';

  var shortenNote = document.getElementById('edit-shorten-note');
  if(shortenNote) shortenNote.style.display = refundAmt > 0 ? 'block' : 'none';

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

  priceSum.style.display = (extendPrice > 0 || refundAmt > 0 || editReturnFee > 0 || editExtrasTotal > 0 || editMotoDiffPrice !== 0) ? 'block' : 'none';
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

  // Save to backend
  if(bookingId){
    var newEndISO = (typeof eDo !== 'undefined' && eDo) ? new Date(eDo.y, eDo.m, eDo.d).toISOString() : null;
    var newStartISO = (typeof eOd !== 'undefined' && eOd && !editIsActive) ? new Date(eOd.y, eOd.m, eOd.d).toISOString() : null;

    // Check for overlapping reservations with new dates
    var checkStart = newStartISO || (typeof origResStart !== 'undefined' ? new Date(origResStart.y, origResStart.m, origResStart.d).toISOString() : null);
    var checkEnd = newEndISO || (typeof origResEnd !== 'undefined' ? new Date(origResEnd.y, origResEnd.m, origResEnd.d).toISOString() : null);
    if(checkStart && checkEnd){
      // Check customer's own bookings overlap
      if(typeof apiCheckBookingOverlap === 'function'){
        var oc = await apiCheckBookingOverlap(checkStart, checkEnd, bookingId);
        if(oc.overlap){
          showT('⚠️',_t('pay').overlapTitle||'Termín obsazen',
            (_t('pay').overlapMsg||'Již máte rezervaci v tomto termínu')+'. '+(_t('pay').overlapHint||'Zvolte jiný termín nebo upravte stávající rezervaci.'));
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
    if(returnTime) changes.return_time = returnTime;
    if(pickupLoc) changes.pickup_location = pickupLoc;
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

    if(diff < 0){
      if(typeof apiShortenBooking === 'function'){
        var res = await apiShortenBooking(bookingId, newEndISO, newStartISO);
        if(res.error){ showT('✗',_t('common').error,res.error); return; }
        // Also save time/location
        if(pickupTime || returnTime || pickupLoc){
          var extraChanges = {};
          if(pickupTime) extraChanges.pickup_time = pickupTime;
          if(returnTime) extraChanges.return_time = returnTime;
          if(pickupLoc) extraChanges.pickup_location = pickupLoc;
          await apiModifyBooking(bookingId, extraChanges);
        }
        // Generate ZF for the shortening change + payment receipt
        if(typeof apiGenerateAdvanceInvoice === 'function'){
          apiGenerateAdvanceInvoice(bookingId, Math.abs(diff), 'edit').catch(function(e){ console.warn('[EDIT] ZF err:', e); });
        }
        if(typeof apiGeneratePaymentReceipt === 'function'){
          apiGeneratePaymentReceipt(bookingId, Math.abs(diff), 'edit').catch(function(e){ console.warn('[EDIT] DP err:', e); });
        }
      }
    } else {
      if(typeof apiModifyBooking === 'function'){
        var editBooking = null;
        if(_isSupabaseReady()){
          try { var _rb=await supabase.from('bookings').select('total_price').eq('id',bookingId).single(); editBooking=_rb.data; } catch(e){}
        }
        if(diff > 0){
          var newPrice = (editBooking ? editBooking.total_price : 0) + diff;
          changes.total_price = newPrice;
        }
        await apiModifyBooking(bookingId, changes);
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
  if(diff>0){
    if(confirmBanner)confirmBanner.innerHTML='✓ '+_t('res').dateConfirmed+' · '+_t('res').toPay+': '+diff.toLocaleString('cs-CZ')+' Kč';
    // Set up proper payment flow for edit
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

// ===== TIME CHIP PICKER FOR EDIT =====
function pickEditTime(el, hiddenId){
  var grid = el.parentNode;
  grid.querySelectorAll('.tchip-edit').forEach(function(b){
    b.classList.remove('active');
    b.style.background='#bbf7d0';b.style.color='#15803d';b.style.fontWeight='600';
  });
  el.classList.add('active');
  el.style.background='#085e27';el.style.color='#fff';el.style.fontWeight='900';
  var hidden = document.getElementById(hiddenId);
  if(hidden) hidden.value = el.textContent.trim();
}

// ===== PAYMENT =====
function selP(type){
  ['card','apple'].forEach(t=>{
    document.getElementById('pm-'+t)?.classList.remove('sel');
    const r=document.getElementById('pmr-'+t);if(r)r.classList.remove('on');
    const d=document.getElementById('pmd-'+t);if(d)d.classList.remove('open');
  });
  document.getElementById('pm-'+type)?.classList.add('sel');
  const r=document.getElementById('pmr-'+type);if(r)r.classList.add('on');
  const d=document.getElementById('pmd-'+type);if(d)d.classList.add('open');
}

function pickT(el){
  if(el.classList.contains('disabled'))return;
  document.querySelectorAll('.tchip').forEach(t=>t.classList.remove('active'));
  el.classList.add('active');
}
function pickBookingTime(el){
  if(el.classList.contains('disabled'))return;
  document.querySelectorAll('#booking-time-grid .tchip').forEach(function(b){
    b.classList.remove('active');
    b.style.background='#bbf7d0';b.style.color='#15803d';b.style.fontWeight='600';
  });
  el.classList.add('active');
  el.style.background='#085e27';el.style.color='#fff';el.style.fontWeight='900';
  showT('🕘','Čas vyzvednutí',el.textContent);
}
function updatePickupTime(val){
  if(val)showT('🕘','Čas vyzvednutí',val);
}
function filterTimeChips(){
  // For select-based time pickers: auto-set hour to next valid hour if today
  var now=new Date();
  var isToday=bOd&&bOd.y===now.getFullYear()&&bOd.m===now.getMonth()&&bOd.d===now.getDate();
  if(isToday){
    var curH=now.getHours();
    var hSel=document.getElementById('booking-time-hour');
    if(hSel && parseInt(hSel.value)<curH+1){
      hSel.value=Math.min(curH+1,23);
    }
  }
}

// ===== POPULATE DYNAMIC RESERVATION DATES =====
function initDynamicDates(){
  // Active reservation card
  const actDate=document.getElementById('rc-act-date');
  const actLen=document.getElementById('rc-act-len');
  const actTotal=document.getElementById('rc-act-total');
  const actId=document.getElementById('rc-act-id');
  if(actDate){
    const d1=ACT_START,d2=ACT_END;
    actDate.textContent=fmtDateShort(d1.d,d1.m)+'–'+fmtDateShort(d2.d,d2.m);
  }
  if(actLen){
    const days=Math.round((new Date(ACT_END.y,ACT_END.m,ACT_END.d)-new Date(ACT_START.y,ACT_START.m,ACT_START.d))/(86400000))+1;
    actLen.textContent=days+(days===1?' den':' dny');
    if(actTotal)actTotal.textContent=(2200*days).toLocaleString('cs-CZ')+' Kč';
  }
  if(actId)actId.textContent='#RES-'+ACT_START.y+'-0031';
  // Upcoming reservation card
  const upcDate=document.getElementById('rc-upc-date');
  const upcLen=document.getElementById('rc-upc-len');
  const upcTotal=document.getElementById('rc-upc-total');
  const upcId=document.getElementById('rc-upc-id');
  if(upcDate){
    const d1=UPC_START,d2=UPC_END;
    upcDate.textContent=fmtDateShort(d1.d,d1.m)+'–'+fmtDateShort(d2.d,d2.m);
  }
  if(upcLen){
    const days=Math.round((new Date(UPC_END.y,UPC_END.m,UPC_END.d)-new Date(UPC_START.y,UPC_START.m,UPC_START.d))/(86400000))+1;
    upcLen.textContent=days+(days===1?' den':' dny');
    if(upcTotal)upcTotal.textContent=(2600*days).toLocaleString('cs-CZ')+' Kč';
  }
  if(upcId)upcId.textContent='#RES-'+UPC_START.y+'-0043';
  // Done reservation cards
  const done1Date=document.getElementById('rc-done1-date');
  if(done1Date)done1Date.textContent=fmtDateShort(DONE1_START.d,DONE1_START.m)+'–'+fmtDateShort(DONE1_END.d,DONE1_END.m);
  const done2Date=document.getElementById('rc-done2-date');
  if(done2Date)done2Date.textContent=fmtDateShort(DONE2_START.d,DONE2_START.m)+'–'+fmtDateShort(DONE2_END.d,DONE2_END.m);
  // Home active reservation banner
  const homeAres=document.getElementById('home-ares-sub');
  if(homeAres)homeAres.textContent='#RES-'+ACT_START.y+'-0031 · '+fmtDateShort(ACT_START.d,ACT_START.m)+' – '+fmtDate(ACT_END.d,ACT_END.m,ACT_END.y);
  // Success screen
  const sucOd=document.getElementById('suc-od');
  const sucDo=document.getElementById('suc-do');
  if(sucOd)sucOd.textContent=fmtDateShort(UPC_START.d,UPC_START.m);
  if(sucDo)sucDo.textContent=fmtDateShort(UPC_END.d,UPC_END.m);
}

// Checkout, cart, voucher, merch → js/cart-engine.js

// ===== DĚTSKÝ MOTOCYKL — ukázat souhlas zákonného zástupce =====
function checkKidsConsent(motoId){
  const m=MOTOS.find(m=>m.id===motoId);
  if(!m) return;
  const kidsLabel=document.getElementById('consent-kids-label');
  const kidsCheck=document.getElementById('consent-kids');
  if(m.cat==='detske'){
    if(kidsCheck) kidsCheck.style.display='inline-block';
    if(kidsLabel) kidsLabel.style.display='inline';
  }
}

// ===== PLATBA — kontrola souhlasů (edit flow) =====
function proceedToEditPayment(){
  // Try to recover bookingMoto from detail list if not set
  if(!bookingMoto && typeof dList!=='undefined' && typeof dIdx!=='undefined' && dList[dIdx]){
    bookingMoto=dList[dIdx];
  }
  if(!bookingMoto){showT('⚠️','Motorka','Vyberte prosím motorku');return;}
  if(!bOd||!bDo){showT('⚠️','Datum','Vyberte prosím datum vyzvednutí a vrácení');return;}
  // Block past dates
  var today=AppTime.today();
  var startDate=new Date(bOd.y,bOd.m,bOd.d);startDate.setHours(0,0,0,0);
  var endDate=new Date(bDo.y,bDo.m,bDo.d);endDate.setHours(0,0,0,0);
  if(startDate<today){showT('⚠️',_t('res').date,_t('res').cannotSelectPast||'Nelze rezervovat v minulosti');return;}
  // Ensure calendar motoId matches bookingMoto for consistent availability
  if(bookingMoto.id && typeof calState !== 'undefined') calState.b.motoId = bookingMoto.id;
  // Validate availability for this specific moto
  if(bookingMoto.id&&typeof isMotoFreeForRange==='function'){
    // Refresh availability data to ensure consistency
    if(typeof initMotoAvailability==='function') initMotoAvailability();
    if(!isMotoFreeForRange(bookingMoto.id,startDate,endDate)){
      showT('⚠️',_t('res').occupied||'Obsazeno',_t('res').motoNotFreeRange||'Motorka není v celém zvoleném období volná');return;
    }
  }
  const c1=document.getElementById('consent-vop');
  const c2=document.getElementById('consent-gdpr');
  if(!c1||!c1.checked){showT('⚠️','Souhlas','Potvrďte souhlas s obchodními podmínkami');return;}
  if(!c2||!c2.checked){showT('⚠️','Souhlas','Potvrďte souhlas se zpracováním osobních údajů');return;}
  goTo('s-payment');
  // Update payment gateway with correct total
  setTimeout(function(){
    var base=0;
    if(typeof calcTotalPrice==='function'&&bookingMoto&&bOd&&bDo){
      base=calcTotalPrice(bookingMoto,new Date(bOd.y,bOd.m,bOd.d),new Date(bDo.y,bDo.m,bDo.d));
    } else { base=2600*bookingDays; }
    var total=base+extraTotal+deliveryFee-discountAmt;
    var formatted=total.toLocaleString('cs-CZ');
    var payBtn=document.getElementById('pay-btn');
    if(payBtn) payBtn.textContent='Zaplatit '+formatted+' Kč →';
    var appleBtn=document.getElementById('apple-pay-btn');
    if(appleBtn) appleBtn.textContent='🍎 Pay '+formatted+' Kč';
  },50);
}

// ===== SOS REPLACEMENT — uložení z edit reservation =====
async function _sosSaveReplacement(){
  var bookingId = window._editBookingId;
  var incId = typeof _sosPendingIncidentId !== 'undefined' ? _sosPendingIncidentId : null;
  var isFault = typeof _sosFault !== 'undefined' && _sosFault === true;

  // Validace: musí být vybrána motorka
  if(!editNewMotoId){
    showT('⚠️','Vyberte motorku','Klikněte na náhradní motorku ze seznamu');
    return;
  }

  // Validace: musí být adresa přistavení
  var pickupAddr = document.getElementById('edit-pickup-address');
  var pickupLoc = (pickupAddr && pickupAddr.value.trim()) ? pickupAddr.value.trim() : null;
  if(!pickupLoc){
    showT('⚠️','Vyplňte adresu','Zadejte adresu přistavení náhradní motorky');
    return;
  }

  var btn = document.getElementById('edit-save-btn');
  if(btn){ btn.disabled = true; btn.style.opacity = '0.6'; btn.textContent = '⏳ Zpracovávám...'; }

  // Změnit motorku na rezervaci
  var changes = {};
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
  changes.pickup_location = pickupLoc;
  changes.sos_replacement = true;

  // Náklady na přistavení
  var deliveryCost = 0;
  if(isFault){
    // Spočítat z edit-pickup adresy
    var retFeeEl = document.getElementById('edit-return-fee');
    if(retFeeEl){
      var parsed = parseInt(retFeeEl.textContent.replace(/[^0-9]/g,''));
      if(!isNaN(parsed)) deliveryCost = parsed;
    }
    if(deliveryCost <= 0) deliveryCost = editReturnFee || 1000;
  }

  // Uložit změnu moto na booking
  if(bookingId && typeof apiModifyBooking === 'function'){
    await apiModifyBooking(bookingId, changes);
  }

  // Aktualizovat SOS incident
  if(incId && window.supabase){
    var selectedModel = '';
    if(typeof MOTOS !== 'undefined'){
      for(var i=0;i<MOTOS.length;i++){
        if(MOTOS[i].id === editNewMotoId){ selectedModel = MOTOS[i].name; break; }
      }
    }
    var replacementData = {
      replacement_moto_id: editNewMotoId,
      replacement_model: selectedModel,
      delivery_address: pickupLoc,
      delivery_fee: deliveryCost,
      payment_amount: deliveryCost,
      payment_status: isFault ? 'pending' : 'free',
      customer_fault: isFault,
      customer_confirmed_at: new Date().toISOString(),
      requested_at: new Date().toISOString()
    };

    if(isFault && deliveryCost > 0){
      // Zákazník zavinil — musí zaplatit přistavení
      try {
        var result = await apiProcessPayment(null, deliveryCost, _currentPaymentMethod || 'card');
        if(result.success && result.checkout_url){
          replacementData.payment_status = 'processing';
          await window.supabase.from('sos_incidents').update({
            replacement_status: 'pending_payment',
            replacement_data: replacementData
          }).eq('id', incId);
          if(window.cordova && window.cordova.InAppBrowser){
            window.cordova.InAppBrowser.open(result.checkout_url, '_system');
          } else { window.open(result.checkout_url, '_blank'); }
          showT('ℹ️','Platba','Otevřena platební brána');
          _sosCleanupEditUI(btn, isFault);
          return;
        }
        if(result.success){
          replacementData.payment_status = 'paid';
          replacementData.paid_at = new Date().toISOString();
          // Generate advance invoice + payment receipt for SOS payment
          if(typeof apiGenerateAdvanceInvoice === 'function' && bookingId){
            apiGenerateAdvanceInvoice(bookingId, deliveryCost, 'sos').catch(function(){});
          }
          if(typeof apiGeneratePaymentReceipt === 'function' && bookingId){
            apiGeneratePaymentReceipt(bookingId, deliveryCost, 'sos').catch(function(){});
          }
        } else {
          showT('❌','Platba zamítnuta','Zkuste to znovu');
          _sosCleanupEditUI(btn, isFault);
          return;
        }
      } catch(e){
        showT('❌','Chyba platby','Zkuste to znovu');
        _sosCleanupEditUI(btn, isFault);
        return;
      }
    }

    await window.supabase.from('sos_incidents').update({
      replacement_status: 'admin_review',
      replacement_data: replacementData
    }).eq('id', incId);
    await window.supabase.from('sos_timeline').insert({
      incident_id: incId,
      action: 'Zákazník objednal náhradní motorku: ' + selectedModel + (isFault ? ' (zaplaceno ' + deliveryCost + ' Kč)' : ' (zdarma)'),
      description: 'Adresa přistavení: ' + pickupLoc + '. Čeká na schválení adminem.'
    });
    if(!isFault && typeof apiSosRequestReplacement === 'function'){
      apiSosRequestReplacement(incId);
    }
  }

  // Úklid a zpráva
  _sosReplacementMode = false;
  _sosPendingIncidentId = null;
  var sosBanner = document.getElementById('sos-edit-banner');
  if(sosBanner) sosBanner.remove();

  if(isFault && deliveryCost > 0){
    showT('✅','Zaplaceno — ' + deliveryCost.toLocaleString('cs-CZ') + ' Kč','Náhradní motorka bude přistavena.');
  } else {
    showT('✅','Objednávka odeslána','Náhradní motorka bude brzy přistavena (zdarma)');
  }
  setTimeout(function(){ goTo('s-sos'); }, 2500);
}

function _sosCalcPickupDelivery(){
  if(typeof _sosReplacementMode === 'undefined' || !_sosReplacementMode) return;
  var isFault = typeof _sosFault !== 'undefined' && _sosFault === true;
  if(!isFault){ updateEditPriceSummary(); return; }
  // Pro zaviněného: spočítej cenu přistavení z pickup adresy
  var addr = document.getElementById('edit-pickup-address');
  var calc = document.getElementById('edit-pickup-calc');
  var kmTxt = document.getElementById('edit-pickup-km-txt');
  if(!addr || !addr.value.trim()){
    if(calc) calc.style.display = 'none';
    editReturnFee = 0;
    updateEditPriceSummary();
    return;
  }
  if(typeof AddressAPI !== 'undefined'){
    var coords = (addr.dataset.lat && addr.dataset.lng)
      ? {lat: parseFloat(addr.dataset.lat), lng: parseFloat(addr.dataset.lng)}
      : addr.value.trim();
    if(kmTxt) kmTxt.textContent = 'Vypočítávám vzdálenost...';
    if(calc) calc.style.display = 'block';
    AddressAPI.calcDistance(coords, function(result){
      if(!result){ _sosCalcPickupFallback(addr, calc, kmTxt); return; }
      editReturnFee = result.fee;
      var txt = '~' + result.km + ' km · ' + result.fee.toLocaleString('cs-CZ') + ' Kč';
      if(result.duration) txt += ' (~' + result.duration + ' min)';
      if(kmTxt) kmTxt.textContent = txt;
      updateEditPriceSummary();
    });
    return;
  }
  _sosCalcPickupFallback(addr, calc, kmTxt);
}

function _sosCalcPickupFallback(addr, calc, kmTxt){
  var km = 50;
  var val = addr.value.toLowerCase();
  if(typeof KM_ESTIMATES !== 'undefined'){
    for(var c in KM_ESTIMATES){ if(val.indexOf(c.toLowerCase()) !== -1){ km = KM_ESTIMATES[c]; break; } }
  } else {
    var KM_EST = {praha:160,brno:60,jihlava:40,tabor:35,ceske:90,plzen:200,ostrava:280};
    for(var c2 in KM_EST){ if(val.indexOf(c2) !== -1){ km = KM_EST[c2]; break; } }
  }
  var fee = 1000 + km * 20;
  editReturnFee = fee;
  if(calc) calc.style.display = 'block';
  if(kmTxt) kmTxt.textContent = '~' + km + ' km · ' + fee.toLocaleString('cs-CZ') + ' Kč (odhad)';
  updateEditPriceSummary();
}

function _sosCleanupEditUI(btn, isFault){
  if(btn){
    btn.disabled = false; btn.style.opacity = '1';
    btn.textContent = isFault ? '💳 Potvrdit a zaplatit přistavení →' : '✅ Potvrdit objednávku (zdarma) →';
  }
}

function _sosUpdateEditPrice(){
  var isFault = typeof _sosFault !== 'undefined' && _sosFault === true;
  var priceSum = document.getElementById('edit-price-summary');
  if(!priceSum) return;
  priceSum.style.display = 'block';
  // Skryj nepotřebné řádky
  var ids = ['edit-extend-row','edit-shorten-row','edit-moto-diff-row','edit-extras-fee-row'];
  ids.forEach(function(id){ var el=document.getElementById(id); if(el) el.style.display='none'; });
  var origRow = document.getElementById('edit-orig-price');
  if(origRow && origRow.parentNode) origRow.parentNode.style.display = 'none';

  var payLabel = document.getElementById('t-editPayRefund');
  var diffEl = document.getElementById('edit-diff-total');

  if(!isFault){
    // Nezaviněná — vše zdarma
    if(payLabel) payLabel.textContent = 'Celkem';
    if(diffEl){ diffEl.textContent = '0 Kč (zdarma)'; diffEl.style.color = 'var(--gd)'; }
    // Skryj řádek přistavení
    var retRow = document.getElementById('edit-return-fee-row');
    if(retRow) retRow.style.display = 'none';
  } else {
    // Zaviněná — zobraz náklady na přistavení
    if(payLabel) payLabel.textContent = 'Náklady na přistavení';
    var retRow2 = document.getElementById('edit-return-fee-row');
    // Spočítej vzdálenost z pickup adresy jako fee
    var pickupAddr = document.getElementById('edit-pickup-address');
    if(pickupAddr && pickupAddr.value.trim()){
      // calcEditDelivery spočítá editReturnFee
      if(retRow2) retRow2.style.display = 'flex';
      var retFee = document.getElementById('edit-return-fee');
      if(retFee) retFee.textContent = '+' + (editReturnFee||0).toLocaleString('cs-CZ') + ' Kč';
      if(diffEl){
        diffEl.textContent = (editReturnFee||0).toLocaleString('cs-CZ') + ' Kč';
        diffEl.style.color = '#b91c1c';
      }
    } else {
      if(retRow2) retRow2.style.display = 'none';
      if(diffEl){ diffEl.textContent = 'Zadejte adresu'; diffEl.style.color = 'var(--g400)'; }
    }
  }

  // Aktualizuj button text
  var saveBtn = document.getElementById('edit-save-btn');
  if(saveBtn){
    if(isFault && editReturnFee > 0){
      saveBtn.textContent = '💳 Zaplatit ' + editReturnFee.toLocaleString('cs-CZ') + ' Kč a objednat →';
    } else if(isFault){
      saveBtn.textContent = '💳 Potvrdit a zaplatit přistavení →';
    } else {
      saveBtn.textContent = '✅ Potvrdit objednávku (zdarma) →';
    }
  }
}
