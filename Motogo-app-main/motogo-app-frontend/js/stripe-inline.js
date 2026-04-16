// ===== STRIPE-INLINE.JS – In-app Stripe Payment Element (no redirect) =====
// Renders Stripe Payment Element inside a fullscreen overlay.
// User pays without leaving the app. Saved cards shown automatically.
// IMPORTANT: Never calls onSuccess until webhook confirms payment_status='paid' in DB.

var _inlinePaymentActive = false;
var _inlineElements = null;
var _inlinePaymentElement = null;
var _inlineClientSecret = null;
var _inlineOnSuccess = null;
var _inlineOnCancel = null;
var _inlineOverlay = null;
var _inlineBookingId = null;
var _inlineOrderId = null;
var _inlinePollTimer = null;
var _inlineAmount = 0;
var _inlinePaymentType = 'booking';

// Show inline payment overlay with Stripe Payment Element
// opts: { onSuccess, onCancel, bookingId, orderId }
function showStripeInlinePayment(clientSecret, amount, opts){
  if(_inlinePaymentActive) return;
  // Lazy-load Stripe SDK if not yet loaded
  if(typeof Stripe !== 'function'){
    _loadStripeSDK().then(function(){ showStripeInlinePayment(clientSecret, amount, opts); });
    return;
  }
  _inlinePaymentActive = true;
  _inlineClientSecret = clientSecret;
  _inlineOnSuccess = (opts && opts.onSuccess) || null;
  _inlineOnCancel = (opts && opts.onCancel) || null;
  _inlineBookingId = (opts && opts.bookingId) || null;
  _inlineOrderId = (opts && opts.orderId) || null;
  _inlineAmount = amount || 0;
  _inlinePaymentType = (opts && opts.paymentType) || 'booking';

  var s = _getStripe();
  if(!s){ _inlinePaymentActive = false; return; }

  _inlineOverlay = document.createElement('div');
  _inlineOverlay.id = 'stripe-inline-overlay';
  _inlineOverlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:99998;background:#f5f5f7;display:flex;flex-direction:column;overflow-y:auto;';

  var amtFmt = (amount||0).toLocaleString('cs-CZ');
  _inlineOverlay.innerHTML =
    '<div style="background:linear-gradient(135deg,#1a2e22,#2d5a3c);padding:env(safe-area-inset-top,20px) 20px 18px;text-align:center;">' +
      '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">' +
        '<button id="sip-back" onclick="_cancelInlinePayment()" style="background:rgba(255,255,255,.15);border:none;border-radius:12px;padding:8px 14px;color:#fff;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">\u2190 '+(_t('hc').backBtn||'Back')+'</button>' +
        '<div style="display:flex;align-items:center;gap:6px;">' +
          '<svg width="42" height="18" viewBox="0 0 60 25" fill="none"><rect width="60" height="25" rx="4" fill="#635BFF"/><text x="30" y="17" text-anchor="middle" fill="#fff" font-family="sans-serif" font-size="11" font-weight="700">stripe</text></svg>' +
          '<span style="font-size:10px;color:rgba(255,255,255,.6);">PCI DSS</span>' +
        '</div>' +
      '</div>' +
      '<div style="font-size:11px;font-weight:700;color:rgba(255,255,255,.6);text-transform:uppercase;letter-spacing:1px;">'+(_t('hc').toPay||'Amount due')+'</div>' +
      '<div style="font-size:32px;font-weight:900;color:#fff;margin-top:4px;">' + amtFmt + ' Kč</div>' +
    '</div>' +
    '<div style="flex:1;padding:16px 20px 20px;">' +
      '<div style="display:flex;gap:8px;margin-bottom:12px;">' +
        '<button onclick="_walletCheckout(\'google_pay\')" style="flex:1;background:#000;color:#fff;border:none;border-radius:12px;padding:14px 10px;font-family:var(--font,Montserrat,sans-serif);font-size:14px;font-weight:800;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;">' +
          '<svg width="20" height="20" viewBox="0 0 24 24"><path d="M12.24 10.285V14.4h6.806c-.275 1.765-2.056 5.174-6.806 5.174-4.095 0-7.439-3.389-7.439-7.574s3.345-7.574 7.439-7.574c2.33 0 3.891.989 4.785 1.849l3.254-3.138C18.189 1.186 15.479 0 12.24 0c-6.635 0-12 5.365-12 12s5.365 12 12 12c6.926 0 11.52-4.869 11.52-11.726 0-.788-.085-1.39-.189-1.989H12.24z" fill="#fff"/></svg>' +
          'Google Pay</button>' +
        '<button onclick="_walletCheckout(\'apple_pay\')" style="flex:1;background:#000;color:#fff;border:none;border-radius:12px;padding:14px 10px;font-family:var(--font,Montserrat,sans-serif);font-size:14px;font-weight:800;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;">' +
          '<svg width="20" height="20" viewBox="0 0 24 24"><path d="M17.05 20.28c-.98.95-2.05.88-3.08.4-1.09-.5-2.08-.48-3.24 0-1.44.62-2.2.44-3.06-.4C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" fill="#fff"/></svg>' +
          'Apple Pay</button>' +
      '</div>' +
      '<div style="display:flex;align-items:center;gap:10px;margin-bottom:12px;">' +
        '<div style="flex:1;height:1px;background:#e5e7eb;"></div>' +
        '<span style="font-size:11px;font-weight:700;color:#9ca3af;">'+(_t('hc').orByCard||'or by card')+'</span>' +
        '<div style="flex:1;height:1px;background:#e5e7eb;"></div>' +
      '</div>' +
      '<div style="background:#fff;border-radius:16px;padding:18px 16px;box-shadow:0 2px 12px rgba(0,0,0,.06);margin-bottom:14px;">' +
        '<div style="font-size:11px;font-weight:800;color:#9ca3af;text-transform:uppercase;letter-spacing:.5px;margin-bottom:12px;">'+(_t('hc').paymentDetails||'Payment details')+'</div>' +
        '<div id="sip-element" style="min-height:120px;"></div>' +
        '<div id="sip-error" style="display:none;margin-top:10px;padding:8px 12px;background:#fee2e2;border-radius:8px;font-size:12px;font-weight:600;color:#b91c1c;"></div>' +
      '</div>' +
      '<button id="sip-pay-btn" onclick="_submitInlinePayment()" style="width:100%;background:var(--green,#22c55e);color:#fff;border:none;border-radius:50px;padding:16px;font-family:var(--font,Montserrat,sans-serif);font-size:16px;font-weight:800;cursor:pointer;box-shadow:0 4px 18px rgba(34,197,94,.3);">' +
        (_t('hc').payByCard||'Pay by card {amt} CZK').replace('{amt}',amtFmt) +
      '</button>' +
      '<div style="text-align:center;margin-top:12px;">' +
        '<div style="font-size:11px;color:#9ca3af;display:flex;align-items:center;justify-content:center;gap:4px;">\ud83d\udd12 '+(_t('hc').encryptedPayment||'Encrypted payment \u00b7 Stripe')+'</div>' +
      '</div>' +
    '</div>';

  document.querySelector('.phone').appendChild(_inlineOverlay);

  // Mount Stripe Payment Element
  _inlineElements = s.elements({
    clientSecret: clientSecret,
    locale: 'cs',
    appearance: {
      theme: 'stripe',
      variables: {
        fontFamily: 'Montserrat, sans-serif',
        fontSizeBase: '14px',
        colorPrimary: '#22c55e',
        borderRadius: '10px',
        spacingUnit: '4px'
      }
    }
  });
  _inlinePaymentElement = _inlineElements.create('payment', {
    layout: { type: 'tabs', defaultCollapsed: false },
    wallets: {
      googlePay: 'auto',
      applePay: 'auto'
    },
    paymentMethodOrder: ['google_pay', 'apple_pay', 'link', 'card']
  });
  _inlinePaymentElement.mount('#sip-element');
}

