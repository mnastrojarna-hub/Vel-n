// ===== CART-CHECKOUT.JS – Checkout, booking price & address autocomplete =====
// Split from original cart-engine.js. Depends on global state variables
// (cart, shipMode, pickupDelivFee, returnDelivFee, etc.) defined in cart-engine.js.

// ===== SHOP DISCOUNT STATE =====
var shopDiscountAmt = 0;
var shopAppliedCodes = [];  // [{code, type:'promo'|'voucher', id, value, discountAmt}]

function updateCheckoutTotal(){
  var shipCost=shipMode==='post'?99:0;
  var cartTotal=typeof cart!=='undefined'?cart.reduce(function(s,c){return s+c.price*c.qty;},0):0;
  var finalTotal=Math.max(0, cartTotal+shipCost-shopDiscountAmt);
  var el=document.getElementById('checkout-total');
  if(el)el.textContent=finalTotal.toLocaleString('cs-CZ')+' Kč';
  // Update discount display
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
  document.getElementById('ship-post').style.borderColor=mode==='post'?'var(--green)':'var(--g200)';
  document.getElementById('ship-post').style.background=mode==='post'?'var(--gp)':'#fff';
  document.getElementById('ship-pickup').style.borderColor=mode==='pickup'?'var(--green)':'var(--g200)';
  document.getElementById('ship-pickup').style.background=mode==='pickup'?'var(--gp)':'#fff';
  var shipWrap = document.getElementById('ship-section-wrap');
  if(shipWrap) shipWrap.style.display = mode==='post' ? 'block' : 'none';
  updateCheckoutTotal();
}

function selCheckoutP(t){
  ['card','apple'].forEach(x=>{
    document.getElementById('pm-'+x+'-ch')?.classList.remove('sel');
    const r=document.getElementById('pmr-'+x+'-ch');if(r){r.classList.remove('on');}
  });
  document.getElementById('pm-'+t+'-ch')?.classList.add('sel');
  const r=document.getElementById('pmr-'+t+'-ch');if(r)r.classList.add('on');
}

async function finalizeCheckout(){
  var subtotal=cart.reduce(function(s,c){return s+c.price*c.qty;},0);
  if(subtotal===0){showT('\u26a0\ufe0f',_t('cart').cart,_t('cart').cartEmpty);return;}
  if(shipMode==='post'){
    var nm=(document.getElementById('ship-name')||{}).value;
    if(!nm){showT('\u26a0\ufe0f',_t('cart').address,_t('cart').fillAddress);return;}
  }
  var shipCost=shipMode==='post'?99:0;
  var finalTotal=Math.max(0, subtotal+shipCost-shopDiscountAmt);
  if(finalTotal<=0){showT('\u26a0\ufe0f','Chyba','Celková cena musí být vyšší než 0 Kč');return;}
  showT('\ud83d\udcb3',_t('cart').processing,_t('cart').pleaseWait);

  var orderSuccess = false;

  if(window.supabase){
    try {
      var items = cart.map(function(c){ return {id:c.id, name:c.name, price:c.price, qty:c.qty}; });
      var shipAddr = null;
      if(shipMode==='post'){
        shipAddr = {
          name: (document.getElementById('ship-name')||{}).value || '',
          street: (document.getElementById('ship-street')||{}).value || '',
          zip: (document.getElementById('ship-zip')||{}).value || '',
          city: (document.getElementById('ship-city')||{}).value || ''
        };
      }
      // Pass first promo code (if any) to create_shop_order
      var promoCode = null;
      for(var i=0;i<shopAppliedCodes.length;i++){
        if(shopAppliedCodes[i].type==='promo'){promoCode=shopAppliedCodes[i].code;break;}
      }
      var r = await window.supabase.rpc('create_shop_order', {
        p_items: items,
        p_shipping_method: shipMode,
        p_shipping_address: shipAddr,
        p_payment_method: 'card',
        p_promo_code: promoCode
      });
      if(r.data && r.data.error){
        console.warn('[SHOP] create_shop_order error:', r.data.error);
        showT('\u26a0\ufe0f','Chyba objednávky', r.data.error);return;
      }
      if(r.error){
        console.warn('[SHOP] RPC error:', r.error.message);
        showT('\u26a0\ufe0f','Chyba objednávky', 'RPC selhalo: ' + r.error.message);return;
      }

      var orderId = r.data && r.data.order_id;
      if(!orderId){
        console.warn('[SHOP] No order_id returned:', JSON.stringify(r.data));
        showT('\u26a0\ufe0f','Chyba','Objednávka nebyla vytvořena (chybí order_id)');return;
      }

      // Mark vouchers as redeemed
      for(var vi=0;vi<shopAppliedCodes.length;vi++){
        if(shopAppliedCodes[vi].type==='voucher'){
          await window.supabase.from('vouchers').update({
            status:'redeemed', redeemed_at:new Date().toISOString(),
            redeemed_by:(await window.supabase.auth.getUser()).data.user.id
          }).eq('id', shopAppliedCodes[vi].id);
        }
      }

      // SIMULOVANÁ PLATBA: označ objednávku jako zaplacenou (přes RPC — obchází RLS)
      var payRes = await window.supabase.rpc('confirm_shop_payment', {
        p_order_id: orderId,
        p_method: 'card'
      });
      if(payRes.error){
        console.warn('[SHOP] RPC confirm_shop_payment failed:', payRes.error.message, '— trying direct update');
        // Fallback: přímý update (funguje jen pokud existuje UPDATE RLS policy)
        var fbRes = await window.supabase.from('shop_orders').update({
          payment_status: 'paid', status: 'confirmed', confirmed_at: new Date().toISOString()
        }).eq('id', orderId);
        if(fbRes.error){
          console.warn('[SHOP] Fallback update also failed:', fbRes.error.message);
          showT('\u26a0\ufe0f','Chyba platby','Objednávka vytvořena ('+orderId.substr(-8)+'), ale platba selhala. Kontaktujte nás.');return;
        }
      }
      // Generuj ZF (zálohovou fakturu) + DP (doklad k platbě)
      // Edge funkce auto-natáhne voucher kódy z DB a zobrazí je na dokladech
      try {
        await window.supabase.functions.invoke('generate-invoice', {
          body: { type: 'shop_proforma', order_id: orderId }
        });
      } catch(ie){ console.warn('[SHOP] ZF generation:', ie); }
      try {
        await window.supabase.functions.invoke('generate-invoice', {
          body: { type: 'payment_receipt', order_id: orderId }
        });
      } catch(re){ console.warn('[SHOP] DP receipt err:', re); }
      // FK (shop_final) se generuje automaticky DB triggerem trg_generate_shop_invoice
      // + edge funkce generate-invoice s voucher kódy
      try {
        await window.supabase.functions.invoke('generate-invoice', {
          body: { type: 'shop_final', order_id: orderId }
        });
      } catch(fe){ console.warn('[SHOP] FK generation:', fe); }

      orderSuccess = true;
    } catch(e){
      console.error('[SHOP] finalizeCheckout DB error:', e);
      showT('\u26a0\ufe0f','Chyba','Nepodařilo se dokončit objednávku: ' + (e.message || e));
      return;
    }
  } else {
    showT('\u26a0\ufe0f','Offline','Nelze vytvořit objednávku bez připojení');
    return;
  }

  if(orderSuccess){
    // Check if cart contains voucher items
    var hasVoucher = cart.some(function(c){ return c.id==='voucher' || (c.name||'').toLowerCase().indexOf('poukaz')!==-1 || (c.name||'').toLowerCase().indexOf('voucher')!==-1; });
    var isAllVouchers = hasVoucher && cart.every(function(c){ return c.id==='voucher' || (c.name||'').toLowerCase().indexOf('poukaz')!==-1 || (c.name||'').toLowerCase().indexOf('voucher')!==-1; });
    var hasPrintedVoucher = cart.some(function(c){ return (c.name||'').toLowerCase().indexOf('tišt')!==-1 || (c.name||'').toLowerCase().indexOf('printed')!==-1; });

    cart=[];
    cartFabDismissed=false;
    appliedCode=null;
    _appliedPromoId=null;
    shopDiscountAmt=0;
    shopAppliedCodes=[];
    updateCartFab();

    var successTitle = _t('cart').thankYou;
    var successLine1 = _t('cart').orderReceived;
    var successLine2 = _t('cart').emailConfirm;
    var successIcon = '\u2705';
    var toastTitle = _t('cart').orderAccepted;
    var toastMsg = _t('cart').confirmEmail;

    if(isAllVouchers && !hasPrintedVoucher){
      // Pure digital voucher — auto-fulfilled
      successIcon = '\uD83C\uDF81';
      successLine1 = 'Váš dárkový poukaz byl vytvořen a odeslán do zpráv v aplikaci.';
      successLine2 = 'Kód najdete v sekci Zprávy. Můžete ho ihned uplatnit při rezervaci.';
      toastTitle = 'Poukaz odeslán!';
      toastMsg = 'Kód najdete ve zprávách v aplikaci.';
    } else if(hasVoucher && hasPrintedVoucher){
      // Physical voucher — code sent digitally, physical card shipped separately
      successIcon = '\uD83C\uDF81';
      successLine1 = 'Kód poukazu byl odeslán do zpráv v aplikaci. Fyzický poukaz vám bude zaslán poštou.';
      successLine2 = 'Kód můžete uplatnit ihned, nemusíte čekat na zásilku.';
      toastTitle = 'Poukaz odeslán!';
      toastMsg = 'Kód ve zprávách, fyzický poukaz poštou.';
    } else if(hasVoucher){
      // Mixed order with voucher + other items
      successIcon = '\uD83C\uDF81';
      successLine1 = 'Kód dárkového poukazu byl odeslán do zpráv v aplikaci.';
      successLine2 = 'Zbylé zboží vám bude zasláno. Kód můžete uplatnit ihned.';
      toastTitle = 'Poukaz odeslán!';
      toastMsg = 'Kód ve zprávách, zboží bude zasláno.';
    }

    showT(successIcon, toastTitle, toastMsg);
    var checkoutEl = document.getElementById('s-checkout');
    if(checkoutEl){
      checkoutEl.innerHTML = '<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:60vh;padding:40px;text-align:center;"><div style="font-size:64px;margin-bottom:16px;">'+successIcon+'</div><div style="font-size:22px;font-weight:900;color:var(--black);margin-bottom:8px;">'+successTitle+'</div><div style="font-size:14px;color:var(--g400);line-height:1.6;">'+successLine1+'<br>'+successLine2+'</div>'+(hasVoucher?'<button onclick="goTo(\'s-messages\')" style="margin-top:20px;background:var(--green);color:#fff;border:none;border-radius:50px;padding:12px 28px;font-family:var(--font);font-size:14px;font-weight:700;cursor:pointer;">Otevřít zprávy</button>':'')+'</div>';
    }
    setTimeout(function(){ goTo('s-merch'); }, hasVoucher ? 8000 : 5000);
  }
}

