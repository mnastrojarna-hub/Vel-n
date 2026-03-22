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
        _stripeCheckoutBookingId = bookingId;
        _lockPaymentScreen('↗ Platební brána otevřena...');
        _openExternalUrl(result.checkout_url);
        showT('ℹ️',_t('pay').payBtn||'Platba','Otevřena platební brána');
        return;
      }

      if(result.success){
        // Confirm restore: set booking to active + paid
        if(typeof apiConfirmRestoreBooking === 'function'){
          await apiConfirmRestoreBooking(bookingId);
        }

        // Auto-generate advance invoice + payment receipt + docs for restored booking
        try {
          if(typeof apiGenerateAdvanceInvoice === 'function'){
            var _zfR = await apiGenerateAdvanceInvoice(bookingId, _currentPaymentAmount, 'restore');
            if(_zfR.error) console.error('[PAY] Restore ZF failed:', _zfR.error);
          }
          if(typeof apiGeneratePaymentReceipt === 'function'){
            var _dpR = await apiGeneratePaymentReceipt(bookingId, _currentPaymentAmount, 'restore');
            if(_dpR.error) console.error('[PAY] Restore DP failed:', _dpR.error);
          }
          if(typeof apiAutoGenerateBookingDocs === 'function'){
            await apiAutoGenerateBookingDocs(bookingId).catch(function(e){ console.warn('[PAY] Docs err:', e); });
          }
        } catch(de){ console.error('[PAY] Restore doc gen err:', de); }

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
  } catch(e){ console.error('doRestorePayment error:', e); }
}

