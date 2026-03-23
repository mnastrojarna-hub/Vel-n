/* === RESERVATIONS-EDIT.JS — Edit, restore, rebook, extend, summary rendering, SOS detail === */

async function openEditResByBookingId(bookingId){
  try {
    var booking = await _getBookingById(bookingId);
    if(!booking){ showT('✗',_t('common').error,_t('res').resNotFound); return; }
    var moto = booking.motorcycles || (booking.moto_id ? await _getMotoById(booking.moto_id) : null);
    var st = _mapStatus(booking.status, booking.start_date, booking.end_date, booking);
    var isActive = (st === 'aktivni');

    // Set V9 global variables for edit screen
    editIsActive = isActive;

    var s = new Date(booking.start_date); s.setHours(0,0,0,0);
    var e = new Date(booking.end_date); e.setHours(0,0,0,0);
    var motoName = moto ? (moto.model || moto.name) : (booking.moto_name || 'Motorka');
    var days = Math.max(1, Math.round((e-s)/86400000)+1);

    // origResStart and origResEnd for edit calendar
    origResStart = {d:s.getDate(), m:s.getMonth(), y:s.getFullYear()};
    origResEnd = {d:e.getDate(), m:e.getMonth(), y:e.getFullYear()};

    // Fill UI
    var subEl = document.getElementById('edit-subtitle');
    if(subEl) subEl.textContent = motoName + ' · #' + bookingId.substr(-8).toUpperCase();

    var durEl = document.getElementById('edit-res-duration');
    var dateRangeEl = document.getElementById('edit-res-dates');
    var now = new Date(); now.setHours(0,0,0,0);

    if(isActive){
      var remaining = Math.max(0, Math.round((e-now)/86400000))+1;
      if(durEl) durEl.textContent = _t('res').activeRemaining+' ' + remaining + (remaining===1?' '+_t('res').day1:remaining<5?' '+_t('res').days2:' '+_t('res').days5);
    } else {
      var daysTo = Math.max(0, Math.round((s-now)/86400000));
      if(durEl) durEl.textContent = _t('res').upcomingIn+' ' + daysTo + (daysTo===1?' '+_t('res').day1:daysTo<5?' '+_t('res').days2:' '+_t('res').days5) + ' · ' + days + (days===1?' '+_t('res').day1:days<5?' '+_t('res').days2:' '+_t('res').days5);
    }
    if(dateRangeEl) dateRangeEl.textContent = s.getDate()+'.'+(s.getMonth()+1)+'. – '+e.getDate()+'.'+(e.getMonth()+1)+'.'+e.getFullYear();

    // Calendar info
    var calResDates = document.getElementById('edit-cal-res-dates');
    var calResMoto = document.getElementById('edit-cal-res-moto');
    var calResInfo = document.getElementById('edit-res-info-cal');
    if(calResDates) calResDates.textContent = dateRangeEl ? dateRangeEl.textContent : '';
    if(calResMoto) calResMoto.textContent = motoName + ' · #' + bookingId.substr(-8).toUpperCase();
    if(calResInfo){
      var infoDiv = calResInfo.querySelector('div');
      if(infoDiv) infoDiv.textContent = isActive ? _t('res').yourActiveRes : _t('res').yourUpcomingRes;
    }

    // Reset edit UI
    var shortenNote = document.getElementById('edit-shorten-note');
    if(shortenNote) shortenNote.style.display = 'none';
    var priceSum = document.getElementById('edit-price-summary');
    if(priceSum) priceSum.style.display = 'none';
    var saveBtn = document.getElementById('edit-save-btn');
    if(saveBtn) saveBtn.textContent = _t('res').saveChanges;

    // Store booking ID for saveEditReservation
    window._editBookingId = bookingId;
    window._editBookingMoto = moto;

    // Update branch address in pickup/return/branch sections dynamically
    var _brAddr = moto && moto.branches && moto.branches.address ? moto.branches.address : 'Mezná 9';
    var _brCity = moto && moto.branches && moto.branches.city ? moto.branches.city : '393 01 Mezná';
    var _brName = moto && moto.branches && moto.branches.name ? moto.branches.name : 'Mezná';
    var _brFull = _brAddr + ', ' + _brCity;
    // Pickup section
    var psl = document.getElementById('edit-pickup-store-label');
    if(psl){ var psn = psl.querySelector('div > div:last-child'); if(psn) psn.textContent = _brFull; }
    // Return section
    var rsl = document.getElementById('edit-return-store-label');
    if(rsl){ var rsn = rsl.querySelector('div > div:last-child'); if(rsn) rsn.textContent = _brFull; }
    // Branch change section
    var bml = document.getElementById('edit-branch-mezna-label');
    if(bml){ var bn = bml.querySelector('div > div:first-child'); if(bn) bn.innerHTML = '🏍️ ' + _brName; var ba = bml.querySelector('div > div:last-child'); if(ba) ba.textContent = _brFull; }

    // Zobrazit doplňky jen pro nadcházející
    var extrasCard = document.getElementById('edit-extras-card');
    if(extrasCard) extrasCard.style.display = isActive ? 'none' : 'block';

    // Naplnit text data
    var odTxt = document.getElementById('edit-od-txt');
    var doTxt = document.getElementById('edit-do-txt');
    if(odTxt) odTxt.textContent = s.getDate()+'.'+(s.getMonth()+1)+'.'+s.getFullYear();
    if(doTxt) doTxt.textContent = e.getDate()+'.'+(e.getMonth()+1)+'.'+e.getFullYear();

    // Nastavit eOd, eDo
    eOd = {d:s.getDate(), m:s.getMonth(), y:s.getFullYear()};
    eDo = {d:e.getDate(), m:e.getMonth(), y:e.getFullYear()};

    // Reset extras and moto change
    if(typeof editExtrasTotal !== 'undefined') editExtrasTotal = 0;
    if(typeof editReturnFee !== 'undefined') editReturnFee = 0;
    if(typeof editMotoDiffPrice !== 'undefined') editMotoDiffPrice = 0;
    if(typeof editNewMotoId !== 'undefined') editNewMotoId = null;

    // Pre-fill return address from booking if delivery was already set
    if(booking.return_method === 'delivery' && booking.return_address){
      var retRadio = document.querySelector('input[name="edit-return"][value="other"]');
      if(retRadio){ retRadio.checked = true; if(typeof setEditReturn === 'function') setEditReturn('other'); }
      var retAddr = document.getElementById('edit-return-address');
      if(retAddr) retAddr.value = booking.return_address;
      // Pre-set editOrigDeliveryPaid so delivery diff is calculated correctly
      if(typeof editOrigDeliveryPaid !== 'undefined') editOrigDeliveryPaid = booking.delivery_fee || 0;
    }

    if(typeof switchEditTab === 'function') switchEditTab('prodlouzit');
    goTo('s-edit-res');
  } catch(e){
    console.error('openEditResByBookingId error:', e);
    showT('✗',_t('common').error,_t('res').openEditFailed);
  }
}

