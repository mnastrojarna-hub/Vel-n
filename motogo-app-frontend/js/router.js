// ===== ROUTER.JS – Screen switching, navigation and shared calendar =====

// ===== NAVIGATION WITH PROPER HISTORY =====
var cur = '';
var navStack = [];
const noNav = ['s-login','s-success','s-docs','s-register','s-doc-scan'];
const navMap = {
  's-home':'ni-home',
  's-search':'ni-search',
  's-detail':'ni-search',
  's-booking':'ni-search',
  's-payment':'ni-search',
  's-res':'ni-res',
  's-res-detail':'ni-res',
  's-edit-res':'ni-res',
  's-done-detail':'ni-res',
  's-merch':'ni-merch',
  's-cart':'ni-merch',
  's-checkout':'ni-merch',
  's-merch-detail':'ni-merch',
  's-voucher':'ni-merch',
  's-profile':'ni-profile',
  's-messages':'ni-profile',
  's-messages-thread':'ni-profile',
  's-invoices':'ni-profile',
  's-contracts':'ni-profile',
  's-sos-replacement':'ni-res',
  's-sos-payment':'ni-res',
  's-sos-done':'ni-res',
  's-ai-agent':'ni-res'
};

// Screens that require authentication — if no session, redirect to login
var _authRequired = ['s-home','s-res','s-res-detail','s-edit-res','s-done-detail','s-booking','s-payment','s-success','s-profile','s-messages','s-messages-thread','s-invoices','s-contracts','s-sos','s-sos-replacement','s-sos-payment','s-sos-done'];

