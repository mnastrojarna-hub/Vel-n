/* MotoGo24 — měření pro Velín → Analýza → Web funnel (engage.php, tabulka web_engagement).
   „Návštěva“ = člověk byl na stránce ≥5 s s viditelnou kartou A skutečně s ní interagoval
   (myš/dotyk/klávesa, jen isTrusted). Boti bez JS sem nedojdou, automatizace
   (navigator.webdriver, headless) se vyřadí. „calc“ = kalkulačka ukázala cenu po akci člověka
   (MGEngage.track('calc') z landing-calc.js; ne cena předvyplněná z URL bez kliknutí).
   Bez cookies a bez úložiště — 1× za den a člověka hlídá server (denní hash) + unikátní index v DB. */
(function () {
  var w = window, d = document, n = navigator;
  if (w.MGEngage) return;
  var noop = { track: function () {} };
  if (n.webdriver || /HeadlessChrome|PhantomJS|Lighthouse|Chrome-Lighthouse/i.test(n.userAgent || '')) { w.MGEngage = noop; return; }

  var NEED_MS = 5000, url = '/api/engage', sent = {}, human = false;
  var visibleMs = 0, since = d.visibilityState === 'visible' ? Date.now() : 0, timer = null;

  function send(e) {
    if (sent[e]) return;
    sent[e] = true;
    var body = JSON.stringify({ e: e, p: location.pathname });
    try {
      if (n.sendBeacon && n.sendBeacon(url, new Blob([body], { type: 'text/plain' }))) return;
    } catch (x) {}
    try { fetch(url, { method: 'POST', body: body, keepalive: true, credentials: 'same-origin' }); } catch (x) {}
  }
  function elapsed() { return visibleMs + (since ? Date.now() - since : 0); }
  function check() {
    if (sent.visit) return;
    if (human && elapsed() >= NEED_MS) { send('visit'); stop(); }
  }
  function stop() { if (timer) { clearInterval(timer); timer = null; } }

  function onHuman(ev) {
    if (!ev || ev.isTrusted === false || human) return;
    human = true;
    check();
  }
  ['pointerdown', 'pointermove', 'touchstart', 'keydown', 'wheel'].forEach(function (t) {
    w.addEventListener(t, onHuman, { capture: true, passive: true });
  });
  d.addEventListener('visibilitychange', function () {
    if (d.visibilityState === 'visible') { if (!since) since = Date.now(); }
    else if (since) { visibleMs += Date.now() - since; since = 0; }
  });
  timer = setInterval(check, 1000);

  w.MGEngage = {
    track: function (e) {
      // jen po akci člověka — cena předvyplněná z URL bez kliknutí se nepočítá
      if (e === 'calc' && human) send(e);
    }
  };
})();
