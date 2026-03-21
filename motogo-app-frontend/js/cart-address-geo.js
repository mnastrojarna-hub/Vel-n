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
}
