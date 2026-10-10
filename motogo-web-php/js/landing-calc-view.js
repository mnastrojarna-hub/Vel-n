/* MotoGo24 — kalkulačka ceny (landing v2): HTML kalendáře, karty motorky a souhrnu.
   Volá js/landing-calc.js s kontextem X (stav S, texty T, helpery). Jádro: landing-calc-core.js. */
(function (w) {
  var K = w.MGKC = w.MGKC || {};
  var esc = function (s) { return K.esc(s); }, tpl = function (s, p) { return K.tpl(s, p); };
  var P = {
    cal: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/>',
    chev: '<path d="m15 6-6 6 6 6"/>', arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>', check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    pin: '<path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
    x: '<path d="M6 6l12 12M18 6 6 18"/>'
  };
  K.ico = function (n) {
    return '<svg class="lp-ico" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (P[n] || '') + '</svg>';
  };
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }
  function wd(X, dw) { return X.fmt(K.iso(Date.UTC(2024, 0, dw === 0 ? 7 : dw)), { weekday: 'short' }).replace('.', ''); }

  K.calHtml = function (X) {
    var S = X.S, T = X.T, y = S.y, mo = S.mo, first = K.iso(Date.UTC(y, mo, 1));
    var dim = new Date(Date.UTC(y, mo + 1, 0)).getUTCDate(), lead = (K.dow(first) + 6) % 7;
    var t0 = +X.today.slice(0, 4) * 12 + (+X.today.slice(5, 7) - 1), cur = y * 12 + mo;
    var m = S.moto ? X.by[S.moto] : null, wait = !X.ready(), title = cap(X.fmt(first, { month: 'long', year: 'numeric' }));
    var h = '<div class="kc-cal-nav"><button type="button" class="kc-nav" data-nav="-1" aria-label="' + esc(T.prev) + '"' + (cur <= t0 ? ' disabled' : '') + '>' + K.ico('chev') + '</button>' +
      '<span class="kc-cal-t">' + esc(title) + '</span>' +
      '<button type="button" class="kc-nav kc-nav--next" data-nav="1" aria-label="' + esc(T.next) + '"' + (cur >= t0 + 18 ? ' disabled' : '') + '>' + K.ico('chev') + '</button></div>' +
      '<div class="kc-days" role="group" aria-label="' + esc(title) + '">';
    for (var i = 1; i <= 7; i++) h += '<span class="kc-wd' + (i > 5 ? ' is-we' : '') + '" aria-hidden="true">' + esc(wd(X, i % 7)) + '</span>';
    for (i = 0; i < lead; i++) h += '<span class="kc-day is-empty" aria-hidden="true"></span>';
    for (var dd = 1; dd <= dim; dd++) {
      var iso = y + '-' + pad(mo + 1) + '-' + pad(dd), s = wait && iso >= X.today ? 'wait' : X.st(iso), dw = K.dow(iso), cls = 'kc-day is-' + s;
      var on = S.start && (iso === S.start || iso === S.end || (S.end && iso > S.start && iso < S.end));
      if (dw === 0 || dw === 6) cls += ' is-we';
      if (iso === S.start) cls += ' is-start';
      if (S.end && iso === S.end) cls += ' is-end';
      if (S.end && iso > S.start && iso < S.end) cls += ' is-in';
      if (iso === X.today) cls += ' is-today';
      var pr = m && s === 'free' && m.p[dw] > 0 ? m.p[dw] : 0;
      var lbl = X.fmt(iso, { weekday: 'long', day: 'numeric', month: 'long' }) +
        ({ free: ' — ' + T.legend_free, busy: ' — ' + T.legend_busy, pending: ' — ' + T.legend_pending }[s] || '') + (pr ? ', ' + X.money(pr) : '');
      h += '<button type="button" class="' + cls + '" data-d="' + iso + '"' + (s === 'free' ? '' : ' disabled') + (on ? ' aria-pressed="true"' : '') +
        ' aria-label="' + esc(lbl) + '"><span class="kc-dn">' + dd + '</span>' + (pr ? '<span class="kc-dp">' + K.short(X.C.cur, pr) + '</span>' : '') + '</button>';
    }
    h += '</div>';
    if (S.fail) h += '<div class="kc-cal-wait">' + esc(T.cal_error) + ' <button type="button" class="kc-retry" data-retry>' + esc(T.retry) + '</button></div>';
    else if (wait) h += '<div class="kc-cal-wait"><span class="kc-spin" aria-hidden="true"></span>' + esc(T.cal_loading) + '</div>';
    return h;
  };

  K.cardHtml = function (X, m) {
    var T = X.T, br = X.branch(m.b), f = X.ready() ? X.firstFree() : (m.na && m.na > X.today ? m.na : (m.st === 'active' ? X.today : null));
    var pills = m.st === 'maintenance' ? '<span class="kc-pill is-warn">' + esc(T.moto_maint) + '</span>' : '';
    if (m.un || (X.ready() && !f)) pills += '<span class="kc-pill is-off">' + esc(T.st_unavail) + '</span>';
    else if (f === X.today) pills += '<span class="kc-pill is-ok"><i></i>' + esc(T.st_today) + '</span>';
    else if (f) pills += '<span class="kc-pill">' + esc(tpl(T.st_from, { date: X.fmt(f, f.slice(0, 4) === X.today.slice(0, 4) ? { day: 'numeric', month: 'short' } : { day: 'numeric', month: 'short', year: 'numeric' }) })) + '</span>';
    var sub = [br ? br.n : '', X.cat(m.c), m.from > 0 ? tpl(T.from, { price: X.money(m.from) }) : ''].filter(Boolean).join(' · ');
    return (m.img ? '<img class="kc-moto-img" src="' + esc(m.img) + '" alt="' + esc(m.m) + '" width="96" height="64" decoding="async">' : '') +
      '<div class="kc-moto-b"><span class="kc-moto-n">' + esc(m.m) + '</span><span class="kc-moto-s">' + esc(sub) + '</span><span class="kc-pills">' + pills + '</span></div>' +
      '<a class="kc-moto-a" href="' + esc(X.C.detail + '/' + encodeURIComponent(m.id)) + '">' + esc(T.detail) + K.ico('arrow') + '</a>';
  };

  function head(X) {
    var S = X.S, T = X.T, o = { weekday: 'short', day: 'numeric', month: 'short' };
    return '<p class="kc-sum-k">' + esc(T.sum_title) + '</p><div class="kc-dates">' +
      '<span class="kc-d"><span class="kc-d-k">' + esc(T.pickup) + '</span><span class="kc-d-v">' + esc(X.fmt(S.start, o)) + '</span></span>' + K.ico('arrow') +
      '<span class="kc-d"><span class="kc-d-k">' + esc(T['return']) + '</span><span class="kc-d-v">' + (S.end ? esc(X.fmt(S.end, o)) : '—') + '</span></span>' +
      (S.end ? '<span class="kc-nd">' + esc(X.days(K.count(S.start, S.end))) + '</span>' : '') + '</div>';
  }
  function cta(X, label, ghost) {
    return '<a class="lp-btn ' + (ghost ? 'lp-btn-ghost' : 'lp-btn-primary') + ' kc-go" href="' + esc(X.href()) + '">' + K.ico('cal') + '<span>' + esc(label) + '</span></a>';
  }
  function foot(X) {
    var T = X.T;
    return '<p class="kc-assure">' + K.ico('check') + esc(T.assure) + '</p>' +
      '<button type="button" class="kc-reset" data-reset>' + K.ico('x') + esc(T.reset) + '</button>' +
      (X.C.cur.code !== 'CZK' ? '<p class="kc-fx">' + esc(tpl(T.fx, { cur: X.C.cur.sym })) + '</p>' : '');
  }
  function bars(X, list, labels, prices) {
    var max = 0;
    list.forEach(function (x) { if (x.price > max) max = x.price; });
    return '<div class="kc-bars' + (labels ? '' : ' kc-bars--dense') + (prices ? ' kc-bars--p' : '') + '" role="img" aria-label="' + esc(X.T.chart + ': ' + list.map(function (x) { return wd(X, x.dow) + ' ' + X.money(x.price); }).join(', ')) + '">' +
      list.map(function (x, i) {
        return '<span class="kc-bar' + (x.dow === 0 || x.dow === 6 ? ' is-we' : '') + '" style="--h:' + Math.max(14, Math.round(x.price / (max || 1) * 100)) + '%;--i:' + i + '"><i></i>' + (labels ? '<em>' + esc(wd(X, x.dow)) + (prices && x.price > 0 ? '<small>' + K.short(X.C.cur, x.price) + '</small>' : '') + '</em>' : '') + '</span>';
      }).join('') + '</div>';
  }

  K.sumHtml = function (X) {
    var S = X.S, T = X.T, m = S.moto ? X.by[S.moto] : null;
    if (!S.start) {
      var wk = m ? [1, 2, 3, 4, 5, 6, 0].map(function (dw) { return { dow: dw, price: m.p[dw] }; }) : null;
      return '<p class="kc-sum-k">' + esc(T.sum_title) + '</p>' + (wk ? '<p class="kc-sum-cap">' + esc(K.tpl(T.legend_price, { cur: X.C.cur.sym })) + '</p>' + bars(X, wk, true, true) : '<div class="kc-sum-art" aria-hidden="true">' + K.ico('cal') + '</div>') +
        '<p class="kc-sum-p">' + esc(T.sum_empty) + '</p>' + (m ? cta(X, T.cta_moto, true) : '');
    }
    if (!S.end) return head(X) + '<p class="kc-sum-p">' + esc(T.sum_pick_end) + '</p>' + foot(X);
    if (!m) return K.freeHtml(X) + cta(X, T.cta_any) + foot(X);
    var bd = K.breakdown(m, S.start, S.end), n = bd.days.length, lp = K.late(bd), g = {}, ord = [];
    bd.days.forEach(function (x) { if (!g[x.dow]) { g[x.dow] = { n: 0, p: x.price }; ord.push(x.dow); } g[x.dow].n++; });
    var rows = ord.map(function (dw) {
      var r = g[dw];
      return '<li><span class="kc-r-d">' + esc(wd(X, dw)) + '</span><span class="kc-r-x">' + (r.n > 1 ? r.n + ' × ' + esc(X.money(r.p)) : '') + '</span><span class="kc-r-v">' + esc(X.money(r.n * r.p)) + '</span></li>';
    }).join('');
    var h = head(X) + (n <= 31 ? bars(X, bd.days, n <= 10) : '') + '<ul class="kc-rows">' + rows + '</ul>' +
      '<div class="kc-total"><span class="kc-total-k">' + esc(T.total) + '</span><span class="kc-total-v" data-kc-total="' + bd.total + '">' + esc(X.money(bd.total)) + '</span>' +
      (X.C.cur.code !== 'CZK' ? '<span class="kc-total-s">' + esc(tpl(T.pay_czk, { price: X.czk(bd.total) })) + '</span>' : '') +
      (n > 1 ? '<span class="kc-total-s">' + esc(tpl(T.avg, { price: X.money(bd.total / n) })) + '</span>' : '') + '</div>';
    h += '<div class="kc-late"><span class="kc-late-pct" aria-hidden="true">½</span><p>' + (lp > 0
      ? '<span class="kc-late-t">' + esc(T.late_title) + '</span> ' + esc(tpl(T.late_text, { amount: X.money(lp), total: X.money(bd.total - lp) }))
      : esc(T.late_one)) + '</p></div>';
    if (!m.tr) h += '<ul class="kc-inc">' + (T.includes || []).map(function (s) { return '<li>' + K.ico('check') + esc(s) + '</li>'; }).join('') + '</ul>';
    if (n < (m.min || 1)) return h + '<p class="kc-warn">' + esc(tpl(T.min_days, { n: m.min })) + '</p>' + foot(X);
    return h + cta(X, T.cta) + foot(X);
  };

  // Bez motorky: stroje volné v CELÉM termínu (pobočka), od nejlevnějšího; dětské na konec
  K.freeHtml = function (X) {
    var S = X.S, T = X.T, n = K.count(S.start, S.end), rows = [];
    X.pool().forEach(function (id) {
      var m = X.by[id], b = X.S.bk[id] || {};
      for (var x = S.start; x <= S.end; x = K.add(x, 1)) if (b[x]) return;
      if (n < (m.min || 1)) return;
      rows.push({ m: m, t: K.breakdown(m, S.start, S.end).total });
    });
    rows.sort(function (a, b) { return ((a.m.c === 'detske') - (b.m.c === 'detske')) || a.t - b.t; });
    var h = head(X) + '<p class="kc-sum-k kc-sum-k--list">' + esc(tpl(T.free_title, { n: rows.length })) + '</p>';
    if (!rows.length) return h + '<p class="kc-warn">' + esc(T.free_none) + '</p>';
    h += '<ul class="kc-free">' + rows.slice(0, 6).map(function (r, i) {
      var br = X.branch(r.m.b);
      return '<li style="--i:' + i + '"><button type="button" class="kc-free-b" data-pick="' + esc(r.m.id) + '">' +
        (r.m.img ? '<img src="' + esc(r.m.img) + '" alt="' + esc(r.m.m) + '" width="72" height="48" loading="lazy" decoding="async">' : '<span></span>') +
        '<span class="kc-free-m"><span class="kc-free-n">' + esc(r.m.m) + '</span><span class="kc-free-s">' + esc([br && !S.branch ? br.n : '', X.cat(r.m.c)].filter(Boolean).join(' · ')) + '</span></span>' +
        '<span class="kc-free-p">' + esc(X.money(r.t)) + K.ico('arrow') + '</span></button></li>';
    }).join('') + '</ul>';
    if (rows.length > 6) h += '<p class="kc-more">' + esc(tpl(T.free_more, { n: rows.length - 6 })) + '</p>';
    return h;
  };
})(window);
