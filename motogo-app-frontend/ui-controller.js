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
var _sosFaultSnapshot = null;      // Persisted fault state (survives async operations)
var _sosActiveIncidentId = null;
var _sosPendingIncidentId = null;  // Incident čekající na platbu (zaviněná nehoda)
var _sosSubmitting = false;        // Guard against double-tap
var _sosCurrentBookingId = null;   // ID aktivní rezervace pro SOS

// Check for active SOS incident and show banner on SOS entry screen
function _sosCheckActiveIncident(){
  if(!window.supabase) return;
  (async function(){
    try {
      var uid = await _getUserId();
      if(!uid) return;
      var r = await window.supabase.from('sos_incidents')
        .select('id, type, status, created_at, replacement_status')
        .eq('user_id', uid)
        .not('status', 'in', '("resolved","closed")')
        .not('type', 'in', '("breakdown_minor","defect_question","location_share","other")')
        .order('created_at', {ascending: false})
        .limit(1);
      var sosScreen = document.getElementById('s-sos');
      var existing = document.getElementById('sos-active-banner');
      if(existing) existing.remove();
      if(r.data && r.data.length > 0){
        var inc = r.data[0];
        _sosActiveIncidentId = inc.id;
        var banner = document.createElement('div');
        banner.id = 'sos-active-banner';
        banner.style.cssText = 'margin:0 20px 10px;padding:12px 14px;border-radius:12px;background:#fef3c7;border:2px solid #fde68a;';
        var statusMap = {reported:'Nahlášeno',acknowledged:'Přijato',in_progress:'Řeší se'};
        var statusLabel = statusMap[inc.status] || inc.status;
        banner.innerHTML = '<div style="font-size:13px;font-weight:800;color:#92400e;">⚠️ Máte aktivní SOS incident</div>' +
          '<div style="font-size:11px;color:#78350f;margin-top:3px;line-height:1.5;">Stav: ' + statusLabel + ' · ID: #' + inc.id.substr(-8).toUpperCase() + '<br>Dokud nebude vyřešen, nelze vytvořit nový SOS incident.</div>' +
          (inc.replacement_status ? '<div style="font-size:11px;color:#78350f;margin-top:4px;">Náhradní moto: ' + inc.replacement_status + '</div>' : '') +
          '<button onclick="goTo(\'s-sos-nepojizda\')" style="margin-top:8px;width:100%;background:#b45309;color:#fff;border:none;border-radius:50px;padding:10px;font-family:var(--font);font-size:12px;font-weight:700;cursor:pointer;">🏍️ Pokračovat v řešení incidentu</button>';
        if(sosScreen){
          var insertPoint = sosScreen.querySelector('[style*="padding:14px 20px"]');
          if(insertPoint) insertPoint.prepend(banner);
          else sosScreen.appendChild(banner);
        }
      }
    } catch(e){ console.warn('[SOS] checkActive:', e); }
  })();
}

// Pre-fetch active booking & moto IDs when entering any SOS screen
function _sosPreFetchIds(){
  if(_sosCurrentBookingId && _sosCurrentMotoId) return; // already fetched
  (async function(){
    try {
      var uid = null;
      try { var u = await window.supabase.auth.getUser(); uid = u.data && u.data.user ? u.data.user.id : null; } catch(e){}
      if(!uid) return;
      var bk = await window.supabase.from('bookings')
        .select('id, moto_id')
        .eq('user_id', uid)
        .in('status', ['active', 'confirmed', 'pending', 'reserved'])
        .lte('start_date', new Date().toISOString())
        .gte('end_date', new Date().toISOString())
        .limit(1);
      if(bk.data && bk.data.length > 0){
        if(!_sosCurrentBookingId) _sosCurrentBookingId = bk.data[0].id;
        if(!_sosCurrentMotoId) _sosCurrentMotoId = bk.data[0].moto_id;
      }
    } catch(e){ console.warn('[SOS] pre-fetch IDs:', e); }
  })();
}

function _sosShowDone(typeLabel, nextInfo, actionButtons) {
  goTo('s-sos-done');
  setTimeout(function(){
    var detail = document.getElementById('sos-done-detail');
    var next = document.getElementById('sos-done-next');
    var actions = document.getElementById('sos-done-actions');
    if(detail) detail.innerHTML = '<div style="font-size:13px;font-weight:800;color:var(--black);">' + (typeLabel || 'Incident') + '</div>' +
      '<div style="font-size:12px;color:var(--g400);margin-top:4px;">' + new Date().toLocaleString('cs-CZ') + '</div>';
    if(next) next.innerHTML = nextInfo || 'Asistent MotoGo24 vás bude kontaktovat.';
    if(actions) actions.innerHTML = actionButtons || '';
  }, 100);
}

