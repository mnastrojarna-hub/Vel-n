// ===== UI-CONTROLLER.JS – DOM manipulation and UI helpers =====

// ===== TOAST =====
let tT;
function showT(icon,title,sub){
  clearTimeout(tT);
  document.getElementById('t-i').textContent=icon;
  document.getElementById('t-t').textContent=title;
  document.getElementById('t-s').textContent=sub;
  document.getElementById('toast').classList.add('show');
  tT=setTimeout(()=>document.getElementById('toast').classList.remove('show'),3000);
}

// Permissions (grantPerms, skipPerms, initPerms) → js/storage.js

// ===== BIO BUTTON =====
// Browser fallback: show bio button if previously enabled or if
// Cordova/Capacitor fingerprint is available (native-bridge.js overrides this)
function setupBioButton(){
  var bs=document.getElementById('bio-section');
  if(!bs) return;
  // Check Cordova fingerprint plugin (VoltBuilder builds)
  if(window.Fingerprint){
    window.Fingerprint.isAvailable(function(){
      bs.style.display='';
      var icon=document.getElementById('bio-icon');
      var label=document.getElementById('bio-label');
      var sub=document.getElementById('bio-sub');
      if(icon) icon.textContent='\ud83d\udd10';
      if(label) label.textContent=_t('auth').biometricBtn||'Biometrick\u00e9 p\u0159ihl\u00e1\u0161en\u00ed';
      if(sub) sub.textContent=_t('auth').fingerprint||'Otisk prstu';
      try{localStorage.setItem('mg_bio_enabled','1');}catch(e){}
    },function(){
      if(localStorage.getItem('mg_bio_enabled')){bs.style.display='';}
      else{bs.style.display='none';}
    });
    return;
  }
  // Browser fallback: show only if previously enabled
  if(!localStorage.getItem('mg_bio_enabled')){bs.style.display='none';return;}
  bs.style.display='';
  document.getElementById('bio-icon').textContent='\ud83d\udc46';
  document.getElementById('bio-label').textContent=_t('auth').fingerprint;
  document.getElementById('bio-sub').textContent=_t('auth').biometricBtn;
}

// ===== LOGIN / REGISTER / BIO =====
// Moved to js/auth-ui.js – doLogin(), bioLogin(), regNext(), doRegister(), doLogout(), renderUserData()

// ===== SOS FUNCTIONS (PRODUCTION) =====

// Global SOS state — tracks user selections across SOS screens
var _sosFault = null;
var _sosActiveIncidentId = null;
var _sosPendingIncidentId = null;  // Incident čekající na platbu (zaviněná nehoda)

function _sosGetGPS(){
  return new Promise(function(resolve){
    if(!navigator.geolocation){ resolve({lat:null,lng:null}); return; }
    navigator.geolocation.getCurrentPosition(
      function(pos){ resolve({lat:pos.coords.latitude,lng:pos.coords.longitude}); },
      function(){ resolve({lat:null,lng:null}); },
      {enableHighAccuracy:true,timeout:10000}
    );
  });
}

function _sosEnsureIncident(type, desc){
  return new Promise(function(resolve){
    if(_sosActiveIncidentId){ resolve(_sosActiveIncidentId); return; }
    showT('⚠️','Hlásím incident...','Odesílám na centrálu');
    apiGetActiveLoan().then(function(loan){
      var bookingId = loan ? (loan.id || (loan._db && loan._db.id)) : null;
      var motoId = loan ? (loan.moto_id || null) : null;
      _sosGetGPS().then(function(gps){
        apiCreateSosIncident(type, bookingId, gps.lat, gps.lng, desc, null, motoId)
          .then(function(r){
            if(r && r.error){
              console.error('[SOS] createIncident error:', r.error);
              showT('❌','Chyba hlášení',''+r.error);
            }
            if(r && r.id) _sosActiveIncidentId = r.id;
            resolve(r && r.id ? r.id : null);
          })
          .catch(function(e){
            console.error('[SOS] createIncident exception:', e);
            showT('❌','Chyba','Nepodařilo se vytvořit incident');
            resolve(null);
          });
      });
    }).catch(function(e){
      console.error('[SOS] getLoan error:', e);
      resolve(null);
    });
  });
}

function _sosUpdateIncident(incidentId, data){
  if(!incidentId || !window.supabase) return Promise.resolve();
  return window.supabase.from('sos_incidents').update(data).eq('id', incidentId)
    .then(function(r){
      if(r && r.error) console.error('[SOS] updateIncident error:', r.error.message, data);
    }).catch(function(e){
      console.error('[SOS] updateIncident exception:', e);
    });
}

function sosReportAccident(type) {
    var sosType = type === 'lehka' ? 'accident_minor' : 'accident_major';
    var ts = new Date().toLocaleString('cs-CZ');
    _sosActiveIncidentId = null;
    _sosFault = null;
    var desc = sosType === 'accident_minor' ? 'Lehká nehoda – pokračuji v jízdě' : 'Závažná nehoda';
    _sosEnsureIncident(sosType, desc)
      .then(function(incId){
        if(incId){
          // Lehká nehoda = pojízdná, závažná = nepojízdná
          var upd = { moto_rideable: sosType === 'accident_minor' };
          _sosUpdateIncident(incId, upd);
          // Timeline entry s detaily
          window.supabase.from('sos_timeline').insert({
            incident_id: incId,
            action: sosType === 'accident_minor'
              ? 'Zákazník nahlásil lehkou nehodu — motorka pojízdná, pokračuje v jízdě'
              : 'Zákazník nahlásil závažnou nehodu — čeká na pokyny',
          }).then(function(){});
        }
        if(sosType === 'accident_minor'){
          showT('✅', 'Děkujeme za nahlášení', 'Šťastnou cestu! 🏍️');
        } else {
          showT('✅', 'Incident nahlášen MotoGo24', ts + '\nAsistent vás kontaktuje.');
        }
        setTimeout(function(){ histBack(); }, 2000);
      });
}

