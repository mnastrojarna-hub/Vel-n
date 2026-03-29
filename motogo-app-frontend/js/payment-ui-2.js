// Called from booking form "Pokračovat k platbě"
async function proceedToPayment(){
  try {
    // Check login
    var session = await _getSession();
    if(!session){
      showT('⚠️',_t('pay').loginTitle||'Přihlášení',_t('pay').loginRequired||'Pro rezervaci se musíte přihlásit');
      goTo('s-login');
      return;
    }

    // Validate profile consents (VOP, GDPR, contract must be agreed in profile)
    var profile = typeof apiFetchProfile === 'function' ? await apiFetchProfile() : null;
    if(profile && (!profile.consent_gdpr || !profile.consent_vop)){
      showT('⚠️','Souhlasy','Pro rezervaci musíte mít odsouhlasené VOP a GDPR v Profilu → Soukromí a souhlasy');
      return;
    }

    // Validate profile completeness before payment
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
        showT('⚠️','Vyplňte osobní údaje','Chybí: ' + missing.join(', ') + '. Doplňte v profilu a vraťte se.');
        // Don't redirect — stay on booking, FAB will be visible
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

    // Check motorcycle availability (prevents same moto being booked twice for same dates)
    if(typeof apiCheckMotoAvailability === 'function' && motoId){
      var motoAvail = await apiCheckMotoAvailability(motoId, startDate.toISOString(), endDate.toISOString());
      if(motoAvail.available === false){
        showT('\u26a0\ufe0f',
          _t('pay').overlapTitle||'Motorka není dostupná',
          'Tato motorka je v daném termínu již rezervována. Zvolte jiný termín nebo jinou motorku.'
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
    // Recalculate discounts at payment time (fixed first, then % on remaining)
    var fullBase = basePrice + (extraTotal || 0) + (deliveryFee || 0);
    if(typeof _recalcBookingDiscounts === 'function'){
      discountAmt = _recalcBookingDiscounts(fullBase);
    }
    var totalPrice = Math.max(0, fullBase - (discountAmt || 0));

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

    // Read GPS coords from address inputs (stored by selectAddr/useMyLocation)
    var pickupLat = pInp && pInp.dataset.lat ? parseFloat(pInp.dataset.lat) : null;
    var pickupLng = pInp && pInp.dataset.lng ? parseFloat(pInp.dataset.lng) : null;
    var returnLat = rInp && rInp.dataset.lat ? parseFloat(rInp.dataset.lat) : null;
    var returnLng = rInp && rInp.dataset.lng ? parseFloat(rInp.dataset.lng) : null;

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
      pickup_lat: pickupLat,
      pickup_lng: pickupLng,
      return_lat: returnLat,
      return_lng: returnLng,
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
    if(totalPrice <= 0){
      // === 100% SLEVA — zobrazit platební obrazovku s potvrzením zdarma ===
      if(payBtn){
        payBtn.textContent = '✅ Potvrdit rezervaci zdarma →';
        payBtn.onclick = function(){ _confirmFreeBooking(result.booking.id, startDate); };
      }
      // Hide card-related elements on payment screen
      setTimeout(function(){
        var cardWrap = document.getElementById('stripe-card-element');
        if(cardWrap) cardWrap.style.display = 'none';
        var cardLabel = document.getElementById('pay-card-label');
        if(cardLabel) cardLabel.style.display = 'none';
        var appleBtn = document.getElementById('apple-pay-btn');
        if(appleBtn) appleBtn.style.display = 'none';
        var savedCard = document.getElementById('pay-saved-card');
        if(savedCard) savedCard.style.display = 'none';
        var freeNote = document.getElementById('pay-free-note');
        if(!freeNote){
          freeNote = document.createElement('div');
          freeNote.id = 'pay-free-note';
          freeNote.style.cssText = 'text-align:center;padding:20px;font-size:14px;font-weight:700;color:var(--gd);background:var(--gp);border:2px solid var(--green);border-radius:var(--rsm);margin:12px 20px;';
          freeNote.textContent = '🎉 Sleva pokrývá celou cenu — platba kartou není potřeba. Klikněte na tlačítko pro potvrzení.';
          var payScreen = document.getElementById('s-payment');
          if(payScreen) payScreen.insertBefore(freeNote, payBtn.parentNode);
        }
      }, 100);
    } else if(payBtn){
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
    // Show saved card preview on payment screen (non-blocking)
    _showSavedCardPreview();
  } catch(e){ console.error('proceedToPayment error:', e); showT('✗',_t('common').error||'Chyba',_t('pay').createFailed||'Nepodařilo se vytvořit rezervaci'); }
}