// ===== SHOP DISCOUNT: validace promo + voucher kódů v košíku =====

async function applyShopDiscount(){
  var inp=document.getElementById('shop-discount-input');
  var msg=document.getElementById('shop-discount-msg');
  if(!inp)return;
  var code=inp.value.trim().toUpperCase();
  if(!code){if(msg)msg.innerHTML='<span style="color:var(--red)">Zadejte kód</span>';return;}

  // Check duplicates
  for(var di=0;di<shopAppliedCodes.length;di++){
    if(shopAppliedCodes[di].code===code){
      if(msg)msg.innerHTML='<span style="color:var(--red)">Tento kód je již uplatněn</span>';return;
    }
  }

  if(!window.supabase){if(msg)msg.innerHTML='<span style="color:var(--red)">Offline</span>';return;}

  var cartTotal=cart.reduce(function(s,c){return s+c.price*c.qty;},0);
  var shipCost=shipMode==='post'?99:0;
  var orderTotal=cartTotal+shipCost;

  // 1. Try promo code
  var hasPromo=shopAppliedCodes.some(function(c){return c.type==='promo';});
  if(!hasPromo){
    var pr=await window.supabase.rpc('validate_promo_code',{p_code:code});
    if(pr.data&&pr.data.valid){
      var pd=pr.data;
      var disc=pd.type==='percent'?Math.round(cartTotal*pd.value/100):pd.value;
      if(shopDiscountAmt+disc>=orderTotal){
        if(msg)msg.innerHTML='<span style="color:var(--red)">Sleva přesahuje cenu objednávky</span>';return;
      }
      shopAppliedCodes.push({code:code,type:'promo',id:pd.id,value:pd.value,discountAmt:disc});
      shopDiscountAmt+=disc;
      var label=pd.type==='percent'?'Sleva '+pd.value+'%':'Sleva '+pd.value+' Kč';
      if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 '+label+' uplatněna</span>';
      inp.value='';
      updateCheckoutTotal();
      _renderShopAppliedCodes();
      return;
    }
  }

  // 2. Try voucher code
  var hasVoucher=shopAppliedCodes.some(function(c){return c.type==='voucher';});
  if(!hasVoucher){
    var vr=await window.supabase.rpc('validate_voucher_code',{p_code:code});
    if(vr.data&&vr.data.valid){
      var vd=vr.data;
      var vDisc=Math.min(vd.value, orderTotal-shopDiscountAmt-1);
      if(vDisc<=0){
        if(msg)msg.innerHTML='<span style="color:var(--red)">Poukaz přesahuje cenu objednávky</span>';return;
      }
      shopAppliedCodes.push({code:code,type:'voucher',id:vd.id,value:vd.value,discountAmt:vDisc});
      shopDiscountAmt+=vDisc;
      if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 Poukaz '+vd.value+' Kč uplatněn (sleva '+vDisc+' Kč)</span>';
      inp.value='';
      updateCheckoutTotal();
      _renderShopAppliedCodes();
      return;
    }
  }

  // 3. Already has both types or code not found
  if(hasPromo&&hasVoucher){
    if(msg)msg.innerHTML='<span style="color:var(--red)">Lze uplatnit max 1 promo kód + 1 poukaz</span>';
  } else {
    if(msg)msg.innerHTML='<span style="color:var(--red)">\u2717 Kód nenalezen</span>';
  }
}