function _sosGetGPS(){
  return new Promise(function(resolve){
    if(!navigator.geolocation){ resolve({lat:null,lng:null}); return; }
    navigator.geolocation.getCurrentPosition(
      function(pos){ resolve({lat:pos.coords.latitude,lng:pos.coords.longitude}); },
      function(){
        // Fallback: try low accuracy
        navigator.geolocation.getCurrentPosition(
          function(pos){ resolve({lat:pos.coords.latitude,lng:pos.coords.longitude}); },
          function(){ resolve({lat:null,lng:null}); },
          {enableHighAccuracy:false,timeout:30000,maximumAge:60000}
        );
      },
      {enableHighAccuracy:true,timeout:30000}
    );
  });
}

function _sosEnsureIncident(type, desc){
  return new Promise(function(resolve){
    if(_sosActiveIncidentId){
      // Verify the incident is still active (not resolved/closed by admin)
      if(window.supabase){
        window.supabase.from('sos_incidents').select('id,status,type').eq('id', _sosActiveIncidentId).single()
          .then(async function(r){
            if(r.data && !['resolved','closed'].includes(r.data.status)){
              // Update type if flow changed
              if(r.data.type !== type){
                await window.supabase.from('sos_incidents').update({type: type, description: desc, title: desc}).eq('id', _sosActiveIncidentId);
                await window.supabase.from('sos_timeline').insert({
                  incident_id: _sosActiveIncidentId,
                  action: 'Typ incidentu změněn: ' + r.data.type + ' → ' + type,
                });
              }
              resolve(_sosActiveIncidentId);
            } else {
              _sosActiveIncidentId = null;
              _sosEnsureIncident(type, desc).then(resolve);
            }
          }).catch(function(){ resolve(_sosActiveIncidentId); });
        return;
      }
      resolve(_sosActiveIncidentId); return;
    }

    // Check DB for existing unresolved serious incident on same booking
    if(window.supabase){
      (async function(){
        try {
          var uid = await _getUserId();
          if(uid){
            // Find active booking first
            var activeBookingId = _sosCurrentBookingId || null;
            if(!activeBookingId){
              try {
                var loan = await apiGetActiveLoan();
                if(loan) activeBookingId = loan.id || (loan._db && loan._db.id) || null;
              } catch(e){}
            }
            // Check for existing serious incident on same booking
            var existingQ = window.supabase.from('sos_incidents')
              .select('id, status, type, booking_id')
              .eq('user_id', uid)
              .not('status', 'in', '("resolved","closed")')
              .not('type', 'in', '("breakdown_minor","defect_question","location_share","other")')
              .order('created_at', {ascending: false})
              .limit(1);
            if(activeBookingId) existingQ = existingQ.eq('booking_id', activeBookingId);
            var existing = await existingQ;
            if(existing.data && existing.data.length > 0){
              // Always ask for confirmation — even when reusing existing incident
              if(!confirm('Opravdu chcete nahlásit SOS incident?\n\nPo potvrzení bude informována centrála MotoGo24.')){
                resolve(null); return;
              }
              _sosActiveIncidentId = existing.data[0].id;
              // Update type if the flow changed (e.g. user started with minor, now doing major)
              var existingType = existing.data[0].type;
              if(existingType !== type){
                await window.supabase.from('sos_incidents').update({type: type, description: desc, title: desc}).eq('id', _sosActiveIncidentId);
                await window.supabase.from('sos_timeline').insert({
                  incident_id: _sosActiveIncidentId,
                  action: 'Typ incidentu změněn: ' + existingType + ' → ' + type,
                });
              }
              showT('ℹ️','Aktivní incident','Pokračujete v existujícím SOS incidentu');
              resolve(_sosActiveIncidentId);
              return;
            }
          }
        } catch(e){ console.warn('[SOS] check existing:', e); }

        // No existing incident — ask confirmation and create new
        if(!confirm('Opravdu chcete nahlásit SOS incident?\n\nPo potvrzení bude informována centrála MotoGo24.')){
          resolve(null); return;
        }
        showT('⚠️','Hlásím incident...','Odesílám na centrálu');

        // Use pre-fetched IDs as fallback
        var bookingId = _sosCurrentBookingId || null;
        var motoId = _sosCurrentMotoId || null;

        // Try apiGetActiveLoan for more complete booking data
        try {
          var loan = await apiGetActiveLoan();
          if(loan){
            bookingId = loan.id || (loan._db && loan._db.id) || bookingId;
            motoId = loan.moto_id || motoId;
          }
        } catch(e){ console.warn('[SOS] getLoan:', e); }

        // Broader search if still no booking
        if(!bookingId || !motoId){
          try {
            var uid2 = await _getUserId();
            if(uid2){
              // 1) Try exact date range match
              var bk = await window.supabase.from('bookings')
                .select('id, moto_id')
                .eq('user_id', uid2)
                .in('status', ['active', 'confirmed', 'pending', 'reserved'])
                .lte('start_date', new Date().toISOString())
                .gte('end_date', new Date().toISOString())
                .limit(1);
              if(bk.data && bk.data.length > 0){
                bookingId = bookingId || bk.data[0].id;
                motoId = motoId || bk.data[0].moto_id;
              }
              // 2) Fallback: most recent paid booking (any active/reserved)
              if(!bookingId || !motoId){
                var bk2 = await window.supabase.from('bookings')
                  .select('id, moto_id')
                  .eq('user_id', uid2)
                  .in('status', ['active', 'reserved'])
                  .eq('payment_status', 'paid')
                  .order('created_at', {ascending: false})
                  .limit(1);
                if(bk2.data && bk2.data.length > 0){
                  bookingId = bookingId || bk2.data[0].id;
                  motoId = motoId || bk2.data[0].moto_id;
                }
              }
            }
          } catch(e){}
        }

        try {
          var gps = await _sosGetGPS();
          var r = await apiCreateSosIncident(type, bookingId, gps.lat, gps.lng, desc, null, motoId);
          if(r && r.error){
            console.error('[SOS] createIncident error:', r.error, r.code, r.details);
            if(String(r.error).indexOf('aktivní') >= 0 || String(r.error).indexOf('active') >= 0 || String(r.error).indexOf('Máte již') >= 0 || String(r.error).indexOf('existuje') >= 0){
              showT('⚠️','Aktivní SOS','Na tuto rezervaci již existuje aktivní SOS incident.');
              try {
                var uid3 = await _getUserId();
                var fallbackQ = window.supabase.from('sos_incidents')
                  .select('id')
                  .eq('user_id', uid3)
                  .not('status', 'in', '("resolved","closed")')
                  .not('type', 'in', '("breakdown_minor","defect_question","location_share","other")')
                  .order('created_at', {ascending: false})
                  .limit(1);
                if(bookingId) fallbackQ = fallbackQ.eq('booking_id', bookingId);
                var fallback = await fallbackQ;
                if(fallback.data && fallback.data.length > 0){
                  _sosActiveIncidentId = fallback.data[0].id;
                  resolve(_sosActiveIncidentId);
                  return;
                }
              } catch(e2){}
            }
            var errDetail = String(r.error).substring(0,100);
            if(r.status === 403) errDetail = 'Oprávnění — odhlaste se a přihlaste znovu';
            showT('❌','Chyba SOS', errDetail);
            resolve(null);
            return;
          }
          if(r && r.id) _sosActiveIncidentId = r.id;
          resolve(r && r.id ? r.id : null);
        } catch(e){
          console.error('[SOS] createIncident exception:', e);
          showT('❌','Chyba','Nepodařilo se vytvořit incident: '+(e.message||e));
          resolve(null);
        }
      })();
      return;
    }

    // Fallback: no supabase
    resolve(null);
  });
}

