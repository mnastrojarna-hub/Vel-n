/* === UI-TOAST-HELPERS.JS — Toast, bio button & initial helpers === */

// ===== TOAST =====
let tT;
function showT(icon,title,sub){
  clearTimeout(tT);
  document.getElementById('t-i').textContent=icon;
  document.getElementById('t-t').textContent=title;
  document.getElementById('t-s').textContent=sub;
  document.getElementById('toast').classList.add('show');
  tT=setTimeout(()=>document.getElementById('toast').classList.remove('show'),3000);
}

// Permissions (grantPerms, skipPerms, initPerms) → js/storage.js

// ===== BIO BUTTON =====
// Browser fallback: show bio button if previously enabled or if
// Cordova/Capacitor fingerprint is available (native-bridge.js overrides this)
function setupBioButton(){
  var bs=document.getElementById('bio-section');
  if(!bs) return;
  // Check Cordova fingerprint plugin (VoltBuilder builds)
  if(window.Fingerprint){
    window.Fingerprint.isAvailable(function(){
      bs.style.display='';
      var icon=document.getElementById('bio-icon');
      var label=document.getElementById('bio-label');
      var sub=document.getElementById('bio-sub');
      if(icon) icon.textContent='\ud83d\udd10';
      if(label) label.textContent=_t('auth').biometricBtn||'Biometrick\u00e9 p\u0159ihl\u00e1\u0161en\u00ed';
      if(sub) sub.textContent=_t('auth').fingerprint||'Otisk prstu';
      try{localStorage.setItem('mg_bio_enabled','1');}catch(e){}
    },function(){
      if(localStorage.getItem('mg_bio_enabled')){bs.style.display='';}
      else{bs.style.display='none';}
    });
    return;
  }
  // Browser fallback: show only if previously enabled
  if(!localStorage.getItem('mg_bio_enabled')){bs.style.display='none';return;}
  bs.style.display='';
  document.getElementById('bio-icon').textContent='\ud83d\udc46';
  document.getElementById('bio-label').textContent=_t('auth').fingerprint;
  document.getElementById('bio-sub').textContent=_t('auth').biometricBtn;
}

// ===== LOGIN / REGISTER / BIO =====
// Moved to js/auth-ui.js – doLogin(), bioLogin(), regNext(), doRegister(), doLogout(), renderUserData()
