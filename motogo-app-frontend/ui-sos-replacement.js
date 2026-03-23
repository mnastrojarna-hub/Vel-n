/* === UI-SOS-REPLACEMENT.JS — SOS replacement flow, payment & swap === */

// ===== SOS REPLACEMENT — přesměrování na Upravit rezervaci =====
var _sosReplacementMode = false;
var _sosReplacementData = { selectedMotoId: null, selectedModel: null, dailyPrice: 0, deliveryFee: 0 };

var _sosReplacementLoading = false;
var _sosCurrentMotoId = null; // ID aktuální (rozbité) motorky zákazníka
function sosRequestReplacement() {
    if(_sosReplacementLoading) return; // guard against double-click
    _sosReplacementLoading = true;
    showT('⏳','Načítám...','Připravuji náhradní motorky');

    // Persist fault state so it survives async operations
    _sosFaultSnapshot = _sosFault;

    var faultDesc = _sosFault === true ? 'Nehoda byla moje chyba' : _sosFault === false ? 'Nehoda nebyla moje chyba' : '';
    var desc = 'Motorka nepojízdná – žádám náhradní motorku. ' + faultDesc;
    var type = _sosFault === true ? 'accident_major' : _sosFault === false ? 'accident_major' : 'breakdown_major';

    // Předem načti aktivní booking a ulož moto_id — MUSÍ se počkat než se vytvoří incident
    _sosCurrentMotoId = null;
    (async function(){
      try {
        var uid = null;
        try { var u = await window.supabase.auth.getUser(); uid = u.data && u.data.user ? u.data.user.id : null; } catch(e){}
        if(uid){
          // Hledej jakoukoliv aktivní/potvrzenou rezervaci, ne jen paid+active
          var bk = await window.supabase.from('bookings')
            .select('moto_id')
            .eq('user_id', uid)
            .in('status', ['active', 'confirmed', 'pending', 'reserved'])
            .lte('start_date', new Date().toISOString())
            .gte('end_date', new Date().toISOString())
            .limit(1);
          if(bk.data && bk.data.length > 0 && bk.data[0].moto_id){
            _sosCurrentMotoId = bk.data[0].moto_id;
          }
        }
      } catch(e){ console.warn('[SOS] pre-fetch moto_id:', e); }

    // Teprve po načtení moto_id vytvoř/reuse incident
    var incId = await _sosEnsureIncident(type, desc);
      _sosReplacementLoading = false;
      if(!incId){ showT('❌','Chyba','Nepodařilo se nahlásit incident'); return; }
      _sosPendingIncidentId = incId;
      var upd = {customer_decision:'replacement_moto', moto_rideable:false, replacement_status: 'selecting'};
      if(_sosFault !== null) upd.customer_fault = _sosFault;
      // Ulož aktuální moto_id i do incidentu
      if(_sosCurrentMotoId) upd.original_moto_id = _sosCurrentMotoId;
      _sosUpdateIncident(incId, upd);
      // End original booking immediately — moto is not rideable, ride is over
      await _sosEndBooking(incId);
      _sosReplacementMode = true;
      // Přejdi na dedicated SOS replacement screen
      goTo('s-sos-replacement');
    })().catch(function(e){ console.error('[SOS] sosRequestReplacement:', e); _sosReplacementLoading = false; });
}

