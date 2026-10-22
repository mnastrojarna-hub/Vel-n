/* ===== MotoGo24 — Rezervace: cena u každého volného dne v kalendáři (2026-10-22) =====
   Jen když kalendář ukazuje JEDNU motorku (MG._rez.motoId — ?moto=, výběr v kroku 1). Cena dne =
   MG.calcPriceBreakdown (js/api.js: price_<den> || price_weekday) = stejný ceník, jaký účtuje server
   v create_web_booking (COALESCE(price_<den>, price_weekday)). Bez sezónních pravidel a bez slevy
   za vyzvednutí od 12:00 (ta je za celou rezervaci, ne za den). Číslo bez měny (jako kalkulačka
   v detailu), měna v legendě pod kalendářem. Jádro (pages-rezervace-calendar.js, minifikované) se
   neupravuje: obal MG._rezRenderMonthHtml doplní <span class="dp"> do volných buněk; nenajde-li vzor
   buňky, ceny se prostě nezobrazí. Vzhled css/rezervace-dates.css. */
(function () {
  'use strict';
  var d = document, w = window, MG = w.MG || {};
  var LG = ((w.MOTOGO_CONFIG || {}).LANG || d.documentElement.lang || 'cs').slice(0, 2);
  var LEG = { cs: 'Cena/den v {cur}', en: 'Price/day in {cur}', de: 'Preis/Tag in {cur}', es: 'Precio/día en {cur}', fr: 'Prix/jour en {cur}',
    nl: 'Prijs/dag in {cur}', pl: 'Cena/dzień w {cur}', uk: 'Ціна/день у {cur}' };
  var CELL = /(onclick="MG\._rezPickDate\('(\d{4}-\d{2}-\d{2})'\)"><span class="dn">[^<]*<\/span><span>\d+<\/span>)(<\/div>)/g;

  function moto() { var r = MG._rez || {}, l = r.motos || []; for (var i = 0; i < l.length; i++) if (l[i] && l[i].id === r.motoId) return l[i]; return null; }
  // měna jako MG.formatPrice; bez kurzu raději Kč než špatné číslo
  function cur() {
    var c = MG.currentCurrency ? String(MG.currentCurrency()).toUpperCase() : 'CZK';
    if (c !== 'CZK' && !(MG.fxRate && MG.fxRate(c) > 0)) c = 'CZK';
    return c;
  }
  function short(p, c) { var v = c === 'CZK' || !MG.convertFromCzk ? p : MG.convertFromCzk(p, c); return Math.round(Number(v) || 0).toLocaleString('cs-CZ'); }
  function sym(c) { return ((MG._curMeta || {})[c] || {}).symbol || (c === 'CZK' ? 'Kč' : c); }

  function hook() {
    if (typeof MG._rezRenderMonthHtml !== 'function' || typeof MG._rezRenderCal !== 'function' || typeof MG.calcPriceBreakdown !== 'function') return false;
    if (MG._rezRenderMonthHtml._uxDp) return true;
    var mh = MG._rezRenderMonthHtml, rc = MG._rezRenderCal;
    MG._rezRenderMonthHtml = function () {
      var h = mh.apply(this, arguments), m = moto(), c = cur();
      if (!m || typeof h !== 'string') return h;
      return h.replace(CELL, function (all, pre, iso, end) {
        var bd = MG.calcPriceBreakdown(m, iso, iso), p = bd && bd.days && bd.days[0] ? Number(bd.days[0].price) : 0;
        return p > 0 ? pre + '<span class="dp">' + short(p, c) + '</span>' + end : all;
      });
    };
    MG._rezRenderMonthHtml._uxDp = 1;
    MG._rezRenderCal = function () {
      var x = rc.apply(this, arguments), el = d.getElementById('rez-calendar');
      if (!el) return x;
      var on = !!el.querySelector('.cal-day .dp');
      el.classList.toggle('ux-has-prices', on);
      var ic = el.querySelector('.calendar-icons');
      if (on && ic && !ic.querySelector('.ux-dp-lg')) {
        var lg = d.createElement('div'), c = cur();
        lg.className = 'ux-dp-lg';
        lg.innerHTML = '<span class="ux-dp-sw" aria-hidden="true">123</span> ';
        lg.appendChild(d.createTextNode((LEG[LG] || LEG.cs).replace('{cur}', sym(c))));
        ic.appendChild(lg);
      }
      return x;
    };
    return true;
  }
  var n = 0;
  (function wait() { if (!hook() && ++n < 100) setTimeout(wait, 50); })();
})();
