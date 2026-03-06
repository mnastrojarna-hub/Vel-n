// ===== CART-CHECKOUT.JS – Checkout, booking price & address autocomplete =====
// Split from original cart-engine.js. Depends on global state variables
// (cart, shipMode, pickupDelivFee, returnDelivFee, etc.) defined in cart-engine.js.

// ===== CHECKOUT FUNCTIONS =====

function selectShipping(mode){
  shipMode=mode;
  document.getElementById('ship-post').style.borderColor=mode==='post'?'var(--green)':'var(--g200)';
  document.getElementById('ship-post').style.background=mode==='post'?'var(--gp)':'#fff';
  document.getElementById('ship-pickup').style.borderColor=mode==='pickup'?'var(--green)':'var(--g200)';
  document.getElementById('ship-pickup').style.background=mode==='pickup'?'var(--gp)':'#fff';
  // NEMĚNIT display ship-address přímo – nechat collapse logiku na toggleShipDetails
  // Jen zobrazíme wrapper pokud je post
  var shipWrap = document.getElementById('ship-section-wrap');
  if(shipWrap) shipWrap.style.display = mode==='post' ? 'block' : 'none';
  // Update checkout total with shipping
  var shipCost=mode==='post'?99:0;
  var cartTotal=typeof cart!=='undefined'?cart.reduce(function(s,c){return s+c.price*c.qty;},0):0;
  var el=document.getElementById('checkout-total');
  if(el)el.textContent=(cartTotal+shipCost).toLocaleString('cs-CZ')+' Kč';
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
  var total=cart.reduce(function(s,c){return s+c.price*c.qty;},0);
  if(total===0){showT('\u26a0\ufe0f',_t('cart').cart,_t('cart').cartEmpty);return;}
  if(shipMode==='post'){
    var nm=(document.getElementById('ship-name')||{}).value;
    if(!nm){showT('\u26a0\ufe0f',_t('cart').address,_t('cart').fillAddress);return;}
  }
  showT('\ud83d\udcb3',_t('cart').processing,_t('cart').pleaseWait);

  // Vytvo\u0159 objedn\u00e1vku v Supabase
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
      var r = await window.supabase.rpc('create_shop_order', {
        p_items: items,
        p_shipping_method: shipMode,
        p_shipping_address: shipAddr,
        p_payment_method: 'card',
        p_promo_code: appliedCode || null
      });
      if(r.data && r.data.error){
        console.warn('[SHOP] create_shop_order error:', r.data.error);
      } else if(r.data && r.data.success){
        console.log('[SHOP] Order created:', r.data.order_id);
        // Mark as paid (shop checkout = immediate payment)
        if(r.data.order_id){
          await window.supabase.from('shop_orders').update({
            payment_status: 'paid',
            order_number: 'OBJ-' + new Date().getFullYear() + '-' + r.data.order_id.substr(-6).toUpperCase()
          }).eq('id', r.data.order_id);
        }
      }
      if(r.error) console.warn('[SHOP] RPC error:', r.error.message);
    } catch(e){ console.error('[SHOP] finalizeCheckout DB error:', e); }
  }

  cart=[];
  cartFabDismissed=false;
  appliedCode=null;
  _appliedPromoId=null;
  updateCartFab();
  showT('\u2705',_t('cart').orderAccepted,_t('cart').confirmEmail);
  var checkoutEl = document.getElementById('s-checkout');
  if(checkoutEl){
    checkoutEl.innerHTML = '<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:60vh;padding:40px;text-align:center;"><div style="font-size:64px;margin-bottom:16px;">\u2705</div><div style="font-size:22px;font-weight:900;color:var(--black);margin-bottom:8px;">'+_t('cart').thankYou+'</div><div style="font-size:14px;color:var(--g400);line-height:1.6;">'+_t('cart').orderReceived+'<br>'+_t('cart').emailConfirm+'</div></div>';
  }
  setTimeout(function(){ goTo('s-merch'); }, 5000);
}

