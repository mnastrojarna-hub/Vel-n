/* MotoGo24 — Půjčení výbavy: odeslání rezervace (MGGR.submit z js/gear-rental.js, 2026-10-23).
   create_web_gear_booking (cenu, sklad, poukaz, souhlasy i identitu ověří server) →
   process-payment (type booking, source web, checkout) → Stripe. E-mail s účtem → přihlášení
   (gear-rental-auth.js) a nový pokus; nezaplacený koncept se při dalším odeslání znovu použije
   (p_existing_booking_id ze sessionStorage — server ho vezme jen u vlastní nezaplacené výpůjčky). */
(function () {
  var G = window.MGGR;
  if (!G) return;
  var C = G.C, T = G.T, tpl = G.tpl, q = G.q, DK = 'mg_gear_draft', busy = false;
  var ERR = { bad_size: 'err_size', branch_closed: 'err_closed', too_long: 'err_long', disabled: 'err_disabled', bad_customer: 'err_contact',
    bad_branch: 'err_branch', branch_unavailable: 'err_branch', bad_dates: 'err_dates', no_items: 'err_items', consents_required: 'err_agree', too_many: 'err_too_many',
    below_minimum: 'err_min', bad_voucher: 'voucher_bad' };

  function val(id) { var e = q('#' + id); return e ? String(e.value || '').trim() : ''; }
  function fail(msg) {
    var E = G.E;
    E.err.textContent = msg; E.err.hidden = false;
    try { E.err.scrollIntoView({ behavior: 'smooth', block: 'center' }); } catch (e) {}
  }
  G.draft = function (v) {
    try {
      if (v === undefined) return sessionStorage.getItem(DK) || null;
      if (v) sessionStorage.setItem(DK, v); else sessionStorage.removeItem(DK);
    } catch (e) {}
    return null;
  };

  G.submit = function () {
    var S = G.S, E = G.E, by = G.by;
    if (busy || !S) return;
    E.err.hidden = true;
    var ks = G.keys();
    if (!S.branch) return fail(T.err_branch);
    if (!S.start || !S.end) return fail(T.err_dates);
    if (!ks.length) return fail(T.err_items);
    for (var i = 0; i < ks.length; i++) if (by[ks[i]].sizes.length && !S.sel[ks[i]]) return fail(tpl(T.err_size, { item: by[ks[i]].label }));
    var cust = { name: val('gr-name'), email: val('gr-email').toLowerCase(), phone: val('gr-phone'), street: val('gr-street'), zip: val('gr-zip'), city: val('gr-city') };
    if (q('#gr-company-on') && q('#gr-company-on').checked) { cust.company = val('gr-company-name'); cust.ico = val('gr-ico'); cust.dic = val('gr-dic'); }
    if (cust.name.length < 3 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cust.email) || cust.phone.length < 6) return fail(T.err_contact);
    if (!q('#gr-agree-vop').checked || !q('#gr-agree-gdpr').checked) return fail(T.err_agree);
    var label = E.go.innerHTML, br = G.branch();
    busy = true; E.go.disabled = true;
    E.go.innerHTML = '<span>' + G.esc(T.processing) + '</span>';
    function done(msg) { busy = false; E.go.disabled = false; E.go.innerHTML = label; if (msg) fail(msg); }
    G.rpc('create_web_gear_booking', {
      p_branch_id: S.branch, p_start: S.start, p_end: S.end, p_items: G.itemsArg(), p_customer: cust,
      p_pickup_time: br && !br.self ? val('gr-time') || null : null, p_return_time: null, p_lang: C.lang,
      p_note: val('gr-note') || null, p_voucher_code: S.vcode || null, p_existing_booking_id: G.draft(),
      p_consents: { vop: true, gdpr: true }
    }).then(function (o) {
      o = o || {};
      if (o.success && o.booking_id) {
        G.draft(o.booking_id);
        return G.pay(o.booking_id, o.amount != null ? o.amount : o.total).then(function (r) {
          if (r.ok) return; // přesměrování na Stripe — tlačítko zůstává zablokované
          if (r.code === 'already_paid') { G.draft(''); location.href = G.url('booking_id=' + encodeURIComponent(o.booking_id)); return; }
          done(G.payMsg(r));
        });
      }
      var e = o.error;
      if (e === 'email_exists' && G.showLogin) { done(''); return G.showLogin(cust.email, G.submit); }
      if (e === 'email_mismatch') return done(tpl(T.err_mismatch, { email: o.email || (G.user && G.user.email) || '' }));
      if (e === 'out_of_stock') { G.reloadAvail(); return done(G.errText(o)); }
      if (e === 'bad_voucher') { S.vcode = ''; S.vstate = 'bad'; G.live(true); }
      // neznámá chyba s uloženým konceptem (např. koncept mezitím zaplacený / cizí) → jednou bez něj
      if (e && !ERR[e] && e !== 'rpc_error' && G.draft()) { G.draft(''); done(''); return G.submit(); }
      done(e && ERR[e] ? tpl(T[ERR[e]], { n: o.max_days || C.maxDays, item: o.key && by[o.key] ? by[o.key].label : '' }) : T.err_generic);
    }).catch(function () { done(T.err_generic); });
  };
})();