function sosReportTheft() {
    var ts = new Date().toLocaleString('cs-CZ');
    _sosActiveIncidentId = null;
    _sosFault = null;
    _sosEnsureIncident('theft', 'Krádež motorky – zákazník informován o postupu (policie 158)')
      .then(function(incId){
        if(incId){
          _sosUpdateIncident(incId, { moto_rideable: false });
          window.supabase.from('sos_timeline').insert({
            incident_id: incId,
            action: 'Zákazník nahlásil krádež motorky — přesměrován na policii ČR (158)',
          }).then(function(){});
        }
        showT('🚨', 'Krádež nahlášena MotoGo24', ts + '\nVolejte policii 158!');
      });
}

// ===== SOS REPLACEMENT — přesměrování na Upravit rezervaci =====
var _sosReplacementMode = false;
var _sosReplacementData = { selectedMotoId: null, selectedModel: null, dailyPrice: 0, deliveryFee: 490 };

var _sosReplacementLoading = false;
function sosRequestReplacement() {
    if(_sosReplacementLoading) return; // guard against double-click
    _sosReplacementLoading = true;
    showT('⏳','Načítám...','Připravuji náhradní motorky');

    var faultDesc = _sosFault === true ? 'Nehoda byla moje chyba' : _sosFault === false ? 'Nehoda nebyla moje chyba' : '';
    var desc = 'Motorka nepojízdná – žádám náhradní motorku. ' + faultDesc;
    var type = _sosFault === true ? 'accident_major' : _sosFault === false ? 'accident_major' : 'breakdown_major';

    _sosEnsureIncident(type, desc).then(function(incId){
      _sosReplacementLoading = false;
      if(!incId){ showT('❌','Chyba','Nepodařilo se nahlásit incident'); return; }
      _sosPendingIncidentId = incId;
      var upd = {customer_decision:'replacement_moto', moto_rideable:false, replacement_status: 'selecting'};
      if(_sosFault !== null) upd.customer_fault = _sosFault;
      _sosUpdateIncident(incId, upd);
      _sosReplacementMode = true;
      // Přejdi na dedicated SOS replacement screen
      goTo('s-sos-replacement');
    }).catch(function(){ _sosReplacementLoading = false; });
}

