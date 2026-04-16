// ===== NATIVE-BIOMETRIC.JS – Capacitor BiometricAuth bridge for MotoGo24 =====
// Biometric login (bioLogin) and biometric button setup (setupBioButton).
// Extracted from native-bridge.js. Must be loaded AFTER native-bridge.js.

(function() {
  'use strict';

  // Guard: only run on native Capacitor platform
  var Cap = window.Capacitor;
  if (!Cap || !Cap.isNativePlatform || !Cap.isNativePlatform()) return;

  var Plugins = Cap.Plugins;
  var BiometricAuth = Plugins.BiometricAuth;

  // ===== BIOMETRIC LOGIN =====
  window.bioLogin = function() {
    if (!localStorage.getItem('mg_bio_enabled')) {
      showT('\u2139\ufe0f', 'Biometrika', 'Biometrika nen\u00ed povolena');
      return;
    }
    var bioUser = null;
    try { var raw = localStorage.getItem('mg_bio_user'); if(raw) bioUser = JSON.parse(raw); } catch(e){}
    if (!bioUser || !bioUser.user_id || !bioUser.email) {
      showT('\u2139\ufe0f', 'Biometrika', 'Nejprve se p\u0159ihla\u0161te klasicky');
      return;
    }
    // DO NOT call _syncLocalSession here — only after biometric + session verification

    BiometricAuth.checkBiometry().then(function(check) {
      if (!check.isAvailable) {
        showT('\u26a0\ufe0f', 'Biometrika', 'Biometrick\u00e9 ov\u011b\u0159en\u00ed nen\u00ed dostupn\u00e9');
        return Promise.reject(new Error('_bio_unavailable_'));
      }
      return BiometricAuth.authenticate({
        reason: 'P\u0159ihl\u00e1\u0161en\u00ed do MotoGo24',
        cancelTitle: 'Zru\u0161it',
        allowDeviceCredential: true,
        androidTitle: 'MotoGo24',
        androidSubtitle: 'Ov\u011b\u0159te svou identitu',
        androidConfirmationRequired: false
      });
    }).then(function() {
      // Biometric verified — now restore real Supabase session
      showT('\ud83d\udd10', 'Biometrika', 'Ov\u011b\u0159eno \u2013 p\u0159ihla\u0161uji...');
      if (typeof _bioRestoreSession === 'function') {
        return _bioRestoreSession(bioUser);
      }
      return false;
    }).then(function(sessionOk) {
      if (sessionOk) {
        if (typeof _syncLocalSession === 'function') _syncLocalSession(bioUser.user_id, bioUser.email);
        if (typeof renderUserData === 'function') renderUserData();
        setTimeout(function() { if (typeof goTo === 'function') goTo('s-home'); }, 1200);
      } else {
        // Session expired — clear bio data and require email/password login
        if (typeof _clearBioData === 'function') _clearBioData();
        showT('\u2139\ufe0f', 'Biometrika', 'Session vypr\u0161ela \u2013 p\u0159ihla\u0161te se emailem a heslem');
      }
    }).catch(function(e) {
      if (e && e.message === '_bio_unavailable_') return;
      console.error('[bridge] bioLogin:', e);
      var msg = (e && e.message) || String(e);
      if (msg.indexOf('cancel') !== -1 || msg.indexOf('Cancel') !== -1) {
        showT('\u2139\ufe0f', 'Biometrika', 'Ov\u011b\u0159en\u00ed zru\u0161eno');
      } else {
        showT('\u2717', 'Chyba', 'Biometrika selhala');
      }
    });
  };

  // ===== BIOMETRIC BUTTON – show if device supports it AND user has logged in before =====
  window.setupBioButton = function(){
    var bs = document.getElementById('bio-section');
    if(!bs) return;
    BiometricAuth.checkBiometry().then(function(check){
      if(check && check.isAvailable){
        // Only auto-enable if user has bio credentials stored (logged in before)
        var hasBioUser = !!localStorage.getItem('mg_bio_user');
        if(hasBioUser){
          bs.style.display = '';
          try{ localStorage.setItem('mg_bio_enabled','1'); }catch(e){}
        } else {
          // Device has biometrics but user never logged in — hide button
          bs.style.display = 'none';
        }
        var icon = document.getElementById('bio-icon');
        var label = document.getElementById('bio-label');
        var sub = document.getElementById('bio-sub');
        if(icon) icon.textContent = '\ud83d\udd10';
        if(label) label.textContent = _t('auth').biometricBtn || 'Biometrick\u00e9 p\u0159ihl\u00e1\u0161en\u00ed';
        var biometryType = check.biometryType || 1;
        if(sub){
          if(biometryType === 2 || biometryType === 'FACE_AUTHENTICATION'){
            sub.textContent = 'Face ID';
          } else {
            sub.textContent = _t('auth').fingerprint || 'Otisk prstu';
          }
        }
      } else {
        bs.style.display = 'none';
      }
    }).catch(function(){
      if(localStorage.getItem('mg_bio_enabled') && localStorage.getItem('mg_bio_user')){
        bs.style.display = '';
      } else {
        bs.style.display = 'none';
      }
    });
  };

})();
