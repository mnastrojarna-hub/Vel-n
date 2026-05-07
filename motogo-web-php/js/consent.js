// MotoGo24 — cookie consent manager (GDPR/ePrivacy compliant)
// Reads window.MG_CONSENT_CFG = {gtmId, sklikId} (set inline in <head>).
// GTM and Sklik are dynamically injected only after explicit user consent.
(function () {
  var CFG = window.MG_CONSENT_CFG || {};
  var COOKIE = 'mg_cookie_consent';
  var ONE_YEAR = 365 * 24 * 3600;

  function readConsent() {
    var m = ('; ' + document.cookie).split('; ' + COOKIE + '=');
    if (m.length < 2) return null;
    var raw = m.pop().split(';').shift();
    try { return JSON.parse(decodeURIComponent(raw)); } catch (e) { return null; }
  }
  function writeConsent(c) {
    var v = encodeURIComponent(JSON.stringify(c));
    var secure = location.protocol === 'https:' ? ';secure' : '';
    document.cookie = COOKIE + '=' + v + ';path=/;max-age=' + ONE_YEAR + ';samesite=Lax' + secure;
  }
  function injectGtm(id) {
    if (!id || window.__mgGtmLoaded) return;
    window.__mgGtmLoaded = true;
    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push({ 'gtm.start': new Date().getTime(), event: 'gtm.js' });
    var s = document.createElement('script');
    s.async = true;
    s.src = 'https://www.googletagmanager.com/gtm.js?id=' + encodeURIComponent(id);
    document.head.appendChild(s);
    var ns = document.createElement('noscript');
    var iframe = document.createElement('iframe');
    iframe.src = 'https://www.googletagmanager.com/ns.html?id=' + encodeURIComponent(id);
    iframe.height = '0'; iframe.width = '0';
    iframe.style.display = 'none'; iframe.style.visibility = 'hidden';
    ns.appendChild(iframe);
    (document.body || document.documentElement).appendChild(ns);
  }
  function injectSklik(id) {
    if (!id || window.__mgSklikLoaded) return;
    window.__mgSklikLoaded = true;
    window.seznam_retargeting_id = id;
    var s = document.createElement('script');
    s.async = true;
    s.src = 'https://c.imedia.cz/js/retargeting.js';
    document.head.appendChild(s);
  }
  function applyConsent(c) {
    if (!c) return;
    if (c.analytics) injectGtm(CFG.gtmId);
    if (c.marketing) injectSklik(CFG.sklikId);
  }
  function showBanner(asSettings) {
    var b = document.getElementById('mg-consent');
    if (!b) return;
    b.hidden = false;
    var settings = document.getElementById('mg-consent-settings');
    var save = document.querySelector('[data-consent-action=save]');
    if (asSettings) {
      if (settings) settings.hidden = false;
      if (save) save.hidden = false;
    } else {
      if (settings) settings.hidden = true;
      if (save) save.hidden = true;
    }
  }
  function hideBanner() {
    var b = document.getElementById('mg-consent');
    if (b) b.hidden = true;
  }
  function persist(an, ma) {
    var c = { necessary: 1, analytics: an ? 1 : 0, marketing: ma ? 1 : 0, v: 1, ts: Math.floor(Date.now() / 1000) };
    writeConsent(c);
    applyConsent(c);
    hideBanner();
  }

  function init() {
    var existing = readConsent();
    if (existing) {
      applyConsent(existing);
    } else {
      showBanner(false);
    }
    var b = document.getElementById('mg-consent');
    if (b) {
      b.addEventListener('click', function (e) {
        var a = e.target.closest('[data-consent-action]');
        if (!a) return;
        e.preventDefault();
        var act = a.getAttribute('data-consent-action');
        if (act === 'accept-all') { persist(true, true); }
        else if (act === 'reject-all') { persist(false, false); }
        else if (act === 'settings') { showBanner(true); }
        else if (act === 'save') {
          var an = document.getElementById('mg-consent-analytics');
          var ma = document.getElementById('mg-consent-marketing');
          persist(an && an.checked, ma && ma.checked);
        }
      });
    }
    document.addEventListener('click', function (e) {
      var trg = e.target.closest('[data-cookie-prefs]');
      if (!trg) return;
      e.preventDefault();
      var ex = readConsent();
      var an = document.getElementById('mg-consent-analytics');
      var ma = document.getElementById('mg-consent-marketing');
      if (an) an.checked = !!(ex && ex.analytics);
      if (ma) ma.checked = !!(ex && ex.marketing);
      showBanner(true);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
