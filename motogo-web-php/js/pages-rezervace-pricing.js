// ===== MotoGo24 Web — Rezervace: pricing + vouchers + pickup time + map picker =====
var MG = window.MG || {};
window.MG = MG;

// ===== DELIVERY/RETURN FEE HELPER =====
// Cena přistavení/vrácení = 1000 Kč + 40 Kč/km. Pokud zatím nemáme distance,
// použijeme jen základní 1000 Kč (zobrazí se "trasa se počítá").
MG._calcDeliveryFee = function(distanceKm){
  var base = 1000;
  if(typeof distanceKm === 'number' && distanceKm > 0) return Math.round(base + 40 * distanceKm);
  return base;
};

// ===== PRICE UPDATE (in-place, no form rebuild) =====
MG._rezUpdatePrice = function(){
  var r = MG._rez, mId = r.motoId || r.selectedMotoId;
  var moto = r.motos.find(function(m){ return m.id === mId; });
  var base = (moto && r.startDate && r.endDate) ? MG.calcPrice(moto, r.startDate, r.endDate) : 0;
  var extras = 0;
  if(document.getElementById('rez-eq-passenger') && document.getElementById('rez-eq-passenger').checked) extras += 690;
  if(document.getElementById('rez-eq-boots-rider') && document.getElementById('rez-eq-boots-rider').checked) extras += 290;
  if(document.getElementById('rez-eq-boots-passenger') && document.getElementById('rez-eq-boots-passenger').checked) extras += 290;
  // Delivery/return fees: 1000 Kč + 40 Kč/km od pobočky Mezná 9
  var isDel = document.getElementById('rez-delivery') && document.getElementById('rez-delivery').checked;
  var retOther = document.getElementById('rez-return-other');
  var retSameAsDel = document.getElementById('rez-return-same-as-delivery');
  var delFee = 0, retFee = 0;
  if(isDel) delFee = MG._calcDeliveryFee(MG._rez.deliveryDistanceKm);
  if(retOther && retOther.checked) retFee = MG._calcDeliveryFee(MG._rez.returnDistanceKm);
  else if(retSameAsDel && retSameAsDel.checked && isDel) retFee = delFee;
  MG._rez.deliveryFee = delFee;
  MG._rez.returnFee = retFee;
  extras += delFee + retFee;
  MG._rez.discountAmt = 0;
  var fullPrice = base + extras;
  if(MG._rez.appliedCodes && MG._rez.appliedCodes.length){
    MG._rez.appliedCodes.forEach(function(c){
      if(c.discountType === 'percent'){
        c.discountAmt = Math.round(fullPrice * c.discountValue / 100);
      } else {
        c.discountAmt = c.discountValue;
      }
    });
    var totalDisc = MG._rez.appliedCodes.reduce(function(s,c){return s+c.discountAmt;},0);
    MG._rez.discountAmt = Math.min(totalDisc, fullPrice);
  }
  var total = Math.max(0, fullPrice - MG._rez.discountAmt);
  MG._renderAppliedCodes();
  var el = document.getElementById('rez-price-preview');
  if(el){
    if(total > 0 || MG._rez.discountAmt > 0){
      var T = (MG.t || function(k){ return k; });
      var discTxt = MG._rez.discountAmt > 0 ? '<div style="font-size:.85rem;color:#1a8c1a;margin-top:.3rem">'+T('rez.discount', {amount: MG.formatPrice(MG._rez.discountAmt)})+'</div>' : '';
      el.innerHTML = '<div style="background:#74FB71;color:#0b0b0b;padding:.75rem 1.5rem;border-radius:25px;font-size:1.15rem;font-weight:800;text-align:center;display:inline-block;margin:1rem 0">'+T('rez.totalPrice', {price: MG.formatPrice(total)})+discTxt+'</div>';
    } else { el.innerHTML = ''; }
  }
};

