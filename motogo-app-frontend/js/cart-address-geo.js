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
    if(type==='pickup'||type==='return'){calcDelivery(type);_showAddrConfirm(type);}
    if(type==='edit-pickup'&&typeof _sosCalcPickupDelivery==='function'){_sosCalcPickupDelivery();}
    if(type==='edit-return'&&typeof calcEditDelivery==='function'){calcEditDelivery();}
    if(type==='sos-repl'&&typeof sosReplCalcDelivery==='function'){sosReplCalcDelivery();}
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

// ===== MAP PICKER – Fullscreen OSM map with crosshair =====
var _mapPickerType = null;
var _mapPickerCenter = null;

function openMapPicker(type){
  _mapPickerType = type;
  var overlay = document.getElementById('map-picker-overlay');
  if(!overlay) return;
  var iframe = document.getElementById('map-picker-iframe');
  // Get current address coords if available
  var addrEl = document.getElementById(type+'-addr-input') || document.getElementById(type+'-address');
  var lat = (addrEl && addrEl.dataset.lat) ? parseFloat(addrEl.dataset.lat) : (typeof AddressAPI!=='undefined' ? AddressAPI.BRANCH_LAT : 49.4147);
  var lng = (addrEl && addrEl.dataset.lng) ? parseFloat(addrEl.dataset.lng) : (typeof AddressAPI!=='undefined' ? AddressAPI.BRANCH_LNG : 15.2953);
  var zoom = (addrEl && addrEl.dataset.lat) ? 15 : 10;
  _mapPickerCenter = {lat: lat, lng: lng};
  // Use Leaflet via CDN in an inline HTML page
  if(iframe){
    var html = '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>' +
      '<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"><\/script>' +
      '<style>html,body{margin:0;padding:0;height:100%;width:100%}#m{height:100%;width:100%}</style></head>' +
      '<body><div id="m"></div><script>' +
      'var map=L.map("m",{zoomControl:false}).setView(['+lat+','+lng+'],'+zoom+');' +
      'L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",{maxZoom:19,attribution:""}).addTo(map);' +
      'L.control.zoom({position:"bottomright"}).addTo(map);' +
      'map.on("moveend",function(){var c=map.getCenter();parent.postMessage({type:"mapCenter",lat:c.lat,lng:c.lng},"*");});' +
      'setTimeout(function(){var c=map.getCenter();parent.postMessage({type:"mapCenter",lat:c.lat,lng:c.lng},"*");},500);' +
      '<\/script></body></html>';
    iframe.srcdoc = html;
  }
  overlay.style.display = 'block';
  document.body.style.overflow = 'hidden';
}

function closeMapPicker(){
  var overlay = document.getElementById('map-picker-overlay');
  if(overlay) overlay.style.display = 'none';
  document.body.style.overflow = '';
  _mapPickerType = null;
}

function confirmMapPicker(){
  if(!_mapPickerCenter || !_mapPickerType) { closeMapPicker(); return; }
  var lat = _mapPickerCenter.lat;
  var lng = _mapPickerCenter.lng;
  var type = _mapPickerType;
  closeMapPicker();
  // Reverse geocode the selected position
  if(typeof AddressAPI !== 'undefined' && typeof AddressAPI.reverseGeocode === 'function'){
    AddressAPI.reverseGeocode(lat, lng, function(result){
      if(!result){ showT('⚠️','Chyba','Nepodařilo se zjistit adresu pro toto místo'); return; }
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
      // Show confirm checkbox
      _showAddrConfirm(type);
    });
  }
}

// Listen for map center updates from iframe
window.addEventListener('message', function(e){
  if(e.data && e.data.type === 'mapCenter'){
    _mapPickerCenter = {lat: e.data.lat, lng: e.data.lng};
    // Reverse geocode for preview
    if(typeof AddressAPI !== 'undefined'){
      AddressAPI.reverseGeocode(e.data.lat, e.data.lng, function(result){
        var el = document.getElementById('map-picker-addr');
        if(el && result){
          var txt = (result.street||'') + (result.houseNum?' '+result.houseNum:'');
          if(result.city) txt += ', ' + result.city;
          if(result.zip) txt += ' ' + result.zip;
          el.textContent = txt || 'Přesuňte mapu na požadované místo';
          el.style.display = 'block';
        }
      });
    }
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
  if(type==='pickup'||type==='return'){calcDelivery(type);_showAddrConfirm(type);}
  if(type==='edit-pickup'&&typeof _sosCalcPickupDelivery==='function'){_sosCalcPickupDelivery();}
  if(type==='edit-return'&&typeof calcEditDelivery==='function'){calcEditDelivery();}
  if(type==='sos-repl'&&typeof sosReplCalcDelivery==='function'){sosReplCalcDelivery();}
}
