// ===== CART-SHOP-DISCOUNT.JS – Shop promo + voucher code validation =====
// Depends on globals: shopDiscountAmt, shopAppliedCodes, cart, shipMode (cart-checkout.js)

async function applyShopDiscount(){
  var inp=document.getElementById('shop-discount-input');
  var msg=document.getElementById('shop-discount-msg');
  if(!inp)return;
  var code=inp.value.trim().toUpperCase();
  if(!code){if(msg)msg.innerHTML='<span style="color:var(--red)">Zadejte k\u00f3d</span>';return;}

  for(var di=0;di<shopAppliedCodes.length;di++){
    if(shopAppliedCodes[di].code===code){
      if(msg)msg.innerHTML='<span style="color:var(--red)">Tento k\u00f3d je ji\u017e uplatn\u011bn</span>';return;
    }
  }

  if(!window.supabase){if(msg)msg.innerHTML='<span style="color:var(--red)">Offline</span>';return;}

  var cartTotal=cart.reduce(function(s,c){return s+c.price*c.qty;},0);
  var digitalOnly=typeof _isCartOnlyDigitalVouchers==='function'&&_isCartOnlyDigitalVouchers();
  var shipCost=digitalOnly?0:(shipMode==='post'?99:0);
  var orderTotal=cartTotal+shipCost;

  // 1. Try promo code
  var hasPromo=shopAppliedCodes.some(function(c){return c.type==='promo';});
  if(!hasPromo){
    var pr=await window.supabase.rpc('validate_promo_code',{p_code:code});
    if(pr.data&&pr.data.valid){
      var pd=pr.data;
      // Prevent combining two percentage codes
      if(pd.type==='percent'){
        var hasPercent=shopAppliedCodes.some(function(c){return c.discountType==='percent';});
        if(hasPercent){if(msg)msg.innerHTML='<span style="color:var(--red)">Nelze kombinovat dva procentu\u00e1ln\u00ed k\u00f3dy</span>';return;}
      }
      // Percentage discount applies to full order total (cart + shipping)
      var disc=pd.type==='percent'?Math.round(orderTotal*pd.value/100):pd.value;
      disc=Math.min(disc,Math.max(0,orderTotal-shopDiscountAmt));
      shopAppliedCodes.push({code:code,type:'promo',id:pd.id,value:pd.value,discountAmt:disc,discountType:pd.type,discountValue:pd.value});
      shopDiscountAmt+=disc;
      var label=pd.type==='percent'?'Sleva '+pd.value+'%':'Sleva '+pd.value+' K\u010d';
      if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 '+label+' uplatn\u011bna</span>';
      inp.value='';updateCheckoutTotal();_renderShopAppliedCodes();return;
    }
  }

  // 2. Try voucher code
  var hasVoucher=shopAppliedCodes.some(function(c){return c.type==='voucher';});
  if(!hasVoucher){
    var vr=await window.supabase.rpc('validate_voucher_code',{p_code:code});
    if(vr.data&&vr.data.valid){
      var vd=vr.data;
      var vDisc=Math.min(vd.value,Math.max(0,orderTotal-shopDiscountAmt));
      shopAppliedCodes.push({code:code,type:'voucher',id:vd.id,value:vd.value,discountAmt:vDisc,discountType:'fixed',discountValue:vd.value});
      shopDiscountAmt+=vDisc;
      if(msg)msg.innerHTML='<span style="color:var(--gd)">\u2713 Poukaz '+vd.value+' K\u010d uplatn\u011bn (sleva '+vDisc+' K\u010d)</span>';
      inp.value='';updateCheckoutTotal();_renderShopAppliedCodes();return;
    }
  }

  if(hasPromo&&hasVoucher){
    if(msg)msg.innerHTML='<span style="color:var(--red)">Lze uplatnit max 1 promo k\u00f3d + 1 poukaz</span>';
  } else {
    if(msg)msg.innerHTML='<span style="color:var(--red)">\u2717 K\u00f3d nenalezen</span>';
  }
}

function removeShopDiscount(code){
  shopAppliedCodes=shopAppliedCodes.filter(function(c){return c.code!==code;});
  shopDiscountAmt=shopAppliedCodes.reduce(function(s,c){return s+c.discountAmt;},0);
  var msg=document.getElementById('shop-discount-msg');
  if(msg)msg.innerHTML='<span style="color:var(--gd)">K\u00f3d '+code+' odebr\u00e1n</span>';
  var inp=document.getElementById('shop-discount-input');
  if(inp)inp.value='';
  updateCheckoutTotal();_renderShopAppliedCodes();
}

function _renderShopAppliedCodes(){
  var wrap=document.getElementById('shop-applied-codes');
  if(!wrap){
    var msg=document.getElementById('shop-discount-msg');
    if(!msg||!msg.parentNode)return;
    wrap=document.createElement('div');wrap.id='shop-applied-codes';wrap.style.cssText='margin-top:6px;';
    msg.parentNode.insertBefore(wrap,msg.nextSibling);
  }
  if(shopAppliedCodes.length===0){wrap.innerHTML='';return;}
  wrap.innerHTML=shopAppliedCodes.map(function(c){
    var discLabel=c.discountType==='percent'?c.code+' (sleva '+c.discountValue+'%)':c.code+' (-'+c.discountAmt.toLocaleString('cs-CZ')+' K\u010d)';
    return '<div style="display:flex;align-items:center;gap:6px;padding:6px 10px;background:var(--gp);border:1px solid var(--green);border-radius:8px;margin-bottom:4px;font-size:12px;font-weight:700;color:var(--gd);">'+
      '<span>'+discLabel+'</span>'+
      '<button onclick="removeShopDiscount(\''+c.code+'\')" style="background:#fee2e2;color:#b91c1c;border:none;border-radius:6px;width:22px;height:22px;font-size:12px;font-weight:800;cursor:pointer;margin-left:auto;padding:0;">\u2715</button>'+
      '</div>';
  }).join('');
}

function initCheckout(){
  shopDiscountAmt=0;shopAppliedCodes=[];
  var digitalOnly=typeof _isCartOnlyDigitalVouchers==='function'&&_isCartOnlyDigitalVouchers();
  if(digitalOnly) shipMode='digital';
  renderCart();selectShipping(digitalOnly?'digital':shipMode);autofillCheckout();updateCheckoutTotal();
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
