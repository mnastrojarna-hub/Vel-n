// ===== NATIVE-BRIDGE.JS – Capacitor native bridge for MotoGo24 =====
// Loaded before app.js. Overrides browser-simulated functions with native
// Capacitor plugin equivalents. In browser, the guard exits immediately
// so original implementations remain untouched.

(function() {
  'use strict';

  // Guard: only run on native Capacitor platform
  var Cap = window.Capacitor;
  if (!Cap || !Cap.isNativePlatform || !Cap.isNativePlatform()) return;

  var Plugins = Cap.Plugins;
  var StatusBar = Plugins.StatusBar;
  var AppPlugin = Plugins.App;
  var Haptics = Plugins.Haptics;
  var Camera = Plugins.Camera;
  var Geolocation = Plugins.Geolocation;
  var BiometricAuth = Plugins.BiometricAuth;

  // ===== HIDE SIMULATED NOTCH – device has real one =====
  var notch = document.querySelector('.notch');
  if (notch) notch.style.display = 'none';

  // ===== SAFE AREA + NATIVE STYLES =====
  var nativeCSS = document.createElement('style');
  nativeCSS.textContent =
    '.notch{display:none!important}' +
    '.phone{padding-top:env(safe-area-inset-top)!important}' +
    '.bnav{padding-bottom:env(safe-area-inset-bottom)!important}' +
    '.perm-overlay{padding-top:env(safe-area-inset-top)}';
  document.head.appendChild(nativeCSS);

  // ===== STATUS BAR =====
  try {
    StatusBar.setBackgroundColor({ color: '#000000' });
    StatusBar.setStyle({ style: 'DARK' });
  } catch (e) { console.warn('[bridge] StatusBar init:', e); }

  // ===== HARDWARE BACK BUTTON =====
  AppPlugin.addListener('backButton', function() {
    // Use existing histBack if there is navigation history
    if (typeof navStack !== 'undefined' && navStack.length > 1) {
      if (typeof histBack === 'function') histBack();
    } else if(typeof cur !== 'undefined' && cur !== 's-home') {
      if(typeof goTo === 'function') goTo('s-home');
    }
    // Never exit app - user must use system gesture
  });

  // ===== HAPTIC TOAST =====
  var _showT = window.showT;
  window.showT = function(icon, title, sub) {
    try { Haptics.impact({ style: 'LIGHT' }); } catch (e) {}
    if (_showT) _showT(icon, title, sub);
  };

  // ===== BIOMETRIC LOGIN =====
  window.bioLogin = function() {
    if (!localStorage.getItem('mg_bio_enabled')) {
      showT('\u2139\ufe0f', 'Biometrika', 'Biometrika nen\u00ed povolena');
      return;
    }
    // Restore session from stored biometric credentials
    var bioUser = null;
    try { var raw = localStorage.getItem('mg_bio_user'); if(raw) bioUser = JSON.parse(raw); } catch(e){}
    if (!bioUser || !bioUser.user_id || !bioUser.email) {
      showT('\u2139\ufe0f', 'Biometrika', 'Nejprve se přihlaste klasicky');
      return;
    }
    if (typeof _syncLocalSession === 'function') _syncLocalSession(bioUser.user_id, bioUser.email);

    BiometricAuth.checkBiometry().then(function(check) {
      if (!check.isAvailable) {
        showT('\u26a0\ufe0f', 'Biometrika', 'Biometrick\u00e9 ov\u011b\u0159en\u00ed nen\u00ed dostupn\u00e9');
        return;
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
      showT('\ud83d\udd10', 'Biometrika', 'Ov\u011b\u0159eno \u2013 p\u0159ihla\u0161uji...');
      if (typeof renderUserData === 'function') renderUserData();
      setTimeout(function() { if (typeof goTo === 'function') goTo('s-home'); }, 1200);
    }).catch(function(e) {
      console.error('[bridge] bioLogin:', e);
      var msg = (e && e.message) || String(e);
      if (msg.indexOf('cancel') !== -1 || msg.indexOf('Cancel') !== -1) {
        showT('\u2139\ufe0f', 'Biometrika', 'Ov\u011b\u0159en\u00ed zru\u0161eno');
      } else {
        showT('\u2717', 'Chyba', 'Biometrika selhala');
      }
    });
  };

  // ===== GPS – with permission check + settings redirect =====
  function _nativeGetPosition(successMsg){
    Geolocation.checkPermissions().then(function(perm){
      if(perm && perm.location === 'denied'){
        _showPermDeniedDialog('Pro sdílení polohy povolte přístup k GPS v nastavení telefonu.');
        return;
      }
      return Geolocation.getCurrentPosition({ enableHighAccuracy: true, timeout: 15000 });
    }).then(function(pos) {
      if(!pos) return;
      var lat = pos.coords.latitude.toFixed(5);
      var lng = pos.coords.longitude.toFixed(5);
      showT('\ud83d\udccd', successMsg || 'Poloha sdílena', lat + ', ' + lng);
    }).catch(function() {
      _showPermDeniedDialog('GPS není dostupné. Povolte přístup k poloze v nastavení.');
    });
  }

  window.sosShareLocation = function() {
    showT('\ud83d\udccd', 'Zjišťuji polohu...', '');
    _nativeGetPosition('Poloha sdílena MotoGo24');
  };

  window.shareLocation = function() {
    showT('\ud83d\udccd', 'Zjišťuji polohu...', '');
    _nativeGetPosition('Poloha sdílena');
  };

  // ===== SCANNER CAMERA – request native camera permission before getUserMedia =====
  var _origStartCamera = (typeof DocScanner !== 'undefined') ? DocScanner.startCamera : null;
  var _d = (typeof CamDebug!=='undefined') ? CamDebug.log.bind(CamDebug) : function(){};
  if (_origStartCamera) {
    DocScanner.startCamera = function(videoEl, overlayEl) {
      _d('BRIDGE','startCamera wrapper entered');
      // Guard: if Camera plugin is broken (debug APK / unsigned build), skip native perm request
      if (!Camera || typeof Camera.requestPermissions !== 'function') {
        _d('BRIDGE','Camera plugin MISSING – skip native perm, fallback to web');
        return _origStartCamera.call(DocScanner, videoEl, overlayEl);
      }
      _d('BRIDGE','calling Camera.requestPermissions({camera})...');
      return Camera.requestPermissions({ permissions: ['camera'] })
        .then(function(r) {
          _d('BRIDGE','requestPermissions result', r);
          if (r && r.camera === 'denied') {
            _d('BRIDGE','DENIED by user');
            _showPermDeniedDialog('Pro skenování dokladů povolte přístup k fotoaparátu v nastavení telefonu.');
            return Promise.reject(new Error('Camera permission denied'));
          }
          _d('BRIDGE','permission OK, calling original startCamera...');
          return _origStartCamera.call(DocScanner, videoEl, overlayEl);
        })
        .catch(function(e) {
          if (e && e.message === 'Camera permission denied') throw e;
          // Plugin call failed (debug build, missing impl) – fall through to web API
          _d('BRIDGE','requestPermissions THREW, fallback to web', e);
          return _origStartCamera.call(DocScanner, videoEl, overlayEl);
        });
    };
  } else {
    _d('BRIDGE','DocScanner.startCamera not found – wrapper NOT installed');
  }

  // ===== CAMERA – Document capture (replaces file input) =====
  window.handleDocCap = function() {
    Camera.getPhoto({
      quality: 85,
      resultType: 'dataUrl',
      source: 'CAMERA',
      correctOrientation: true,
      width: 1200,
      height: 1600
    }).then(function(photo) {
      if (photo && photo.dataUrl) {
        if (typeof docCaps !== 'undefined' && typeof docType !== 'undefined') {
          docCaps[docType] = photo.dataUrl;
        }
        if (typeof renderDocs === 'function') renderDocs();
        showT('\ud83d\udccb', 'Doklad naskenov\u00e1n', 'Ulo\u017eeno');
      }
    }).catch(function(err) {
      var msg = (err && err.message) || '';
      if (msg.indexOf('cancel') !== -1 || msg.indexOf('Cancel') !== -1) return;
      if (msg.indexOf('denied') !== -1 || msg.indexOf('permission') !== -1){
        _showPermDeniedDialog('Pro focení dokladů povolte přístup k fotoaparátu v nastavení telefonu.');
      } else {
        showT('\u274c', 'Fotoaparát', 'Nepodařilo se pořídit snímek');
      }
    });
  };

  // ===== GALLERY – Document upload from photos (request full access) =====
  window.handleDocUp = function() {
    Camera.requestPermissions({ permissions: ['photos'] }).then(function(r) {
      if (r && r.photos === 'limited') {
        _showPermDeniedDialog('Přístup pouze k vybraným fotkám. Pro plný přístup ke galerii povolte „Všechny fotky" v nastavení telefonu.');
        return;
      }
      if (r && r.photos === 'denied') {
        _showPermDeniedDialog('Pro výběr fotek povolte přístup ke galerii v nastavení telefonu.');
        return;
      }
      return Camera.getPhoto({
        quality: 85,
        resultType: 'dataUrl',
        source: 'PHOTOS',
        correctOrientation: true,
        width: 1200,
        height: 1600
      });
    }).then(function(photo) {
      if (photo && photo.dataUrl) {
        if (typeof docCaps !== 'undefined' && typeof docType !== 'undefined') {
          docCaps[docType] = photo.dataUrl;
        }
        if (typeof renderDocs === 'function') renderDocs();
        showT('\ud83d\udccb', 'Doklad nahrán', 'Uloženo');
      }
    }).catch(function(err) {
      if (!err) return;
      var msg = (err && err.message) || '';
      if (msg.indexOf('cancel') !== -1 || msg.indexOf('Cancel') !== -1) return;
      if (msg.indexOf('denied') !== -1 || msg.indexOf('permission') !== -1){
        _showPermDeniedDialog('Pro výběr fotek povolte přístup ke galerii v nastavení telefonu.');
      } else {
        showT('\u274c', 'Galerie', 'Nepodařilo se vybrat snímek');
      }
    });
  };

  // ===== OPEN DEVICE SETTINGS =====
  function _openAppSettings(){
    try {
      if(Plugins.NativeSettings && Plugins.NativeSettings.openAndroid){
        Plugins.NativeSettings.openAndroid({option:'application_details'});
      } else if(AppPlugin && AppPlugin.openUrl){
        AppPlugin.openUrl({url:'app-settings:'});
      } else {
        showT('⚙️','Nastavení','Otevřete Nastavení > Aplikace > MotoGo24 > Oprávnění');
      }
    } catch(e){
      showT('⚙️','Nastavení','Otevřete Nastavení > Aplikace > MotoGo24 > Oprávnění');
    }
  }

  // ===== PERMISSION CHECK & REQUEST =====
  function _checkAndRequestPermission(type, requestFn, deniedMsg){
    return requestFn().then(function(result){
      // Check if permission was actually granted
      var status = result && (result[type] || result.location || result.camera || result.photos);
      if(status === 'denied' || status === 'prompt-with-rationale'){
        // Permission permanently denied – navigate to settings
        _showPermDeniedDialog(deniedMsg);
        return Promise.reject(new Error('denied'));
      }
      return result;
    });
  }

  function _showPermDeniedDialog(msg){
    var ov = document.getElementById('perm-denied-overlay');
    if(!ov){
      ov = document.createElement('div');
      ov.id = 'perm-denied-overlay';
      ov.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:99999;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;padding:20px;';
      document.querySelector('.phone').appendChild(ov);
    }
    ov.innerHTML = '<div style="background:#fff;border-radius:18px;padding:24px;max-width:300px;width:100%;text-align:center;">' +
      '<div style="font-size:48px;margin-bottom:12px;">⚙️</div>' +
      '<div style="font-size:16px;font-weight:900;margin-bottom:6px;">Oprávnění zamítnuto</div>' +
      '<div style="font-size:13px;color:var(--g400);margin-bottom:16px;line-height:1.5;">' + (msg || 'Pro tuto funkci je potřeba oprávnění. Povolte ho v nastavení telefonu.') + '</div>' +
      '<button onclick="nativeOpenSettings();document.getElementById(\'perm-denied-overlay\').style.display=\'none\'" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:12px;padding:14px;font-family:var(--font);font-size:14px;font-weight:700;cursor:pointer;margin-bottom:8px;">Otevřít nastavení</button>' +
      '<button onclick="document.getElementById(\'perm-denied-overlay\').style.display=\'none\'" style="width:100%;background:var(--g100);color:var(--black);border:none;border-radius:12px;padding:14px;font-family:var(--font);font-size:13px;font-weight:600;cursor:pointer;">Později</button>' +
      '</div>';
    ov.style.display = 'flex';
  }

  // Expose to global scope for onclick
  window.nativeOpenSettings = _openAppSettings;

  // ===== PERMISSIONS – request real native permissions =====
  window.grantPerms = function() {
    var promises = [];
    var denied = [];

    // Camera + photos (request full access)
    try {
      promises.push(
        Camera.requestPermissions({ permissions: ['camera', 'photos'] })
          .then(function(r){
            if(r && r.camera==='denied') denied.push('fotoaparát');
            if(r && (r.photos==='denied' || r.photos==='limited')) denied.push('galerie (plný přístup)');
            return r;
          })
          .catch(function(){ return null; })
      );
    } catch (e) { promises.push(Promise.resolve()); }

    // Geolocation
    try {
      promises.push(
        Geolocation.requestPermissions()
          .then(function(r){ if(r && r.location==='denied') denied.push('poloha'); return r; })
          .catch(function(){ return null; })
      );
    } catch (e) { promises.push(Promise.resolve()); }

    // Microphone (via getUserMedia trigger)
    promises.push(
      navigator.mediaDevices.getUserMedia({ audio: true })
        .then(function(s) { s.getTracks().forEach(function(t) { t.stop(); }); })
        .catch(function() { denied.push('mikrofon'); })
    );

    Promise.all(promises).then(function() {
      try { localStorage.setItem('mg_perms', 'granted'); } catch (e) {}
      var ov = document.getElementById('perm-overlay');
      if (ov) ov.style.display = 'none';
      if(denied.length > 0){
        _showPermDeniedDialog('Následující oprávnění nebyla povolena: ' + denied.join(', ') + '. Pro plnou funkčnost je povolte v nastavení.');
      } else {
        showT('\u2713', 'Oprávnění povolena', 'Biometrika, poloha, fotoaparát, mikrofon');
      }
    });
  };

  // ===== MICROPHONE – ensure native permission with settings redirect =====
  var _aiToggleMic = window.aiToggleMic;
  window.aiToggleMic = function() {
    navigator.mediaDevices.getUserMedia({ audio: true })
      .then(function(stream) {
        stream.getTracks().forEach(function(t) { t.stop(); });
        if (_aiToggleMic) _aiToggleMic();
      })
      .catch(function() {
        _showPermDeniedDialog('Pro hlasové příkazy povolte přístup k mikrofonu v nastavení telefonu.');
      });
  };

  // ===== BIOMETRIC BUTTON – always show if device supports it =====
  window.setupBioButton = function(){
    var bs = document.getElementById('bio-section');
    if(!bs) return;
    BiometricAuth.checkBiometry().then(function(check){
      if(check && check.isAvailable){
        bs.style.display = '';
        var icon = document.getElementById('bio-icon');
        var label = document.getElementById('bio-label');
        var sub = document.getElementById('bio-sub');
        if(icon) icon.textContent = '\ud83d\udd10';
        if(label) label.textContent = _t('auth').biometricBtn || 'Biometrické přihlášení';
        var biometryType = check.biometryType || 1;
        if(sub){
          if(biometryType === 2 || biometryType === 'FACE_AUTHENTICATION'){
            sub.textContent = 'Face ID';
          } else {
            sub.textContent = _t('auth').fingerprint || 'Otisk prstu';
          }
        }
        // Auto-enable for native
        try{ localStorage.setItem('mg_bio_enabled','1'); }catch(e){}
      } else {
        bs.style.display = 'none';
      }
    }).catch(function(){
      // Fallback – show if previously enabled
      if(localStorage.getItem('mg_bio_enabled')){
        bs.style.display = '';
      } else {
        bs.style.display = 'none';
      }
    });
  };

  console.log('[MotoGo24] Native bridge initialized \u2713');
})();

// ===== CORDOVA FINGERPRINT BRIDGE =====
// VoltBuilder builds use Cordova plugins. This section adds support for
// cordova-plugin-fingerprint-aio when Capacitor is NOT available.
(function() {
  'use strict';

  // Skip if Capacitor already handled everything
  var Cap = window.Capacitor;
  if (Cap && Cap.isNativePlatform && Cap.isNativePlatform()) return;

  // Check for Cordova fingerprint plugin
  function _hasCordovaFingerprint() {
    return !!(window.Fingerprint);
  }

  // Check if running inside Cordova webview
  function _isCordova() {
    return !!(window.cordova);
  }

  // Wait for deviceready if Cordova is present
  function _onDeviceReady(cb) {
    if (!_isCordova()) { cb(); return; }
    if (document.readyState === 'complete') {
      // deviceready may have already fired
      setTimeout(cb, 100);
    } else {
      document.addEventListener('deviceready', cb, false);
    }
  }

  _onDeviceReady(function() {
    if (!_hasCordovaFingerprint()) return;

    console.log('[MotoGo24] Cordova fingerprint plugin detected');

    // ===== CORDOVA BIOMETRIC BUTTON =====
    window.setupBioButton = function() {
      var bs = document.getElementById('bio-section');
      if (!bs) return;

      window.Fingerprint.isAvailable(function(result) {
        // Biometrics available
        bs.style.display = '';
        var icon = document.getElementById('bio-icon');
        var label = document.getElementById('bio-label');
        var sub = document.getElementById('bio-sub');
        if (icon) icon.textContent = '\ud83d\udd10';
        var t = (typeof _t === 'function') ? _t('auth') : {};
        if (label) label.textContent = t.biometricBtn || 'Biometrick\u00e9 p\u0159ihl\u00e1\u0161en\u00ed';
        if (sub) {
          if (result === 'face') {
            sub.textContent = 'Face ID';
          } else {
            sub.textContent = t.fingerprint || 'Otisk prstu';
          }
        }
        try { localStorage.setItem('mg_bio_enabled', '1'); } catch (e) {}
      }, function() {
        // Not available – show if previously enabled
        if (localStorage.getItem('mg_bio_enabled')) {
          bs.style.display = '';
        } else {
          bs.style.display = 'none';
        }
      });
    };

    // ===== CORDOVA BIOMETRIC LOGIN =====
    window.bioLogin = function() {
      if (!localStorage.getItem('mg_bio_enabled')) {
        if (typeof showT === 'function') showT('\u2139\ufe0f', 'Biometrika', 'Biometrika nen\u00ed povolena');
        return;
      }
      var bioUser = null;
      try {
        var raw = localStorage.getItem('mg_bio_user');
        if (raw) bioUser = JSON.parse(raw);
      } catch (e) {}
      if (!bioUser || !bioUser.user_id || !bioUser.email) {
        if (typeof showT === 'function') showT('\u2139\ufe0f', 'Biometrika', 'Nejprve se p\u0159ihla\u0161te klasicky');
        return;
      }

      window.Fingerprint.show({
        title: 'MotoGo24',
        subtitle: 'Ov\u011b\u0159te svou identitu',
        description: 'P\u0159ihl\u00e1\u0161en\u00ed do MotoGo24',
        fallbackButtonTitle: 'Pou\u017e\u00edt heslo',
        disableBackup: false
      }, function() {
        // Success
        if (typeof _syncLocalSession === 'function') {
          _syncLocalSession(bioUser.user_id, bioUser.email);
        }
        if (typeof showT === 'function') showT('\ud83d\udd10', 'Biometrika', 'Ov\u011b\u0159eno \u2013 p\u0159ihla\u0161uji...');
        if (typeof renderUserData === 'function') renderUserData();
        setTimeout(function() {
          if (typeof goTo === 'function') goTo('s-home');
        }, 1200);
      }, function(err) {
        var msg = (err && err.message) || String(err || '');
        if (msg.indexOf('cancel') !== -1 || msg.indexOf('Cancel') !== -1) {
          if (typeof showT === 'function') showT('\u2139\ufe0f', 'Biometrika', 'Ov\u011b\u0159en\u00ed zru\u0161eno');
        } else {
          if (typeof showT === 'function') showT('\u2717', 'Chyba', 'Biometrika selhala');
        }
      });
    };

    // Re-run setupBioButton if app already initialized
    if (typeof setupBioButton === 'function') {
      setTimeout(setupBioButton, 200);
    }

    // ===== CORDOVA NATIVE STYLES =====
    var notch = document.querySelector('.notch');
    if (notch) notch.style.display = 'none';
    var nativeCSS = document.createElement('style');
    nativeCSS.textContent =
      '.notch{display:none!important}' +
      '.phone{padding-top:env(safe-area-inset-top)!important}' +
      '.bnav{padding-bottom:env(safe-area-inset-bottom)!important}';
    document.head.appendChild(nativeCSS);

    console.log('[MotoGo24] Cordova fingerprint bridge initialized \u2713');
  });
})();