// ===== PICKUP TIME VALIDATION =====
// Returns min allowed time as HH:MM string; null if any time is ok (future date)
MG._rezMinPickupTime = function(){
  var r = MG._rez;
  if(!r.startDate) return null;
  var today = new Date().toISOString().split('T')[0];
  if(r.startDate > today) return null; // future date, any time
  var isDelivery = document.getElementById('rez-delivery') && document.getElementById('rez-delivery').checked;
  var now = new Date();
  var offsetH = isDelivery ? 6 : 1;
  now.setHours(now.getHours() + offsetH);
  var hh = String(now.getHours()).padStart(2,'0');
  var mm = String(now.getMinutes()).padStart(2,'0');
  return hh + ':' + mm;
};

MG._rezValidatePickupTime = function(){
  var pt = document.getElementById('rez-pickup-time');
  if(!pt || !pt.value) return false;
  var min = MG._rezMinPickupTime();
  if(!min) return true;
  return pt.value >= min;
};

// ===== VOUCHER / PROMO CODE VALIDATION =====
if(!MG._rez.appliedCodes) MG._rez.appliedCodes = [];
if(!MG._rez.discountAmt) MG._rez.discountAmt = 0;

MG._applyVoucher = async function(){
  var T = (MG.t || function(k){ return k; });
  var inp = document.getElementById('rez-voucher');
  var msg = document.getElementById('rez-voucher-msg');
  if(!inp || !inp.value.trim()){ if(msg) msg.innerHTML='<span style="color:#c00">'+T('rez.voucher.enter')+'</span>'; return; }
  var code = inp.value.trim().toUpperCase();
  // Check duplicate
  for(var i=0;i<MG._rez.appliedCodes.length;i++){
    if(MG._rez.appliedCodes[i].code===code){ if(msg) msg.innerHTML='<span style="color:#c00">'+T('rez.voucher.duplicate')+'</span>'; return; }
  }
  if(msg) msg.innerHTML='<span style="color:#999">'+T('rez.voucher.verifying')+'</span>';
  // Calculate base for discount
  var r=MG._rez, mId=r.motoId||r.selectedMotoId;
  var moto=r.motos.find(function(m){return m.id===mId;});
  var base=(moto&&r.startDate&&r.endDate)?MG.calcPrice(moto,r.startDate,r.endDate):0;

  // Try promo code first
  var pr = await window.sb.rpc('validate_promo_code',{p_code:code});
  if(pr.error){
    console.error('[VOUCHER] validate_promo_code error:', pr.error.message);
    if(msg) msg.innerHTML='<span style="color:#c00">'+T('rez.voucher.error',{msg: pr.error.message})+'</span>'; return;
  }
  if(pr.data && pr.data.valid){
    var pd=pr.data;
    if(pd.type==='percent' && MG._rez.appliedCodes.some(function(c){return c.discountType==='percent';})){
      if(msg) msg.innerHTML='<span style="color:#c00">'+T('rez.voucher.percentOnce')+'</span>'; return;
    }
    var disc=pd.type==='percent'?Math.round(base*pd.value/100):pd.value;
    var curDisc=MG._rez.appliedCodes.reduce(function(s,c){return s+c.discountAmt;},0);
    disc=Math.min(disc,Math.max(0,base-curDisc));
    MG._rez.appliedCodes.push({code:code,type:'promo',id:pd.id,discountAmt:disc,discountType:pd.type,discountValue:pd.value});
    var lbl=pd.type==='percent'?pd.value+'%':MG.formatPrice(pd.value);
    if(msg) msg.innerHTML='<span style="color:#1a8c1a">'+T('rez.voucher.discountApplied',{label: lbl, amt: MG.formatPrice(disc)})+'</span>';
    inp.value=''; MG._renderAppliedCodes(); MG._rezUpdatePrice(); return;
  }
  // Try voucher
  var vr = await window.sb.rpc('validate_voucher_code',{p_code:code});
  if(vr.error){
    console.error('[VOUCHER] validate_voucher_code error:', vr.error.message);
    if(msg) msg.innerHTML='<span style="color:#c00">'+T('rez.voucher.error',{msg: vr.error.message})+'</span>'; return;
  }
  if(vr.data && vr.data.valid){
    var vd=vr.data;
    var curDiscV=MG._rez.appliedCodes.reduce(function(s,c){return s+c.discountAmt;},0);
    var vDisc=Math.min(vd.value,Math.max(0,base-curDiscV));
    MG._rez.appliedCodes.push({code:code,type:'voucher',id:vd.id,discountAmt:vDisc,discountType:'fixed',discountValue:vd.value});
    if(msg) msg.innerHTML='<span style="color:#1a8c1a">'+T('rez.voucher.voucherApplied',{amt: MG.formatPrice(vd.value)})+'</span>';
    inp.value=''; MG._renderAppliedCodes(); MG._rezUpdatePrice(); return;
  }
  // Show specific error from promo validation if available
  var errDetail = (pr.data && pr.data.error) ? pr.data.error : T('rez.voucher.invalid');
  if(msg) msg.innerHTML='<span style="color:#c00">✗ '+errDetail+'</span>';
};

