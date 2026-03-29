
// Process payment — inline Stripe Payment Element (no redirect)
function doPayment(){
  if(_stripeCheckoutOpened || _inlinePaymentActive) return;
  try {
    var payBtn = document.getElementById('pay-btn');
    if(payBtn){
      payBtn.textContent = '⏳ ' + (_t('pay').processing||'Zpracování platby...');
      payBtn.disabled = true;
      payBtn.style.opacity = '0.6';
    }

    setTimeout(async function(){
      console.log('[PAY] doPayment:', {bookingId: _currentBookingId, amount: _currentPaymentAmount, method: _currentPaymentMethod});
      var result = await apiProcessPayment(_currentBookingId, _currentPaymentAmount, _currentPaymentMethod);
      console.log('[PAY] doPayment result:', result);

      if(payBtn){ payBtn.disabled = false; payBtn.style.opacity = '1'; }

      // 100% sleva — potvrzeno na serveru bez Stripe
      if(result.success && result.free){
        if(typeof _resetBookingDiscount === 'function') _resetBookingDiscount();
        var freeNote = document.getElementById('pay-free-note');
        if(freeNote) freeNote.remove();
        showT('✅','Rezervace potvrzena','Sleva pokrývá celou cenu — platba není potřeba');
        goTo('s-res');
        if(typeof renderMyReservations === 'function') renderMyReservations();
        return;
      }

      // Inline Payment Element — platba přímo v appce
      if(result.success && result.client_secret){
        _stripeCheckoutBookingId = _currentBookingId;
        showStripeInlinePayment(result.client_secret, _currentPaymentAmount, {
          bookingId: _currentBookingId,
          onSuccess: function(){ _onInlinePaymentSuccess(_currentBookingId); },
          onCancel: function(){ _onInlinePaymentCancel(); }
        });
        if(payBtn) payBtn.textContent = (_t('pay').payBtn||'Zaplatit') + ' ' + _currentPaymentAmount.toLocaleString('cs-CZ') + ' Kč →';
        return;
      }

      // Fallback: Stripe Checkout redirect
      if(result.success && result.checkout_url){
        _stripeCheckoutBookingId = _currentBookingId;
        _lockPaymentScreen('↗ Platební brána otevřena...');
        _openExternalUrl(result.checkout_url);
        return;
      }

      _paymentAttempts++;
      var errDetail = (result && result.error) ? result.error : '';
      if(_paymentAttempts >= _MAX_PAYMENT_ATTEMPTS){
        _autoCancelUnpaid(_currentBookingId, 'Zamítnuto po ' + _paymentAttempts + ' pokusech');
        return;
      }
      showT('✗',_t('pay').declined||'Platba zamítnuta', errDetail || ((_t('pay').retry||'Zkuste to znovu')+' ('+_paymentAttempts+'/'+_MAX_PAYMENT_ATTEMPTS+')'));
      if(payBtn) payBtn.textContent = (_t('pay').payBtn||'Zaplatit') + ' ' + _currentPaymentAmount.toLocaleString('cs-CZ') + ' Kč →';
    }, 1500);
  } catch(e){ console.error('doPayment error:', e); showT('✗',_t('common').error||'Chyba',_t('pay').processingError||'Chyba při zpracování platby'); }
}

// === 100% SLEVA — potvrzení bez Stripe ===
async function _confirmFreeBooking(bookingId, startDate){
  var btn = document.getElementById('pay-btn');
  if(btn){ btn.disabled = true; btn.textContent = '⏳ Potvrzuji...'; btn.style.opacity = '0.6'; }
  try {
    var confirmRes = await window.supabase.rpc('confirm_payment', {
      p_booking_id: bookingId,
      p_method: 'free'
    });
    if(confirmRes.error){
      // Fallback: přímý update
      await window.supabase.from('bookings').update({
        payment_status: 'paid',
        status: (startDate && startDate <= new Date()) ? 'active' : 'reserved',
        confirmed_at: new Date().toISOString()
      }).eq('id', bookingId);
    }
    // Generate documents (non-blocking)
    try {
      if(typeof apiAutoGenerateBookingDocs === 'function') apiAutoGenerateBookingDocs(bookingId).catch(function(){});
    } catch(e){}
    if(typeof _resetBookingDiscount === 'function') _resetBookingDiscount();
    // Cleanup free note
    var freeNote = document.getElementById('pay-free-note');
    if(freeNote) freeNote.remove();
    showT('✅','Rezervace potvrzena','Sleva pokrývá celou cenu — platba není potřeba');
    goTo('s-res');
    if(typeof renderMyReservations === 'function') renderMyReservations();
  } catch(e){
    console.error('[PAY] _confirmFreeBooking error:', e);
    if(btn){ btn.disabled = false; btn.textContent = '✅ Potvrdit rezervaci zdarma →'; btn.style.opacity = '1'; }
    showT('✗','Chyba','Nepodařilo se potvrdit rezervaci: ' + (e.message || ''));
  }
}

