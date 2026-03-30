function sosReplSelectMoto(motoId, model, dailyPrice){
    _sosReplacementData.selectedMotoId = motoId;
    _sosReplacementData.selectedModel = model;
    _sosReplacementData.dailyPrice = dailyPrice;

    // UI feedback
    document.querySelectorAll('.sos-repl-moto-card').forEach(function(el){
      el.style.borderColor = 'var(--g200)';
      el.style.background = '#fff';
    });
    var sel = document.getElementById('sos-moto-' + motoId);
    if(sel){ sel.style.borderColor = 'var(--green)'; sel.style.background = 'var(--gp)'; }

    // Update summary
    sosReplUpdateSummary();
}

function sosReplUpdateSummary(){
    var isFault = _sosFault === true || _sosFaultSnapshot === true;
    var summary = document.getElementById('sos-repl-summary');
    var totalEl = document.getElementById('sos-repl-total');

    var delivery = _sosReplacementData.deliveryFee;
    var daily = _sosReplacementData.dailyPrice;
    var days = _sosReplacementData._remainingDays || 1;
    var motoTotal = daily * days;
    var damageDeposit = isFault ? 30000 : 0;
    var total = isFault ? (motoTotal + delivery + damageDeposit) : 0;

    var daysLabel = days === 1 ? 'den' : days < 5 ? 'dny' : 'dní';

    if(summary){
      var html = '<div style="display:flex;justify-content:space-between;"><span>🏍️ ' + (_sosReplacementData.selectedModel || '—') + ' (' + days + ' ' + daysLabel + ' × ' + daily.toLocaleString('cs-CZ') + ' Kč)</span><span style="font-weight:800;">' + (isFault ? motoTotal.toLocaleString('cs-CZ') + ' Kč' : 'zdarma') + '</span></div>'
        + '<div style="display:flex;justify-content:space-between;margin-top:4px;"><span>🚛 Přistavení' + (isFault && _sosReplacementData._deliveryKm ? ' (~' + _sosReplacementData._deliveryKm + ' km)' : '') + '</span><span style="font-weight:800;">' + (isFault ? (delivery ? delivery.toLocaleString('cs-CZ') + ' Kč' : 'zadejte adresu') : 'zdarma') + '</span></div>';
      if(isFault){
        html += '<div style="display:flex;justify-content:space-between;margin-top:4px;border-top:1px solid var(--g200);padding-top:4px;"><span>🛡️ Záloha na poškození</span><span style="font-weight:800;color:#b91c1c;">' + damageDeposit.toLocaleString('cs-CZ') + ' Kč</span></div>';
        html += '<div style="font-size:10px;color:var(--g400);margin-top:4px;">Záloha je vratná po vyhodnocení škody. Obdržíte zálohovou fakturu.</div>';
      }
      summary.innerHTML = html;
    }
    if(totalEl){
      totalEl.textContent = (isFault ? total.toLocaleString('cs-CZ') : '0') + ' Kč';
      if(!isFault){ totalEl.style.color = 'var(--green)'; }
      else { totalEl.style.color = '#b91c1c'; }
    }

    // Update button text with total
    var btn = document.getElementById('sos-repl-btn');
    if(btn){
      if(isFault) btn.textContent = '💳 Zaplatit ' + total.toLocaleString('cs-CZ') + ' Kč a objednat';
      else btn.textContent = '✅ Potvrdit objednávku (zdarma)';
    }
}

