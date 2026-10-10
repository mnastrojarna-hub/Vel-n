/* MotoGo24 — katalog v2 (pages/katalog-v2-*.php): okamžité filtrování karet nad JSON kf-data.
   Predikáty i řazení zrcadlí PHP filtr v pages/katalog.php (stejné výsledky jako GET formulář),
   URL drží stejné parametry (?kategorie=&ridicak=&pobocka=&kw_min=…&razeni=, + start/end termínu).
   Fulltext ?q= filtruje server (qm), jeho změna stránku znovu načte. Panely: landing-catalog-sheet.js,
   termín: landing-catalog-dates.js, kalkulačka (landing-calc*.js) je pod mřížkou, na mobilu sbalená. */
(function () {
  var d = document, w = window, F = w.MGKF = w.MGKF || {}, K = w.MGKC || {};
  var root = d.querySelector('[data-kf]'), el = d.getElementById('kf-data');
  if (!root || !el || !F.openSheet) return;
  var D, kc = null;
  try { D = JSON.parse(el.textContent); } catch (e) { return; }
  try { kc = JSON.parse(d.getElementById('kc-data').textContent); } catch (e) {}
  var T = D.t, B = D.b, S = D.s, motos = D.motos, each = function (l, f) { Array.prototype.forEach.call(l, f); };
  var q = function (s) { return root.querySelector(s); }, qa = function (s) { return root.querySelectorAll(s); };
  var bar = q('[data-kf-bar]'), form = q('[data-kf-panel]'), grid = q('[data-kf-grid]'), countEl = q('[data-kf-count]');
  var activeEl = q('[data-kf-active]'), emptyEl = q('[data-kf-empty]'), showEl = q('[data-kf-show]'), nfEl = q('[data-kf-nf]');
  var cur = kc ? kc.cur : { code: 'CZK', rate: 1, dec: 0, sym: 'Kč' }, cards = {}, R = {}, lastVis = 0, DT = null;
  var KEYS = ['ridicak', 'pobocka', 'kw_min', 'kw_max', 'cena_min', 'cena_max', 'abs', 'jezdci', 'q', 'razeni', 'start', 'end'];
  S.cat = String(S.cat || '').toLowerCase(); S.lic = String(S.lic || '').toUpperCase();
  each(grid.children, function (li) { cards[li.getAttribute('data-id')] = li; });
  F.initSheets(bar);
  var tpl = function (s, p) { s = String(s || ''); for (var k in p) s = s.split('{' + k + '}').join(p[k]); return s; };
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  function plural(n) { return tpl(n === 1 ? T.f_count_one : (n >= 2 && n <= 4 ? T.f_count_few : T.f_count_many), { n: n }); }
  function money0(v) { return K.money ? K.money(cur, v, 0) : Math.round(v) + ' Kč'; }
  function fmtR(k, a, b) { return k === 'kw' ? a + ' – ' + (b >= B.kw[1] ? T.max : b) + ' kW' : money0(a) + ' – ' + money0(b); }
  function moved(k) { return S[k][0] > B[k][0] || S[k][1] < B[k][1]; }

  // --- Predikáty (zrcadlo PHP filtru) ---
  function catOk(m, c) { return !c || m.c.indexOf(c) >= 0 || m.rc === c; }
  function pass(m, skip) {
    if (skip !== 'cat' && S.cat && !catOk(m, S.cat)) return false;
    if (S.lic && m.l.indexOf(S.lic) < 0) return false;
    if (S.br && m.b !== S.br) return false;
    if (moved('kw') && m.kw !== null && (m.kw < S.kw[0] || m.kw > S.kw[1])) return false;
    if (moved('pr') && m.pr > 0 && (m.pr < S.pr[0] || m.pr > S.pr[1])) return false;
    if (S.abs && !m.abs) return false;
    if (S.two && m.kid) return false;
    if (S.q && !m.qm) return false;
    if (skip !== 'date' && DT && DT.free(m) === false) return false;
    return true;
  }
  // Řazení jako usort v PHP (stabilní, bez ceny vždy na konec)
  function key(m) {
    switch (S.sort) {
      case 'cena_asc': return m.pr > 0 ? m.pr : Infinity;
      case 'cena_desc': return m.pr > 0 ? -m.pr : 1;
      case 'vykon_desc': return -(m.kw || 0);
      case 'vykon_asc': return m.kw || 0;
    }
    return 0;
  }
  function actives() {
    var a = [];
    if (S.lic) a.push(['lic', S.lic === 'N' ? T.license_none : tpl(T.license, { g: S.lic })]);
    if (S.br) a.push(['br', D.br[S.br] || S.br]);
    if (moved('pr')) a.push(['pr', fmtR('pr', S.pr[0], S.pr[1])]);
    if (moved('kw')) a.push(['kw', fmtR('kw', S.kw[0], S.kw[1])]);
    if (S.abs) a.push(['abs', T.absOnly]);
    if (S.two) a.push(['two', T.ridersTwo]);
    if (S.q) a.push(['q', '“' + S.q + '”']);
    return a;
  }

  // --- URL (stejné parametry jako formulář; cizí parametry typu ?landing= zůstávají) ---
  function params() {
    var u = new URLSearchParams(w.location.search);
    KEYS.forEach(function (k) { u.delete(k); });
    if (D.base) { u.delete('kategorie'); if (S.cat) u.set('kategorie', S.cat); }
    if (S.lic) u.set('ridicak', S.lic);
    if (S.br) u.set('pobocka', S.br);
    if (S.kw[0] > B.kw[0]) u.set('kw_min', S.kw[0]);
    if (S.kw[1] < B.kw[1]) u.set('kw_max', S.kw[1]);
    if (S.pr[0] > B.pr[0]) u.set('cena_min', S.pr[0]);
    if (S.pr[1] < B.pr[1]) u.set('cena_max', S.pr[1]);
    if (S.abs) u.set('abs', '1');
    if (S.two) u.set('jezdci', '2');
    if (S.q) u.set('q', S.q);
    if (S.sort && S.sort !== 'default') u.set('razeni', S.sort);
    if (DT && DT.active()) { u.set('start', DT.start()); u.set('end', DT.end()); }
    return u;
  }
  function sync() {
    var s = params().toString(), url = w.location.pathname + (s ? '?' + s : '') + w.location.hash;
    if (url !== w.location.pathname + w.location.search + w.location.hash) try { history.replaceState(history.state, '', url); } catch (e) {}
  }

  // --- Použití filtru ---
  function apply(init) {
    var order = motos.slice().sort(function (a, b) { return (key(a) - key(b)) || (a.i - b.i); }), vis = 0, n = 0, moveIt = false;
    var lis = Array.prototype.slice.call(grid.children);
    order.forEach(function (m) {
      var li = cards[m.id];
      if (!li) return;
      if (lis[n++] !== li) moveIt = true;
      var on = pass(m);
      if (li.hidden === on) {
        li.hidden = !on;
        if (on && !init && !F.rm) { li.classList.remove('is-in'); void li.offsetWidth; li.classList.add('is-in'); }
      }
      if (on) vis++;
    });
    if (moveIt) { var fr = d.createDocumentFragment(); order.forEach(function (m) { if (cards[m.id]) fr.appendChild(cards[m.id]); }); grid.appendChild(fr); }
    lastVis = vis;
    var busy = !!(DT && DT.busy());
    grid.classList.toggle('is-busy', busy && !(DT && DT.fail()));
    grid.setAttribute('aria-busy', busy ? 'true' : 'false');
    countEl.textContent = plural(vis) + (busy && kc ? ' · ' + (DT.fail() ? kc.t.cal_error : kc.t.cal_loading) : '');
    emptyEl.hidden = vis > 0;
    q('[data-kf-empty-t]').textContent = DT && DT.active() ? T.f_none_dates : T.empty;
    showEl.textContent = tpl(T.f_show, { count: plural(vis) });
    each(qa('[data-kf-cat]'), function (a) {
      var c = a.getAttribute('data-kf-cat'), k = 0, on = c === S.cat;
      motos.forEach(function (m) { if (catOk(m, c) && pass(m, 'cat')) k++; });
      a.querySelector('.kf-cat-n').textContent = k;
      a.classList.toggle('is-zero', !k);
      a.classList.toggle('is-on', on);
      if (on) a.setAttribute('aria-current', 'true'); else a.removeAttribute('aria-current');
    });
    var act = actives(), x = K.ico ? K.ico('x') : '×', h = '';
    nfEl.hidden = !act.length;
    nfEl.textContent = act.length;
    if (DT && DT.active()) act.unshift(['dates', DT.chip()]);
    act.forEach(function (a) { h += '<button type="button" class="kf-ac" data-kf-rm="' + a[0] + '" aria-label="' + esc(tpl(T.f_remove, { label: a[1] })) + '"><span>' + esc(a[1]) + '</span>' + x + '</button>'; });
    if (act.length) h += '<button type="button" class="kf-ac kf-ac--clear" data-kf-rm="all">' + esc(T.f_clear) + '</button>';
    activeEl.innerHTML = h;
    activeEl.hidden = !act.length;
    if (DT) DT.update();
    if (!init) sync();
  }
  var raf = 0;
  function later() { if (!raf) raf = requestAnimationFrame(function () { raf = 0; apply(); }); }

  // --- Panel: vstupy ↔ stav ---
  function bindRange(k) {
    var wr = form.querySelector('[data-kf-range="' + k + '"]');
    if (!wr) return;
    var ins = wr.querySelectorAll('input[type=range]'), a = ins[0], b = ins[1], rv = wr.querySelector('[data-kf-rv]'), fill = wr.querySelector('.range-fill');
    var lo = B[k][0], hi = B[k][1];
    function show() {
      var x = +a.value, y = +b.value;
      rv.textContent = fmtR(k, x, y);
      if (fill && hi > lo) { fill.style.left = (x - lo) / (hi - lo) * 100 + '%'; fill.style.right = 100 - (y - lo) / (hi - lo) * 100 + '%'; }
    }
    function on(src) {
      var x = +a.value, y = +b.value;
      if (x > y) { if (src === a) { b.value = x; y = x; } else { a.value = y; x = y; } }
      S[k] = [x, y]; show(); later();
    }
    a.addEventListener('input', function () { on(a); });
    b.addEventListener('input', function () { on(b); });
    R[k] = function () { a.value = S[k][0]; b.value = S[k][1]; show(); };
    show();
  }
  bindRange('kw'); bindRange('pr');
  var qIn = form.querySelector('input[name="q"]');
  function setInputs() {
    each(form.querySelectorAll('input[type=radio]'), function (r) {
      var v = { ridicak: S.lic, pobocka: S.br, razeni: S.sort || 'default' }[r.name];
      r.checked = String(r.value).toUpperCase() === String(v).toUpperCase();
    });
    each(form.querySelectorAll('input[type=checkbox]'), function (c) { c.checked = c.name === 'abs' ? S.abs : S.two; });
    R.kw && R.kw(); R.pr && R.pr();
    if (qIn) qIn.value = S.q;
  }
  function reset() {
    if (D.base) S.cat = '';
    S.lic = ''; S.br = ''; S.kw = B.kw.slice(); S.pr = B.pr.slice(); S.abs = S.two = false; S.q = ''; S.sort = 'default';
    setInputs();
    if (DT && DT.active()) DT.clear(); else apply();
  }
  form.addEventListener('change', function (e) {
    var t = e.target, n = t.name;
    if (n === 'ridicak') S.lic = t.value.toUpperCase();
    else if (n === 'pobocka') S.br = t.value;
    else if (n === 'razeni') S.sort = t.value;
    else if (n === 'abs') S.abs = t.checked;
    else if (n === 'jezdci') S.two = t.checked;
    else return;
    apply();
  });
  if (qIn) qIn.addEventListener('input', function () { if (!qIn.value.trim() && S.q) { S.q = ''; apply(); } });
  // Odeslání: změněný fulltext → nové načtení (server prohledá i popis), jinak jen zavřít panel
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var nq = qIn ? qIn.value.trim() : S.q;
    if (nq !== S.q) {
      S.q = nq;
      if (nq) { var s = params().toString(); w.location.assign(w.location.pathname + (s ? '?' + s : '')); return; }
      apply();
    }
    done();
  });
  function done() {
    F.closeSheet();
    var r = q('.kf-res'), top = r.getBoundingClientRect().top;
    if (top < 0 || top > w.innerHeight * 0.6) r.scrollIntoView({ behavior: F.rm ? 'auto' : 'smooth', block: 'start' });
  }
  root.addEventListener('click', function (e) {
    var t = e.target.closest('[data-kf-rm],[data-kf-reset],[data-kf-cat],[data-kf-close],[data-kf-open="panel"],[data-kf-calc],.kf-calc-btn');
    if (!t) return;
    if (t.hasAttribute('data-kf-open')) { if (F.openEl() === form) F.closeSheet(); else F.openSheet(form, t); return; }
    if (t.hasAttribute('data-kf-close')) { if (form.contains(t)) F.closeSheet(); return; }
    if (t.hasAttribute('data-kf-reset')) { e.preventDefault(); reset(); return; }
    if (t.hasAttribute('data-kf-calc')) { e.preventDefault(); calc(''); return; }
    if (t.classList.contains('kf-calc-btn')) { calc(t.getAttribute('data-id')); return; }
    if (t.hasAttribute('data-kf-cat')) {
      var c = t.getAttribute('data-kf-cat');
      if (D.base) { e.preventDefault(); S.cat = c; apply(); return; }
      var u = params(); u.delete('kategorie'); // stránka kategorie → přechod na jinou (SEO URL), filtry jdou s sebou
      var s = u.toString(); t.setAttribute('href', t.getAttribute('href').split('?')[0] + (s ? '?' + s : ''));
      return;
    }
    var k = t.getAttribute('data-kf-rm');
    if (k === 'all') { reset(); return; }
    if (k === 'dates') { DT.clear(); return; }
    if (k === 'lic') S.lic = ''; else if (k === 'br') S.br = ''; else if (k === 'kw' || k === 'pr') S[k] = B[k].slice();
    else if (k === 'abs') S.abs = false; else if (k === 'two') S.two = false; else if (k === 'q') S.q = '';
    setInputs(); apply();
    var nx = activeEl.querySelector('.kf-ac'); (nx || countEl).focus && nx && nx.focus();
  });

  // --- Kalkulačka pod mřížkou (na mobilu sbalená) + tlačítko na kartách ---
  var kcRoot = d.querySelector('[data-kc]'), tg = null;
  function calc(id) {
    if (!kcRoot) return;
    kcRoot.classList.remove('kf-closed');
    if (tg) tg.hidden = true;
    if (K.calcSet && (id || (DT && DT.active()))) K.calcSet({ moto: id || '', start: DT && DT.start(), end: DT && DT.end() });
    kcRoot.scrollIntoView({ behavior: F.rm ? 'auto' : 'smooth', block: 'start' });
  }
  if (kcRoot && kc) {
    q('[data-kf-calc]').hidden = false;
    var un = {};
    kc.motos.forEach(function (m) { if (m.un) un[m.id] = 1; });
    Object.keys(cards).forEach(function (id) {
      var li = cards[id], act = li.querySelector('.kf-act'), h = li.querySelector('h3');
      if (!act || un[id] || !K.ico) return;
      var b = d.createElement('button');
      b.type = 'button'; b.className = 'kf-calc-btn'; b.setAttribute('data-id', id);
      b.setAttribute('aria-label', T.f_calc + (h ? ': ' + h.textContent : ''));
      b.title = T.f_calc;
      b.innerHTML = q('[data-kf-calc] .lp-ico').outerHTML;
      act.appendChild(b);
    });
    var head = kcRoot.querySelector('.kc-head'), body = kcRoot.querySelector('.kc-grid');
    if (head && body && !F.isDesk() && w.location.hash !== '#kalkulacka') {
      body.id = body.id || 'kc-body';
      kcRoot.classList.add('kf-closed');
      tg = d.createElement('button');
      tg.type = 'button'; tg.className = 'lp-btn lp-btn-primary kf-calc-tg';
      tg.setAttribute('aria-expanded', 'false'); tg.setAttribute('aria-controls', body.id);
      tg.innerHTML = K.ico ? K.ico('cal') + '<span>' + esc(T.f_calc_open) + '</span>' : esc(T.f_calc_open);
      head.appendChild(tg);
      tg.addEventListener('click', function () {
        kcRoot.classList.remove('kf-closed'); tg.setAttribute('aria-expanded', 'true'); tg.hidden = true;
        var s = kcRoot.querySelector('#kc-moto'); if (s) s.focus({ preventScroll: true });
      });
    }
  }

  // --- Úvodní text na mobilu sbalený na 2 řádky ---
  var intro = d.querySelector('.kf-intro');
  if (intro && w.innerWidth <= 768) {
    intro.classList.add('is-clamp');
    if (intro.scrollHeight > intro.clientHeight + 4) {
      var mb = d.createElement('button');
      mb.type = 'button'; mb.className = 'kf-more'; mb.setAttribute('aria-expanded', 'false'); mb.textContent = T.more_open;
      intro.parentNode.insertBefore(mb, intro.nextSibling);
      mb.addEventListener('click', function () {
        var o = intro.classList.toggle('is-clamp');
        mb.textContent = o ? T.more_open : T.more_close; mb.setAttribute('aria-expanded', o ? 'false' : 'true');
      });
    } else intro.classList.remove('is-clamp');
  }

  // --- Stín lišty, když je přilepená ---
  if ('IntersectionObserver' in w) {
    var sen = d.createElement('div');
    sen.setAttribute('aria-hidden', 'true');
    bar.parentNode.insertBefore(sen, bar);
    new IntersectionObserver(function (es) { bar.classList.toggle('is-stuck', !es[0].isIntersecting); }).observe(sen);
  }

  DT = F.initDates ? F.initDates({ kc: kc, T: T, bar: bar, btn: q('[data-kf-open="dates"]'), motos: motos, cards: cards, plural: plural,
    passNoDate: function (m) { return pass(m, 'date'); }, apply: function () { apply(); }, count: function () { return lastVis; }, done: done }) : null;
  q('[data-kf-open="panel"]').hidden = false;
  setInputs();
  apply(true);
})();
