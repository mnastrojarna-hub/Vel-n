// ===== CART-CHECKOUT.JS – Shop checkout flow + discount =====
// Depends on globals from cart-engine.js (cart, shipMode, etc.)
// Booking price → cart-booking-price.js | Address → cart-address.js

// ===== SHOP DISCOUNT STATE =====
var shopDiscountAmt = 0;
var shopAppliedCodes = [];  // [{code, type:'promo'|'voucher', id, value, discountAmt, discountType, discountValue}]
var _pendingShopOrderId = null; // For post-Stripe payment check
var _selectedSavedCardId = null; // Selected saved card PM ID for checkout

// Detect if cart contains ONLY digital vouchers (no shipping needed)
function _isCartOnlyDigitalVouchers(){
  if(!cart || cart.length===0) return false;
  return cart.every(function(c){
    var nm=(c.name||'').toLowerCase();
    var isVoucher=c.id==='voucher'||nm.indexOf('poukaz')!==-1||nm.indexOf('voucher')!==-1;
    var isPrinted=nm.indexOf('tišt')!==-1||nm.indexOf('printed')!==-1;
    return isVoucher && !isPrinted;
  });
}

function updateCheckoutTotal(){
  var digitalOnly=_isCartOnlyDigitalVouchers();
  var shipCost=digitalOnly?0:(shipMode==='post'?99:0);
  var cartTotal=typeof cart!=='undefined'?cart.reduce(function(s,c){return s+c.price*c.qty;},0):0;
  var finalTotal=Math.max(0, cartTotal+shipCost-shopDiscountAmt);
  var el=document.getElementById('checkout-total');
  if(el)el.textContent=finalTotal.toLocaleString('cs-CZ')+' Kč';
  var dRow=document.getElementById('shop-discount-row');
  var dAmt=document.getElementById('shop-discount-amt');
  var dLabel=document.getElementById('shop-discount-label');
  if(dRow&&dAmt){
    dRow.style.display=shopDiscountAmt>0?'block':'none';
    dAmt.textContent='-'+shopDiscountAmt.toLocaleString('cs-CZ')+' Kč';
    if(dLabel) dLabel.textContent=shopAppliedCodes.map(function(c){return c.code;}).join(' + ');
  }
}

// ===== CHECKOUT FUNCTIONS =====

function selectShipping(mode){
  shipMode=mode;
  var postEl=document.getElementById('ship-post');
  var pickupEl=document.getElementById('ship-pickup');
  if(postEl){postEl.style.borderColor=mode==='post'?'var(--green)':'var(--g200)';postEl.style.background=mode==='post'?'var(--gp)':'#fff';}
  if(pickupEl){pickupEl.style.borderColor=mode==='pickup'?'var(--green)':'var(--g200)';pickupEl.style.background=mode==='pickup'?'var(--gp)':'#fff';}
  var shipWrap = document.getElementById('ship-section-wrap');
  if(shipWrap) shipWrap.style.display = mode==='post' ? 'block' : 'none';
  // Hide entire delivery section for digital-only vouchers
  var deliveryCard = postEl ? postEl.closest('.bcard') : null;
  if(deliveryCard) deliveryCard.style.display = _isCartOnlyDigitalVouchers() ? 'none' : '';
  updateCheckoutTotal();
}

// Show saved cards as selectable options in checkout screen
async function _showCheckoutSavedCard(){
  var el = document.getElementById('checkout-saved-card');
  if(!el || typeof apiFetchPaymentMethods !== 'function') return;
  _selectedSavedCardId = null;
  try {
    var r = await apiFetchPaymentMethods();
    if(!r.success || !r.methods || r.methods.length === 0) return;
    var brandIcons = {visa:'VISA',mastercard:'MC',amex:'AMEX'};
    el.style.display = 'block';
    el.innerHTML = '<div style="font-size:11px;font-weight:700;color:var(--g400);margin-bottom:6px;">Uložené karty:</div>' +
      r.methods.map(function(m){
        var brand = brandIcons[m.brand] || (m.brand||'').toUpperCase();
        var exp = (m.exp_month < 10 ? '0' : '') + m.exp_month + '/' + String(m.exp_year).slice(-2);
        var isDefault = m.is_default;
        return '<div onclick="_selectSavedCard(\''+m.id+'\')" id="saved-card-'+m.id+'" style="display:flex;align-items:center;gap:10px;padding:10px 12px;background:'+(isDefault?'var(--gp)':'#fff')+';border:2px solid '+(isDefault?'var(--green)':'var(--g200)')+';border-radius:var(--rsm);cursor:pointer;margin-bottom:6px;transition:border-color .15s,background .15s;">' +
          '<div style="font-size:18px;">💳</div>' +
          '<div style="flex:1;"><div style="font-size:13px;font-weight:700;">•••• ' + m.last4 + ' <span style="font-size:10px;color:var(--g400);">' + brand + '</span></div>' +
          '<div style="font-size:10px;color:var(--g400);">' + exp + (m.holder_name?' · '+m.holder_name:'') + '</div></div>' +
          '<div id="saved-card-check-'+m.id+'" style="font-size:10px;font-weight:700;color:var(--green);display:'+(isDefault?'block':'none')+';">✓ Vybráno</div></div>';
      }).join('');
    // Auto-select default card
    var def = r.methods.find(function(m){ return m.is_default; }) || r.methods[0];
    if(def) _selectSavedCard(def.id);
  } catch(e){}
}