MG._renderAppliedCodes = function(){
  var el=document.getElementById('rez-applied-codes'); if(!el) return;
  if(!MG._rez.appliedCodes.length){ el.innerHTML=''; return; }
  var h='';
  MG._rez.appliedCodes.forEach(function(c,i){
    h+='<div style="display:inline-flex;align-items:center;gap:.4rem;background:#dcfce7;padding:.3rem .7rem;border-radius:20px;margin:0 .5rem .5rem 0;font-size:.85rem">' +
      '<strong>'+c.code+'</strong> −'+MG.formatPrice(c.discountAmt) +
      ' <span style="cursor:pointer;color:#c00" onclick="MG._removeCode('+i+')">✕</span></div>';
  });
  el.innerHTML=h;
};

MG._removeCode = function(idx){
  MG._rez.appliedCodes.splice(idx,1);
  MG._rez.discountAmt=MG._rez.appliedCodes.reduce(function(s,c){return s+c.discountAmt;},0);
  MG._renderAppliedCodes(); MG._rezUpdatePrice();
};

// ===== MAPY.CZ API (web reservation) =====
MG.MAPY_CZ_KEY = 'whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0';
MG.MAPY_CZ_BASE = 'https://api.mapy.cz/v1';

// Reverse geocode pres Mapy.cz -> objekt s adresou
MG._mapyRgeocode = function(lat, lng){
  var url = MG.MAPY_CZ_BASE + '/rgeocode?lat=' + lat + '&lon=' + lng + '&lang=cs&apikey=' + MG.MAPY_CZ_KEY;
  return fetch(url, { headers: { 'X-Mapy-Api-Key': MG.MAPY_CZ_KEY } })
    .then(function(r){ return r.json(); })
    .then(function(data){
      var it = (data && data.items || [])[0];
      if(!it) return null;
      var addr = it.regionalStructure || [];
      function byT(t){ var x = addr.find(function(a){ return a.type === t; }); return x ? x.name : ''; }
      var street = byT('regional.street') || byT('regional.address') || '';
      var hn = (it.name && /\d/.test(it.name)) ? (it.name.match(/\d+[a-zA-Z]?(?:\/\d+[a-zA-Z]?)?/) || [''])[0] : '';
      var city = byT('regional.municipality') || byT('regional.municipality_part') || byT('regional.region') || '';
      var zip = it.zip || '';
      var line = [street, hn].filter(Boolean).join(' ').trim() || it.name || '';
      var full = [line, [zip, city].filter(Boolean).join(' ').trim()].filter(Boolean).join(', ');
      return { full: full, street: street, hn: hn, city: city, zip: zip, label: it.label || it.name || '' };
    })
    .catch(function(){ return null; });
};

// ===== ROUTE CALCULATION (delivery/return distance from branch) =====
// Pobočka Mezná 9, 393 01 Mezná — koordináty se geocodují při prvním požadavku
MG._BRANCH_FROM_ADDRESS = 'Mezná 9, 393 01 Mezná';
MG._BRANCH_FROM_COORDS = null;

MG._ensureBranchCoords = function(){
  if(MG._BRANCH_FROM_COORDS) return Promise.resolve(MG._BRANCH_FROM_COORDS);
  return MG._mapySuggest(MG._BRANCH_FROM_ADDRESS, 1).then(function(arr){
    if(arr && arr.length && arr[0].lat && arr[0].lng){
      MG._BRANCH_FROM_COORDS = { lat: arr[0].lat, lng: arr[0].lng };
      return MG._BRANCH_FROM_COORDS;
    }
    return null;
  });
};

