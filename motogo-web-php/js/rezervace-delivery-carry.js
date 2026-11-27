/* ===== MotoGo24 — Rezervace: přistavení zvolené v kalkulačce ceny se přenese do formuláře (2026-11-27) =====
   Kalkulačka (js/landing-calc-delivery.js) posílá /rezervace?moto=&start=&end=&delivery=1[&return_delivery=1]
   a adresu s GPS nechává v sessionStorage['mg_calc_delivery'] (do adresy URL nepatří — osobní údaj).
   Tento soubor jádro formuláře jen obaluje (jako rezervace-dates.js) a NIC nepočítá: vyplní VLASTNÍ pole
   formuláře a zavolá jeho vlastní výpočet trasy MG._calcRouteFor — cenu, zámek samoobsluhy, předstih 6 h
   i dostupnost si formulář ověří sám jako při ručním zadání.
   Záznam se použije jen když sedí na adresu stránky (motorka + termín), není starší než 24 h a nejde o
   ?resume. Bez platného záznamu se neděje NIC — formulář se chová přesně jako dřív (samotné ?delivery=1
   dál jen zaškrtne přistavení, ?return_delivery=1 bez záznamu nedělá nic). Nejde-li volba použít
   (motorka ze samoobsluhy → zamčeno, trasu nejde spočítat), platí běžné chování formuláře.
   Záznam: { v:1, ts, moto, start, end, d:{a,lat,lng}|null, ret:'same'|'branch'|'other', r:{a,lat,lng}|null }. */
(function () {
  'use strict';
  var w = window, d = document, MG = w.MG || {}, P = w.REZERVACE_PARAMS || {}, KEY = 'mg_calc_delivery', TTL = 864e5;
  if (P.resume || (P.delivery !== '1' && P.returnDelivery !== '1') || typeof MG._rezBindNav !== 'function') return;

  function point(p) {
    if (!p || typeof p.a !== 'string' || p.a.length > 300) return null;
    var ok = typeof p.lat === 'number' && typeof p.lng === 'number' && isFinite(p.lat) && isFinite(p.lng);
    return { a: p.a.trim(), lat: ok ? p.lat : null, lng: ok ? p.lng : null };
  }
  function read() {
    try {
      var r = JSON.parse(sessionStorage.getItem(KEY) || 'null');
      if (!r || r.v !== 1 || !(Date.now() - r.ts < TTL) || !r.moto || r.moto !== (P.moto || '')) return null;
      if ((r.start || '') !== (P.start || '') || (r.end || '') !== (P.end || '')) return null;
      return { d: point(r.d), ret: r.ret, r: point(r.r) };
    } catch (e) { return null; }
  }
  function $(id) { return d.getElementById(id); }
  function fire(el) { el.dispatchEvent(new Event('change', { bubbles: true })); }
  // Stejné kroky jako výběr adresy z našeptávače formuláře (MG._attachMapyAutocomplete)
  function fill(type, p) {
    var inp = $('rez-' + type + '-address');
    if (!inp || !p || !p.a || typeof MG._calcRouteFor !== 'function' || !MG._rez) return;
    inp.value = p.a;
    MG._rez['_' + type + 'RouteAddr'] = p.a;
    fire(inp);
    if (p.lat === null) MG._calcRouteFor(type); else MG._calcRouteFor(type, p.lat, p.lng);
  }
  function apply() {
    var rec = read();
    if (!rec || !$('rez-form')) return;
    var del = $('rez-delivery'), ro = $('rez-return-other'), same = $('rez-return-same-as-delivery');
    // přistavení: zaškrtlo ho jádro z ?delivery=1; u motorky ze samoobsluhy ho zámek hned zase vypnul → nepřenášíme nic
    var on = !!(rec.d && P.delivery === '1' && del && del.checked && !del.disabled);
    // vrácení řešíme PŘED trasou přistavení (formulář kopíruje km přistavení do vrácení, dokud je „stejná adresa“ zaškrtnutá)
    if (rec.ret === 'other' && P.returnDelivery === '1') {
      if (ro && !ro.disabled) { if (!ro.checked) { ro.checked = true; fire(ro); } fill('return', rec.r); }
    } else if (rec.ret === 'branch' && on && same && same.checked) { same.checked = false; fire(same); }
    if (on) fill('delivery', rec.d);
  }

  // Konec MG._rezInit = jediné volání MG._rezBindNav('form'): formulář je vykreslený, ?delivery=1 zaškrtnuté
  // a zámek samoobsluhy uplatněný (pages-rezervace-selfservice.js; flag se dočte dřív, než init doběhne).
  var orig = MG._rezBindNav, done = false;
  MG._rezBindNav = function (step) {
    var x = orig.apply(this, arguments);
    if (step === 'form' && !done) {
      done = true;
      setTimeout(function () { try { apply(); } catch (e) { if (w.console) console.warn('[REZ] delivery carry skipped:', e); } }, 0);
    }
    return x;
  };
})();
