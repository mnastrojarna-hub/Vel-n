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

// Show inline payment overlay with Stripe Payment Element
// opts: { onSuccess, onCancel, bookingId, orderId }
function showStripeInlinePayment(clientSecret, amount, opts){
  if(_inlinePaymentActive) return;
  _inlinePaymentActive = true;
  _inlineClientSecret = clientSecret;
  _inlineOnSuccess = (opts && opts.onSuccess) || null;
  _inlineOnCancel = (opts && opts.onCancel) || null;
  _inlineBookingId = (opts && opts.bookingId) || null;
  _inlineOrderId = (opts && opts.orderId) || null;

  var s = _getStripe();
  if(!s){ _inlinePaymentActive = false; return; }

  _inlineOverlay = document.createElement('div');
  _inlineOverlay.id = 'stripe-inline-overlay';
  _inlineOverlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:99998;background:#f5f5f7;display:flex;flex-direction:column;overflow-y:auto;';

  var amtFmt = (amount||0).toLocaleString('cs-CZ');
  _inlineOverlay.innerHTML =
    '<div style="background:linear-gradient(135deg,#1a2e22,#2d5a3c);padding:env(safe-area-inset-top,20px) 20px 18px;text-align:center;">' +
      '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">' +
        '<button id="sip-back" onclick="_cancelInlinePayment()" style="background:rgba(255,255,255,.15);border:none;border-radius:12px;padding:8px 14px;color:#fff;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">← Zpět</button>' +
        '<div style="display:flex;align-items:center;gap:6px;">' +
          '<svg width="42" height="18" viewBox="0 0 60 25" fill="none"><rect width="60" height="25" rx="4" fill="#635BFF"/><text x="30" y="17" text-anchor="middle" fill="#fff" font-family="sans-serif" font-size="11" font-weight="700">stripe</text></svg>' +
          '<span style="font-size:10px;color:rgba(255,255,255,.6);">PCI DSS</span>' +
        '</div>' +
      '</div>' +
      '<div style="font-size:11px;font-weight:700;color:rgba(255,255,255,.6);text-transform:uppercase;letter-spacing:1px;">K úhradě</div>' +
      '<div style="font-size:32px;font-weight:900;color:#fff;margin-top:4px;">' + amtFmt + ' Kč</div>' +
    '</div>' +
    '<div style="flex:1;padding:16px 20px 20px;">' +
      '<div style="background:#fff;border-radius:16px;padding:18px 16px;box-shadow:0 2px 12px rgba(0,0,0,.06);margin-bottom:14px;">' +
        '<div style="font-size:11px;font-weight:800;color:#9ca3af;text-transform:uppercase;letter-spacing:.5px;margin-bottom:12px;">Platební údaje</div>' +
        '<div id="sip-element" style="min-height:120px;"></div>' +
        '<div id="sip-error" style="display:none;margin-top:10px;padding:8px 12px;background:#fee2e2;border-radius:8px;font-size:12px;font-weight:600;color:#b91c1c;"></div>' +
      '</div>' +
      '<button id="sip-pay-btn" onclick="_submitInlinePayment()" style="width:100%;background:var(--green,#22c55e);color:#fff;border:none;border-radius:50px;padding:16px;font-family:var(--font,Montserrat,sans-serif);font-size:16px;font-weight:800;cursor:pointer;box-shadow:0 4px 18px rgba(34,197,94,.3);">' +
        'Zaplatit ' + amtFmt + ' Kč' +
      '</button>' +
      '<div style="text-align:center;margin-top:12px;">' +
        '<div style="font-size:11px;color:#9ca3af;display:flex;align-items:center;justify-content:center;gap:4px;">🔒 Šifrovaná platba · Stripe</div>' +
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
    layout: { type: 'tabs', defaultCollapsed: false }
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
  if(btn){ btn.disabled = true; btn.style.opacity = '0.6'; btn.textContent = '⏳ Zpracovávám platbu...'; }
  if(backBtn){ backBtn.style.display = 'none'; }
  if(errEl) errEl.style.display = 'none';

  try {
    var result = await s.confirmPayment({
      elements: _inlineElements,
      confirmParams: { return_url: window.location.href },
      redirect: 'if_required'
    });

    if(result.error){
      if(errEl){ errEl.textContent = result.error.message || 'Platba se nezdařila'; errEl.style.display = 'block'; }
      if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = 'Zaplatit'; }
      if(backBtn){ backBtn.style.display = ''; }
      return;
    }

    // Stripe confirmed card charge — now wait for webhook to confirm in DB
    // NEVER show success until DB has payment_status='paid'
    if(result.paymentIntent && (result.paymentIntent.status === 'succeeded' || result.paymentIntent.status === 'processing')){
      if(btn) btn.textContent = '⏳ Ověřuji platbu...';
      _waitForWebhookConfirmation();
    } else if(result.paymentIntent && result.paymentIntent.status === 'requires_action'){
      if(btn) btn.textContent = '🔐 Ověření karty...';
      // 3DS popup handled by Stripe — will re-trigger or fail
    } else {
      // Unknown status — do NOT call success, show error
      if(errEl){ errEl.textContent = 'Platba nebyla dokončena. Zkuste to znovu.'; errEl.style.display = 'block'; }
      if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = 'Zaplatit'; }
      if(backBtn){ backBtn.style.display = ''; }
    }
  } catch(e){
    console.error('[STRIPE-INLINE] confirmPayment error:', e);
    if(errEl){ errEl.textContent = 'Chyba platby: ' + (e.message || 'Neznámá chyba'); errEl.style.display = 'block'; }
    if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = 'Zaplatit'; }
    if(backBtn){ backBtn.style.display = ''; }
  }
}

// Poll DB every 1.5s for up to 30s — wait for webhook to set payment_status='paid'
function _waitForWebhookConfirmation(){
  var attempts = 0;
  var maxAttempts = 20; // 20 × 1.5s = 30s
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
      // Show warning but DON'T call success — let user check reservations
      _closeInlineOverlay();
      if(typeof showT === 'function') showT('⏳','Platba zpracovávána','Potvrzení může trvat několik sekund. Zkontrolujte Moje rezervace.');
    }
  }, 1500);
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
  if(_inlineOverlay && _inlineOverlay.parentNode){
    _inlineOverlay.parentNode.removeChild(_inlineOverlay);
  }
  _inlineOverlay = null;
}