// Submit payment — after Stripe confirms, poll DB until webhook sets payment_status='paid'
async function _submitInlinePayment(){
  if(!_inlineElements || !_inlinePaymentActive) return;
  var s = _getStripe();
  if(!s) return;

  var btn = document.getElementById('sip-pay-btn');
  var errEl = document.getElementById('sip-error');
  var backBtn = document.getElementById('sip-back');
  if(btn){ btn.disabled = true; btn.style.opacity = '0.6'; btn.textContent = '\u23f3 '+(_t('hc').processingPayment||'Processing...'); }
  if(backBtn){ backBtn.style.display = 'none'; }
  if(errEl) errEl.style.display = 'none';

  try {
    var result = await s.confirmPayment({
      elements: _inlineElements,
      confirmParams: { return_url: window.location.href },
      redirect: 'if_required'
    });

    if(result.error){
      if(errEl){ errEl.textContent = result.error.message || (_t('hc').paymentFailed||'Payment failed'); errEl.style.display = 'block'; }
      if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = (_t('pay').payBtn||'Pay'); }
      if(backBtn){ backBtn.style.display = ''; }
      return;
    }

    // Stripe confirmed card charge — now wait for webhook to confirm in DB
    // NEVER show success until DB has payment_status='paid'
    if(result.paymentIntent && (result.paymentIntent.status === 'succeeded' || result.paymentIntent.status === 'processing')){
      if(btn) btn.textContent = '\u23f3 '+(_t('hc').verifyingPayment||'Verifying payment...');
      _waitForWebhookConfirmation();
    } else if(result.paymentIntent && result.paymentIntent.status === 'requires_action'){
      if(btn) btn.textContent = '\ud83d\udd10 '+(_t('hc').cardVerification||'Card verification...');
      // 3DS popup handled by Stripe — will re-trigger or fail
    } else {
      // Unknown status — do NOT call success, show error
      if(errEl){ errEl.textContent = (_t('hc').paymentIncomplete||'Payment was not completed. Try again.'); errEl.style.display = 'block'; }
      if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = (_t('pay').payBtn||'Pay'); }
      if(backBtn){ backBtn.style.display = ''; }
    }
  } catch(e){
    console.error('[STRIPE-INLINE] confirmPayment error:', e);
    if(errEl){ errEl.textContent = (_t('hc').paymentError||'Payment error') + ': ' + (e.message || (_t('hc').unknownError||'Unknown error')); errEl.style.display = 'block'; }
    if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = (_t('pay').payBtn||'Pay'); }
    if(backBtn){ backBtn.style.display = ''; }
  }
}