// End active booking when SOS incident ends ride (without replacement)
async function _sosEndBooking(incidentId){
  try {
    var uid = await _getUserId();
    if(!uid) return;
    var todayISO = new Date().toISOString().slice(0,10);
    // Find active booking linked to this incident or current active booking
    var bk = null;
    var incR = await window.supabase.from('sos_incidents').select('booking_id').eq('id', incidentId).single();
    if(incR.data && incR.data.booking_id){
      bk = await window.supabase.from('bookings').select('id, moto_id, end_date').eq('id', incR.data.booking_id).single();
    }
    if(!bk || !bk.data){
      var bkR = await window.supabase.from('bookings').select('id, moto_id, end_date')
        .eq('user_id', uid).in('status', ['active','confirmed','reserved'])
        .eq('payment_status', 'paid')
        .order('start_date', {ascending: false}).limit(1);
      if(bkR.data && bkR.data.length > 0) bk = {data: bkR.data[0]};
    }
    if(!bk || !bk.data) return;
    var booking = bk.data;
    // Update booking: completed + ended_by_sos
    await window.supabase.from('bookings').update({
      status: 'completed',
      end_date: todayISO,
      ended_by_sos: true,
      sos_incident_id: incidentId,
      notes: '[SOS] Ukončeno ke dni ' + todayISO + ' — incident #' + incidentId.substr(-8).toUpperCase()
    }).eq('id', booking.id);
    // Set motorcycle to maintenance
    if(booking.moto_id){
      await window.supabase.from('motorcycles').update({status: 'maintenance'}).eq('id', booking.moto_id);
    }
    // Invalidate cache
    _cachedBookings = null;
  } catch(e){ console.error('[SOS] _sosEndBooking error:', e); }
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
    if(_sosSubmitting) return;
    _sosSubmitting = true;
    var sosType = type === 'lehka' ? 'accident_minor' : 'accident_major';
    _sosActiveIncidentId = null;
    _sosFault = null;
    var desc = sosType === 'accident_minor' ? 'Lehká nehoda – pokračuji v jízdě' : 'Závažná nehoda';
    var typeLabel = sosType === 'accident_minor' ? 'Lehká nehoda' : 'Závažná nehoda';
    _sosEnsureIncident(sosType, desc)
      .then(function(incId){
        _sosSubmitting = false;
        if(!incId){
          _sosShowDone(typeLabel, '❌ Nepodařilo se vytvořit incident. Zkontrolujte připojení a zkuste znovu.',
            '<button onclick="goTo(\'s-sos\')" style="width:100%;background:#b91c1c;color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;">↩ Zkusit znovu</button>');
          return;
        }
        var upd = { moto_rideable: sosType === 'accident_minor' };
        _sosUpdateIncident(incId, upd);
        // Upload SOS photos if any
        if(typeof _sosPhotos!=='undefined' && _sosPhotos.length > 0) {
          uploadSOSPhotos(incId, _sosPhotos).then(function(urls){ if(urls.length) saveSOSPhotoUrls(incId, urls); _sosResetPhotos(); });
        }
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: sosType === 'accident_minor'
            ? 'Zákazník nahlásil lehkou nehodu — motorka pojízdná, pokračuje v jízdě'
            : 'Zákazník nahlásil závažnou nehodu — čeká na pokyny',
        }).then(function(){});
        if(sosType === 'accident_minor'){
          _sosShowDone(typeLabel, 'Děkujeme za nahlášení. Šťastnou cestu!');
        } else {
          // Těžká nehoda → rovnou přesměruj na výběr motorky (nepojízdná)
          goTo('s-sos-nepojizda');
        }
      }).catch(function(){ _sosSubmitting = false; });
}