// Routing pres Mapy.cz - vraci { distanceKm, durationMin }
MG._mapyRouting = function(fromLat, fromLng, toLat, toLng){
  var url = MG.MAPY_CZ_BASE + '/routing/route' +
    '?start=' + fromLng + ',' + fromLat +
    '&end=' + toLng + ',' + toLat +
    '&routeType=car_fast&lang=cs&format=geojson&apikey=' + MG.MAPY_CZ_KEY;
  return fetch(url, { headers: { 'X-Mapy-Api-Key': MG.MAPY_CZ_KEY } })
    .then(function(r){ return r.json(); })
    .then(function(data){
      var len = (data && (data.length || (data.properties && data.properties.length))) || 0;
      var dur = (data && (data.duration || (data.properties && data.properties.duration))) || 0;
      if(!len) return null;
      return { distanceKm: len / 1000, durationMin: Math.round(dur / 60) };
    })
    .catch(function(){ return null; });
};

// Format trasa-info HTML do panelu prislusneho typu (delivery/return)
MG._renderRouteInfo = function(type, state){
  var el = document.getElementById('rez-' + type + '-route-info');
  if(!el) return;
  if(state.loading){
    el.style.display = 'block';
    el.innerHTML = '<div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:8px;padding:.6rem .8rem;font-size:.85rem;color:#374151"><span class="spinner" style="display:inline-block;width:12px;height:12px;border:2px solid #74FB71;border-right-color:transparent;border-radius:50%;animation:spin 0.8s linear infinite;margin-right:.5rem;vertical-align:middle"></span>Počítám nejrychlejší trasu od pobočky Mezná 9, 393 01 Mezná…</div>';
    return;
  }
  if(state.error){
    el.style.display = 'block';
    el.innerHTML = '<div style="background:#fff4f4;border:1px solid #f0c8c8;border-radius:8px;padding:.6rem .8rem;font-size:.85rem;color:#a02020">Trasu se nepodařilo spočítat. Cena přistavení bude upřesněna ručně ('+MG.formatPrice(1000)+' + '+MG.formatPrice(40)+'/km).</div>';
    return;
  }
  if(typeof state.distanceKm === 'number'){
    var km = state.distanceKm.toFixed(1).replace('.', ',');
    var fee = MG._calcDeliveryFee(state.distanceKm);
    var label = type === 'delivery' ? 'přistavení' : 'vrácení';
    el.style.display = 'block';
    el.innerHTML =
      '<div style="background:#f0faf5;border:1px solid #74FB71;border-radius:8px;padding:.6rem .8rem;font-size:.88rem;color:#1a3a2a">' +
        '<div style="font-weight:700;margin-bottom:.2rem">Cena ' + label + ': ' + MG.formatPrice(fee) + '</div>' +
        '<div style="font-size:.82rem;color:#374151">Nejrychlejší trasa od pobočky <strong>Mezná 9, 393 01 Mezná</strong>: <strong>' + km + ' km</strong>' +
        (state.durationMin ? ' (~' + state.durationMin + ' min jízdy)' : '') + '</div>' +
        '<div style="font-size:.78rem;color:#6b7280;margin-top:.2rem">Výpočet: '+MG.formatPrice(1000)+' + '+MG.formatPrice(40)+' × ' + km + ' km = ' + MG.formatPrice(fee) + '</div>' +
      '</div>';
    return;
  }
  el.style.display = 'none';
  el.innerHTML = '';
};

