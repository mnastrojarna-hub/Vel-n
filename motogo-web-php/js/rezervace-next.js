/* ===== MotoGo24 — Rezervace: „Pokračovat“ v souhrnu = první nedokončený krok shora (2026-10-22) =====
   Tlačítko souhrnu (.rz-sum-go z js/rezervace-v2.js — boční panel na desktopu, spodní lišta na mobilu)
   dřív vždy sjelo na spodní CTA. Teď (capture na dokumentu = před handlerem v2) najede na PRVNÍ krok
   shora, který není hotový, a zvýrazní první chybějící pole. Kontroly = stejné podmínky jako
   MG._submitReservation (pages-rezervace-steps.js) + MG._rezValidatePickupTime, v pořadí formuláře.
   Kroky s výchozími hodnotami / volitelné (4 převzetí, 5 výbava) jsou „hotové“ až když je zákazník
   viděl nebo v nich něco změnil — jinak by je tlačítko přeskočilo. Vše hotové → původní chování
   (posun na spodní CTA). Odesílá jen původní CTA, tento soubor nic neodesílá.
   Krok 2 sbalený termínem z detailu motorky (js/rezervace-dates.js, .ux-collapsed) = hotový, má-li
   MG._rez termín; jinak se rozbalí přes MG._uxExpandStep. Načítá se jen ve v2 (pages/rezervace.php),
   vzhled zvýraznění css/rezervace-dates.css. */