function _selectSavedCard(pmId){
  _selectedSavedCardId = pmId;
  var wrap = document.getElementById('checkout-saved-card');
  if(!wrap) return;
  var cards = wrap.querySelectorAll('[id^="saved-card-"]');
  cards.forEach(function(c){
    if(c.id.indexOf('saved-card-check-')===0) return;
    var isSelected = c.id === 'saved-card-'+pmId;
    c.style.borderColor = isSelected ? 'var(--green)' : 'var(--g200)';
    c.style.background = isSelected ? 'var(--gp)' : '#fff';
    var check = document.getElementById('saved-card-check-'+c.id.replace('saved-card-',''));
    if(check) check.style.display = isSelected ? 'block' : 'none';
  });
}

async function finalizeCheckout(){
  var subtotal=cart.reduce(function(s,c){return s+c.price*c.qty;},0);
  if(subtotal===0){showT('\u26a0\ufe0f',_t('cart').cart,_t('cart').cartEmpty);return;}
  var digitalOnly=_isCartOnlyDigitalVouchers();
  if(!digitalOnly && shipMode==='post'){
    var nm=(document.getElementById('ship-name')||{}).value;
    if(!nm){showT('\u26a0\ufe0f',_t('cart').address,_t('cart').fillAddress);return;}
  }
  var shipCost=digitalOnly?0:(shipMode==='post'?99:0);
  var finalTotal=Math.max(0, subtotal+shipCost-shopDiscountAmt);
  if(finalTotal===0 && shopDiscountAmt>0){showT('\u2139\ufe0f','Sleva','Objednávka je plně pokryta slevou');}
  else if(finalTotal<=0){showT('\u26a0\ufe0f','Chyba','Celková cena musí být vyšší než 0 Kč');return;}
  // Validate stock before checkout
  if(window.supabase){
    for(var si=0;si<cart.length;si++){
      var ci=cart[si];var baseId=ci.id.split('-')[0];
      try{
        var sr=await window.supabase.from('products').select('stock_quantity,name').eq('id',baseId).single();
        if(sr.data && sr.data.stock_quantity!==null && sr.data.stock_quantity<ci.qty){
          showT('\u26a0\ufe0f','Nedostatek skladu',(sr.data.name||ci.name)+': skladem '+sr.data.stock_quantity+' ks');
          if(sr.data.stock_quantity<=0){cart=cart.filter(function(x){return x.id!==ci.id;});updateCartFab();}
          return;
        }
      }catch(se){}
    }
  }
  showT('\ud83d\udcb3',_t('cart').processing,_t('cart').pleaseWait);

  var orderSuccess = false;

  if(window.supabase){
    try {
      var items = cart.map(function(c){ return {id:c.id, name:c.name, price:c.price, qty:c.qty}; });
      var shipAddr = null;
      if(!digitalOnly && shipMode==='post'){
        shipAddr = {
          name: (document.getElementById('ship-name')||{}).value || '',
          street: (document.getElementById('ship-street')||{}).value || '',
          zip: (document.getElementById('ship-zip')||{}).value || '',
          city: (document.getElementById('ship-city')||{}).value || ''
        };
      }
      var promoCode = null;
      for(var i=0;i<shopAppliedCodes.length;i++){
        if(shopAppliedCodes[i].type==='promo'){promoCode=shopAppliedCodes[i].code;break;}
      }
      var r = await window.supabase.rpc('create_shop_order', {
        p_items: items, p_shipping_method: digitalOnly ? 'digital' : shipMode,
        p_shipping_address: shipAddr, p_payment_method: 'card', p_promo_code: promoCode
      });
      if(r.data && r.data.error){showT('\u26a0\ufe0f','Chyba objednávky', r.data.error);return;}
      if(r.error){showT('\u26a0\ufe0f','Chyba objednávky', 'RPC selhalo: ' + r.error.message);return;}

      var orderId = r.data && r.data.order_id;
      if(!orderId){showT('\u26a0\ufe0f','Chyba','Objednávka nebyla vytvořena (chybí order_id)');return;}

      // ZF (zálohová faktura) — trigger: vytvoření objednávky (před platbou)
      try {
        await window.supabase.functions.invoke('generate-invoice', {
          body: { type: 'shop_proforma', order_id: orderId, send_email: false }
        });
      } catch(ie){ console.warn('[SHOP] ZF generation:', ie); }

      // Mark vouchers as redeemed
      for(var vi=0;vi<shopAppliedCodes.length;vi++){
        if(shopAppliedCodes[vi].type==='voucher'){
          await window.supabase.from('vouchers').update({
            status:'redeemed', redeemed_at:new Date().toISOString(),
            redeemed_by:(await window.supabase.auth.getUser()).data.user.id
          }).eq('id', shopAppliedCodes[vi].id);
        }
      }

      // STRIPE PLATBA: inline Payment Element nebo fallback Checkout
      if(finalTotal > 0){
        var payResult = await apiProcessPayment(null, finalTotal, 'card', {type: 'shop', order_id: orderId});
        // Inline Payment Element
        if(payResult.success && payResult.client_secret){
          _pendingShopOrderId = orderId;
          showStripeInlinePayment(payResult.client_secret, finalTotal, {
            orderId: orderId,
            onSuccess: function(){
              _stripeCheckoutOpened = false;
              _stripeCheckoutBookingId = null;
              _pendingShopOrderId = null;
              try {
                window.supabase.functions.invoke('generate-invoice', {
                  body: { type: 'payment_receipt', order_id: orderId, send_email: false }
                }).catch(function(){});
              } catch(re){}
              _showCheckoutSuccess();
            },
            onCancel: function(){
              _pendingShopOrderId = null;
              showT('\u2139\ufe0f','Platba přerušena','Objednávka čeká na zaplacení');
            }
          });
          return;
        }
        // Fallback: Checkout redirect
        if(payResult.success && payResult.checkout_url){
          _pendingShopOrderId = orderId;
          _stripeCheckoutBookingId = orderId;
          _stripeCheckoutOpened = true;
          if(typeof _openExternalUrl === 'function') _openExternalUrl(payResult.checkout_url);
          else window.open(payResult.checkout_url, '_blank');
          return;
        }
        showT('\u26a0\ufe0f','Chyba platby','Nepodařilo se otevřít platební bránu. Zkuste to znovu.');
        return;
      } else {
        // 100% discount — confirm payment directly (no Stripe needed)
        var payRes = await window.supabase.rpc('confirm_shop_payment', {
          p_order_id: orderId, p_method: 'voucher'
        });
        if(payRes.error){
          await window.supabase.from('shop_orders').update({
            payment_status: 'paid', status: 'confirmed', confirmed_at: new Date().toISOString()
          }).eq('id', orderId);
        }
      }
      // DP (doklad k přijaté platbě) — trigger: zaplacení (jen pro 100% slevu, jinak řeší webhook)
      if(finalTotal <= 0){
        try {
          await window.supabase.functions.invoke('generate-invoice', {
            body: { type: 'payment_receipt', order_id: orderId, send_email: false }
          });
        } catch(re){ console.warn('[SHOP] DP receipt err:', re); }
      }

      orderSuccess = true;
    } catch(e){
      showT('\u26a0\ufe0f','Chyba','Nepodařilo se dokončit objednávku: ' + (e.message || e));
      return;
    }
  } else {
    showT('\u26a0\ufe0f','Offline','Nelze vytvořit objednávku bez připojení');return;
  }

  if(orderSuccess){ _showCheckoutSuccess(); }
}