function goTo(id){
  if(id===cur){const el=document.getElementById(id);if(el)el.scrollTo({top:0,behavior:'smooth'});return;}
  // Block leaving payment screen when Stripe checkout is open (except to success/res which are valid post-payment destinations)
  if(typeof _stripeCheckoutOpened!=='undefined' && _stripeCheckoutOpened && (cur==='s-payment'||cur==='s-sos-payment') && id!=='s-success' && id!=='s-res' && id!=='s-res-detail' && id!=='s-sos-done'){
    showT('⚠️','Platba probíhá','Vyčkejte na dokončení platby');
    if(typeof _checkPaymentAfterStripe==='function') _checkPaymentAfterStripe();
    return;
  }
  // Auth guard: block protected screens when not logged in
  if(_authRequired.indexOf(id)!==-1 && id!=='s-login'){
    var _sess=null;
    try{var _r=localStorage.getItem('mg_current_session');if(_r)_sess=JSON.parse(_r);}catch(e){}
    if(!_sess || !_sess.user_id){
      if(typeof showT==='function') showT('⚠️','Přihlášení','Pro pokračování se musíte přihlásit');
      id='s-login';
    }
  }
  if(id===cur){return;}
  if(cur==='s-booking')bookingFromDetail=false;
  // Hide thread reply bar when leaving thread screen
  if(cur==='s-messages-thread'&&id!=='s-messages-thread'){var _rb=document.getElementById('thread-reply-bar');if(_rb)_rb.style.display='none';}
  // Stop scanner camera when leaving scan screen
  if(cur==='s-doc-scan'&&typeof DocScanner!=='undefined') DocScanner.stopCamera();

  // Clear 5-min payment auto-cancel when leaving s-payment — FAB + backend cron will handle expiry
  if(cur==='s-payment' && id!=='s-success'){
    if(typeof _paymentTimeout!=='undefined' && _paymentTimeout){ clearTimeout(_paymentTimeout); _paymentTimeout=null; }
  }
  // --- State resets on navigation (BUG 2/3/4/5) ---
  // Full reset when going home or to search – clean start
  if(id==='s-home'||id==='s-search'){
    if(typeof resetBookingState==='function') resetBookingState();
    bookingMoto=null;
    if(typeof dOd!=='undefined') dOd=null;
    if(typeof dDo!=='undefined') dDo=null;
    if(typeof bOd!=='undefined') bOd=null;
    if(typeof bDo!=='undefined') bDo=null;
  }
  // Reset search dates when going home to prevent stale dates in detail pages
  if(id==='s-home'){
    if(typeof sOd!=='undefined') sOd=null;
    if(typeof sDo!=='undefined') sDo=null;
    if(typeof sStep!=='undefined') sStep=1;
  }
  // Reset detail-specific state when entering a new detail
  if(id==='s-detail'){
    dStep=1;
    if(typeof dOd!=='undefined') dOd=null;
    if(typeof dDo!=='undefined') dDo=null;
  }
  // Cart FAB: only re-show after addToCart, not on navigation

  var curEl=document.getElementById(cur);
  if(curEl)curEl.classList.add('hidden');
  // If navigating to a top-level tab, reset the navStack
  var topTabs=['s-home','s-search','s-res','s-merch','s-profile'];
  if(topTabs.indexOf(id)!==-1){navStack=[id];}else{navStack.push(id);}
  cur=id;
  const nx=document.getElementById(id);
  nx.classList.remove('hidden');
  nx.scrollTop=0;
  const stb=document.getElementById('scroll-top-btn');if(stb)stb.classList.remove('visible');
  document.getElementById('bnav').style.display=noNav.includes(id)?'none':'flex';
  document.querySelectorAll('.ni').forEach(n=>n.classList.remove('active'));
  const k=navMap[id];
  if(k)document.getElementById(k)?.classList.add('active');
  // Re-render dynamic screens — refreshni MOTOS z DB při každém návratu
  if(id==='s-home'){
    if(typeof enrichMOTOS==='function') enrichMOTOS().then(function(){
      if(typeof applyHomeFilters==='function') applyHomeFilters();
    }); else if(typeof applyHomeFilters==='function') applyHomeFilters();
  }
  if(id==='s-search'){
    if(typeof enrichMOTOS==='function') enrichMOTOS().then(function(){
      if(typeof buildCal==='function') buildCal('s');
      if(typeof applyFilters==='function') applyFilters();
    }); else {
      if(typeof buildCal==='function') buildCal('s');
      if(typeof applyFilters==='function') applyFilters();
    }
  }
  if(id==='s-res'){
    if(typeof initDynamicDates==='function')initDynamicDates();
    if(typeof updateResButtons==='function')updateResButtons();
    if(typeof renderMyReservations==='function')renderMyReservations();
  }
  if(id==='s-profile'){
    if(typeof renderProfile==='function')renderProfile();
  }
  if(id==='s-home'){
    if(typeof renderUserData==='function')renderUserData();
  }
  if(id==='s-merch'&&typeof renderShopProducts==='function')renderShopProducts();
  if(id==='s-cart'&&typeof renderCart==='function')renderCart();
  if(id==='s-checkout'){
    if(typeof initCheckout==='function')initCheckout();
    var shipCost=(typeof shipMode!=='undefined'&&shipMode==='post')?99:0;
    const t=typeof cart!=='undefined'?cart.reduce((s,c)=>s+c.price*c.qty,0):0;
    const el=document.getElementById('checkout-total');if(el)el.textContent=(t+shipCost).toLocaleString('cs-CZ')+' Kč';
    if(typeof _showCheckoutSavedCard==='function')_showCheckoutSavedCard();
  }
  if(id==='s-booking'){
    // Require login for booking (check local session sync)
    var _bsLocal=null;
    try { var _raw=localStorage.getItem('mg_current_session'); if(_raw) _bsLocal=JSON.parse(_raw); } catch(e){}
    if(!_bsLocal){showT('⚠️','Přihlášení','Pro rezervaci se musíte přihlásit');goTo('s-login');return;}
    // Preserve booking state - only reset extras, not core data
    extraTotal=0; discountAmt=0;
    // Reset extra checkboxes
    document.querySelectorAll('#s-booking label[id^="extra-"]').forEach(function(lbl){
      var cb=lbl.querySelector('input[type=checkbox]');
      if(cb)cb.checked=false;
      lbl.style.borderColor='var(--g200)';
    });
    // Restore date display if dates exist
    if(bOd && bDo){
      var bs=document.getElementById('b-date-summary');
      var bw=document.getElementById('b-cal-wrap');
      if(bs){
        document.getElementById('b-od-txt').textContent=bOd.d+'. '+(bOd.m+1)+'. '+bOd.y;
        document.getElementById('b-do-txt').textContent=bDo.d+'. '+(bDo.m+1)+'. '+bDo.y;
        bs.style.display='block';
      }
      if(bw) bw.style.display='none';
      bookingFromDetail=true;
    } else if(bookingFromDetail===false || (!bOd && !bDo)){
      var bs2=document.getElementById('b-date-summary');
      var bw2=document.getElementById('b-cal-wrap');
      if(bs2)bs2.style.display='none';
      if(bw2){bw2.style.display='block'; buildBCal();}
    }
    // Restore moto info if exists
    if(bookingMoto){
      var bi=document.getElementById('b-img');
      if(bi) bi.src=(bookingMoto.imgs&&bookingMoto.imgs.length)?bookingMoto.imgs[0]:(bookingMoto.img||'');
      var bn=document.getElementById('b-name');
      if(bn) bn.textContent=bookingMoto.name;
    }
    if(typeof filterTimeChips==='function')filterTimeChips();
    recalcTotal();
    // Fill contact data
    if(typeof renderUserData==='function') renderUserData();
  }
  if(id==='s-messages'){
    if(typeof renderAdminMessages==='function') renderAdminMessages();
    if(typeof renderThreadsList==='function') renderThreadsList();
  }
  if(id==='s-messages-thread'){
    if(typeof renderThreadChat==='function') renderThreadChat();
  }
  if(id==='s-invoices'){
    if(typeof _invResetCache==='function') _invResetCache();
    if(typeof renderInvoicesPage==='function') renderInvoicesPage();
    else if(typeof renderInvoices==='function') renderInvoices();
  }
  if(id==='s-contracts'){
    if(typeof _conResetCache==='function') _conResetCache();
    if(typeof renderContractsPage==='function') renderContractsPage();
  }
  // Pre-fetch active booking/moto IDs on any SOS screen entry
  if(id.indexOf('s-sos')===0 && typeof _sosPreFetchIds==='function') _sosPreFetchIds();
  if(id==='s-sos' && typeof _sosCheckActiveIncident==='function') _sosCheckActiveIncident();
  // Inject SOS photo step on relevant screens
  if(id==='s-sos-nehoda' && typeof _sosInjectPhotoStep==='function') setTimeout(function(){ _sosInjectPhotoStep('sos-photo-step-nehoda'); },50);
  if(id==='s-sos-porucha' && typeof _sosInjectPhotoStep==='function') setTimeout(function(){ _sosInjectPhotoStep('sos-photo-step-porucha'); },50);
  if(id==='s-sos-kradez' && typeof _sosInjectPhotoStep==='function') setTimeout(function(){ _sosInjectPhotoStep('sos-photo-step-kradez'); },50);
  if(id==='s-sos-replacement' && typeof sosReplInit==='function') sosReplInit();
  if(id==='s-sos-payment' && typeof _sosInitPaymentFromRouter==='function') _sosInitPaymentFromRouter();
  if(typeof updateCartFab==='function')updateCartFab();
  // Update booking & SOS FABs visibility on navigation
  if(typeof _updateBookingFabVisibility==='function')_updateBookingFabVisibility();
  if(typeof _updateSosFabVisibility==='function')_updateSosFabVisibility();
  if(typeof scrollCurrentToTop==='function')scrollCurrentToTop();
  // Debug panel – show diagnostics on every screen
  if(typeof _debugPanel==='function') setTimeout(function(){ _debugPanel(id); }, 100);
}

