// ===== CART-SHOP-DISCOUNT.JS – Shop promo + voucher code validation =====
// Depends on globals: shopDiscountAmt, shopAppliedCodes, cart, shipMode (cart-checkout.js)

async function applyShopDiscount(){
  var inp=document.getElementById('shop-discount-input');
  var msg=document.getElementById('shop-discount-msg');
  if(!inp)return;
  var code=inp.value.trim().toUpperCase();
  if(!code){if(msg)msg.innerHTML='<span style="color:var(--red)">Zadejte kód</span>';return;}

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
      inp.value='';updateCheckoutTotal();_renderShopAppliedCodes();return;
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
      inp.value='';updateCheckoutTotal();_renderShopAppliedCodes();return;
    }
  }

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
    return '<div style="display:flex;align-items:center;gap:6px;padding:6px 10px;background:var(--gp);border:1px solid var(--green);border-radius:8px;margin-bottom:4px;font-size:12px;font-weight:700;color:var(--gd);">'+
      '<span>'+c.code+' (-'+c.discountAmt.toLocaleString('cs-CZ')+' Kč)</span>'+
      '<button onclick="removeShopDiscount(\''+c.code+'\')" style="background:#fee2e2;color:#b91c1c;border:none;border-radius:6px;width:22px;height:22px;font-size:12px;font-weight:800;cursor:pointer;margin-left:auto;padding:0;">✕</button>'+
      '</div>';
  }).join('');
}

function initCheckout(){
  shopDiscountAmt=0;shopAppliedCodes=[];
  renderCart();selectShipping(shipMode);autofillCheckout();updateCheckoutTotal();
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