function sosReportTheft() {
    if(_sosSubmitting) return;
    _sosSubmitting = true;
    _sosActiveIncidentId = null;
    _sosFault = null;
    _sosEnsureIncident('theft', 'Krádež motorky – zákazník informován o postupu (policie 158)')
      .then(function(incId){
        _sosSubmitting = false;
        if(!incId) return; // User cancelled confirmation
        _sosUpdateIncident(incId, { moto_rideable: false });
        // Upload SOS photos if any
        if(typeof _sosPhotos!=='undefined' && _sosPhotos.length > 0) {
          uploadSOSPhotos(incId, _sosPhotos).then(function(urls){ if(urls.length) saveSOSPhotoUrls(incId, urls); _sosResetPhotos(); });
        }
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: 'Zákazník nahlásil krádež motorky — přesměrován na policii ČR (158)',
        }).then(function(){});
        // Mark button as reported
        var btn = document.getElementById('sos-kradez-report-btn');
        if(btn){
          btn.textContent = '✅ Krádež nahlášena MotoGo24';
          btn.style.background = '#1a8a18';
          btn.disabled = true;
          btn.style.opacity = '0.8';
        }
        showT('✅','Krádež nahlášena','MotoGo24 byla informována o krádeži');
      }).catch(function(){ _sosSubmitting = false; });
}

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

