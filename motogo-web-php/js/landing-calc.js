/* MotoGo24 — kalkulačka ceny v katalogu (landing v2, pages/katalog-calc.php): stav, události,
   načítání obsazenosti, mobilní lišta s cenou a tlačítka „Spočítat cenu“ na kartách motorek.
   HTML staví landing-calc-view.js, výpočty landing-calc-core.js. */
(function () {
  var d = document, K = window.MGKC, root = d.querySelector('[data-kc]'), dataEl = d.getElementById('kc-data');
  if (!root || !K || !K.calHtml || !dataEl) return;
  var C;
  try { C = JSON.parse(dataEl.textContent); } catch (e) { return; }
  d.documentElement.classList.add('lp-js');
  var T = C.t, by = {}, today = K.today(), CZK = { code: 'CZK', rate: 1, dec: 0, sym: 'Kč' };
  var rm = !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
  C.motos.forEach(function (m) { by[m.id] = m; });
  var S = { branch: '', moto: '', start: null, end: null, y: +today.slice(0, 4), mo: +today.slice(5, 7) - 1, bk: {}, wait: {}, fail: false, live: false, note: '', shown: 0 };
  var q = function (s) { return root.querySelector(s); };
  var E = { sel: q('#kc-moto'), card: q('[data-kc-moto]'), cal: q('[data-kc-cal]'), hint: q('[data-kc-hint]'), note: q('[data-kc-note]'), sum: q('[data-kc-sum]') };
  var radios = root.querySelectorAll('input[name="kc-branch"]'), each = function (l, f) { Array.prototype.forEach.call(l, f); };

  function inB(m) { return !S.branch || m.b === S.branch; }
  function pool() { return S.moto ? [S.moto] : C.motos.filter(function (m) { return inB(m) && !m.un && !m.tr; }).map(function (m) { return m.id; }); }
  function ready() { return pool().every(function (id) { return !!S.bk[id]; }); }
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
  function firstFree() { for (var x = today, i = 0; i < 400; x = K.add(x, 1), i++) if (st(x) === 'free') return x; return null; }
  function fmt(iso, o) {
    try { var p = { timeZone: 'UTC' }; for (var k in o) p[k] = o[k]; return new Intl.DateTimeFormat(C.lang, p).format(new Date(K.ms(iso))); } catch (e) { return iso; }
  }
  var X = {
    C: C, T: T, S: S, by: by, today: today, st: st, pool: pool, ready: ready, firstFree: firstFree, fmt: fmt,
    money: function (v) { return K.money(C.cur, v); }, czk: function (v) { return K.money(CZK, v); },
    days: function (n) { return K.tpl(n === 1 ? T.days_one : (n >= 2 && n <= 4 ? T.days_few : T.days_many), { n: n }); },
    branch: function (id) { for (var i = 0; i < C.branches.length; i++) if (C.branches[i].id === id) return C.branches[i]; return null; },
    cat: function (k) { for (var i = 0; i < C.cats.length; i++) if (C.cats[i].k === k) return C.cats[i].l; return ''; },
    href: function () {
      var p = [];
      if (S.moto) p.push('moto=' + encodeURIComponent(S.moto)); else if (S.branch) p.push('pobocka=' + encodeURIComponent(S.branch));
      if (S.start && S.end) p.push('start=' + S.start, 'end=' + S.end);
      return C.rez + (p.length ? '?' + p.join('&') : '');
    }
  };

  // --- Načtení obsazenosti (lazy: až je kalkulačka vidět nebo se s ní pracuje) ---
  function load() {
    if (!S.live) return;
    var need = pool().filter(function (id) { return !S.bk[id] && !S.wait[id]; });
    if (!need.length) return;
    S.fail = false;
    need.forEach(function (id) {
      S.wait[id] = K.fetchBooked(C.sb, id, today).then(function (map) { S.bk[id] = map; }, function () { S.fail = true; }).then(function () {
        delete S.wait[id];
        if (Object.keys(S.wait).length) return;
        if (ready()) { check(); if (!S.start) jump(); }
        render();
      });
    });
  }
  function jump() { var f = firstFree(); if (f) { S.y = +f.slice(0, 4); S.mo = +f.slice(5, 7) - 1; } }
  // Termín musí být volný i po změně motorky/pobočky (jinak ho zrušíme s vysvětlením)
  function check() {
    if (!S.start || !ready()) return;
    for (var x = S.start; x <= (S.end || S.start); x = K.add(x, 1)) {
      if (st(x) !== 'free') { S.start = S.end = null; S.note = S.moto ? T.moto_busy : T.range_busy; return; }
    }
  }

  // --- Výběr ---
  function fillSel() {
    var h = '<option value="">' + K.esc(T.moto_any) + '</option>';
    C.cats.forEach(function (g) {
      var list = C.motos.filter(function (m) { return m.c === g.k && inB(m); });
      if (!list.length) return;
      h += '<optgroup label="' + K.esc(g.l) + '">';
      list.forEach(function (m) {
        var tag = m.un ? ' · ' + T.moto_unavail : (m.st === 'maintenance' ? ' · ' + T.moto_maint : '');
        h += '<option value="' + K.esc(m.id) + '"' + (m.un ? ' disabled' : '') + '>' + K.esc(m.m + (m.from > 0 ? ' — ' + K.tpl(T.from, { price: X.money(m.from) }) : '') + tag) + '</option>';
      });
      h += '</optgroup>';
    });
    E.sel.innerHTML = h;
    E.sel.value = S.moto;
  }
  function changed() { S.note = ''; S.live = true; check(); if (!S.start && ready()) jump(); load(); render(); }
  function setBranch(v) {
    S.branch = v || '';
    each(radios, function (r) { r.checked = r.value === S.branch; });
    if (S.moto && !inB(by[S.moto])) S.moto = '';
    fillSel();
    changed();
  }
  function setMoto(id) {
    var m = by[id];
    S.moto = m && !m.un ? id : '';
    if (S.moto && !inB(m)) { setBranch(''); }
    E.sel.value = S.moto;
    changed();
  }
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
  }

  // --- Vykreslení ---
  function render() {
    var a = d.activeElement, key = a && E.cal.contains(a) ? (a.getAttribute('data-d') ? '[data-d="' + a.getAttribute('data-d') + '"]' : (a.getAttribute('data-nav') ? '[data-nav="' + a.getAttribute('data-nav') + '"]' : '')) : '';
    E.cal.innerHTML = K.calHtml(X);
    E.cal.classList.toggle('is-wait', !ready() || S.fail);
    if (key) { var nb = E.cal.querySelector(key); if (nb && !nb.disabled) nb.focus({ preventScroll: true }); }
    var m = S.moto ? by[S.moto] : null, ch = m ? K.cardHtml(X, m) : '';
    E.card.hidden = !m;
    if (ch !== S.cardHtml) { E.card.innerHTML = ch; S.cardHtml = ch; }
    E.hint.textContent = !S.start ? T.hint_start : (!S.end ? T.hint_end : T.hint_done);
    E.note.textContent = S.note || (m ? K.tpl(T.legend_price, { cur: C.cur.sym }) : T.cal_any);
    E.note.classList.toggle('is-warn', !!S.note);
    each(root.querySelectorAll('[data-kc-step]'), function (li) {
      var n = +li.getAttribute('data-kc-step'), done = n === 1 ? !!(S.branch || S.moto) : (n === 2 ? !!S.moto : !!S.end);
      li.classList.toggle('is-done', done);
    });
    var prevTotal = S.shown, sh = '<div class="kc-sum-in">' + K.sumHtml(X) + '</div>';
    if (sh === S.sumHtml) { sticky(); return; }
    E.sum.innerHTML = S.sumHtml = sh;
    var tv = E.sum.querySelector('[data-kc-total]');
    S.shown = tv ? +tv.getAttribute('data-kc-total') : 0;
    if (tv && prevTotal !== S.shown && !rm) count(tv, prevTotal, S.shown);
    sticky();
  }
  function count(el, from, to) {
    var t0 = 0, dur = 450;
    function f(t) {
      if (!t0) t0 = t;
      var k = Math.min(1, (t - t0) / dur), v = from + (to - from) * (1 - Math.pow(1 - k, 3));
      el.textContent = X.money(k < 1 ? v : to);
      if (k < 1 && el.isConnected) requestAnimationFrame(f);
    }
    requestAnimationFrame(f);
  }

  // --- Mobilní lišta s cenou (když souhrn není vidět) ---
  var bar = d.createElement('div'), sumVis = false;
  bar.className = 'kc-sticky';
  bar.setAttribute('aria-hidden', 'true');
  d.body.appendChild(bar);
  function sticky() {
    var m = S.moto ? by[S.moto] : null, bd = m && S.end ? K.breakdown(m, S.start, S.end) : null;
    var on = !!bd && bd.days.length >= (m.min || 1) && !sumVis && window.innerWidth < 900;
    if (bd) {
      bar.innerHTML = '<span class="kc-sticky-t"><span class="kc-sticky-m">' + K.esc(m.m + ' · ' + X.days(bd.days.length)) + '</span><span class="kc-sticky-v">' + K.esc(X.money(bd.total)) + '</span></span>' +
        '<a class="lp-btn lp-btn-primary" href="' + K.esc(X.href()) + '"' + (on ? '' : ' tabindex="-1"') + '>' + K.ico('cal') + '<span>' + K.esc(T.sticky) + '</span></a>';
    }
    bar.classList.toggle('is-on', on);
    bar.setAttribute('aria-hidden', on ? 'false' : 'true');
    d.body.classList.toggle('lp-sticky-on', on);
  }
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (es) { sumVis = es[0].isIntersecting; sticky(); }, { rootMargin: '0px 0px -30% 0px' }).observe(E.sum);
    new IntersectionObserver(function (es) {
      if (es[0].isIntersecting && !S.live) { S.live = true; load(); render(); }
    }, { rootMargin: '300px 0px' }).observe(E.cal);
  } else { S.live = true; }
  window.addEventListener('resize', sticky);

  // --- Události ---
  each(radios, function (r) { r.addEventListener('change', function () { if (r.checked) setBranch(r.value); }); });
  E.sel.addEventListener('change', function () { setMoto(E.sel.value); });
  E.cal.addEventListener('click', function (ev) {
    var b = ev.target.closest('button');
    if (!b || b.disabled) return;
    if (b.hasAttribute('data-nav')) {
      S.mo += +b.getAttribute('data-nav');
      if (S.mo < 0) { S.mo = 11; S.y--; } else if (S.mo > 11) { S.mo = 0; S.y++; }
      render();
    } else if (b.hasAttribute('data-retry')) { S.fail = false; load(); render(); }
    else if (b.getAttribute('data-d')) pick(b.getAttribute('data-d'));
  });
  E.cal.addEventListener('mouseover', function (ev) {
    if (!S.start || S.end) return;
    var b = ev.target.closest('[data-d]'), to = b && !b.disabled ? b.getAttribute('data-d') : '';
    each(E.cal.querySelectorAll('[data-d]'), function (x) { var v = x.getAttribute('data-d'); x.classList.toggle('is-hover', !!to && v > S.start && v <= to); });
  });
  E.sum.addEventListener('click', function (ev) {
    var b = ev.target.closest('[data-pick],[data-reset]');
    if (!b) return;
    if (b.hasAttribute('data-reset')) { S.start = S.end = null; S.note = ''; render(); return; }
    setMoto(b.getAttribute('data-pick'));
  });

  // Tlačítko „Spočítat cenu“ na kartách katalogu (sourozenec odkazu karty, ne vnořené)
  each(d.querySelectorAll('#katalog-grid .moto-wrapper'), function (a) {
    var id = decodeURIComponent((a.getAttribute('href') || '').split(/[?#]/)[0].split('/').pop());
    if (!by[id] || by[id].un) return;
    var btn = d.createElement('button');
    btn.type = 'button';
    btn.className = 'kc-card-btn';
    btn.innerHTML = K.ico('cal') + '<span>' + K.esc(T.card_btn) + '</span>';
    btn.addEventListener('click', function () {
      setMoto(id);
      root.scrollIntoView({ behavior: rm ? 'auto' : 'smooth', block: 'start' });
    });
    a.parentNode.insertBefore(btn, a.nextSibling);
  });

  // Start: předvybraná pobočka (filtr ?pobocka=) / motorka (detail)
  var pre = C.pre || {}, pm = by[pre.moto] && !by[pre.moto].un ? pre.moto : '';
  S.branch = pre.branch && X.branch(pre.branch) && (!pm || by[pm].b === pre.branch) ? pre.branch : '';
  S.moto = pm;
  each(radios, function (r) { r.checked = r.value === S.branch; });
  fillSel();
  root.classList.add('is-ready');
  render();
  load();
})();