function sosReplInit(){
    // Reset state
    _sosReplacementData = { selectedMotoId: null, selectedModel: null, dailyPrice: 0, deliveryFee: 0 };

    // Restore from pending SOS incident if coming from floating banner
    if(window._pendingSosIncident && !_sosPendingIncidentId){
      var inc = window._pendingSosIncident;
      _sosPendingIncidentId = inc.id;
      // 3 paths: breakdown (null) = free, not-at-fault (false) = free, at-fault (true) = paid
      if(inc.customer_fault === true){
        _sosFault = true; _sosFaultSnapshot = true;
      } else {
        // breakdown (null) or not-at-fault (false) → both free
        _sosFault = inc.customer_fault === false ? false : null;
        _sosFaultSnapshot = _sosFault;
      }
      if(inc.original_moto_id) _sosCurrentMotoId = inc.original_moto_id;
    }

    // Use snapshot as fallback
    var isFault = _sosFault === true || _sosFaultSnapshot === true;
    var hdr = document.getElementById('sos-repl-hdr');
    var sub = document.getElementById('sos-repl-subtitle');
    var banner = document.getElementById('sos-repl-banner');
    var totalLabel = document.getElementById('sos-repl-total-label');
    var totalEl = document.getElementById('sos-repl-total');
    var btn = document.getElementById('sos-repl-btn');

    if(isFault){
      if(hdr) hdr.style.background = 'linear-gradient(135deg,#7f1d1d,#b91c1c)';
      if(sub) sub.textContent = 'Zaviněná nehoda — náhradní motorka za poplatek';
      if(banner){
        banner.style.background = '#fee2e2';
        banner.style.border = '1px solid #fca5a5';
        banner.style.color = '#b91c1c';
        banner.innerHTML = '⚠️ Nehoda zaviněná zákazníkem — motorka a přistavení jsou <strong>za poplatek</strong>. Po zaplacení bude motorka ihned přistavena.';
      }
      if(btn){
        btn.style.background = '#b91c1c';
        btn.textContent = '💳 Zaplatit a objednat motorku';
      }
    } else {
      if(hdr) hdr.style.background = 'linear-gradient(135deg,#1a2e22,#2d5a3c)';
      if(sub) sub.textContent = 'Porucha / nezaviněná nehoda — přistavení zdarma';
      if(banner){
        banner.style.background = 'var(--gp)';
        banner.style.border = '1px solid var(--green)';
        banner.style.color = 'var(--gd)';
        banner.innerHTML = '💚 Náhradní motorka i přistavení jsou <strong>zdarma</strong> (porucha / nezaviněná nehoda).';
      }
      if(totalEl){ totalEl.textContent = '0 Kč'; totalEl.style.color = 'var(--green)'; }
      if(totalLabel) totalLabel.style.color = 'var(--green)';
      if(btn){
        btn.style.background = 'var(--green)';
        btn.textContent = '✅ Potvrdit objednávku (zdarma)';
      }
    }

    // Načti dostupné motorky
    sosReplLoadMotos();
}

