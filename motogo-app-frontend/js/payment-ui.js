// ===== PAYMENT-UI.JS – Payment flow & booking confirmation =====

var _currentBookingId = null;
var _currentPaymentAmount = 0;
var _currentPaymentMethod = 'card';
var _paymentAttempts = 0;
var _paymentTimeout = null;
var _MAX_PAYMENT_ATTEMPTS = 3;
var _PAYMENT_TIMEOUT_MS = 300000; // 5 minutes
var _isRestorePayment = false;
var _isEditPayment = false;
var _editPaymentBookingId = null;

// Called from booking form "Pokračovat k platbě"
async function proceedToPayment(){
  try {
    // Validate consents
    var vop = document.getElementById('consent-vop');
    var gdpr = document.getElementById('consent-gdpr');
    if(!vop || !vop.checked || !gdpr || !gdpr.checked){
      showT('⚠️',_t('pay').consents||'Souhlasy',_t('pay').checkVOP||'Zaškrtněte souhlas s VOP a GDPR');
      return;
    }

    // Check login
    var session = await _getSession();
    if(!session){
      showT('⚠️',_t('pay').loginTitle||'Přihlášení',_t('pay').loginRequired||'Pro rezervaci se musíte přihlásit');
      goTo('s-login');
      return;
    }

    // Get booking data
    if(!bookingMoto){
      showT('⚠️',_t('pay').motoLabel||'Motorka',_t('pay').selectMoto||'Vyberte motorku');
      return;
    }

    // Get dates – from booking form or detail
    var startDate, endDate;
    if(typeof bOd !== 'undefined' && bOd && typeof bDo !== 'undefined' && bDo){
      startDate = new Date(bOd.y, bOd.m, bOd.d);
      endDate = new Date(bDo.y, bDo.m, bDo.d);
    } else if(typeof dOd !== 'undefined' && dOd && typeof dDo !== 'undefined' && dDo){
      startDate = new Date(dOd.y, dOd.m, dOd.d);
      endDate = new Date(dDo.y, dDo.m, dDo.d);
    } else {
      showT('\u26a0\ufe0f',_t('pay').dateLabel||'Term\u00edn',_t('pay').selectDates||'Vyberte datum vyzvednut\u00ed a vr\u00e1cen\u00ed');
      return;
    }

    if(!startDate || !endDate || isNaN(startDate.getTime())){
      showT('\u26a0\ufe0f',_t('pay').dateLabel||'Term\u00edn',_t('pay').selectDates||'Vyberte datum vyzvednut\u00ed a vr\u00e1cen\u00ed');
      return;
    }

    // Block past dates
    var today=new Date();today.setHours(0,0,0,0);
    startDate.setHours(0,0,0,0);endDate.setHours(0,0,0,0);
    if(startDate<today){
      showT('\u26a0\ufe0f',_t('pay').dateLabel||'Datum',_t('pay').pastDate||'Nelze rezervovat v minulosti');
      return;
    }

    // Check for overlapping reservations
    if(typeof apiCheckBookingOverlap === 'function'){
      var overlapCheck = await apiCheckBookingOverlap(startDate.toISOString(), endDate.toISOString());
      if(overlapCheck.overlap){
        var cf = overlapCheck.conflicting;
        var cfName = cf.moto_name || 'motorka';
        var cfFrom = _fmtDatePayment(cf.start_date);
        var cfTo = _fmtDatePayment(cf.end_date);
        showT('\u26a0\ufe0f',
          _t('pay').overlapTitle||'Termín obsazen',
          (_t('pay').overlapMsg||'Již máte rezervaci v tomto termínu')+': '+cfName+' ('+cfFrom+' – '+cfTo+'). '+(_t('pay').overlapHint||'Zvolte jiný termín nebo upravte stávající rezervaci.')
        );
        return;
      }
    }

    // Získej UUID z _db (enrichMOTOS), nebo fallback lookup v Supabase
    var motoId = null;
    if(bookingMoto._db && bookingMoto._db.id){
      motoId = bookingMoto._db.id;
    } else if(window.supabase && bookingMoto.name){
      // enrichMOTOS ještě nedoběhlo — najdi UUID podle názvu
      try {
        var _lookup = await window.supabase
          .from('motorcycles')
          .select('id')
          .ilike('model', '%' + bookingMoto.name.split(' ').slice(0,3).join('%') + '%')
          .eq('status', 'active')
          .limit(1)
          .single();
        if(_lookup.data) motoId = _lookup.data.id;
      } catch(e){ }
    }
    if(!motoId){
      showT('✗', 'Chyba', 'Nepodařilo se identifikovat motorku. Zkuste to znovu.');
      return;
    }

    var pickupTime = (document.getElementById('booking-pickup-time') || {}).value || '09:00';

    // Calculate total
    var basePrice = 0;
    if(typeof calcTotalPrice === 'function'){
      basePrice = calcTotalPrice(bookingMoto, startDate, endDate);
    } else {
      basePrice = await apiCalcBookingPrice(motoId, startDate.toISOString(), endDate.toISOString());
    }
    var totalPrice = basePrice + (extraTotal || 0) + (deliveryFee || 0) - (discountAmt || 0);

    // Read selected pickup time from time picker
    var pickupTimeEl = document.getElementById('booking-time-hour');
    var pickupMinEl = document.getElementById('booking-time-min');
    if(pickupTimeEl && pickupMinEl){
      pickupTime = pickupTimeEl.value + ':' + pickupMinEl.value;
    }

    // Create booking
    var result = await apiCreateBooking({
      moto_id: motoId,
      start_date: startDate.toISOString(),
      end_date: endDate.toISOString(),
      pickup_time: pickupTime,
      total_price: totalPrice,
      extras_price: extraTotal || 0,
      delivery_fee: deliveryFee || 0,
      discount_amount: discountAmt || 0,
      discount_code: appliedCode || null
    });

    if(result.error){
      showT('✗',_t('common').error||'Chyba', result.error);
      return;
    }

    if(!result.booking || !result.booking.id){
      showT('✗',_t('common').error||'Chyba',_t('pay').createFailed||'Rezervace se nepodařila vytvořit');
      return;
    }

    _currentBookingId = result.booking.id;
    _currentPaymentAmount = totalPrice;

    // Update payment screen
    var payBtn = document.getElementById('pay-btn');
    if(payBtn){
      payBtn.textContent = (_t('pay').payBtn||'Zaplatit') + ' ' + totalPrice.toLocaleString('cs-CZ') + ' Kč →';
      payBtn.onclick = function(){ doPayment(); };
    }
    var applePayBtn = document.getElementById('apple-pay-btn');
    if(applePayBtn) applePayBtn.textContent = '🍎 Pay ' + totalPrice.toLocaleString('cs-CZ') + ' Kč';

    _paymentAttempts = 0;
    if(_paymentTimeout) clearTimeout(_paymentTimeout);
    _paymentTimeout = setTimeout(function(){
      if(_currentBookingId){
        _autoCancelUnpaid(_currentBookingId, 'Nezaplaceno do 5 minut (automatické zrušení)');
      }
    }, _PAYMENT_TIMEOUT_MS);
    goTo('s-payment');
  } catch(e){ showT('✗',_t('common').error||'Chyba',_t('pay').createFailed||'Nepodařilo se vytvořit rezervaci'); }
}