async function restoreBooking(bookingId){
  try {
    if(!confirm(_t('res').restoreConfirm)) return;
    var result = await apiRestoreBooking(bookingId);
    if(result.error){ showT('✗',_t('common').error,result.error); return; }
    var booking = result.booking;
    // Check for overlapping reservations before restoring
    if(typeof apiCheckBookingOverlap === 'function' && booking){
      var oc = await apiCheckBookingOverlap(booking.start_date, booking.end_date, bookingId);
      if(oc.overlap){
        var cf = oc.conflicting;
        showT('⚠️',_t('pay').overlapTitle||'Termín obsazen',
          (_t('pay').overlapMsg||'Již máte rezervaci v tomto termínu')+': '+(cf.moto_name||'motorka')+' ('+_fmtDate(cf.start_date)+' – '+_fmtDate(cf.end_date)+'). '+(_t('pay').overlapHint||'Zvolte jiný termín nebo upravte stávající rezervaci.'));
        return;
      }
    }
    if(!booking){ showT('✗',_t('common').error,'Rezervace nenalezena'); return; }

    // Reservation stays cancelled until payment succeeds
    // Set up payment flow for the restore
    _currentBookingId = bookingId;
    _currentPaymentAmount = booking.total_price || 0;
    _currentPaymentMethod = 'card';
    _paymentAttempts = 0;
    _isRestorePayment = true;

    // Navigate to payment screen
    var payBtn = document.getElementById('pay-btn');
    if(payBtn){
      payBtn.textContent = (_t('pay').payBtn||'Zaplatit') + ' ' + _currentPaymentAmount.toLocaleString('cs-CZ') + ' Kč →';
      payBtn.onclick = function(){ doRestorePayment(bookingId); };
    }
    var applePayBtn = document.getElementById('apple-pay-btn');
    if(applePayBtn) applePayBtn.textContent = '🍎 Pay ' + _currentPaymentAmount.toLocaleString('cs-CZ') + ' Kč';

    goTo('s-payment');
  } catch(e){ console.error('restoreBooking error:', e); showT('✗',_t('common').error,_t('res').restoreFailed); }
}

