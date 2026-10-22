/* MotoGo24 — výpůjčky výbavy z motorkových stránek na stránku výbavy (2026-10-23, DESIGN-GEAR §3.5).
   /rezervace?resume=<id>: je-li id výpůjčka výbavy (get_web_gear_booking ji vrátí), jde se na
   /pujceni-obleceni?resume=<id> (+ payfail, lang) ještě PŘED motorkovým MG._rezInit (obalí se),
   takže fungují i všechny dosavadní odkazy /rezervace?resume (e-maily, crony, AI).
   /potvrzeni?booking_id= | ?session_id= (bez order_id): u výbavy na potvrzení stránky výbavy;
   motorkové texty se do rozhodnutí skryjí (nejvýš 4 s). Motorkové rezervace beze změny.
   Načítá se za pages-rezervace.js / pages-potvrzeni.js; adresa stránky výbavy v data-gear-url. */
(function () {
  var w = window, d = document, sc = d.currentScript;
  var url = (sc && sc.getAttribute('data-gear-url')) || '/pujceni-obleceni';
  var MG = w.MG = w.MG || {}, P = new URLSearchParams(location.search);
  var RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  function rpc(fn, args) {
    if (!(w.sb && w.sb.rpc)) return Promise.resolve(null);
    return Promise.resolve(w.sb.rpc(fn, args)).then(function (r) { return r && !r.error ? r.data : null; }, function () { return null; });
  }
  function gear(o) { return !!(o && !o.error && o.id); }
  function go(qs) {
    var lp = P.get('lang');
    location.replace(url + '?' + qs + (lp ? '&lang=' + encodeURIComponent(lp) : ''));
  }

  // ---- /rezervace?resume=<id> ----
  if (typeof MG._rezInit === 'function') {
    var id = String((w.REZERVACE_PARAMS || {}).resume || '');
    if (!RE.test(id) || MG._rezInit._gearHook) return;
    var orig = MG._rezInit;
    MG._rezInit = function () {
      var self = this, args = arguments;
      return rpc('get_web_gear_booking', { p_booking_id: id }).then(function (o) {
        if (gear(o)) return go('resume=' + encodeURIComponent(id) + (P.get('payfail') ? '&payfail=1' : ''));
        return orig.apply(self, args);
      });
    };
    MG._rezInit._gearHook = true;
    return;
  }

  // ---- /potvrzeni ----
  var box = d.getElementById('confirm-content'), bid = P.get('booking_id') || '', sid = P.get('session_id') || '';
  if (!box || P.get('order_id') || P.get('flow') || (!RE.test(bid) && !sid)) return;
  box.style.visibility = 'hidden';
  var t = setTimeout(function () { box.style.visibility = ''; }, 4000);
  // bez booking_id: id podle Stripe session; motorková rezervace (moto_id) se dál neověřuje
  (RE.test(bid) ? Promise.resolve({ id: bid }) : rpc('get_web_booking_confirmation', { p_session_id: sid }).then(function (c) {
    return c && !c.error && c.id && !c.moto_id ? c : null;
  })).then(function (c) {
    return c ? rpc('get_web_gear_booking', { p_booking_id: c.id, p_session_id: sid || null }) : null;
  }).then(function (o) {
    clearTimeout(t);
    if (gear(o)) return go('booking_id=' + encodeURIComponent(o.id) + (sid ? '&session_id=' + encodeURIComponent(sid) : ''));
    box.style.visibility = '';
  }, function () { clearTimeout(t); box.style.visibility = ''; });
})();