function removeShopDiscount(code){
  shopAppliedCodes=shopAppliedCodes.filter(function(c){return c.code!==code;});
  shopDiscountAmt=shopAppliedCodes.reduce(function(s,c){return s+c.discountAmt;},0);
  var msg=document.getElementById('shop-discount-msg');
  if(msg)msg.innerHTML='<span style="color:var(--gd)">Kód '+code+' odebrán</span>';
  var inp=document.getElementById('shop-discount-input');
  if(inp)inp.value='';
  updateCheckoutTotal();
  _renderShopAppliedCodes();
}

function _renderShopAppliedCodes(){
  var wrap=document.getElementById('shop-applied-codes');
  if(!wrap){
    var msg=document.getElementById('shop-discount-msg');
    if(!msg||!msg.parentNode)return;
    wrap=document.createElement('div');
    wrap.id='shop-applied-codes';
    wrap.style.cssText='margin-top:6px;';
    msg.parentNode.insertBefore(wrap,msg.nextSibling);
  }
  if(shopAppliedCodes.length===0){wrap.innerHTML='';return;}
  wrap.innerHTML=shopAppliedCodes.map(function(c){
    return '<div style="display:flex;align-items:center;gap:6px;padding:6px 10px;background:var(--gp);border:1px solid var(--green);border-radius:8px;margin-bottom:4px;font-size:12px;font-weight:700;color:var(--gd);">'+
      '<span>'+c.code+' (-'+c.discountAmt.toLocaleString('cs-CZ')+' Kč)</span>'+
      '<button onclick="removeShopDiscount(\''+c.code+'\')" style="background:#fee2e2;color:#b91c1c;border:none;border-radius:6px;width:22px;height:22px;font-size:12px;font-weight:800;cursor:pointer;margin-left:auto;padding:0;">✕</button>'+
      '</div>';
  }).join('');
}

function initCheckout(){
  shopDiscountAmt=0;
  shopAppliedCodes=[];
  renderCart();
  selectShipping(shipMode);
  autofillCheckout();
  updateCheckoutTotal();
}
async function autofillCheckout(){
  try {
    var profile = await apiFetchProfile();
    var nameEl=document.getElementById('ship-name');
    var streetEl=document.getElementById('ship-street');
    var zipEl=document.getElementById('ship-zip');
    var cityEl=document.getElementById('ship-city');
    if(profile){
      if(nameEl&&!nameEl.value) nameEl.value=profile.full_name||'';
      if(streetEl&&!streetEl.value) streetEl.value=profile.street||'';
      if(zipEl&&!zipEl.value) zipEl.value=profile.zip||'';
      if(cityEl&&!cityEl.value) cityEl.value=profile.city||'';
    }
    var namePreview=document.getElementById('ship-details-name');
    if(namePreview && profile) namePreview.textContent='\u00b7 '+profile.full_name;
  } catch(e){ console.error('autofillCheckout error:', e); }
}

function toggleShipDetails(){
  var el=document.getElementById('ship-address');
  var arr=document.getElementById('ship-details-arrow');
  if(!el)return;
  var open=el.style.display!=='none';
  el.style.display=open?'none':'block';
  if(arr)arr.style.transform=open?'rotate(0deg)':'rotate(90deg)';
}

// ===== BOOKING PRICE FUNCTIONS =====

function recalcTotal(){
  // Use day-of-week pricing if moto and dates available
  var base=0;
  if(typeof calcTotalPrice==='function'&&bookingMoto&&bOd&&bDo){
    base=calcTotalPrice(bookingMoto,new Date(bOd.y,bOd.m,bOd.d),new Date(bDo.y,bDo.m,bDo.d));
  } else {
    base=2600*bookingDays;
  }
  var total=base+extraTotal+deliveryFee-discountAmt;
  var baseEl=document.getElementById('pr-base');
  if(baseEl)baseEl.textContent=base.toLocaleString('cs-CZ')+' Kč';
  var lblEl=document.getElementById('pr-base-label');
  if(lblEl){
    var avgDay=bookingDays>0?Math.round(base/bookingDays):0;
    lblEl.textContent=avgDay.toLocaleString('cs-CZ')+' Kč/den × '+bookingDays+' '+(bookingDays===1?'den':'dní');
  }
  var el=document.getElementById('pr-total');
  if(el)el.textContent=total.toLocaleString('cs-CZ')+' Kč';
  var dr=document.getElementById('pr-delivery-row'),da=document.getElementById('pr-delivery-amt');
  if(dr&&da){dr.style.display=deliveryFee>0?'flex':'none';da.textContent=deliveryFee+' Kč';}
  var er=document.getElementById('pr-extras-row'),ea=document.getElementById('pr-extras-amt');
  if(er&&ea){er.style.display=extraTotal>0?'flex':'none';ea.textContent=extraTotal+' Kč';}
  var dcr=document.getElementById('pr-discount-row'),dca=document.getElementById('pr-discount-amt');
  if(dcr&&dca){dcr.style.display=discountAmt>0?'flex':'none';dca.textContent='-'+discountAmt+' Kč';}
}

function toggleExtra(label,price){
  const chk=label.querySelector('input[type=checkbox]');
  // Recalculate extraTotal from all checked extras
  extraTotal=0;
  document.querySelectorAll('#s-booking label[id^="extra-"]').forEach(function(lbl){
    var cb=lbl.querySelector('input[type=checkbox]');
    if(cb&&cb.checked){
      var priceAttr=lbl.getAttribute('data-price');
      if(priceAttr) extraTotal+=parseInt(priceAttr);
      lbl.style.borderColor='var(--green)';
    } else if(cb) {
      lbl.style.borderColor='var(--g200)';
    }
  });
  recalcTotal();
}

function _setDelivMode(type,val){
  var det=document.getElementById(type+'-detail');
  var sl=document.getElementById(type+'-store-label');
  var dl=document.getElementById(type+'-delivery-label');
  var isStore=val==='store';
  if(det)det.style.display=isStore?'none':'block';
  if(sl){sl.style.borderColor=isStore?'var(--green)':'var(--g200)';sl.style.background=isStore?'var(--gp)':'var(--g100)';}
  if(dl){dl.style.borderColor=isStore?'var(--g200)':'var(--green)';dl.style.background=isStore?'var(--g100)':'var(--gp)';}
  if(type==='pickup')pickupDelivFee=isStore?0:1000;
  else returnDelivFee=isStore?0:1000;
  deliveryFee=pickupDelivFee+returnDelivFee;
  recalcTotal();
}
function setPickup(val){_setDelivMode('pickup',val);}
function setReturn(val){_setDelivMode('return',val);}