async function sosReplLoadMotos(){
    var container = document.getElementById('sos-repl-motos');
    if(!container) return;
    container.innerHTML = '<div style="text-align:center;padding:15px;color:var(--g400);font-size:12px;">⏳ Načítám dostupné motorky...</div>';

    try {
      // Zjisti uživatele
      var uid = null;
      try { var u = await window.supabase.auth.getUser(); uid = u.data && u.data.user ? u.data.user.id : null; } catch(e){}

      // Najdi aktivní rezervaci — širší dotaz než apiGetActiveLoan (zahrnuje i confirmed/pending)
      var startDate = null, endDate = null, currentMotoId = _sosCurrentMotoId || null;
      if(uid){
        var bkR = await window.supabase.from('bookings')
          .select('moto_id, start_date, end_date')
          .eq('user_id', uid)
          .in('status', ['active', 'confirmed', 'pending', 'reserved'])
          .lte('start_date', new Date().toISOString())
          .gte('end_date', new Date().toISOString())
          .limit(1);
        if(bkR.data && bkR.data.length > 0){
          var bk = bkR.data[0];
          startDate = bk.start_date;
          endDate = bk.end_date;
          if(!currentMotoId) currentMotoId = bk.moto_id;
        }
      }
      // Záloha: zkus i apiGetActiveLoan
      if(!currentMotoId){
        var loan = await apiGetActiveLoan();
        if(loan){
          if(!startDate) startDate = loan.start_date;
          if(!endDate) endDate = loan.end_date;
          currentMotoId = loan.moto_id;
        }
      }
      // Zjisti řidičák zákazníka
      var customerLicense = null;
      if(uid){
        var pr = await window.supabase.from('profiles').select('license_group').eq('id', uid).single();
        if(pr.data && pr.data.license_group) customerLicense = pr.data.license_group; // array e.g. ['A'] or ['A2']
      }

      // Načti všechny motorky se statusem active
      var r = await window.supabase.from('motorcycles')
        .select('id, model, image_url, images, price_weekday, price_weekend, category, license_required, branches(name, city)')
        .eq('status', 'active')
        .limit(50);
      var allMotos = r.data || [];

      // Načti motorky s rezervacemi překrývajícími zbývající období (dnes → konec původní rezervace)
      var rentedMotoIds = {};
      var nowISO = new Date().toISOString().slice(0,10);
      var overlapEnd = endDate || nowISO; // end_date původní rezervace = konec období náhradní motorky
      try {
        // Najdi všechny bookings které se překrývají s obdobím [dnes, endDate]
        // Překryv: booking.start_date <= overlapEnd AND booking.end_date >= nowISO
        var rentedR = await window.supabase.from('bookings')
          .select('moto_id')
          .in('status', ['active', 'reserved', 'pending'])
          .lte('start_date', overlapEnd)
          .gte('end_date', nowISO);
        if(rentedR.data){
          rentedR.data.forEach(function(b){ if(b.moto_id) rentedMotoIds[String(b.moto_id).toLowerCase()] = true; });
        }
      } catch(e){ console.warn('[SOS] fetch rented motos:', e); }

      // Hierarchie ŘP skupin: A > A2 > A1 > AM, B samostatně, N = bez ŘP
      // Skupina A smí řídit: A, A2, A1, AM
      // Skupina A2 smí řídit: A2, A1, AM
      // Skupina A1 smí řídit: A1, AM
      // Skupina AM smí řídit: AM
      // Skupina B smí řídit: B, AM
      // N = nevyžaduje ŘP (dětské motorky) — může kdokoliv
      var LICENSE_COVERS = {
        'A':  ['A','A2','A1','AM'],
        'A2': ['A2','A1','AM'],
        'A1': ['A1','AM'],
        'AM': ['AM'],
        'B':  ['B','AM']
      };

      // Filtruj: 1) ne aktuální motorku, 2) ne motorky s překrývající rezervací, 3) řidičák
      var motos = allMotos.filter(function(m){
        var motoIdLower = String(m.id).toLowerCase();
        // Vyřaď aktuální (rozbitou) motorku zákazníka
        if(currentMotoId && motoIdLower === String(currentMotoId).toLowerCase()) return false;
        // Vyřaď motorky s překrývající rezervací v období náhradní motorky
        if(rentedMotoIds[motoIdLower]) return false;
        // Řidičák — motorky s N (dětské) může řídit kdokoliv
        var req = m.license_required;
        if(!req || req === 'N') return true;
        if(!customerLicense) return true; // nemáme info → zobraz vše
        var has = Array.isArray(customerLicense) ? customerLicense : [customerLicense];
        // Zákazník smí řídit motorku pokud některá jeho skupina pokrývá požadovanou
        var canRide = false;
        for(var i = 0; i < has.length; i++){
          var covers = LICENSE_COVERS[has[i]];
          if(covers && covers.indexOf(req) !== -1){ canRide = true; break; }
        }
        return canRide;
      });
      if(motos.length === 0){
        container.innerHTML = '<div style="text-align:center;padding:15px;color:#b91c1c;font-size:12px;font-weight:600;">Žádné motorky momentálně nejsou dostupné. Kontaktujte MotoGo24.</div>';
        return;
      }

      // Spočítej zbývající dny pro cenový výpočet
      var remainingDays = 1;
      if(endDate){
        var now2 = new Date();
        var end2 = new Date(endDate);
        remainingDays = Math.max(1, Math.ceil((end2 - now2) / (1000*60*60*24)));
      }
      _sosReplacementData._remainingDays = remainingDays;
      _sosReplacementData._endDate = endDate;

      var isFault = _sosFault === true || _sosFaultSnapshot === true;
      var html = '';
      motos.forEach(function(m){
        var price = parseFloat(m.price_weekday) || parseFloat(m.price_weekend) || 890;
        var img = m.image_url || (m.images && m.images[0]) || '';
        var branch = m.branches ? (m.branches.name || m.branches.city || '') : '';
        html += '<div class="sos-repl-moto-card" onclick="sosReplSelectMoto(\'' + m.id + '\',\'' + (m.model||'').replace(/'/g,"\\'") + '\',' + price + ')" '
          + 'id="sos-moto-' + m.id + '" '
          + 'style="display:flex;align-items:center;gap:12px;padding:10px;border:2px solid var(--g200);border-radius:var(--rsm);cursor:pointer;transition:all .15s;">'
          + (img ? '<img src="' + img + '" style="width:56px;height:40px;object-fit:cover;border-radius:8px;flex-shrink:0;" alt="">' : '<div style="width:56px;height:40px;background:var(--g100);border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;">🏍️</div>')
          + '<div style="flex:1;min-width:0;">'
          + '<div style="font-size:13px;font-weight:800;color:var(--black);">' + (m.model||'Motorka') + '</div>'
          + '<div style="font-size:10px;color:var(--g400);margin-top:1px;">' + branch + (endDate ? ' · do ' + new Date(endDate).toLocaleDateString('cs-CZ') : '') + '</div>'
          + '</div>'
          + '<div style="text-align:right;">'
          + '<div style="font-size:12px;font-weight:800;color:var(--black);">' + price.toLocaleString('cs-CZ') + ' Kč/den</div>'
          + (isFault ? '<div style="font-size:10px;color:var(--g400);">' + remainingDays + ' ' + (remainingDays === 1 ? 'den' : remainingDays < 5 ? 'dny' : 'dní') + ' = ' + (price * remainingDays).toLocaleString('cs-CZ') + ' Kč</div>' : '')
          + '</div>'
          + '</div>';
      });
      container.innerHTML = html;
    } catch(e){
      container.innerHTML = '<div style="text-align:center;padding:15px;color:#b91c1c;font-size:12px;font-weight:600;">Chyba při načítání motorek.</div>';
      console.error('[SOS] loadMotos:', e);
    }
}

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
          if(addrEl) addrEl.value = street;
          if(cityEl) cityEl.value = city;
          if(zipEl) zipEl.value = zip;
          showT('📍','Adresa doplněna', street + ', ' + city);
          sosReplCalcDelivery();
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

// Výpočet ceny přistavení pro SOS replacement (1000 Kč + 20 Kč/km)
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
    var fee = 1000 + km * 20;
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
      if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = 'Potvrdit objednávku'; }
    } else {
      // Porucha / nezaviněná → rovnou swap bookings + do admin_review
      await _sosSwapBookingsAndConfirm(incId, replacementData, false, address, city);
    }
}

