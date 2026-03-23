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
        _isEditPayment = true;
        _editPaymentBookingId = bookingId;
        // Save edit changes for after payment return
        window._pendingEditChanges = changes;
        _lockPaymentScreen('↗ Platební brána otevřena...');
        _openExternalUrl(result.checkout_url);
        showT('ℹ️',_t('pay').payBtn||'Platba','Otevřena platební brána');
        return;
      }

      // Stripe nevrátilo checkout URL — chyba
      {
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