function sosReplInit(){
    // Reset state
    _sosReplacementData = { selectedMotoId: null, selectedModel: null, dailyPrice: 0, deliveryFee: 490 };

    var isFault = _sosFault === true;
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
      // Najdi aktivní rezervaci a profil zákazníka
      var loan = await apiGetActiveLoan();
      var startDate = loan ? (loan.start_date || (loan._db && loan._db.start_date)) : null;
      var endDate = loan ? (loan.end_date || (loan._db && loan._db.end_date)) : null;
      var currentMotoId = loan ? (loan.moto_id || (loan._db && loan._db.moto_id)) : null;

      // Zjisti řidičák zákazníka
      var uid = null;
      try { var u = await window.supabase.auth.getUser(); uid = u.data && u.data.user ? u.data.user.id : null; } catch(e){}
      var customerLicense = null;
      if(uid){
        var pr = await window.supabase.from('profiles').select('license_group').eq('id', uid).single();
        if(pr.data && pr.data.license_group) customerLicense = pr.data.license_group; // array e.g. ['A'] or ['A2']
      }

      // Načti všechny motorky (ne jen active – zobrazit všechny dostupné)
      var r = await window.supabase.from('motorcycles')
        .select('id, model, image_url, images, daily_price, price_per_day, category, license_required, branches(name, city)')
        .in('status', ['active', 'available'])
        .limit(50);
      var allMotos = r.data || [];

      // Filtruj: 1) ne aktuální motorku, 2) zákazník má odpovídající řidičák
      var motos = allMotos.filter(function(m){
        // Vyřaď aktuální motorku zákazníka
        if(currentMotoId && m.id === currentMotoId) return false;
        // Zkontroluj řidičák – A zahrnuje A2, A2 nezahrnuje A
        if(customerLicense && m.license_required){
          var req = m.license_required; // e.g. 'A' or 'A2'
          var has = Array.isArray(customerLicense) ? customerLicense : [customerLicense];
          // A licence covers A, A2, A1, AM; A2 covers A2, A1, AM
          if(req === 'A' && has.indexOf('A') === -1) return false;
          if(req === 'A2' && has.indexOf('A') === -1 && has.indexOf('A2') === -1) return false;
        }
        return true;
      });

      // Zkontroluj dostupnost v termínu rezervace (vyřaď motorky s kolizí)
      if(startDate && endDate){
        var now = new Date().toISOString();
        var bookedR = await window.supabase.from('bookings')
          .select('moto_id')
          .in('status', ['active', 'confirmed', 'pending'])
          .in('payment_status', ['paid', 'pending'])
          .lt('start_date', endDate)
          .gt('end_date', now);
        var bookedMotoIds = {};
        if(bookedR.data){
          bookedR.data.forEach(function(b){ bookedMotoIds[b.moto_id] = true; });
        }
        motos = motos.filter(function(m){ return !bookedMotoIds[m.id]; });
      }

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

      var isFault = _sosFault === true;
      var html = '';
      motos.forEach(function(m){
        var price = m.daily_price || m.price_per_day || 890;
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
    var isFault = _sosFault === true;
    var summary = document.getElementById('sos-repl-summary');
    var totalEl = document.getElementById('sos-repl-total');

    var delivery = _sosReplacementData.deliveryFee;
    var daily = _sosReplacementData.dailyPrice;
    var days = _sosReplacementData._remainingDays || 1;
    var motoTotal = daily * days;
    var total = isFault ? (motoTotal + delivery) : 0;

    var daysLabel = days === 1 ? 'den' : days < 5 ? 'dny' : 'dní';

    if(summary){
      summary.innerHTML = '<div style="display:flex;justify-content:space-between;"><span>🏍️ ' + (_sosReplacementData.selectedModel || '—') + ' (' + days + ' ' + daysLabel + ' × ' + daily.toLocaleString('cs-CZ') + ' Kč)</span><span style="font-weight:800;">' + (isFault ? motoTotal.toLocaleString('cs-CZ') + ' Kč' : 'zdarma') + '</span></div>'
        + '<div style="display:flex;justify-content:space-between;margin-top:4px;"><span>🚛 Přistavení</span><span style="font-weight:800;">' + (isFault ? delivery.toLocaleString('cs-CZ') + ' Kč' : 'zdarma') + '</span></div>';
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
    navigator.geolocation.getCurrentPosition(function(pos){
      // Reverse geocode via Nominatim
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
        })
        .catch(function(){ showT('📍','GPS OK, adresu vyplňte ručně',''); });
    }, function(){ showT('❌','Poloha nedostupná','Vyplňte adresu ručně'); },
    {enableHighAccuracy:true, timeout:15000});
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

    var isFault = _sosFault === true;
    var daily = _sosReplacementData.dailyPrice;
    var delivery = _sosReplacementData.deliveryFee;
    var days = _sosReplacementData._remainingDays || 1;
    var motoTotal = daily * days;
    var total = isFault ? (motoTotal + delivery) : 0;

    var btn = document.getElementById('sos-repl-btn');
    if(btn){ btn.textContent = '⏳ Zpracovávám...'; btn.disabled = true; btn.style.opacity = '0.6'; }

    var replacementData = {
      replacement_moto_id: _sosReplacementData.selectedMotoId,
      replacement_model: _sosReplacementData.selectedModel,
      delivery_address: address,
      delivery_city: city,
      delivery_zip: zip,
      delivery_note: note,
      daily_price: daily,
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
      // Zákazník zavinil → musí zaplatit → zpracuj platbu
      try {
        var result = await apiProcessPayment(null, total, _currentPaymentMethod || 'card');
        if(result.success && result.checkout_url){
          // Stripe redirect
          replacementData.payment_status = 'processing';
          var upRes = await window.supabase.from('sos_incidents').update({
            replacement_status: 'pending_payment',
            replacement_data: replacementData
          }).eq('id', incId);
          if(upRes.error) console.error('[SOS] update pending_payment error:', upRes.error.message);
          if(window.cordova && window.cordova.InAppBrowser){
            window.cordova.InAppBrowser.open(result.checkout_url, '_system');
          } else {
            window.open(result.checkout_url, '_blank');
          }
          showT('ℹ️','Platba','Otevřena platební brána');
          if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit a objednat motorku'; }
          return;
        }
        if(result.success){
          replacementData.payment_status = 'paid';
          replacementData.paid_at = new Date().toISOString();
          var upRes2 = await window.supabase.from('sos_incidents').update({
            replacement_status: 'admin_review',
            replacement_data: replacementData
          }).eq('id', incId);
          if(upRes2.error) console.error('[SOS] update admin_review error:', upRes2.error.message);
          await window.supabase.from('sos_timeline').insert({
            incident_id: incId,
            action: 'Zákazník zaplatil ' + total + ' Kč a objednal náhradní motorku: ' + _sosReplacementData.selectedModel,
            description: 'Adresa: ' + address + ', ' + city + '. Čeká na schválení adminem.'
          });
          showT('✅','Zaplaceno — ' + total + ' Kč','Objednávka odeslána ke schválení. Kontaktujeme vás.');
          _sosPendingIncidentId = null;
          setTimeout(function(){ goTo('s-sos'); }, 3000);
        } else {
          console.error('[SOS] payment failed:', result);
          showT('❌','Platba zamítnuta','Zkuste to znovu');
          if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit a objednat motorku'; }
        }
      } catch(e){
        console.error('[SOS] payment exception:', e);
        showT('❌','Chyba platby','Zkuste to znovu');
        if(btn){ btn.disabled = false; btn.style.opacity = '1'; btn.textContent = '💳 Zaplatit a objednat motorku'; }
      }
    } else {
      // Porucha / nezaviněná → platba 0 Kč → rovnou do admin_review
      var upRes3 = await window.supabase.from('sos_incidents').update({
        replacement_status: 'admin_review',
        replacement_data: replacementData
      }).eq('id', incId);
      if(upRes3.error) console.error('[SOS] update admin_review (free) error:', upRes3.error.message);
      await window.supabase.from('sos_timeline').insert({
        incident_id: incId,
        action: 'Zákazník objednal náhradní motorku: ' + _sosReplacementData.selectedModel + ' (zdarma)',
        description: 'Adresa: ' + address + ', ' + city + '. Čeká na schválení adminem.'
      });
      apiSosRequestReplacement(incId);
      showT('✅','Objednávka odeslána','Náhradní motorka bude brzy přistavena (zdarma)');
      _sosPendingIncidentId = null;
      setTimeout(function(){ goTo('s-sos'); }, 2500);
    }
}

function sosEndRide() {
    showT('🚛', 'Objednávám odtah...', '');
    var faultDesc = _sosFault === true ? 'Nehoda byla moje chyba' : _sosFault === false ? 'Nehoda nebyla moje chyba' : '';
    var desc = 'Motorka nepojízdná – ukončuji jízdu, žádám odtah. ' + faultDesc;
    var type = _sosFault !== null ? 'accident_major' : 'breakdown_major';
    _sosEnsureIncident(type, desc).then(function(incId){
      if(!incId){ showT('❌','Chyba','Nepodařilo se nahlásit incident'); return; }
      var upd = {customer_decision:'end_ride', moto_rideable:false};
      if(_sosFault !== null) upd.customer_fault = _sosFault;
      _sosUpdateIncident(incId, upd);
      apiSosRequestTow(incId).then(function(){
        // Timeline entry s detaily
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: 'Zákazník ukončuje jízdu — žádá odtah' + (_sosFault === true ? ' (zavinil zákazník)' : _sosFault === false ? ' (cizí zavinění — zdarma)' : ''),
        }).then(function(){});
        showT('🚛', 'Odtah objednán', 'MotoGo24 zařídí odtah motorky');
        setTimeout(function(){ goTo('s-sos'); }, 2500);
      });
    });
}

