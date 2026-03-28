// ===== CART-ADDRESS-GEO.JS – GPS geolocation + selectAddr =====
// Depends on: AddressAPI (address-api.js), calcDelivery (cart-booking-price.js)

function useMyLocation(type){
  if(!navigator.geolocation){showT('\u26a0\ufe0f','GPS','Geolokace není k dispozici');return;}
  var addrInputMap={'ship':'ship-street','b-contact':'b-contact-street','sos-repl':'sos-repl-address'};
  var cityInputMap={'ship':'ship-city','b-contact':'b-contact-city','sos-repl':'sos-repl-city'};
  var zipInputMap={'ship':'ship-zip','b-contact':'b-contact-zip','sos-repl':'sos-repl-zip'};
  var cityEl=document.getElementById(cityInputMap[type]||'')||document.getElementById(type+'-city');
  if(cityEl) cityEl.value='Hledám polohu...';

  function _fillFromResult(result, lat, lng){
    if(!result){
      if(cityEl) cityEl.value='';
      showT('\u26a0\ufe0f','Chyba','Nepodařilo se zjistit adresu');return;
    }
    if(cityEl) cityEl.value=result.city||'';
    var zipEl=document.getElementById(zipInputMap[type]||'')||document.getElementById(type+'-zip');
    if(zipEl && result.zip) zipEl.value=result.zip;
    var addrEl=document.getElementById(addrInputMap[type]||'')||document.getElementById(type+'-addr-input')||document.getElementById(type+'-address');
    if(addrEl){
      var street=result.street||'';
      if(result.houseNum) street+=(street?' ':'')+result.houseNum;
      addrEl.value=street;addrEl.dataset.lat=lat;addrEl.dataset.lng=lng;
    }
    if(type==='pickup'||type==='return'){calcDelivery(type);}
    if(type==='edit-pickup'&&typeof _sosCalcPickupDelivery==='function'){_sosCalcPickupDelivery();}
    if(type==='edit-return'&&typeof calcEditDelivery==='function'){calcEditDelivery();}
    if(type==='sos-repl'&&typeof sosReplCalcDelivery==='function'){sosReplCalcDelivery();}
    _showAddrConfirm(type);
  }

  function _geocodePos(pos){
    var lat=pos.coords.latitude;var lng=pos.coords.longitude;
    if(typeof AddressAPI==='undefined' || typeof AddressAPI.reverseGeocode!=='function'){
      if(cityEl) cityEl.value='';
      showT('\u26a0\ufe0f','Chyba','Reverzní geokódování nedostupné');return;
    }
    AddressAPI.reverseGeocode(lat, lng, function(result){ _fillFromResult(result, lat, lng); });
  }

  navigator.geolocation.getCurrentPosition(_geocodePos, function(err){
    if(err.code===1){
      if(cityEl) cityEl.value='';showT('\u26a0\ufe0f','GPS','Poloha zamítnuta');return;
    }
    navigator.geolocation.getCurrentPosition(_geocodePos, function(err2){
      if(cityEl) cityEl.value='';
      var msg='Poloha zamítnuta';
      if(err2.code===2) msg='Poloha nedostupná – zkuste to venku';
      if(err2.code===3) msg='GPS neodpovědělo – zkuste to venku';
      showT('\u26a0\ufe0f','GPS',msg);
    }, {enableHighAccuracy:false, timeout:30000, maximumAge:60000});
  }, {enableHighAccuracy:true, timeout:30000, maximumAge:60000});
}

// ===== MAP PICKER – Fullscreen map with crosshair =====
// Uses CARTO tiles (no referrer required, works from file:// and Capacitor)
// Reverse geocode via Nominatim (no API key needed)
var _mapPickerType = null;
var _mapPickerCenter = null;
var _mapRgeoTimer = null;

function _mapReverseGeocode(lat, lng, callback){
  fetch('https://nominatim.openstreetmap.org/reverse?lat='+lat+'&lon='+lng+'&format=json&addressdetails=1&accept-language=cs&zoom=18')
    .then(function(r){ return r.json(); })
    .then(function(data){
      if(!data || !data.address){ callback(null); return; }
      var a = data.address;
      callback({
        street: a.road || a.pedestrian || a.hamlet || '',
        houseNum: a.house_number || '',
        city: a.city || a.town || a.village || a.municipality || '',
        zip: a.postcode || '',
        lat: lat, lng: lng
      });
    }).catch(function(){ callback(null); });
}

