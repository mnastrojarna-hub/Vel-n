// ===== PAYMENT-UI.JS – Payment flow & booking confirmation =====

var _currentBookingId = null;
var _currentPaymentAmount = 0;
var _currentPaymentMethod = 'card';
var _paymentAttempts = 0;
var _paymentTimeout = null;
var _MAX_PAYMENT_ATTEMPTS = 3;
var _PAYMENT_TIMEOUT_MS = 600000; // 10 minutes (shodně s backend cron auto_cancel_expired_pending)
var _isRestorePayment = false;
var _isEditPayment = false;
var _editPaymentBookingId = null;
var _stripeCheckoutOpened = false; // true = platební brána otevřena, blokuj zpět + duplicitní platbu
var _stripeCheckoutBookingId = null; // booking ID čekající na potvrzení ze Stripe

// Capacitor Browser místo Cordova InAppBrowser
function _openExternalUrl(url){
  if(window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Browser){
    window.Capacitor.Plugins.Browser.open({ url: url });
  } else {
    window.open(url, '_blank');
  }
}

// Lock payment screen after Stripe checkout opened — hide back button, disable pay button
function _lockPaymentScreen(msg){
  _stripeCheckoutOpened = true;
  // Hide back button on s-payment
  var backRow = document.querySelector('#s-payment .back-row');
  if(backRow) backRow.style.display = 'none';
  // Hide back button on s-sos-payment
  var sosBack = document.querySelector('#s-sos-payment .sos-sub-back');
  if(sosBack) sosBack.style.display = 'none';
  // Disable pay buttons
  var payBtn = document.getElementById('pay-btn');
  if(payBtn){ payBtn.disabled = true; payBtn.style.opacity = '0.6'; payBtn.textContent = msg || 'Čekám na potvrzení platby...'; }
  var sosPayBtn = document.getElementById('sos-pay-btn');
  if(sosPayBtn){ sosPayBtn.disabled = true; sosPayBtn.style.opacity = '0.6'; sosPayBtn.textContent = msg || 'Čekám na potvrzení platby...'; }
}