function sosEndRideFree() {
    var desc = 'Porucha – motorka nepojízdná. Ukončuji jízdu, zařídím se sám.';
    _sosEnsureIncident('breakdown_major', desc).then(function(incId){
      if(incId){
        _sosUpdateIncident(incId, {customer_decision:'end_ride', moto_rideable:false, customer_fault:false});
        apiSosRequestTow(incId);
        // Timeline entry
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: 'Zákazník ukončuje jízdu — porucha (nezaviněná) — pronájem zdarma, odtah objednán',
        }).then(function(){});
      }
      showT('✅', 'Pronájem zdarma', 'Vracíme plnou částku. Odtah zajistíme.');
      setTimeout(function(){ goTo('s-home'); }, 2200);
    });
}

function sosShareLocation() {
    if (!navigator.geolocation) { showT('❌', 'GPS nedostupné', 'Váš prohlížeč nepodporuje GPS'); return; }
    showT('📍', 'Zjišťuji polohu...', 'Čekejte prosím');

    function _sendLocation(lat, lng) {
        apiGetMySosIncidents().then(function(incidents) {
            var latest = incidents && incidents.length ? incidents[0] : null;
            if (latest) {
                apiSosShareLocation(latest.id, lat, lng).then(function() {
                    showT('📍', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
                });
            } else {
                apiGetActiveLoan().then(function(loan) {
                    var loanId = loan ? loan.id : null;
                    apiCreateSosIncident('location_share', loanId, lat, lng, null, null).then(function() {
                        showT('📍', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
                    });
                });
            }
        });
    }

    // Try high accuracy first, fallback to low accuracy on timeout
    navigator.geolocation.getCurrentPosition(
        function(pos) { _sendLocation(pos.coords.latitude, pos.coords.longitude); },
        function(err) {
            if (err.code === 1) { showT('❌', 'Přístup odepřen', 'Povolte polohu v nastavení'); return; }
            showT('📍', 'Hledám polohu...', 'Zkouším alternativní metodu');
            navigator.geolocation.getCurrentPosition(
                function(pos) { _sendLocation(pos.coords.latitude, pos.coords.longitude); },
                function(err2) {
                    if (err2.code === 1) showT('❌', 'Přístup odepřen', 'Povolte polohu v nastavení');
                    else if (err2.code === 2) showT('❌', 'GPS nedostupné', 'Zkuste to venku nebo povolte polohu');
                    else showT('❌', 'Časový limit', 'GPS neodpovědělo – zkuste to venku');
                },
                { enableHighAccuracy: false, timeout: 20000, maximumAge: 60000 }
            );
        },
        { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 }
    );
}

function sosDrobnaZavada() {
    showT('🔩', 'Hlásím závadu...', '');
    _sosActiveIncidentId = null;
    _sosFault = null;
    _sosEnsureIncident('breakdown_minor', 'Drobná závada – motorka pojízdná, pokračuji v jízdě').then(function(incId){
      if(incId){
        _sosUpdateIncident(incId, { moto_rideable: true, customer_fault: false, customer_decision: 'continue' });
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: 'Zákazník nahlásil drobnou závadu — motorka pojízdná, pokračuje v jízdě',
        }).then(function(){});
      }
      showT('✅', 'Děkujeme za nahlášení', 'Šťastnou cestu! 🏍️');
      setTimeout(function(){ histBack(); }, 1600);
    });
}

// ===== AI CHAT =====
function aiGetResponse(txt){
  const lc=txt.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
  // scan knowledge base
  for(const entry of AI_KB){
    for(const key of entry.keys){
      const kn=key.normalize('NFD').replace(/[\u0300-\u036f]/g,'');
      if(lc.includes(kn)) return entry.ans;
    }
  }
  return 'Rozumím. Pro tento problém doporučuji otevřít manuál v detailu motorky, nebo kontaktujte naši linku +420 774 256 271. Jsme tu 24/7! Zkuste popsat konkrétněji – např. "červená kontrolka", "kde je baterie BMW", "nechce nastartovat".';
}
function aiSend(textOverride){
  const inp=document.getElementById('ai-chat-inp');
  const msgs=document.getElementById('ai-chat-msgs');
  if(!msgs)return;
  const txt=(textOverride||inp?.value||'').trim();
  if(!txt)return;
  msgs.innerHTML+=`<div class="ai-msg user"><div class="ai-bubble">${txt}</div></div>`;
  if(inp)inp.value='';
  msgs.scrollTop=msgs.scrollHeight;
  // Typing indicator
  const typId='ai-typing-'+Date.now();
  msgs.innerHTML+=`<div class="ai-msg bot" id="${typId}"><div class="ai-bubble" style="color:var(--g400);">⏳ Hledám v manuálech...</div></div>`;
  msgs.scrollTop=msgs.scrollHeight;
  setTimeout(()=>{
    const resp=aiGetResponse(txt);
    const typEl=document.getElementById(typId);
    if(typEl)typEl.querySelector('.ai-bubble').innerHTML=resp.replace(/\n/g,'<br>');
    msgs.scrollTop=msgs.scrollHeight;
  },700);
}