function openMapPicker(type){
  _mapPickerType = type;
  // Remove old overlay completely to avoid stale state
  var old = document.getElementById('map-picker-overlay');
  if(old) old.remove();
  // Hide app header banner
  var banner = document.getElementById('header-banner');
  if(banner) banner.style.display = 'none';

  var overlay = document.createElement('div');
  overlay.id = 'map-picker-overlay';
  overlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:99999;background:#fff;';
  overlay.innerHTML =
    '<div style="position:absolute;top:0;left:0;right:0;z-index:100001;display:flex;align-items:center;justify-content:space-between;padding:14px 16px;background:#fff;box-shadow:0 2px 12px rgba(0,0,0,.15);gap:10px;">' +
      '<button type="button" onclick="closeMapPicker()" style="background:none;border:none;font-size:22px;cursor:pointer;padding:6px 10px;color:#333;flex-shrink:0;">\u2715</button>' +
      '<span style="font-size:15px;font-weight:800;color:#1a2e22;flex:1;text-align:center;">Vyberte m\u00edsto na map\u011b</span>' +
      '<button type="button" onclick="confirmMapPicker()" style="background:#1a8a18;color:#fff;border:none;border-radius:10px;padding:10px 20px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;flex-shrink:0;box-shadow:0 2px 8px rgba(26,138,24,.3);">Potvrdit</button>' +
    '</div>' +
    '<iframe id="map-picker-iframe" style="width:100%;height:100%;border:none;" src=""></iframe>' +
    '<div style="position:absolute;top:50%;left:50%;transform:translate(-50%,-100%);z-index:100000;pointer-events:none;font-size:36px;text-shadow:0 2px 6px rgba(0,0,0,.3);line-height:1;">\ud83d\udccd</div>' +
    '<div id="map-picker-addr" style="position:absolute;bottom:24px;left:16px;right:16px;z-index:100001;background:#fff;border-radius:12px;padding:14px 18px;font-size:14px;font-weight:600;color:#1a2e22;text-align:center;box-shadow:0 4px 16px rgba(0,0,0,.15);display:none;"></div>';
  document.body.appendChild(overlay);
  document.body.style.overflow = 'hidden';

  var iframe = document.getElementById('map-picker-iframe');
  var addrEl = document.getElementById(type+'-addr-input') || document.getElementById(type+'-address');
  var lat = (addrEl && addrEl.dataset.lat) ? parseFloat(addrEl.dataset.lat) : (typeof AddressAPI!=='undefined' ? AddressAPI.BRANCH_LAT : 49.4147);
  var lng = (addrEl && addrEl.dataset.lng) ? parseFloat(addrEl.dataset.lng) : (typeof AddressAPI!=='undefined' ? AddressAPI.BRANCH_LNG : 15.2953);
  var zoom = (addrEl && addrEl.dataset.lat) ? 15 : 10;
  _mapPickerCenter = {lat: lat, lng: lng};

  if(iframe){
    // CARTO Voyager tiles — no referrer/API key required, works from file:// and Capacitor
    var html = '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">' +
      '<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>' +
      '<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"><\/script>' +
      '<style>html,body{margin:0;padding:0;height:100%;width:100%}#m{height:100%;width:100%}.leaflet-control-attribution{display:none!important}</style></head>' +
      '<body><div id="m"></div><script>' +
      'var map=L.map("m",{zoomControl:false}).setView(['+lat+','+lng+'],'+zoom+');' +
      'L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png",{maxZoom:19,subdomains:"abcd"}).addTo(map);' +
      'L.control.zoom({position:"bottomright"}).addTo(map);' +
      'map.on("moveend",function(){var c=map.getCenter();parent.postMessage({type:"mapCenter",lat:c.lat,lng:c.lng},"*");});' +
      'setTimeout(function(){var c=map.getCenter();parent.postMessage({type:"mapCenter",lat:c.lat,lng:c.lng},"*");},500);' +
      '<\/script></body></html>';
    iframe.srcdoc = html;
  }
}

function closeMapPicker(){
  var overlay = document.getElementById('map-picker-overlay');
  if(overlay) overlay.remove();
  document.body.style.overflow = '';
  _mapPickerType = null;
  // Restore app header banner
  var banner = document.getElementById('header-banner');
  if(banner) banner.style.display = '';
}

