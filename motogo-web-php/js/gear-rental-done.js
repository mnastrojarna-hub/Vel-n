/* MotoGo24 — Půjčení výbavy: potvrzení, pokračování v rezervaci a její stav (2026-10-23).
   ?booking_id=&session_id= (návrat ze Stripe): ověření session (process-payment
   verify_setup_session — výpůjčka za 0 Kč přes ověření karty) + get_web_gear_booking, dokud
   není zaplaceno. ?resume=<id> (storno platby, e-maily): nezaplacená → souhrn + Zaplatit,
   zaplacená → potvrzení (+ nahrání dokladu, &docs=1 k němu sroluje), zrušená / ukončená /
   nenalezená → hláška a odkaz na novou rezervaci. Karta dokladů: js/gear-rental-docs.js. */
(function () {
  var G = window.MGGR;
  if (!G) return;
  var C = G.C, T = G.T, K = G.K, esc = G.esc, tpl = G.tpl, q = G.q;
  var PAID = ['paid', 'partial_refund', 'refund_pending'];
  var wantDocs = new URLSearchParams(location.search).get('docs') === '1';

  function shell() {
    var box = q('[data-gr-done]'), main = q('[data-gr-main]');
    if (main) main.hidden = true;
    box.hidden = false;
    box.innerHTML = '<div class="gr-ok"><span class="kc-spin" aria-hidden="true"></span><p>' + esc(T.ok_wait) + '</p></div>';
    return box;
  }
  function get(id, session) { return G.rpc('get_web_gear_booking', { p_booking_id: id, p_session_id: session || null }); }
  function isPaid(o) { return !!o && PAID.indexOf(o.payment_status) >= 0; }
  function days(o) {
    var n = G.num(o.days);
    return n || (o.start_date ? K.count(String(o.start_date).slice(0, 10), String(o.end_date || o.start_date).slice(0, 10)) : 0);
  }
  // Plná cena = subtotal (Kč/den × dny); k úhradě = total (bookings.total_price po poukazu —
  // tolik účtuje process-payment, i po zaokrouhlení / úpravě ve Velínu); bez total plná − poukaz
  function full(o) {
    if (o.subtotal != null && G.num(o.subtotal) > 0) return G.num(o.subtotal);
    var per = G.num(o.per_day), n = days(o);
    return per > 0 && n > 0 ? per * n : G.num(o.total) + G.num(o.voucher_amount);
  }
  function toPay(o) { return Math.max(0, o.total != null && o.total !== '' ? G.num(o.total) : full(o) - G.num(o.voucher_amount)); }
  function lines(o) {
    return (Array.isArray(o.lines) ? o.lines : []).map(function (l) {
      // pořadí kusů dle includes (jsonb sizes klíče přeřadí), jako souhrn ve formuláři
      var sz = (Array.isArray(l.includes) && l.includes.length ? l.includes : Object.keys(l.sizes || {})).map(function (k) {
        return l.sizes && l.sizes[k] ? (l.kind === 'set' && G.by[k] ? G.lc(G.by[k].label) + ' ' : '') + l.sizes[k] : '';
      }).filter(Boolean).join(', ');
      return '<li>' + esc(G.by[l.key] ? G.by[l.key].label : (l.label || l.key)) + (sz ? ' <small>' + esc(sz) + '</small>' : '') + '</li>';
    }).join('');
  }
  function summary(o) {
    var b = o.branch, va = G.num(o.voucher_amount), li = lines(o), n = days(o);
    var addr = b ? [String(b.name || '').replace(/^MotoGo24\s*/i, ''), b.address, b.city].filter(Boolean).join(', ') : '';
    return '<div class="gr-ok-sum">' +
      (o.booking_number ? '<p><span>' + esc(T.ok_order) + '</span><b>' + esc(o.booking_number) + '</b></p>' : '') +
      (addr ? '<p>' + K.ico('pin') + esc(addr) + '</p>' : '') +
      (o.start_date ? '<p>' + K.ico('cal') + esc(G.period(o.start_date, o.end_date)) + (n ? ' (' + esc(G.days(n)) + ')' : '') +
        (o.pickup_time ? ' · ' + esc(String(o.pickup_time).slice(0, 5)) : '') + '</p>' : '') +
      (li ? '<ul>' + li + '</ul>' : '') +
      (va > 0 ? '<p class="gr-vline"><span>' + esc(tpl(T.voucher_line, { code: '' }).trim()) + '</span><span>−' + esc(G.czk(va)) + '</span></p>' : '') +
      (full(o) > 0 || va > 0 ? '<p class="gr-total"><span>' + esc(va > 0 && !isPaid(o) ? T.to_pay : T.total) + '</span><b>' + esc(G.czk(toPay(o))) + '</b></p>' : '') + '</div>';
  }
  function btns(o) {
    return '<p class="gr-ok-btns"><a class="lp-btn lp-btn-primary" href="' + esc(C.katalog) + '">' + K.ico('arrow') + '<span>' + esc(T.ok_motos) + '</span></a> ' +
      (o && isPaid(o) ? '<a class="gr-link" href="' + esc(C.manage) + '">' + esc(T.ok_manage) + '</a> ' : '') +
      '<a class="gr-link" href="' + esc(C.home) + '">' + esc(T.ok_home) + '</a></p>' +
      // nepřihlášený (nový účet má náhodné heslo): jak se do úpravy rezervace přihlásit
      (o && isPaid(o) && T.ok_manage_hint && !(G.hasStored && G.hasStored()) ? '<p class="gr-ok-hint">' + esc(T.ok_manage_hint) + '</p>' : '');
  }
  function msgView(box, text, o, keepNew) {
    box.innerHTML = '<div class="gr-ok"><p>' + esc(text) + '</p>' + (o && o.id ? summary(o) : '') +
      (keepNew ? btns(o) : '<p class="gr-ok-btns"><a class="lp-btn lp-btn-primary" href="' + esc(C.page) + '">' + K.ico('arrow') + '<span>' + esc(T.res_new) + '</span></a> ' +
        '<a class="gr-link" href="' + esc(C.home) + '">' + esc(T.ok_home) + '</a></p>') + '</div>';
  }
  function paidView(box, o, ctx) {
    var dd = o.docs || {}, self = o.branch && o.branch.type === 'samoobslužná';
    var docs = dd.required && !dd.ok && G.docsHtml;
    if (G.draft) G.draft('');
    box.innerHTML = '<div class="gr-ok"><div class="gr-ok-ico" aria-hidden="true">✔</div><h2>' + esc(T.ok_title) + '</h2><p>' + esc(T.ok_lead) + '</p>' +
      summary(o) + (docs ? G.docsHtml(o) : '') +
      '<p class="gr-ok-next">' + esc(self ? T.ok_next_self : T.ok_next_staffed) + ' ' + esc(self ? T.ok_return_self : T.ok_return) + '</p>' + btns(o) + '</div>';
    if (!docs) return;
    G.docsBind(box, o, ctx.session);
    if (ctx.docs) setTimeout(function () { try { q('#gr-docs').scrollIntoView({ behavior: 'smooth', block: 'start' }); } catch (e) {} }, 300);
  }
  function payView(box, o, ctx) {
    var pay = toPay(o);
    box.innerHTML = '<div class="gr-ok">' + (ctx.payfail ? '<p class="gr-err gr-payfail" role="alert">' + esc(T.payfail) + '</p>' : '') +
      '<h2>' + esc(T.res_title) + '</h2><p>' + esc(T.res_lead) + '</p>' + summary(o) +
      '<p class="gr-err" data-gr-perr role="alert" hidden></p>' +
      '<button type="button" class="lp-btn lp-btn-primary gr-go" data-gr-pay>' + K.ico('arrow') + '<span>' + esc(tpl(T.res_pay, { amount: G.czk(pay) })) + '</span></button>' +
      '<p class="gr-ok-btns"><a class="gr-link" href="' + esc(C.page) + '">' + esc(T.res_new) + '</a></p></div>';
    var b = q('[data-gr-pay]', box), er = q('[data-gr-perr]', box);
    b.addEventListener('click', function () {
      var lbl = b.innerHTML;
      b.disabled = true; b.innerHTML = '<span>' + esc(T.processing) + '</span>'; er.hidden = true;
      G.pay(o.id, pay).then(function (r) {
        if (r.ok) return;
        if (r.code === 'already_paid') return G.resumeView(o.id, false);
        b.disabled = false; b.innerHTML = lbl;
        er.textContent = G.payMsg(r); er.hidden = false;
      });
    });
  }
  function show(box, o, ctx) {
    if (!o || o.error || !o.id) return msgView(box, ctx.pending ? T.ok_pending : T.res_nf, null, !!ctx.pending);
    if (o.status === 'cancelled') return msgView(box, T.res_cancelled, o);
    if (o.status === 'completed') return msgView(box, T.res_completed, o, true);
    if (isPaid(o)) return paidView(box, o, ctx);
    if (ctx.pending) return msgView(box, T.ok_pending, o, true);
    if (o.can_pay) return payView(box, o, ctx);
    return msgView(box, T.res_nf, o);
  }

  G.confirmView = function (id, session) {
    var box = shell(), n = 0;
    var verify = function () { if (session) G.edge('process-payment', { action: 'verify_setup_session', session_id: session }).catch(function () {}); };
    verify();
    (function poll() {
      get(id, session).then(function (o) {
        if (o && !o.error && (isPaid(o) || o.status === 'cancelled' || o.status === 'completed')) return show(box, o, { session: session, docs: wantDocs });
        if (o && o.error === 'not_found' && n >= 2) return show(box, o, { session: session });
        if (++n < 12) { if (n === 3 || n === 7) verify(); return setTimeout(poll, 2000); }
        show(box, o, { session: session, pending: true });
      }).catch(function () {
        if (++n < 12) setTimeout(poll, 2000);
        else show(box, null, { pending: true });
      });
    })();
  };
  G.resumeView = function (id, payfail) {
    var box = shell();
    get(id, null).then(function (o) { show(box, o, { payfail: payfail, docs: wantDocs }); })
      .catch(function () { msgView(box, T.err_server, null); });
  };
})();