// ===== MIKROFON / SPEECH RECOGNITION =====
let aiMicActive=false;
let aiRecognition=null;
function aiToggleMic(){
  const btn=document.getElementById('ai-mic-btn');
  const status=document.getElementById('ai-mic-status');
  if(aiMicActive){
    // stop
    if(aiRecognition)aiRecognition.stop();
    aiMicActive=false;
    if(btn){btn.style.background='var(--g100)';btn.style.borderColor='var(--g200)';btn.textContent='🎤';}
    if(status)status.style.display='none';
    return;
  }
  // Request mic permission
  const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
  if(!SR){
    showT('❌',_t('sos').voiceInput||'Hlasový vstup',_t('sos').browserNoSpeech||'Váš prohlížeč nepodporuje rozpoznávání řeči');
    return;
  }

  function _startRecognition(){
    aiRecognition=new SR();
    aiRecognition.lang='cs-CZ';
    aiRecognition.continuous=false;
    aiRecognition.interimResults=false;
    aiRecognition.onstart=()=>{
      aiMicActive=true;
      if(btn){btn.style.background='#fee2e2';btn.style.borderColor='var(--red)';btn.textContent='⏹️';}
      if(status)status.style.display='block';
    };
    aiRecognition.onresult=(e)=>{
      const transcript=e.results[0][0].transcript;
      const inp=document.getElementById('ai-chat-inp');
      if(inp)inp.value=transcript;
      showT('🎤',_t('sos').recognized||'Rozpoznáno',transcript.substring(0,40));
    };
    aiRecognition.onend=()=>{
      aiMicActive=false;
      if(btn){btn.style.background='var(--g100)';btn.style.borderColor='var(--g200)';btn.textContent='🎤';}
      if(status)status.style.display='none';
      setTimeout(()=>aiSend(),300);
    };
    aiRecognition.onerror=(e)=>{
      aiMicActive=false;
      if(btn){btn.style.background='var(--g100)';btn.style.borderColor='var(--g200)';btn.textContent='🎤';}
      if(status)status.style.display='none';
      if(e.error==='not-allowed')showT('❌',_t('sos').mic||'Mikrofon',_t('sos').micDenied||'Přístup k mikrofonu odepřen');
      else if(e.error==='network')showT('⚠️',_t('sos').voiceInput||'Hlasový vstup','Chyba sítě – zkuste znovu');
      else showT('⚠️',_t('sos').voiceInput||'Hlasový vstup',_t('sos').soundFailed||'Rozpoznávání selhalo – zkuste znovu');
    };
    aiRecognition.start();
  }

  // Try getUserMedia first for permission, fallback to direct start
  if(navigator.mediaDevices && navigator.mediaDevices.getUserMedia){
    navigator.mediaDevices.getUserMedia({audio:true}).then(function(stream){
      // Stop the stream immediately, we just needed the permission
      stream.getTracks().forEach(function(t){t.stop();});
      _startRecognition();
    }).catch(function(){
      // On some devices getUserMedia fails but SpeechRecognition works
      try { _startRecognition(); }
      catch(e){ showT('❌',_t('sos').mic||'Mikrofon',_t('sos').micAllow||'Povolte mikrofon v nastavení'); }
    });
  } else {
    // No getUserMedia (HTTP or old browser) – try starting recognition directly
    try { _startRecognition(); }
    catch(e){ showT('❌',_t('sos').mic||'Mikrofon',_t('sos').micAllow||'Povolte mikrofon v nastavení'); }
  }
}

