/* ===== MotoGo24 — Rezervace: termín z detailu motorky = krok 2 sbalený (2026-10-22) =====
   Detail motorky / karta katalogu posílá /rezervace?moto=&start=&end= (js/landing-calc.js X.href()).
   Jádro js/pages-rezervace*.js je minifikované — tento soubor ho jen obaluje zvenčí (MG.* funkce):
   1) Rychlá kontrola adresy PŘED MG._rezInit: špatný formát / minulost / konec před začátkem → termín
      se z REZERVACE_PARAMS zahodí (dřív NaN v kalendáři). Stejné ověření dělá PHP v pages/rezervace.php.
   2) Motorka + celý termín z adresy (bez ?resume) → sekce #rez-step-cal dostane .ux-collapsed: kalendář
      a lišta termínu se skryjí, místo nich souhrn (data, počet dní) a tlačítko „Změnit“.
   3) Konečné ověření, až je načtená obsazenost (1. MG._rezUpdateBanner po MG._rezLoadCalendar): motorka
      je v nabídce, každý den termínu volný, min/max dní motorky. Neprojde → krok zůstane otevřený jako
      dřív (výběr se nemaže). Zmizí-li termín (změna motorky/pobočky, reset) nebo přestane-li být volný
      (30s obnova obsazenosti), krok se rozbalí sám.
   Veřejné: MG._uxExpandStep(sekce) — používá js/rezervace-next.js („Pokračovat“). Vzhled css/rezervace-dates.css. */
