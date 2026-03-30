// ===== NATIVE-BRIDGE.JS – Capacitor native bridge for MotoGo24 =====
// Loaded before app.js. Overrides browser-simulated functions with native
// Capacitor plugin equivalents. In browser, the guard exits immediately
// so original implementations remain untouched.
//
// Split into 4 files (load order matters):
//   1. native-bridge.js      — init, notch, status bar, back button, haptic, camera, permissions, notifications, polling
//   2. native-biometric.js   — bioLogin, setupBioButton (Capacitor BiometricAuth)
//   3. native-gps.js         — GPS/location functions (Capacitor Geolocation)
//   4. native-fingerprint.js — Cordova fingerprint-aio bridge (VoltBuilder builds)

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
    // Block back when Stripe checkout is open — prevent double payment
    if(typeof _stripeCheckoutOpened!=='undefined' && _stripeCheckoutOpened && typeof cur!=='undefined' && (cur==='s-payment'||cur==='s-sos-payment')){
      if(typeof showT==='function') showT('⚠️','Platba probíhá','Vyčkejte na dokončení platby');
      if(typeof _checkPaymentAfterStripe==='function') _checkPaymentAfterStripe();
      return;
    }
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
  var Geolocation = Plugins.Geolocation;
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

    // Notifications (Capacitor LocalNotifications)
    if(LocalNotif){
      promises.push(
        LocalNotif.requestPermissions()
          .then(function(r){
            if(r && r.display === 'denied') denied.push('oznámení');
            return r;
          })
          .catch(function(){ return null; })
      );
    }

    Promise.all(promises).then(function() {
      try { localStorage.setItem('mg_perms', 'granted'); } catch (e) {}
      var ov = document.getElementById('perm-overlay');
      if (ov) ov.style.display = 'none';
      if(denied.length > 0){
        _showPermDeniedDialog('Následující oprávnění nebyla povolena: ' + denied.join(', ') + '. Pro plnou funkčnost je povolte v nastavení.');
      } else {
        showT('\u2713', 'Oprávnění povolena', 'Biometrika, poloha, fotoaparát, mikrofon, oznámení');
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

  // ===== CAPACITOR LOCAL NOTIFICATIONS (replaces Cordova) =====
  var LocalNotif = Plugins.LocalNotifications;
  if(LocalNotif){
    // Override showMsgNotification for native notifications
    var _origShowMsgNotif = window.showMsgNotification;
    window.showMsgNotification = function(msg){
      // Always show fullscreen DOM overlay (foreground)
      if(typeof showFullScreenMessage === 'function'){
        var icon = (typeof _msgIcon === 'function') ? _msgIcon(msg.type) : '';
        showFullScreenMessage(msg.title || 'Zpráva z Moto Go', msg.message || '', icon);
      }
      // Also fire native local notification (works in background)
      try {
        LocalNotif.schedule({ notifications: [{
          id: Date.now() % 2147483647,
          title: msg.title || 'Zpráva z Moto Go',
          body: msg.message || '',
          smallIcon: 'res://icon',
          largeIcon: 'res://icon',
          sound: 'default'
        }]}).catch(function(){});
      } catch(e){}
      if(typeof updateMsgBadge === 'function') updateMsgBadge();
    };
    // Request permission (shown again if not granted during initial permissions flow)
    try {
      LocalNotif.checkPermissions().then(function(r){
        if(r && r.display !== 'granted'){
          LocalNotif.requestPermissions().catch(function(){});
        }
      }).catch(function(){ LocalNotif.requestPermissions().catch(function(){}); });
    } catch(e){}
  }

  // ===== MESSAGE POLLING (Supabase realtime unreliable in native background) =====
  var _lastMsgTs = null;
  var _lastSosTs = null;
  var _lastThreadMsgTs = null;
  var _msgPollTimer = null;
  function _pollMessages(){
    if(!window.supabase) return;
    var uid = null;
    try { uid = localStorage.getItem('mg_user_id'); } catch(e){}
    if(!uid) return;

    // 1. Poll admin_messages (notifications)
    var q = window.supabase.from('admin_messages').select('*')
      .eq('user_id', uid).eq('read', false)
      .order('created_at', {ascending:false}).limit(5);
    q.then(function(r){
      if(!r.data || r.data.length === 0) return;
      r.data.forEach(function(m){
        var ts = m.created_at || '';
        if(_lastMsgTs && ts <= _lastMsgTs) return;
        _lastMsgTs = ts;
        if(typeof window.showMsgNotification === 'function'){
          window.showMsgNotification(m);
        }
      });
    }).catch(function(){});

    // 2. Poll SOS incidents for status changes
    window.supabase.from('sos_incidents').select('id,status,type,title,updated_at')
      .eq('user_id', uid)
      .in('status', ['acknowledged','in_progress','resolved'])
      .order('updated_at', {ascending:false}).limit(3)
      .then(function(r){
        if(!r.data || r.data.length === 0) return;
        r.data.forEach(function(s){
          var ts = s.updated_at || '';
          if(_lastSosTs && ts <= _lastSosTs) return;
          _lastSosTs = ts;
          if(typeof window._showSosStatusNotification === 'function'){
            window._showSosStatusNotification(s);
          }
        });
      }).catch(function(){});

    // 3. Poll thread messages (new admin replies in chat)
    window.supabase.from('message_threads').select('id,subject,messages(id,content,direction,read_at,created_at)')
      .eq('customer_id', uid)
      .order('last_message_at', {ascending:false}).limit(5)
      .then(function(r){
        if(!r.data) return;
        r.data.forEach(function(t){
          var msgs = (t.messages || []).filter(function(m){ return m.direction === 'admin' && !m.read_at; });
          msgs.forEach(function(m){
            var ts = m.created_at || '';
            if(_lastThreadMsgTs && ts <= _lastThreadMsgTs) return;
            _lastThreadMsgTs = ts;
            if(typeof window.showMsgNotification === 'function'){
              window.showMsgNotification({
                title: t.subject || 'Zpráva z MotoGo24',
                message: m.content || '',
                type: (t.subject && t.subject.indexOf('SOS:') === 0) ? 'sos_response' : 'info'
              });
            }
          });
        });
      }).catch(function(){});
  }
  function _startMsgPolling(){
    if(_msgPollTimer) clearInterval(_msgPollTimer);
    // Poll every 30s
    _msgPollTimer = setInterval(_pollMessages, 30000);
    // Also poll immediately on app resume
    _pollMessages();
  }

  // Start polling when app comes to foreground
  AppPlugin.addListener('appStateChange', function(state){
    if(state && state.isActive){
      _pollMessages();
      // Also re-check for pending fullscreen messages
      if(typeof updateMsgBadge === 'function') updateMsgBadge();
      // Check Stripe payment status after returning from payment gateway
      if(typeof _stripeCheckoutOpened!=='undefined' && _stripeCheckoutOpened && typeof _checkPaymentAfterStripe==='function'){
        _checkPaymentAfterStripe();
      }
    }
  });

  // Start polling after short delay (wait for supabase init)
  setTimeout(_startMsgPolling, 5000);

})();