function _rebookMoto(motoId){
  if(motoId && typeof openDetail === 'function'){
    openDetail(motoId);
    showT('🏍️',_t('res').bookAgain||'Rezervace',_t('res').selectDateSameMoto||'Vyberte termín pro stejnou motorku');
  } else {
    goTo('s-home');
    showT('🏍️',_t('res').bookAgain||'Rezervace',_t('res').selectMoto||'Vyberte motorku');
  }
}

function _fmtDT(iso){
  try { var d=new Date(iso); return d.getDate()+'.'+(d.getMonth()+1)+'.'+d.getFullYear()+' '+d.getHours()+':'+('0'+d.getMinutes()).slice(-2); } catch(e){ return '—'; }
}

function _descMod(fromStart, fromEnd, toStart, toEnd){
  // Normalize to local midnight to avoid timezone drift
  var _nd=function(d){var dt=new Date(d);return new Date(dt.getFullYear(),dt.getMonth(),dt.getDate());};
  var fs=_nd(fromStart),fe=_nd(fromEnd),ts=_nd(toStart),te=_nd(toEnd);
  var sd=Math.round((ts-fs)/86400000), ed=Math.round((te-fe)/86400000);
  var origD=Math.max(1,Math.round((fe-fs)/86400000)+1), newD=Math.max(1,Math.round((te-ts)/86400000)+1);
  var dd=newD-origD;
  var parts=[];
  if(sd<0) parts.push('začátek dříve o '+Math.abs(sd)+' d');
  else if(sd>0) parts.push('začátek později o '+sd+' d');
  if(ed>0) parts.push('konec později o '+ed+' d');
  else if(ed<0) parts.push('konec dříve o '+Math.abs(ed)+' d');
  var type,color;
  if(dd>0){type='prodlouženo o '+dd+' d';color='#2563eb';}
  else if(dd<0){type='zkráceno o '+Math.abs(dd)+' d';color='#dc2626';}
  else if(sd!==0||ed!==0){type='posunuto';color='#92400e';}
  else{type='beze změny';color='#4a6357';}
  var detail=parts.length>0?parts.join(', '):type;
  return {type:type,detail:detail,origDays:origD,newDays:newD,color:color};
}

