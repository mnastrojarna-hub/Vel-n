/* MotoGo24 — katalog v2: filtr termínu. Kalendář = K.calHtml (js/landing-calc-view.js) v režimu
   „jakákoli motorka“ nad motorkami, které projdou ostatními filtry; obsazenost = RPC
   get_moto_booked_dates (K.fetchBooked, sdílená cache s kalkulačkou). Po výběru termínu zůstanou
   jen motorky volné po CELÝ termín (bez vozíku a motorek s neznámou dostupností, min. délka
   pronájmu), na kartách cena za termín (K.breakdown = MG.calcPriceBreakdown) a „Rezervovat“
   vede na /rezervace?moto=&start=&end=. Volá js/landing-catalog.js přes MGKF.initDates(o). */
(function (w) {
  var d = document, F = w.MGKF = w.MGKF || {}, K = w.MGKC;
  F.initDates = function (o) {
    if (!K || !K.calHtml || !K.fetchBooked || !o.kc || !o.btn) return null;
    var C = o.kc, T = C.t, FT = o.T, today = K.today(), by = {}, sheet, cal, hint, note, show;
    var S = { start: null, end: null, y: +today.slice(0, 4), mo: +today.slice(5, 7) - 1, moto: '', fail: false, note: '', bk: {}, wait: {}, jumped: false };
    C.motos.forEach(function (m) { by[m.id] = m; });
    var all = C.motos.filter(function (m) { return !m.un && !m.tr; }).map(function (m) { return m.id; });
    var esc = K.esc, tpl = K.tpl;
    function pool() {
      return o.motos.filter(function (m) { var k = by[m.id]; return k && !k.un && !k.tr && o.passNoDate(m); }).map(function (m) { return m.id; });
    }
    function ready() { return all.every(function (id) { return !!S.bk[id]; }); }
    function st(iso) {
      if (iso < today) return 'past';
      var ids = pool(), pend = false;
      for (var i = 0; i < ids.length; i++) {
        var v = (S.bk[ids[i]] || {})[iso];
        if (!v) return 'free';
        if (v === 'pending') pend = true;
      }
      return pend ? 'pending' : 'busy';
    }
    function fmt(iso, op) {
      try { var p = { timeZone: 'UTC' }; for (var k in op) p[k] = op[k]; return new Intl.DateTimeFormat(C.lang, p).format(new Date(K.ms(iso))); } catch (e) { return iso; }
    }
    function days(n) { return tpl(n === 1 ? T.days_one : (n >= 2 && n <= 4 ? T.days_few : T.days_many), { n: n }); }
    var X = { S: S, T: T, C: C, by: {}, today: today, st: st, ready: ready, fmt: fmt, money: function (v) { return K.money(C.cur, v); } };
    function active() { return !!(S.start && S.end); }
    function range() {
      if (!active()) return '';
      var md = { day: 'numeric', month: 'short' };
      if (S.start === S.end) return fmt(S.start, md);
      return (S.start.slice(0, 7) === S.end.slice(0, 7) ? fmt(S.start, { day: 'numeric' }) : fmt(S.start, md)) + ' – ' + fmt(S.end, md);
    }

    // --- Obsazenost ---
    function load() {
      var need = all.filter(function (id) { return !S.bk[id] && !S.wait[id]; });
      if (!need.length) return;
      S.fail = false;
      need.forEach(function (id) {
        S.wait[id] = K.fetchBooked(C.sb, id, today).then(function (map) { S.bk[id] = map; }, function () { S.fail = true; }).then(function () {
          delete S.wait[id];
          if (Object.keys(S.wait).length) return;
          if (ready() && !S.start && !S.jumped) jump();
          render();
          o.apply();
        });
      });
    }
    function jump() {
      S.jumped = true;
      for (var x = today, i = 0; i < 400; x = K.add(x, 1), i++) if (st(x) === 'free') { S.y = +x.slice(0, 4); S.mo = +x.slice(5, 7) - 1; return; }
    }

    // --- Výběr dnů (jako kalkulačka: 1. klik vyzvednutí, 2. vrácení) ---
    function pick(iso) {
      S.note = '';
      if (!S.start || S.end || iso < S.start) { S.start = iso; S.end = null; }
      else {
        for (var x = K.add(S.start, 1); x < iso; x = K.add(x, 1)) {
          if (st(x) !== 'free') { S.note = T.range_busy; render(); return; }
        }
        S.end = iso;
      }
      render();
      o.apply();
    }
    function clear() { S.start = S.end = null; S.note = ''; render(); o.apply(); }

    // --- Vykreslení ---
    function render() {
      if (!sheet) return;
      var a = d.activeElement, key = a && cal.contains(a) ? (a.getAttribute('data-d') ? '[data-d="' + a.getAttribute('data-d') + '"]' : (a.getAttribute('data-nav') ? '[data-nav="' + a.getAttribute('data-nav') + '"]' : '')) : '';
      cal.innerHTML = K.calHtml(X);
      cal.classList.toggle('is-wait', !ready() || S.fail);
      if (key) { var nb = cal.querySelector(key); if (nb && !nb.disabled) nb.focus({ preventScroll: true }); }
      hint.textContent = !S.start ? T.hint_start : (!S.end ? T.hint_end : T.hint_done);
      note.textContent = S.note || T.cal_any;
      note.classList.toggle('is-warn', !!S.note);
      show.textContent = tpl(FT.f_show, { count: o.plural(o.count()) });
    }
    // Cena za termín na kartách + odkaz do rezervace s termínem
    function cards() {
      var on = active(), n = on ? K.count(S.start, S.end) : 0, ico = K.ico('cal');
      Object.keys(o.cards).forEach(function (id) {
        var li = o.cards[id], k = by[id], pe = li.querySelector('[data-kf-price]'), bk = li.querySelector('[data-kf-book]');
        if (!pe || !bk) return;
        if (!li._kf) li._kf = { p: pe.innerHTML, h: bk.getAttribute('href'), l: bk.innerHTML };
        var key = on && k && !k.tr ? S.start + S.end : '';
        if (li._kfKey === key) return;
        li._kfKey = key;
        if (key) {
          pe.innerHTML = '<span class="kf-days">' + esc(days(n)) + '</span><span class="kf-total">' + esc(K.money(C.cur, K.breakdown(k, S.start, S.end).total, 0)) + '</span>';
          bk.setAttribute('href', C.rez + '?moto=' + encodeURIComponent(id) + '&start=' + S.start + '&end=' + S.end);
          bk.innerHTML = ico + '<span>' + esc(T.cta) + '</span>';
        } else {
          pe.innerHTML = li._kf.p; bk.setAttribute('href', li._kf.h); bk.innerHTML = li._kf.l;
        }
        bk.classList.toggle('is-dates', !!key);
      });
    }

    // --- Sheet ---
    sheet = d.createElement('div');
    sheet.className = 'kf-dates';
    sheet.id = 'kf-dates';
    sheet.setAttribute('aria-labelledby', 'kf-dates-t');
    var lg = ['free', 'busy', 'pending', 'sel'].map(function (k) { return '<li class="kc-lg kc-lg--' + k + '"><i aria-hidden="true"></i>' + esc(T['legend_' + k]) + '</li>'; }).join('');
    sheet.innerHTML = '<div class="kf-sheet-head"><p class="kf-sheet-t" id="kf-dates-t">' + K.ico('cal') + esc(FT.f_dates_title) + '</p>' +
      '<button type="button" class="kf-x" data-kf-close aria-label="' + esc(FT.f_close) + '">' + K.ico('x') + '</button></div>' +
      '<div class="kf-sheet-body"><p class="kf-dates-lead">' + esc(FT.f_dates_lead) + '</p><p class="kf-dates-hint" data-kf-hint aria-live="polite"></p>' +
      '<div class="kc-cal-box" data-kf-cal></div><ul class="kc-legend">' + lg + '</ul><p class="kc-note" data-kf-note></p></div>' +
      '<div class="kf-foot"><button type="button" class="kf-reset" data-kf-dclear>' + esc(T.reset) + '</button>' +
      '<button type="button" class="lp-btn lp-btn-primary kf-apply" data-kf-done><span data-kf-dshow></span></button></div>';
    o.bar.appendChild(sheet);
    cal = sheet.querySelector('[data-kf-cal]'); hint = sheet.querySelector('[data-kf-hint]'); note = sheet.querySelector('[data-kf-note]'); show = sheet.querySelector('[data-kf-dshow]');
    sheet.addEventListener('click', function (ev) {
      var b = ev.target.closest('button');
      if (!b || b.disabled) return;
      if (b.hasAttribute('data-kf-close')) F.closeSheet();
      else if (b.hasAttribute('data-kf-done')) { F.closeSheet(); if (o.done) o.done(); }
      else if (b.hasAttribute('data-kf-dclear')) clear();
      else if (b.hasAttribute('data-nav')) {
        S.mo += +b.getAttribute('data-nav');
        if (S.mo < 0) { S.mo = 11; S.y--; } else if (S.mo > 11) { S.mo = 0; S.y++; }
        render();
      } else if (b.hasAttribute('data-retry')) { S.fail = false; load(); render(); }
      else if (b.getAttribute('data-d')) pick(b.getAttribute('data-d'));
    });
    cal.addEventListener('mouseover', function (ev) {
      if (!S.start || S.end) return;
      var b = ev.target.closest('[data-d]'), to = b && !b.disabled ? b.getAttribute('data-d') : '';
      Array.prototype.forEach.call(cal.querySelectorAll('[data-d]'), function (x) { var v = x.getAttribute('data-d'); x.classList.toggle('is-hover', !!to && v > S.start && v <= to); });
    });
    o.btn.classList.add('kf-btn--date');
    o.btn.hidden = false;
    o.btn.addEventListener('click', function () { load(); render(); F.openSheet(sheet, o.btn); });

    // Termín z URL (?start=&end=, např. po přechodu mezi kategoriemi)
    try {
      var u = new URLSearchParams(w.location.search), s0 = u.get('start') || '', e0 = u.get('end') || '', re = /^\d{4}-\d{2}-\d{2}$/;
      if (re.test(s0) && re.test(e0) && s0 >= today && e0 >= s0 && K.count(s0, e0) <= 400) {
        S.start = s0; S.end = e0; S.y = +s0.slice(0, 4); S.mo = +s0.slice(5, 7) - 1; S.jumped = true;
        load();
      }
    } catch (e) {}

    return {
      active: active, range: range, clear: clear,
      start: function () { return S.start; }, end: function () { return S.end; },
      busy: function () { return active() && (!ready() || S.fail); },
      fail: function () { return active() && S.fail; },
      chip: function () { return active() ? range() + ' · ' + days(K.count(S.start, S.end)) : ''; },
      // free(m): true/false, null = obsazenost se ještě načítá (karta zůstane vidět)
      free: function (m) {
        if (!active()) return true;
        var k = by[m.id];
        if (!k || k.un || k.tr || K.count(S.start, S.end) < (k.min || 1)) return false;
        var b = S.bk[m.id];
        if (!b) return null;
        for (var x = S.start; x <= S.end; x = K.add(x, 1)) if (b[x]) return false;
        return true;
      },
      update: function () {
        cards();
        var on = active(), l = o.btn.querySelector('.kf-btn-l');
        if (l) l.textContent = on ? range() : FT.f_dates;
        o.btn.classList.toggle('is-set', on);
        o.btn.setAttribute('aria-label', on ? FT.f_dates + ': ' + range() : FT.f_dates);
        if (F.openEl() === sheet) render(); else if (show) show.textContent = tpl(FT.f_show, { count: o.plural(o.count()) });
      }
    };
  };
})(window);