// Check payment status after returning from Stripe — called on app resume
// Retries up to 5x with 2s intervals to wait for webhook confirmation
async function _checkPaymentAfterStripe(attempt){
  if(!_stripeCheckoutOpened || !_stripeCheckoutBookingId) return;
  if(!window.supabase) return;
  attempt = attempt || 0;
  try {
    var r = await window.supabase.from('bookings').select('status, payment_status').eq('id', _stripeCheckoutBookingId).single();
    if(!r.data){
      // No data — force unblock after retries
      if(attempt >= 4){
        _stripeCheckoutOpened = false;
        goTo('s-res');
      }
      return;
    }
    // Still unpaid — webhook hasn't arrived yet, retry
    if(r.data.payment_status !== 'paid' && r.data.status !== 'cancelled' && attempt < 5){
      _lockPaymentScreen('⏳ Ověřuji platbu... (' + (attempt + 1) + '/5)');
      setTimeout(function(){ _checkPaymentAfterStripe(attempt + 1); }, 2000);
      return;
    }
    // Timeout — force navigate to reservations (prevent black screen)
    if(r.data.payment_status !== 'paid' && r.data.status !== 'cancelled' && attempt >= 5){
      _stripeCheckoutOpened = false;
      _stripeCheckoutBookingId = null;
      showT('ℹ️','Platba se ověřuje','Stav platby bude aktualizován. Zkontrolujte v Moje rezervace.');
      goTo('s-res');
      if(typeof renderMyReservations === 'function') renderMyReservations();
      return;
    }
    if(r.data.payment_status === 'paid'){
      // Platba potvrzena webhookem
      var bkId = _stripeCheckoutBookingId;
      _stripeCheckoutOpened = false;
      _stripeCheckoutBookingId = null;
      if(_isRestorePayment){
        _isRestorePayment = false;
        _currentBookingId = null;
        // Confirm restore: set booking to active + paid
        if(typeof apiConfirmRestoreBooking === 'function') apiConfirmRestoreBooking(bkId).catch(function(){});
        // Auto-generate docs (non-blocking)
        try {
          if(typeof apiGenerateAdvanceInvoice === 'function') apiGenerateAdvanceInvoice(bkId, _currentPaymentAmount, 'restore').catch(function(){});
          if(typeof apiGeneratePaymentReceipt === 'function') apiGeneratePaymentReceipt(bkId, _currentPaymentAmount, 'restore').catch(function(){});
          if(typeof apiAutoGenerateBookingDocs === 'function') apiAutoGenerateBookingDocs(bkId).catch(function(){});
        } catch(de){}
        showT('✓',_t('pay').paid||'Zaplaceno',_t('res').restored||'Rezervace obnovena');
        goTo('s-res');
        if(typeof renderMyReservations === 'function') renderMyReservations();
        return;
      }
      if(_isEditPayment){
        _isEditPayment = false;
        _editPaymentBookingId = null;
        _cachedBookings = null;
        // Apply pending edit changes after successful payment
        var pendingChanges = window._pendingEditChanges || null;
        if(pendingChanges && typeof apiModifyBooking === 'function'){
          apiModifyBooking(bkId, pendingChanges).catch(function(e){ console.warn('[PAY] Edit apply err:', e); });
          window._pendingEditChanges = null;
        }
        // Auto-generate docs (non-blocking)
        try {
          if(typeof apiGenerateAdvanceInvoice === 'function') apiGenerateAdvanceInvoice(bkId, _currentPaymentAmount, 'edit').catch(function(){});
          if(typeof apiGeneratePaymentReceipt === 'function') apiGeneratePaymentReceipt(bkId, _currentPaymentAmount, 'edit').catch(function(){});
          if(typeof apiAutoGenerateBookingDocs === 'function') apiAutoGenerateBookingDocs(bkId, true).catch(function(){});
        } catch(de){}
        showT('✓',_t('pay').paid||'Zaplaceno',_t('res').changesSavedShort||'Změny uloženy');
        if(typeof renderMyReservations === 'function') renderMyReservations();
        if(typeof openResDetailById === 'function') openResDetailById(bkId);
        else goTo('s-res');
        return;
      }
      // Normal booking payment
      if(_paymentTimeout){ clearTimeout(_paymentTimeout); _paymentTimeout = null; }
      // Log all applied promo codes
      if(typeof _appliedBookingCodes !== 'undefined' && _appliedBookingCodes.length > 0 && typeof apiUsePromoCode === 'function'){
        var _fullBase = _currentPaymentAmount + (typeof discountAmt !== 'undefined' ? discountAmt : 0);
        for(var _pi=0;_pi<_appliedBookingCodes.length;_pi++){
          if(_appliedBookingCodes[_pi].type==='promo' && _appliedBookingCodes[_pi].code){
            try { apiUsePromoCode(_appliedBookingCodes[_pi].code, bkId, _fullBase); } catch(pe){}
          }
        }
      } else if(typeof appliedCode !== 'undefined' && appliedCode && typeof apiUsePromoCode === 'function'){
        try { apiUsePromoCode(appliedCode, bkId, _currentPaymentAmount + (typeof discountAmt !== 'undefined' ? discountAmt : 0)); } catch(pe){}
      }
      // Auto-generate docs (non-blocking)
      try {
        if(typeof apiGenerateAdvanceInvoice === 'function') apiGenerateAdvanceInvoice(bkId, _currentPaymentAmount, 'booking').catch(function(){});
        if(typeof apiGeneratePaymentReceipt === 'function') apiGeneratePaymentReceipt(bkId, _currentPaymentAmount, 'booking').catch(function(){});
        if(typeof apiAutoGenerateBookingDocs === 'function') apiAutoGenerateBookingDocs(bkId).catch(function(){});
      } catch(de){}
      var sucResId = document.getElementById('suc-res-id');
      if(sucResId) sucResId.textContent = '#' + bkId.substr(-8).toUpperCase();
      if(typeof initMotoAvailability === 'function') initMotoAvailability();
      if(typeof syncGlobalOcc === 'function') syncGlobalOcc();
      showT('✓',_t('pay').paid||'Zaplaceno',_t('pay').resConfirmed||'Rezervace potvrzena');
      goTo('s-success');
      if(typeof promptPostPaymentScan === 'function') setTimeout(function(){ promptPostPaymentScan(); }, 1200);
      return;
    }
    if(r.data.status === 'cancelled'){
      _stripeCheckoutOpened = false;
      _stripeCheckoutBookingId = null;
      _currentBookingId = null;
      showT('✗','Rezervace zrušena','Rezervace byla automaticky zrušena');
      goTo('s-res');
      if(typeof renderMyReservations === 'function') renderMyReservations();
      return;
    }
    // Still pending — show waiting UI
    _lockPaymentScreen('⏳ Čekám na potvrzení platby...');
  } catch(e){ console.warn('[PAY] _checkPaymentAfterStripe err:', e); }
}

// Save individual extras from booking form checkboxes into booking_extras table
var _EXTRA_MAP = {
  'extra-spolujezdec': 'Výbava spolujezdce',
  'extra-boty-ridic': 'Boty řidiče',
  'extra-boty-spolu': 'Boty spolujezdce'
};
async function _saveBookingExtras(bookingId){
  if(!window.supabase) return;
  var labels = document.querySelectorAll('#s-booking label[id^="extra-"]');
  if(!labels || !labels.length) return;
  var checked = [];
  labels.forEach(function(lbl){
    var cb = lbl.querySelector('input[type=checkbox]');
    if(cb && cb.checked){
      var price = parseInt(lbl.getAttribute('data-price')) || 0;
      var name = _EXTRA_MAP[lbl.id] || lbl.id;
      checked.push({name: name, price: price});
    }
  });
  if(!checked.length) return;
  // Insert booking_extras with name and unit_price
  for(var i = 0; i < checked.length; i++){
    var ext = checked[i];
    var catId = null;
    var cat = await window.supabase.from('extras_catalog').select('id').eq('name', ext.name).limit(1).maybeSingle();
    if(cat && cat.data) catId = cat.data.id;
    await window.supabase.from('booking_extras').insert({
      booking_id: bookingId,
      extra_id: catId,
      name: ext.name,
      unit_price: ext.price,
      quantity: 1
    });
  }
}

