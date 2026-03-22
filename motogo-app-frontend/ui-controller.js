/* === UI-CONTROLLER.JS — Date picker, docs, protocol & misc UI === */

// ===== CUSTOM DATE PICKER =====
var _dpTarget=null;
var _dpY=2000,_dpM=0,_dpMode='day',_dpYBase=2000;
var _dpCallback=null;
function openDatePicker(inp){
  _dpCallback=null;_dpMode='day';
  _dpTarget=inp;
  var val=inp.value;
  if(val&&/\d{1,2}\.\s?\d{1,2}\.\s?\d{4}/.test(val)){
    var pts=val.split('.');_dpY=parseInt(pts[2]);_dpM=parseInt(pts[1])-1;
  } else {var n=new Date();_dpY=n.getFullYear();_dpM=n.getMonth();}
  var ov=document.getElementById('dp-overlay');
  if(!ov){ov=document.createElement('div');ov.id='dp-overlay';ov.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;padding:16px;';document.querySelector('.phone').appendChild(ov);}
  ov.style.display='flex';renderDP();
}
function openSearchDP(type){
  _dpTarget=null;_dpMode='day';
  _dpCallback=function(d,m,y){
    var val=y+'-'+String(m+1).padStart(2,'0')+'-'+String(d).padStart(2,'0');
    setSearchDateFromInput(type,val);
  };
  var n=new Date();_dpY=n.getFullYear();_dpM=n.getMonth();
  if(type==='do'&&typeof sOd!=='undefined'&&sOd){_dpY=sOd.y;_dpM=sOd.m;}
  var ov=document.getElementById('dp-overlay');
  if(!ov){ov=document.createElement('div');ov.id='dp-overlay';ov.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;padding:16px;';document.querySelector('.phone').appendChild(ov);}
  ov.style.display='flex';renderDP();
}
function renderDP(){
  var ov=document.getElementById('dp-overlay');if(!ov)return;
  if(_dpMode==='year'){renderDPYear();return;}
  var dim=new Date(_dpY,_dpM+1,0).getDate();
  var fd=new Date(_dpY,_dpM,1).getDay();fd=fd===0?6:fd-1;
  var now=new Date();now.setHours(0,0,0,0);
  var h='<div style="background:#fff;border-radius:18px;padding:18px;max-width:320px;width:100%;">'+
    '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">'+
    '<button onclick="_dpM--;if(_dpM<0){_dpM=11;_dpY--;}renderDP()" style="background:var(--g100);border:none;border-radius:8px;width:32px;height:32px;font-size:16px;cursor:pointer;">‹</button>'+
    '<div style="font-size:14px;font-weight:800;color:var(--black);">'+MONTHS[_dpM]+' <span onclick="_dpYBase=_dpY-_dpY%12;_dpMode=\'year\';renderDP()" style="cursor:pointer;text-decoration:underline dotted;text-underline-offset:3px;">'+_dpY+'</span></div>'+
    '<button onclick="_dpM++;if(_dpM>11){_dpM=0;_dpY++;}renderDP()" style="background:var(--g100);border:none;border-radius:8px;width:32px;height:32px;font-size:16px;cursor:pointer;">›</button></div>'+
    '<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:2px;text-align:center;font-size:10px;color:var(--g400);font-weight:700;margin-bottom:4px;">'+
    '<div>Po</div><div>Út</div><div>St</div><div>Čt</div><div>Pá</div><div>So</div><div>Ne</div></div>'+
    '<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:2px;">';
  for(var i=0;i<fd;i++)h+='<div></div>';
  for(var d=1;d<=dim;d++){
    var isPast=_dpCallback&&(new Date(_dpY,_dpM,d)<now);
    if(isPast){h+='<div style="text-align:center;padding:8px 0;font-size:13px;font-weight:600;border-radius:8px;color:var(--g400);opacity:.35;">'+d+'</div>';}
    else{h+='<div onclick="pickDP('+d+')" style="text-align:center;padding:8px 0;font-size:13px;font-weight:600;border-radius:8px;cursor:pointer;color:var(--black);background:'+(_dpCallback?'#bbf7d0':'var(--g100)')+';">'+d+'</div>';}
  }
  h+='</div><button onclick="closeDP()" style="width:100%;margin-top:12px;background:var(--g100);border:none;border-radius:10px;padding:10px;font-family:var(--font);font-size:13px;font-weight:600;cursor:pointer;color:var(--g400);">'+_t('common').cancel+'</button></div>';
  ov.innerHTML=h;
}
function renderDPYear(){
  var ov=document.getElementById('dp-overlay');if(!ov)return;
  var h='<div style="background:#fff;border-radius:18px;padding:18px;max-width:320px;width:100%;">'+
    '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">'+
    '<button onclick="_dpYBase-=12;renderDP()" style="background:var(--g100);border:none;border-radius:8px;width:32px;height:32px;font-size:16px;cursor:pointer;">‹</button>'+
    '<div style="font-size:14px;font-weight:800;color:var(--black);">'+_dpYBase+' – '+(_dpYBase+11)+'</div>'+
    '<button onclick="_dpYBase+=12;renderDP()" style="background:var(--g100);border:none;border-radius:8px;width:32px;height:32px;font-size:16px;cursor:pointer;">›</button></div>'+
    '<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:6px;">';
  for(var i=0;i<12;i++){
    var y=_dpYBase+i,sel=y===_dpY;
    h+='<div onclick="_dpY='+y+';_dpMode=\'day\';renderDP()" style="text-align:center;padding:12px 0;font-size:14px;font-weight:'+(sel?'800':'600')+';border-radius:10px;cursor:pointer;background:'+(sel?'var(--green)':'var(--g100)')+';color:'+(sel?'#fff':'var(--black)')+';">'+y+'</div>';
  }
  h+='</div><button onclick="_dpMode=\'day\';renderDP()" style="width:100%;margin-top:12px;background:var(--g100);border:none;border-radius:10px;padding:10px;font-family:var(--font);font-size:13px;font-weight:600;cursor:pointer;color:var(--g400);">'+_t('common').back+'</button></div>';
  ov.innerHTML=h;
}
function pickDP(d){
  if(_dpCallback){_dpCallback(d,_dpM,_dpY);}
  else if(_dpTarget){_dpTarget.value=d+'. '+(_dpM+1)+'. '+_dpY;_dpTarget.dispatchEvent(new Event('change'));}
  closeDP();
}
function closeDP(){var ov=document.getElementById('dp-overlay');if(ov)ov.style.display='none';}

// ===== EXPAND =====
function toggleExpand(expId,arrId){
  const exp=document.getElementById(expId);
  const arr=document.getElementById(arrId);
  const isOpen=exp.classList.contains('open');
  exp.classList.toggle('open',!isOpen);
  if(arr)arr.textContent=isOpen?'›':'∨';
}

// ===== DOCS =====
let docType='op',docCaps={op:null,pas:null,rp:null};
function _switchDocTab(t){
  docType=t;
  document.getElementById('dtab-id').classList.toggle('on',t==='op');
  document.getElementById('dtab-pas').classList.toggle('on',t==='pas');
  document.getElementById('dtab-rp').classList.toggle('on',t==='rp');
  renderDocs();
}
function switchDoc(t){_switchDocTab(t);}
function _handleDocFile(e,label){
  const f=e.target.files[0];if(!f)return;
  const r=new FileReader();
  r.onload=ev=>{docCaps[docType]=ev.target.result;renderDocs();showT('📋',_t('scan').docScanned,label);};
  r.readAsDataURL(f);e.target.value='';
}
function handleDocCap(e){_handleDocFile(e,_t('scan').scanned);}
function handleDocUp(e){
  // If called with file input event, use it
  if(e&&e.target&&e.target.files){_handleDocFile(e,_t('scan').uploaded);return;}
  // Cordova: use cordova-plugin-camera to pick from gallery
  if(navigator.camera){
    navigator.camera.getPicture(
      function(dataUrl){
        docCaps[docType]='data:image/jpeg;base64,'+dataUrl;
        renderDocs();
        showT('📋',_t('scan').docScanned||'Doklad nahrán',_t('scan').uploaded||'Uloženo');
      },
      function(err){
        if(err&&err.indexOf&&err.indexOf('cancel')!==-1) return;
        showT('❌','Galerie','Nepodařilo se vybrat snímek');
      },
      {quality:85,destinationType:0,sourceType:0,correctOrientation:true,targetWidth:1200,targetHeight:1600}
    );
    return;
  }
  // Browser fallback: open file picker
  var inp=document.createElement('input');
  inp.type='file';inp.accept='image/*';
  inp.onchange=function(ev){_handleDocFile(ev,_t('scan').uploaded||'Nahráno');};
  inp.click();
}
function renderDocs(){
  const labels={op:'🪪 Občanský průkaz',pas:'📕 Cestovní pas',rp:'🏍️ Řidičský průkaz'};
  var scanMap={op:'mg_doc_id_front',pas:'mg_doc_passport_front',rp:'mg_doc_dl_front'};
  for(var sk in scanMap){
    if(!docCaps[sk]){
      try{ var sv=localStorage.getItem(scanMap[sk]); if(sv) docCaps[sk]=sv; }catch(e){}
    }
  }
  var docCount = Object.values(docCaps).filter(function(v){return !!v;}).length;
  var html='';
  if(docCount > 0){
    html += '<div style="background:#ecfdf5;border:1px solid #6ee7b7;border-radius:12px;padding:12px 16px;margin-bottom:12px;display:flex;align-items:center;gap:10px;">' +
      '<span style="font-size:22px;">✅</span>' +
      '<div><div style="font-size:14px;font-weight:700;color:#065f46;">Doklady nahrány ('+docCount+')</div>' +
      '<div style="font-size:12px;color:#047857;">Uloženo v zařízení</div></div></div>';
  }
  html += Object.entries(docCaps).filter(([,v])=>v).map(([k,v])=>
    `<div class="dprev"><img src="${v}"><div class="dprev-lbl">${labels[k]}</div><button class="dprev-del" onclick="docCaps['${k}']=null;renderDocs()">✕</button></div>`
  ).join('');
  document.getElementById('doc-prev').innerHTML=html;
  var wrap=document.getElementById('doc-area-wrap');
  if(wrap) wrap.style.display=html?'':'none';
}

// ===== ONLINE DOT SIMULATION =====
// Toggle online/offline status for demo
let isOnline=true;
setInterval(()=>{
  // Simulate brief offline moments
  if(Math.random()<0.05){
    isOnline=false;
    const dot=document.getElementById('online-dot');
    if(dot){dot.classList.add('offline');dot.title='Offline – bez připojení';}
    setTimeout(()=>{
      isOnline=true;
      const dot2=document.getElementById('online-dot');
      if(dot2){dot2.classList.remove('offline');dot2.title='Online';}
    },2000);
  }
},8000);

// savePersonalData, deleteAccount → js/storage.js

// ===== SHARE LOCATION =====
function shareLocation(){
  if(!navigator.geolocation){showT('❌',_t('sos').gpsUnavailable,_t('sos').browserNoGPS);return;}
  showT('📍',_t('sos').locating,_t('sos').pleaseWait);
  navigator.geolocation.getCurrentPosition(
    pos=>{const lat=pos.coords.latitude.toFixed(5),lng=pos.coords.longitude.toFixed(5);showT('📍',_t('sos').locationShared,lat+', '+lng);},
    err=>{
      if(err.code===1)showT('❌',_t('sos').accessDenied,_t('sos').allowLocation);
      else showT('❌',_t('sos').gpsUnavailable,_t('sos').cannotGetLocation);
    },
    {enableHighAccuracy:true,timeout:15000,maximumAge:0}
  );
}

// ===== REPORT MINOR ACCIDENT =====
function reportMinorAccident(){
  const ts=new Date().toLocaleString('cs-CZ');
  showT('🟡',_t('sos').incidentRecorded,ts);
}

// ===== NEHODA / NEPOJIZDA =====
function setNehoda(vinik){
  const bv=document.getElementById('btn-vinik');
  const bn=document.getElementById('btn-nevinik');
  const info=document.getElementById('nehoda-nahrada');
  if(vinik){
    if(bv){bv.style.background='#b91c1c';bv.style.color='#fff';bv.style.border='none';}
    if(bn){bn.style.background='var(--g100)';bn.style.color='var(--black)';bn.style.border='2px solid var(--g200)';}
    if(info)info.innerHTML='<div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:var(--rsm);padding:10px 12px;font-size:12px;font-weight:600;color:#b91c1c;line-height:1.6;width:100%;">⚠️ '+_t('sos').faultVinikMsg+'</div>';
  } else {
    if(bn){bn.style.background='var(--green)';bn.style.color='#fff';bn.style.border='none';}
    if(bv){bv.style.background='var(--g100)';bv.style.color='var(--black)';bv.style.border='2px solid var(--g200)';}
    if(info)info.innerHTML='<div style="background:var(--gp);border:1px solid var(--green);border-radius:var(--rsm);padding:10px 12px;font-size:12px;font-weight:600;color:var(--gd);line-height:1.6;width:100%;">💚 '+_t('sos').faultNevinikMsg+'</div>';
  }
}
function setNepojizda(vinik){
  _sosFault = vinik;
  _sosFaultSnapshot = vinik;
  // Keep _sosActiveIncidentId — reuse existing incident, don't create duplicate
  const bv=document.getElementById('btn-nepoj-vinik');
  const bn=document.getElementById('btn-nepoj-nevinik');
  const info=document.getElementById('nepojizda-info');
  const tit=document.getElementById('nahr-title');
  const sub=document.getElementById('nahr-sub');
  if(vinik){
    if(bv){bv.style.background='#b91c1c';bv.style.color='#fff';bv.style.border='none';}
    if(bn){bn.style.background='var(--g100)';bn.style.color='var(--black)';bn.style.border='2px solid var(--g200)';}
    if(info)info.innerHTML='<div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:var(--rsm);padding:10px 12px;font-size:12px;font-weight:600;color:#b91c1c;line-height:1.6;">⚠️ '+_t('sos').nepojVinikMsg+'</div>';
    if(tit)tit.innerHTML=_t('sos').replacementFee;
    if(sub)sub.textContent=_t('sos').deliveryFee;
  } else {
    if(bn){bn.style.background='var(--green)';bn.style.color='#fff';bn.style.border='none';}
    if(bv){bv.style.background='var(--g100)';bv.style.color='var(--black)';bv.style.border='2px solid var(--g200)';}
    if(info)info.innerHTML='<div style="background:var(--gp);border:1px solid var(--green);border-radius:var(--rsm);padding:10px 12px;font-size:12px;font-weight:600;color:var(--gd);line-height:1.6;">💚 '+_t('sos').nepojNevinikMsg+'</div>';
    if(tit)tit.innerHTML=_t('sos').replacementFree;
    if(sub)sub.textContent=_t('sos').deliveryFree;
  }
}

// ===== SOS NEARBY SERVIS =====
function sosNearbyServis(){
  showT('📍',_t('sos').searchService,_t('sos').openMaps);
  setTimeout(()=>window.open('https://www.google.com/maps/search/motocyklový+servis+nearby','_blank'),800);
}

// ===== RATE RIDE =====
var _currentRating=5;
function rateRide(val){
  _currentRating=val;
  document.querySelectorAll('.star-btn').forEach((s,i)=>{
    s.style.color=i<val?'#f59e0b':'#d1d5db';
    s.style.transform=i<val?'scale(1.15)':'scale(1)';
  });
  const msgs=['','😞 '+_t('res').badExp,'😐 '+_t('res').average,'🙂 '+_t('res').good,'😊 '+_t('res').veryGood,'🏆 '+_t('res').excellent];
  const msg=document.getElementById('done-rating-msg');
  if(msg)msg.textContent=msgs[val]||'';
  // Save rating to DB
  if(_currentResId && _isSupabaseReady()){
    supabase.from('bookings').update({rating:val,rated_at:new Date().toISOString()}).eq('id',_currentResId)
      .then(()=>{}).catch(e=>console.warn('[RATE]',e));
  }
  showT('⭐',_t('res').thankStars.replace('{n}',val),_t('res').feedbackHelps);
  // Show Google review prompt after rating
  if(val >= 4) _showGoogleReviewBanner();
}

// ===== GOOGLE RECENZE =====
var _googleReviewUrl = null;
async function _loadGoogleReviewUrl(){
  if(_googleReviewUrl) return _googleReviewUrl;
  if(!window.supabase) return null;
  try {
    var r = await window.supabase.from('app_settings').select('value').eq('key','google_review_url').maybeSingle();
    if(r.data && r.data.value){
      _googleReviewUrl = typeof r.data.value === 'string' ? r.data.value : r.data.value.url || r.data.value;
      return _googleReviewUrl;
    }
  } catch(e){}
  // Fallback placeholder URL
  return 'https://search.google.com/local/writereview?placeid=PLACE_ID';
}

function _showGoogleReviewBanner(){
  var el = document.getElementById('done-google-review');
  if(el) el.style.display = 'block';
}

async function _openGoogleReview(){
  var url = await _loadGoogleReviewUrl();
  // Track that user was asked for review
  if(window.supabase && _currentResId){
    try {
      var uid = await _getUserId();
      if(uid){
        window.supabase.from('reviews').insert({
          booking_id: _currentResId,
          customer_id: uid,
          source: 'google_prompt',
          created_at: new Date().toISOString()
        }).then(function(){}).catch(function(){});
      }
    } catch(e){}
  }
  if(url) {
    if(typeof openExternalLink === 'function') openExternalLink(url);
    else window.open(url, '_blank');
  }
  var el = document.getElementById('done-google-review');
  if(el) el.style.display = 'none';
}

function _initDoneDetailGoogleReview(booking){
  var el = document.getElementById('done-google-review');
  if(!el) return;
  // Show only for completed bookings that haven't been rated yet
  if(booking && booking.status === 'completed' && !booking.rated_at){
    el.style.display = 'block';
  } else {
    el.style.display = 'none';
  }
}

// ===== DIGITÁLNÍ PŘEDÁVACÍ PROTOKOL JS =====
let protocolSigned=false;
function signProtocol(method){
  if(method==='biometric'){
    // Simulate biometric
    showT('🔐',_t('sos').verifying,_t('sos').bioVerification);
    setTimeout(()=>finalizeSignature(),1200);
  } else {
    document.getElementById('pin-input-wrap').style.display='block';
  }
}
function confirmPin(){
  const pin=document.getElementById('proto-pin')?.value||'';
  if(pin.length<4){showT('⚠️',_t('sos').pin,_t('sos').enterPin);return;}
  finalizeSignature();
}
function finalizeSignature(){
  protocolSigned=true;
  const now=new Date().toLocaleString('cs-CZ');
  const pinWrap=document.getElementById('pin-input-wrap');
  if(pinWrap) pinWrap.style.display='none';
  const signed=document.getElementById('proto-signed');
  if(signed) signed.style.display='block';
  const time=document.getElementById('proto-signed-time');
  var _signerName=(document.getElementById('home-user-name')&&document.getElementById('home-user-name').textContent)||'';
  if(time) time.textContent='Podepsáno: '+now+(_signerName?' · '+_signerName:'');
  showT('✅',_t('sos').sigConfirmed,_t('sos').protocolSigned);
}
function submitProtocol(){
  if(!protocolSigned){showT('⚠️',_t('sos').sigConfirmed,_t('sos').signFirst);return;}
  showT('📤',_t('sos').submitted,_t('sos').protocolSent);
  setTimeout(()=>histBack(),1500);
}

// ===== STORNO DIALOG =====
function openStornoDialog(bookingId){
  var bid = bookingId || (typeof _currentResId !== 'undefined' ? _currentResId : null);
  if(!bid){ showT('✗',_t('common').error,_t('sos').noResToCancel); return; }
  if(typeof doCancelBooking === 'function'){ doCancelBooking(bid); return; }
}

// ===== ZAHRANIČNÍ JÍZDA =====
function toggleForeign(cb){
  const det=document.getElementById('foreign-detail');
  if(det) det.style.display=cb.checked?'block':'none';
}

// ===== DIGITÁLNÍ PŘEDÁVACÍ PROTOKOL =====
function showDigitalProtocol(){
  goTo('s-protocol');
}

// ===== EXTERNAL LINKS =====
function openExternalLink(url){
  if(!url) return;
  // On Capacitor (native), use Browser plugin or system browser
  if(typeof Capacitor !== 'undefined' && Capacitor.isNativePlatform && Capacitor.isNativePlatform()){
    if(typeof Browser !== 'undefined' && Browser.open){
      Browser.open({ url: url });
    } else {
      window.open(url, '_system');
    }
  } else {
    // Web: open in new tab
    window.open(url, '_blank', 'noopener,noreferrer');
  }
}

// ===== CONTACT DETAILS TOGGLE =====
function toggleContactDetails(){
  var exp=document.getElementById('contact-expanded');
  var arr=document.getElementById('contact-arrow');
  if(!exp)return;
  if(exp.style.display==='none'){
    exp.style.display='block';
    if(arr)arr.style.transform='rotate(90deg)';
  } else {
    exp.style.display='none';
    if(arr)arr.style.transform='rotate(0deg)';
  }
}

// ===== SCROLL TO TOP =====
function scrollCurrentToTop(){
  var s=document.getElementById(cur);
  if(s) s.scrollTo({top:0,behavior:'smooth'});
}
function initScrollTop(){
  var btn=document.getElementById('scroll-top-btn');
  if(!btn) return;
  // Capture scroll events on all screens via event delegation
  document.querySelector('.phone').addEventListener('scroll',function(e){
    var target=e.target;
    if(target && target.classList && target.classList.contains('screen') && target.id===cur){
      btn.classList.toggle('visible', target.scrollTop > 300);
    }
  }, true);
  btn.onclick = function(e){
    e.preventDefault();
    e.stopPropagation();
    var s=document.getElementById(cur);
    if(s) s.scrollTo({top:0,behavior:'smooth'});
  };
}