// Process payment with 2s delay
function doPayment(){
  try {
    var payBtn = document.getElementById('pay-btn');
    if(payBtn){
      payBtn.textContent = '⏳ ' + (_t('pay').processing||'Zpracování platby...');
      payBtn.disabled = true;
      payBtn.style.opacity = '0.6';
    }

    setTimeout(async function(){
      var result = await apiProcessPayment(_currentBookingId, _currentPaymentAmount, _currentPaymentMethod);

      if(payBtn){
        payBtn.disabled = false;
        payBtn.style.opacity = '1';
      }

      // Stripe Checkout – otevři platební stránku
      if(result.success && result.checkout_url){
        if(window.cordova && window.cordova.InAppBrowser){
          window.cordova.InAppBrowser.open(result.checkout_url, '_system');
        } else {
          window.open(result.checkout_url, '_blank');
        }
        showT('ℹ️',_t('pay').payBtn||'Platba','Otevřena platební brána Stripe');
        if(payBtn) payBtn.textContent = (_t('pay').payBtn||'Zaplatit') + ' ' + _currentPaymentAmount.toLocaleString('cs-CZ') + ' Kč →';
        return;
      }

      if(result.success){
        // Payment succeeded – clear timeout and counter
        _paymentAttempts = 0;
        if(_paymentTimeout){ clearTimeout(_paymentTimeout); _paymentTimeout = null; }
        // Zaloguj promo k\u00f3d pokud byl pou\u017eit
        if(typeof appliedCode !== 'undefined' && appliedCode && typeof apiUsePromoCode === 'function'){
          try {
            apiUsePromoCode(appliedCode, _currentBookingId, _currentPaymentAmount + (typeof discountAmt !== 'undefined' ? discountAmt : 0));
          } catch(pe){ }
        }

        // AUTO-GENERATE: Advance invoice + Payment receipt + Contract + VOP
        if(_currentBookingId){
          try {
            if(typeof apiGenerateAdvanceInvoice === 'function'){
              apiGenerateAdvanceInvoice(_currentBookingId, _currentPaymentAmount, 'booking').catch(function(e){ });
            }
            if(typeof apiGeneratePaymentReceipt === 'function'){
              apiGeneratePaymentReceipt(_currentBookingId, _currentPaymentAmount, 'booking').catch(function(e){ });
            }
            if(typeof apiAutoGenerateBookingDocs === 'function'){
              apiAutoGenerateBookingDocs(_currentBookingId).then(function(){}).catch(function(e){ });
            }
          } catch(de){ }
        }

        // Update success screen
        var sucResId = document.getElementById('suc-res-id');
        if(sucResId && _currentBookingId) sucResId.textContent = '#' + _currentBookingId.substr(-8).toUpperCase();

        var booking = null;
        if(_isSupabaseReady()){
          try {
            var bResult = await supabase.from('bookings').select('*').eq('id',_currentBookingId).single();
            booking = bResult.data;
          } catch(e){}
        }
        if(booking){
          var sucOd = document.getElementById('suc-od');
          if(sucOd) sucOd.textContent = _fmtDatePayment(booking.start_date);
          var sucDo = document.getElementById('suc-do');
          if(sucDo) sucDo.textContent = _fmtDatePayment(booking.end_date);
        }

        var sucMoto = document.querySelector('#s-success .sbi-v');
        if(sucMoto && bookingMoto) sucMoto.textContent = bookingMoto.name;

        // Refresh availability after new booking
        if(typeof initMotoAvailability === 'function') initMotoAvailability();
        if(typeof syncGlobalOcc === 'function') syncGlobalOcc();
        showT('✓',_t('pay').paid||'Zaplaceno',_t('pay').resConfirmed||'Rezervace potvrzena');
        goTo('s-success');
        // Prompt doc scan if not verified
        if(typeof promptPostPaymentScan==='function'){
          setTimeout(function(){ promptPostPaymentScan(); }, 1200);
        }
        // Auto-redirect po 5 sekundách
        setTimeout(function(){
          if(cur === 's-success'){
            if(typeof closePostPayScan==='function') closePostPayScan();
            goTo('s-res');
          }
        }, 5000);
      } else {
        _paymentAttempts++;
        if(_paymentAttempts >= _MAX_PAYMENT_ATTEMPTS){
          _autoCancelUnpaid(_currentBookingId, 'Zamítnuto po ' + _paymentAttempts + ' pokusech');
          return;
        }
        showT('✗',_t('pay').declined||'Platba zamítnuta',(_t('pay').retry||'Zkuste to znovu')+' ('+_paymentAttempts+'/'+_MAX_PAYMENT_ATTEMPTS+')');
        if(payBtn) payBtn.textContent = (_t('pay').payBtn||'Zaplatit') + ' ' + _currentPaymentAmount.toLocaleString('cs-CZ') + ' Kč →';
      }
    }, 2000);
  } catch(e){ showT('✗',_t('common').error||'Chyba',_t('pay').processingError||'Chyba při zpracování platby'); }
}