// Simulace platební brány (pro zaviněné nehody)
function _sosInitPaymentGateway(amount){
    var cardNum = document.getElementById('sos-pay-card');
    var expiry = document.getElementById('sos-pay-expiry');
    var cvc = document.getElementById('sos-pay-cvc');
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
    if(cardNum) cardNum.value = '';
    if(expiry) expiry.value = '';
    if(cvc) cvc.value = '';
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

function sosEndRide() {
    showT('🚛', 'Objednávám odtah...', '');
    // Keep _sosActiveIncidentId — reuse existing incident from sosReportAccident
    var faultDesc = _sosFault === true ? 'Nehoda byla moje chyba' : _sosFault === false ? 'Nehoda nebyla moje chyba' : '';
    var desc = 'Motorka nepojízdná – ukončuji jízdu, žádám odtah. ' + faultDesc;
    var type = _sosFault !== null ? 'accident_major' : 'breakdown_major';
    _sosEnsureIncident(type, desc).then(function(incId){
      if(!incId){ showT('❌','Chyba','Nepodařilo se nahlásit incident'); return; }
      var upd = {customer_decision:'end_ride', moto_rideable:false};
      if(_sosFault !== null) upd.customer_fault = _sosFault;
      _sosUpdateIncident(incId, upd);
      // Mark booking as completed + ended_by_sos
      _sosEndBooking(incId);
      apiSosRequestTow(incId).then(function(){
        // Timeline entry s detaily
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: 'Zákazník ukončuje jízdu — žádá odtah' + (_sosFault === true ? ' (zavinil zákazník)' : _sosFault === false ? ' (cizí zavinění — zdarma)' : ''),
        }).then(function(){});
        _sosShowDone('Odtah objednán', 'MotoGo24 zařídí odtah motorky. Asistent vás bude kontaktovat.',
          '<button onclick="goTo(\'s-res\')" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;">📋 Zobrazit moje rezervace</button>');
      });
    });
}

function sosEndRideFree() {
    // Keep _sosActiveIncidentId — reuse existing incident
    var desc = 'Porucha – motorka nepojízdná. Ukončuji jízdu, zařídím se sám.';
    _sosEnsureIncident('breakdown_major', desc).then(function(incId){
      if(incId){
        _sosUpdateIncident(incId, {customer_decision:'end_ride', moto_rideable:false, customer_fault:false});
        // Mark booking as completed + ended_by_sos
        _sosEndBooking(incId);
        apiSosRequestTow(incId);
        // Timeline entry
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: 'Zákazník ukončuje jízdu — porucha (nezaviněná) — pronájem zdarma, odtah objednán',
        }).then(function(){});
      }
      _sosShowDone('Pronájem zdarma', 'Vracíme plnou částku. Odtah zajistíme.',
        '<button onclick="goTo(\'s-res\')" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;">📋 Zobrazit moje rezervace</button>');
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
                { enableHighAccuracy: false, timeout: 30000, maximumAge: 60000 }
            );
        },
        { enableHighAccuracy: true, timeout: 30000, maximumAge: 0 }
    );
}

function sosDrobnaZavada() {
    if(_sosSubmitting) return;
    _sosSubmitting = true;
    showT('🔩', 'Hlásím závadu...', '');
    _sosActiveIncidentId = null;
    _sosFault = null;
    _sosEnsureIncident('breakdown_minor', 'Drobná závada – motorka pojízdná, pokračuji v jízdě').then(function(incId){
      _sosSubmitting = false;
      if(incId){
        _sosUpdateIncident(incId, { moto_rideable: true, customer_fault: false, customer_decision: 'continue' });
        // Upload SOS photos if any
        if(typeof _sosPhotos!=='undefined' && _sosPhotos.length > 0) {
          uploadSOSPhotos(incId, _sosPhotos).then(function(urls){ if(urls.length) saveSOSPhotoUrls(incId, urls); _sosResetPhotos(); });
        }
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: 'Zákazník nahlásil drobnou závadu — motorka pojízdná, pokračuje v jízdě',
        }).then(function(){});
      }
      _sosShowDone('Drobná závada', 'Děkujeme za nahlášení. Šťastnou cestu!');
    }).catch(function(){ _sosSubmitting = false; });
}