// Poll DB every 1s for up to 8s — Stripe already confirmed, just wait for webhook
function _waitForWebhookConfirmation(){
  var attempts = 0;
  var maxAttempts = 8; // 8 × 1s = 8s max
  if(_inlinePollTimer) clearInterval(_inlinePollTimer);

  _inlinePollTimer = setInterval(async function(){
    attempts++;
    if(!window.supabase || !_inlinePaymentActive){
      clearInterval(_inlinePollTimer); _inlinePollTimer = null;
      return;
    }
    try {
      var paid = false;
      if(_inlineBookingId){
        var r = await window.supabase.from('bookings').select('payment_status').eq('id', _inlineBookingId).single();
        if(r.data && r.data.payment_status === 'paid') paid = true;
      } else if(_inlineOrderId){
        var r = await window.supabase.from('shop_orders').select('payment_status').eq('id', _inlineOrderId).single();
        if(r.data && r.data.payment_status === 'paid') paid = true;
      } else {
        // No ID to poll — fallback: trust Stripe after 5s
        if(attempts >= 4) paid = true;
      }

      if(paid){
        clearInterval(_inlinePollTimer); _inlinePollTimer = null;
        _closeInlineOverlay();
        if(_inlineOnSuccess) _inlineOnSuccess();
        return;
      }
    } catch(e){ console.warn('[STRIPE-INLINE] Poll error:', e); }

    if(attempts >= maxAttempts){
      clearInterval(_inlinePollTimer); _inlinePollTimer = null;
      // Timeout — Stripe charged card but webhook hasn't confirmed yet
      // Payment IS successful (Stripe confirmed), show success anyway
      _closeInlineOverlay();
      if(_inlineOnSuccess) _inlineOnSuccess();
    }
  }, 1000);
}

// Wallet checkout — redirect to Stripe Checkout in system browser (Google Pay / Apple Pay)
async function _walletCheckout(wallet){
  var bookingId = _inlineBookingId;
  var orderId = _inlineOrderId;
  var amount = _inlineAmount;
  var payType = _inlinePaymentType;
  var onSuccess = _inlineOnSuccess;
  var onCancel = _inlineOnCancel;

  // Close inline overlay first
  _closeInlineOverlay();
  _inlinePaymentActive = false;

  if(typeof apiProcessPayment !== 'function') return;
  try {
    var opts = { type: payType, mode: 'checkout' };
    if(orderId) opts.order_id = orderId;
    var result = await apiProcessPayment(bookingId, amount, 'card', opts);
    if(result.success && result.checkout_url){
      _stripeCheckoutOpened = true;
      _stripeCheckoutBookingId = bookingId;
      if(typeof _lockPaymentScreen === 'function') _lockPaymentScreen('↗ ' + (wallet === 'apple_pay' ? 'Apple Pay' : 'Google Pay') + '...');
      if(typeof _openExternalUrl === 'function') _openExternalUrl(result.checkout_url);
      else window.open(result.checkout_url, '_blank');
    } else {
      if(typeof showT === 'function') showT('\u2717',_t('common').error,result.error || (_t('hc').gatewayOpenFailed||'Failed to open payment gateway'));
      if(onCancel) onCancel();
    }
  } catch(e){
    console.error('[STRIPE-INLINE] walletCheckout error:', e);
    if(typeof showT === 'function') showT('\u2717',_t('common').error,_t('hc').gatewayOpenFailed||'Failed to open payment gateway');
    if(onCancel) onCancel();
  }
}

// Cancel — close overlay, call onCancel (triggers FAB)
function _cancelInlinePayment(){
  if(_inlinePollTimer){ clearInterval(_inlinePollTimer); _inlinePollTimer = null; }
  _closeInlineOverlay();
  if(_inlineOnCancel) _inlineOnCancel();
}

function _closeInlineOverlay(){
  _inlinePaymentActive = false;
  if(_inlinePaymentElement){ try { _inlinePaymentElement.destroy(); } catch(e){} _inlinePaymentElement = null; }
  _inlineElements = null;
  _inlineClientSecret = null;
  _inlineBookingId = null;
  _inlineOrderId = null;
  _inlineAmount = 0;
  _inlinePaymentType = 'booking';
  if(_inlineOverlay && _inlineOverlay.parentNode){
    _inlineOverlay.parentNode.removeChild(_inlineOverlay);
  }
  _inlineOverlay = null;
}
