// ===== CART-BOOKING-PRICE.JS – Booking price calculations + discount =====
// Depends on globals: bookingDays, bookingMoto, bOd, bDo, extraTotal,
// deliveryFee, discountAmt, appliedCode, pickupDelivFee, returnDelivFee

function recalcTotal(){
  var base=0;
  if(typeof calcTotalPrice==='function'&&bookingMoto&&bOd&&bDo){
    base=calcTotalPrice(bookingMoto,new Date(bOd.y,bOd.m,bOd.d),new Date(bDo.y,bDo.m,bDo.d));
  } else { base=2600*bookingDays; }
  var total=Math.max(0,base+extraTotal+deliveryFee-discountAmt);
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
  extraTotal=0;
  document.querySelectorAll('#s-booking label[id^="extra-"]').forEach(function(lbl){
    var cb=lbl.querySelector('input[type=checkbox]');
    if(cb&&cb.checked){
      var priceAttr=lbl.getAttribute('data-price');
      if(priceAttr) extraTotal+=parseInt(priceAttr);
      lbl.style.borderColor='var(--green)';
    } else if(cb) { lbl.style.borderColor='var(--g200)'; }
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

var _calcDelivTimer = null;
function calcDelivery(type){
  clearTimeout(_calcDelivTimer);
  _calcDelivTimer = setTimeout(function(){ _doCalcDelivery(type); }, 500);
}
function _doCalcDelivery(type){
  var inp=document.getElementById(type+'-addr-input');
  var calcEl=document.getElementById(type+'-price-calc');
  var kmTxt=document.getElementById(type+'-km-txt');
  if(!inp||!inp.value.trim()){if(calcEl)calcEl.style.display='none';return;}
  var addr=inp.value.trim();
  if(addr.length < 3 && !(inp.dataset.lat && inp.dataset.lng)){
    if(calcEl)calcEl.style.display='none';return;
  }
  var cityEl=document.getElementById(type+'-city');
  var zipEl=document.getElementById(type+'-zip');
  var city=(cityEl && cityEl.value) ? cityEl.value.trim() : '';
  var zip=(zipEl && zipEl.value) ? zipEl.value.trim() : '';
  var fullAddr = addr;
  if(city) fullAddr += ', ' + city;
  if(zip) fullAddr += ', ' + zip;

  if(typeof AddressAPI !== 'undefined'){
    var coords = (inp.dataset.lat && inp.dataset.lng)
      ? {lat: parseFloat(inp.dataset.lat), lng: parseFloat(inp.dataset.lng)}
      : fullAddr;
    if(kmTxt) kmTxt.textContent='Vypočítávám vzdálenost...';
    if(calcEl) calcEl.style.display='block';
    AddressAPI.calcDistance(coords, function(result){
      if(!result){ _calcDeliveryFallback(type, fullAddr, calcEl, kmTxt); return; }
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
  _calcDeliveryFallback(type, fullAddr, calcEl, kmTxt);
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
var _appliedBookingCodes = []; // [{code, type:'promo'|'voucher', id, discountAmt, discountType, discountValue}]

function removeDiscount(){
  discountAmt=0;appliedCode=null;_appliedPromoId=null;_appliedBookingCodes=[];
  var inp=document.getElementById('discount-input');
  if(inp){inp.value='';inp.style.borderColor='var(--g200)';}
  var msg=document.getElementById('discount-msg');if(msg)msg.innerHTML='';
  var wrap=document.getElementById('booking-applied-codes');if(wrap)wrap.innerHTML='';
  recalcTotal();
}

function _renderBookingAppliedCodes(){
  var wrap=document.getElementById('booking-applied-codes');
  if(!wrap){
    var msg=document.getElementById('discount-msg');
    if(!msg||!msg.parentNode)return;
    wrap=document.createElement('div');wrap.id='booking-applied-codes';wrap.style.cssText='margin-top:6px;';
    msg.parentNode.appendChild(wrap);
  }
  if(_appliedBookingCodes.length===0){wrap.innerHTML='';return;}
  wrap.innerHTML=_appliedBookingCodes.map(function(c){
    var discLabel=c.discountType==='percent'?c.code+' (sleva '+c.discountValue+'%)':c.code+' (-'+c.discountAmt.toLocaleString('cs-CZ')+' K\u010d)';
    return '<div style="display:flex;align-items:center;gap:6px;padding:5px 10px;background:var(--gp);border:1px solid var(--green);border-radius:8px;margin-bottom:4px;font-size:11px;font-weight:700;color:var(--gd);">'+
      '<span>'+discLabel+'</span>'+
      '<button onclick="removeOneDiscount(\''+c.code+'\')" style="background:#fee2e2;color:#b91c1c;border:none;border-radius:6px;width:20px;height:20px;font-size:11px;font-weight:800;cursor:pointer;margin-left:auto;padding:0;">\u2715</button>'+
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

function updateBookingPrice(){
  if(!bOd||!bDo)return;
  var days=Math.max(1,Math.round((new Date(bDo.y,bDo.m,bDo.d)-new Date(bOd.y,bOd.m,bOd.d))/86400000)+1);
  bookingDays=days;
  if(typeof calcTotalPrice==='function'&&bookingMoto){
    var base=calcTotalPrice(bookingMoto,new Date(bOd.y,bOd.m,bOd.d),new Date(bDo.y,bDo.m,bDo.d));
    var avg=Math.round(base/days);
    var el=document.getElementById('pr-base');
    if(el)el.textContent=avg.toLocaleString('cs-CZ')+' Kč/den × '+days+' '+(days===1?'den':'dní');
    var calPrice=document.getElementById('b-cal-price');
    var calPriceVal=document.getElementById('b-cal-price-val');
    if(calPrice&&calPriceVal){
      var total=Math.max(0,base+extraTotal+deliveryFee-discountAmt);
      calPriceVal.textContent=total.toLocaleString('cs-CZ')+' Kč';
      calPrice.style.display='block';
    }
  }
  recalcTotal();
}
