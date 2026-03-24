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
      if(msg)msg.innerHTML='<span style="color:var(--red)">Tento k\u00f3d je ji\u017e uplatn\u011bn</span>';return;
    }
  }

  if(window.supabase){
    try {
      var baseForDiscount=0;
      if(typeof calcTotalPrice==='function'&&bookingMoto&&bOd&&bDo){
        baseForDiscount=calcTotalPrice(bookingMoto,new Date(bOd.y,bOd.m,bOd.d),new Date(bDo.y,bDo.m,bDo.d));
      } else { baseForDiscount=2600*(bookingDays||1); }
      // Sleva se aplikuje na celou cenu (pron\u00e1jem + p\u0159\u00edslu\u0161enstv\u00ed + p\u0159istaven\u00ed)
      baseForDiscount += (typeof extraTotal!=='undefined'?extraTotal:0) + (typeof deliveryFee!=='undefined'?deliveryFee:0);

      var r = await window.supabase.rpc('validate_promo_code', { p_code: code });
      if(r.data && r.data.valid){
        var promoData = r.data;
        // Prevent combining two percentage codes
        if(promoData.type==='percent'){
          var hasPercent=_appliedBookingCodes.some(function(c){return c.discountType==='percent';});
          if(hasPercent){if(msg)msg.innerHTML='<span style="color:var(--red)">Nelze kombinovat dva procentu\u00e1ln\u00ed k\u00f3dy</span>';return;}
        }
        var disc=promoData.type==='percent'?Math.round(baseForDiscount*promoData.value/100):promoData.value;
        var currentOtherDisc=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
        disc=Math.min(disc,Math.max(0,baseForDiscount-currentOtherDisc));
        _appliedBookingCodes.push({code:code,type:'promo',id:promoData.id,discountAmt:disc,discountType:promoData.type,discountValue:promoData.value});
        _appliedPromoId = promoData.id;appliedCode = code;
        discountAmt=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
        var label=promoData.type==='percent'?promoData.value+'%':promoData.value+' K\u010d';
        if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 '+_t('cart').discount+' '+label+' '+_t('cart').applied+'</span>';
        showT('\ud83c\udff7\ufe0f',_t('cart').discount+' '+label,_t('cart').youSave+' '+disc+' K\u010d');
        if(inp)inp.value='';_renderBookingAppliedCodes();recalcTotal();
      } else {
        var vr = await window.supabase.rpc('validate_voucher_code', { p_code: code });
        if(vr.data && vr.data.valid){
          var vData = vr.data;
          var currentDiscV=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
          var vDisc=Math.min(vData.value,Math.max(0,baseForDiscount-currentDiscV));
          if(vDisc<=0){if(msg)msg.innerHTML='<span style="color:var(--red)">Sleva ji\u017e pokr\u00fdv\u00e1 celou cenu</span>';return;}
          _appliedBookingCodes.push({code:code,type:'voucher',id:vData.id,discountAmt:vDisc,discountType:'fixed',discountValue:vData.value});
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
    var curDisc2=_appliedBookingCodes.reduce(function(s,c){return s+c.discountAmt;},0);
    disc2=Math.min(disc2,Math.max(0,base2-curDisc2));
    _appliedBookingCodes.push({code:code,type:'promo',id:null,discountAmt:disc2,discountType:'percent',discountValue:pct});
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
