/* MotoGo24 — kalkulačka ceny: přistavení na adresu / vrácení jinde (2026-11-27, zadání majitele) — stav a pravidla.
   Kalkulačka tu NEMÁ vlastní vzorec ani pravidlo, všechno volá z rezervačního formuláře:
     komu se přistavení nenabízí ..... MG.DELIVERY.blocked            (js/delivery-rules.js)
     cena za km, našeptávač, trasa ... MG._calcDeliveryFee, _mapySuggest, _ensureBranchCoords, _mapyRouting
     předstih přistavení ............. MG._rezValidatePickupTime      (js/pages-rezervace-pricing.js)
   Součet poplatků = stejné pravidlo jako MG._rezUpdatePrice: přistavení fee(km); „vrácení jinde“ fee(km vrácení);
   jinak „vrátit na stejné adrese“ (výchozí zaškrtnuto) = ještě jednou cena přistavení. Bez trasy fee() = základ.
   Předání do /rezervace: ?delivery=1 / ?return_delivery=1 (K.dvQuery) + adresa a GPS v sessionStorage
   (K.dvSave; bez km a ceny — formulář si je spočítá sám, js/rezervace-delivery-carry.js).
   Vzhled a události: js/landing-calc-delivery-ui.js. Háčky: landing-calc.js (4×), landing-calc-view.js (K.sumHtml). */