// Uložená data pro platbu
var _sosReplacementPaymentData = null;

// Called from router when navigating to s-sos-payment
function _sosInitPaymentFromRouter(){
  if(_sosReplacementPaymentData && _sosReplacementPaymentData.total){
    _sosInitPaymentGateway(_sosReplacementPaymentData.total);
  }
}

// Stripe platební brána (pro zaviněné nehody)
function _sosInitPaymentGateway(amount){
    var amountEl = document.getElementById('sos-pay-amount');
    var errorEl = document.getElementById('sos-pay-error');

    if(amountEl){
      amountEl.textContent = amount.toLocaleString('cs-CZ') + ' Kč';
      // Show breakdown under amount
      var parent = amountEl.parentElement;
      if(parent){
        var breakdown = parent.querySelector('.pay-breakdown');
        if(!breakdown){ breakdown = document.createElement('div'); breakdown.className = 'pay-breakdown'; parent.appendChild(breakdown); }
        var pd = _sosReplacementPaymentData;
        if(pd && pd.replacementData){
          var rd = pd.replacementData;
          breakdown.style.cssText = 'font-size:11px;color:var(--g400,#6b7280);margin-top:8px;text-align:left;line-height:1.8;';
          breakdown.innerHTML = '🏍️ Motorka: ' + (rd.moto_total || 0).toLocaleString('cs-CZ') + ' Kč<br>' +
            '🚛 Přistavení: ' + (rd.delivery_fee || 0).toLocaleString('cs-CZ') + ' Kč<br>' +
            '🛡️ <strong>Záloha na poškození: ' + (rd.damage_deposit || 30000).toLocaleString('cs-CZ') + ' Kč</strong>';
        }
      }
    }
    if(errorEl) errorEl.style.display = 'none';
    // Update button text with amount
    var btn = document.getElementById('sos-pay-btn');
    if(btn) btn.textContent = '💳 Zaplatit ' + amount.toLocaleString('cs-CZ') + ' Kč přes Stripe';
}