function calcDelivery(type){
  var inp=document.getElementById(type+'-addr-input');
  var calcEl=document.getElementById(type+'-price-calc');
  var kmTxt=document.getElementById(type+'-km-txt');
  if(!inp||!inp.value.trim()){if(calcEl)calcEl.style.display='none';return;}
  var addr=inp.value.trim();

  // Use OSRM API if AddressAPI available + coordinates cached
  if(typeof AddressAPI !== 'undefined'){
    var coords = (inp.dataset.lat && inp.dataset.lng)
      ? {lat: parseFloat(inp.dataset.lat), lng: parseFloat(inp.dataset.lng)}
      : addr;
    if(kmTxt) kmTxt.textContent='Vypočítávám vzdálenost...';
    if(calcEl) calcEl.style.display='block';
    AddressAPI.calcDistance(coords, function(result){
      if(!result){ _calcDeliveryFallback(type, addr, calcEl, kmTxt); return; }
      var km=result.km; var fee=result.fee;
      if(type==='pickup'){pickupDelivFee=fee;}else{returnDelivFee=fee;}
      deliveryFee=pickupDelivFee+returnDelivFee;
      if(calcEl)calcEl.style.display='block';
      var txt='📍 ~'+km+' km · '+fee.toLocaleString('cs-CZ')+' Kč';
      if(result.duration) txt+=' · ~'+result.duration+' min';
      if(result.approx) txt+=' (odhad)';
      if(kmTxt)kmTxt.textContent=txt;
      recalcTotal();
    });
    return;
  }

  _calcDeliveryFallback(type, addr, calcEl, kmTxt);
}

function _calcDeliveryFallback(type, addr, calcEl, kmTxt){
  var km=null;
  for(var city in KM_ESTIMATES){
    if(addr.toLowerCase().indexOf(city.toLowerCase())!==-1){km=KM_ESTIMATES[city];break;}
  }
  if(!km){km=Math.round(20+addr.length*1.5);if(km>200)km=200;}
  var fee=1000+km*20;
  if(type==='pickup'){pickupDelivFee=fee;}else{returnDelivFee=fee;}
  deliveryFee=pickupDelivFee+returnDelivFee;
  if(calcEl)calcEl.style.display='block';
  if(kmTxt)kmTxt.textContent='📍 ~'+km+' km · '+fee.toLocaleString('cs-CZ')+' Kč (odhad)';
  recalcTotal();
}

var _appliedPromoId = null;
var _appliedBookingCodes = []; // [{code, type:'promo'|'voucher', id, discountAmt}]

function removeDiscount(){
  discountAmt=0;
  appliedCode=null;
  _appliedPromoId=null;
  _appliedBookingCodes=[];
  var inp=document.getElementById('discount-input');
  if(inp){inp.value='';inp.style.borderColor='var(--g200)';}
  var msg=document.getElementById('discount-msg');
  if(msg)msg.innerHTML='';
  var wrap=document.getElementById('booking-applied-codes');
  if(wrap)wrap.innerHTML='';
  recalcTotal();
}

function _renderBookingAppliedCodes(){
  var wrap=document.getElementById('booking-applied-codes');
  if(!wrap){
    var msg=document.getElementById('discount-msg');
    if(!msg||!msg.parentNode)return;
    wrap=document.createElement('div');
    wrap.id='booking-applied-codes';
    wrap.style.cssText='margin-top:6px;';
    msg.parentNode.appendChild(wrap);
  }
  if(_appliedBookingCodes.length===0){wrap.innerHTML='';return;}
  wrap.innerHTML=_appliedBookingCodes.map(function(c){
    return '<div style="display:flex;align-items:center;gap:6px;padding:5px 10px;background:var(--gp);border:1px solid var(--green);border-radius:8px;margin-bottom:4px;font-size:11px;font-weight:700;color:var(--gd);">'+
      '<span>'+c.code+' (-'+c.discountAmt.toLocaleString('cs-CZ')+' Kč)</span>'+
      '<button onclick="removeOneDiscount(\''+c.code+'\')" style="background:#fee2e2;color:#b91c1c;border:none;border-radius:6px;width:20px;height:20px;font-size:11px;font-weight:800;cursor:pointer;margin-left:auto;padding:0;">✕</button>'+
      '</div>';
  }).join('');
}

function removeOneDiscount(code){
  _appliedBookingCodes=_appliedBookingCodes.filter(function(c){return c.code!==code;});
  discountAmt=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
  appliedCode=_appliedBookingCodes.length>0?_appliedBookingCodes[_appliedBookingCodes.length-1].code:null;
  _appliedPromoId=_appliedBookingCodes.length>0?_appliedBookingCodes[_appliedBookingCodes.length-1].id:null;
  _renderBookingAppliedCodes();
  var msg=document.getElementById('discount-msg');
  if(msg)msg.innerHTML='<span style="color:var(--gd)">Kód '+code+' odebrán</span>';
  recalcTotal();
}

async function applyDiscount(){
  var code=(document.getElementById('discount-input')||{value:''}).value.trim().toUpperCase();
  var msg=document.getElementById('discount-msg');
  var inp=document.getElementById('discount-input');
  if(!code){if(msg)msg.innerHTML='<span style="color:var(--red)">'+_t('cart').enterCode+'</span>';return;}

  // Check duplicates
  for(var di=0;di<_appliedBookingCodes.length;di++){
    if(_appliedBookingCodes[di].code===code){
      if(msg)msg.innerHTML='<span style="color:var(--red)">Tento kód je již uplatněn</span>';return;
    }
  }

  // Supabase DB validace — single source of truth
  if(window.supabase){
    try {
      var baseForDiscount=0;
      if(typeof calcTotalPrice==='function'&&bookingMoto&&bOd&&bDo){
        baseForDiscount=calcTotalPrice(bookingMoto,new Date(bOd.y,bOd.m,bOd.d),new Date(bDo.y,bDo.m,bDo.d));
      } else { baseForDiscount=2600*(bookingDays||1); }

      var r = await window.supabase.rpc('validate_promo_code', { p_code: code });
      if(r.data && r.data.valid){
        var promoData = r.data;
        var disc=promoData.type==='percent'?Math.round(baseForDiscount*promoData.value/100):promoData.value;
        _appliedBookingCodes.push({code:code,type:'promo',id:promoData.id,discountAmt:disc});
        _appliedPromoId = promoData.id;
        appliedCode = code;
        discountAmt=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
        var label=promoData.type==='percent'?promoData.value+'%':promoData.value+' Kč';
        if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 '+_t('cart').discount+' '+label+' '+_t('cart').applied+'</span>';
        showT('\ud83c\udff7\ufe0f',_t('cart').discount+' '+label,_t('cart').youSave+' '+disc+' K\u010d');
        if(inp)inp.value='';
        _renderBookingAppliedCodes();
        recalcTotal();
      } else {
        // Promo code not found — try voucher
        var vr = await window.supabase.rpc('validate_voucher_code', { p_code: code });
        if(vr.data && vr.data.valid){
          var vData = vr.data;
          _appliedBookingCodes.push({code:code,type:'voucher',id:vData.id,discountAmt:vData.value});
          _appliedPromoId = vData.id;
          appliedCode = code;
          discountAmt=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
          if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 '+(_t('cart').voucher||'Poukaz')+' '+vData.value+' K\u010d '+_t('cart').applied+'</span>';
          showT('\ud83c\udf81',(_t('cart').voucher||'Poukaz')+' '+vData.value+' K\u010d','');
          if(inp)inp.value='';
          _renderBookingAppliedCodes();
          recalcTotal();
        } else {
          var errMsg = (r.data && r.data.error) ? r.data.error : _t('cart').codeNotFound;
          if(msg)msg.innerHTML='<span style="color:var(--red)">\u2717 '+errMsg+'</span>';
          if(inp)inp.style.borderColor='var(--red)';
        }
      }
      return;
    } catch(e){ console.error('[PROMO] DB validation failed:', e); }
  }

  // Hardcoded fallback (offline)
  if(typeof CODES !== 'undefined' && CODES[code]){
    var pct=CODES[code];
    var base2=0;
    if(typeof calcTotalPrice==='function'&&bookingMoto&&bOd&&bDo){
      base2=calcTotalPrice(bookingMoto,new Date(bOd.y,bOd.m,bOd.d),new Date(bDo.y,bDo.m,bDo.d));
    } else { base2=2600*(bookingDays||1); }
    var disc2=Math.round(base2*pct/100);
    _appliedBookingCodes.push({code:code,type:'promo',id:null,discountAmt:disc2});
    discountAmt=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
    appliedCode = code;
    if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 '+_t('cart').discount+' '+pct+'% '+_t('cart').applied+'</span>';
    if(inp)inp.value='';
    _renderBookingAppliedCodes();
    recalcTotal();
    showT('\ud83c\udff7\ufe0f',_t('cart').discount+' '+pct+'%',_t('cart').youSave+' '+disc2+' K\u010d');
  } else {
    if(msg)msg.innerHTML='<span style="color:var(--red)">\u2717 '+_t('cart').codeNotFound+'</span>';
    if(inp)inp.style.borderColor='var(--red)';
  }
}

