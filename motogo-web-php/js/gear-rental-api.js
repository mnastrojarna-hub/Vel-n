/* MotoGo24 — Půjčení výbavy: společné jádro js/gear-rental*.js (2026-10-23, DESIGN-GEAR §3.5).
   window.MGGR = konfigurace stránky (#gr-data), texty, formátování a volání backendu:
   RPC přes PostgREST (JWT přihlášeného zákazníka, jinak anon klíč), edge funkce, start platby.
   Supabase SDK (≈160 kB) se načte AŽ když je potřeba — přihlášení, nebo už uložená session
   (pak RPC nese JWT a create_web_gear_booking rezervaci přiřadí přihlášenému účtu).
   Načítá se před gear-ss-cap.js (ten potřebuje window.MG). */
(function () {
  var w = window, d = document;
  w.MG = w.MG || {};
  var el = d.getElementById('gr-data'), K = w.MGKC;
  if (!el || !K) return;
  var C;
  try { C = JSON.parse(el.textContent); } catch (e) { return; }
  var T = C.t;
  var G = w.MGGR = { C: C, T: T, K: K, esc: K.esc, tpl: K.tpl };
  G.q = function (s, root) { return (root || d).querySelector(s); };
  G.money = function (v) { return K.money(C.cur, v); };
  G.czk = function (v) { return K.money({ code: 'CZK', rate: 1, dec: 0, sym: 'Kč' }, v); };
  G.num = function (v) { var n = Number(v); return isFinite(n) ? n : 0; };
  G.days = function (n) { return K.tpl(n === 1 ? T.days_one : (n >= 2 && n <= 4 ? T.days_few : T.days_many), { n: n }); };
  G.isId = function (s) { return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(s || '')); };
  G.fmt = function (iso, o) {
    try {
      var p = { timeZone: 'UTC' };
      for (var k in o) p[k] = o[k];
      return new Intl.DateTimeFormat(C.lang, p).format(new Date(K.ms(String(iso).slice(0, 10))));
    } catch (e) { return String(iso || ''); }
  };
  G.period = function (a, b) {
    a = String(a || '').slice(0, 10); b = String(b || a).slice(0, 10);
    var full = { day: 'numeric', month: 'numeric', year: 'numeric' };
    return b && b !== a ? G.fmt(a, { day: 'numeric', month: 'numeric' }) + ' – ' + G.fmt(b, full) : G.fmt(a, full);
  };
  // Odkaz na tuto stránku s parametry (+ ?lang= z aktuální adresy, jako vrací Stripe)
  G.url = function (qs) {
    var lp = new URLSearchParams(location.search).get('lang');
    return C.page + '?' + qs + (lp ? '&lang=' + encodeURIComponent(lp) : '');
  };

  // ---- Supabase SDK na vyžádání ----
  G.hasStored = function () {
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (k && /^sb-.+-auth-token$/.test(k) && localStorage.getItem(k)) return true;
      }
    } catch (e) {}
    return false;
  };
  function addScript(src) {
    return new Promise(function (ok, ko) {
      var s = d.createElement('script');
      s.src = src; s.onload = ok; s.onerror = ko;
      d.head.appendChild(s);
    });
  }
  G.loadSb = function () {
    if (w.sb && w.sb.auth) return Promise.resolve(w.sb);
    if (G._sbp) return G._sbp;
    var mc = w.MOTOGO_CONFIG = w.MOTOGO_CONFIG || {};
    mc.SUPABASE_URL = mc.SUPABASE_URL || C.sb.url;
    mc.SUPABASE_ANON_KEY = mc.SUPABASE_ANON_KEY || C.sb.key;
    G._sbp = (w.supabase && w.supabase.createClient ? Promise.resolve() : addScript(C.sdk[0]))
      .then(function () { return w.sb ? null : addScript(C.sdk[1]); })
      .then(function () { if (!(w.sb && w.sb.auth)) throw new Error('sdk'); return w.sb; })
      .catch(function (e) { G._sbp = null; throw e; });
    return G._sbp;
  };
  // Platná session (SDK ji případně obnoví); bez uložené session se SDK vůbec nenačítá
  G.session = function () {
    if (!(w.sb && w.sb.auth) && !G.hasStored()) return Promise.resolve(null);
    return G.loadSb().then(function (sb) { return sb.auth.getSession(); })
      .then(function (r) { return (r && r.data && r.data.session) || null; })
      .catch(function () { return null; });
  };

  // ---- backend ----
  // RPC: vrací JSON odpověď funkce; HTTP chyba = {error:'rpc_error', code, message}
  // (PGRST202 = funkce na serveru ještě není → volající padá na původní chování).
  G.rpc = function (fn, args) {
    return G.session().then(function (s) {
      return fetch(C.sb.url + '/rest/v1/rpc/' + fn, {
        method: 'POST',
        headers: { apikey: C.sb.key, Authorization: 'Bearer ' + ((s && s.access_token) || C.sb.key), 'Content-Type': 'application/json' },
        body: JSON.stringify(args || {})
      });
    }).then(function (r) {
      return r.text().then(function (t) {
        var j = null;
        try { j = t ? JSON.parse(t) : null; } catch (e) {}
        if (r.ok) return j;
        return { error: 'rpc_error', http: r.status, code: j && j.code, message: (j && (j.message || j.error)) || '' };
      });
    });
  };
  // Edge funkce jako motorkový web: host jen apikey, přihlášený navíc svůj JWT (auth=true)
  G.edge = function (fn, body, auth) {
    return (auth ? G.session() : Promise.resolve(null)).then(function (s) {
      var h = { apikey: C.sb.key, 'Content-Type': 'application/json' };
      if (s && s.access_token) h.Authorization = 'Bearer ' + s.access_token;
      return fetch(C.sb.url + '/functions/v1/' + fn, { method: 'POST', headers: h, body: JSON.stringify(body || {}) });
    }).then(function (r) {
      return r.json().catch(function () { return null; }).then(function (j) { j = j || {}; j._status = r.status; return j; });
    });
  };
  // Start platby rezervace (jako motorkový web): Stripe Checkout; návrat řeší process-payment
  // (gear → ?booking_id=&session_id= / ?resume=&payfail=1). Výsledek {ok} nebo {code, msg}.
  G.pay = function (bookingId, amount) {
    return G.edge('process-payment', {
      booking_id: bookingId, amount: G.num(amount), type: 'booking', source: 'web', mode: 'checkout',
      origin: location.origin, locale: C.lang
    }).then(function (p) {
      var url = p && (p.checkout_url || p.url);
      if (url) {
        try { history.replaceState(null, '', G.url('resume=' + encodeURIComponent(bookingId))); } catch (e) {}
        location.href = url;
        return { ok: true };
      }
      return { ok: false, code: (p && p.code) || '', msg: (p && p.error) || '' };
    }).catch(function () { return { ok: false, code: 'network', msg: '' }; });
  };
  G.payMsg = function (r) {
    if (r.code === 'payment_in_progress') return T.err_pay_busy;
    if (r.code === 'below_minimum') return T.err_min;
    return C.lang === 'cs' && r.msg && typeof r.msg === 'string' ? r.msg : T.err_pay;
  };
  // Název kusu uvnitř kompletu malým písmenem („helma M“) — němčina píše podstatná jména velkým
  G.lc = function (s) { return C.lang === 'de' ? String(s || '') : String(s || '').toLowerCase(); };
  // Seznam „helma M, bunda L“ z quote řádků / položek {key,size}
  G.itemsLabel = function (list) {
    return (list || []).map(function (it) {
      var p = G.by && G.by[it.key];
      return (p ? p.label : String(it.key || '')) + (it.size ? ' ' + it.size : '');
    }).join(', ');
  };
})();
