// ===== MotoGo24 — Header auth indicator =====
// Lehký globální script (~1 KB), runs on every page přes layout.php.
// Nepotřebuje načtený Supabase SDK — čte session přímo z localStorage
// (klíč `sb-<project>-auth-token`, který Supabase JS klient ukládá).
// Pokud window.sb existuje (rezervace/upravit-rezervaci/checkout/potvrzeni),
// hooke se na auth.onAuthStateChange a logout odešle přes signOut.
(function () {
  function findAuthKey() {
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (k && /^sb-.+-auth-token$/.test(k)) return k;
      }
    } catch (e) {}
    return null;
  }
  function readSession() {
    var k = findAuthKey();
    if (!k) return null;
    try {
      var raw = localStorage.getItem(k);
      if (!raw) return null;
      var obj = JSON.parse(raw);
      // Supabase v2 stores either { currentSession: {...} } or the session directly.
      var s = (obj && obj.currentSession) ? obj.currentSession : obj;
      if (!s || !s.access_token) return null;
      // Expiry sanity check (expires_at in seconds since epoch)
      if (s.expires_at && Date.now() / 1000 > Number(s.expires_at)) return null;
      var email = (s.user && s.user.email) || (s.user_metadata && s.user_metadata.email) || '';
      var name = (s.user && s.user.user_metadata && (s.user.user_metadata.full_name || s.user.user_metadata.name)) || '';
      return { email: email, name: name, token: s.access_token };
    } catch (e) { return null; }
  }
  function clearAllSbKeys() {
    try {
      var rm = [];
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (k && /^sb-/.test(k)) rm.push(k);
      }
      rm.forEach(function (k) { localStorage.removeItem(k); });
    } catch (e) {}
  }
  function render() {
    var bar = document.querySelector('[data-mg-auth]');
    if (!bar) return;
    var emailEl = bar.querySelector('[data-mg-auth-email]');
    var btn = bar.querySelector('[data-mg-auth-logout]');
    var sess = readSession();
    if (sess && sess.email) {
      if (emailEl) emailEl.textContent = sess.email;
      bar.hidden = false;
      bar.setAttribute('aria-live', 'polite');
      // Expose for other scripts (rezervace step 3 → skip password creation)
      try {
        window.MG = window.MG || {};
        window.MG._authSession = sess;
        window.dispatchEvent(new CustomEvent('mg-auth-changed', { detail: sess }));
      } catch (e) {}
    } else {
      bar.hidden = true;
      try {
        if (window.MG && window.MG._authSession) {
          window.MG._authSession = null;
          window.dispatchEvent(new CustomEvent('mg-auth-changed', { detail: null }));
        }
      } catch (e) {}
    }
    if (btn && !btn._bound) {
      btn._bound = true;
      btn.addEventListener('click', function () {
        try {
          if (window.sb && window.sb.auth && typeof window.sb.auth.signOut === 'function') {
            window.sb.auth.signOut().catch(function () {}).finally(function () {
              clearAllSbKeys();
              try { sessionStorage.removeItem('mg_rez_form'); } catch (e) {}
              window.location.reload();
            });
            return;
          }
        } catch (e) {}
        clearAllSbKeys();
        try { sessionStorage.removeItem('mg_rez_form'); } catch (e) {}
        window.location.reload();
      });
    }
  }
  function init() {
    render();
    // React to logins/logouts in this tab when window.sb is available.
    try {
      if (window.sb && window.sb.auth && typeof window.sb.auth.onAuthStateChange === 'function') {
        window.sb.auth.onAuthStateChange(function () { setTimeout(render, 50); });
      }
    } catch (e) {}
    // Cross-tab sync — když se uživatel odhlásí v jiném tabu, hlavička se aktualizuje.
    try {
      window.addEventListener('storage', function (e) {
        if (!e.key || /^sb-/.test(e.key)) render();
      });
    } catch (e) {}
    // Pokud se SDK doinicializuje až po DOMContentLoaded (rezervace.php), zkusíme znovu po 1 s.
    setTimeout(render, 1000);
    setTimeout(render, 3000);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