function updateBookingPrice(){
  if(!bOd||!bDo)return;
  var days=Math.max(1,Math.round((new Date(bDo.y,bDo.m,bDo.d)-new Date(bOd.y,bOd.m,bOd.d))/86400000)+1);
  bookingDays=days;
  // Use day-of-week pricing via booking-utils
  if(typeof calcTotalPrice==='function'&&bookingMoto){
    var base=calcTotalPrice(bookingMoto,new Date(bOd.y,bOd.m,bOd.d),new Date(bDo.y,bDo.m,bDo.d));
    var avg=Math.round(base/days);
    var el=document.getElementById('pr-base');
    if(el)el.textContent=avg.toLocaleString('cs-CZ')+' Kč/den × '+days+' '+(days===1?'den':'dní');
    // Show price below calendar
    var calPrice=document.getElementById('b-cal-price');
    var calPriceVal=document.getElementById('b-cal-price-val');
    if(calPrice&&calPriceVal){
      var total=base+extraTotal+deliveryFee-discountAmt;
      calPriceVal.textContent=total.toLocaleString('cs-CZ')+' Kč';
      calPrice.style.display='block';
    }
  }
  recalcTotal();
}

// ===== ADDRESS AUTOCOMPLETE SUGGESTIONS =====
var ADDR_DB=[
  // Praha
  {addr:'Václavské náměstí 1, 110 00 Praha 1',city:'Praha'},
  {addr:'Náměstí Míru 12, 120 00 Praha 2',city:'Praha'},
  {addr:'Na Příkopě 22, 110 00 Praha 1',city:'Praha'},
  {addr:'Smíchovské nádraží, 150 00 Praha 5',city:'Praha'},
  {addr:'Letňany OC, 190 00 Praha 9',city:'Praha'},
  {addr:'Karlovo náměstí 5, 120 00 Praha 2',city:'Praha'},
  {addr:'Vinohradská 50, 120 00 Praha 2',city:'Praha'},
  {addr:'Dejvická 4, 160 00 Praha 6',city:'Praha'},
  {addr:'Budějovická 1, 140 00 Praha 4',city:'Praha'},
  {addr:'Žižkov - Koněvova 100, 130 00 Praha 3',city:'Praha'},
  {addr:'Holešovice - Argentinská 30, 170 00 Praha 7',city:'Praha'},
  {addr:'Černý Most - Chlumecká 6, 198 00 Praha 9',city:'Praha'},
  {addr:'Chodov - Roztylská 19, 148 00 Praha 4',city:'Praha'},
  {addr:'Zličín OC, 155 00 Praha 5',city:'Praha'},
  // Brno
  {addr:'Masarykova 10, 602 00 Brno',city:'Brno'},
  {addr:'Náměstí Svobody 5, 602 00 Brno',city:'Brno'},
  {addr:'Česká 28, 602 00 Brno',city:'Brno'},
  {addr:'Kounicova 46, 612 00 Brno',city:'Brno'},
  {addr:'Vídeňská 120, 619 00 Brno',city:'Brno'},
  // Ostrava
  {addr:'Nádražní 7, 702 00 Ostrava',city:'Ostrava'},
  {addr:'Masarykovo náměstí 1, 702 00 Ostrava',city:'Ostrava'},
  {addr:'28. října 100, 702 00 Ostrava',city:'Ostrava'},
  {addr:'Poruba - Hlavní třída 50, 708 00 Ostrava',city:'Ostrava'},
  // Plzeň
  {addr:'Náměstí Republiky 1, 301 00 Plzeň',city:'Plzeň'},
  {addr:'Americká 42, 301 00 Plzeň',city:'Plzeň'},
  {addr:'Borská 15, 320 00 Plzeň',city:'Plzeň'},
  // Liberec
  {addr:'Náměstí Dr. E. Beneše 1, 460 59 Liberec',city:'Liberec'},
  {addr:'Pražská 20, 460 01 Liberec',city:'Liberec'},
  // Olomouc
  {addr:'Horní náměstí 1, 779 00 Olomouc',city:'Olomouc'},
  {addr:'Třída Svobody 10, 779 00 Olomouc',city:'Olomouc'},
  // České Budějovice
  {addr:'Lannova 1, 370 01 České Budějovice',city:'České Budějovice'},
  {addr:'Náměstí Přemysla Otakara II. 5, 370 01 České Budějovice',city:'České Budějovice'},
  // Hradec Králové
  {addr:'Velké náměstí 1, 500 02 Hradec Králové',city:'Hradec Králové'},
  {addr:'Gočárova třída 15, 500 02 Hradec Králové',city:'Hradec Králové'},
  // Ústí nad Labem
  {addr:'Mírové náměstí 1, 400 01 Ústí nad Labem',city:'Ústí nad Labem'},
  // Pardubice
  {addr:'Třída Míru 60, 530 02 Pardubice',city:'Pardubice'},
  {addr:'Pernštýnské náměstí 1, 530 02 Pardubice',city:'Pardubice'},
  // Zlín
  {addr:'Náměstí Míru 12, 760 01 Zlín',city:'Zlín'},
  {addr:'Třída Tomáše Bati 20, 760 01 Zlín',city:'Zlín'},
  // Havířov
  {addr:'Hlavní třída 1, 736 01 Havířov',city:'Havířov'},
  // Kladno
  {addr:'Náměstí Starosty Pavla 1, 272 01 Kladno',city:'Kladno'},
  // Most
  {addr:'1. náměstí 1, 434 01 Most',city:'Most'},
  // Opava
  {addr:'Horní náměstí 1, 746 01 Opava',city:'Opava'},
  // Frýdek-Místek
  {addr:'Náměstí Svobody 1, 738 01 Frýdek-Místek',city:'Frýdek-Místek'},
  // Karviná
  {addr:'Fryštátská 72, 733 01 Karviná',city:'Karviná'},
  // Jihlava
  {addr:'Husova 8, 586 01 Jihlava',city:'Jihlava'},
  {addr:'Masarykovo náměstí 1, 586 01 Jihlava',city:'Jihlava'},
  // Teplice
  {addr:'Náměstí Svobody 2, 415 01 Teplice',city:'Teplice'},
  // Děčín
  {addr:'Masarykovo náměstí 1, 405 02 Děčín',city:'Děčín'},
  // Karlovy Vary
  {addr:'Třída T. G. Masaryka 10, 360 01 Karlovy Vary',city:'Karlovy Vary'},
  {addr:'Vřídelní 2, 360 01 Karlovy Vary',city:'Karlovy Vary'},
  // Chomutov
  {addr:'Náměstí 1. máje 1, 430 01 Chomutov',city:'Chomutov'},
  // Jablonec nad Nisou
  {addr:'Mírové náměstí 19, 466 01 Jablonec nad Nisou',city:'Jablonec nad Nisou'},
  // Prostějov
  {addr:'Náměstí T. G. Masaryka 1, 796 01 Prostějov',city:'Prostějov'},
  // Přerov
  {addr:'Náměstí T. G. Masaryka 1, 750 02 Přerov',city:'Přerov'},
  // Mladá Boleslav
  {addr:'Staroměstské náměstí 1, 293 01 Mladá Boleslav',city:'Mladá Boleslav'},
  // Česká Lípa
  {addr:'Náměstí T. G. Masaryka 1, 470 01 Česká Lípa',city:'Česká Lípa'},
  // Třebíč
  {addr:'Karlovo náměstí 20, 674 01 Třebíč',city:'Třebíč'},
  // Třinec
  {addr:'Náměstí Svobody 1, 739 61 Třinec',city:'Třinec'},
  // Tábor
  {addr:'Komenského 15, 390 01 Tábor',city:'Tábor'},
  {addr:'Žižkovo náměstí 2, 390 01 Tábor',city:'Tábor'},
  // Znojmo
  {addr:'Masarykovo náměstí 1, 669 02 Znojmo',city:'Znojmo'},
  // Příbram
  {addr:'Náměstí T. G. Masaryka 1, 261 01 Příbram',city:'Příbram'},
  // Cheb
  {addr:'Náměstí Krále Jiřího 1, 350 02 Cheb',city:'Cheb'},
  // Kolín
  {addr:'Karlovo náměstí 78, 280 02 Kolín',city:'Kolín'},
  // Trutnov
  {addr:'Krakonošovo náměstí 1, 541 01 Trutnov',city:'Trutnov'},
  // Písek
  {addr:'Velké náměstí 1, 397 01 Písek',city:'Písek'},
  // Kroměříž
  {addr:'Velké náměstí 1, 767 01 Kroměříž',city:'Kroměříž'},
  // Šumperk
  {addr:'Náměstí Míru 1, 787 01 Šumperk',city:'Šumperk'},
  // Vsetín
  {addr:'Svárov 1080, 755 01 Vsetín',city:'Vsetín'},
  // Valašské Meziříčí
  {addr:'Náměstí 7, 757 01 Valašské Meziříčí',city:'Valašské Meziříčí'},
  // Litoměřice
  {addr:'Mírové náměstí 15, 412 01 Litoměřice',city:'Litoměřice'},
  // Uherské Hradiště
  {addr:'Masarykovo náměstí 19, 686 01 Uherské Hradiště',city:'Uherské Hradiště'},
  // Břeclav
  {addr:'Náměstí T. G. Masaryka 1, 690 02 Břeclav',city:'Břeclav'},
  // Hodonín
  {addr:'Masarykovo náměstí 1, 695 01 Hodonín',city:'Hodonín'},
  // Vyškov
  {addr:'Masarykovo náměstí 1, 682 01 Vyškov',city:'Vyškov'},
  // Blansko
  {addr:'Náměstí Svobody 1, 678 01 Blansko',city:'Blansko'},
  // Klatovy
  {addr:'Náměstí Míru 62, 339 01 Klatovy',city:'Klatovy'},
  // Sokolov
  {addr:'Staré náměstí 1, 356 01 Sokolov',city:'Sokolov'},
  // Nový Jičín
  {addr:'Masarykovo náměstí 1, 741 01 Nový Jičín',city:'Nový Jičín'},
  // Žďár nad Sázavou
  {addr:'Žižkova 4, 591 01 Žďár nad Sázavou',city:'Žďár nad Sázavou'},
  // Pelhřimov
  {addr:'Hlavní 5, 393 01 Pelhřimov',city:'Pelhřimov'},
  {addr:'Masarykovo náměstí 1, 393 01 Pelhřimov',city:'Pelhřimov'},
  // Benešov
  {addr:'Masarykovo náměstí 1, 256 01 Benešov',city:'Benešov'},
  // Beroun
  {addr:'Husovo náměstí 68, 266 01 Beroun',city:'Beroun'},
  // Kutná Hora
  {addr:'Havlíčkovo náměstí 552, 284 01 Kutná Hora',city:'Kutná Hora'},
  // Chrudim
  {addr:'Resselovo náměstí 1, 537 01 Chrudim',city:'Chrudim'},
  // Svitavy
  {addr:'Náměstí Míru 1, 568 02 Svitavy',city:'Svitavy'},
  // Náchod
  {addr:'Masarykovo náměstí 40, 547 01 Náchod',city:'Náchod'},
  // Rychnov nad Kněžnou
  {addr:'Havlíčkova 136, 516 01 Rychnov nad Kněžnou',city:'Rychnov nad Kněžnou'},
  // Strakonice
  {addr:'Velké náměstí 2, 386 01 Strakonice',city:'Strakonice'},
  // Prachatice
  {addr:'Velké náměstí 3, 383 01 Prachatice',city:'Prachatice'},
  // Domažlice
  {addr:'Náměstí Míru 1, 344 01 Domažlice',city:'Domažlice'},
  // Rokycany
  {addr:'Masarykovo náměstí 1, 337 01 Rokycany',city:'Rokycany'},
  // Louny
  {addr:'Mírové náměstí 1, 440 01 Louny',city:'Louny'},
  // Rakovník
  {addr:'Husovo náměstí 27, 269 01 Rakovník',city:'Rakovník'},
  // Mělník
  {addr:'Náměstí Míru 1, 276 01 Mělník',city:'Mělník'},
  // Nymburk
  {addr:'Náměstí Přemyslovců 1, 288 02 Nymburk',city:'Nymburk'},
  // Semily
  {addr:'Husova 82, 513 01 Semily',city:'Semily'},
  // Havlíčkův Brod
  {addr:'Smetanovo náměstí 2, 580 01 Havlíčkův Brod',city:'Havlíčkův Brod'},
  {addr:'Havlíčkovo náměstí 57, 580 01 Havlíčkův Brod',city:'Havlíčkův Brod'},
  // Humpolec
  {addr:'Pražská 100, 396 01 Humpolec',city:'Humpolec'},
  {addr:'Horní náměstí 300, 396 01 Humpolec',city:'Humpolec'},
  // Mezná (domovská pobočka)
  {addr:'Mezná 9, 393 01 Mezná',city:'Mezná'},
  // Pacov
  {addr:'Náměstí Svobody 1, 395 01 Pacov',city:'Pacov'},
  // Kamenice nad Lipou
  {addr:'Náměstí Čsl. armády 1, 394 70 Kamenice nad Lipou',city:'Kamenice nad Lipou'}
];