// ===== CUSTOM DATE PICKER =====
var _dpTarget=null;
var _dpY=2000,_dpM=0,_dpMode='day',_dpYBase=2000;
var _dpCallback=null;
function openDatePicker(inp){
  _dpCallback=null;_dpMode='day';
  _dpTarget=inp;
  var val=inp.value;
  if(val&&/\d{1,2}\.\s?\d{1,2}\.\s?\d{4}/.test(val)){
    var pts=val.split('.');_dpY=parseInt(pts[2]);_dpM=parseInt(pts[1])-1;
  } else {var n=new Date();_dpY=n.getFullYear();_dpM=n.getMonth();}
  var ov=document.getElementById('dp-overlay');
  if(!ov){ov=document.createElement('div');ov.id='dp-overlay';ov.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;padding:16px;';document.querySelector('.phone').appendChild(ov);}
  ov.style.display='flex';renderDP();
}
function openSearchDP(type){
  _dpTarget=null;_dpMode='day';
  _dpCallback=function(d,m,y){
    var val=y+'-'+String(m+1).padStart(2,'0')+'-'+String(d).padStart(2,'0');
    setSearchDateFromInput(type,val);
  };
  var n=new Date();_dpY=n.getFullYear();_dpM=n.getMonth();
  if(type==='do'&&typeof sOd!=='undefined'&&sOd){_dpY=sOd.y;_dpM=sOd.m;}
  var ov=document.getElementById('dp-overlay');
  if(!ov){ov=document.createElement('div');ov.id='dp-overlay';ov.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;padding:16px;';document.querySelector('.phone').appendChild(ov);}
  ov.style.display='flex';renderDP();
}
function renderDP(){
  var ov=document.getElementById('dp-overlay');if(!ov)return;
  if(_dpMode==='year'){renderDPYear();return;}
  var dim=new Date(_dpY,_dpM+1,0).getDate();
  var fd=new Date(_dpY,_dpM,1).getDay();fd=fd===0?6:fd-1;
  var now=new Date();now.setHours(0,0,0,0);
  var h='<div style="background:#fff;border-radius:18px;padding:18px;max-width:320px;width:100%;">'+
    '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">'+
    '<button onclick="_dpM--;if(_dpM<0){_dpM=11;_dpY--;}renderDP()" style="background:var(--g100);border:none;border-radius:8px;width:32px;height:32px;font-size:16px;cursor:pointer;">‹</button>'+
    '<div style="font-size:14px;font-weight:800;color:var(--black);">'+MONTHS[_dpM]+' <span onclick="_dpYBase=_dpY-_dpY%12;_dpMode=\'year\';renderDP()" style="cursor:pointer;text-decoration:underline dotted;text-underline-offset:3px;">'+_dpY+'</span></div>'+
    '<button onclick="_dpM++;if(_dpM>11){_dpM=0;_dpY++;}renderDP()" style="background:var(--g100);border:none;border-radius:8px;width:32px;height:32px;font-size:16px;cursor:pointer;">›</button></div>'+
    '<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:2px;text-align:center;font-size:10px;color:var(--g400);font-weight:700;margin-bottom:4px;">'+
    '<div>Po</div><div>Út</div><div>St</div><div>Čt</div><div>Pá</div><div>So</div><div>Ne</div></div>'+
    '<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:2px;">';
  for(var i=0;i<fd;i++)h+='<div></div>';
  for(var d=1;d<=dim;d++){
    var isPast=_dpCallback&&(new Date(_dpY,_dpM,d)<now);
    if(isPast){h+='<div style="text-align:center;padding:8px 0;font-size:13px;font-weight:600;border-radius:8px;color:var(--g400);opacity:.35;">'+d+'</div>';}
    else{h+='<div onclick="pickDP('+d+')" style="text-align:center;padding:8px 0;font-size:13px;font-weight:600;border-radius:8px;cursor:pointer;color:var(--black);background:'+(_dpCallback?'#bbf7d0':'var(--g100)')+';">'+d+'</div>';}
  }
  h+='</div><button onclick="closeDP()" style="width:100%;margin-top:12px;background:var(--g100);border:none;border-radius:10px;padding:10px;font-family:var(--font);font-size:13px;font-weight:600;cursor:pointer;color:var(--g400);">'+_t('common').cancel+'</button></div>';
  ov.innerHTML=h;
}
function renderDPYear(){
  var ov=document.getElementById('dp-overlay');if(!ov)return;
  var h='<div style="background:#fff;border-radius:18px;padding:18px;max-width:320px;width:100%;">'+
    '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">'+
    '<button onclick="_dpYBase-=12;renderDP()" style="background:var(--g100);border:none;border-radius:8px;width:32px;height:32px;font-size:16px;cursor:pointer;">‹</button>'+
    '<div style="font-size:14px;font-weight:800;color:var(--black);">'+_dpYBase+' – '+(_dpYBase+11)+'</div>'+
    '<button onclick="_dpYBase+=12;renderDP()" style="background:var(--g100);border:none;border-radius:8px;width:32px;height:32px;font-size:16px;cursor:pointer;">›</button></div>'+
    '<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:6px;">';
  for(var i=0;i<12;i++){
    var y=_dpYBase+i,sel=y===_dpY;
    h+='<div onclick="_dpY='+y+';_dpMode=\'day\';renderDP()" style="text-align:center;padding:12px 0;font-size:14px;font-weight:'+(sel?'800':'600')+';border-radius:10px;cursor:pointer;background:'+(sel?'var(--green)':'var(--g100)')+';color:'+(sel?'#fff':'var(--black)')+';">'+y+'</div>';
  }
  h+='</div><button onclick="_dpMode=\'day\';renderDP()" style="width:100%;margin-top:12px;background:var(--g100);border:none;border-radius:10px;padding:10px;font-family:var(--font);font-size:13px;font-weight:600;cursor:pointer;color:var(--g400);">'+_t('common').back+'</button></div>';
  ov.innerHTML=h;
}
function pickDP(d){
  if(_dpCallback){_dpCallback(d,_dpM,_dpY);}
  else if(_dpTarget){_dpTarget.value=d+'. '+(_dpM+1)+'. '+_dpY;_dpTarget.dispatchEvent(new Event('change'));}
  closeDP();
}
function closeDP(){var ov=document.getElementById('dp-overlay');if(ov)ov.style.display='none';}

// ===== EXPAND =====
function toggleExpand(expId,arrId){
  const exp=document.getElementById(expId);
  const arr=document.getElementById(arrId);
  const isOpen=exp.classList.contains('open');
  exp.classList.toggle('open',!isOpen);
  if(arr)arr.textContent=isOpen?'›':'∨';
}

// ===== DOCS =====
let docType='op',docCaps={op:null,pas:null,rp:null};
function _switchDocTab(t){
  docType=t;
  document.getElementById('dtab-id').classList.toggle('on',t==='op');
  document.getElementById('dtab-pas').classList.toggle('on',t==='pas');
  document.getElementById('dtab-rp').classList.toggle('on',t==='rp');
  renderDocs();
}
function switchDoc(t){_switchDocTab(t);}
function _handleDocFile(e,label){
  const f=e.target.files[0];if(!f)return;
  const r=new FileReader();
  r.onload=ev=>{docCaps[docType]=ev.target.result;renderDocs();showT('📋',_t('scan').docScanned,label);};
  r.readAsDataURL(f);e.target.value='';
}
function handleDocCap(e){_handleDocFile(e,_t('scan').scanned);}
function handleDocUp(e){
  // If called with file input event, use it
  if(e&&e.target&&e.target.files){_handleDocFile(e,_t('scan').uploaded);return;}
  // Cordova: use cordova-plugin-camera to pick from gallery
  if(navigator.camera){
    navigator.camera.getPicture(
      function(dataUrl){
        docCaps[docType]='data:image/jpeg;base64,'+dataUrl;
        renderDocs();
        showT('📋',_t('scan').docScanned||'Doklad nahrán',_t('scan').uploaded||'Uloženo');
      },
      function(err){
        if(err&&err.indexOf&&err.indexOf('cancel')!==-1) return;
        showT('❌','Galerie','Nepodařilo se vybrat snímek');
      },
      {quality:85,destinationType:0,sourceType:0,correctOrientation:true,targetWidth:1200,targetHeight:1600}
    );
    return;
  }
  // Browser fallback: open file picker
  var inp=document.createElement('input');
  inp.type='file';inp.accept='image/*';
  inp.onchange=function(ev){_handleDocFile(ev,_t('scan').uploaded||'Nahráno');};
  inp.click();
}
function renderDocs(){
  const labels={op:'🪪 Občanský průkaz',pas:'📕 Cestovní pas',rp:'🏍️ Řidičský průkaz'};
  var scanMap={op:'mg_doc_id_front',pas:'mg_doc_passport_front',rp:'mg_doc_dl_front'};
  for(var sk in scanMap){
    if(!docCaps[sk]){
      try{ var sv=localStorage.getItem(scanMap[sk]); if(sv) docCaps[sk]=sv; }catch(e){}
    }
  }
  var docCount = Object.values(docCaps).filter(function(v){return !!v;}).length;
  var html='';
  if(docCount > 0){
    html += '<div style="background:#ecfdf5;border:1px solid #6ee7b7;border-radius:12px;padding:12px 16px;margin-bottom:12px;display:flex;align-items:center;gap:10px;">' +
      '<span style="font-size:22px;">✅</span>' +
      '<div><div style="font-size:14px;font-weight:700;color:#065f46;">Doklady nahrány ('+docCount+')</div>' +
      '<div style="font-size:12px;color:#047857;">Uloženo v zařízení</div></div></div>';
  }
  html += Object.entries(docCaps).filter(([,v])=>v).map(([k,v])=>
    `<div class="dprev"><img src="${v}"><div class="dprev-lbl">${labels[k]}</div><button class="dprev-del" onclick="docCaps['${k}']=null;renderDocs()">✕</button></div>`
  ).join('');
  document.getElementById('doc-prev').innerHTML=html;
  var wrap=document.getElementById('doc-area-wrap');
  if(wrap) wrap.style.display=html?'':'none';
}

// ===== ONLINE DOT SIMULATION =====
// Toggle online/offline status for demo
let isOnline=true;
setInterval(()=>{
  // Simulate brief offline moments
  if(Math.random()<0.05){
    isOnline=false;
    const dot=document.getElementById('online-dot');
    if(dot){dot.classList.add('offline');dot.title='Offline – bez připojení';}
    setTimeout(()=>{
      isOnline=true;
      const dot2=document.getElementById('online-dot');
      if(dot2){dot2.classList.remove('offline');dot2.title='Online';}
    },2000);
  }
},8000);

// savePersonalData, deleteAccount → js/storage.js

// ===== SHARE LOCATION =====
function shareLocation(){
  if(!navigator.geolocation){showT('❌',_t('sos').gpsUnavailable,_t('sos').browserNoGPS);return;}
  showT('📍',_t('sos').locating,_t('sos').pleaseWait);
  navigator.geolocation.getCurrentPosition(
    pos=>{const lat=pos.coords.latitude.toFixed(5),lng=pos.coords.longitude.toFixed(5);showT('📍',_t('sos').locationShared,lat+', '+lng);},
    err=>{
      if(err.code===1)showT('❌',_t('sos').accessDenied,_t('sos').allowLocation);
      else showT('❌',_t('sos').gpsUnavailable,_t('sos').cannotGetLocation);
    },
    {enableHighAccuracy:true,timeout:15000,maximumAge:0}
  );
}

// ===== REPORT MINOR ACCIDENT =====
function reportMinorAccident(){
  const ts=new Date().toLocaleString('cs-CZ');
  showT('🟡',_t('sos').incidentRecorded,ts);
}

// ===== NEHODA / NEPOJIZDA =====
function setNehoda(vinik){
  const bv=document.getElementById('btn-vinik');
  const bn=document.getElementById('btn-nevinik');
  const info=document.getElementById('nehoda-nahrada');
  if(vinik){
    if(bv){bv.style.background='#b91c1c';bv.style.color='#fff';bv.style.border='none';}
    if(bn){bn.style.background='var(--g100)';bn.style.color='var(--black)';bn.style.border='2px solid var(--g200)';}
    if(info)info.innerHTML='<div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:var(--rsm);padding:10px 12px;font-size:12px;font-weight:600;color:#b91c1c;line-height:1.6;width:100%;">⚠️ '+_t('sos').faultVinikMsg+'</div>';
  } else {
    if(bn){bn.style.background='var(--green)';bn.style.color='#fff';bn.style.border='none';}
    if(bv){bv.style.background='var(--g100)';bv.style.color='var(--black)';bv.style.border='2px solid var(--g200)';}
    if(info)info.innerHTML='<div style="background:var(--gp);border:1px solid var(--green);border-radius:var(--rsm);padding:10px 12px;font-size:12px;font-weight:600;color:var(--gd);line-height:1.6;width:100%;">💚 '+_t('sos').faultNevinikMsg+'</div>';
  }
}
function setNepojizda(vinik){
  _sosFault = vinik;
  _sosActiveIncidentId = null;
  const bv=document.getElementById('btn-nepoj-vinik');
  const bn=document.getElementById('btn-nepoj-nevinik');
  const info=document.getElementById('nepojizda-info');
  const tit=document.getElementById('nahr-title');
  const sub=document.getElementById('nahr-sub');
  if(vinik){
    if(bv){bv.style.background='#b91c1c';bv.style.color='#fff';bv.style.border='none';}
    if(bn){bn.style.background='var(--g100)';bn.style.color='var(--black)';bn.style.border='2px solid var(--g200)';}
    if(info)info.innerHTML='<div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:var(--rsm);padding:10px 12px;font-size:12px;font-weight:600;color:#b91c1c;line-height:1.6;">⚠️ '+_t('sos').nepojVinikMsg+'</div>';
    if(tit)tit.innerHTML=_t('sos').replacementFee;
    if(sub)sub.textContent=_t('sos').deliveryFee;
  } else {
    if(bn){bn.style.background='var(--green)';bn.style.color='#fff';bn.style.border='none';}
    if(bv){bv.style.background='var(--g100)';bv.style.color='var(--black)';bv.style.border='2px solid var(--g200)';}
    if(info)info.innerHTML='<div style="background:var(--gp);border:1px solid var(--green);border-radius:var(--rsm);padding:10px 12px;font-size:12px;font-weight:600;color:var(--gd);line-height:1.6;">💚 '+_t('sos').nepojNevinikMsg+'</div>';
    if(tit)tit.innerHTML=_t('sos').replacementFree;
    if(sub)sub.textContent=_t('sos').deliveryFree;
  }
}

// ===== SOS NEARBY SERVIS =====
function sosNearbyServis(){
  showT('📍',_t('sos').searchService,_t('sos').openMaps);
  setTimeout(()=>window.open('https://www.google.com/maps/search/motocyklový+servis+nearby','_blank'),800);
}

// ===== RATE RIDE =====
var _currentRating=5;
function rateRide(val){
  _currentRating=val;
  document.querySelectorAll('.star-btn').forEach((s,i)=>{
    s.style.color=i<val?'#f59e0b':'#d1d5db';
    s.style.transform=i<val?'scale(1.15)':'scale(1)';
  });
  const msgs=['','😞 '+_t('res').badExp,'😐 '+_t('res').average,'🙂 '+_t('res').good,'😊 '+_t('res').veryGood,'🏆 '+_t('res').excellent];
  const msg=document.getElementById('done-rating-msg');
  if(msg)msg.textContent=msgs[val]||'';
  // Save rating to DB
  if(_currentResId && _isSupabaseReady()){
    supabase.from('bookings').update({rating:val,rated_at:new Date().toISOString()}).eq('id',_currentResId)
      .then(()=>{}).catch(e=>console.warn('[RATE]',e));
  }
  showT('⭐',_t('res').thankStars.replace('{n}',val),_t('res').feedbackHelps);
}

// ===== DIGITÁLNÍ PŘEDÁVACÍ PROTOKOL JS =====
let protocolSigned=false;
function signProtocol(method){
  if(method==='biometric'){
    // Simulate biometric
    showT('🔐',_t('sos').verifying,_t('sos').bioVerification);
    setTimeout(()=>finalizeSignature(),1200);
  } else {
    document.getElementById('pin-input-wrap').style.display='block';
  }
}
function confirmPin(){
  const pin=document.getElementById('proto-pin')?.value||'';
  if(pin.length<4){showT('⚠️',_t('sos').pin,_t('sos').enterPin);return;}
  finalizeSignature();
}
function finalizeSignature(){
  protocolSigned=true;
  const now=new Date().toLocaleString('cs-CZ');
  const pinWrap=document.getElementById('pin-input-wrap');
  if(pinWrap) pinWrap.style.display='none';
  const signed=document.getElementById('proto-signed');
  if(signed) signed.style.display='block';
  const time=document.getElementById('proto-signed-time');
  var _signerName=(document.getElementById('home-user-name')&&document.getElementById('home-user-name').textContent)||'';
  if(time) time.textContent='Podepsáno: '+now+(_signerName?' · '+_signerName:'');
  showT('✅',_t('sos').sigConfirmed,_t('sos').protocolSigned);
}
function submitProtocol(){
  if(!protocolSigned){showT('⚠️',_t('sos').sigConfirmed,_t('sos').signFirst);return;}
  showT('📤',_t('sos').submitted,_t('sos').protocolSent);
  setTimeout(()=>histBack(),1500);
}

// ===== STORNO DIALOG =====
function openStornoDialog(bookingId){
  var bid = bookingId || (typeof _currentResId !== 'undefined' ? _currentResId : null);
  if(!bid){ showT('✗',_t('common').error,_t('sos').noResToCancel); return; }
  if(typeof doCancelBooking === 'function'){ doCancelBooking(bid); return; }
}

// ===== ZAHRANIČNÍ JÍZDA =====
function toggleForeign(cb){
  const det=document.getElementById('foreign-detail');
  if(det) det.style.display=cb.checked?'block':'none';
}

// ===== DIGITÁLNÍ PŘEDÁVACÍ PROTOKOL =====
function showDigitalProtocol(){
  goTo('s-protocol');
}

// ===== EXTERNAL LINKS =====
function openExternalLink(url){
  if(!url) return;
  // On Capacitor (native), use Browser plugin or system browser
  if(typeof Capacitor !== 'undefined' && Capacitor.isNativePlatform && Capacitor.isNativePlatform()){
    if(typeof Browser !== 'undefined' && Browser.open){
      Browser.open({ url: url });
    } else {
      window.open(url, '_system');
    }
  } else {
    // Web: open in new tab
    window.open(url, '_blank', 'noopener,noreferrer');
  }
}

// ===== CONTACT DETAILS TOGGLE =====
function toggleContactDetails(){
  var exp=document.getElementById('contact-expanded');
  var arr=document.getElementById('contact-arrow');
  if(!exp)return;
  if(exp.style.display==='none'){
    exp.style.display='block';
    if(arr)arr.style.transform='rotate(90deg)';
  } else {
    exp.style.display='none';
    if(arr)arr.style.transform='rotate(0deg)';
  }
}

// ===== SCROLL TO TOP =====
function scrollCurrentToTop(){
  var s=document.getElementById(cur);
  if(s) s.scrollTo({top:0,behavior:'smooth'});
}
function initScrollTop(){
  var btn=document.getElementById('scroll-top-btn');
  if(!btn) return;
  // Capture scroll events on all screens via event delegation
  document.querySelector('.phone').addEventListener('scroll',function(e){
    var target=e.target;
    if(target && target.classList && target.classList.contains('screen') && target.id===cur){
      btn.classList.toggle('visible', target.scrollTop > 300);
    }
  }, true);
  btn.onclick = function(e){
    e.preventDefault();
    e.stopPropagation();
    var s=document.getElementById(cur);
    if(s) s.scrollTo({top:0,behavior:'smooth'});
  };
}
