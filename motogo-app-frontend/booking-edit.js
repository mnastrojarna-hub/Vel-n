// ===== BOOKING-EDIT.JS – Time pickers, UI toggles, delivery calc, extras, branch, moto selection =====
// Split from original booking-edit.js. See also: booking-edit-price.js, booking-edit-sos.js

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

var _calcEditDelivTimer = null;
function calcEditDelivery(){
  clearTimeout(_calcEditDelivTimer);
  _calcEditDelivTimer = setTimeout(_doCalcEditDelivery, 500);
}
function _doCalcEditDelivery(){
  var addr = document.getElementById('edit-return-address');
  var calc = document.getElementById('edit-return-calc');
  var kmTxt = document.getElementById('edit-return-km-txt');
  if(!addr || !addr.value.trim()){ if(calc) calc.style.display='none'; editReturnFee=0; updateEditPriceSummary(); return; }

  var addrVal = addr.value.trim();
  // Build full address with city for accurate geocoding
  var cityEl = document.getElementById('edit-return-city');
  var zipEl = document.getElementById('edit-return-zip');
  var city = (cityEl && cityEl.value) ? cityEl.value.trim() : '';
  var zip = (zipEl && zipEl.value) ? zipEl.value.trim() : '';
  var fullAddr = addrVal;
  if(city) fullAddr += ', ' + city;
  if(zip) fullAddr += ', ' + zip;

  // Use OSRM API if available
  if(typeof AddressAPI !== 'undefined'){
    var coords = (addr.dataset.lat && addr.dataset.lng)
      ? {lat: parseFloat(addr.dataset.lat), lng: parseFloat(addr.dataset.lng)}
      : fullAddr;
    if(kmTxt) kmTxt.textContent = 'Vypočítávám vzdálenost...';
    if(calc) calc.style.display = 'block';
    AddressAPI.calcDistance(coords, function(result){
      if(!result){ _calcEditDelivFallback(addr, calc, kmTxt); return; }
      var fee = result.fee;
      var diff = Math.max(0, fee - editOrigDeliveryPaid);
      editReturnFee = diff;
      var txt = '📍 ~' + result.km + ' km · ' + fee.toLocaleString('cs-CZ') + ' Kč';
      if(result.duration) txt += ' · ~' + result.duration + ' min';
      if(editOrigDeliveryPaid > 0 && diff > 0) txt += '\nDoplatek: ' + diff.toLocaleString('cs-CZ') + ' Kč (zaplaceno ' + editOrigDeliveryPaid.toLocaleString('cs-CZ') + ' Kč)';
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
  var _t2 = '📍 ~' + km + ' km · ' + fee.toLocaleString('cs-CZ') + ' Kč (odhad)';
  if(editOrigDeliveryPaid > 0 && diff > 0) _t2 += '\nDoplatek: ' + diff.toLocaleString('cs-CZ') + ' Kč (zaplaceno ' + editOrigDeliveryPaid.toLocaleString('cs-CZ') + ' Kč)';
  if(kmTxt) kmTxt.textContent = _t2;
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
