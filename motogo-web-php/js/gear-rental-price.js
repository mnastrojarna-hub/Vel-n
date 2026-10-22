/* MotoGo24 — Půjčení výbavy: serverová cena a dárkový poukaz (2026-10-23).
   quote_gear_booking = nanečisto create_web_gear_booking (cena z DB, poukaz, sklad, zavřená
   pobočka) → souhrn ukáže serverovou cenu, odečet poukazu a případné varování. Bez odpovědi
   (funkce na serveru ještě není) zůstává klientské nacenění z js/gear-rental.js. U výbavy jen
   dárkové poukazy (slevové kódy / věrnost ne — rozhoduje server, `bad_voucher`).
   Stav v MGGR.S (sq = poslední odpověď, vcode / vstate = poukaz), prvky v MGGR.E. */
(function () {
  var G = window.MGGR;
  if (!G) return;
  var C = G.C, T = G.T, esc = G.esc, tpl = G.tpl, q = G.q, liveT = 0, liveN = 0;

  G.voucherAmt = function (o) { return G.num(o.voucher_amount) || G.num(o.voucher && o.voucher.amount) || G.num(o.discount_amount); };
  G.errText = function (o) {
    var e = o && o.error, by = G.by || {};
    if (e === 'out_of_stock') return tpl(T.err_stock, { items: G.itemsLabel(o.items) });
    if (e === 'below_minimum') return T.err_min;
    if (e === 'branch_closed') return T.err_closed;
    if (e === 'too_long') return tpl(T.err_long, { n: (o && o.max_days) || C.maxDays });
    if (e === 'bad_size') return tpl(T.err_size, { item: o.key && by[o.key] ? by[o.key].label : '' });
    if (e === 'disabled') return T.err_disabled;
    if (e === 'bad_dates') return T.err_dates;
    return e ? T.err_generic : '';
  };

  G.live = function live(force) {
    var S = G.S;
    if (!G.complete()) { S.sq = null; if (S.vcode) S.vstate = 'need'; G.renderVoucher(); return; }
    var key = [S.branch, S.start, S.end, JSON.stringify(G.itemsArg()), S.vcode].join('|');
    if (!force && S.sq && S.sq.key === key) return;
    var n = ++liveN;
    S.sq = { key: key, wait: true };
    if (S.vcode) S.vstate = 'wait';
    G.renderVoucher();
    clearTimeout(liveT);
    liveT = setTimeout(function () {
      G.rpc('quote_gear_booking', { p_branch_id: S.branch, p_start: S.start, p_end: S.end, p_items: G.itemsArg(), p_voucher_code: S.vcode || null })
        .then(function (o) {
          if (n !== liveN) return;
          o = o || {};
          if (o.error === 'rpc_error') { S.sq = null; if (S.vcode) S.vstate = ''; G.renderSum(); G.renderVoucher(); return; }
          S.sq = { key: key, res: o };
          if (S.vcode) {
            if (o.error === 'bad_voucher') { S.vstate = 'bad'; S.vcode = ''; S.sq = null; live(true); }
            else S.vstate = o.error ? '' : (G.voucherAmt(o) > 0 ? 'ok' : 'bad');
          }
          G.renderSum(); G.renderVoucher();
        }).catch(function () { if (n === liveN) { S.sq = null; G.renderSum(); } });
    }, 350);
  };

  G.renderVoucher = function () {
    var S = G.S, m = G.E && G.E.vmsg, s = S.vstate, r = S.sq && S.sq.res;
    if (!m) return;
    m.hidden = !s;
    m.className = 'gr-voucher-msg' + (s === 'bad' ? ' is-bad' : (s === 'ok' ? ' is-ok' : ''));
    m.innerHTML = s === 'ok' && r ? esc(tpl(T.voucher_line, { code: (r.voucher && r.voucher.code) || S.vcode }) + ': −' + G.money(G.voucherAmt(r))) +
        ' <button type="button" class="gr-linkbtn" data-gr-vdel>' + esc(T.voucher_remove) + '</button>'
      : esc(s === 'bad' ? T.voucher_bad : (s === 'wait' ? T.voucher_wait : (s === 'need' ? T.voucher_need : '')));
  };

  // Události pole poukazu (volá js/gear-rental.js při startu formuláře)
  G.bindVoucher = function () {
    var S = G.S, vo = q('#gr-voucher-on'), vi = q('#gr-voucher'), ap = q('[data-gr-vapply]');
    if (!vo || !vi) return;
    vo.addEventListener('change', function () {
      q('#gr-voucher-box').hidden = !vo.checked;
      if (vo.checked) { try { vi.focus(); } catch (e) {} } else if (S.vcode || S.vstate) { S.vcode = ''; S.vstate = ''; G.live(true); G.renderSum(); }
    });
    function apply() {
      var c = String(vi.value || '').trim().toUpperCase();
      if (!c) return;
      S.vcode = c; S.vstate = G.complete() ? 'wait' : 'need';
      G.renderVoucher(); G.live(true);
    }
    ap && ap.addEventListener('click', apply);
    vi.addEventListener('keydown', function (ev) { if (ev.key === 'Enter') { ev.preventDefault(); apply(); } });
    G.E.vmsg && G.E.vmsg.addEventListener('click', function (ev) {
      if (!ev.target.closest('[data-gr-vdel]')) return;
      S.vcode = ''; S.vstate = ''; vi.value = ''; G.live(true); G.renderSum(); G.renderVoucher();
    });
  };
})();