function _renderDetailSummary(b, moto, st, days, branchName, bookingId){
  var el = document.getElementById('rd-detail-summary');
  if(!el) return;
  var li = function(label, val){ return val ? '<li><strong>'+label+':</strong> '+val+'</li>' : ''; };
  var h = '<ul class="rd-sum">';

  // Status & ID
  h += li('Stav', _statusLabel(st));
  h += li('ID rezervace', '#'+bookingId.substr(-8).toUpperCase());
  h += li('Motorka', moto ? (moto.model||'—') + (moto.spz ? ' ('+moto.spz+')' : '') : '—');
  if(moto && moto.category){
    var catMap = {cestovni:'Cestovní enduro',naked:'Naked',supermoto:'Supermoto',detske:'Dětské',sportovni:'Sportovní'};
    var catLabel = catMap[(moto.category||'').toLowerCase()] || moto.category;
    var licReq = moto.license_required ? ' · ' + moto.license_required : '';
    h += li('Kategorie', catLabel + licReq);
  }
  h += li('Pobočka', branchName);

  // Dates — current
  h += li('Začátek', _fmtDate(b.start_date) + ' v ' + (b.pickup_time||'9:00'));
  h += li('Konec', _fmtDate(b.end_date) + ' v ' + (b.pickup_time || '9:00'));
  h += li('Délka', days + ' ' + (days===1?'den':days<5?'dny':'dní'));

  // Original dates (if modified)
  if(b.original_start_date && b.original_end_date && (b.original_start_date !== b.start_date || b.original_end_date !== b.end_date)){
    var _mod = _descMod(b.original_start_date, b.original_end_date, b.start_date, b.end_date);
    h += '<li style="color:#b45309;"><strong>Původní termín:</strong> '+_fmtDate(b.original_start_date)+' – '+_fmtDate(b.original_end_date)+' ('+_mod.origDays+' dní)</li>';
    h += '<li style="color:'+_mod.color+';"><strong>Celkem:</strong> '+_mod.type+' → '+_fmtDate(b.start_date)+' – '+_fmtDate(b.end_date)+' ('+days+' dní)</li>';
    // Show full modification history
    var _hist = Array.isArray(b.modification_history) ? b.modification_history : [];
    for(var hi=0; hi<_hist.length; hi++){
      var _hm = _descMod(_hist[hi].from_start, _hist[hi].from_end, _hist[hi].to_start, _hist[hi].to_end);
      var _hmExtra = '';
      if(_hist[hi].from_moto && _hist[hi].to_moto) _hmExtra = ' · motorka: '+_hist[hi].from_moto+' → '+_hist[hi].to_moto;
      h += '<li style="color:'+_hm.color+';font-size:11px;"><strong>Úprava #'+(hi+1)+':</strong> '+_fmtDT(_hist[hi].at)+' — '+_hm.type+' ('+_hm.detail+')'+_hmExtra+' · '+(_hist[hi].source==='admin'?'admin':'zákazník')+'</li>';
    }
  }

  // Pickup/return method & address
  h += li(b.pickup_method==='delivery'?'Přistavení':'Vyzvednutí', (b.pickup_method==='delivery'?'Přistavení na adresu':'Na pobočce') + ' — ' + (b.pickup_address||branchName));
  h += li(b.return_method==='delivery'?'Svoz':'Vrácení', (b.return_method==='delivery'?'Svoz z adresy':'Na pobočce') + ' — ' + (b.return_address||branchName));
  if(b.delivery_fee > 0){
    var pFee = typeof pickupDelivFee !== 'undefined' ? pickupDelivFee : 0;
    var rFee = typeof returnDelivFee !== 'undefined' ? returnDelivFee : 0;
    if(pFee > 0) h += li('Přistavení cena', pFee.toLocaleString('cs-CZ')+' Kč');
    if(rFee > 0) h += li('Svoz cena', rFee.toLocaleString('cs-CZ')+' Kč');
  }

  // Gear
  if(b.boots_size) h += li('Boty', 'vel. '+b.boots_size);
  if(b.helmet_size) h += li('Helma', 'vel. '+b.helmet_size);
  if(b.jacket_size) h += li('Bunda', 'vel. '+b.jacket_size);

  // Insurance
  if(b.insurance_type) h += li('Pojištění', b.insurance_type);

  // Pricing
  h += li('Cena výpůjčky', (b.total_price||0).toLocaleString('cs-CZ')+' Kč');
  if(b.extras_price > 0) h += li('Příslušenství', b.extras_price.toLocaleString('cs-CZ')+' Kč');
  if(b.delivery_fee > 0) h += li('Doručení', b.delivery_fee.toLocaleString('cs-CZ')+' Kč');
  if(b.discount_amount > 0){
    var _dLabel = b._promoType==='percent' && b._promoValue ? 'sleva '+b._promoValue+'%' : '-'+b.discount_amount.toLocaleString('cs-CZ')+' K\u010d';
    h += li('Sleva', _dLabel+(b.discount_code?' (k\u00f3d: '+b.discount_code+')':''));
  }
  h += li('Platba', b.payment_status==='paid'?'Zaplaceno':'Nezaplaceno');
  if(b.payment_method) h += li('Způsob platby', b.payment_method);

  // Mileage
  if(b.mileage_start) h += li('Nájezd při převzetí', b.mileage_start+' km');
  if(b.mileage_end) h += li('Nájezd při vrácení', b.mileage_end+' km');
  if(b.mileage_start && b.mileage_end) h += li('Najeto', (b.mileage_end-b.mileage_start)+' km');

  // Damage
  if(b.damage_report) h += '<li style="color:#b91c1c;"><strong>Poškození:</strong> '+b.damage_report+'</li>';

  // SOS
  if(b.sos_replacement) h += '<li style="color:#1a8a18;"><strong>SOS náhrada:</strong> Ano'+(b.replacement_for_booking_id?' (za #'+b.replacement_for_booking_id.substr(-8).toUpperCase()+')':'')+'</li>';
  if(b.ended_by_sos) h += '<li style="color:#b91c1c;"><strong>Ukončeno SOS:</strong> Ano'+(b.sos_incident_id?' (incident #'+b.sos_incident_id.substr(-8).toUpperCase()+')':'')+'</li>';

  // Cancellation
  if(b.status==='cancelled'){
    h += '<li style="color:#b91c1c;"><strong>Zrušeno:</strong> '+_fmtDT(b.cancelled_at)+'</li>';
    if(b.cancellation_reason) h += '<li style="color:#b91c1c;"><strong>Důvod:</strong> '+b.cancellation_reason+'</li>';
  }

  // Timeline
  h += '</ul><div class="rd-sum-t" style="margin-top:8px;"><strong>Průběh:</strong></div><ul class="rd-sum">';
  if(b.created_at) h += '<li>Vytvořeno: '+_fmtDT(b.created_at)+'</li>';
  if(b.confirmed_at) h += '<li>Potvrzeno: '+_fmtDT(b.confirmed_at)+'</li>';
  if(b.picked_up_at) h += '<li>Vydáno: '+_fmtDT(b.picked_up_at)+'</li>';
  if(b.returned_at) h += '<li>Vráceno: '+_fmtDT(b.returned_at)+'</li>';
  if(b.actual_return_date) h += '<li>Skutečné vrácení: '+_fmtDT(b.actual_return_date)+'</li>';
  if(b.cancelled_at) h += '<li style="color:#b91c1c;">Zrušeno: '+_fmtDT(b.cancelled_at)+'</li>';
  if(b.rated_at) h += '<li>Hodnoceno: '+_fmtDT(b.rated_at)+' ('+b.rating+'/5)</li>';
  h += '</ul>';

  // Fetch SOS incidents async
  el.innerHTML = h;
  el.style.display = 'block';
  _loadSosForDetail(b.id, el);
}