function initCheckout(){
  renderCart();
  selectShipping(shipMode);
  autofillCheckout();
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

var _extraTimer=null;
function toggleExtra(label,price){
  const chk=label.querySelector('input[type=checkbox]');
  if(_extraTimer) clearTimeout(_extraTimer);
  _extraTimer=setTimeout(function(){
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
  },80);
  if(chk){
    label.style.borderColor=chk.checked?'var(--green)':'var(--g200)';
  }
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
      var txt='~'+km+' km od Mezné → 1 000 Kč + '+km+'×20 Kč = '+fee.toLocaleString('cs-CZ')+' Kč';
      if(result.duration) txt+=' (~'+result.duration+' min)';
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
  if(kmTxt)kmTxt.textContent='~'+km+' km od Mezné → 1 000 Kč + '+km+'×20 Kč = '+fee.toLocaleString('cs-CZ')+' Kč (odhad)';
  recalcTotal();
}

var _appliedPromoId = null;
var _appliedCodes = []; // Array of applied codes for stacking

async function applyDiscount(){
  var inp=document.getElementById('discount-input');
  var code=(inp||{value:''}).value.trim().toUpperCase();
  var msg=document.getElementById('discount-msg');
  if(!code){if(msg)msg.innerHTML='<span style="color:var(--red)">'+_t('cart').enterCode+'</span>';return;}

  // Check if code already applied
  if(_appliedCodes.indexOf(code) !== -1){
    if(msg)msg.innerHTML='<span style="color:var(--red)">Tento kód je již použit</span>';
    return;
  }

  // Supabase DB validace — single source of truth
  if(window.supabase){
    try {
      var baseForDiscount=0;
      if(typeof calcTotalPrice==='function'&&bookingMoto&&bOd&&bDo){
        baseForDiscount=calcTotalPrice(bookingMoto,new Date(bOd.y,bOd.m,bOd.d),new Date(bDo.y,bDo.m,bDo.d));
      } else { baseForDiscount=2600*(bookingDays||1); }

      // 1) Try promo_codes table
      var r = await window.supabase.rpc('validate_promo_code', { p_code: code });
      if(r.data && r.data.valid){
        var promoData = r.data;
        _appliedPromoId = promoData.id;
        var thisDiscount = 0;
        if(promoData.type === 'percent'){
          thisDiscount = Math.round(baseForDiscount * promoData.value / 100);
        } else {
          thisDiscount = promoData.value;
        }
        _appliedCodes.push(code);
        appliedCode = _appliedCodes.join(',');
        discountAmt += thisDiscount;
        _showAppliedCodes(msg);
        if(inp){inp.style.borderColor='var(--green)';inp.value='';}
        _showAddCodeBtn();
        recalcTotal();
        showT('\ud83c\udff7\ufe0f',_t('cart').discount,_t('cart').youSave+' '+discountAmt+' K\u010d');
        return;
      }

      // 2) Try vouchers table (gift voucher codes)
      var vr = await window.supabase.from('vouchers')
        .select('id, code, amount, currency, status, valid_from, valid_until')
        .eq('code', code)
        .eq('status', 'active')
        .limit(1)
        .single();
      if(vr.data && vr.data.id){
        var voucher = vr.data;
        // Check validity dates
        var today = new Date().toISOString().split('T')[0];
        if(voucher.valid_from && voucher.valid_from > today){
          if(msg)msg.innerHTML='<span style="color:var(--red)">\u2717 Poukaz ještě není platný</span>';
          return;
        }
        if(voucher.valid_until && voucher.valid_until < today){
          if(msg)msg.innerHTML='<span style="color:var(--red)">\u2717 Poukaz vypršel</span>';
          return;
        }
        var voucherAmt = Number(voucher.amount) || 0;
        _appliedCodes.push(code);
        appliedCode = _appliedCodes.join(',');
        discountAmt += voucherAmt;
        _showAppliedCodes(msg);
        if(inp){inp.style.borderColor='var(--green)';inp.value='';}
        _showAddCodeBtn();
        recalcTotal();
        showT('\ud83c\udf81',_t('cart').discount+' (poukaz)',_t('cart').youSave+' '+discountAmt+' K\u010d');
        return;
      }

      // Neither promo nor voucher found
      var errMsg = (r.data && r.data.error) ? r.data.error : _t('cart').codeNotFound;
      if(msg)msg.innerHTML='<span style="color:var(--red)">\u2717 '+errMsg+'</span>';
      if(inp)inp.style.borderColor='var(--red)';
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
    var thisDisc=Math.round(base2*pct/100);
    _appliedCodes.push(code);
    appliedCode = _appliedCodes.join(',');
    discountAmt+=thisDisc;
    _showAppliedCodes(msg);
    if(inp){inp.style.borderColor='var(--green)';inp.value='';}
    _showAddCodeBtn();
    recalcTotal();
    showT('\ud83c\udff7\ufe0f',_t('cart').discount+' '+pct+'%',_t('cart').youSave+' '+discountAmt+' K\u010d');
  } else {
    if(msg)msg.innerHTML='<span style="color:var(--red)">\u2717 '+_t('cart').codeNotFound+'</span>';
    if(inp)inp.style.borderColor='var(--red)';
  }
}

function _showAppliedCodes(msg){
  if(!msg) return;
  var html = _appliedCodes.map(function(c){
    return '<span style="display:inline-block;background:var(--gp);color:var(--gd);border-radius:20px;padding:3px 10px;font-size:11px;font-weight:700;margin:2px 4px 2px 0;">\u2713 '+c+'</span>';
  }).join('');
  html += '<span style="color:var(--gd);font-size:11px;font-weight:600;"> \u2014 '+_t('cart').youSave+' '+discountAmt+' K\u010d</span>';
  msg.innerHTML = html;
}

function _showAddCodeBtn(){
  var wrap = document.getElementById('add-code-btn-wrap');
  if(wrap) wrap.style.display = 'block';
}

function showAddCodeInput(){
  var inp=document.getElementById('discount-input');
  if(inp){inp.removeAttribute('readonly');inp.value='';inp.style.borderColor='var(--g200)';inp.focus();}
  var wrap = document.getElementById('add-code-btn-wrap');
  if(wrap) wrap.style.display = 'none';
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

function showAddrSuggestions(inp,type){
  var sugEl=document.getElementById(type+'-addr-suggestions');
  if(!sugEl)return;
  var val=(inp.value||'').trim();
  if(val.length<2){sugEl.style.display='none';return;}

  // Use Nominatim API if available, fallback to local ADDR_DB
  if(typeof AddressAPI !== 'undefined'){
    AddressAPI.suggestDebounced(val, function(results){
      if(!results || results.length===0){sugEl.style.display='none';return;}
      _renderAddrSuggestions(sugEl, results, type);
      sugEl.style.display='block';
    });
    return;
  }

  // Fallback to local ADDR_DB
  var q=val.toLowerCase();
  var matches=ADDR_DB.filter(function(a){return a.addr.toLowerCase().indexOf(q)!==-1||a.city.toLowerCase().indexOf(q)!==-1;}).slice(0,5);
  if(matches.length===0){sugEl.style.display='none';return;}
  var results=matches.map(function(a){
    var zipMatch=a.addr.match(/(\d{3})\s?(\d{2})/);
    return {label:a.addr,lat:null,lng:null,city:a.city,zip:zipMatch?zipMatch[1]+' '+zipMatch[2]:''};
  });
  _renderAddrSuggestions(sugEl, results, type);
  sugEl.style.display='block';
}

// Render suggestions with touch-safe events (fixes mobile tap issues)
function _renderAddrSuggestions(sugEl, results, type){
  sugEl.innerHTML='';
  results.forEach(function(r){
    var div=document.createElement('div');
    div.className='addr-sug-item';
    div.textContent='\uD83D\uDCCD '+r.label;
    function handler(e){
      e.preventDefault();
      e.stopPropagation();
      selectAddr(type, r.label, r.city||'', r.lat||null, r.lng||null);
    }
    div.addEventListener('mousedown', handler);
    div.addEventListener('touchstart', handler, {passive:false});
    sugEl.appendChild(div);
  });
}

function showCitySuggestions(inp){
  var sugEl=document.getElementById('edit-return-city-suggestions');
  if(!sugEl)return;
  var val=(inp.value||'').trim();
  if(val.length<2){sugEl.style.display='none';return;}

  // Use API if available
  if(typeof AddressAPI !== 'undefined'){
    AddressAPI.suggestDebounced(val, function(results){
      if(!results || results.length===0){sugEl.style.display='none';return;}
      var cities=[];var seen={};
      results.forEach(function(r){
        if(r.city && !seen[r.city]){seen[r.city]=1;cities.push(r.city);}
      });
      if(cities.length===0){sugEl.style.display='none';return;}
      sugEl.innerHTML=cities.map(function(c){return '<div class="addr-sug-item" onclick="selectCity(\''+c.replace(/'/g,"\\'")+'\')">📍 '+c+'</div>';}).join('');
      sugEl.style.display='block';
    });
    return;
  }

  // Fallback to local
  var q=val.toLowerCase();
  var allCities=[...new Set(ADDR_DB.map(function(a){return a.city;}))];
  var matches=allCities.filter(function(c){return c.toLowerCase().indexOf(q)!==-1;}).slice(0,5);
  if(matches.length===0){sugEl.style.display='none';return;}
  sugEl.innerHTML=matches.map(function(c){return '<div class="addr-sug-item" onclick="selectCity(\''+c+'\')">📍 '+c+'</div>';}).join('');
  sugEl.style.display='block';
}
function selectCity(city){
  var inp=document.getElementById('edit-return-city');
  if(inp)inp.value=city;
  var sugEl=document.getElementById('edit-return-city-suggestions');
  if(sugEl)sugEl.style.display='none';
  if(typeof updateEditPriceSummary==='function')updateEditPriceSummary();
}
function selectAddr(type,addr,city,lat,lng){
  // Map special types to their input IDs
  var addrInputMap={'ship':'ship-street','b-contact':'b-contact-street'};
  var cityInputMap={'ship':'ship-city','b-contact':'b-contact-city'};
  var zipInputMap={'ship':'ship-zip','b-contact':'b-contact-zip'};
  var inp=document.getElementById(addrInputMap[type]||'')||document.getElementById(type+'-addr-input')||document.getElementById(type+'-address');
  if(inp){inp.value=addr;}
  // Store coordinates for distance calc
  if(inp && lat && lng){inp.dataset.lat=lat;inp.dataset.lng=lng;}
  var cityInp=document.getElementById(cityInputMap[type]||'')||document.getElementById(type+'-city');
  if(cityInp){cityInp.value=city;}
  // Auto-fill ZIP from address
  var zipMatch=addr.match(/(\d{3}\s?\d{2})/);
  if(zipMatch){
    var zipInp=document.getElementById(zipInputMap[type]||'');
    if(zipInp)zipInp.value=zipMatch[1];
  }
  var sugEl=document.getElementById(type+'-addr-suggestions');
  if(sugEl)sugEl.style.display='none';
  if(type==='pickup'||type==='return'){calcDelivery(type);}
  if(type==='edit-return'&&typeof calcEditDelivery==='function'){calcEditDelivery();}
}
