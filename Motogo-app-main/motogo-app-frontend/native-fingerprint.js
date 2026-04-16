// ===== NATIVE-FINGERPRINT.JS – Cordova fingerprint-aio bridge for MotoGo24 =====
// VoltBuilder builds use Cordova plugins. This section adds support for
// cordova-plugin-fingerprint-aio when Capacitor is NOT available.
// Extracted from native-bridge.js. Must be loaded AFTER native-bridge.js.

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

    // ===== CORDOVA BIOMETRIC BUTTON =====
    window.setupBioButton = function() {
      var bs = document.getElementById('bio-section');
      if (!bs) return;

      window.Fingerprint.isAvailable(function(result) {
        var hasBioUser = !!localStorage.getItem('mg_bio_user');
        if(hasBioUser){
          bs.style.display = '';
          try { localStorage.setItem('mg_bio_enabled', '1'); } catch (e) {}
        } else {
          bs.style.display = 'none';
        }
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
      }, function() {
        if (localStorage.getItem('mg_bio_enabled') && localStorage.getItem('mg_bio_user')) {
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
        // Biometric verified — now restore real Supabase session
        if (typeof showT === 'function') showT('\ud83d\udd10', 'Biometrika', 'Ov\u011b\u0159eno \u2013 p\u0159ihla\u0161uji...');
        if (typeof _bioRestoreSession === 'function') {
          _bioRestoreSession(bioUser).then(function(sessionOk) {
            if (sessionOk) {
              if (typeof _syncLocalSession === 'function') _syncLocalSession(bioUser.user_id, bioUser.email);
              if (typeof renderUserData === 'function') renderUserData();
              setTimeout(function() { if (typeof goTo === 'function') goTo('s-home'); }, 1200);
            } else {
              if (typeof _clearBioData === 'function') _clearBioData();
              if (typeof showT === 'function') showT('\u2139\ufe0f', 'Biometrika', 'Session vypr\u0161ela \u2013 p\u0159ihla\u0161te se emailem a heslem');
            }
          });
        }
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

    // ===== CORDOVA GEOLOCATION OVERRIDES =====
    // cordova-plugin-geolocation patches navigator.geolocation with native GPS.
    // These overrides add proper error handling, longer timeouts, and permission dialogs.

    function _cordovaGetPosition(onSuccess, onError, highAccuracy) {
      if (!navigator.geolocation) { if (onError) onError('GPS nedostupné'); return; }
      navigator.geolocation.getCurrentPosition(
        onSuccess,
        function(err) {
          // If high accuracy failed, try low accuracy fallback
          if (highAccuracy && err.code !== 1) {
            navigator.geolocation.getCurrentPosition(
              onSuccess,
              function(err2) { if (onError) onError(err2); },
              { enableHighAccuracy: false, timeout: 30000, maximumAge: 60000 }
            );
          } else {
            if (onError) onError(err);
          }
        },
        { enableHighAccuracy: highAccuracy !== false, timeout: 30000, maximumAge: 0 }
      );
    }

    function _cordovaGpsError(err) {
      if (!err) return 'Poloha nedostupná';
      if (err.code === 1) return 'Přístup k poloze zamítnut';
      if (err.code === 2) return 'GPS nedostupné – zkuste to venku';
      if (err.code === 3) return 'GPS neodpovědělo – zkuste to venku';
      return 'Poloha nedostupná';
    }

    // Override sosReplFillGPS for Cordova
    window.sosReplFillGPS = function() {
      if (typeof showT === 'function') showT('\ud83d\udccd', 'Zjišťuji polohu...', '');
      _cordovaGetPosition(function(pos) {
        var lat = pos.coords.latitude;
        var lng = pos.coords.longitude;
        fetch('https://nominatim.openstreetmap.org/reverse?format=json&lat=' + lat + '&lon=' + lng + '&zoom=18&addressdetails=1')
          .then(function(r) { return r.json(); })
          .then(function(data) {
            var addr = data.address || {};
            var street = (addr.road || '') + (addr.house_number ? ' ' + addr.house_number : '');
            var city = addr.city || addr.town || addr.village || '';
            var zip = addr.postcode || '';
            var addrEl = document.getElementById('sos-repl-address');
            var cityEl = document.getElementById('sos-repl-city');
            var zipEl = document.getElementById('sos-repl-zip');
            if (addrEl) addrEl.value = street;
            if (cityEl) cityEl.value = city;
            if (zipEl) zipEl.value = zip;
            if (typeof showT === 'function') showT('\ud83d\udccd', 'Adresa doplněna', street + ', ' + city);
            if (typeof sosReplCalcDelivery === 'function') sosReplCalcDelivery();
          })
          .catch(function() { if (typeof showT === 'function') showT('\ud83d\udccd', 'GPS OK, adresu vyplňte ručně', ''); });
      }, function(err) {
        if (typeof showT === 'function') showT('\u274c', 'GPS', _cordovaGpsError(err));
      }, true);
    };

    // Override sosShareLocation for Cordova
    window.sosShareLocation = function() {
      if (typeof showT === 'function') showT('\ud83d\udccd', 'Zjišťuji polohu...', 'Čekejte prosím');

      function _sendLoc(lat, lng) {
        if (typeof apiGetMySosIncidents === 'function') {
          apiGetMySosIncidents().then(function(incidents) {
            var latest = incidents && incidents.length ? incidents[0] : null;
            if (latest && typeof apiSosShareLocation === 'function') {
              apiSosShareLocation(latest.id, lat, lng).then(function() {
                if (typeof showT === 'function') showT('\ud83d\udccd', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
              });
            } else if (typeof apiGetActiveLoan === 'function') {
              apiGetActiveLoan().then(function(loan) {
                var loanId = loan ? loan.id : null;
                if (typeof apiCreateSosIncident === 'function') {
                  apiCreateSosIncident('location_share', loanId, lat, lng, null, null).then(function() {
                    if (typeof showT === 'function') showT('\ud83d\udccd', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
                  });
                }
              });
            } else {
              if (typeof showT === 'function') showT('\ud83d\udccd', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
            }
          });
        } else {
          if (typeof showT === 'function') showT('\ud83d\udccd', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
        }
      }

      _cordovaGetPosition(function(pos) {
        _sendLoc(pos.coords.latitude, pos.coords.longitude);
      }, function(err) {
        if (typeof showT === 'function') showT('\u274c', 'GPS', _cordovaGpsError(err));
      }, true);
    };

    // Override _sosGetGPS for Cordova
    window._sosGetGPS = function() {
      return new Promise(function(resolve) {
        _cordovaGetPosition(function(pos) {
          resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude });
        }, function() {
          resolve({ lat: null, lng: null });
        }, true);
      });
    };

    // Override useMyLocation for Cordova
    window.useMyLocation = function(type) {
      var cityInputMap = { 'ship': 'ship-city', 'b-contact': 'b-contact-city', 'sos-repl': 'sos-repl-city' };
      var addrInputMap = { 'ship': 'ship-street', 'b-contact': 'b-contact-street', 'sos-repl': 'sos-repl-address' };
      var zipInputMap = { 'ship': 'ship-zip', 'b-contact': 'b-contact-zip', 'sos-repl': 'sos-repl-zip' };
      var cityEl = document.getElementById(cityInputMap[type] || '') || document.getElementById(type + '-city');
      if (cityEl) cityEl.value = 'Hledám polohu...';

      _cordovaGetPosition(function(pos) {
        var lat = pos.coords.latitude;
        var lng = pos.coords.longitude;
        if (typeof AddressAPI === 'undefined' || typeof AddressAPI.reverseGeocode !== 'function') {
          if (cityEl) cityEl.value = '';
          if (typeof showT === 'function') showT('\u26a0\ufe0f', 'Chyba', 'Reverzní geokódování nedostupné');
          return;
        }
        AddressAPI.reverseGeocode(lat, lng, function(result) {
          if (!result) {
            if (cityEl) cityEl.value = '';
            if (typeof showT === 'function') showT('\u26a0\ufe0f', 'Chyba', 'Nepodařilo se zjistit adresu');
            return;
          }
          if (cityEl) cityEl.value = result.city || '';
          var zipEl = document.getElementById(zipInputMap[type] || '') || document.getElementById(type + '-zip');
          if (zipEl && result.zip) zipEl.value = result.zip;
          var addrEl = document.getElementById(addrInputMap[type] || '') || document.getElementById(type + '-addr-input') || document.getElementById(type + '-address');
          if (addrEl) {
            var street = result.street || '';
            if (result.houseNum) street += (street ? ' ' : '') + result.houseNum;
            addrEl.value = street;
            addrEl.dataset.lat = lat;
            addrEl.dataset.lng = lng;
          }
          if (type === 'pickup' || type === 'return') { if (typeof calcDelivery === 'function') calcDelivery(type); }
          if (type === 'edit-pickup' && typeof _sosCalcPickupDelivery === 'function') { _sosCalcPickupDelivery(); }
          if (type === 'edit-return' && typeof calcEditDelivery === 'function') { calcEditDelivery(); }
          if (type === 'sos-repl' && typeof sosReplCalcDelivery === 'function') { sosReplCalcDelivery(); }
        });
      }, function(err) {
        if (cityEl) cityEl.value = '';
        if (typeof showT === 'function') showT('\u26a0\ufe0f', 'GPS', _cordovaGpsError(err));
      }, true);
    };

    // Override shareLocation for Cordova
    window.shareLocation = function() {
      if (typeof showT === 'function') showT('\ud83d\udccd', 'Zjišťuji polohu...', '');
      _cordovaGetPosition(function(pos) {
        if (typeof showT === 'function') showT('\ud83d\udccd', 'Poloha sdílena', pos.coords.latitude.toFixed(5) + ', ' + pos.coords.longitude.toFixed(5));
      }, function(err) {
        if (typeof showT === 'function') showT('\u274c', 'GPS', _cordovaGpsError(err));
      }, true);
    };

    // ===== CORDOVA NATIVE STYLES =====
    var notch = document.querySelector('.notch');
    if (notch) notch.style.display = 'none';
    var nativeCSS = document.createElement('style');
    nativeCSS.textContent =
      '.notch{display:none!important}' +
      '.phone{padding-top:env(safe-area-inset-top)!important}' +
      '.bnav{padding-bottom:env(safe-area-inset-bottom)!important}';
    document.head.appendChild(nativeCSS);

  });
})();