// Check shop payment after returning from Stripe
async function _checkShopPaymentAfterStripe(){
  if(!_pendingShopOrderId || !window.supabase) return;
  try {
    var r = await window.supabase.from('shop_orders').select('status, payment_status').eq('id', _pendingShopOrderId).single();
    if(!r.data) return;
    if(r.data.payment_status === 'paid'){
      _stripeCheckoutOpened = false;
      _stripeCheckoutBookingId = null;
      _pendingShopOrderId = null;
      // DP — doklad k přijaté platbě (webhook potvrdil platbu)
      try {
        await window.supabase.functions.invoke('generate-invoice', {
          body: { type: 'payment_receipt', order_id: r.data.id || _pendingShopOrderId }
        });
      } catch(re){}
      _showCheckoutSuccess();
      return;
    }
  } catch(e){ console.warn('[SHOP] _checkShopPaymentAfterStripe err:', e); }
}

// Listen for Stripe return (reuse visibility change event)
document.addEventListener('visibilitychange', function(){
  if(!document.hidden && _pendingShopOrderId && typeof _checkShopPaymentAfterStripe === 'function'){
    _checkShopPaymentAfterStripe();
  }
});

function _showCheckoutSuccess(){
  var hasVoucher = cart.some(function(c){ return c.id==='voucher' || (c.name||'').toLowerCase().indexOf('poukaz')!==-1 || (c.name||'').toLowerCase().indexOf('voucher')!==-1; });
  var isAllVouchers = hasVoucher && cart.every(function(c){ return c.id==='voucher' || (c.name||'').toLowerCase().indexOf('poukaz')!==-1 || (c.name||'').toLowerCase().indexOf('voucher')!==-1; });
  var hasPrintedVoucher = cart.some(function(c){ return (c.name||'').toLowerCase().indexOf('tišt')!==-1 || (c.name||'').toLowerCase().indexOf('printed')!==-1; });

  cart=[];cartFabDismissed=false;appliedCode=null;_appliedPromoId=null;
  shopDiscountAmt=0;shopAppliedCodes=[];updateCartFab();

  var successTitle = _t('cart').thankYou;
  var successLine1 = _t('cart').orderReceived;
  var successLine2 = _t('cart').emailConfirm;
  var successIcon = '\u2705';
  var toastTitle = _t('cart').orderAccepted;
  var toastMsg = _t('cart').confirmEmail;

  if(isAllVouchers && !hasPrintedVoucher){
    successIcon='\uD83C\uDF81';successLine1='Váš dárkový poukaz byl vytvořen a odeslán do zpráv v aplikaci.';
    successLine2='Kód najdete v sekci Zprávy. Můžete ho ihned uplatnit při rezervaci.';
    toastTitle='Poukaz odeslán!';toastMsg='Kód najdete ve zprávách v aplikaci.';
  } else if(hasVoucher && hasPrintedVoucher){
    successIcon='\uD83C\uDF81';successLine1='Kód poukazu byl odeslán do zpráv. Fyzický poukaz poštou.';
    successLine2='Kód můžete uplatnit ihned, nemusíte čekat na zásilku.';
    toastTitle='Poukaz odeslán!';toastMsg='Kód ve zprávách, fyzický poukaz poštou.';
  } else if(hasVoucher){
    successIcon='\uD83C\uDF81';successLine1='Kód dárkového poukazu byl odeslán do zpráv v aplikaci.';
    successLine2='Zbylé zboží vám bude zasláno. Kód můžete uplatnit ihned.';
    toastTitle='Poukaz odeslán!';toastMsg='Kód ve zprávách, zboží bude zasláno.';
  }

  showT(successIcon, toastTitle, toastMsg);
  var checkoutEl = document.getElementById('s-checkout');
  if(checkoutEl){
    checkoutEl.innerHTML='<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:60vh;padding:40px;text-align:center;"><div style="font-size:64px;margin-bottom:16px;">'+successIcon+'</div><div style="font-size:22px;font-weight:900;color:var(--black);margin-bottom:8px;">'+successTitle+'</div><div style="font-size:14px;color:var(--g400);line-height:1.6;">'+successLine1+'<br>'+successLine2+'</div>'+(hasVoucher?'<button onclick="goTo(\'s-messages\')" style="margin-top:20px;background:var(--green);color:#fff;border:none;border-radius:50px;padding:12px 28px;font-family:var(--font);font-size:14px;font-weight:700;cursor:pointer;">Otevřít zprávy</button>':'')+'</div>';
  }
  setTimeout(function(){ goTo('s-merch'); }, hasVoucher ? 8000 : 5000);
}