async function sosPaymentSubmit(){
    var errorEl = document.getElementById('sos-pay-error');
    var btn = document.getElementById('sos-pay-btn');

    if(errorEl) errorEl.style.display = 'none';
    if(btn){ btn.textContent = '⏳ Zpracovávám platbu...'; btn.disabled = true; btn.style.opacity = '0.6'; }

    try {
      var pd = _sosReplacementPaymentData;
      if(!pd){
        showT('❌','Chyba','Chybí data objednávky');
        if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit'; }
        return;
      }

      // Ensure customer_fault is preserved from snapshot
      if(pd.replacementData.customer_fault !== true && _sosFaultSnapshot === true){
        pd.replacementData.customer_fault = true;
      }

      var sosAmount = pd.replacementData.payment_amount || pd.total || 0;

      // First do the swap so we get a replacement booking ID
      await _sosSwapBookingsAndConfirm(pd.incId, pd.replacementData, true, pd.address, pd.city);

      // Find replacement booking ID
      var replBookingId = pd.replacementData.replacement_booking_id;
      if(!replBookingId && pd.incId){
        var incCheck = await window.supabase.from('sos_incidents').select('replacement_booking_id').eq('id', pd.incId).single();
        if(incCheck.data && incCheck.data.replacement_booking_id) replBookingId = incCheck.data.replacement_booking_id;
      }
      if(!replBookingId){
        try {
          var uid = null;
          try { var u = await window.supabase.auth.getUser(); uid = u.data && u.data.user ? u.data.user.id : null; } catch(e){}
          if(uid){
            var recentBk = await window.supabase.from('bookings').select('id')
              .eq('user_id', uid).eq('sos_replacement', true)
              .order('created_at', {ascending: false}).limit(1);
            if(recentBk.data && recentBk.data.length > 0) replBookingId = recentBk.data[0].id;
          }
        } catch(e2){ console.warn('[SOS] Retry find replacement booking:', e2); }
      }

      if(!replBookingId){
        console.error('[SOS] No replacement booking ID found after swap. incId=' + pd.incId);
        showT('❌','Chyba','Nepodařilo se vytvořit náhradní rezervaci');
        if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit'; btn.style.background = '#b91c1c'; }
        return;
      }

      // Process payment via Stripe
      var payResult = await apiProcessPayment(replBookingId, sosAmount, 'card', {type: 'sos', incident_id: pd.incId});

      if(payResult.success){
        // Stripe checkout redirect
        if(payResult.checkout_url){
          _stripeCheckoutBookingId = replBookingId;
          if(typeof _lockPaymentScreen==='function') _lockPaymentScreen('↗ Platební brána otevřena...');
          if(btn){ btn.textContent = '↗ Přesměrování na platbu...'; btn.disabled = true; btn.style.opacity = '0.6'; }
          showT('✅','Přesměrování', 'Budete přesměrováni na platební bránu Stripe...');
          if(typeof _openExternalUrl==='function') _openExternalUrl(payResult.checkout_url);
          else window.location.href = payResult.checkout_url;
          return;
        }

        // PaymentIntent confirmed (Stripe Elements or test)
        pd.replacementData.payment_status = 'paid';
        pd.replacementData.paid_at = new Date().toISOString();

        if(btn){ btn.textContent = '✅ Platba přijata!'; btn.style.background = '#1a8a18'; }
        showT('✅','Platba přijata!', sosAmount.toLocaleString('cs-CZ') + ' Kč');

        await new Promise(function(r){ setTimeout(r, 1500); });

        // Generate ZF + DP
        try {
          if(typeof apiGenerateAdvanceInvoice === 'function'){
            var _zfSos = await apiGenerateAdvanceInvoice(replBookingId, sosAmount, 'sos');
            if(_zfSos.error) console.error('[SOS] ZF generation failed:', _zfSos.error);
            else console.log('[SOS] ZF generated:', _zfSos.invoice_number);
          }
          if(typeof apiGeneratePaymentReceipt === 'function'){
            var _dpSos = await apiGeneratePaymentReceipt(replBookingId, sosAmount, 'sos');
            if(_dpSos.error) console.error('[SOS] DP generation failed:', _dpSos.error);
            else console.log('[SOS] DP generated:', _dpSos.receipt_number);
          }
        } catch(e){ console.error('[SOS] ZF/DP generation failed:', e); }

        // Navigate back
        goTo('s-reservations');
        await loadMyReservations();
      } else {
        showT('❌','Platba selhala', payResult.error || 'Zkuste to znovu');
        if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit'; btn.style.background = '#b91c1c'; }
      }
    } catch(e){
      console.error('[SOS] Payment processing error:', e);
      showT('❌','Chyba při zpracování','Zkuste to znovu');
      if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit'; btn.style.background = '#b91c1c'; }
    }
}