// ===== STEPPED ADDRESS AUTOCOMPLETE: City → Street+č.p. → PSČ =====

/**
 * Show STREET suggestions — reads city from the city field to scope results
 */
function showAddrSuggestions(inp,type){
  var sugEl=document.getElementById(type+'-addr-suggestions');
  if(!sugEl)return;
  var val=(inp.value||'').trim();
  if(val.length<2){sugEl.style.display='none';return;}

  // Get the city from the associated city field (for scoped street search)
  var cityInputMap={'ship':'ship-city','b-contact':'b-contact-city','sos-repl':'sos-repl-city'};
  var cityEl=document.getElementById(cityInputMap[type]||'')||document.getElementById(type+'-city');
  var city=(cityEl && cityEl.value) ? cityEl.value.trim() : '';

  // Use stepped API: suggestStreets(query, city) if city is filled, else generic suggest
  if(typeof AddressAPI !== 'undefined'){
    if(city){
      AddressAPI.suggestStreetsDebounced(val, city, function(results){
        if(!results || results.length===0){sugEl.style.display='none';return;}
        _renderStreetSuggestions(sugEl, results, type);
        sugEl.style.display='block';
      });
    } else {
      AddressAPI.suggestDebounced(val, function(results){
        if(!results || results.length===0){sugEl.style.display='none';return;}
        _renderStreetSuggestions(sugEl, results, type);
        sugEl.style.display='block';
      });
    }
    return;
  }

  // Fallback to local ADDR_DB
  var q=val.toLowerCase();
  var matches=ADDR_DB.filter(function(a){
    if(city && a.city.toLowerCase() !== city.toLowerCase()) return false;
    return a.addr.toLowerCase().indexOf(q)!==-1;
  }).slice(0,8);
  if(matches.length===0){sugEl.style.display='none';return;}
  var results=matches.map(function(a){
    var zipMatch=a.addr.match(/(\d{3})\s?(\d{2})/);
    var streetMatch=a.addr.match(/^([^,]+?)(?:,\s*\d)/);
    var street=streetMatch?streetMatch[1]:'';
    var numMatch=street.match(/^(.+?)\s+(\d+.*)$/);
    return {label:a.addr,lat:null,lng:null,street:numMatch?numMatch[1]:street,houseNum:numMatch?numMatch[2]:'',district:'',city:a.city,zip:zipMatch?zipMatch[1]+' '+zipMatch[2]:''};
  });
  _renderStreetSuggestions(sugEl, results, type);
  sugEl.style.display='block';
}

