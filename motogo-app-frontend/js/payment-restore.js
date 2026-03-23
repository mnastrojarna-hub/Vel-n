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
        _isRestorePayment = true;
        _lockPaymentScreen('↗ Platební brána otevřena...');
        _openExternalUrl(result.checkout_url);
        showT('ℹ️',_t('pay').payBtn||'Platba','Otevřena platební brána');
        return;
      }

      // Stripe nevrátilo checkout URL — chyba
      {
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