// Spocita trasu pro dany typ (delivery/return) pri zadane lat/lng adrese.
// Pokud lat/lng chybi, zkusi geocode pres _mapySuggest podle textu inputu.
MG._calcRouteFor = function(type, lat, lng){
  MG._renderRouteInfo(type, { loading: true });
  var inpId = type === 'delivery' ? 'rez-delivery-address' : 'rez-return-address';

  function withCoords(toLat, toLng){
    return MG._ensureBranchCoords().then(function(from){
      if(!from) { MG._renderRouteInfo(type, { error: true }); return; }
      return MG._mapyRouting(from.lat, from.lng, toLat, toLng).then(function(res){
        if(!res){ MG._renderRouteInfo(type, { error: true }); return; }
        if(type === 'delivery') MG._rez.deliveryDistanceKm = res.distanceKm;
        else MG._rez.returnDistanceKm = res.distanceKm;
        MG._renderRouteInfo(type, { distanceKm: res.distanceKm, durationMin: res.durationMin });
        // Pokud "Vrátit motorku na stejné adrese" — propaguj vzdalenost na return
        if(type === 'delivery'){
          var rSame = document.getElementById('rez-return-same-as-delivery');
          if(rSame && rSame.checked) MG._rez.returnDistanceKm = res.distanceKm;
        }
        MG._rezUpdatePrice();
      });
    });
  }

  if(typeof lat === 'number' && typeof lng === 'number'){
    return withCoords(lat, lng);
  }
  // Fallback: geocode podle textu inputu
  var inp = document.getElementById(inpId);
  var q = inp && inp.value && inp.value.trim();
  if(!q){ MG._renderRouteInfo(type, {}); return Promise.resolve(); }
  return MG._mapySuggest(q, 1).then(function(arr){
    if(arr && arr.length && arr[0].lat && arr[0].lng){
      return withCoords(arr[0].lat, arr[0].lng);
    }
    MG._renderRouteInfo(type, { error: true });
  });
};

// Suggest (autocomplete) pres Mapy.cz
MG._mapySuggest = function(query, limit){
  if(!query || query.trim().length < 2) return Promise.resolve([]);
  var url = MG.MAPY_CZ_BASE + '/suggest?query=' + encodeURIComponent(query.trim()) +
    '&limit=' + (limit || 8) + '&lang=cs&apikey=' + MG.MAPY_CZ_KEY;
  return fetch(url, { headers: { 'X-Mapy-Api-Key': MG.MAPY_CZ_KEY } })
    .then(function(r){ return r.json(); })
    .then(function(data){
      return (data && data.items || []).map(function(it){
        var p = it.position || {};
        return {
          label: it.name || '',
          description: it.location || '',
          full: [it.name, it.location].filter(Boolean).join(', '),
          lat: p.lat,
          lng: p.lon,
          zip: it.zip || '',
        };
      });
    })
    .catch(function(){ return []; });
};