(function () {
  'use strict';
  var d = document, w = window;
  var RM = !!(w.matchMedia && w.matchMedia('(prefers-reduced-motion: reduce)').matches);
  var TOUCH = !!(w.matchMedia && w.matchMedia('(hover: none) and (pointer: coarse)').matches);
  var SOFT = { loc: 1, gear: 1 }; // kroky s výchozími hodnotami / volitelné → zastavit, dokud je zákazník neviděl
  var seen = {};
  function M() { return w.MG || {}; }
  function R() { return M()._rez || {}; }
  function $(id) { return d.getElementById(id); }
  function v(id) { var e = $(id); return e && e.value ? String(e.value).trim() : ''; }
  function on(id) { var e = $(id); return !!(e && e.checked); }
  function vis(e) { return !!(e && e.getClientRects().length); }
  function T(k) { var t = M().t ? M().t(k) : ''; return t && t !== k ? String(t).replace(/<[^>]*>/g, '') : ''; }
  function sec(e) { return e && e.closest ? e.closest('.rez-section') : null; }
  function branchType() {
    var r = R(), id = r.motoId || r.selectedMotoId, l = r.motos || [];
    for (var i = 0; i < l.length; i++) if (l[i] && l[i].id === id) return (l[i].branches || {}).type || '';
    return '';
  }

  // Kroky shora. Každý vrací null (hotovo) nebo { el: pole k zvýraznění, msg: klíč existující hlášky rez.alert.* }
  var STEPS = [
    { k: 'moto', s: function () { return $('rez-step-moto'); }, chk: function (r) {
      if (r.motoId || r.selectedMotoId) return null;
      var av = $('rez-avail-dropdown'); // termín vybraný bez motorky → seznam volných pod kalendářem
      if (r.startDate && av && vis($('rez-avail-select'))) return { el: av._uxBtn || av, sec: $('rez-step-cal'), msg: 'rez.alert.moto' };
      var md = $('rez-moto-dropdown'); return { el: md && (md._uxBtn || md), msg: 'rez.alert.moto' };
    } },
    { k: 'cal', s: function () { return $('rez-step-cal'); }, chk: function (r) {
      return r.startDate && r.endDate ? null : { el: $('rez-calendar'), msg: 'rez.alert.dates' };
    } },
    { k: 'contact', s: function () { return sec($('rez-name')); }, chk: function () {
      var G = M(), em = v('rez-email');
      if (!(G._isNameValid ? G._isNameValid(v('rez-name')) : v('rez-name').length > 1)) return { el: $('rez-name'), msg: 'rez.alert.name' };
      if (v('rez-street').length < 3) return { el: $('rez-street'), msg: 'rez.alert.street' };
      if (!v('rez-zip')) return { el: $('rez-zip'), msg: 'rez.alert.zip' };
      if (v('rez-city').length < 2) return { el: $('rez-city'), msg: 'rez.alert.city' };
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(em)) return { el: $('rez-email'), msg: 'rez.alert.email' };
      if (!(G._isPhoneValid ? G._isPhoneValid(v('rez-phone')) : v('rez-phone'))) return { el: $('rez-phone'), msg: 'rez.alert.phone' };
      if (!v('rez-dob')) {
        var f = ['rez-dob-day', 'rez-dob-month', 'rez-dob-year'].map($).filter(function (e) { return e && !e.value; })[0];
        return { el: f || $('rez-dob-day'), msg: 'rez.alert.dob' };
      }
      return null;
    } },
    { k: 'loc', s: function () { return sec($('rez-pickup-time')); }, chk: function () {
      var G = M(), dl = on('rez-delivery');
      if (!v('rez-pickup-time')) return { el: $('rez-pickup-time'), msg: 'rez.alert.pickupTime' };
      if (G._rezValidatePickupTime && !G._rezValidatePickupTime()) return { el: $('rez-pickup-time'), msg: dl ? 'rez.alert.minTimeDelivery' : branchType() === 'samoobslužná' ? 'rez.alert.minTimeSelfService' : 'rez.alert.minTime' };
      if (dl && !v('rez-delivery-address')) return { el: $('rez-delivery-address'), msg: 'rez.pickup.deliveryAddr' };
      if (on('rez-return-other') && !v('rez-return-address')) return { el: $('rez-return-address'), msg: 'rez.pickup.returnAddr' };
      if (!v('rez-return-time')) return { el: $('rez-return-time'), msg: 'rez.alert.returnTime' };
      return null;
    } },
    { k: 'gear', s: function () { return $('rez-step-gear'); }, chk: function (r) {
      var G = M(); if (!G._rezGearPick || !G._rezGearTicks) return null;
      var miss = G._rezGearPick(r.sizes, G._rezGearTicks()).missing, c = miss && $(miss);
      if (!c) return null;
      var row = c.querySelector('.size-pick[data-empty="1"]'), chip = row && row.closest('.size-row') && row.closest('.size-row').querySelector('.size-chip');
      return { el: chip || c, box: c, msg: 'rez.alert.gearSize' };
    } },
    { k: 'agree', s: function () { return sec($('rez-agree-vop')); }, chk: function (r) {
      if (!on('rez-agree-vop')) return { el: $('rez-agree-vop'), msg: 'rez.alert.terms' };
      if (!on('rez-agree-gdpr')) return { el: $('rez-agree-gdpr'), msg: 'rez.alert.gdpr' };
      if (r.isChildMoto && !on('rez-agree-guardian')) return { el: $('rez-agree-guardian'), msg: 'rez.alert.guardian' };
      return null;
    } }
  ];

  // první nedokončený krok shora → { s: sekce, el, msg } | null (vše hotové)
  function firstOpen() {
    var r = R();
    for (var i = 0; i < STEPS.length; i++) {
      var st = STEPS[i], s = st.s();
      if (!s) continue;
      var p = st.chk(r);
      if (p) return { k: st.k, s: p.sec || s, el: p.el, box: p.box, msg: p.msg };
      if (SOFT[st.k] && !seen[st.k] && vis(s)) return { k: st.k, s: s, el: null, soft: 1 };
    }
    return null;
  }

  // „viděl“ = krok byl aktuálním krokem (nadpis v horních ~40 % okna, jako ukazatel kroků v rezervace-v2.js)
  // nebo v něm zákazník sám něco změnil; programové změny (isTrusted=false) se nepočítají
  function keyOf(s) { for (var i = 0; i < STEPS.length; i++) if (STEPS[i].s() === s) return STEPS[i].k; return ''; }
  var raf = 0;
  function look() {
    raf = 0;
    var vh = w.innerHeight || 800;
    STEPS.forEach(function (st) {
      if (!SOFT[st.k] || seen[st.k]) return;
      var s = st.s(), r = s && vis(s) ? s.getBoundingClientRect() : null;
      if (r && r.top <= vh * 0.4 && r.bottom >= vh * 0.3) seen[st.k] = 1;
    });
  }
  w.addEventListener('scroll', function () { if (!raf) raf = w.requestAnimationFrame ? w.requestAnimationFrame(look) : setTimeout(look, 16); }, { passive: true });
  ['change', 'input', 'click'].forEach(function (t) {
    d.addEventListener(t, function (e) { var s = sec(e.target), k = s && keyOf(s); if (k && e.isTrusted) seen[k] = 1; if (cur && !cur.soft) later(); }, true);
  });

  // zvýraznění + hláška (texty rez.alert.* už jsou v MG_I18N ve všech 8 jazycích)
  var cur = null, tm = 0;
  function clear() {
    if (!cur) return;
    cur.s.classList.remove('ux-need-sec');
    if (cur.f) { cur.f.classList.remove('ux-need'); cur.f.removeAttribute('aria-invalid'); }
    if (cur.m && cur.m.parentNode) cur.m.parentNode.removeChild(cur.m);
    cur = null;
  }
  function later() { clearTimeout(tm); tm = setTimeout(function () { if (!cur || cur.soft) return; var o = firstOpen(); if (!o || o.s !== cur.s || o.el !== cur.el) clear(); }, 120); }
  function mark(o) {
    clear();
    var s = o.s, f = o.box || (o.el && o.el.type === 'checkbox' && o.el.closest('label')) || o.el, txt = o.msg ? T(o.msg) : '', m = null;
    s.classList.add('ux-need-sec');
    if (f && f !== s && !o.soft) { f.classList.add('ux-need'); if (/^(INPUT|SELECT|TEXTAREA)$/.test(f.tagName)) f.setAttribute('aria-invalid', 'true'); }
    if (txt) {
      m = d.createElement('p'); m.className = 'ux-need-msg'; m.setAttribute('role', 'status'); m.textContent = txt;
      var h = s.querySelector('.rez-section-head'); if (h && h.nextSibling) s.insertBefore(m, h.nextSibling); else s.appendChild(m);
    }
    cur = { s: s, f: f, el: o.el, m: m, soft: o.soft };
    if (o.soft) setTimeout(function () { if (cur && cur.s === s && cur.soft) clear(); }, 2600);
  }
  function expand(s) {
    // krok sbalený jinou úpravou (např. termín z detailu motorky) → rozbalit
    if (s.classList.contains('ux-collapsed')) { if (typeof M()._uxExpandStep === 'function') M()._uxExpandStep(s); else s.classList.remove('ux-collapsed'); }
    var rf = $('rez-form');
    // přihlášený s neúplným profilem: pole jsou skrytá třídou .rez-logged-in (css/main.css:29-33) → ukázat; ne přes
    // MG._rezAuth._expandFields (sám fokusuje a posouvá na #rez-name → přebil by náš posun)
    if (rf && s.contains($('rez-name'))) rf.classList.remove('rez-logged-in');
    if (s.classList.contains('rz-rv')) s.classList.add('rz-rv-in'); // odhalit hned, ať se neměří s translateY
  }
  function jump(o) {
    var s = o.s, el = o.el;
    expand(s); mark(o); seen[o.k] = 1;
    var vh = w.innerHeight || 800, sr = s.getBoundingClientRect(), er = el && vis(el) ? el.getBoundingClientRect() : sr;
    var top = er.bottom - sr.top < vh * 0.62; // pole je vidět i při zarovnání sekce nahoru → ukázat celý krok od nadpisu
    (top || !el ? s : el).scrollIntoView({ behavior: RM ? 'auto' : 'smooth', block: top || !el ? 'start' : 'center' });
    var done = false, fo = function () {
      if (done) return; done = true;
      // obsah se během plynulého posunu mohl posunout (sbalení karty, hláška) → dorovnat bez animace
      var t = (top || !el ? s : el).getBoundingClientRect(), vh2 = w.innerHeight || 800;
      if (top || !el ? (t.top < -2 || t.top > vh2 * 0.3) : (t.top < 0 || t.bottom > vh2)) (top || !el ? s : el).scrollIntoView({ behavior: 'auto', block: top || !el ? 'start' : 'center' });
      // dotyk: textové pole nefokusovat (klávesnice by zakryla krok i hlášku a v2 skryje spodní lištu) — stačí zvýraznění
      var txt = el && el.tagName === 'INPUT' && !/^(checkbox|radio|button|submit)$/.test(el.type) || el && el.tagName === 'TEXTAREA';
      if (el && el.focus && !o.soft && !(txt && TOUCH)) try { el.focus({ preventScroll: true }); } catch (e) {}
    };
    if ('onscrollend' in w && !RM) { w.addEventListener('scrollend', fo, { once: true }); setTimeout(fo, 900); } else setTimeout(fo, RM ? 0 : 480);
  }

  // veřejné: MG._rezFirstOpen() = stav (null = vše hotové), MG._rezJumpNext() = najet na krok; true = posunuto
  function jumpNext() { if (!$('rez-form') || !vis(d.querySelector('#rez-form .rez-cta'))) return false; var o = firstOpen(); if (!o) { clear(); return false; } jump(o); return true; }
  if (w.MG) { w.MG._rezFirstOpen = firstOpen; w.MG._rezJumpNext = jumpNext; }

  // capture na dokumentu → před handlerem .rz-sum-go v rezervace-v2.js; jen v 1. kroku (formulář s .rez-cta)
  d.addEventListener('click', function (e) {
    var b = e.target && e.target.closest && e.target.closest('.rz-sum-go');
    if (!b || !jumpNext()) return; // vše hotové / 2. krok → původní posun na spodní CTA (rezervace-v2.js)
    e.stopImmediatePropagation(); e.preventDefault();
  }, true);
})();
