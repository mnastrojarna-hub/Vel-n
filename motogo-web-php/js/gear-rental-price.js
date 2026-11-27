/* MotoGo24 — Půjčení výbavy: serverová cena a slevové kódy / dárkové poukazy (2026-10-23, kódy 2026-11-27).
   quote_gear_booking = nanečisto create_web_gear_booking (cena z DB, kódy, sklad, zavřená pobočka) →
   souhrn ukáže serverovou cenu, řádek každé slevy a případné varování. Kódy jako rezervace motorky:
   víc slevových kódů a dárkových poukazů najednou (nejvýš jeden procentní), poukaz ze Slevomatu se
   při prvním použití ověří přes edge slevomat-voucher. Platnost a výši slev určuje VŽDY server.
   Stav v MGGR.S (sq = poslední odpověď, codes = uplatněné kódy, ctry = zkoušený kód, cmsg = hláška). */
(function () {
  var G = window.MGGR;
  if (!G) return;
  var C = G.C, T = G.T, esc = G.esc, tpl = G.tpl, q = G.q, liveT = 0, liveN = 0;

  /** Slevy z odpovědi serveru: [{kind, code, amount}] (starší odpověď jen s poukazem → jeden řádek). */
  G.discounts = function (o) {
    if (o && Array.isArray(o.discounts)) return o.discounts.filter(function (d) { return G.num(d.amount) > 0; });
    var va = o ? (G.num(o.voucher_amount) || G.num(o.voucher && o.voucher.amount)) : 0;
    return va > 0 ? [{ kind: 'voucher', code: (o.voucher && o.voucher.code) || '', amount: va }] : [];
  };
  G.voucherAmt = function (o) {
    return G.discounts(o).reduce(function (s, d) { return s + G.num(d.amount); }, 0) || G.num(o && o.discount_amount);
  };
  G.discountLabel = function (d) { return tpl(d.kind === 'promo_code' ? (T.code_line || T.voucher_line) : T.voucher_line, { code: d.code || '' }); };
  G.codeErr = function (o) {
    var bad = o && Array.isArray(o.invalid) && o.invalid[0] ? o.invalid[0] : o || {}, e = bad.error;
    if (o && o.in_use) return T.code_inuse || T.voucher_bad;
    if (e === 'min_order') return tpl(T.code_min || T.voucher_bad, { min: G.money(G.num(bad.min)) });
    if (e === 'multiple_percent') return T.code_pct || T.voucher_bad;
    if (e === 'not_applicable') return T.code_moto || T.voucher_bad;
    if (e === 'rate_limited') return T.code_rate || T.voucher_bad;
    return T.voucher_bad;
  };
  G.errText = function (o) {
    var e = o && o.error, by = G.by || {};
    if (e === 'out_of_stock') return tpl(T.err_stock, { items: G.itemsLabel(o.items) });
    if (e === 'below_minimum') return T.err_min;
    if (e === 'branch_closed') return T.err_closed;
    if (e === 'too_long') return tpl(T.err_long, { n: (o && o.max_days) || C.maxDays });
    if (e === 'bad_size') return tpl(T.err_size, { item: o.key && by[o.key] ? by[o.key].label : '' });
    if (e === 'disabled') return T.err_disabled;
    if (e === 'bad_dates') return T.err_dates;
    if (e === 'bad_code') return G.codeErr(o);
    return e ? T.err_generic : '';
  };

  function msg(kind, text) { G.S.cmsg = kind ? { kind: kind, text: text || '' } : null; G.renderVoucher(); }
  // Poukaz ze Slevomatu se do systému dostane až ověřením u Slevomatu (jako rezervace motorky)
  function slevomat(code) {
    return G.edge('slevomat-voucher', { action: 'check', code: code }, false)
      .then(function (r) { return !!(r && r.valid && r.voucher_id); }).catch(function () { return false; });
  }

  G.live = function live(force, _retried) {
    var S = G.S;
    S.codes = S.codes || [];
    var codes = S.codes.concat(S.ctry ? [S.ctry] : []);
    if (!G.complete()) { S.sq = null; if (codes.length) msg('need', T.voucher_need); else G.renderVoucher(); return; }
    var key = [S.branch, S.start, S.end, JSON.stringify(G.itemsArg()), codes.join(',')].join('|');
    if (!force && S.sq && S.sq.key === key) return;
    var n = ++liveN;
    S.sq = { key: key, wait: true };
    if (S.ctry) msg('wait', T.voucher_wait);
    clearTimeout(liveT);
    liveT = setTimeout(function () {
      G.rpcCodes('quote_gear_booking', { p_branch_id: S.branch, p_start: S.start, p_end: S.end, p_items: G.itemsArg() }, codes)
        .then(function (o) {
          if (n !== liveN) return;
          o = o || {};
          // starší server (jen jeden dárkový poukaz): chybu převést na společný tvar
          if (o.error === 'bad_voucher') { o.error = 'bad_code'; o.code = codes[0] || ''; }
          if (o.error === 'rpc_error') { S.sq = null; if (S.ctry) { S.ctry = ''; msg('bad', T.err_generic); } G.renderSum(); return; }
          if (o.error === 'bad_code' && o.code) {
            var c = String(o.code).toUpperCase();
            if (c === S.ctry && !_retried && (!o.invalid || !o.invalid[0] || o.invalid[0].error === 'code_invalid')) {
              // neznámý kód → zkusit Slevomat (po ověření je z něj dárkový poukaz) a nacenit znovu
              return slevomat(c).then(function (ok) {
                if (n !== liveN) return;
                if (ok) return live(true, true);
                S.ctry = ''; msg('bad', G.codeErr(o)); live(true);
              });
            }
            // neplatný kód z dřívějška (např. jiný termín pod min. hodnotu) nebo zkoušený → pryč a znovu nacenit
            S.codes = S.codes.filter(function (x) { return x !== c; });
            if (S.ctry === c) S.ctry = '';
            msg('bad', G.codeErr(o)); S.sq = null; return live(true);
          }
          // starší server umí jen jeden dárkový poukaz → druhý kód nepřijmout naoko
          if (G.legacyCodes && S.ctry && S.codes.length) { S.ctry = ''; msg('bad', T.voucher_bad); S.sq = null; return live(true); }
          S.sq = { key: key, res: o };
          if (S.ctry) { S.codes.push(S.ctry); S.ctry = ''; }
          if (S.cmsg && (S.cmsg.kind === 'wait' || S.cmsg.kind === 'need')) S.cmsg = null;
          G.renderSum(); G.renderVoucher();
        }).catch(function () { if (n === liveN) { S.sq = null; G.renderSum(); } });
    }, 350);
  };

  G.renderVoucher = function () {
    var S = G.S, m = G.E && G.E.vmsg, r = S.sq && !S.sq.wait && S.sq.res, cm = S.cmsg;
    if (!m) return;
    var lines = (S.codes || []).map(function (c) {
      var d = r ? G.discounts(r).filter(function (x) { return String(x.code).toUpperCase() === c; })[0] : null;
      var label = d ? G.discountLabel(d) + ': −' + G.money(G.num(d.amount)) : c;
      return '<span class="gr-voucher-ok">' + esc(label) + ' <button type="button" class="gr-linkbtn" data-gr-vdel="' + esc(c) + '">' + esc(T.voucher_remove) + '</button></span>';
    });
    var note = cm && cm.text ? '<span class="gr-voucher-note' + (cm.kind === 'bad' ? ' is-bad' : '') + '">' + esc(cm.text) + '</span>' : '';
    m.hidden = !lines.length && !note;
    m.className = 'gr-voucher-msg' + (cm && cm.kind === 'bad' && !lines.length ? ' is-bad' : (lines.length ? ' is-ok' : ''));
    m.innerHTML = lines.join('<br>') + (lines.length && note ? '<br>' : '') + note;
  };

  // Události pole kódů (volá js/gear-rental.js při startu formuláře)
  G.bindVoucher = function () {
    var S = G.S, vo = q('#gr-voucher-on'), vi = q('#gr-voucher'), ap = q('[data-gr-vapply]');
    if (!vo || !vi) return;
    S.codes = S.codes || [];
    vo.addEventListener('change', function () {
      q('#gr-voucher-box').hidden = !vo.checked;
      if (vo.checked) { try { vi.focus(); } catch (e) {} } else if (S.codes.length || S.ctry || S.cmsg) { S.codes = []; S.ctry = ''; S.cmsg = null; G.live(true); G.renderSum(); G.renderVoucher(); }
    });
    function apply() {
      var c = String(vi.value || '').trim().toUpperCase();
      if (!c) return;
      if (S.codes.indexOf(c) >= 0) { msg('bad', T.code_dup || T.voucher_bad); return; }
      vi.value = '';
      S.ctry = c;
      if (!G.complete()) { msg('need', T.voucher_need); return; }
      G.live(true);
    }
    ap && ap.addEventListener('click', apply);
    vi.addEventListener('keydown', function (ev) { if (ev.key === 'Enter') { ev.preventDefault(); apply(); } });
    G.E.vmsg && G.E.vmsg.addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-gr-vdel]');
      if (!b) return;
      var c = b.getAttribute('data-gr-vdel');
      S.codes = S.codes.filter(function (x) { return x !== c; }); S.cmsg = null;
      G.live(true); G.renderSum(); G.renderVoucher();
    });
  };
})();
