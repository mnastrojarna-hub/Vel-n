/* MotoGo24 — kalkulačka ceny (landing v2, pages/katalog-calc.php): jádro bez DOM.
   Cena = MG.calcPriceBreakdown (js/api.js): součet price_<den> (|| price_weekday) za každý den
   termínu včetně krajních; sleva za vyzvednutí od 12:00 = MG._latePickupDiscount
   (js/pages-rezervace-pricing.js): round(50 % ceny 1. dne) při 2+ dnech. Obsazenost
   = MG._rezBookedMap: pending mladší 4 h „čeká“, vše ostatní (rezervace, servis,
   zavřená pobočka) obsazeno. Data jako 'YYYY-MM-DD' počítáme v UTC (bez posunů DST). */
(function (w) {
  var K = w.MGKC = w.MGKC || {};
  var DAY = 864e5;
  K.ms = function (iso) { var p = String(iso).split('-'); return Date.UTC(+p[0], +p[1] - 1, +p[2]); };
  K.iso = function (ms) { return new Date(ms).toISOString().slice(0, 10); };
  K.add = function (iso, n) { return K.iso(K.ms(iso) + n * DAY); };
  K.dow = function (iso) { return new Date(K.ms(iso)).getUTCDay(); };
  K.count = function (a, b) { return Math.round((K.ms(b) - K.ms(a)) / DAY) + 1; };

  // Dnešek v Praze (rezervace bere UTC datum — Praha je vždy stejný nebo pozdější den,
  // takže kalkulačka nikdy nenabídne den, který by rezervace odmítla)
  K.today = function () {
    try {
      var q = {};
      new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Prague', year: 'numeric', month: '2-digit', day: '2-digit' })
        .formatToParts(new Date()).forEach(function (x) { q[x.type] = x.value; });
      if (q.year && q.month && q.day) return q.year + '-' + q.month + '-' + q.day;
    } catch (e) {}
    return new Date().toISOString().slice(0, 10);
  };

  K.breakdown = function (m, s, e) {
    var days = [], total = 0;
    if (!m || !s || !e || s > e) return { total: 0, days: days };
    for (var x = s, i = 0; x <= e && i < 400; x = K.add(x, 1), i++) {
      var dw = K.dow(x), p = Number(m.p[dw]) || 0;
      days.push({ iso: x, dow: dw, price: p });
      total += p;
    }
    return { total: total, days: days };
  };
  K.late = function (bd) { return bd && bd.days.length >= 2 ? Math.round(bd.days[0].price * 0.5) : 0; };

  // Řádky z RPC get_moto_booked_dates → { 'YYYY-MM-DD': 'busy' | 'pending' } (jen od dneška, max ~2 roky)
  K.bookedMap = function (rows, today) {
    var map = {}, now = Date.now(), last = K.add(today, 760);
    (rows || []).forEach(function (r) {
      if (!r || !r.start_date || !r.end_date) return;
      var s = String(r.start_date).slice(0, 10), e = String(r.end_date).slice(0, 10);
      var c = r.created_at ? Date.parse(r.created_at) : 0;
      var st = r.status === 'pending' && c && now - c < 144e5 ? 'pending' : 'busy';
      if (s < today) s = today;
      if (e > last) e = last;
      for (var x = s; x <= e; x = K.add(x, 1)) if (map[x] !== 'busy') map[x] = st;
    });
    return map;
  };

  K.fetchBooked = function (sb, id, today) {
    return fetch(sb.url + '/rest/v1/rpc/get_moto_booked_dates', {
      method: 'POST',
      headers: { apikey: sb.key, Authorization: 'Bearer ' + sb.key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_moto_id: id })
    }).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    }).then(function (rows) { return K.bookedMap(Array.isArray(rows) ? rows : [], today); });
  };

  // Formát jako MG.formatPrice: převod z Kč kurzem (Kč za 1 jednotku), cs-CZ, desetinná místa dle měny
  K.money = function (cur, czk, dec) {
    var v = cur.code === 'CZK' ? Number(czk) : Number(czk) / cur.rate;
    var n = dec === undefined ? cur.dec : dec;
    return v.toLocaleString('cs-CZ', { minimumFractionDigits: n, maximumFractionDigits: n }) + ' ' + cur.sym;
  };
  // Krátká cena do buňky kalendáře (bez měny, celé číslo)
  K.short = function (cur, czk) {
    var v = cur.code === 'CZK' ? Number(czk) : Number(czk) / cur.rate;
    return Math.round(v).toLocaleString('cs-CZ');
  };
  K.esc = function (s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; });
  };
  K.tpl = function (s, p) {
    s = String(s || '');
    for (var k in p) if (Object.prototype.hasOwnProperty.call(p, k)) s = s.split('{' + k + '}').join(p[k]);
    return s;
  };
})(window);
