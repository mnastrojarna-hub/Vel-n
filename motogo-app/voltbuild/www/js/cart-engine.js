// ===== CART-ENGINE.JS – Cart, merch detail & voucher functions =====
// Split from original cart-engine.js. Checkout, booking price & address
// autocomplete functions live in cart-checkout.js (loaded dynamically below).

// ===== STATE VARIABLES (shared with cart-checkout.js) =====
var cart = [];
var voucherAmt = 0;
var voucherType = 'digital';
var shipMode = 'post';
var appliedCode = null;
var appliedDiscount = 0;
var pickupDelivFee = 0;
var returnDelivFee = 0;

// ===== CART FUNCTIONS =====

function addToCart(id, name, price) {
  const existing = cart.find(c => c.id === id);
  if(existing) { existing.qty++; }
  else { cart.push({id, name, price, qty:1}); }
  cartFabDismissed=false;
  updateCartFab();
  showT('✓',_t('cart').added,''+name);
}

function removeFromCart(id) {
  cart = cart.filter(c=>c.id!==id);
  updateCartFab();
  renderCart();
}

function changeQty(id, delta) {
  var item = cart.find(function(c){ return c.id === id; });
  if(!item) return;
  item.qty += delta;
  if(item.qty <= 0) { removeFromCart(id); return; }
  updateCartFab();
  renderCart();
}

function renderCart() {
  const list = document.getElementById('cart-items-list');
  const totalEl = document.getElementById('cart-total-final');
  if(!list) return;
  const total = cart.reduce((s,c)=>s+c.price*c.qty,0);
  if(totalEl) totalEl.textContent = total.toLocaleString('cs-CZ') + ' Kč';
  if(cart.length === 0){
    list.innerHTML = '<div style="text-align:center;padding:40px 0;color:var(--g400);font-size:13px;font-weight:600;">'+_t('cart').cartEmpty+'<br><br><button onclick="goTo(\'s-merch\')" style="background:var(--green);color:#fff;border:none;border-radius:50px;padding:10px 24px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">'+_t('cart').backToShop+'</button></div>';
    return;
  }
  var _cmr=_t('merch')||{};
  list.innerHTML = cart.map(c => {
    var _cn=(_cmr[c.id]&&_cmr[c.id].name)||c.name;
    return '<div style="display:flex;align-items:center;gap:10px;background:#fff;border-radius:var(--rsm);padding:12px;margin-bottom:8px;box-shadow:var(--shadow);">'+
      '<div style="flex:1;min-width:0;"><div style="font-size:13px;font-weight:700;overflow:hidden;text-overflow:ellipsis;">'+_cn+'</div><div style="font-size:12px;color:var(--g400);">'+c.price.toLocaleString('cs-CZ')+' '+(_t('cart').perItem||'Kč/ks')+'</div></div>'+
      '<div style="display:flex;align-items:center;gap:6px;flex-shrink:0;">'+
        '<button onclick="changeQty(\''+c.id+'\',-1)" style="width:28px;height:28px;background:var(--g100);border:2px solid var(--g200);border-radius:8px;font-size:15px;font-weight:800;cursor:pointer;color:var(--black);display:flex;align-items:center;justify-content:center;font-family:var(--font);padding:0;">\u2212</button>'+
        '<span style="font-size:14px;font-weight:800;color:var(--black);min-width:20px;text-align:center;">'+c.qty+'</span>'+
        '<button onclick="changeQty(\''+c.id+'\',1)" style="width:28px;height:28px;background:var(--green);border:none;border-radius:8px;font-size:15px;font-weight:800;cursor:pointer;color:#fff;display:flex;align-items:center;justify-content:center;font-family:var(--font);padding:0;">+</button>'+
      '</div>'+
      '<div style="font-size:14px;font-weight:800;color:var(--green);min-width:50px;text-align:right;flex-shrink:0;">'+(c.price*c.qty).toLocaleString('cs-CZ')+' Kč</div>'+
      '<button onclick="removeFromCart(\''+c.id+'\')" style="background:#fee2e2;color:#b91c1c;border:none;border-radius:8px;width:28px;height:28px;font-size:14px;cursor:pointer;font-weight:800;flex-shrink:0;padding:0;">×</button>'+
    '</div>';
  }).join('');
}

function updateCartFab(){
  try {
    var total = cart.reduce(function(s,c){return s+c.price*c.qty;},0);
    var count = cart.reduce(function(s,c){return s+c.qty;},0);
    var fab = document.getElementById('cart-fab');
    var countEl = document.getElementById('cart-count');
    var totalEl = document.getElementById('cart-total-fab');
    var hideOn = ['s-login','s-register','s-docs','s-cart','s-checkout','s-booking','s-payment','s-success'];
    if(fab){
      var shouldShow = count > 0 && hideOn.indexOf(cur) === -1 && !cartFabDismissed;
      fab.style.display = shouldShow ? 'flex' : 'none';
    }
    if(countEl) countEl.textContent = count;
    if(totalEl) totalEl.textContent = total.toLocaleString('cs-CZ') + ' Kč';
  } catch(e){ console.error('updateCartFab error:', e); }
}