function histBack(){
  // Block back when Stripe checkout is open — prevent double payment
  if(typeof _stripeCheckoutOpened!=='undefined' && _stripeCheckoutOpened && (cur==='s-payment'||cur==='s-sos-payment')){
    showT('⚠️','Platba probíhá','Vyčkejte na dokončení platby');
    if(typeof _checkPaymentAfterStripe==='function') _checkPaymentAfterStripe();
    return;
  }
  if(navStack.length<=1){if(cur!=='s-home'&&cur!=='s-login')goTo('s-home');return;}
  if(navStack.length>1){
    navStack.pop();
    const prev=navStack[navStack.length-1];
    var leavingScreen=cur;
    // Hide thread reply bar when leaving thread screen via back
    if(cur==='s-messages-thread'){var _rb2=document.getElementById('thread-reply-bar');if(_rb2)_rb2.style.display='none';}
    var curEl=document.getElementById(cur);
    if(curEl)curEl.classList.add('hidden');
    cur=prev;
    const nx=document.getElementById(prev);
    if(nx){nx.classList.remove('hidden');nx.scrollTop=0;}
    const stb2=document.getElementById('scroll-top-btn');if(stb2)stb2.classList.remove('visible');
    document.getElementById('bnav').style.display=noNav.includes(prev)?'none':'flex';
    document.querySelectorAll('.ni').forEach(n=>n.classList.remove('active'));
    const k=navMap[prev];
    if(k)document.getElementById(k)?.classList.add('active');
    // Clear 5-min payment auto-cancel when leaving s-payment via back
    if(leavingScreen==='s-payment'){
      if(typeof _paymentTimeout!=='undefined' && _paymentTimeout){ clearTimeout(_paymentTimeout); _paymentTimeout=null; }
    }
    // State resets on back navigation (same logic as goTo)
    if(prev==='s-home'||prev==='s-search'){
      if(typeof resetBookingState==='function') resetBookingState();
      bookingMoto=null;
      if(typeof dOd!=='undefined') dOd=null;
      if(typeof dDo!=='undefined') dDo=null;
      if(typeof bOd!=='undefined') bOd=null;
      if(typeof bDo!=='undefined') bDo=null;
    }
    if(prev==='s-home'){
      if(typeof sOd!=='undefined') sOd=null;
      if(typeof sDo!=='undefined') sDo=null;
      if(typeof sStep!=='undefined') sStep=1;
    }
    // Cart FAB: respect user's X dismiss – do not reset cartFabDismissed on back navigation
    // Re-render dynamic screens on back navigation — refreshni MOTOS z DB
    if(prev==='s-home'){
      if(typeof enrichMOTOS==='function') enrichMOTOS().then(function(){
        if(typeof applyHomeFilters==='function') applyHomeFilters();
      }); else if(typeof applyHomeFilters==='function') applyHomeFilters();
    }
    if(prev==='s-detail'&&typeof renderDetail==='function')renderDetail();
    if(prev==='s-res'){if(typeof initDynamicDates==='function')initDynamicDates();if(typeof updateResButtons==='function')updateResButtons();if(typeof renderMyReservations==='function')renderMyReservations();}
    if(prev==='s-profile'&&typeof renderProfile==='function')renderProfile();
    // Reset SOS replacement mode on back from edit
    if(typeof _sosReplacementMode!=='undefined'&&_sosReplacementMode){_sosReplacementMode=false;var sb=document.getElementById('sos-edit-banner');if(sb)sb.remove();}
    if(typeof updateCartFab==='function')updateCartFab();
    if(typeof _updateBookingFabVisibility==='function')_updateBookingFabVisibility();
    if(typeof _updateSosFabVisibility==='function')_updateSosFabVisibility();
  }
}