/**
 * Show CITY suggestions — for city input fields (stepped: city first)
 */
function showCitySuggestionsFor(inp,type){
  var sugEl=document.getElementById(type+'-city-suggestions');
  if(!sugEl)return;
  var val=(inp.value||'').trim();
  if(val.length<2){sugEl.style.display='none';return;}

  if(typeof AddressAPI !== 'undefined'){
    AddressAPI.suggestCitiesDebounced(val, function(results){
      if(!results || results.length===0){sugEl.style.display='none';return;}
      _renderCitySuggestions(sugEl, results, type);
      sugEl.style.display='block';
    });
    return;
  }

  // Fallback: unique cities from ADDR_DB
  var q=val.toLowerCase();
  var seen={};
  var matches=ADDR_DB.filter(function(a){
    if(seen[a.city]) return false;
    var ok=a.city.toLowerCase().indexOf(q)!==-1;
    if(ok) seen[a.city]=true;
    return ok;
  }).slice(0,8);
  if(matches.length===0){sugEl.style.display='none';return;}
  var results=matches.map(function(a){
    var zipMatch=a.addr.match(/(\d{3})\s?(\d{2})/);
    return {label:a.city, city:a.city, zip:zipMatch?zipMatch[1]+' '+zipMatch[2]:'', district:'', lat:null, lng:null};
  });
  _renderCitySuggestions(sugEl, results, type);
  sugEl.style.display='block';
}

/**
 * Render CITY suggestion items
 */
function _renderCitySuggestions(sugEl, results, type){
  sugEl.innerHTML='';
  results.forEach(function(r){
    var div=document.createElement('div');
    div.className='addr-sug-item';
    var sub = r.district ? r.district : (r.zip || '');
    if(sub){
      div.innerHTML='<div style="display:flex;align-items:center;gap:8px;">'+
        '<span style="color:var(--green);font-size:15px;line-height:1;">🏙️</span>'+
        '<div><div style="font-weight:700;font-size:13px;line-height:1.3;">'+_esc(r.city)+'</div>'+
        '<div style="font-size:11px;color:var(--g400);font-weight:500;line-height:1.3;">'+_esc(sub)+'</div></div></div>';
    } else {
      div.innerHTML='<span style="color:var(--green);font-size:15px;">🏙️</span> <span style="font-weight:700;">'+_esc(r.city)+'</span>';
    }
    function handler(e){
      e.preventDefault();
      e.stopPropagation();
      _selectCityFor(type, r.city, r.zip||'');
    }
    div.addEventListener('mousedown', handler);
    div.addEventListener('touchstart', handler, {passive:false});
    sugEl.appendChild(div);
  });
}

/**
 * Handle city selection — fills city+PSČ, clears street, focuses street field
 */
function _selectCityFor(type, city, zip){
  var cityInputMap={'ship':'ship-city','b-contact':'b-contact-city','sos-repl':'sos-repl-city'};
  var zipInputMap={'ship':'ship-zip','b-contact':'b-contact-zip','sos-repl':'sos-repl-zip'};
  var addrInputMap={'ship':'ship-street','b-contact':'b-contact-street','sos-repl':'sos-repl-address'};

  var cityEl=document.getElementById(cityInputMap[type]||'')||document.getElementById(type+'-city');
  if(cityEl) cityEl.value=city;

  // Fill PSČ if available
  if(zip){
    var zipEl=document.getElementById(zipInputMap[type]||'')||document.getElementById(type+'-zip');
    if(zipEl) zipEl.value=zip;
  }

  // Hide city suggestions
  var sugEl=document.getElementById(type+'-city-suggestions');
  if(sugEl) sugEl.style.display='none';

  // Focus the street input so user can continue
  var addrEl=document.getElementById(addrInputMap[type]||'')||document.getElementById(type+'-addr-input')||document.getElementById(type+'-address');
  if(addrEl){ addrEl.value=''; setTimeout(function(){ addrEl.focus(); }, 100); }

  if(typeof updateEditPriceSummary==='function') updateEditPriceSummary();
  if(type==='sos-repl' && typeof sosReplCalcDelivery==='function') sosReplCalcDelivery();
}

