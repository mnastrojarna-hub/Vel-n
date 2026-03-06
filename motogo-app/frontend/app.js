// ===== APP.JS – Initialization entry point for MotoGo24 =====
// Navigation (goTo, histBack) is now in js/router.js
// Dependencies: data/*.js, templates.js, js/router.js, js/storage.js, js/cart-engine.js, ui-controller.js, booking-logic.js
// Backend: Supabase (production) — žádný mock fallback

// ===== INITIALIZATION =====
console.log('%c[MG] MotoGo24 v5.0.0','color:#74FB71;font-weight:bold;font-size:14px;');

function _resolveSession(cb){
  // Supabase session (async, primary backend)
  if(typeof supabase !== 'undefined' && supabase){
    supabase.auth.getSession().then(function(result){
      var hasSession = !!(result.data && result.data.session);
      if(hasSession){
        try {
          var user = result.data.session.user;
          if(typeof _syncLocalSession === 'function'){
            _syncLocalSession(user.id, user.email);
          }
        } catch(e){}
      }
      cb(hasSession);
    }).catch(function(){
      cb(false);
    });
    return;
  }
  cb(false);
}

function _continueInit(hasSession){
  if(hasSession){
    cur='s-home';
    navStack=['s-home'];
    var bnav = document.getElementById('bnav');
    if(bnav) bnav.style.display = 'flex';
    if(typeof renderUserData === 'function') renderUserData();
  } else {
    cur='s-login';
    navStack=['s-login'];
  }

  // Show the current screen, hide others
  document.querySelectorAll('.screen').forEach(function(s){
    s.classList.toggle('hidden', s.id !== cur);
  });

  // Obohatit MOTOS z Supabase (propojení lokální ID ↔ UUID, filtr neaktivních)
  // enrichMOTOS() je async — musí doběhnout PŘED initMotoAvailability
  if(typeof enrichMOTOS==='function'){
    enrichMOTOS().then(function(){
      if(typeof initMotoAvailability==='function') initMotoAvailability();
      if(typeof applyFilters==='function') applyFilters();
    });
  } else {
    if(typeof initMotoAvailability==='function') initMotoAvailability();
  }
  // Sync global OCC/UNCONF from actual bookings
  if(typeof syncGlobalOcc==='function') syncGlobalOcc();

  // Initialize UI components
  if(typeof setupBioButton==='function') setupBioButton();
  // Language selection (first launch) – must run before permissions
  if(typeof initLangSelect==='function') initLangSelect();
  if(typeof initPerms==='function') initPerms();

  // Build calendars
  if(typeof buildSCal==='function') buildSCal();
  if(typeof buildBCal==='function') buildBCal();
  if(typeof buildECal==='function') buildECal();

  // Apply home filters (renders moto cards)
  if(typeof applyHomeFilters==='function') applyHomeFilters();

  // Initialize dynamic dates
  if(typeof initDynamicDates==='function') initDynamicDates();

  // Update reservation buttons based on real time (AppTime)
  if(typeof updateResButtons==='function') updateResButtons();

  // Initialize scroll-to-top
  if(typeof initScrollTop==='function') initScrollTop();

  // Subscribe to admin messages (realtime notifications)
  if(hasSession && typeof initAdminMessageSubscription==='function'){
    initAdminMessageSubscription();
  }

  // Spustit offline guard
  OfflineGuard.startWatching();
}

function initApp(){
  // Load templates into screen containers
  if(typeof loadTemplates==='function') loadTemplates();
  if(typeof initTimePickers==='function') initTimePickers();

  // Check for existing session (Supabase only)
  _resolveSession(function(hasSession){
    _continueInit(hasSession);
  });
}

// Run init when DOM is ready
if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',initApp);
} else {
  initApp();
}