function clearCart() {
  cart = [];
  cartFabDismissed=false;
  updateCartFab();
  showT('🗑️',_t('cart').cartCleared,_t('cart').allRemoved);
}

// Dismiss the cart FAB bar (hide without clearing cart)
var cartFabDismissed=false;
function dismissCartFab(){
  try {
    cartFabDismissed = true;
    var fab = document.getElementById('cart-fab');
    if(fab) fab.style.display = 'none';
  } catch(e){ console.error('dismissCartFab error:', e); }
}

function checkoutMerch() {
  if(cart.length===0){showT('⚠️',_t('cart').cart,_t('cart').cartEmpty);return;}
  goTo('s-checkout');
}

// ===== MERCH DETAIL FUNCTIONS =====

function openMerchItem(id) {
  if(typeof MERCH_ITEMS==='undefined'||!MERCH_ITEMS[id]) return;
  currentMerchId = id;
  selectedMerchSize = null;
  goTo('s-merch-detail');
  var item = MERCH_ITEMS[id];
  var _mr=_t('merch')||{};var _mtr=_mr[id]||{};
  var titleEl = document.getElementById('md-title');
  if(titleEl) titleEl.textContent = _mtr.name||item.name;
  var nameEl = document.getElementById('md-name');
  if(nameEl) nameEl.textContent = _mtr.name||item.name;
  var priceEl = document.getElementById('md-price');
  if(priceEl) priceEl.textContent = item.price.toLocaleString('cs-CZ') + ' Kč';
  var descEl = document.getElementById('md-desc');
  if(descEl) descEl.textContent = _mtr.desc||item.desc;
  var colorEl = document.getElementById('md-color');
  if(colorEl) colorEl.textContent = _mtr.color||item.color;
  var matEl = document.getElementById('md-material');
  if(matEl) matEl.textContent = item.material;
  var imagesEl = document.getElementById('md-images');
  if(imagesEl) {
    imagesEl.innerHTML =
      '<img src="'+item.img+'" style="width:100%;min-width:280px;height:220px;object-fit:cover;border-radius:var(--r);box-shadow:var(--shadow);flex-shrink:0;">'+
      '<img src="'+item.img2+'" style="width:100%;min-width:280px;height:220px;object-fit:cover;border-radius:var(--r);box-shadow:var(--shadow);flex-shrink:0;">';
  }
  var sizeWrap = document.getElementById('md-size-wrap');
  if(sizeWrap) sizeWrap.style.display = item.needsSize ? 'block' : 'none';
  var sizeMsg = document.getElementById('md-size-msg');
  if(sizeMsg) sizeMsg.style.display = 'none';
  document.querySelectorAll('.md-size-btn').forEach(function(b){
    b.style.borderColor='var(--g200)'; b.style.background='#fff'; b.style.color='var(--black)';
  });
}

function selectMerchSize(size) {
  selectedMerchSize = size;
  document.querySelectorAll('.md-size-btn').forEach(function(b){
    b.style.borderColor='var(--g200)'; b.style.background='#fff'; b.style.color='var(--black)';
  });
  document.querySelectorAll('.md-size-btn').forEach(function(b){
    if(b.textContent.trim() === size){
      b.style.borderColor='var(--green)'; b.style.background='var(--green)'; b.style.color='#fff';
    }
  });
  var sizeMsg = document.getElementById('md-size-msg');
  if(sizeMsg) sizeMsg.style.display = 'none';
}

function addMerchFromDetail() {
  if(!currentMerchId || typeof MERCH_ITEMS==='undefined') return;
  var item = MERCH_ITEMS[currentMerchId];
  if(!item) return;
  if(item.needsSize && !selectedMerchSize){
    var sizeMsg = document.getElementById('md-size-msg');
    if(sizeMsg) sizeMsg.style.display = 'block';
    showT('\u26A0\uFE0F',_t('cart').size,_t('cart').selectSize);
    return;
  }
  var cartName = item.name;
  var cartId = item.id;
  if(item.needsSize && selectedMerchSize){
    cartName = item.name + ' ('+selectedMerchSize+')';
    cartId = item.id + '-' + selectedMerchSize;
  }
  addToCart(cartId, cartName, item.price);
}

// ===== VOUCHER FUNCTIONS =====