async function _loadSosForDetail(bookingId, el){
  if(!_isSupabaseReady()) return;
  try {
    var r = await supabase.from('sos_incidents').select('id,type,title,status,severity,created_at,resolved_at,description').eq('booking_id',bookingId).order('created_at',{ascending:false});
    if(!r.data || r.data.length===0) return;
    var h = '<div class="rd-sum-t" style="margin-top:8px;"><strong>SOS incidenty:</strong></div><ul class="rd-sum">';
    for(var i=0;i<r.data.length;i++){
      var inc = r.data[i];
      h += '<li style="color:#b91c1c;">#'+inc.id.substr(-8).toUpperCase()+' — '+inc.type+' ('+inc.severity+') — '+inc.status;
      if(inc.title) h += ' — '+inc.title;
      h += ' — '+_fmtDT(inc.created_at);
      if(inc.resolved_at) h += ' → vyřešeno '+_fmtDT(inc.resolved_at);
      h += '</li>';
    }
    h += '</ul>';
    el.innerHTML += h;
  } catch(e){}
}

async function openExtendBooking(bookingId){
  try {
    var booking = await _getBookingById(bookingId);
    if(!booking){ showT('✗',_t('common').error,_t('res').resNotFound); return; }

    var currentEnd = new Date(booking.end_date);
    var newEnd = new Date(currentEnd);
    newEnd.setDate(newEnd.getDate() + 1);

    var msg = _t('res').extendConfirm + ' ' + newEnd.getDate() + '. ' + (newEnd.getMonth()+1) + '. ' + newEnd.getFullYear() + '?';
    if(!confirm(msg)) return;

    var result = await apiExtendBooking(bookingId, newEnd.getFullYear()+'-'+String(newEnd.getMonth()+1).padStart(2,'0')+'-'+String(newEnd.getDate()).padStart(2,'0'));
    if(result.error){
      showT('✗',_t('common').error, result.error);
      return;
    }

    showT('✓',_t('res').extended,_t('res').extendedMsg);
    renderMyReservations();
    if(_currentResId === bookingId) openResDetailById(bookingId);
  } catch(e){ console.error('openExtendBooking error:', e); showT('✗',_t('common').error,_t('res').extendFailed); }
}