function confirmMapPicker(){
  if(!_mapPickerCenter || !_mapPickerType) { closeMapPicker(); return; }
  var lat = _mapPickerCenter.lat;
  var lng = _mapPickerCenter.lng;
  var type = _mapPickerType;
  closeMapPicker();
  // Reverse geocode via Nominatim (reliable, no API key)
  _mapReverseGeocode(lat, lng, function(result){
    if(!result){ showT('\u26a0\ufe0f','Chyba','Nepoda\u0159ilo se zjistit adresu pro toto m\u00edsto'); return; }
    var cityEl = document.getElementById(type+'-city');
    var zipEl = document.getElementById(type+'-zip');
    var addrEl = document.getElementById(type+'-addr-input') || document.getElementById(type+'-address');
    if(cityEl) cityEl.value = result.city || '';
    if(zipEl && result.zip) zipEl.value = result.zip;
    if(addrEl){
      var street = result.street || '';
      if(result.houseNum) street += (street?' ':'') + result.houseNum;
      addrEl.value = street;
      addrEl.dataset.lat = lat;
      addrEl.dataset.lng = lng;
    }
    if(type==='pickup'||type==='return') calcDelivery(type);
    if(type==='edit-pickup'&&typeof _sosCalcPickupDelivery==='function') _sosCalcPickupDelivery();
    if(type==='edit-return'&&typeof calcEditDelivery==='function') calcEditDelivery();
    if(type==='sos-repl'&&typeof sosReplCalcDelivery==='function') sosReplCalcDelivery();
    _showAddrConfirm(type);
  });
}

// Listen for map center updates from iframe — debounced reverse geocode preview
window.addEventListener('message', function(e){
  if(e.data && e.data.type === 'mapCenter'){
    _mapPickerCenter = {lat: e.data.lat, lng: e.data.lng};
    clearTimeout(_mapRgeoTimer);
    _mapRgeoTimer = setTimeout(function(){
      _mapReverseGeocode(e.data.lat, e.data.lng, function(result){
        var el = document.getElementById('map-picker-addr');
        if(el && result){
          var txt = (result.street||'') + (result.houseNum?' '+result.houseNum:'');
          if(result.city) txt += ', ' + result.city;
          if(result.zip) txt += ' ' + result.zip;
          el.textContent = txt || 'P\u0159esu\u0148te mapu na po\u017eadovan\u00e9 m\u00edsto';
          el.style.display = 'block';
        }
      });
    }, 400); // debounce 400ms to avoid spamming Nominatim
  }
});

// ===== ADDRESS CONFIRMATION =====
function _showAddrConfirm(type){
  var label = document.getElementById(type+'-confirm-label');
  if(label) label.style.display = 'flex';
}
function onAddrConfirmed(type, checked){
  var label = document.getElementById(type+'-confirm-label');
  if(label){
    label.style.background = checked ? '#dcfce7' : 'var(--gp)';
    label.style.borderColor = checked ? '#22c55e' : 'var(--green)';
  }
}

function selectAddr(type,addr,city,lat,lng){
  var addrInputMap={'ship':'ship-street','b-contact':'b-contact-street','sos-repl':'sos-repl-address'};
  var cityInputMap={'ship':'ship-city','b-contact':'b-contact-city','sos-repl':'sos-repl-city'};
  var zipInputMap={'ship':'ship-zip','b-contact':'b-contact-zip','sos-repl':'sos-repl-zip'};
  var inp=document.getElementById(addrInputMap[type]||'')||document.getElementById(type+'-addr-input')||document.getElementById(type+'-address');
  if(inp){inp.value=addr;}
  if(inp && lat && lng){inp.dataset.lat=lat;inp.dataset.lng=lng;}
  var cityInp=document.getElementById(cityInputMap[type]||'')||document.getElementById(type+'-city');
  if(cityInp && city){cityInp.value=city;}
  var zipMatch=addr.match(/(\d{3}\s?\d{2})/);
  if(zipMatch){
    var zipInp=document.getElementById(zipInputMap[type]||'')||document.getElementById(type+'-zip');
    if(zipInp)zipInp.value=zipMatch[1];
  }
  var sugEl=document.getElementById(type+'-addr-suggestions');
  if(sugEl)sugEl.style.display='none';
  if(type==='pickup'||type==='return'){calcDelivery(type);}
  if(type==='edit-pickup'&&typeof _sosCalcPickupDelivery==='function'){_sosCalcPickupDelivery();}
  if(type==='edit-return'&&typeof calcEditDelivery==='function'){calcEditDelivery();}
  if(type==='sos-repl'&&typeof sosReplCalcDelivery==='function'){sosReplCalcDelivery();}
  _showAddrConfirm(type);
}