// ===== SHARED CALENDAR GENERATOR =====
function genCal(y,m,fn,motoId){
  var occ,unc;
  if(motoId && typeof getMotoOcc==='function'){
    occ=getMotoOcc(motoId,m);
    unc=getMotoUnconf(motoId,m);
  } else {
    occ=OCC[m]||[];
    unc=UNCONF[m]||[];
  }
  const fd=new Date(y,m,1).getDay();
  const off=fd===0?6:fd-1;
  const dim=new Date(y,m+1,0).getDate();
  const now=new Date();
  const todayY=now.getFullYear(),todayM=now.getMonth(),todayD=now.getDate();
  let h='';
  for(let i=0;i<off;i++)h+=`<button class="cd empty" disabled></button>`;
  for(let d=1;d<=dim;d++){
    const isPast=(y<todayY)||(y===todayY&&m<todayM)||(y===todayY&&m===todayM&&d<todayD);
    if(isPast)h+=`<button class="cd occupied" disabled>${d}</button>`;
    else if(occ.includes(d))h+=`<button class="cd occupied" disabled title="Potvrzená rezervace">${d}</button>`;
    else if(unc.includes(d))h+=`<button class="cd unconfirmed" disabled title="Nepotvrzená rezervace – čeká na platbu (4h)">${d}</button>`;
    else h+=`<button class="cd free" onclick="${fn}(this,${d},${y},${m})">${d}</button>`;
  }
  return h;
}