function sosReplFillGPS(){
    if(!navigator.geolocation){ showT('❌','GPS nedostupné',''); return; }
    showT('📍','Zjišťuji polohu...','');
    function _fillAddr(pos){
      fetch('https://nominatim.openstreetmap.org/reverse?format=json&lat='+pos.coords.latitude+'&lon='+pos.coords.longitude+'&zoom=18&addressdetails=1')
        .then(function(r){ return r.json(); })
        .then(function(data){
          var addr = data.address || {};
          var street = (addr.road || '') + (addr.house_number ? ' ' + addr.house_number : '');
          var city = addr.city || addr.town || addr.village || '';
          var zip = addr.postcode || '';
          var addrEl = document.getElementById('sos-repl-address');
          var cityEl = document.getElementById('sos-repl-city');
          var zipEl = document.getElementById('sos-repl-zip');
          if(addrEl){ addrEl.value = street; addrEl.dataset.lat = pos.coords.latitude; addrEl.dataset.lng = pos.coords.longitude; }
          if(cityEl) cityEl.value = city;
          if(zipEl) zipEl.value = zip;
          showT('📍','Adresa doplněna', street + ', ' + city);
          sosReplCalcDelivery();
          if(typeof _showAddrConfirm === 'function') _showAddrConfirm('sos-repl');
        })
        .catch(function(){ showT('📍','GPS OK, adresu vyplňte ručně',''); });
    }
    navigator.geolocation.getCurrentPosition(_fillAddr,
    function(err){
      if(err.code===1){ showT('❌','Přístup k poloze zamítnut','Povolte v nastavení'); return; }
      showT('📍','Hledám polohu...','Zkouším alternativní metodu');
      navigator.geolocation.getCurrentPosition(_fillAddr,
        function(){ showT('❌','Poloha nedostupná','Vyplňte adresu ručně'); },
        {enableHighAccuracy:false, timeout:30000, maximumAge:60000});
    },
    {enableHighAccuracy:true, timeout:30000});
}

// Výpočet ceny přistavení pro SOS replacement (1000 Kč + 40 Kč/km, tam+zpět)
var _sosReplDelivTimer = null;
function sosReplCalcDelivery(){
    clearTimeout(_sosReplDelivTimer);
    _sosReplDelivTimer = setTimeout(_doSosReplCalcDelivery, 500);
}
function _doSosReplCalcDelivery(){
    var isFault = _sosFault === true || _sosFaultSnapshot === true;
    if(!isFault){ _sosReplacementData.deliveryFee = 0; sosReplUpdateSummary(); return; }

    var cityEl = document.getElementById('sos-repl-city');
    var addrEl = document.getElementById('sos-repl-address');
    var zipEl = document.getElementById('sos-repl-zip');
    var city = cityEl ? cityEl.value.trim() : '';
    var addr = addrEl ? addrEl.value.trim() : '';
    var zip = zipEl ? zipEl.value.trim() : '';

    if(!city && !addr){ _sosReplacementData.deliveryFee = 1000; sosReplUpdateSummary(); return; }

    // Build full address for geocoding
    var fullAddr = addr || city;
    if(addr && city) fullAddr = addr + ', ' + city;
    if(zip) fullAddr += ', ' + zip;

    var calcEl = document.getElementById('sos-repl-delivery-calc');

    // Use AddressAPI if available (OSRM routing for accurate distance)
    if(typeof AddressAPI !== 'undefined'){
        // Prefer stored coordinates from suggestion selection
        var coords = (addrEl && addrEl.dataset.lat && addrEl.dataset.lng)
            ? {lat: parseFloat(addrEl.dataset.lat), lng: parseFloat(addrEl.dataset.lng)}
            : fullAddr;
        if(calcEl){ calcEl.textContent = 'Vypočítávám vzdálenost...'; calcEl.style.display = 'block'; }
        AddressAPI.calcDistance(coords, function(result){
            if(!result){ _sosReplCalcFallback(city.toLowerCase()); return; }
            var km = result.km;
            var fee = result.fee;
            _sosReplacementData.deliveryFee = fee;
            _sosReplacementData._deliveryKm = km;
            var txt = '📍 ~' + km + ' km · ' + fee.toLocaleString('cs-CZ') + ' Kč';
            if(result.duration) txt += ' · ~' + result.duration + ' min';
            if(result.approx) txt += ' (odhad)';
            if(calcEl){ calcEl.textContent = txt; calcEl.style.display = 'block'; }
            sosReplUpdateSummary();
        });
        return;
    }

    // Fallback: estimate from city name
    _sosReplCalcFallback(city.toLowerCase());
}
function _sosReplCalcFallback(city){
    var km = 50;
    var KM_EST = {praha:160,brno:60,jihlava:40,tabor:35,tábor:35,ceske:90,české:90,plzen:200,plzeň:200,ostrava:280,olomouc:180,liberec:130,hradec:110,pardubice:90,budejovice:70,budějovice:70,mezna:0,mezná:0,humpolec:31,pelhřimov:18,pelhrimov:18};
    for(var c in KM_EST){ if(city.indexOf(c) !== -1){ km = KM_EST[c]; break; } }
    var fee = 1000 + km * 2 * 20;
    _sosReplacementData.deliveryFee = fee;
    _sosReplacementData._deliveryKm = km;
    var calcEl = document.getElementById('sos-repl-delivery-calc');
    if(calcEl){ calcEl.textContent = '📍 ~' + km + ' km · ' + fee.toLocaleString('cs-CZ') + ' Kč (odhad)'; calcEl.style.display = 'block'; }
    sosReplUpdateSummary();
}