// Core: swap bookings via RPC + update incident
async function _sosSwapBookingsAndConfirm(incId, replacementData, isPaid, address, city){
    var isFault = replacementData.customer_fault;
    var total = replacementData.payment_amount || 0;
    var swapOk = false;

    try {
      // 1. Swap bookings via RPC (atomická operace v DB)
      var swapResult = await window.supabase.rpc('sos_swap_bookings', {
        p_incident_id: incId,
        p_replacement_moto_id: replacementData.replacement_moto_id,
        p_replacement_model: replacementData.replacement_model || null,
        p_delivery_fee: replacementData.delivery_fee || 0,
        p_daily_price: replacementData.daily_price || 0,
        p_is_free: !isFault
      });

      if(swapResult.error){
        console.error('[SOS] sos_swap_bookings RPC error:', swapResult.error.message);
      } else if(swapResult.data){
        var sr = typeof swapResult.data === 'string' ? JSON.parse(swapResult.data) : swapResult.data;
        if(sr.error){
          console.warn('[SOS] swap returned error:', sr.error);
        } else if(sr.success){
          swapOk = true;
          replacementData.original_booking_id = sr.original_booking_id;
          replacementData.replacement_booking_id = sr.replacement_booking_id;
          replacementData.original_end_date = sr.original_end_date;
        }
      }
    } catch(e){
      console.error('[SOS] swap exception:', e);
    }

    // Pokud RPC swap selhal, zkus manuální fallback (přímé DB operace)
    if(!swapOk){
      console.warn('[SOS] RPC swap failed — trying manual fallback');
      try {
        var uid = await _getUserId();
        if(uid){
          var todayISO = new Date().toISOString().slice(0,10);
          // Najdi aktivní booking (nebo ended_by_sos)
          var bkR = await window.supabase.from('bookings')
            .select('id, moto_id, end_date, original_end_date, status, ended_by_sos')
            .eq('user_id', uid)
            .in('status', ['active','confirmed','reserved'])
            .eq('payment_status', 'paid')
            .lte('start_date', todayISO)
            .gte('end_date', todayISO)
            .limit(1);
          var origBooking = bkR.data && bkR.data[0];
          // Fallback: hledej ended_by_sos booking
          if(!origBooking){
            var bkR2 = await window.supabase.from('bookings')
              .select('id, moto_id, end_date, original_end_date, status, ended_by_sos')
              .eq('user_id', uid).eq('ended_by_sos', true).eq('status', 'completed')
              .order('created_at', {ascending: false}).limit(1);
            if(bkR2.data && bkR2.data.length > 0) origBooking = bkR2.data[0];
          }
          if(origBooking){
            var alreadyEnded = origBooking.status === 'completed' && origBooking.ended_by_sos;
            var origEndDate = origBooking.original_end_date || origBooking.end_date;
            if(!alreadyEnded){
              // Ukonči původní booking
              await window.supabase.from('bookings').update({
                original_end_date: origBooking.end_date,
                end_date: todayISO,
                status: 'completed',
                ended_by_sos: true,
                sos_incident_id: incId
              }).eq('id', origBooking.id);
            }
            // Vytvoř náhradní booking
            var newBk = await window.supabase.from('bookings').insert({
              user_id: uid,
              moto_id: replacementData.replacement_moto_id,
              start_date: todayISO,
              end_date: origEndDate,
              pickup_time: '09:00',
              status: 'active',
              payment_status: isFault ? 'unpaid' : 'paid',
              total_price: total,
              delivery_fee: isFault ? (replacementData.delivery_fee || 0) : 0,
              sos_replacement: true,
              replacement_for_booking_id: origBooking.id,
              sos_incident_id: incId,
              notes: '[SOS] Náhradní motorka (fallback). Incident: ' + incId,
              picked_up_at: new Date().toISOString()
            }).select('id').single();
            if(newBk.data){
              swapOk = true;
              replacementData.original_booking_id = origBooking.id;
              replacementData.replacement_booking_id = newBk.data.id;
              replacementData.original_end_date = origBooking.end_date;
              // Update incident
              await window.supabase.from('sos_incidents').update({
                original_booking_id: origBooking.id,
                replacement_booking_id: newBk.data.id,
                original_moto_id: origBooking.moto_id
              }).eq('id', incId);
              // Motorka do servisu
              if(origBooking.moto_id){
                await window.supabase.from('motorcycles').update({status:'maintenance'}).eq('id', origBooking.moto_id);
              }
            }
          }
        }
      } catch(e2){ console.error('[SOS] manual fallback failed:', e2); }
    }

    // 2. Update incident
    var newStatus = isFault ? (isPaid ? 'admin_review' : 'pending_payment') : 'admin_review';
    await window.supabase.from('sos_incidents').update({
      replacement_status: newStatus,
      replacement_data: replacementData
    }).eq('id', incId);

    // 3. Timeline
    var actionText = isFault
      ? 'Zákazník zaplatil ' + total + ' Kč a objednal náhradní motorku: ' + (replacementData.replacement_model || '?')
      : 'Zákazník objednal náhradní motorku: ' + (replacementData.replacement_model || '?') + ' (zdarma)';
    if(!swapOk) actionText += ' [SWAP SELHAL — čeká na ruční zpracování adminem]';
    await window.supabase.from('sos_timeline').insert({
      incident_id: incId,
      action: actionText,
      description: 'Adresa: ' + (address||'') + ', ' + (city||'') + '.' + (swapOk ? ' Rezervace automaticky přepnuta.' : ' SWAP SELHAL — admin musí zpracovat ručně.') + ' Čeká na schválení adminem.'
    });

    if(!isFault) apiSosRequestReplacement(incId);

    // 4. Refresh reservations cache
    _cachedBookings = null;

    // 5. Success feedback
    _sosPendingIncidentId = null;
    _sosReplacementPaymentData = null;
    // Refresh reservations cache
    if(typeof renderMyReservations === 'function') renderMyReservations();

    var resBtn = '<button onclick="goTo(\'s-res\')" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;">📋 Zobrazit moje rezervace</button>';
    if(!swapOk){
      // Swap selhal — informuj uživatele že admin to vyřeší
      _sosShowDone(isFault ? 'Zaplaceno — ' + total.toLocaleString('cs-CZ') + ' Kč' : 'Požadavek odeslán',
        'Objednávka náhradní motorky (' + (replacementData.replacement_model || '?') + ') byla zaznamenána.<br>' +
        'MotoGo24 zpracuje váš požadavek co nejdříve.<br>' +
        (isFault ? 'Platba přijata, admin potvrdí přepnutí rezervace.' : ''),
        resBtn);
    } else if(isFault){
      _sosShowDone('Zaplaceno — ' + total.toLocaleString('cs-CZ') + ' Kč',
        'Rezervace přepnuta na ' + (replacementData.replacement_model || 'náhradní motorku') + '.<br>' +
        'Objednávka čeká na schválení MotoGo24.<br>' +
        'Zálohová faktura byla vygenerována do sekce Faktury.',
        resBtn);
    } else {
      _sosShowDone('Náhradní motorka objednána',
        'Rezervace přepnuta na ' + (replacementData.replacement_model || 'náhradní motorku') + ' (zdarma).<br>' +
        'Objednávka čeká na schválení MotoGo24.',
        resBtn);
    }
}