(function () {
  'use strict';
  var d = document, w = window, MG = w.MG || {}, P = w.REZERVACE_PARAMS || {};
  var LG = ((w.MOTOGO_CONFIG || {}).LANG || d.documentElement.lang || 'cs').slice(0, 2);
  var TX = {
    cs: { sel: 'Vybraný termín', chg: 'Změnit', aria: 'Změnit termín', days: function (n) { return n + (n === 1 ? ' den' : n < 5 ? ' dny' : ' dní'); } },
    en: { sel: 'Your dates', chg: 'Change', aria: 'Change dates', days: function (n) { return n + (n === 1 ? ' day' : ' days'); } },
    de: { sel: 'Dein Termin', chg: 'Ändern', aria: 'Termin ändern', days: function (n) { return n + (n === 1 ? ' Tag' : ' Tage'); } },
    es: { sel: 'Tus fechas', chg: 'Cambiar', aria: 'Cambiar fechas', days: function (n) { return n + (n === 1 ? ' día' : ' días'); } },
    fr: { sel: 'Tes dates', chg: 'Modifier', aria: 'Modifier les dates', days: function (n) { return n + (n === 1 ? ' jour' : ' jours'); } },
    nl: { sel: 'Jouw data', chg: 'Wijzigen', aria: 'Data wijzigen', days: function (n) { return n + (n === 1 ? ' dag' : ' dagen'); } },
    pl: { sel: 'Twój termin', chg: 'Zmień', aria: 'Zmień termin', days: function (n) { return n + (n === 1 ? ' dzień' : ' dni'); } },
    uk: { sel: 'Твої дати', chg: 'Змінити', aria: 'Змінити дати', days: function (n) { var a = n % 10, b = n % 100; return n + (a === 1 && b !== 11 ? ' день' : a >= 2 && a <= 4 && (b < 12 || b > 14) ? ' дні' : ' днів'); } }
  };
  TX = TX[LG] || TX.cs;
  var DAY = 864e5, today = new Date().toISOString().slice(0, 10); // jako buňky kalendáře (UTC)

  // ---- 1) rychlá kontrola adresy (tento soubor se načítá před spuštěním MG._rezInit) ----
  function okIso(s) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(s || '')) return false;
    var t = Date.UTC(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10));
    return !isNaN(t) && new Date(t).toISOString().slice(0, 10) === s;
  }
  if (P.start || P.end) {
    var bad = !okIso(P.start) || (P.end && !okIso(P.end)) || P.start < today || (P.end && P.end < P.start);
    if (bad) { P.start = ''; P.end = ''; }
  }
  var want = !!(P.moto && P.start && P.end && !P.resume), verified = false, sec = null;

  function R() { return MG._rez || {}; }
  function $(id) { return d.getElementById(id); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function ms(iso) { return Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10)); }
  function count(a, b) { return Math.round((ms(b) - ms(a)) / DAY) + 1; }
  function fmt(iso, yr) {
    var o = { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' };
    if (yr) o.year = 'numeric';
    try { return new Intl.DateTimeFormat(LG, o).format(new Date(ms(iso))); } catch (e) { return iso; }
  }
  function moto() { var r = R(), l = r.motos || []; for (var i = 0; i < l.length; i++) if (l[i] && l[i].id === r.motoId) return l[i]; return null; }

  // Termín z adresy je pořád ten vybraný, motorka v nabídce, každý den volný, min/max dní motorky
  function valid() {
    var r = R(), m = moto();
    if (!m || r.motoId !== P.moto || r.startDate !== P.start || r.endDate !== P.end || P.start < today) return false;
    if (!r.allBookings || !r.allBookings[m.id] || typeof MG._rezDateStatus !== 'function') return false;
    for (var t = ms(P.start), e = ms(P.end); t <= e; t += DAY) if (MG._rezDateStatus(new Date(t).toISOString().slice(0, 10)) !== 'free') return false;
    var n = count(P.start, P.end), mn = parseInt(m.min_rental_days, 10) || 1, mx = parseInt(m.max_rental_days, 10) || 0;
    return n >= mn && !(mx > 0 && n > mx);
  }

  function sumHtml() {
    var y = P.start.slice(0, 4) !== today.slice(0, 4) || P.end.slice(0, 4) !== P.start.slice(0, 4);
    var nw = function (t) { return '<span class="ux-cal-d">' + esc(t) + '</span>'; }; // datum se nezalomí uvnitř
    var dt = P.start === P.end ? nw(fmt(P.start, y)) : nw(fmt(P.start, y && P.start.slice(0, 4) !== P.end.slice(0, 4)) + ' –') + ' ' + nw(fmt(P.end, y));
    return '<span class="ux-cal-ok" aria-hidden="true"></span><span class="ux-cal-tx"><small>' + esc(TX.sel) + '</small><b>' + dt + '</b>' +
      '<span class="ux-cal-n">' + esc(TX.days(count(P.start, P.end))) + '</span></span>' +
      '<button type="button" class="ux-cal-chg" aria-expanded="false" aria-controls="rez-calendar" aria-label="' + esc(TX.aria) + '">' + esc(TX.chg) + '</button>';
  }
  function collapse(s) {
    if (!s || s.classList.contains('ux-collapsed') || s._uxDone) return;
    s._uxDone = 1; sec = s; // jen jednou (příchod z detailu); po rozbalení se znovu nesbaluje
    var box = d.createElement('div');
    box.className = 'ux-cal-sum'; box.innerHTML = sumHtml();
    var h = s.querySelector('.rez-section-head');
    if (h && h.nextSibling) s.insertBefore(box, h.nextSibling); else s.appendChild(box);
    s.classList.add('ux-collapsed');
    box.querySelector('.ux-cal-chg').addEventListener('click', function () { expand(s, true); });
  }
  // Rozbalit (Změnit / neplatný termín / rezervace-next.js); výběr termínu zůstává, další klik vybírá znovu
  function expand(s, go) {
    s = s || sec;
    if (!s || !s.classList.contains('ux-collapsed')) return;
    s.classList.remove('ux-collapsed', 'ux-cal-verified');
    var box = s.querySelector('.ux-cal-sum'); if (box) box.parentNode.removeChild(box);
    if (!go) return;
    if (typeof MG._rezRenderCal === 'function' && R().calYear != null) MG._rezRenderCal();
    var c = $('rez-calendar'), rm = !!(w.matchMedia && w.matchMedia('(prefers-reduced-motion: reduce)').matches);
    if (c) {
      c.scrollIntoView({ behavior: rm ? 'auto' : 'smooth', block: 'start' });
      var f = c.querySelector('.cal-day.sel-start') || c.querySelector('.cal-day.free');
      if (f) { f.setAttribute('tabindex', '-1'); try { f.focus({ preventScroll: true }); } catch (e) {} }
    }
  }
  MG._uxExpandStep = expand;

  function check() {
    if (!sec || !sec.classList.contains('ux-collapsed')) return;
    if (valid()) { verified = true; sec.classList.add('ux-cal-verified'); } else expand(sec, false);
  }

  if (want) {
    // sbalit hned, jak jádro vykreslí sekci 2 (bez probliknutí prázdného kalendáře při načítání obsazenosti)
    var app = $('rezervace-app'), tries = 0, mo = null;
    var look = function () { var s = $('rez-step-cal'); if (s && !s._uxDone) { collapse(s); if (mo) mo.disconnect(); } };
    if (app && w.MutationObserver) { mo = new MutationObserver(look); mo.observe(app, { childList: true, subtree: true }); }
    look();
    // pojistka: obsazenost se nenačetla / init spadl → po 15 s rozbalit (formulář jako dřív)
    setTimeout(function () { if (sec && !verified) expand(sec, false); if (mo) mo.disconnect(); }, 15000);
    (function hook() {
      if (typeof MG._rezUpdateBanner !== 'function' || typeof MG._rezResetDates !== 'function' || typeof MG._rezRenderCal !== 'function') {
        if (++tries < 100) setTimeout(hook, 50);
        return;
      }
      var ub = MG._rezUpdateBanner, rd = MG._rezResetDates, rc = MG._rezRenderCal;
      // konečné ověření: jádro volá banner až po await MG._rezLoadCalendar() (obsazenost je načtená)
      MG._rezUpdateBanner = function () { var x = ub.apply(this, arguments); if (!verified) check(); return x; };
      // termín zrušen (jiná motorka / pobočka, min. dní, „Zrušit výběr“) → rozbalit
      MG._rezResetDates = function () { var x = rd.apply(this, arguments); expand(sec, false); return x; };
      // 30s obnova obsazenosti překresluje kalendář → termín musí zůstat celý volný
      MG._rezRenderCal = function () { var x = rc.apply(this, arguments); if (verified) check(); return x; };
    })();
  }
})();