function _fmtDatePayment(iso){
  try {
    var d = new Date(iso);
    return d.getDate() + '. ' + (d.getMonth()+1) + '. ' + d.getFullYear();
  } catch(e){ return '—'; }
}

async function _autoCancelUnpaid(bookingId, reason){
  if(_paymentTimeout){ clearTimeout(_paymentTimeout); _paymentTimeout = null; }
  try {
    if(window.supabase && bookingId){
      // Restore any applied voucher codes back to 'active' so they can be reused
      if(appliedCode){
        var codes = appliedCode.split(',');
        for(var ci = 0; ci < codes.length; ci++){
          var c = codes[ci].trim();
          if(!c) continue;
          try {
            await window.supabase.from('vouchers')
              .update({ status: 'active', redeemed_at: null, redeemed_by: null, booking_id: null, updated_at: new Date().toISOString() })
              .eq('code', c).eq('status', 'redeemed');
          } catch(ve){ }
        }
      }
      await window.supabase.from('bookings').update({
        status: 'cancelled',
        cancelled_by_source: 'unpaid_auto',
        cancellation_reason: reason || 'Automaticky zrušeno pro nezaplacení',
        cancelled_at: new Date().toISOString()
      }).eq('id', bookingId).eq('payment_status', 'unpaid');
    }
  } catch(e){ }
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

// ===== RESTORE PAYMENT (cancelled reservation → pay to reactivate) =====
function doRestorePayment(bookingId){
  try {
    var payBtn = document.getElementById('pay-btn');
    if(payBtn){
      payBtn.textContent = '⏳ ' + (_t('pay').processing||'Zpracování platby...');
      payBtn.disabled = true;
      payBtn.style.opacity = '0.6';
    }

    setTimeout(async function(){
      var result = await apiProcessPayment(bookingId, _currentPaymentAmount, _currentPaymentMethod);

      if(payBtn){
        payBtn.disabled = false;
        payBtn.style.opacity = '1';
      }

      if(result.success && result.checkout_url){
        if(window.cordova && window.cordova.InAppBrowser){
          window.cordova.InAppBrowser.open(result.checkout_url, '_system');
        } else {
          window.open(result.checkout_url, '_blank');
        }
        showT('ℹ️',_t('pay').payBtn||'Platba','Otevřena platební brána');
        if(payBtn) payBtn.textContent = (_t('pay').payBtn||'Zaplatit') + ' ' + _currentPaymentAmount.toLocaleString('cs-CZ') + ' Kč →';
        return;
      }

      if(result.success){
        // Confirm restore: set booking to active + paid
        if(typeof apiConfirmRestoreBooking === 'function'){
          await apiConfirmRestoreBooking(bookingId);
        }

        // Auto-generate advance invoice + payment receipt + docs for restored booking
        if(typeof apiGenerateAdvanceInvoice === 'function'){
          apiGenerateAdvanceInvoice(bookingId, _currentPaymentAmount, 'restore').catch(function(e){ });
        }
        if(typeof apiGeneratePaymentReceipt === 'function'){
          apiGeneratePaymentReceipt(bookingId, _currentPaymentAmount, 'restore').catch(function(e){ });
        }
        if(typeof apiAutoGenerateBookingDocs === 'function'){
          apiAutoGenerateBookingDocs(bookingId).catch(function(e){ });
        }

        _isRestorePayment = false;
        _currentBookingId = null;
        showT('✓',_t('pay').paid||'Zaplaceno',_t('res').restored||'Rezervace obnovena');
        goTo('s-res');
        if(typeof renderMyReservations === 'function') renderMyReservations();
      } else {
        _paymentAttempts++;
        if(_paymentAttempts >= _MAX_PAYMENT_ATTEMPTS){
          _isRestorePayment = false;
          _currentBookingId = null;
          showT('✗',_t('pay').declined||'Platba zamítnuta','Platba se nezdařila. Rezervace zůstává zrušená.');
          goTo('s-res');
          return;
        }
        showT('✗',_t('pay').declined||'Platba zamítnuta',(_t('pay').retry||'Zkuste to znovu')+' ('+_paymentAttempts+'/'+_MAX_PAYMENT_ATTEMPTS+')');
        if(payBtn) payBtn.textContent = (_t('pay').payBtn||'Zaplatit') + ' ' + _currentPaymentAmount.toLocaleString('cs-CZ') + ' Kč →';
      }
    }, 2000);
  } catch(e){ }
}

// ===== EDIT PAYMENT (extend/shorten booking → pay difference) =====
function doEditPayment(bookingId, amount, changes){
  try {
    var payBtn = document.getElementById('pay-btn');
    if(payBtn){
      payBtn.textContent = '⏳ ' + (_t('pay').processing||'Zpracování platby...');
      payBtn.disabled = true;
      payBtn.style.opacity = '0.6';
    }

    setTimeout(async function(){
      var result = await apiProcessPayment(bookingId, amount, _currentPaymentMethod);

      if(payBtn){
        payBtn.disabled = false;
        payBtn.style.opacity = '1';
      }

      if(result.success && result.checkout_url){
        if(window.cordova && window.cordova.InAppBrowser){
          window.cordova.InAppBrowser.open(result.checkout_url, '_system');
        } else {
          window.open(result.checkout_url, '_blank');
        }
        return;
      }

      if(result.success){
        // Apply the booking changes after successful payment
        if(changes && typeof apiModifyBooking === 'function'){
          await apiModifyBooking(bookingId, changes);
        }

        // Auto-generate advance invoice + payment receipt for the edit payment
        if(typeof apiGenerateAdvanceInvoice === 'function'){
          apiGenerateAdvanceInvoice(bookingId, amount, 'edit').catch(function(e){ });
        }
        if(typeof apiGeneratePaymentReceipt === 'function'){
          apiGeneratePaymentReceipt(bookingId, amount, 'edit').catch(function(e){ });
        }

        _isEditPayment = false;
        _editPaymentBookingId = null;
        showT('✓',_t('pay').paid||'Zaplaceno',_t('res').changesSavedShort||'Změny uloženy');
        // Invalidate cache and refresh
        _cachedBookings = null;
        if(typeof renderMyReservations === 'function') renderMyReservations();
        // Re-open updated detail immediately
        if(typeof openResDetailById === 'function'){
          openResDetailById(bookingId);
        } else {
          goTo('s-res');
        }
      } else {
        _paymentAttempts++;
        if(_paymentAttempts >= _MAX_PAYMENT_ATTEMPTS){
          _isEditPayment = false;
          showT('✗',_t('pay').declined||'Platba zamítnuta','Změny nebyly aplikovány.');
          goTo('s-res');
          return;
        }
        showT('✗',_t('pay').declined||'Platba zamítnuta',(_t('pay').retry||'Zkuste to znovu')+' ('+_paymentAttempts+'/'+_MAX_PAYMENT_ATTEMPTS+')');
        if(payBtn) payBtn.textContent = (_t('pay').payBtn||'Zaplatit') + ' ' + amount.toLocaleString('cs-CZ') + ' Kč →';
      }
    }, 2000);
  } catch(e){ }
}

// Payment method selection (existing selP function enhancement)
function selP(method){
  try {
    _currentPaymentMethod = method;
    var cards = ['card','apple'];
    cards.forEach(function(c){
      var pm = document.getElementById('pm-'+c);
      var pmr = document.getElementById('pmr-'+c);
      var pmd = document.getElementById('pmd-'+c);
      if(pm) pm.classList.toggle('sel', c===method);
      if(pmr) pmr.classList.toggle('on', c===method);
      if(pmd) pmd.classList.toggle('open', c===method);
    });
  } catch(e){ }
}