/**
 * Render STREET suggestion items (with city+PSČ secondary line)
 */
function _renderStreetSuggestions(sugEl, results, type){
  sugEl.innerHTML='';
  results.forEach(function(r){
    var div=document.createElement('div');
    div.className='addr-sug-item';
    var streetLine = r.street ? (r.street + (r.houseNum ? ' ' + r.houseNum : '')) : r.label;
    var cityLine = r.city || '';
    if(r.zip && cityLine) cityLine = r.zip + ' ' + cityLine;
    if(r.district && r.district !== r.city) cityLine += ' · ' + r.district;
    if(cityLine && r.street){
      div.innerHTML='<div style="display:flex;align-items:flex-start;gap:8px;">'+
        '<span style="color:var(--green);font-size:15px;line-height:1;">📍</span>'+
        '<div><div style="font-weight:700;font-size:13px;line-height:1.3;">'+_esc(streetLine)+'</div>'+
        '<div style="font-size:11px;color:var(--g400);font-weight:500;line-height:1.3;">'+_esc(cityLine)+'</div></div></div>';
    } else {
      div.innerHTML='<span style="color:var(--green);font-size:15px;">📍</span> <span style="font-weight:600;">'+_esc(streetLine)+'</span>';
    }
    function handler(e){
      e.preventDefault();
      e.stopPropagation();
      // Put only street+number in address input (not the full label with city)
      var addrVal = r.street ? (r.street + (r.houseNum ? ' ' + r.houseNum : '')) : r.label;
      selectAddr(type, addrVal, r.city||'', r.lat||null, r.lng||null);
      // Fill PSČ from structured data
      if(r.zip){
        var zipMaps={'ship':'ship-zip','b-contact':'b-contact-zip','sos-repl':'sos-repl-zip'};
        var zipEl=document.getElementById(zipMaps[type]||'')||document.getElementById(type+'-zip');
        if(zipEl) zipEl.value=r.zip;
      }
    }
    div.addEventListener('mousedown', handler);
    div.addEventListener('touchstart', handler, {passive:false});
    sugEl.appendChild(div);
  });
}
function _esc(s){return s?s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'):'';}

// Legacy city suggestions for edit-return (now uses generic function)
function showCitySuggestions(inp){
  showCitySuggestionsFor(inp,'edit-return');
}
function selectCity(city){
  _selectCityFor('edit-return', city, '');
}

/**
 * Use device GPS to fill address fields (city, street, PSČ)
 */
function useMyLocation(type){
  if(!navigator.geolocation){
    showT('\u26a0\ufe0f','GPS','Geolokace není k dispozici');
    return;
  }
  // Visual feedback
  var addrInputMap={'ship':'ship-street','b-contact':'b-contact-street','sos-repl':'sos-repl-address'};
  var cityInputMap={'ship':'ship-city','b-contact':'b-contact-city','sos-repl':'sos-repl-city'};
  var zipInputMap={'ship':'ship-zip','b-contact':'b-contact-zip','sos-repl':'sos-repl-zip'};
  var cityEl=document.getElementById(cityInputMap[type]||'')||document.getElementById(type+'-city');
  if(cityEl) cityEl.value='Hledám polohu...';

  navigator.geolocation.getCurrentPosition(function(pos){
    var lat=pos.coords.latitude;
    var lng=pos.coords.longitude;
    if(typeof AddressAPI==='undefined' || typeof AddressAPI.reverseGeocode!=='function'){
      if(cityEl) cityEl.value='';
      showT('\u26a0\ufe0f','Chyba','Reverzní geokódování nedostupné');
      return;
    }
    AddressAPI.reverseGeocode(lat, lng, function(result){
      if(!result){
        if(cityEl) cityEl.value='';
        showT('\u26a0\ufe0f','Chyba','Nepodařilo se zjistit adresu');
        return;
      }
      // Fill city
      if(cityEl) cityEl.value=result.city||'';
      // Fill ZIP
      var zipEl=document.getElementById(zipInputMap[type]||'')||document.getElementById(type+'-zip');
      if(zipEl && result.zip) zipEl.value=result.zip;
      // Fill street
      var addrEl=document.getElementById(addrInputMap[type]||'')||document.getElementById(type+'-addr-input')||document.getElementById(type+'-address');
      if(addrEl){
        var street=result.street||'';
        if(result.houseNum) street+=(street?' ':'')+result.houseNum;
        addrEl.value=street;
        addrEl.dataset.lat=lat;
        addrEl.dataset.lng=lng;
      }
      // Trigger delivery calculation
      if(type==='pickup'||type==='return'){calcDelivery(type);}
      if(type==='edit-pickup'&&typeof _sosCalcPickupDelivery==='function'){_sosCalcPickupDelivery();}
      if(type==='edit-return'&&typeof calcEditDelivery==='function'){calcEditDelivery();}
      if(type==='sos-repl'&&typeof sosReplCalcDelivery==='function'){sosReplCalcDelivery();}
    });
  }, function(err){
    if(cityEl) cityEl.value='';
    var msg='Poloha zamítnuta';
    if(err.code===2) msg='Poloha nedostupná';
    if(err.code===3) msg='Vypršel čas';
    showT('\u26a0\ufe0f','GPS',msg);
  }, {enableHighAccuracy:true, timeout:10000, maximumAge:60000});
}

function selectAddr(type,addr,city,lat,lng){
  // Map special types to their input IDs
  var addrInputMap={'ship':'ship-street','b-contact':'b-contact-street','sos-repl':'sos-repl-address'};
  var cityInputMap={'ship':'ship-city','b-contact':'b-contact-city','sos-repl':'sos-repl-city'};
  var zipInputMap={'ship':'ship-zip','b-contact':'b-contact-zip','sos-repl':'sos-repl-zip'};
  var inp=document.getElementById(addrInputMap[type]||'')||document.getElementById(type+'-addr-input')||document.getElementById(type+'-address');
  if(inp){inp.value=addr;}
  // Store coordinates for distance calc
  if(inp && lat && lng){inp.dataset.lat=lat;inp.dataset.lng=lng;}
  // Fill city field — try mapped IDs first, then type-city
  var cityInp=document.getElementById(cityInputMap[type]||'')||document.getElementById(type+'-city');
  if(cityInp && city){cityInp.value=city;}
  // Auto-fill ZIP from structured data or address regex
  var zipMatch=addr.match(/(\d{3}\s?\d{2})/);
  if(zipMatch){
    var zipInp=document.getElementById(zipInputMap[type]||'')||document.getElementById(type+'-zip');
    if(zipInp)zipInp.value=zipMatch[1];
  }
  var sugEl=document.getElementById(type+'-addr-suggestions');
  if(sugEl)sugEl.style.display='none';
  if(type==='pickup'||type==='return'){calcDelivery(type);}
  if(type==='edit-pickup'&&typeof _sosCalcPickupDelivery==='function'){_sosCalcPickupDelivery();}
  if(type==='edit-return'&&typeof calcEditDelivery==='function'){calcEditDelivery();}
  if(type==='sos-repl'&&typeof sosReplCalcDelivery==='function'){sosReplCalcDelivery();}
}
