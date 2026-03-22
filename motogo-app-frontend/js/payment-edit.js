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
      var result = await apiProcessPayment(bookingId, amount, _currentPaymentMethod, {type: 'extension'});

      if(payBtn){
        payBtn.disabled = false;
        payBtn.style.opacity = '1';
      }

      if(result.success && result.checkout_url){
        _stripeCheckoutBookingId = bookingId;
        _lockPaymentScreen('↗ Platební brána otevřena...');
        _openExternalUrl(result.checkout_url);
        showT('ℹ️',_t('pay').payBtn||'Platba','Otevřena platební brána');
        return;
      }

      if(result.success){
        // Fetch OLD booking state BEFORE modification (for itemized invoice comparison)
        var editCtx = null;
        try {
          var _oldB = await window.supabase.from('bookings')
            .select('*, motorcycles('+(_MOTO_PRICE_COLS||'model, spz, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, price_weekday, price_weekend')+')')
            .eq('id', bookingId).single();
          if(_oldB.data){
            var _ob = _oldB.data, _om = _oldB.data.motorcycles || {};
            // Find original ZF number for reference link
            var _origZf = await window.supabase.from('invoices').select('number')
              .eq('booking_id', bookingId).eq('type','advance').eq('source','booking')
              .order('created_at',{ascending:true}).limit(1);
            editCtx = {
              orig_start: _ob.start_date, orig_end: _ob.end_date,
              orig_moto: _om, orig_total: _ob.total_price || 0,
              orig_extras: _ob.extras_price || 0, orig_delivery: _ob.delivery_fee || 0,
              orig_discount: _ob.discount_amount || 0,
              orig_zf_number: (_origZf.data && _origZf.data.length > 0) ? _origZf.data[0].number : null
            };
          }
        } catch(ec){ console.warn('[PAY] editCtx fetch err:', ec); }

        // Apply the booking changes after successful payment
        var saveOk = true;
        if(changes && typeof apiModifyBooking === 'function'){
          var modRes = await apiModifyBooking(bookingId, changes);
          if(modRes && modRes.error){
            console.error('[PAY] apiModifyBooking failed:', modRes.error);
            showT('⚠️',_t('pay').paid||'Zaplaceno','Platba OK, ale uložení změn selhalo: ' + modRes.error);
            saveOk = false;
          }
        }

        // Auto-generate advance invoice + payment receipt with itemized edit breakdown
        try {
          if(typeof apiGenerateAdvanceInvoice === 'function'){
            var _zfE = await apiGenerateAdvanceInvoice(bookingId, amount, 'edit', editCtx);
            if(_zfE.error) console.error('[PAY] Edit ZF failed:', _zfE.error);
          }
          if(typeof apiGeneratePaymentReceipt === 'function'){
            var _dpE = await apiGeneratePaymentReceipt(bookingId, amount, 'edit', editCtx);
            if(_dpE.error) console.error('[PAY] Edit DP failed:', _dpE.error);
          }
        } catch(de){ console.error('[PAY] Edit doc gen err:', de); }
        // Regenerate contract + VOP with updated booking data (force=true deletes old ones)
        if(typeof apiAutoGenerateBookingDocs === 'function'){
          apiAutoGenerateBookingDocs(bookingId, true).catch(function(e){ console.warn('[PAY] edit docs err:', e); });
        }

        _isEditPayment = false;
        _editPaymentBookingId = null;
        if(saveOk) showT('✓',_t('pay').paid||'Zaplaceno',_t('res').changesSavedShort||'Změny uloženy');
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
  } catch(e){ console.error('doEditPayment error:', e); }
}

// Check Stripe payment on browser/webview tab focus (non-native fallback)
document.addEventListener('visibilitychange', function(){
  if(!document.hidden && _stripeCheckoutOpened && typeof _checkPaymentAfterStripe==='function'){
    _checkPaymentAfterStripe();
  }
});

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
  } catch(e){ console.error('selP error:', e); }
}
