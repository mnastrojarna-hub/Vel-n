/* MotoGo24 — Půjčení oblečení (jen výbava, bez motorky): pages/pujceni-obleceni.php.
   Pobočka → termín (1. klik = 1 den, 2. klik = poslední den) → kusy s velikostmi → kontakt.
   Výpůjčka = rezervace (create_web_gear_booking, js/gear-rental-submit.js). Velikosti: na
   samoobsluze jen rozsah gear-ss-cap.js, se zapnutou kontrolou skladu jen volné v termínu
   (get_gear_rental_availability). Souhrn: okamžitě z klientského nacenění (zrcadlí SQL
   _gear_rental_quote), pak serverová cena + dárkový poukaz (js/gear-rental-price.js).
   Návrat ?booking_id=&session_id= / ?resume= kreslí js/gear-rental-done.js. Kalendář kreslí
   K.calHtml z landing-calc-view.js; sdílené helpery window.MGGR (gear-rental-api.js). */
(function () {
  var G = window.MGGR, d = document, MG = window.MG || {};
  if (!G || !G.K.calHtml) return;
  var C = G.C, T = G.T, K = G.K, esc = G.esc, tpl = G.tpl, q = G.q, money = G.money;
  var today = K.today();
  var S = G.S = { branch: '', start: null, end: null, open: false, y: +today.slice(0, 4), mo: +today.slice(5, 7) - 1, moto: '', sel: {}, note: '',
    avail: null, availKey: '', sq: null, vcode: '', vstate: '', drop: '' };
  var by = G.by = {};
  C.prices.forEach(function (p) { by[p.key] = p; });
  var items = C.prices.filter(function (p) { return p.kind === 'item'; });
  var sets = C.prices.filter(function (p) { return p.kind === 'set'; }).sort(function (a, b) {
    return (b.includes.length - a.includes.length) || (a.p - b.p) || (a.key < b.key ? -1 : 1);
  });
  var last = K.add(today, C.maxAhead || 400);

  function closed(iso) {
    if (!S.branch) return false;
    for (var i = 0; i < C.closures.length; i++) {
      var c = C.closures[i];
      if (c.b === S.branch && iso >= c.f && iso <= c.t) return true;
    }
    return false;
  }
  function st(iso) { return iso < today ? 'past' : (iso > last || closed(iso) ? 'busy' : 'free'); }
  var X = { C: C, T: T, S: S, by: {}, today: today, st: st, ready: function () { return true; }, fmt: G.fmt, money: money };

  // ---- nacenění (shodně se SQL _gear_rental_quote) ----
  function keys() { return items.filter(function (p) { return S.sel[p.key] !== undefined; }).map(function (p) { return p.key; }); }
  function quote() {
    var left = keys(), lines = [], per = 0, single = 0;
    left.forEach(function (k) { single += by[k].p; });
    sets.forEach(function (s) {
      if (!s.includes.length || !s.includes.every(function (k) { return left.indexOf(k) >= 0; })) return;
      var sum = 0;
      s.includes.forEach(function (k) { sum += by[k] ? by[k].p : 0; });
      if (!(s.p < sum)) return;
      lines.push(s); per += s.p;
      left = left.filter(function (k) { return s.includes.indexOf(k) < 0; });
    });
    items.forEach(function (p) { if (left.indexOf(p.key) >= 0) { lines.push(p); per += p.p; } });
    return { lines: lines, per: per, save: Math.max(0, single - per) };
  }
  function nDays() { return S.start && S.end ? K.count(S.start, S.end) : 0; }
  function branch() {
    for (var i = 0; i < C.branches.length; i++) if (C.branches[i].id === S.branch) return C.branches[i];
    return null;
  }
  function itemsArg() { return keys().map(function (k) { return { key: k, size: S.sel[k] || null }; }); }
  function complete() {
    var ks = keys();
    return !!(S.branch && S.start && S.end && ks.length) && ks.every(function (k) { return !by[k].sizes.length || S.sel[k]; });
  }
  G.keys = keys; G.nDays = nDays; G.branch = branch; G.itemsArg = itemsArg; G.complete = complete;

  // ---- velikosti: rozsah samoobsluhy (gear-ss-cap.js) + volné kusy v termínu ----
  function isSelf() { var b = branch(); return !!(b && b.self); }
  function sizesFor(p) {
    return isSelf() && typeof MG._ssGearInRange === 'function' ? p.sizes.filter(function (z) { return MG._ssGearInRange(p.key, z); }) : p.sizes;
  }
  function nz(z) { var u = String(z == null ? '' : z).trim().toUpperCase(); return { XXL: '2XL', XXXL: '3XL', XXXXL: '4XL' }[u] || u; }
  // Sledovaný typ (klíč v sizes) = jen velikosti s volnými kusy; nesledovaný = bez omezení
  function free(key, z) {
    var a = S.avail, m = a && a.enabled && a.sizes ? a.sizes[key] : null, hit = null;
    if (!m || typeof m !== 'object') return true;
    Object.keys(m).forEach(function (k) { if (nz(k) === nz(z)) hit = G.num(m[k]); });
    return hit !== null && hit > 0;
  }
  function sizeOk(key, z) { return sizesFor(by[key]).indexOf(z) >= 0 && free(key, z); }
  function prune() {
    var msg = [];
    keys().forEach(function (k) {
      var z = S.sel[k];
      if (z && !sizeOk(k, z)) { S.sel[k] = ''; if (free(k, z) === false) msg.push(tpl(T.size_dropped, { size: z, item: by[k].label })); }
    });
    if (msg.length) S.drop = msg.join(' ');
  }
  var availT = 0;
  function loadAvail() {
    var key = S.branch && S.start ? [S.branch, S.start, S.end || S.start].join('|') : '';
    if (key === S.availKey) return;
    S.availKey = key; S.avail = null;
    clearTimeout(availT);
    if (!key) return;
    availT = setTimeout(function () {
      G.rpc('get_gear_rental_availability', { p_branch_id: S.branch, p_start: S.start, p_end: S.end || S.start }).then(function (o) {
        if (S.availKey !== key) return;
        S.avail = o && !o.error && o.enabled ? o : null;
        prune(); renderItems(); renderSum(); live();
      }).catch(function () {});
    }, 200);
  }
  G.reloadAvail = function () { S.availKey = ''; loadAvail(); };

  function live(force) { if (G.live) G.live(force); }

  // ---- render ----
  var E = G.E = { br: q('[data-gr-branches]'), self: q('[data-gr-selfnote]'), cal: q('[data-gr-cal]'), hint: q('[data-gr-hint]'), time: q('[data-gr-time]'),
    clear: q('[data-gr-clear]'), quick: q('[data-gr-quick]'), items: q('[data-gr-items]'), ss: q('[data-gr-ssnote]'), sum: q('[data-gr-sum]'),
    err: q('[data-gr-err]'), go: q('[data-gr-go]'), form: q('#gr-form'), vmsg: q('[data-gr-vmsg]') };

  function renderBranches() {
    if (!E.br) return;
    E.br.innerHTML = C.branches.map(function (b) {
      return '<label class="gr-br' + (S.branch === b.id ? ' is-on' : '') + '"><input type="radio" name="gr-branch" value="' + esc(b.id) + '"' + (S.branch === b.id ? ' checked' : '') + '>' +
        '<span class="gr-br-n">' + K.ico('pin') + esc(b.n) + '</span><span class="gr-br-s">' + esc(b.self ? T.branch_self : T.branch_staffed) + '</span>' +
        (b.a ? '<span class="gr-br-a">' + esc(b.a) + '</span>' : '') + '</label>';
    }).join('');
    var br = branch();
    if (E.self) E.self.hidden = !(br && br.self);
    if (E.ss) E.ss.hidden = !(br && br.self);
    if (E.time) E.time.hidden = !(br && !br.self);
  }
  function renderCal() {
    if (!E.cal) return;
    E.cal.innerHTML = K.calHtml(X);
    E.hint.textContent = S.note || (!S.start ? T.hint_start : (S.open ? T.hint_end : T.hint_done));
    E.hint.classList.toggle('is-warn', !!S.note);
    if (E.clear) E.clear.hidden = !S.start;
  }
  function renderItems() {
    if (E.quick) E.quick.innerHTML = C.prices.filter(function (p) { return p.kind === 'set'; }).map(function (s) {
      var on = s.includes.every(function (k) { return S.sel[k] !== undefined; }) && keys().length === s.includes.length;
      return '<button type="button" class="gr-qs' + (on ? ' is-on' : '') + '" data-set="' + esc(s.key) + '" aria-pressed="' + on + '"><span class="gr-qs-t">' + esc(s.label) + '</span>' +
        (s.desc ? '<span class="gr-qs-d">' + esc(s.desc) + '</span>' : '') + '<span class="gr-qs-p">' + esc(money(s.p)) + ' ' + esc(T.per_day) + '</span></button>';
    }).join('');
    if (E.items) E.items.innerHTML = (S.drop ? '<p class="gr-sz-hint gr-drop" role="status">' + esc(S.drop) + '</p>' : '') + items.map(function (p) {
      var on = S.sel[p.key] !== undefined, sz = S.sel[p.key] || '', list = sizesFor(p);
      return '<div class="gr-it' + (on ? ' is-on' : '') + '"><label class="gr-it-h"><input type="checkbox" data-item="' + esc(p.key) + '"' + (on ? ' checked' : '') + '>' +
        '<span class="gr-it-n">' + esc(p.label) + '</span><span class="gr-it-p">' + esc(money(p.p)) + ' <small>' + esc(T.per_day) + '</small></span></label>' +
        (on && list.length ? '<div class="gr-sizes" role="group" aria-label="' + esc(p.label + ' — ' + T.size_choose) + '">' + list.map(function (z) {
          var ok = free(p.key, z);
          return '<button type="button" class="gr-sz' + (z === sz ? ' is-on' : '') + (ok ? '' : ' is-out') + '" data-size="' + esc(z) + '" data-for="' + esc(p.key) + '" aria-pressed="' + (z === sz) + '"' +
            (ok ? '' : ' disabled title="' + esc(T.size_out) + '" aria-label="' + esc(z + ' — ' + T.size_out) + '"') + '>' + esc(z) + '</button>';
        }).join('') + '</div>' : '') + (on && list.length && !sz ? '<p class="gr-sz-hint">' + esc(T.size_choose) + '</p>' : '') + '</div>';
    }).join('');
  }
  function renderSum() {
    if (!E.sum) return;
    var qq = quote(), n = nDays(), br = branch();
    if (!qq.lines.length || !n || !br) {
      E.sum.innerHTML = '<p class="gr-sum-k">' + esc(T.sum_title) + '</p><p class="gr-sum-e">' + esc(T.sum_empty) + '</p>';
      return;
    }
    var rows = qq.lines.map(function (l) {
      var sz = (l.kind === 'set' ? l.includes : [l.key]).map(function (k) {
        return S.sel[k] ? (l.kind === 'set' ? (by[k] ? G.lc(by[k].label) + ' ' : '') : '') + S.sel[k] : '';
      }).filter(Boolean).join(', ');
      return '<li><span class="gr-l-n">' + esc(l.label) + (sz ? ' <small>' + esc(sz) + '</small>' : '') + '</span><span class="gr-l-v">' + esc(n + ' × ' + money(l.p)) + '</span></li>';
    }).join('');
    var r = S.sq && S.sq.res && !S.sq.wait ? S.sq.res : null, full = qq.per * n;
    if (r && !r.error && G.num(r.per_day) > 0) full = G.num(r.per_day) * n;
    var va = r && !r.error ? G.voucherAmt(r) : 0, pay = va > 0 ? (r.amount != null ? G.num(r.amount) : Math.max(0, full - va)) : full;
    var warn = r && r.error && r.error !== 'bad_voucher' ? G.errText(r) : '';
    E.sum.innerHTML = '<p class="gr-sum-k">' + esc(T.sum_title) + '</p>' +
      '<p class="gr-sum-m">' + K.ico('pin') + esc(br.n) + ' · ' + esc(G.period(S.start, S.end)) + ' (' + esc(G.days(n)) + ')</p>' +
      '<ul class="gr-lines">' + rows + '</ul>' +
      (qq.save > 0 ? '<p class="gr-save">' + K.ico('check') + esc(tpl(T.save || '', { amount: money(qq.save * n) })) + '</p>' : '') +
      (va > 0 ? '<p class="gr-total gr-total-sub"><span>' + esc(T.total) + '</span><span>' + esc(money(full)) + '</span></p>' +
        '<p class="gr-vline"><span>' + esc(tpl(T.voucher_line, { code: (r.voucher && r.voucher.code) || S.vcode })) + '</span><span>−' + esc(money(va)) + '</span></p>' : '') +
      '<p class="gr-total"><span>' + esc(va > 0 ? T.to_pay : T.total) + '</span><b>' + esc(money(pay)) + '</b></p>' +
      (warn ? '<p class="gr-sum-warn" role="status">' + esc(warn) + '</p>' : '');
  }
  function renderVoucher() { if (G.renderVoucher) G.renderVoucher(); }
  function render() { renderBranches(); renderCal(); renderItems(); renderSum(); renderVoucher(); }
  G.render = render; G.renderSum = renderSum;

  // ---- výběr termínu: 1. klik = 1 den (otevřený rozsah), 2. klik pozdější den = konec ----
  function rangeOk(a, b) {
    for (var x = a; x <= b; x = K.add(x, 1)) if (st(x) !== 'free') return false;
    return true;
  }
  function changed() { S.drop = ''; prune(); loadAvail(); live(); renderItems(); renderSum(); }
  function pick(iso) {
    S.note = '';
    if (S.open && S.start && iso >= S.start) {
      if (!rangeOk(S.start, iso)) S.note = T.err_closed;
      else if (K.count(S.start, iso) > C.maxDays) S.note = tpl(T.err_long, { n: C.maxDays });
      else { S.end = iso; S.open = false; }
    } else { S.start = S.end = iso; S.open = true; }
    renderCal(); changed();
  }
  function setBranch(id) {
    S.branch = id;
    if (S.start && !rangeOk(S.start, S.end || S.start)) { S.start = S.end = null; S.open = false; S.note = T.err_closed; }
    renderBranches(); renderCal(); changed();
  }

  // ---- události ----
  if (E.form) {
    E.br.addEventListener('change', function (ev) { var r = ev.target; if (r && r.name === 'gr-branch') setBranch(r.value); });
    E.cal.addEventListener('click', function (ev) {
      var b = ev.target.closest('button');
      if (!b || b.disabled) return;
      if (b.hasAttribute('data-nav')) {
        S.mo += +b.getAttribute('data-nav');
        if (S.mo < 0) { S.mo = 11; S.y--; } else if (S.mo > 11) { S.mo = 0; S.y++; }
        renderCal();
      } else if (b.getAttribute('data-d')) pick(b.getAttribute('data-d'));
    });
    E.clear && E.clear.addEventListener('click', function () {
      S.start = S.end = null; S.open = false; S.note = '';
      renderCal(); changed();
      try { E.cal.querySelector('button[data-d]:not([disabled])').focus(); } catch (e) {}
    });
    E.quick.addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-set]');
      if (!b) return;
      var s = by[b.getAttribute('data-set')], all = s.includes.every(function (k) { return S.sel[k] !== undefined; }) && keys().length === s.includes.length;
      if (all) S.sel = {};
      else { var n = {}; s.includes.forEach(function (k) { if (by[k]) n[k] = S.sel[k] || ''; }); S.sel = n; }
      S.drop = ''; renderItems(); renderSum(); live();
    });
    E.items.addEventListener('change', function (ev) {
      var c = ev.target;
      if (!c || !c.hasAttribute('data-item')) return;
      var k = c.getAttribute('data-item');
      if (c.checked) S.sel[k] = S.sel[k] || ''; else delete S.sel[k];
      S.drop = ''; renderItems(); renderSum(); live();
    });
    E.items.addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-size]');
      if (!b || b.disabled) return;
      var k = b.getAttribute('data-for'), z = b.getAttribute('data-size');
      S.sel[k] = S.sel[k] === z ? '' : z;
      S.drop = ''; renderItems(); renderSum(); live();
    });
    var co = q('#gr-company-on');
    co && co.addEventListener('change', function () { q('#gr-company').hidden = !co.checked; });
    if (G.bindVoucher) G.bindVoucher();
    var ts = q('#gr-time');
    if (ts) for (var h = 7; h <= 20; h++) {
      var o = d.createElement('option'), v = (h < 10 ? '0' : '') + h + ':00';
      o.value = o.textContent = v;
      if (h === 9) o.selected = true;
      ts.appendChild(o);
    }
    E.form.addEventListener('submit', function (ev) { ev.preventDefault(); if (G.submit) G.submit(); });
  }

  // ---- start: návrat ze Stripe / pokračování v rezervaci / nový formulář ----
  var u = new URLSearchParams(location.search), bid = u.get('booking_id'), res = u.get('resume'), oid = u.get('order_id');
  var pb = u.get('pobocka');
  if (pb && C.branches.some(function (b) { return b.id === pb; })) S.branch = pb;
  else if (C.branches.length === 1) S.branch = C.branches[0].id;
  if (G.isId(oid) && !bid && !res) {
    // dřívější objednávky výbavy přes e-shop (před 2026-10-23) potvrdí obecné /potvrzeni
    location.replace(C.confirm + '?order_id=' + encodeURIComponent(oid) + (u.get('session_id') ? '&session_id=' + encodeURIComponent(u.get('session_id')) : ''));
  } else if (G.isId(bid) && G.confirmView) G.confirmView(bid, u.get('session_id') || '');
  else if (G.isId(res) && G.resumeView) G.resumeView(res, !!u.get('payfail'));
  else {
    render();
    if (G.authInit) G.authInit();
  }
})();