async function sosConfirmReplacement(){
    var incId = _sosPendingIncidentId;
    if(!incId){ showT('❌','Chyba','Žádný incident'); return; }
    if(!_sosReplacementData.selectedMotoId){ showT('⚠️','Vyberte motorku','Klikněte na jednu z nabídek'); return; }

    var address = (document.getElementById('sos-repl-address')||{}).value || '';
    var city = (document.getElementById('sos-repl-city')||{}).value || '';
    var zip = (document.getElementById('sos-repl-zip')||{}).value || '';
    var note = (document.getElementById('sos-repl-note')||{}).value || '';

    if(!address.trim() || !city.trim()){ showT('⚠️','Vyplňte adresu','Zadejte ulici a město pro přistavení'); return; }

    // Use snapshot as fallback — protects against _sosFault being reset by async ops
    var isFault = _sosFault === true || _sosFaultSnapshot === true;
    var daily = _sosReplacementData.dailyPrice;
    var delivery = _sosReplacementData.deliveryFee;
    var days = _sosReplacementData._remainingDays || 1;
    var motoTotal = daily * days;
    var damageDeposit = isFault ? 30000 : 0;
    var total = isFault ? (motoTotal + delivery + damageDeposit) : 0;

    sosLoading();
    var btn = document.getElementById('sos-repl-btn');
    if(btn){ btn.textContent = '⏳ Zpracovávám...'; btn.disabled = true; btn.style.opacity = '0.6'; }

    var replacementData = {
      replacement_moto_id: _sosReplacementData.selectedMotoId,
      replacement_model: _sosReplacementData.selectedModel,
      original_moto_id: _sosCurrentMotoId || null,
      delivery_address: address,
      delivery_city: city,
      delivery_zip: zip,
      delivery_note: note,
      daily_price: daily,
      damage_deposit: damageDeposit,
      remaining_days: days,
      moto_total: motoTotal,
      delivery_fee: delivery,
      payment_amount: total,
      payment_status: isFault ? 'pending' : 'free',
      customer_fault: isFault,
      customer_confirmed_at: new Date().toISOString(),
      requested_at: new Date().toISOString()
    };

    if(isFault){
      // Zákazník zavinil → simulace platební brány → pak swap bookings
      _sosReplacementPaymentData = { incId: incId, replacementData: replacementData, total: total, address: address, city: city };
      goTo('s-sos-payment');
      // Wait for DOM to render after page transition before initializing payment form
      setTimeout(function(){ _sosInitPaymentGateway(total); }, 150);
      sosLoadingHide();
      if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = 'Potvrdit objednávku'; }
    } else {
      // Porucha / nezaviněná → rovnou swap bookings + do admin_review
      await _sosSwapBookingsAndConfirm(incId, replacementData, false, address, city);
      sosLoadingHide();
    }
}
