// ===== BOOKING-EDIT-SOS.JS – Time chips, dynamic dates, kids consent, payment controls, SOS replacement flow =====
// Split from original booking-edit.js. See also: booking-edit.js, booking-edit-price.js

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
  showT('🕘',_t('hc').pickupTime,el.textContent);
}
function updatePickupTime(val){
  if(val)showT('🕘',_t('hc').pickupTime,val);
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
  var h=_t('hc');
  if(!bookingMoto){showT('⚠️',_t('book').motorcycle,h.selectMoto);return;}
  if(!bOd||!bDo){showT('⚠️',_t('res').date,h.selectDates);return;}
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
  if(!c1||!c1.checked){showT('⚠️',_t('pay').consents,h.consentVOP);return;}
  if(!c2||!c2.checked){showT('⚠️',_t('pay').consents,h.consentGDPR);return;}
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
    if(payBtn) payBtn.textContent=(_t('pay').payBtn||'Pay')+' '+formatted+' Kč →';
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
  var h=_t('hc');
  if(!editNewMotoId){
    showT('⚠️',h.selectMoto,h.selectReplaceMoto);
    return;
  }

  // Validace: musí být adresa přistavení
  var pickupAddr = document.getElementById('edit-pickup-address');
  var pickupLoc = (pickupAddr && pickupAddr.value.trim()) ? pickupAddr.value.trim() : null;
  if(!pickupLoc){
    showT('⚠️',_t('edit').enterAddr,h.fillAddress);
    return;
  }

  var btn = document.getElementById('edit-save-btn');
  if(btn){ btn.disabled = true; btn.style.opacity = '0.6'; btn.textContent = '⏳ ' + h.processing; }

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
          if(typeof _openExternalUrl === 'function'){ _openExternalUrl(result.checkout_url); }
          else { window.open(result.checkout_url, '_blank'); }
          showT('ℹ️',_t('pay').title,h.payGatewayOpened);
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
          showT('❌',h.payDeclined,h.tryAgain);
          _sosCleanupEditUI(btn, isFault);
          return;
        }
      } catch(e){
        showT('❌',h.payError,h.tryAgain);
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
    showT('✅',h.paidDelivery.replace('{amt}',deliveryCost.toLocaleString('cs-CZ')),h.replacementDelivered);
  } else {
    showT('✅',h.orderSent,h.replacementFreeMsg);
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
  // Build full address with city for accurate geocoding
  var cityEl = document.getElementById('edit-pickup-city');
  var zipEl = document.getElementById('edit-pickup-zip');
  var city = (cityEl && cityEl.value) ? cityEl.value.trim() : '';
  var zip = (zipEl && zipEl.value) ? zipEl.value.trim() : '';
  var fullAddr = addr.value.trim();
  if(city) fullAddr += ', ' + city;
  if(zip) fullAddr += ', ' + zip;

  if(typeof AddressAPI !== 'undefined'){
    var coords = (addr.dataset.lat && addr.dataset.lng)
      ? {lat: parseFloat(addr.dataset.lat), lng: parseFloat(addr.dataset.lng)}
      : fullAddr;
    if(kmTxt) kmTxt.textContent = _t('hc').calcDistance;
    if(calc) calc.style.display = 'block';
    AddressAPI.calcDistance(coords, function(result){
      if(!result){ _sosCalcPickupFallback(addr, calc, kmTxt); return; }
      editReturnFee = result.fee;
      var txt = '📍 ~' + result.km + ' km · ' + result.fee.toLocaleString('cs-CZ') + ' Kč';
      if(result.duration) txt += ' · ~' + result.duration + ' min';
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
  var fee = 1000 + km * 2 * 20;
  editReturnFee = fee;
  if(calc) calc.style.display = 'block';
  if(kmTxt) kmTxt.textContent = '📍 ~' + km + ' km · ' + fee.toLocaleString('cs-CZ') + ' Kč (' + _t('hc').estimate + ')';
  updateEditPriceSummary();
}

function _sosCleanupEditUI(btn, isFault){
  if(btn){
    btn.disabled = false; btn.style.opacity = '1';
    var h=_t('hc');
    btn.textContent = isFault ? '💳 ' + h.payConfirmDelivery : '✅ ' + h.confirmOrderFree;
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

  var h=_t('hc');
  var payLabel = document.getElementById('t-editPayRefund');
  var diffEl = document.getElementById('edit-diff-total');

  if(!isFault){
    // Nezaviněná — vše zdarma
    if(payLabel) payLabel.textContent = h.totalLabel;
    if(diffEl){ diffEl.textContent = '0 Kč (' + h.free + ')'; diffEl.style.color = 'var(--gd)'; }
    // Skryj řádek přistavení
    var retRow = document.getElementById('edit-return-fee-row');
    if(retRow) retRow.style.display = 'none';
  } else {
    // Zaviněná — zobraz náklady na přistavení
    if(payLabel) payLabel.textContent = h.deliveryCosts;
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
      if(diffEl){ diffEl.textContent = h.enterAddress; diffEl.style.color = 'var(--g400)'; }
    }
  }

  // Aktualizuj button text
  var saveBtn = document.getElementById('edit-save-btn');
  if(saveBtn){
    if(isFault && editReturnFee > 0){
      saveBtn.textContent = '💳 ' + h.payAndOrder.replace('{amt}',editReturnFee.toLocaleString('cs-CZ'));
    } else if(isFault){
      saveBtn.textContent = '💳 ' + h.payConfirmDelivery;
    } else {
      saveBtn.textContent = '✅ ' + h.confirmOrderFree;
    }
  }
}
