// ===== SCAN-FLOW.JS – Integrates doc scanning into registration & post-payment =====
// Scan is triggered: 1) when clicking "Registrovat se", 2) after payment if skipped

var _pendingBookingAction = null;

// Check if documents have been scanned and verified (localStorage cache, DB-backed)
function isDocsVerified(){
  try{ return localStorage.getItem('mg_docs_verified')==='1'; }
  catch(e){ return false; }
}

// Async DB-backed check — authoritative, survives reinstall
async function isDocsVerifiedFromDB(){
  if(typeof apiCheckDocsVerified==='function'){
    var v=await apiCheckDocsVerified();
    return v;
  }
  return isDocsVerified();
}

// Quick check whether camera is likely to work (no actual permission prompt)
function _isCameraLikelyAvailable(){
  var _d = (typeof CamDebug!=='undefined') ? CamDebug.log.bind(CamDebug) : function(){};
  var ok = true;
  // 1) Web API must exist (requires secure context)
  if(!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia){
    _d('FLOW','mediaDevices/getUserMedia MISSING');
    ok = false;
  }
  // 2) On Capacitor native – check if Camera plugin is reachable
  var Cap = window.Capacitor;
  if(Cap && Cap.isNativePlatform && Cap.isNativePlatform()){
    var cam = Cap.Plugins && Cap.Plugins.Camera;
    _d('FLOW','native platform, Camera plugin='+!!cam+', requestPermissions='+!!(cam&&cam.requestPermissions));
    if(!cam || typeof cam.requestPermissions !== 'function') ok = false;
  } else {
    _d('FLOW','browser/web platform');
  }
  _d('FLOW','_isCameraLikelyAvailable => '+ok);
  return ok;
}

// Called from "Registrovat se" button – go straight to registration form
function startRegistrationWithScan(){
  var _d = (typeof CamDebug!=='undefined') ? CamDebug.log.bind(CamDebug) : function(){};
  _d('FLOW','startRegistrationWithScan called – skipping scanner, going to form');
  goTo('s-register');
}

// Booking flow – require login, go straight to booking (no scan here)
async function startBookingWithScan(setupFn){
  var session = await _getSession();
  if(!session){
    showT('⚠️',_t('scan').loginRequired,_t('scan').loginForBooking);
    goTo('s-login');
    return;
  }
  if(setupFn) setupFn();
  goTo('s-booking');
}

// Called after registration completes to continue to booking
function continuePendingBooking(){
  if(_pendingBookingAction){
    var fn = _pendingBookingAction;
    _pendingBookingAction = null;
    fn();
    goTo('s-booking');
  }
}

// Post-payment: prompt scan if docs not yet verified
async function promptPostPaymentScan(){
  if(isDocsVerified()) return;
  // Double-check from DB (survives reinstall/update)
  var dbVerified=await isDocsVerifiedFromDB();
  if(dbVerified) return;
  var ov = document.getElementById('post-pay-scan-overlay');
  if(!ov){
    ov = document.createElement('div');
    ov.id = 'post-pay-scan-overlay';
    ov.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;padding:20px;';
    document.querySelector('.phone').appendChild(ov);
  }
  ov.innerHTML = '<div style="background:#fff;border-radius:18px;padding:24px;max-width:320px;width:100%;text-align:center;">' +
    '<div style="font-size:48px;margin-bottom:12px;">📋</div>' +
    '<div style="font-size:18px;font-weight:900;color:var(--black);margin-bottom:6px;">'+_t('scan').uploadDocs+'</div>' +
    '<div style="font-size:13px;color:var(--g400);margin-bottom:6px;line-height:1.5;">'+_t('scan').docsNeeded+'</div>' +
    '<div style="font-size:12px;color:#b91c1c;margin-bottom:16px;line-height:1.5;background:#fff5f5;border:1px solid #fca5a5;border-radius:10px;padding:10px;">⚠️ '+_t('scan').noDocsWarning+'</div>' +
    '<button onclick="closePostPayScan();openDocScanner(\'s-success\')" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:12px;padding:14px;font-family:var(--font);font-size:14px;font-weight:700;cursor:pointer;margin-bottom:8px;">'+_t('scan').scanDocs+'</button>' +
    '<button onclick="closePostPayScan()" style="width:100%;background:var(--g100);color:var(--black);border:none;border-radius:12px;padding:14px;font-family:var(--font);font-size:13px;font-weight:600;cursor:pointer;">'+_t('scan').scanLater+'</button>' +
    '</div>';
  ov.style.display = 'flex';
}

// Open scanner from profile "Moje doklady" – same scanner as registration
function openDocsProfileScan(){
  var _d = (typeof CamDebug!=='undefined') ? CamDebug.log.bind(CamDebug) : function(){};
  _d('FLOW','openDocsProfileScan called');
  if(typeof ScannerUI!=='undefined' && _isCameraLikelyAvailable()){
    ScannerUI.open('s-docs');
  } else {
    _d('FLOW','camera unavailable for docs scan');
    showT('⚠️','Fotoaparát','Kamera není dostupná – nahrajte doklady z galerie');
  }
}

function closePostPayScan(){
  var ov = document.getElementById('post-pay-scan-overlay');
  if(ov) ov.style.display = 'none';
}
