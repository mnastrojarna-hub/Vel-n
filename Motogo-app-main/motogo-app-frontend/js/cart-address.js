// ===== CART-ADDRESS.JS – Address autocomplete: City → Street → PSČ =====
// Depends on: ADDR_DB (cart-address-data.js), AddressAPI (address-api.js)

function showAddrSuggestions(inp,type){
  var sugEl=document.getElementById(type+'-addr-suggestions');
  if(!sugEl)return;
  var val=(inp.value||'').trim();
  if(val.length<2){sugEl.style.display='none';return;}
  var cityInputMap={'ship':'ship-city','b-contact':'b-contact-city','sos-repl':'sos-repl-city'};
  var cityEl=document.getElementById(cityInputMap[type]||'')||document.getElementById(type+'-city');
  var city=(cityEl && cityEl.value) ? cityEl.value.trim() : '';

  if(typeof AddressAPI !== 'undefined'){
    if(city){
      AddressAPI.suggestStreetsDebounced(val, city, function(results){
        if(!results || results.length===0){sugEl.style.display='none';return;}
        _renderStreetSuggestions(sugEl, results, type);sugEl.style.display='block';
      });
    } else {
      AddressAPI.suggestDebounced(val, function(results){
        if(!results || results.length===0){sugEl.style.display='none';return;}
        _renderStreetSuggestions(sugEl, results, type);sugEl.style.display='block';
      });
    }
    return;
  }
  var q=val.toLowerCase();
  var matches=ADDR_DB.filter(function(a){
    if(city && a.city.toLowerCase() !== city.toLowerCase()) return false;
    return a.addr.toLowerCase().indexOf(q)!==-1;
  }).slice(0,8);
  if(matches.length===0){sugEl.style.display='none';return;}
  var results=matches.map(function(a){
    var zipMatch=a.addr.match(/(\d{3})\s?(\d{2})/);
    var streetMatch=a.addr.match(/^([^,]+?)(?:,\s*\d)/);
    var street=streetMatch?streetMatch[1]:'';
    var numMatch=street.match(/^(.+?)\s+(\d+.*)$/);
    return {label:a.addr,lat:null,lng:null,street:numMatch?numMatch[1]:street,houseNum:numMatch?numMatch[2]:'',district:'',city:a.city,zip:zipMatch?zipMatch[1]+' '+zipMatch[2]:''};
  });
  _renderStreetSuggestions(sugEl, results, type);sugEl.style.display='block';
}

function showCitySuggestionsFor(inp,type){
  var sugEl=document.getElementById(type+'-city-suggestions');
  if(!sugEl)return;
  var val=(inp.value||'').trim();
  if(val.length<2){sugEl.style.display='none';return;}
  if(typeof AddressAPI !== 'undefined'){
    AddressAPI.suggestCitiesDebounced(val, function(results){
      if(!results || results.length===0){sugEl.style.display='none';return;}
      _renderCitySuggestions(sugEl, results, type);sugEl.style.display='block';
    });
    return;
  }
  var q=val.toLowerCase();var seen={};
  var matches=ADDR_DB.filter(function(a){
    if(seen[a.city]) return false;
    var ok=a.city.toLowerCase().indexOf(q)!==-1;
    if(ok) seen[a.city]=true;return ok;
  }).slice(0,8);
  if(matches.length===0){sugEl.style.display='none';return;}
  var results=matches.map(function(a){
    var zipMatch=a.addr.match(/(\d{3})\s?(\d{2})/);
    return {label:a.city, city:a.city, zip:zipMatch?zipMatch[1]+' '+zipMatch[2]:'', district:'', lat:null, lng:null};
  });
  _renderCitySuggestions(sugEl, results, type);sugEl.style.display='block';
}

