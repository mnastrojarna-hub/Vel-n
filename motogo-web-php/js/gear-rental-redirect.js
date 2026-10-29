/* MotoGo24 — výpůjčky výbavy z motorkových stránek na stránku výbavy (2026-10-23, DESIGN-GEAR §3.5).
   /rezervace?resume=<id>: je-li id výpůjčka výbavy (get_web_gear_booking ji vrátí), jde se na
   /pujceni-obleceni?resume=<id> (+ payfail, lang) ještě PŘED motorkovým MG._rezInit (obalí se),
   takže fungují i všechny dosavadní odkazy /rezervace?resume (e-maily, crony, AI). Dotaz má
   strop 2,5 s — pak (i při chybě) motorkový start běží normálně.
   /potvrzeni?booking_id= | ?session_id= (bez order_id): u výbavy na potvrzení stránky výbavy.
   Motorkové potvrzení se NIKDY neskrývá: rozhodne get_web_booking_confirmation (moto_id =
   motorka → konec); skryje se až rezervace bez motorky (do přesměrování, nejvýš 2,5 s).
   Načítá se za pages-rezervace.js / pages-potvrzeni.js; adresa stránky výbavy v data-gear-url. */
(function () {
  var w = window, d = document, sc = d.currentScript;
  var url = (sc && sc.getAttribute('data-gear-url')) || '/pujceni-obleceni';
  var MG = w.MG = w.MG || {}, P = new URLSearchParams(location.search);
  var RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, MAX = 2500;
  // RPC → data | null (chyba, bez SDK, po MAX ms)
  function rpc(fn, args) {
    if (!(w.sb && w.sb.rpc)) return Promise.resolve(null);
    var call = Promise.resolve(w.sb.rpc(fn, args)).then(function (r) { return r && !r.error ? r.data : null; }, function () { return null; });
    return Promise.race([call, new Promise(function (ok) { setTimeout(function () { ok(null); }, MAX); })]);
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
  var t = 0;
  function show() { clearTimeout(t); box.style.visibility = ''; }
  rpc('get_web_booking_confirmation', RE.test(bid) ? { p_booking_id: bid } : { p_session_id: sid }).then(function (c) {
    if (c && c.moto_id) return null;                       // motorka — potvrzení beze změny
    var gid = c && !c.error && c.id ? c.id : (RE.test(bid) ? bid : '');
    if (!gid) return null;
    if (c && c.id) { box.style.visibility = 'hidden'; t = setTimeout(show, MAX); }
    return rpc('get_web_gear_booking', { p_booking_id: gid, p_session_id: sid || null });
  }).then(function (o) {
    if (gear(o)) return go('booking_id=' + encodeURIComponent(o.id) + (sid ? '&session_id=' + encodeURIComponent(sid) : ''));
    show();
  }, show);
})();
