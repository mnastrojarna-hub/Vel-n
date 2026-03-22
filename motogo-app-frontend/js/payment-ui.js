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
async function _checkPaymentAfterStripe(){
  if(!_stripeCheckoutOpened || !_stripeCheckoutBookingId) return;
  if(!window.supabase) return;
  try {
    var r = await window.supabase.from('bookings').select('status, payment_status').eq('id', _stripeCheckoutBookingId).single();
    if(!r.data) return;
    if(r.data.payment_status === 'paid'){
      // Platba potvrzena webhookem
      var bkId = _stripeCheckoutBookingId;
      _stripeCheckoutOpened = false;
      _stripeCheckoutBookingId = null;
      if(_isRestorePayment){
        _isRestorePayment = false;
        _currentBookingId = null;
        showT('✓',_t('pay').paid||'Zaplaceno',_t('res').restored||'Rezervace obnovena');
        goTo('s-res');
        if(typeof renderMyReservations === 'function') renderMyReservations();
        return;
      }
      if(_isEditPayment){
        _isEditPayment = false;
        _editPaymentBookingId = null;
        _cachedBookings = null;
        showT('✓',_t('pay').paid||'Zaplaceno',_t('res').changesSavedShort||'Změny uloženy');
        if(typeof renderMyReservations === 'function') renderMyReservations();
        if(typeof openResDetailById === 'function') openResDetailById(bkId);
        else goTo('s-res');
        return;
      }
      // Normal booking payment
      if(_paymentTimeout){ clearTimeout(_paymentTimeout); _paymentTimeout = null; }
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
  // Find or create extras_catalog entries, then insert booking_extras
  for(var i = 0; i < checked.length; i++){
    var ext = checked[i];
    var cat = await window.supabase.from('extras_catalog').select('id').eq('name', ext.name).limit(1).single();
    var catId = null;
    if(cat.data) { catId = cat.data.id; }
    else {
      var ins = await window.supabase.from('extras_catalog').insert({name: ext.name, price: ext.price}).select('id').single();
      if(ins.data) catId = ins.data.id;
    }
    if(catId){
      await window.supabase.from('booking_extras').insert({booking_id: bookingId, extra_id: catId});
    }
  }
}

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

    // Validate profile completeness before payment
    var profile = typeof apiFetchProfile === 'function' ? await apiFetchProfile() : null;
    if(profile){
      var isKidsBike = bookingMoto && bookingMoto.cat === 'detske';
      var missing = [];
      if(!profile.full_name || !profile.full_name.trim()) missing.push('Jméno a příjmení');
      if(!profile.phone || !profile.phone.trim()) missing.push('Telefon');
      if(!profile.street || !profile.street.trim()) missing.push('Ulice');
      if(!profile.city || !profile.city.trim()) missing.push('Město');
      if(!profile.zip || !profile.zip.trim()) missing.push('PSČ');
      if(!isKidsBike){
        if(!profile.license_number || !profile.license_number.trim()) missing.push('Číslo ŘP');
      }
      if(missing.length > 0){
        showT('⚠️','Vyplňte osobní údaje','Chybí: ' + missing.join(', '));
        goTo('s-profile');
        return;
      }
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

    // Check for overlapping reservations (date-based — allows future bookings alongside current ones)
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
      } catch(e){ console.error('[PAY] moto lookup failed:', e); }
    }
    if(!motoId){
      showT('✗', 'Chyba', 'Nepodařilo se identifikovat motorku. Zkuste to znovu.');
      return;
    }

    // Check license validity for the entire rental period
    if(typeof apiCheckLicenseForMoto === 'function'){
      var licCheck = await apiCheckLicenseForMoto(motoId, endDate);
      if(!licCheck.allowed){
        showT('✗', _t('pay').licenseTitle||'Řidičský průkaz', licCheck.reason || (_t('pay').licenseInvalid||'Nemáte platný ŘP pro tuto motorku'));
        return;
      }
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

    // Determine pickup/return method and address (composed from separate fields)
    var pickupMethod = (typeof pickupDelivFee !== 'undefined' && pickupDelivFee > 0) ? 'delivery' : 'branch';
    var returnMethod = (typeof returnDelivFee !== 'undefined' && returnDelivFee > 0) ? 'delivery' : 'branch';
    var pickupAddr = '', returnAddr = '';
    var pInp = document.getElementById('pickup-addr-input');
    var pCity = document.getElementById('pickup-city');
    var pZip = document.getElementById('pickup-zip');
    if(pInp && pInp.value.trim()){
      pickupAddr = [pInp.value.trim(), pCity?pCity.value.trim():'', pZip?pZip.value.trim():''].filter(Boolean).join(', ');
    }
    var rInp = document.getElementById('return-addr-input');
    var rCity = document.getElementById('return-city');
    var rZip = document.getElementById('return-zip');
    if(rInp && rInp.value.trim()){
      returnAddr = [rInp.value.trim(), rCity?rCity.value.trim():'', rZip?rZip.value.trim():''].filter(Boolean).join(', ');
    }

    // Create booking (YYYY-MM-DD format to avoid timezone shift)
    var _toDateStr = function(d){ return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'); };
    var result = await apiCreateBooking({
      moto_id: motoId,
      start_date: _toDateStr(startDate),
      end_date: _toDateStr(endDate),
      pickup_time: pickupTime,
      total_price: totalPrice,
      extras_price: extraTotal || 0,
      delivery_fee: deliveryFee || 0,
      discount_amount: discountAmt || 0,
      discount_code: appliedCode || null,
      pickup_method: pickupMethod,
      pickup_address: pickupAddr || null,
      return_method: returnMethod,
      return_address: returnAddr || null,
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

    // Save individual extras to booking_extras table (non-blocking)
    _saveBookingExtras(result.booking.id).catch(function(e){ console.warn('[PAY] Extras save err:', e); });

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
    // Spustit odpočet — storno řeší backend cron, frontend jen zobrazí čas a refreshne stav
    _paymentDeadline = Date.now() + _PAYMENT_TIMEOUT_MS;
    _startPaymentCountdown();
    goTo('s-payment');
  } catch(e){ console.error('proceedToPayment error:', e); showT('✗',_t('common').error||'Chyba',_t('pay').createFailed||'Nepodařilo se vytvořit rezervaci'); }
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
        _stripeCheckoutBookingId = _currentBookingId;
        _lockPaymentScreen('↗ Platební brána otevřena...');
        _openExternalUrl(result.checkout_url);
        showT('ℹ️',_t('pay').payBtn||'Platba','Otevřena platební brána Stripe');
        return;
      }

      if(result.success){
        // Payment succeeded – clear timeout and counter
        _paymentAttempts = 0;
        if(_paymentTimeout){ clearTimeout(_paymentTimeout); _paymentTimeout = null; }

        // Verify booking status was actually updated (edge fn may silently fail)
        if(_currentBookingId && window.supabase){
          try {
            var _vb = await window.supabase.from('bookings').select('status, payment_status').eq('id', _currentBookingId).single();
            if(_vb.data && _vb.data.status === 'pending'){
              console.warn('[PAY] Booking still pending after payment — forcing status update via RPC');
              await window.supabase.rpc('confirm_payment', {p_booking_id: _currentBookingId, p_method: _currentPaymentMethod || 'card'});
            }
          } catch(ve){ console.warn('[PAY] Status verify err:', ve); }
        }

        // Zaloguj promo k\u00f3d pokud byl pou\u017eit
        if(typeof appliedCode !== 'undefined' && appliedCode && typeof apiUsePromoCode === 'function'){
          try {
            apiUsePromoCode(appliedCode, _currentBookingId, _currentPaymentAmount + (typeof discountAmt !== 'undefined' ? discountAmt : 0));
          } catch(pe){ console.warn('[PAY] Promo tracking:', pe); }
        }

        // AUTO-GENERATE: Advance invoice + Payment receipt + Contract + VOP
        if(_currentBookingId){
          try {
            var _zfOk = false, _dpOk = false;
            if(typeof apiGenerateAdvanceInvoice === 'function'){
              var _zfRes = await apiGenerateAdvanceInvoice(_currentBookingId, _currentPaymentAmount, 'booking');
              _zfOk = !_zfRes.error;
              if(_zfRes.error) console.error('[PAY] ZF generation failed:', _zfRes.error);
            }
            if(typeof apiGeneratePaymentReceipt === 'function'){
              var _dpRes = await apiGeneratePaymentReceipt(_currentBookingId, _currentPaymentAmount, 'booking');
              _dpOk = !_dpRes.error;
              if(_dpRes.error) console.error('[PAY] DP generation failed:', _dpRes.error);
            }
            if(!_zfOk || !_dpOk) console.warn('[PAY] Invoice auto-gen: ZF=' + _zfOk + ' DP=' + _dpOk);
            if(typeof apiAutoGenerateBookingDocs === 'function'){
              await apiAutoGenerateBookingDocs(_currentBookingId).catch(function(e){ console.warn('[PAY] Docs err:', e); });
            }
          } catch(de){ console.error('[PAY] Doc gen err:', de); }
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
        // Uživatel klikne na tlačítko "Moje rezervace" ručně — žádný auto-redirect
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
  } catch(e){ console.error('doPayment error:', e); showT('✗',_t('common').error||'Chyba',_t('pay').processingError||'Chyba při zpracování platby'); }
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