// Pripoji autocomplete k input poli
MG._attachMapyAutocomplete = function(inputId){
  var inp = document.getElementById(inputId);
  if(!inp || inp.dataset.mapyAttached === '1') return;
  inp.dataset.mapyAttached = '1';
  inp.autocomplete = 'off';

  var wrap = document.createElement('div');
  wrap.style.cssText = 'position:relative;width:100%';
  inp.parentNode.insertBefore(wrap, inp);
  wrap.appendChild(inp);
  inp.style.width = '100%';

  var list = document.createElement('div');
  list.style.cssText = 'position:absolute;top:100%;left:0;right:0;z-index:10000;background:#fff;border:1px solid #e0e0e0;border-radius:6px;margin-top:4px;max-height:240px;overflow-y:auto;box-shadow:0 4px 14px rgba(0,0,0,.12);display:none';
  wrap.appendChild(list);

  var timer = null, items = [], active = -1, justPickedValue = null;

  function render(){
    if(!items.length){ list.style.display = 'none'; list.innerHTML = ''; return; }
    list.innerHTML = items.map(function(it, i){
      var bg = i === active ? '#f1faf7' : '#fff';
      var bt = i === 0 ? 'none' : '1px solid #eef5f1';
      return '<div data-i="'+i+'" style="padding:7px 10px;cursor:pointer;background:'+bg+';border-top:'+bt+';font-size:13px">' +
        '<div style="font-weight:700;color:#0f1a14">'+ (it.label || '') +'</div>' +
        (it.description ? '<div style="font-size:11px;color:#6b7280">'+ it.description +'</div>' : '') +
        '</div>';
    }).join('');
    list.style.display = 'block';
    Array.from(list.children).forEach(function(el){
      el.addEventListener('mousedown', function(e){
        e.preventDefault();
        var i = parseInt(el.getAttribute('data-i'), 10);
        pick(items[i]);
      });
    });
  }

  function closeList(){ items = []; active = -1; clearTimeout(timer); list.style.display = 'none'; list.innerHTML = ''; }

  function pick(it){
    var newVal = it.full || it.label || '';
    inp.value = newVal;
    justPickedValue = newVal;
    closeList();
    var t = inputId === 'rez-delivery-address' ? 'delivery' : 'return';
    MG._rez['_'+t+'RouteAddr'] = inp.value;
    // Trigger only `change` (downstream price recalc, confirm checkbox).
    // Do NOT dispatch `input` — to znovu spustí suggest a zacyklí dropdown.
    inp.dispatchEvent(new Event('change', { bubbles: true }));
    inp.blur();
    // Výpočet trasy automaticky po výběru adresy
    if(typeof MG._calcRouteFor === 'function'){
      MG._calcRouteFor(t, it.lat, it.lng);
    }
  }

  inp.addEventListener('input', function(){
    var q = inp.value;
    // Po vybrání ze suggestionu input ignoruje opakovaný suggest, dokud user neupraví hodnotu
    if(justPickedValue !== null && q === justPickedValue){ closeList(); return; }
    justPickedValue = null;
    clearTimeout(timer);
    if(!q || q.length < 2){ closeList(); return; }
    timer = setTimeout(function(){
      MG._mapySuggest(q, 8).then(function(arr){ items = arr; active = -1; render(); });
    }, 220);
  });
  inp.addEventListener('change', function(){
    var t = inputId === 'rez-delivery-address' ? 'delivery' : 'return';
    var v = inp.value && inp.value.trim();
    if(!v){
      if(t==='delivery') MG._rez.deliveryDistanceKm = null;
      else MG._rez.returnDistanceKm = null;
      MG._rez['_'+t+'RouteAddr'] = '';
      MG._renderRouteInfo(t, {});
      MG._rezUpdatePrice();
      return;
    }
    if(MG._rez['_'+t+'RouteAddr'] === v) return;
    MG._rez['_'+t+'RouteAddr'] = v;
    // Fallback geocode podle textu (kdyz uzivatel nepouzil autocomplete)
    MG._calcRouteFor(t);
  });
  inp.addEventListener('keydown', function(e){
    if(!items.length){
      if(e.key === 'Escape') closeList();
      return;
    }
    if(e.key === 'ArrowDown'){ e.preventDefault(); active = Math.min(items.length - 1, active + 1); render(); }
    else if(e.key === 'ArrowUp'){ e.preventDefault(); active = Math.max(0, active - 1); render(); }
    else if(e.key === 'Enter' && active >= 0){ e.preventDefault(); pick(items[active]); }
    else if(e.key === 'Escape'){ e.preventDefault(); closeList(); }
  });
  // Pokud user manuálně promaže input nebo začne psát něco jiného, povol nový suggest
  inp.addEventListener('focus', function(){
    if(justPickedValue !== null && inp.value === justPickedValue){
      // držet zavřený — user už adresu vybral
      closeList();
    }
  });
  document.addEventListener('mousedown', function(e){
    if(!wrap.contains(e.target)){ closeList(); }
  });
};

// Automaticky pripoj autocomplete na obe pole jakmile jsou v DOM
MG._initMapyAutocomplete = function(){
  ['rez-delivery-address','rez-return-address'].forEach(function(id){
    MG._attachMapyAutocomplete(id);
  });
};
document.addEventListener('DOMContentLoaded', function(){ setTimeout(MG._initMapyAutocomplete, 300); });
// A i pri dynamickem vytvareni formulare
if(window.MutationObserver){
  var mo = new MutationObserver(function(){ MG._initMapyAutocomplete(); });
  try { mo.observe(document.body, { childList: true, subtree: true }); } catch(e){}
}

// ===== WEB MAP PICKER (fullscreen Leaflet + Mapy.cz tiles) =====
MG._webMapPickerType = null;
MG._webMapCenter = null;

