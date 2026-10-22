/* MotoGo24 — Půjčení oblečení (jen výbava, bez motorky): pages/pujceni-obleceni.php.
   Pobočka → termín (1. klik = 1 den, 2. klik = poslední den) → kusy s velikostmi → kontakt →
   RPC create_gear_rental_order (cena ze serveru) → process-payment (kind=products) → Stripe.
   Návrat ?order_id=&session_id= = potvrzení (get_gear_rental_confirmation). Kalendář kreslí
   K.calHtml z landing-calc-view.js; nacenění zrcadlí SQL _gear_rental_quote. */
(function () {
  var d = document, K = window.MGKC, el = d.getElementById('gr-data');
  if (!K || !K.calHtml || !el) return;
  var C;
  try { C = JSON.parse(el.textContent); } catch (e) { return; }
  var T = C.t, today = K.today(), q = function (s) { return d.querySelector(s); };
  var S = { branch: '', start: null, end: null, open: false, y: +today.slice(0, 4), mo: +today.slice(5, 7) - 1, moto: '', sel: {}, note: '' };
  var by = {}; C.prices.forEach(function (p) { by[p.key] = p; });
  var items = C.prices.filter(function (p) { return p.kind === 'item'; });
  var sets = C.prices.filter(function (p) { return p.kind === 'set'; }).sort(function (a, b) {
    return (b.includes.length - a.includes.length) || (a.p - b.p) || (a.key < b.key ? -1 : 1);
  });
  var last = K.add(today, C.maxAhead || 400);
  var esc = K.esc, tpl = K.tpl;
  var money = function (v) { return K.money(C.cur, v); };
  var days = function (n) { return tpl(n === 1 ? T.days_one : (n >= 2 && n <= 4 ? T.days_few : T.days_many), { n: n }); };
  function fmt(iso, o) {
    try { var p = { timeZone: 'UTC' }; for (var k in o) p[k] = o[k]; return new Intl.DateTimeFormat(C.lang, p).format(new Date(K.ms(iso))); } catch (e) { return iso; }
  }
  function closed(iso) {
    if (!S.branch) return false;
    for (var i = 0; i < C.closures.length; i++) { var c = C.closures[i]; if (c.b === S.branch && iso >= c.f && iso <= c.t) return true; }
    return false;
  }
  function st(iso) { return iso < today ? 'past' : (iso > last || closed(iso) ? 'busy' : 'free'); }
  var X = { C: C, T: T, S: S, by: {}, today: today, st: st, ready: function () { return true; }, fmt: fmt, money: money };

  // ---- nacenění (shodně se SQL _gear_rental_quote) ----
  function keys() { return items.filter(function (p) { return S.sel[p.key] !== undefined; }).map(function (p) { return p.key; }); }
  function quote() {
    var left = keys(), lines = [], per = 0, single = 0;
    left.forEach(function (k) { single += by[k].p; });
    sets.forEach(function (s) {
      if (!s.includes.length || !s.includes.every(function (k) { return left.indexOf(k) >= 0; })) return;
      var sum = 0; s.includes.forEach(function (k) { sum += by[k] ? by[k].p : 0; });
      if (!(s.p < sum)) return;
      lines.push(s); per += s.p;
      left = left.filter(function (k) { return s.includes.indexOf(k) < 0; });
    });
    items.forEach(function (p) { if (left.indexOf(p.key) >= 0) { lines.push(p); per += p.p; } });
    return { lines: lines, per: per, save: Math.max(0, single - per) };
  }
  function nDays() { return S.start && S.end ? K.count(S.start, S.end) : 0; }

  // ---- render ----
  var E = { br: q('[data-gr-branches]'), self: q('[data-gr-selfnote]'), cal: q('[data-gr-cal]'), hint: q('[data-gr-hint]'), time: q('[data-gr-time]'),
    quick: q('[data-gr-quick]'), items: q('[data-gr-items]'), sum: q('[data-gr-sum]'), err: q('[data-gr-err]'), go: q('[data-gr-go]'), form: q('#gr-form') };
  function renderBranches() {
    if (!E.br) return;
    E.br.innerHTML = C.branches.map(function (b) {
      return '<label class="gr-br' + (S.branch === b.id ? ' is-on' : '') + '"><input type="radio" name="gr-branch" value="' + esc(b.id) + '"' + (S.branch === b.id ? ' checked' : '') + '>' +
        '<span class="gr-br-n">' + K.ico('pin') + esc(b.n) + '</span><span class="gr-br-s">' + esc(b.self ? T.branch_self : T.branch_staffed) + '</span>' +
        (b.a ? '<span class="gr-br-a">' + esc(b.a) + '</span>' : '') + '</label>';
    }).join('');
    var br = branch();
    if (E.self) E.self.hidden = !(br && br.self);
    if (E.time) E.time.hidden = !(br && !br.self);
  }
  function branch() { for (var i = 0; i < C.branches.length; i++) if (C.branches[i].id === S.branch) return C.branches[i]; return null; }
  function renderCal() {
    if (!E.cal) return;
    E.cal.innerHTML = K.calHtml(X);
    E.hint.textContent = S.note || (!S.start ? T.hint_start : (S.open ? T.hint_end : T.hint_done));
    E.hint.classList.toggle('is-warn', !!S.note);
  }
  function renderItems() {
    if (E.quick) E.quick.innerHTML = C.prices.filter(function (p) { return p.kind === 'set'; }).map(function (s) {
      var on = s.includes.every(function (k) { return S.sel[k] !== undefined; }) && keys().length === s.includes.length;
      return '<button type="button" class="gr-qs' + (on ? ' is-on' : '') + '" data-set="' + esc(s.key) + '" aria-pressed="' + on + '"><span class="gr-qs-t">' + esc(s.label) + '</span>' +
        (s.desc ? '<span class="gr-qs-d">' + esc(s.desc) + '</span>' : '') + '<span class="gr-qs-p">' + esc(money(s.p)) + ' ' + esc(T.per_day) + '</span></button>';
    }).join('');
    if (E.items) E.items.innerHTML = items.map(function (p) {
      var on = S.sel[p.key] !== undefined, sz = S.sel[p.key] || '';
      return '<div class="gr-it' + (on ? ' is-on' : '') + '"><label class="gr-it-h"><input type="checkbox" data-item="' + esc(p.key) + '"' + (on ? ' checked' : '') + '>' +
        '<span class="gr-it-n">' + esc(p.label) + '</span><span class="gr-it-p">' + esc(money(p.p)) + ' <small>' + esc(T.per_day) + '</small></span></label>' +
        (on && p.sizes.length ? '<div class="gr-sizes" role="group" aria-label="' + esc(p.label + ' — ' + T.size_choose) + '">' + p.sizes.map(function (z) {
          return '<button type="button" class="gr-sz' + (z === sz ? ' is-on' : '') + '" data-size="' + esc(z) + '" data-for="' + esc(p.key) + '" aria-pressed="' + (z === sz) + '">' + esc(z) + '</button>';
        }).join('') + '</div>' : '') + (on && p.sizes.length && !sz ? '<p class="gr-sz-hint">' + esc(T.size_choose) + '</p>' : '') + '</div>';
    }).join('');
  }
  function renderSum() {
    if (!E.sum) return;
    var qq = quote(), n = nDays(), br = branch();
    if (!qq.lines.length || !n || !br) { E.sum.innerHTML = '<p class="gr-sum-k">' + esc(T.sum_title) + '</p><p class="gr-sum-e">' + esc(T.sum_empty) + '</p>'; return; }
    var rows = qq.lines.map(function (l) {
      var sz = (l.kind === 'set' ? l.includes : [l.key]).map(function (k) { return S.sel[k] ? (l.kind === 'set' ? (by[k] ? by[k].label.toLowerCase() + ' ' : '') : '') + S.sel[k] : ''; }).filter(Boolean).join(', ');
      return '<li><span class="gr-l-n">' + esc(l.label) + (sz ? ' <small>' + esc(sz) + '</small>' : '') + '</span><span class="gr-l-v">' + esc(n + ' × ' + money(l.p)) + '</span></li>';
    }).join('');
    E.sum.innerHTML = '<p class="gr-sum-k">' + esc(T.sum_title) + '</p>' +
      '<p class="gr-sum-m">' + K.ico('pin') + esc(br.n) + ' · ' + esc(fmt(S.start, { day: 'numeric', month: 'numeric' }) + (S.end !== S.start ? ' – ' + fmt(S.end, { day: 'numeric', month: 'numeric', year: 'numeric' }) : '')) + ' (' + esc(days(n)) + ')</p>' +
      '<ul class="gr-lines">' + rows + '</ul>' +
      (qq.save > 0 ? '<p class="gr-save">' + K.ico('check') + esc(tpl(T.save || '', { amount: money(qq.save * n) })) + '</p>' : '') +
      '<p class="gr-total"><span>' + esc(T.total) + '</span><b>' + esc(money(qq.per * n)) + '</b></p>';
  }
  function render() { renderBranches(); renderCal(); renderItems(); renderSum(); }

  // ---- výběr termínu: 1. klik = 1 den (otevřený rozsah), 2. klik pozdější den = konec ----
  function rangeOk(a, b) { for (var x = a; x <= b; x = K.add(x, 1)) if (st(x) !== 'free') return false; return true; }
  function pick(iso) {
    S.note = '';
    if (S.open && S.start && iso >= S.start) {
      if (!rangeOk(S.start, iso)) S.note = T.err_closed;
      else if (K.count(S.start, iso) > C.maxDays) S.note = tpl(T.err_long, { n: C.maxDays });
      else { S.end = iso; S.open = false; }
    } else { S.start = S.end = iso; S.open = true; }
    renderCal(); renderSum();
  }
  function setBranch(id) {
    S.branch = id;
    if (S.start && !rangeOk(S.start, S.end || S.start)) { S.start = S.end = null; S.open = false; S.note = T.err_closed; }
    render();
  }

  // ---- události ----
  if (E.form) {
    E.br.addEventListener('change', function (ev) { var r = ev.target; if (r && r.name === 'gr-branch') setBranch(r.value); });
    E.cal.addEventListener('click', function (ev) {
      var b = ev.target.closest('button'); if (!b || b.disabled) return;
      if (b.hasAttribute('data-nav')) {
        S.mo += +b.getAttribute('data-nav');
        if (S.mo < 0) { S.mo = 11; S.y--; } else if (S.mo > 11) { S.mo = 0; S.y++; }
        renderCal();
      } else if (b.getAttribute('data-d')) pick(b.getAttribute('data-d'));
    });
    E.quick.addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-set]'); if (!b) return;
      var s = by[b.getAttribute('data-set')], all = s.includes.every(function (k) { return S.sel[k] !== undefined; }) && keys().length === s.includes.length;
      if (all) S.sel = {}; else { var n = {}; s.includes.forEach(function (k) { if (by[k]) n[k] = S.sel[k] || ''; }); S.sel = n; }
      renderItems(); renderSum();
    });
    E.items.addEventListener('change', function (ev) {
      var c = ev.target; if (!c || !c.hasAttribute('data-item')) return;
      var k = c.getAttribute('data-item');
      if (c.checked) S.sel[k] = S.sel[k] || ''; else delete S.sel[k];
      renderItems(); renderSum();
    });
    E.items.addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-size]'); if (!b) return;
      var k = b.getAttribute('data-for'), z = b.getAttribute('data-size');
      S.sel[k] = S.sel[k] === z ? '' : z;
      renderItems(); renderSum();
    });
    var co = q('#gr-company-on'); co && co.addEventListener('change', function () { q('#gr-company').hidden = !co.checked; });
    var ts = q('#gr-time');
    if (ts) for (var h = 7; h <= 20; h++) { var o = d.createElement('option'), v = (h < 10 ? '0' : '') + h + ':00'; o.value = o.textContent = v; if (h === 9) o.selected = true; ts.appendChild(o); }
    E.form.addEventListener('submit', submit);
  }

  function val(id) { var e = q('#' + id); return e ? String(e.value || '').trim() : ''; }
  function fail(msg) { E.err.textContent = msg; E.err.hidden = false; E.err.scrollIntoView({ behavior: 'smooth', block: 'center' }); }
  var ERR = { bad_size: 'err_size', branch_closed: 'err_closed', too_long: 'err_long', disabled: 'err_disabled', bad_customer: 'err_contact', bad_branch: 'err_branch', bad_dates: 'err_dates', no_items: 'err_items' };
  function submit(ev) {
    ev.preventDefault();
    E.err.hidden = true;
    var ks = keys();
    if (!S.branch) return fail(T.err_branch);
    if (!S.start || !S.end) return fail(T.err_dates);
    if (!ks.length) return fail(T.err_items);
    for (var i = 0; i < ks.length; i++) if (by[ks[i]].sizes.length && !S.sel[ks[i]]) return fail(tpl(T.err_size, { item: by[ks[i]].label }));
    var cust = { name: val('gr-name'), email: val('gr-email'), phone: val('gr-phone'), street: val('gr-street'), zip: val('gr-zip'), city: val('gr-city') };
    if (q('#gr-company-on') && q('#gr-company-on').checked) { cust.company = val('gr-company-name'); cust.ico = val('gr-ico'); cust.dic = val('gr-dic'); }
    if (cust.name.length < 3 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cust.email) || cust.phone.length < 6) return fail(T.err_contact);
    if (!q('#gr-agree').checked) return fail(T.err_agree);
    var label = E.go.innerHTML;
    E.go.disabled = true; E.go.innerHTML = '<span>' + esc(T.processing) + '</span>';
    var br = branch(), H = { apikey: C.sb.key, Authorization: 'Bearer ' + C.sb.key, 'Content-Type': 'application/json' };
    fetch(C.sb.url + '/rest/v1/rpc/create_gear_rental_order', { method: 'POST', headers: H, body: JSON.stringify({
      p_branch_id: S.branch, p_start: S.start, p_end: S.end,
      p_items: ks.map(function (k) { return { key: k, size: S.sel[k] || null }; }), p_customer: cust,
      p_pickup_time: br && !br.self ? val('gr-time') : null, p_lang: C.lang, p_note: val('gr-note') || null
    }) }).then(function (r) { return r.json(); }).then(function (o) {
      if (!o || !o.success) {
        var e = o && o.error, m = T[ERR[e]] || T.err_generic;
        throw new Error(tpl(m, { n: (o && o.max_days) || C.maxDays, item: o && o.key && by[o.key] ? by[o.key].label : '' }));
      }
      return fetch(C.sb.url + '/functions/v1/process-payment', { method: 'POST', headers: H, body: JSON.stringify({
        type: 'shop', kind: 'products', source: 'web', order_id: o.order_id, amount: Number(o.total), currency: 'czk',
        customer_email: cust.email, customer_name: cust.name, customer_phone: cust.phone,
        origin: location.origin, locale: C.lang
      }) }).then(function (r) { return r.json(); });
    }).then(function (p) {
      var url = p && (p.checkout_url || p.url);
      if (!url) throw new Error((p && p.error) || T.err_generic);
      location.href = url;
    }).catch(function (e) {
      E.go.disabled = false; E.go.innerHTML = label;
      fail(e && e.message && e.message.indexOf('Failed to fetch') < 0 ? e.message : T.err_generic);
    });
  }

  // ---- návrat ze Stripe: potvrzení ----
  var u = new URLSearchParams(location.search), oid = u.get('order_id'), sid = u.get('session_id') || '';
  var pb = u.get('pobocka');
  if (pb && C.branches.some(function (b) { return b.id === pb; })) S.branch = pb;
  else if (C.branches.length === 1) S.branch = C.branches[0].id;
  if (oid && !u.get('payfail')) confirmView(oid, sid); else render();

  function confirmView(id, session) {
    var box = q('[data-gr-done]'), main = q('[data-gr-main]');
    if (main) main.hidden = true;
    box.hidden = false;
    box.innerHTML = '<div class="gr-ok"><span class="kc-spin" aria-hidden="true"></span><p>' + esc(T.ok_wait) + '</p></div>';
    var H = { apikey: C.sb.key, Authorization: 'Bearer ' + C.sb.key, 'Content-Type': 'application/json' };
    if (session) fetch(C.sb.url + '/functions/v1/process-payment', { method: 'POST', headers: H, body: JSON.stringify({ action: 'verify_shop_session', session_id: session, order_id: id }) }).catch(function () {});
    var n = 0;
    (function poll() {
      fetch(C.sb.url + '/rest/v1/rpc/get_gear_rental_confirmation', { method: 'POST', headers: H, body: JSON.stringify({ p_order_id: id, p_session_id: session || null }) })
        .then(function (r) { return r.json(); }).then(function (o) {
          if (o && o.payment_status === 'paid') return done(box, o, true);
          if (++n < 12) return setTimeout(poll, 2000);
          done(box, o, false);
        }).catch(function () { if (++n < 12) setTimeout(poll, 2000); else done(box, null, false); });
    })();
  }
  function done(box, o, paid) {
    var lines = o && o.lines ? o.lines.map(function (l) {
      var sz = Object.keys(l.sizes || {}).map(function (k) { return l.sizes[k] ? (l.kind === 'set' && by[k] ? by[k].label.toLowerCase() + ' ' : '') + l.sizes[k] : ''; }).filter(Boolean).join(', ');
      return '<li>' + esc(by[l.key] ? by[l.key].label : l.label) + (sz ? ' <small>' + esc(sz) + '</small>' : '') + '</li>';
    }).join('') : '';
    var self = o && o.branch && o.branch.type === 'samoobslužná';
    box.innerHTML = '<div class="gr-ok">' + (paid ? '<div class="gr-ok-ico" aria-hidden="true">✔</div><h2>' + esc(T.ok_title) + '</h2><p>' + esc(T.ok_lead) + '</p>' : '<p>' + esc(T.ok_pending) + '</p>') +
      (o && o.order_number ? '<div class="gr-ok-sum"><p><span>' + esc(T.ok_order) + '</span><b>' + esc(o.order_number) + '</b></p>' +
        (o.branch ? '<p>' + K.ico('pin') + esc(String(o.branch.name || '').replace(/^MotoGo24\s*/i, '')) + (o.branch.address ? ', ' + esc(o.branch.address) : '') + '</p>' : '') +
        (o.start_date ? '<p>' + K.ico('cal') + esc(fmt(o.start_date, { day: 'numeric', month: 'numeric' }) + ' – ' + fmt(o.end_date, { day: 'numeric', month: 'numeric', year: 'numeric' })) + ' (' + esc(days(o.days || 1)) + ')</p>' : '') +
        (lines ? '<ul>' + lines + '</ul>' : '') + (o.total != null ? '<p class="gr-total"><span>' + esc(T.total) + '</span><b>' + esc(K.money({ code: 'CZK', rate: 1, dec: 0, sym: 'Kč' }, o.total)) + '</b></p>' : '') + '</div>' : '') +
      (paid ? '<p>' + esc(self ? T.ok_next_self : T.ok_next_staffed) + ' ' + esc(T.ok_return) + '</p>' : '') +
      '<p class="gr-ok-btns"><a class="lp-btn lp-btn-primary" href="' + esc(C.katalog) + '">' + K.ico('arrow') + '<span>' + esc(T.ok_motos) + '</span></a> <a class="gr-link" href="' + esc(C.home) + '">' + esc(T.ok_home) + '</a></p></div>';
  }
})();
