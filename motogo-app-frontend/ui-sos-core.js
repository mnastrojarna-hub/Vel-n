/* === UI-SOS-CORE.JS — SOS incident creation & reporting === */

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
        .in('status', ['active', 'pending', 'reserved'])
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
                .in('status', ['active', 'pending', 'reserved'])
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
        .eq('user_id', uid).in('status', ['active','reserved'])
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