MG._openWebMapPicker = function(type){
  MG._webMapPickerType = type;
  var old = document.getElementById('web-map-picker-overlay');
  if(old) old.remove();
  var overlay = document.createElement('div');
  overlay.id = 'web-map-picker-overlay';
  overlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:99999;background:#fff;';
  overlay.innerHTML =
    '<div style="position:absolute;top:0;left:0;right:0;z-index:100001;display:flex;align-items:center;justify-content:space-between;padding:12px 20px;background:rgba(255,255,255,.95);box-shadow:0 2px 8px rgba(0,0,0,.1);">' +
      '<button onclick="MG._closeWebMapPicker()" style="background:none;border:none;font-size:22px;cursor:pointer;padding:4px 8px;">✕</button>' +
      '<span style="font-size:15px;font-weight:700;">Vyberte místo na mapě (Mapy.cz)</span>' +
      '<button onclick="MG._confirmWebMapPicker()" style="background:#1a8c1a;color:#fff;border:none;border-radius:8px;padding:8px 18px;font-size:14px;font-weight:700;cursor:pointer;">Potvrdit</button>' +
    '</div>' +
    '<div id="web-map-container" style="width:100%;height:100%;"></div>' +
    '<div style="position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);z-index:100000;pointer-events:none;font-size:36px;text-shadow:0 2px 6px rgba(0,0,0,.3);">📍</div>' +
    '<a href="https://mapy.cz/" target="_blank" style="position:absolute;left:12px;bottom:8px;z-index:100001"><img src="https://api.mapy.cz/img/api/logo.svg" style="width:90px" alt="Mapy.cz"/></a>' +
    '<div id="web-map-addr-preview" style="position:absolute;bottom:40px;left:20px;right:20px;z-index:100001;background:rgba(255,255,255,.95);border-radius:10px;padding:12px 16px;font-size:14px;font-weight:600;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,.1);display:none;"></div>';
  document.body.appendChild(overlay);
  document.body.style.overflow = 'hidden';
  if(!window.L){
    var css = document.createElement('link'); css.rel='stylesheet'; css.href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
    document.head.appendChild(css);
    var scr = document.createElement('script'); scr.src='https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
    scr.onload = function(){ MG._initWebMap(); };
    document.head.appendChild(scr);
  } else {
    setTimeout(function(){ MG._initWebMap(); }, 50);
  }
};

MG._initWebMap = function(){
  var container = document.getElementById('web-map-container');
  if(!container || !window.L) return;
  var lat = 49.8175, lng = 15.473, zoom = 7;
  MG._webMapCenter = {lat:lat, lng:lng};
  var map = L.map(container, {zoomControl:true}).setView([lat, lng], zoom);
  var tileUrl = MG.MAPY_CZ_BASE + '/maptiles/basic/256/{z}/{x}/{y}?apikey=' + MG.MAPY_CZ_KEY;
  L.tileLayer(tileUrl, { minZoom: 0, maxZoom: 19, attribution: '<a href="https://api.mapy.cz/copyright" target="_blank">Mapy.cz &amp; Seznam.cz a.s.</a>' }).addTo(map);
  MG._webMap = map;
  map.on('moveend', function(){
    var c = map.getCenter();
    MG._webMapCenter = {lat:c.lat, lng:c.lng};
    MG._reverseGeocodePreview(c.lat, c.lng);
  });
};

MG._reverseGeocodePreview = function(lat, lng){
  var el = document.getElementById('web-map-addr-preview');
  MG._mapyRgeocode(lat, lng).then(function(r){
    if(r && r.full && el){ el.textContent = r.full; el.style.display = 'block'; }
  });
};

MG._closeWebMapPicker = function(){
  var overlay = document.getElementById('web-map-picker-overlay');
  if(overlay) overlay.remove();
  document.body.style.overflow = '';
  if(MG._webMap){ MG._webMap.remove(); MG._webMap=null; }
};

MG._confirmWebMapPicker = function(){
  var center = MG._webMapCenter;
  var type = MG._webMapPickerType;
  MG._closeWebMapPicker();
  if(!center) return;
  MG._mapyRgeocode(center.lat, center.lng).then(function(r){
    if(!r) return;
    var inputId = type === 'delivery' ? 'rez-delivery-address' : 'rez-return-address';
    var inp = document.getElementById(inputId);
    if(inp){ inp.value = r.full; inp.dispatchEvent(new Event('input', { bubbles: true })); }
    MG._calcRouteFor(type, center.lat, center.lng);
  });
};