// Handle inline payment success — same logic as _checkPaymentAfterStripe but immediate
function _onInlinePaymentSuccess(bookingId){
  _stripeCheckoutOpened = false;
  _stripeCheckoutBookingId = null;
  var bkId = bookingId || _currentBookingId;

  if(_isRestorePayment){
    _isRestorePayment = false;
    _currentBookingId = null;
    if(typeof apiConfirmRestoreBooking === 'function') apiConfirmRestoreBooking(bkId).catch(function(){});
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
    var pendingChanges = window._pendingEditChanges || null;
    if(pendingChanges && typeof apiModifyBooking === 'function'){
      apiModifyBooking(bkId, pendingChanges).catch(function(e){ console.warn('[PAY] Edit apply err:', e); });
      window._pendingEditChanges = null;
    }
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
}

// Handle inline payment cancel — user closed the overlay, show FAB
function _onInlinePaymentCancel(){
  _stripeCheckoutOpened = false;
  _stripeCheckoutBookingId = null;
  // FAB already detects pending unpaid bookings — just navigate away
  showT('ℹ️','Platba přerušena','Můžete pokračovat přes tlačítko dole');
}

function _parseDate(str){
  if(!str) return null;
  if(typeof str==='string' && str.length===10) str += 'T12:00:00';
  return new Date(str);
}

function _fmtDatePayment(iso){
  try {
    var d = _parseDate(iso);
    if(!d || isNaN(d.getTime())) return '—';
    return d.getDate() + '. ' + (d.getMonth()+1) + '. ' + d.getFullYear();
  } catch(e){ return '—'; }
}

// Show saved card preview on payment screen
async function _showSavedCardPreview(){
  var el = document.getElementById('pay-saved-card');
  if(!el || typeof apiFetchPaymentMethods !== 'function') return;
  try {
    var r = await apiFetchPaymentMethods();
    if(!r.success || !r.methods || r.methods.length === 0) return;
    var def = r.methods.find(function(m){ return m.is_default; }) || r.methods[0];
    var brandIcons = {visa:'VISA',mastercard:'MC',amex:'AMEX'};
    var brand = brandIcons[def.brand] || def.brand.toUpperCase();
    var exp = (def.exp_month < 10 ? '0' : '') + def.exp_month + '/' + String(def.exp_year).slice(-2);
    var name = def.holder_name ? ' · ' + def.holder_name : '';
    el.style.display = 'block';
    el.innerHTML = '<div style="background:var(--gp);border:2px solid var(--green);border-radius:var(--rsm);padding:10px 14px;text-align:left;display:flex;align-items:center;gap:10px;">' +
      '<div style="font-size:22px;">💳</div>' +
      '<div><div style="font-size:13px;font-weight:700;">•••• ' + def.last4 + ' <span style="font-size:10px;color:var(--g400);">' + brand + '</span></div>' +
      '<div style="font-size:10px;color:var(--g400);">' + exp + name + '</div></div>' +
      '<div style="margin-left:auto;font-size:10px;font-weight:700;color:var(--green);">Předvyplněno</div></div>';
  } catch(e){}
}

var _paymentDeadline = 0;
var _countdownInterval = null;

// Odpočet "Zbývá X minut na zaplacení" — storno řeší výhradně backend cron
function _startPaymentCountdown(){
  if(_countdownInterval) clearInterval(_countdownInterval);
  _countdownInterval = setInterval(function(){
    var remaining = _paymentDeadline - Date.now();
    var el = document.getElementById('pay-countdown');
    if(remaining <= 0){
      clearInterval(_countdownInterval);
      _countdownInterval = null;
      if(el) el.textContent = 'Čas na zaplacení vypršel';
      // Refreshni stav z DB — backend cron už mohl booking zrušit
      _refreshBookingStatus();
      return;
    }
    var min = Math.floor(remaining / 60000);
    var sec = Math.floor((remaining % 60000) / 1000);
    if(el) el.textContent = 'Zbývá ' + min + ':' + String(sec).padStart(2,'0') + ' na zaplacení';
  }, 1000);
}

// Po vypršení odpočtu refreshni stav bookingu z DB
async function _refreshBookingStatus(){
  if(!_currentBookingId || !window.supabase) return;
  try {
    var r = await window.supabase.from('bookings').select('status, payment_status').eq('id', _currentBookingId).single();
    if(r.data && r.data.status === 'cancelled'){
      _stripeCheckoutOpened = false;
      _stripeCheckoutBookingId = null;
      appliedCode = null;
      _appliedPromoId = null;
      _appliedCodes = [];
      discountAmt = 0;
      _currentBookingId = null;
      _paymentAttempts = 0;
      showT('✗', _t('pay').declined||'Rezervace zrušena', 'Rezervace byla automaticky zrušena pro nezaplacení');
      goTo('s-res');
      if(typeof renderMyReservations === 'function') renderMyReservations();
    }
  } catch(e){ console.warn('[PAY] Status refresh err:', e); }
}