// ===== SOS PHOTO-ONLY SUBMIT — informativní fotodokumentace =====
function sosSubmitPhotosOnly() {
    if(typeof _sosPhotos==='undefined' || _sosPhotos.length === 0) {
      showT('⚠️', 'Žádné fotky', 'Nejdříve přidejte alespoň jednu fotku');
      return;
    }
    if(_sosSubmitting) return;
    _sosSubmitting = true;
    var btn = document.getElementById('sos-photo-submit-btn');
    if(btn){ btn.textContent = '⏳ Odesílám...'; btn.disabled = true; }
    // Get active booking for linking
    _sosPreFetchIds();
    setTimeout(function(){
      var bookingId = _sosCurrentBookingId || null;
      var motoId = _sosCurrentMotoId || null;
      // Create a lightweight 'other' incident for informative photo documentation
      _sosGetGPS().then(function(gps){
        return apiCreateSosIncident('other', bookingId, gps.lat, gps.lng, 'Informativní fotodokumentace – zákazník odeslal fotky', false, motoId);
      }).then(function(incId){
        if(!incId){
          _sosSubmitting = false;
          if(btn){ btn.textContent = '📤 Odeslat fotodokumentaci do MotoGo24'; btn.disabled = false; }
          showT('❌', 'Chyba', 'Nepodařilo se odeslat. Zkuste znovu.');
          return;
        }
        // Upload photos
        uploadSOSPhotos(incId, _sosPhotos).then(function(urls){
          if(urls.length) saveSOSPhotoUrls(incId, urls);
          _sosResetPhotos();
          _sosSubmitting = false;
          // Timeline entry
          window.supabase.from('sos_timeline').insert({
            incident_id: incId,
            action: 'Zákazník odeslal informativní fotodokumentaci (' + urls.length + ' fotek)',
          }).then(function(){});
          showT('✅', 'Fotodokumentace odeslána', 'MotoGo24 obdržela vaše fotky');
          if(btn){ btn.textContent = '✅ Odesláno'; btn.style.background = '#1a8a18'; btn.style.opacity = '0.8'; }
          setTimeout(function(){
            if(btn){ btn.textContent = '📤 Odeslat fotodokumentaci do MotoGo24'; btn.disabled = false; btn.style.background = 'var(--green)'; btn.style.opacity = '1'; btn.style.display = 'none'; }
          }, 3000);
        });
      }).catch(function(e){
        console.error('[SOS] sosSubmitPhotosOnly error:', e);
        _sosSubmitting = false;
        if(btn){ btn.textContent = '📤 Odeslat fotodokumentaci do MotoGo24'; btn.disabled = false; }
        showT('❌', 'Chyba', 'Nepodařilo se odeslat fotky');
      });
    }, 300);
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
  _sosFaultSnapshot = vinik;
  // Keep _sosActiveIncidentId — reuse existing incident, don't create duplicate
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
  // Show Google review prompt after rating
  if(val >= 4) _showGoogleReviewBanner();
}

// ===== GOOGLE RECENZE =====
var _googleReviewUrl = null;
async function _loadGoogleReviewUrl(){
  if(_googleReviewUrl) return _googleReviewUrl;
  if(!window.supabase) return null;
  try {
    var r = await window.supabase.from('app_settings').select('value').eq('key','google_review_url').maybeSingle();
    if(r.data && r.data.value){
      _googleReviewUrl = typeof r.data.value === 'string' ? r.data.value : r.data.value.url || r.data.value;
      return _googleReviewUrl;
    }
  } catch(e){}
  // Fallback placeholder URL
  return 'https://search.google.com/local/writereview?placeid=PLACE_ID';
}

function _showGoogleReviewBanner(){
  var el = document.getElementById('done-google-review');
  if(el) el.style.display = 'block';
}

async function _openGoogleReview(){
  var url = await _loadGoogleReviewUrl();
  // Track that user was asked for review
  if(window.supabase && _currentResId){
    try {
      var uid = await _getUserId();
      if(uid){
        window.supabase.from('reviews').insert({
          booking_id: _currentResId,
          customer_id: uid,
          source: 'google_prompt',
          created_at: new Date().toISOString()
        }).then(function(){}).catch(function(){});
      }
    } catch(e){}
  }
  if(url) {
    if(typeof openExternalLink === 'function') openExternalLink(url);
    else window.open(url, '_blank');
  }
  var el = document.getElementById('done-google-review');
  if(el) el.style.display = 'none';
}

function _initDoneDetailGoogleReview(booking){
  var el = document.getElementById('done-google-review');
  if(!el) return;
  // Show only for completed bookings that haven't been rated yet
  if(booking && booking.status === 'completed' && !booking.rated_at){
    el.style.display = 'block';
  } else {
    el.style.display = 'none';
  }
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
