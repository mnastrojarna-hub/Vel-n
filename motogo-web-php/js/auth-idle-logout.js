// ===== MotoGo24 Web — Auto-logout po 10 minutách nečinnosti =====
// Sleduje aktivitu uživatele (mouse, keyboard, scroll, touch) a po 10
// minutách bez interakce odhlásí přihlášenou Supabase auth session.
// Anonymní návštěvník není dotčen.
//
// Aktivuje se na všech stránkách, kde je načtený `supabase-init.js`
// (rezervace, upravit-rezervaci, ...). Idle timer se spouští/ruší
// v reakci na `auth.onAuthStateChange` — login → start, logout → stop.
(function(){
  var IDLE_LIMIT_MS = 10 * 60 * 1000; // 10 minut
  var THROTTLE_MS = 5 * 1000;         // resetTimer jen 1× za 5 s (ochrana CPU při mousemove)
  var idleTimer = null;
  var lastReset = 0;
  var hasActiveSession = false;
  var initialized = false;

  function clearTimer(){
    if(idleTimer){ clearTimeout(idleTimer); idleTimer = null; }
  }

  async function doLogout(){
    clearTimer();
    if(!hasActiveSession) return;
    hasActiveSession = false;
    try { if(window.sb && window.sb.auth) await window.sb.auth.signOut(); } catch(e){}
    try { sessionStorage.removeItem('mg_rez_form'); } catch(e){}
    try {
      alert('Byl/a jste automaticky odhlášen/a po 10 minutách nečinnosti. Stránka se nyní obnoví.');
    } catch(e){}
    try { window.location.reload(); } catch(e){}
  }

  function resetTimer(){
    if(!hasActiveSession) return;
    var now = Date.now();
    if(now - lastReset < THROTTLE_MS) return;
    lastReset = now;
    clearTimer();
    idleTimer = setTimeout(doLogout, IDLE_LIMIT_MS);
  }

  function bindActivity(){
    var events = ['mousedown','mousemove','keydown','scroll','touchstart','click','wheel'];
    events.forEach(function(ev){
      window.addEventListener(ev, resetTimer, { passive: true, capture: true });
    });
    // Když se vrátí tab do popředí, znovu zkontrolovat session a resetnout
    document.addEventListener('visibilitychange', function(){
      if(document.visibilityState === 'visible') resetTimer();
    });
  }

  function activate(){
    hasActiveSession = true;
    lastReset = 0;
    resetTimer();
  }

  function deactivate(){
    hasActiveSession = false;
    clearTimer();
  }

  function init(){
    if(initialized) return;
    if(!window.sb || !window.sb.auth) return;
    initialized = true;
    bindActivity();

    // Aktuální session při načtení stránky (refresh přes přihlášenou session)
    window.sb.auth.getSession().then(function(res){
      var sess = res && res.data && res.data.session;
      if(sess && sess.user){ activate(); }
    }).catch(function(){});

    // Změny stavu (login/logout v jiném tabu nebo programově)
    if(typeof window.sb.auth.onAuthStateChange === 'function'){
      window.sb.auth.onAuthStateChange(function(event, session){
        if(event === 'SIGNED_OUT' || !(session && session.user)){
          deactivate();
        } else {
          activate();
        }
      });
    }
  }

  function tryInit(){
    if(window.sb){ init(); }
    else { setTimeout(tryInit, 200); }
  }

  if(document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', function(){ setTimeout(tryInit, 200); });
  } else {
    setTimeout(tryInit, 200);
  }
})();
