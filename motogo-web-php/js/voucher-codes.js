/* MotoGo24 — Koupit dárkový poukaz: slevové kódy (2026-11-27).
   Stejná mechanika jako rezervace motorky a půjčení výbavy: víc slevových kódů najednou (nejvýš jeden
   procentní), platnost a výši slevy určuje server (RPC quote_web_voucher_order — tutéž funkci volá
   i process-payment před platbou). Dárkovým poukazem se jiný poukaz zaplatit nedá.
   Použití (pages/poukazy-objednat.php): var GC = MGVoucherCodes({url, key, T, errGen, fmt, amount(),
   print(), onChange()}); GC.list() = uplatněné kódy, GC.quote(a, fee) = odpověď serveru pro danou
   hodnotu a tisk (jinak null), GC.requote() po změně hodnoty, GC.drop(kód, hláška). */
window.MGVoucherCodes = function (cfg) {
  var T = cfg.T, codes = [], tryCode = '', quote = null, qN = 0, qT = 0, note = '', noteBad = false;
  var $ = function (id) { return document.getElementById(id); };
  var on = $('gv-code-on'), box = $('gv-code-box'), input = $('gv-code'), msgEl = $('gv-code-msg'), ap = $('gv-code-apply');
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function codeErr(o) {
    var b = (o && o.invalid && o.invalid[0]) || o || {}, e = b.error;
    if (o && o.error === 'below_minimum') return T.belowMin;
    if (e === 'min_order') return T.min.replace('{min}', cfg.fmt(Number(b.min) || 0));
    if (e === 'multiple_percent') return T.pct;
    if (e === 'not_applicable') return T.moto;
    if (e === 'voucher_not_allowed') return T.voucher;
    if (e === 'rate_limited') return T.rate;
    return T.bad;
  }
  function render() {
    if (!msgEl) return;
    var ls = (quote && quote.discount_codes) || [];
    var lines = codes.map(function (c) {
      var d = ls.filter(function (x) { return String(x.code).toUpperCase() === c; })[0];
      return '<span class="gv-code-ok">' + esc(T.line.replace('{code}', c) + (d ? ': −' + cfg.fmt(Number(d.amount) || 0) : '')) +
        ' <button type="button" class="gv-linkbtn" data-code-del="' + esc(c) + '">' + esc(T.remove) + '</button></span>';
    });
    var n = note ? '<span class="gv-code-note' + (noteBad ? ' is-bad' : '') + '">' + esc(note) + '</span>' : '';
    msgEl.hidden = !lines.length && !n;
    msgEl.innerHTML = lines.join('<br>') + (lines.length && n ? '<br>' : '') + n;
  }
  function say(t, bad) { note = t || ''; noteBad = !!bad; render(); }
  function requote() {
    var list = codes.concat(tryCode ? [tryCode] : []);
    if (!list.length) { quote = null; render(); cfg.onChange(); return; }
    var n = ++qN;
    if (tryCode) say(T.wait);
    clearTimeout(qT);
    qT = setTimeout(function () {
      fetch(cfg.url + '/rest/v1/rpc/quote_web_voucher_order', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: cfg.key, Authorization: 'Bearer ' + cfg.key },
        body: JSON.stringify({ p_amount: cfg.amount(), p_print: !!cfg.print(), p_codes: list })
      }).then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.json(); }).then(function (o) {
        if (n !== qN) return;
        o = o || {};
        if (o.error === 'bad_code' && o.code) {
          var c = String(o.code).toUpperCase();
          codes = codes.filter(function (x) { return x !== c; });
          if (tryCode === c) tryCode = '';
          say(codeErr(o), true); return requote();
        }
        if (o.error === 'below_minimum' && tryCode) { tryCode = ''; say(codeErr(o), true); return requote(); }
        if (o.error === 'bad_amount') { quote = null; render(); cfg.onChange(); return; }
        if (tryCode) { codes.push(tryCode); tryCode = ''; }
        quote = o.success ? o : null;
        if (!o.success) say(codeErr(o), true); else { if (note === T.wait) note = ''; render(); }
        cfg.onChange();
      }).catch(function () { if (n === qN) { tryCode = ''; quote = null; say(cfg.errGen, true); cfg.onChange(); } });
    }, 300);
  }
  function apply() {
    var c = String(input.value || '').trim().toUpperCase();
    if (!c) return;
    if (codes.indexOf(c) >= 0) { say(T.dup, true); return; }
    input.value = ''; note = ''; tryCode = c; requote();
  }
  if (on) on.addEventListener('change', function () {
    box.hidden = !on.checked;
    if (on.checked) { try { input.focus(); } catch (e) {} } else if (codes.length || tryCode) { codes = []; tryCode = ''; note = ''; requote(); }
  });
  if (ap) ap.addEventListener('click', apply);
  if (input) input.addEventListener('keydown', function (ev) { if (ev.key === 'Enter') { ev.preventDefault(); apply(); } });
  if (msgEl) msgEl.addEventListener('click', function (ev) {
    var b = ev.target.closest('[data-code-del]');
    if (!b) return;
    var c = b.getAttribute('data-code-del');
    codes = codes.filter(function (x) { return x !== c; }); note = ''; requote();
  });
  return {
    list: function () { return codes.slice(); },
    /** odpověď serveru jen když odpovídá aktuální hodnotě poukazu a tisku */
    quote: function (amount, fee) { return quote && codes.length && Number(quote.amount) === amount && Number(quote.print_fee) === fee ? quote : null; },
    requote: function () { if (codes.length) requote(); },
    drop: function (c, text) { c = String(c || '').toUpperCase(); codes = codes.filter(function (x) { return x !== c; }); say(text || T.bad, true); requote(); }
  };
};