function selectVoucherType(type) {
  voucherType = type;
  const dEl = document.getElementById('voucher-digital');
  const pEl = document.getElementById('voucher-printed');
  if(dEl){dEl.style.borderColor = type==='digital' ? 'var(--green)' : 'rgba(255,255,255,.2)';dEl.style.background = type==='digital' ? 'rgba(116,251,113,.15)' : 'transparent';}
  if(pEl){pEl.style.borderColor = type==='printed' ? 'var(--green)' : 'rgba(255,255,255,.2)';pEl.style.background = type==='printed' ? 'rgba(116,251,113,.15)' : 'transparent';}
  // Update price button to reflect shipping cost
  updateVoucherPriceBtn();
}

function updateVoucherPriceBtn() {
  const priceBtn = document.getElementById('voucher-price-btn');
  if(!priceBtn) return;
  if(voucherAmt > 0) {
    const total = voucherType === 'printed' ? voucherAmt + 180 : voucherAmt;
    priceBtn.textContent = total.toLocaleString('cs-CZ') + ' Kč' + (voucherType === 'printed' ? ' ('+_t('cart').inclShipping+')' : '');
  } else {
    priceBtn.textContent = _t('cart').enterAmount;
  }
}

function selectVoucherAmt(amt) {
  voucherAmt = amt;
  document.querySelectorAll('.vamt-btn').forEach(b => {
    b.style.background = 'transparent';
    b.style.borderColor = 'rgba(255,255,255,.2)';
  });
  const sel = document.getElementById('vamt-' + amt);
  if(sel){sel.style.background='var(--green)';sel.style.borderColor='var(--green)';}
  const customWrap = document.getElementById('vamt-custom-wrap');
  if(customWrap) customWrap.style.display = amt === 0 ? 'block' : 'none';
  updateVoucherPriceBtn();
}

function customVoucherAmt(val) {
  voucherAmt = parseInt(val) || 0;
  updateVoucherPriceBtn();
}

function buyVoucher() {
  if(voucherAmt < 100){showT('⚠️',_t('cart').voucher,_t('cart').minVoucher);return;}
  const totalPrice = voucherType === 'printed' ? voucherAmt + 180 : voucherAmt;
  const typeName = voucherType === 'printed' ? ' ('+_t('cart').printed+')' : ' ('+_t('cart').digital+')';
  addToCart('voucher',_t('cart').giftVoucher+' ' + voucherAmt.toLocaleString('cs-CZ') + ' Kč' + typeName, totalPrice);
  showT('🎁',_t('cart').addedToCart,_t('cart').giftVoucher+' ' + voucherAmt.toLocaleString('cs-CZ') + ' Kč' + typeName);
}

// Voucher page (s-voucher) helpers
function selectVoucherAmtV(amt) {
  voucherAmt = amt;
  document.querySelectorAll('.vamt-btn-v').forEach(function(b){
    b.style.background='#fff'; b.style.borderColor='var(--g200)'; b.style.color='var(--black)';
  });
  var btns = document.querySelectorAll('.vamt-btn-v');
  btns.forEach(function(b){ if(parseInt(b.textContent.replace(/\s/g,''))===amt){b.style.background='var(--green)';b.style.borderColor='var(--green)';b.style.color='#fff';} });
  var ci = document.getElementById('vamt-custom-v');
  if(ci) ci.value='';
  updateVoucherPriceBtnV();
  // Also sync merch page state
  updateVoucherPriceBtn();
}
function customVoucherAmtV(val) {
  voucherAmt = parseInt(val) || 0;
  document.querySelectorAll('.vamt-btn-v').forEach(function(b){
    b.style.background='#fff'; b.style.borderColor='var(--g200)'; b.style.color='var(--black)';
  });
  updateVoucherPriceBtnV();
  updateVoucherPriceBtn();
}
function selectVoucherTypeV(type) {
  voucherType = type;
  var dEl=document.getElementById('vtype-digital-v');
  var pEl=document.getElementById('vtype-printed-v');
  if(dEl){dEl.style.borderColor=type==='digital'?'var(--green)':'var(--g200)';dEl.style.background=type==='digital'?'var(--gp)':'#fff';}
  if(pEl){pEl.style.borderColor=type==='printed'?'var(--green)':'var(--g200)';pEl.style.background=type==='printed'?'var(--gp)':'#fff';}
  updateVoucherPriceBtnV();
  // Sync merch page type
  selectVoucherType(type);
}
function updateVoucherPriceBtnV() {
  var priceBtn=document.getElementById('voucher-price-btn-v');
  if(!priceBtn) return;
  if(voucherAmt > 0) {
    var total = voucherType==='printed' ? voucherAmt+180 : voucherAmt;
    priceBtn.textContent = total.toLocaleString('cs-CZ')+' Kč'+(voucherType==='printed'?' ('+_t('cart').inclShipping+')':'');
  } else {
    priceBtn.textContent = _t('cart').enterAmount;
  }
}

// Checkout, booking price & address functions → js/cart-checkout.js