(function (w) {
  var K = w.MGKC = w.MGKC || {}, d = document, KEY = 'mg_calc_delivery';
  function mg() { return w.MG || {}; }
  function side() { return { a: '', lat: null, lng: null, km: null, min: null, st: '', q: 0 }; }
  // on = přistavení, same = vrátit na stejné adrese, ro = vrácení jinde; d / r = adresa přistavení / vrácení
  // (st: '' | 'wait' | 'ok' | 'err'). Adresy zůstávají v paměti i po vypnutí volby — jako pole formuláře.
  var D = K.dv = { on: false, same: true, ro: false, cut: false, d: side(), r: side() };

  K.dvReady = function () { var M = mg(); return typeof M._calcDeliveryFee === 'function' && !!M.DELIVERY && typeof M.DELIVERY.blocked === 'function'; };
  // Rozhoduje pobočka VYBRANÉ motorky (bez motorky kalkulačka cenu nepočítá, takže ani přistavení)
  K.dvBlocked = function (X) {
    var m = X.S.moto ? X.by[X.S.moto] : null, b = m ? X.branch(m.b) : null;
    return !!b && !!mg().DELIVERY.blocked(b.ty, !!X.C.ssd);
  };
  K.dvActive = function (X) { return K.dvReady() && !!X.S.moto && !K.dvBlocked(X); };
  // Po změně motorky / pobočky: motorka, u které formulář přistavení zamyká → obě volby vypnout (jako formulář);
  // cut = právě jsme zákazníkovi zvolené přistavení zrušili → krok ukáže vysvětlení rovnou rozbalené
  K.dvCheck = function (X) { if (K.dvReady() && X.S.moto && K.dvBlocked(X)) { D.cut = D.on || D.ro; D.on = D.ro = false; } };
  K.dvFees = function (X) {
    if (!K.dvActive(X)) return { p: 0, r: 0, total: 0 };
    var f = mg()._calcDeliveryFee, p = D.on ? f(D.d.km) : 0, r = D.ro ? f(D.r.km) : (D.on && D.same ? p : 0);
    return { p: p, r: r, total: p + r };
  };
  // Sazba pro texty („1 000 Kč + 40 Kč/km“) — odvozená z funkce formuláře, žádné číslo tady
  K.dvRate = function () { var f = mg()._calcDeliveryFee, b = f(0); return { base: b, perKm: f(1) - b }; };

  // Adresa → GPS → trasa od pobočky, stejnými voláními jako MG._calcRouteFor. hit = řádek z našeptávače
  // (má GPS); bez něj se text geokóduje prvním výsledkem (jako formulář při ručně dopsané adrese).
  K.dvAddr = function (key, text, hit, done) {
    var s = D[key], M = mg(), q = ++s.q;
    s.a = String(text || '').trim(); s.lat = s.lng = s.km = s.min = null; s.st = s.a ? 'wait' : '';
    if (!s.a) { done(); return; }
    function end(st) { if (q === s.q) { s.st = st; done(); } }
    function route(lat, lng) {
      if (typeof lat !== 'number' || typeof lng !== 'number') return end('err');
      s.lat = lat; s.lng = lng;
      M._ensureBranchCoords().then(function (o) { return o ? M._mapyRouting(o.lat, o.lng, lat, lng) : null; }).then(function (rt) {
        if (q !== s.q) return;
        if (rt && rt.distanceKm > 0) { s.km = rt.distanceKm; s.min = rt.durationMin || null; end('ok'); } else end('err');
      }, function () { end('err'); });
    }
    done();
    if (hit) route(hit.lat, hit.lng);
    else M._mapySuggest(s.a, 1).then(function (l) { if (q === s.q) route(l && l[0] && l[0].lat, l && l[0] && l[0].lng); }, function () { end('err'); });
  };

  // Předstih přistavení se ptáme přímo formuláře: MG._rezValidatePickupTime čte #rez-delivery a #rez-pickup-time,
  // tak mu je na okamžik podstrčíme (zaškrtnuté přistavení + zkoušený čas v den vyzvednutí). Bez kopie pravidla „+6 h“.
  function leadOk(iso, time) {
    var M = mg(), R = M._rez;
    if (typeof M._rezValidatePickupTime !== 'function' || !R || d.getElementById('rez-delivery') || d.getElementById('rez-pickup-time')) return true;
    var box = d.createElement('div'), old = R.startDate, ok = true;
    box.hidden = true;
    box.innerHTML = '<input type="checkbox" id="rez-delivery" checked><input type="text" id="rez-pickup-time" value="' + time + '">';
    d.body.appendChild(box);
    try { R.startDate = iso; ok = M._rezValidatePickupTime() !== false; } catch (e) {}
    R.startDate = old; d.body.removeChild(box);
    return ok;
  }
  // '' = v pořádku · 'soon' = den vyzvednutí začíná dřív než za 6 h (čas musí být později) · 'late' = ten den už to nejde
  K.dvLead = function (X) {
    var s = X.S.start;
    if (!s || !D.on || !K.dvActive(X)) return '';
    return !leadOk(s, '23:59') ? 'late' : (leadOk(s, '00:00') ? '' : 'soon');
  };

  K.dvQuery = function (X) {
    var q = [];
    if (K.dvActive(X)) { if (D.on) q.push('delivery=1'); if (D.ro) q.push('return_delivery=1'); }
    return q;
  };
  K.dvSave = function (X) {
    try {
      if (!K.dvQuery(X).length) { sessionStorage.removeItem(KEY); return; }
      var S = X.S, pt = function (s) { return { a: s.a, lat: s.lat, lng: s.lng }; };
      sessionStorage.setItem(KEY, JSON.stringify({ v: 1, ts: Date.now(), moto: S.moto, start: S.start && S.end ? S.start : '', end: S.start && S.end ? S.end : '',
        d: D.on ? pt(D.d) : null, ret: D.ro ? 'other' : (D.on && D.same ? 'same' : 'branch'), r: D.ro ? pt(D.r) : null }));
    } catch (e) {}
  };

  // Řádky do souhrnu (K.sumHtml): názvy = položky rezervace „Přistavení motorky“ / „Vrácení motorky“
  K.dvKm = function (km) { return km.toFixed(1).replace('.', ','); }; // jako formulář (MG._renderRouteInfo)
  var unit = '';
  function kmUnit(X) { // „km“ v jazyce stránky (uk „км“); jen popisek jednotky, číslo formátuje K.dvKm
    if (!unit) try { unit = new Intl.NumberFormat(X.C.lang, { style: 'unit', unit: 'kilometer' }).formatToParts(1).filter(function (p) { return p.type === 'unit'; })[0].value; } catch (e) {}
    return unit || (unit = 'km');
  }
  K.dvRows = function (X) {
    var f = K.dvFees(X), T = X.T, h = '';
    function row(label, s, fee) {
      var known = !!s && s.st === 'ok';
      return '<li class="kc-r-dv"><span class="kc-r-d">' + K.esc(label) + '</span><span class="kc-r-x">' + (known ? K.esc(K.dvKm(s.km) + ' ' + kmUnit(X)) : '') + '</span>' +
        '<span class="kc-r-v">' + K.esc(known ? X.money(fee) : K.tpl(T.dv_from, { price: X.money(fee) })) + '</span></li>';
    }
    if (D.on && f.p > 0) h += row(T.dv_row_d, D.d, f.p);
    if (f.r > 0) h += row(T.dv_row_r, D.ro ? D.r : D.d, f.r);
    return h;
  };
})(window);
