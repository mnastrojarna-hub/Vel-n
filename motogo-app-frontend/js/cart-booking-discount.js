// ===== CART-BOOKING-DISCOUNT.JS – Booking promo/voucher code validation =====
// Depends on globals: _appliedBookingCodes, _appliedPromoId, discountAmt,
// appliedCode, bookingMoto, bOd, bDo, bookingDays

async function applyDiscount(){
  var code=(document.getElementById('discount-input')||{value:''}).value.trim().toUpperCase();
  var msg=document.getElementById('discount-msg');
  var inp=document.getElementById('discount-input');
  if(!code){if(msg)msg.innerHTML='<span style="color:var(--red)">'+_t('cart').enterCode+'</span>';return;}

  for(var di=0;di<_appliedBookingCodes.length;di++){
    if(_appliedBookingCodes[di].code===code){
      if(msg)msg.innerHTML='<span style="color:var(--red)">Tento kód je již uplatněn</span>';return;
    }
  }

  if(window.supabase){
    try {
      var baseForDiscount=0;
      if(typeof calcTotalPrice==='function'&&bookingMoto&&bOd&&bDo){
        baseForDiscount=calcTotalPrice(bookingMoto,new Date(bOd.y,bOd.m,bOd.d),new Date(bDo.y,bDo.m,bDo.d));
      } else { baseForDiscount=2600*(bookingDays||1); }
      // Sleva se aplikuje na celou cenu (pronájem + příslušenství + přistavení)
      baseForDiscount += (typeof extraTotal!=='undefined'?extraTotal:0) + (typeof deliveryFee!=='undefined'?deliveryFee:0);

      var r = await window.supabase.rpc('validate_promo_code', { p_code: code });
      if(r.data && r.data.valid){
        var promoData = r.data;
        var disc=promoData.type==='percent'?Math.round(baseForDiscount*promoData.value/100):promoData.value;
        _appliedBookingCodes.push({code:code,type:'promo',id:promoData.id,discountAmt:disc});
        _appliedPromoId = promoData.id;appliedCode = code;
        discountAmt=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
        var label=promoData.type==='percent'?promoData.value+'%':promoData.value+' Kč';
        if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 '+_t('cart').discount+' '+label+' '+_t('cart').applied+'</span>';
        showT('\ud83c\udff7\ufe0f',_t('cart').discount+' '+label,_t('cart').youSave+' '+disc+' K\u010d');
        if(inp)inp.value='';_renderBookingAppliedCodes();recalcTotal();
      } else {
        var vr = await window.supabase.rpc('validate_voucher_code', { p_code: code });
        if(vr.data && vr.data.valid){
          var vData = vr.data;
          _appliedBookingCodes.push({code:code,type:'voucher',id:vData.id,discountAmt:vData.value});
          _appliedPromoId = vData.id;appliedCode = code;
          discountAmt=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
          if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 '+(_t('cart').voucher||'Poukaz')+' '+vData.value+' K\u010d '+_t('cart').applied+'</span>';
          showT('\ud83c\udf81',(_t('cart').voucher||'Poukaz')+' '+vData.value+' K\u010d','');
          if(inp)inp.value='';_renderBookingAppliedCodes();recalcTotal();
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
    base2 += (typeof extraTotal!=='undefined'?extraTotal:0) + (typeof deliveryFee!=='undefined'?deliveryFee:0);
    var disc2=Math.round(base2*pct/100);
    _appliedBookingCodes.push({code:code,type:'promo',id:null,discountAmt:disc2});
    discountAmt=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
    appliedCode = code;
    if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 '+_t('cart').discount+' '+pct+'% '+_t('cart').applied+'</span>';
    if(inp)inp.value='';_renderBookingAppliedCodes();recalcTotal();
    showT('\ud83c\udff7\ufe0f',_t('cart').discount+' '+pct+'%',_t('cart').youSave+' '+disc2+' K\u010d');
  } else {
    if(msg)msg.innerHTML='<span style="color:var(--red)">\u2717 '+_t('cart').codeNotFound+'</span>';
    if(inp)inp.style.borderColor='var(--red)';
  }
}
