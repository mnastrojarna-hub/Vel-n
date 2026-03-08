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
  's-invoices':'ni-profile',
  's-contracts':'ni-profile',
  's-sos-replacement':'ni-res'
};

function goTo(id){
  if(id===cur){const el=document.getElementById(id);if(el)el.scrollTo({top:0,behavior:'smooth'});return;}
  if(cur==='s-booking')bookingFromDetail=false;
  // Stop scanner camera when leaving scan screen
  if(cur==='s-doc-scan'&&typeof DocScanner!=='undefined') DocScanner.stopCamera();

  // --- State resets on navigation (BUG 2/3/4/5) ---
  // Full reset when going home or to search – clean start
  if(id==='s-home'||id==='s-search'){
    if(typeof resetBookingState==='function') resetBookingState();
    bookingMoto=null;
  }
  // Reset search dates when going home to prevent stale dates in detail pages
  if(id==='s-home'){
    if(typeof sOd!=='undefined') sOd=null;
    if(typeof sDo!=='undefined') sDo=null;
    if(typeof sStep!=='undefined') sStep=1;
  }
  // Reset detail-specific calendar step when entering a new detail
  // dOd/dDo are set in renderDetail() from sOd/sDo – don't clear here
  if(id==='s-detail'){
    dStep=1;
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
  if(id==='s-cart'&&typeof renderCart==='function')renderCart();
  if(id==='s-checkout'){
    if(typeof initCheckout==='function')initCheckout();
    var shipCost=(typeof shipMode!=='undefined'&&shipMode==='post')?99:0;
    const t=typeof cart!=='undefined'?cart.reduce((s,c)=>s+c.price*c.qty,0):0;
    const el=document.getElementById('checkout-total');if(el)el.textContent=(t+shipCost).toLocaleString('cs-CZ')+' Kč';
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
  }
  if(id==='s-invoices'){
    if(typeof renderInvoicesPage==='function') renderInvoicesPage();
    else if(typeof renderInvoices==='function') renderInvoices();
  }
  if(id==='s-contracts' && typeof renderContractsPage==='function') renderContractsPage();
  if(id==='s-sos-replacement' && typeof sosReplInit==='function') sosReplInit();
  if(typeof updateCartFab==='function')updateCartFab();
  if(typeof scrollCurrentToTop==='function')scrollCurrentToTop();
}

function histBack(){
  if(navStack.length<=1){if(cur!=='s-home'&&cur!=='s-login')goTo('s-home');return;}
  if(navStack.length>1){
    navStack.pop();
    const prev=navStack[navStack.length-1];
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
    // State resets on back navigation (same logic as goTo)
    if(prev==='s-home'||prev==='s-search'){
      if(typeof resetBookingState==='function') resetBookingState();
      bookingMoto=null;
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