function _renderCitySuggestions(sugEl, results, type){
  sugEl.innerHTML='';
  results.forEach(function(r){
    var div=document.createElement('div');div.className='addr-sug-item';
    var sub = r.district ? r.district : (r.zip || '');
    if(sub){
      div.innerHTML='<div style="display:flex;align-items:center;gap:8px;"><span style="color:var(--green);font-size:15px;line-height:1;">🏙️</span><div><div style="font-weight:700;font-size:13px;line-height:1.3;">'+_esc(r.city)+'</div><div style="font-size:11px;color:var(--g400);font-weight:500;line-height:1.3;">'+_esc(sub)+'</div></div></div>';
    } else {
      div.innerHTML='<span style="color:var(--green);font-size:15px;">🏙️</span> <span style="font-weight:700;">'+_esc(r.city)+'</span>';
    }
    function handler(e){e.preventDefault();e.stopPropagation();_selectCityFor(type, r.city, r.zip||'');}
    div.addEventListener('mousedown', handler);
    div.addEventListener('touchstart', handler, {passive:false});
    sugEl.appendChild(div);
  });
}

function _selectCityFor(type, city, zip){
  var cityInputMap={'ship':'ship-city','b-contact':'b-contact-city','sos-repl':'sos-repl-city'};
  var zipInputMap={'ship':'ship-zip','b-contact':'b-contact-zip','sos-repl':'sos-repl-zip'};
  var addrInputMap={'ship':'ship-street','b-contact':'b-contact-street','sos-repl':'sos-repl-address'};
  var cityEl=document.getElementById(cityInputMap[type]||'')||document.getElementById(type+'-city');
  if(cityEl) cityEl.value=city;
  if(zip){
    var zipEl=document.getElementById(zipInputMap[type]||'')||document.getElementById(type+'-zip');
    if(zipEl) zipEl.value=zip;
  }
  var sugEl=document.getElementById(type+'-city-suggestions');
  if(sugEl) sugEl.style.display='none';
  var addrEl=document.getElementById(addrInputMap[type]||'')||document.getElementById(type+'-addr-input')||document.getElementById(type+'-address');
  if(addrEl){ addrEl.value=''; setTimeout(function(){ addrEl.focus(); }, 100); }
  if(typeof updateEditPriceSummary==='function') updateEditPriceSummary();
  if(type==='sos-repl' && typeof sosReplCalcDelivery==='function') sosReplCalcDelivery();
}

function _renderStreetSuggestions(sugEl, results, type){
  sugEl.innerHTML='';
  results.forEach(function(r){
    var div=document.createElement('div');div.className='addr-sug-item';
    var streetLine = r.street ? (r.street + (r.houseNum ? ' ' + r.houseNum : '')) : r.label;
    var cityLine = r.city || '';
    if(r.zip && cityLine) cityLine = r.zip + ' ' + cityLine;
    if(r.district && r.district !== r.city) cityLine += ' · ' + r.district;
    if(cityLine && r.street){
      div.innerHTML='<div style="display:flex;align-items:flex-start;gap:8px;"><span style="color:var(--green);font-size:15px;line-height:1;">📍</span><div><div style="font-weight:700;font-size:13px;line-height:1.3;">'+_esc(streetLine)+'</div><div style="font-size:11px;color:var(--g400);font-weight:500;line-height:1.3;">'+_esc(cityLine)+'</div></div></div>';
    } else {
      div.innerHTML='<span style="color:var(--green);font-size:15px;">📍</span> <span style="font-weight:600;">'+_esc(streetLine)+'</span>';
    }
    function handler(e){
      e.preventDefault();e.stopPropagation();
      var addrVal = r.street ? (r.street + (r.houseNum ? ' ' + r.houseNum : '')) : r.label;
      selectAddr(type, addrVal, r.city||'', r.lat||null, r.lng||null);
      if(r.zip){
        var zipMaps={'ship':'ship-zip','b-contact':'b-contact-zip','sos-repl':'sos-repl-zip'};
        var zipEl=document.getElementById(zipMaps[type]||'')||document.getElementById(type+'-zip');
        if(zipEl) zipEl.value=r.zip;
      }
    }
    div.addEventListener('mousedown', handler);
    div.addEventListener('touchstart', handler, {passive:false});
    sugEl.appendChild(div);
  });
}
function _esc(s){return s?s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'):'';}

function showCitySuggestions(inp){ showCitySuggestionsFor(inp,'edit-return'); }
function selectCity(city){ _selectCityFor('edit-return', city, ''); }
