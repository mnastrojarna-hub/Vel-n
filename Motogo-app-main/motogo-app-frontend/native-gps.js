// ===== NATIVE-GPS.JS – Capacitor Geolocation bridge for MotoGo24 =====
// GPS/location functions: _nativeGetPosition, sosShareLocation, shareLocation,
// sosReplFillGPS, _sosGetGPS, useMyLocation.
// Extracted from native-bridge.js. Must be loaded AFTER native-bridge.js.

(function() {
  'use strict';

  // Guard: only run on native Capacitor platform
  var Cap = window.Capacitor;
  if (!Cap || !Cap.isNativePlatform || !Cap.isNativePlatform()) return;

  var Plugins = Cap.Plugins;
  var Geolocation = Plugins.Geolocation;

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
    showT('\ud83d\udccd', 'Zjišťuji polohu...', 'Čekejte prosím');
    Geolocation.checkPermissions().then(function(perm){
      if(perm && perm.location === 'denied'){
        _showPermDeniedDialog('Pro sdílení polohy povolte přístup k GPS v nastavení telefonu.');
        return;
      }
      return Geolocation.getCurrentPosition({ enableHighAccuracy: true, timeout: 15000 });
    }).then(function(pos) {
      if(!pos) return;
      var lat = pos.coords.latitude;
      var lng = pos.coords.longitude;
      // Send location to Supabase (same logic as ui-controller.js sosShareLocation)
      if (typeof apiGetMySosIncidents === 'function') {
        apiGetMySosIncidents().then(function(incidents) {
          var latest = incidents && incidents.length ? incidents[0] : null;
          if (latest && typeof apiSosShareLocation === 'function') {
            apiSosShareLocation(latest.id, lat, lng).then(function() {
              showT('\ud83d\udccd', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
            });
          } else if (typeof apiGetActiveLoan === 'function') {
            apiGetActiveLoan().then(function(loan) {
              var loanId = loan ? loan.id : null;
              if (typeof apiCreateSosIncident === 'function') {
                apiCreateSosIncident('location_share', loanId, lat, lng, null, null).then(function() {
                  showT('\ud83d\udccd', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
                });
              } else {
                showT('\ud83d\udccd', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
              }
            });
          } else {
            showT('\ud83d\udccd', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
          }
        });
      } else {
        showT('\ud83d\udccd', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
      }
    }).catch(function() {
      _showPermDeniedDialog('GPS není dostupné. Povolte přístup k poloze v nastavení.');
    });
  };

  window.shareLocation = function() {
    showT('\ud83d\udccd', 'Zjišťuji polohu...', '');
    _nativeGetPosition('Poloha sdílena');
  };

  // ===== GPS – sosReplFillGPS (replacement motorcycle address fill) =====
  window.sosReplFillGPS = function() {
    showT('\ud83d\udccd', 'Zjišťuji polohu...', '');
    Geolocation.checkPermissions().then(function(perm) {
      if (perm && perm.location === 'denied') {
        return Geolocation.requestPermissions().then(function(r) {
          if (r && r.location === 'denied') {
            _showPermDeniedDialog('Pro zjištění polohy povolte přístup k GPS v nastavení telefonu.');
            return null;
          }
          return Geolocation.getCurrentPosition({ enableHighAccuracy: true, timeout: 30000 });
        });
      }
      return Geolocation.getCurrentPosition({ enableHighAccuracy: true, timeout: 30000 });
    }).then(function(pos) {
      if (!pos) return;
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
          showT('\ud83d\udccd', 'Adresa doplněna', street + ', ' + city);
          if (typeof sosReplCalcDelivery === 'function') sosReplCalcDelivery();
        })
        .catch(function() { showT('\ud83d\udccd', 'GPS OK, adresu vyplňte ručně', ''); });
    }).catch(function() {
      // Fallback: try low accuracy
      Geolocation.getCurrentPosition({ enableHighAccuracy: false, timeout: 30000 }).then(function(pos) {
        if (!pos) return;
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
            showT('\ud83d\udccd', 'Adresa doplněna', street + ', ' + city);
            if (typeof sosReplCalcDelivery === 'function') sosReplCalcDelivery();
          })
          .catch(function() { showT('\ud83d\udccd', 'GPS OK, adresu vyplňte ručně', ''); });
      }).catch(function() {
        _showPermDeniedDialog('GPS není dostupné. Povolte přístup k poloze v nastavení.');
      });
    });
  };

  // ===== GPS – _sosGetGPS (internal SOS GPS) =====
  window._sosGetGPS = function() {
    return Geolocation.getCurrentPosition({ enableHighAccuracy: true, timeout: 30000 })
      .then(function(pos) {
        return { lat: pos.coords.latitude, lng: pos.coords.longitude };
      })
      .catch(function() {
        return Geolocation.getCurrentPosition({ enableHighAccuracy: false, timeout: 30000 })
          .then(function(pos) {
            return { lat: pos.coords.latitude, lng: pos.coords.longitude };
          })
          .catch(function() {
            return { lat: null, lng: null };
          });
      });
  };

  // ===== GPS – useMyLocation (address auto-fill for checkout/SOS replacement) =====
  var _origUseMyLocation = window.useMyLocation;
  window.useMyLocation = function(type) {
    var cityInputMap = { 'ship': 'ship-city', 'b-contact': 'b-contact-city', 'sos-repl': 'sos-repl-city' };
    var cityEl = document.getElementById(cityInputMap[type] || '') || document.getElementById(type + '-city');
    if (cityEl) cityEl.value = 'Hledám polohu...';

    Geolocation.checkPermissions().then(function(perm) {
      if (perm && perm.location === 'denied') {
        return Geolocation.requestPermissions().then(function(r) {
          if (r && r.location === 'denied') {
            if (cityEl) cityEl.value = '';
            _showPermDeniedDialog('Pro zjištění polohy povolte přístup k GPS v nastavení telefonu.');
            return null;
          }
          return Geolocation.getCurrentPosition({ enableHighAccuracy: true, timeout: 30000 });
        });
      }
      return Geolocation.getCurrentPosition({ enableHighAccuracy: true, timeout: 30000 });
    }).then(function(pos) {
      if (!pos) return;
      var lat = pos.coords.latitude;
      var lng = pos.coords.longitude;
      if (typeof AddressAPI === 'undefined' || typeof AddressAPI.reverseGeocode !== 'function') {
        if (cityEl) cityEl.value = '';
        showT('\u26a0\ufe0f', 'Chyba', 'Reverzní geokódování nedostupné');
        return;
      }
      var addrInputMap = { 'ship': 'ship-street', 'b-contact': 'b-contact-street', 'sos-repl': 'sos-repl-address' };
      var zipInputMap = { 'ship': 'ship-zip', 'b-contact': 'b-contact-zip', 'sos-repl': 'sos-repl-zip' };
      AddressAPI.reverseGeocode(lat, lng, function(result) {
        if (!result) {
          if (cityEl) cityEl.value = '';
          showT('\u26a0\ufe0f', 'Chyba', 'Nepodařilo se zjistit adresu');
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
    }).catch(function() {
      if (cityEl) cityEl.value = '';
      showT('\u26a0\ufe0f', 'GPS', 'Poloha nedostupná');
    });
  };

})();
