/* ===== MotoGo24 — Upravit rezervaci: výpůjčka JEN výbavy (data, ceník, chyby) =====
 * Od 2026-10-23 je výpůjčka výbavy běžná rezervace (bookings.booking_kind='gear', moto_id NULL,
 * pobočka v branch_id, řádky v gear_lines). Zákazník gear řádky přímým SELECTem nevidí (RESTRICTIVE
 * RLS, dokud Velín nezapne gear_rental.app_visible) → seznam doplňuje RPC get_my_gear_bookings()
 * (deduplikace podle id; vidí-li je i select jádra, sloučí se). Tento soubor: _isGear, ceník
 * gear_rental_prices (popisky 8 jazyků, velikosti, přecenění při odebrání kusu), cena/den pro
 * jádrové náhledy (_fallbackDailyRate = gear_per_day), obsazené dny = uzavírky pobočky,
 * texty jádra s „motorkou“ → výbava (jen u gear rezervace), překlad chybových kódů serveru,
 * náhled pro CMS (mock). Vykreslení: gearbk-view.js, záložky Velikosti/Odebrat kus: gearbk-tabs.js.
 */
(function() {
  var MG = window.MG;
  var ER = (MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  var TYPES = ['helmet', 'jacket', 'pants', 'gloves', 'boots'];
  var PAIDISH = ['paid', 'partial_refund', 'refund_pending'];

  ER._isGear = function(b) { return !!b && b.booking_kind === 'gear'; };
  ER._gearIsSS = function(b) { return !!(b && b.branch && b.branch.type === 'samoobslužná'); };
  ER._gearPaid = function(b) { return !!b && PAIDISH.indexOf(b.payment_status) >= 0; };

  // ---- Ceník (veřejně čitelný, jen aktivní řádky) ----
  var pricesP = null;
  ER._gearPriceRows = [];
  ER._gearPricesLoad = function() {
    if (pricesP) return pricesP;
    if (!window.sb || ER._isMockMode) return Promise.resolve(ER._gearPriceRows);
    pricesP = Promise.resolve(window.sb.from('gear_rental_prices')
      .select('key,kind,label,includes,sizes,price_per_day,sort_order,translations')
      .eq('is_active', true).order('sort_order', { ascending: true }))
      .then(function(r) {
        var rows = (r && !r.error && Array.isArray(r.data)) ? r.data : [];
        if (!rows.length) pricesP = null;
        ER._gearPriceRows = rows;
        return rows;
      }).catch(function() { pricesP = null; return []; });
    return pricesP;
  };
  ER._gearRow = function(key) {
    var rows = ER._gearPriceRows || [];
    for (var i = 0; i < rows.length; i++) if (rows[i].key === key) return rows[i];
    return null;
  };
  function lang() { return (window.MOTOGO_CONFIG && window.MOTOGO_CONFIG.LANG) || 'cs'; }
  ER._gearLabel = function(key, fallback) {
    var r = ER._gearRow(key), L = lang();
    var tr = r && r.translations && r.translations[L];
    if (L !== 'cs' && tr && tr.label) return tr.label;
    var k = 'rez.gear.label.' + key, t = MG.t(k);
    if (L !== 'cs' && t !== k) return t;
    return (r && r.label) || fallback || (t !== k ? t : key);
  };
  // Kusy výpůjčky [{key,size}] z naceněných řádků (komplet = jeho kusy), pořadí helma → boty.
  ER._gearItems = function(b) {
    var out = [], seen = {};
    ((b && b.gear_lines) || []).forEach(function(l) {
      var inc = (Array.isArray(l.includes) && l.includes.length) ? l.includes : [l.key];
      inc.forEach(function(k) {
        if (!k || seen[k]) return;
        seen[k] = 1;
        var sz = (l.sizes && l.sizes[k] != null) ? l.sizes[k] : (b[k + '_size'] || null);
        out.push({ key: k, size: sz });
      });
    });
    return out.sort(function(a, c) {
      var x = TYPES.indexOf(a.key), y = TYPES.indexOf(c.key);
      return (x < 0 ? 99 : x) - (y < 0 ? 99 : y);
    });
  };
  // Zrcadlo SQL _gear_rental_quote: komplet, je-li levnější než součet jeho kusů.
  ER._gearQuote = function(keys) {
    var rows = ER._gearPriceRows || [];
    if (!rows.length || !keys.length) return null;
    var price = {}, left = keys.slice(), perDay = 0, lines = [];
    rows.forEach(function(r) { if (r.kind === 'item') price[r.key] = Number(r.price_per_day || 0); });
    for (var i = 0; i < keys.length; i++) if (price[keys[i]] == null) return null;
    rows.filter(function(r) { return r.kind === 'set'; }).sort(function(a, c) {
      return (c.includes || []).length - (a.includes || []).length ||
        Number(a.price_per_day) - Number(c.price_per_day) || (a.key < c.key ? -1 : 1);
    }).forEach(function(s) {
      var inc = s.includes || [];
      if (!inc.every(function(k) { return left.indexOf(k) >= 0; })) return;
      var sum = inc.reduce(function(a, k) { return a + (price[k] || 0); }, 0);
      if (Number(s.price_per_day) >= sum) return;
      lines.push({ key: s.key, price_per_day: Number(s.price_per_day) });
      perDay += Number(s.price_per_day);
      left = left.filter(function(k) { return inc.indexOf(k) < 0; });
    });
    left.forEach(function(k) { lines.push({ key: k, price_per_day: price[k] }); perDay += price[k]; });
    return { per_day: perDay, lines: lines };
  };

  // ---- RPC řádek → tvar rezervace, se kterým pracuje jádro ----
  function fromRpc(r) {
    var g = {
      id: r.id, booking_kind: 'gear', moto_id: null, motorcycles: null,
      user_id: r.user_id || (ER.user && ER.user.id) || null,
      booking_number: r.booking_number || null,
      start_date: r.start_date, end_date: r.end_date,
      pickup_time: r.pickup_time || null, return_time: r.return_time || null,
      status: r.status, payment_status: r.payment_status,
      total_price: Number(r.total != null ? r.total : r.total_price || 0),
      gear_per_day: Number(r.per_day != null ? r.per_day : r.gear_per_day || 0),
      gear_lines: Array.isArray(r.lines) ? r.lines : (r.gear_lines || []),
      discount_amount: Number(r.voucher_amount || r.discount_amount || 0),
      extras_price: 0, delivery_fee: 0, late_pickup_discount_amount: 0,
      created_at: r.created_at || null, picked_up_at: r.picked_up_at || null,
      branch: r.branch || null, branch_id: (r.branch && r.branch.id) || r.branch_id || null,
      docs: r.docs || null, codes_released: !!r.codes_released, can_pay: r.can_pay,
      modification_history: r.modification_history || null,
      original_start_date: r.original_start_date || null, original_end_date: r.original_end_date || null,
      // bez údaje o platbě předpokládej kartu (webová výpůjčka se platí Stripe checkoutem)
      stripe_payment_intent_id: r.stripe_payment_intent_id !== undefined ? r.stripe_payment_intent_id
        : (r.manual_payment ? null : 'stripe'),
      pickup_method: 'branch', return_method: 'branch'
    };
    ER._gearItems(g).forEach(function(it) { g[it.key + '_size'] = it.size; });
    return g;
  }
  ER._gearFromRpc = fromRpc;

  function merge(list) {
    var arr = ER.bookings = (ER.bookings || []).slice();
    list.forEach(function(r) {
      if (!r || !r.id) return;
      var g = fromRpc(r), idx = -1;
      for (var i = 0; i < arr.length; i++) if (arr[i] && arr[i].id === r.id) { idx = i; break; }
      if (idx < 0) { arr.push(g); return; }
      var d = arr[idx];
      Object.keys(d).forEach(function(k) {
        if (d[k] != null && k !== 'motorcycles' && k !== 'booking_kind' && k !== 'moto_id') g[k] = d[k];
      });
      arr[idx] = g;
    });
  }

  var coreLoad = ER._loadBookings;
  ER._loadBookings = async function() {
    var res = await coreLoad.apply(this, arguments);
    if (!ER.user || ER._isMockMode || !window.sb) return res;
    try {
      var r = await window.sb.rpc('get_my_gear_bookings');
      var list = r && !r.error && Array.isArray(r.data) ? r.data : null;
      if (r && r.error) console.warn('[editRez] get_my_gear_bookings', r.error);
      if (list && list.length) {
        await ER._gearPricesLoad();
        merge(list);
      }
    } catch (e) {
      console.warn('[editRez] gear bookings load failed', e);
    }
    return res;
  };

  // Nezaplacenou výpůjčku výbavy doplatit na stránce výbavy (ne /rezervace).
  var coreResume = ER._resumePending;
  ER._resumePending = function(id) {
    var b = (ER.bookings || []).filter(function(x) { return x && x.id === id; })[0];
    if (ER._isGear(b)) { window.location.href = '/pujceni-obleceni?resume=' + encodeURIComponent(id); return; }
    return coreResume.apply(this, arguments);
  };

  // Cena dne pro jádrové náhledy (prodloužení/zkrácení): součet kusů × 1 den.
  var coreRate = ER._fallbackDailyRate;
  ER._fallbackDailyRate = function(b) {
    if (ER._isGear(b) && Number(b.gear_per_day) > 0) return Math.round(Number(b.gear_per_day));
    return coreRate.apply(this, arguments);
  };

  // „Obsazené“ dny gear rezervace = uzavírky její pobočky (sklad hlídá server: out_of_stock).
  var coreOcc = ER._loadOccupied;
  ER._loadOccupied = async function(motoId) {
    var b = ER.selectedBooking;
    if (motoId || !ER._isGear(b)) return coreOcc.apply(this, arguments);
    if (!b.branch_id || !window.sb || ER._isMockMode) return [];
    try {
      var r = await window.sb.from('branch_closures').select('closed_from,closed_to')
        .eq('branch_id', b.branch_id).gte('closed_to', ER._toIsoDate(new Date()));
      return ((r && r.data) || []).map(function(c) {
        return { start_date: ER._normIso(c.closed_from), end_date: ER._normIso(c.closed_to), status: 'closed' };
      });
    } catch (e) { return []; }
  };

  // ---- Texty jádra s motorkou → výbava (jen při otevřené gear rezervaci) ----
  var GEAR_T = {
    'editRez.move.occupiedRange': 'editRez.gearbk.closedRange',
    'editRez.validate.dayOccupied': 'editRez.gearbk.dayClosed',
    'editRez.validate.gapBeforeStart': 'editRez.gearbk.gapClosed',
    'editRez.validate.gapAfterEnd': 'editRez.gearbk.gapClosed',
    'editRez.extend.unavailable': 'editRez.gearbk.unavailable',
    'editRez.cal.legend.occupied': 'editRez.gearbk.legendClosed',
    'editRez.pending.text': 'editRez.gearbk.pendingText',
    'editRez.shorten.helpActiveLong': 'editRez.gearbk.shortenHelpActive',
    'editRez.doc.uploadHelp': 'editRez.gearbk.docsHelp',
    'rez.pickup.selfServiceHint': 'editRez.gearbk.ssTimeHint'
  };
  var prevT = MG.t;
  MG.t = function(k, p) {
    var g = GEAR_T[k];
    if (g && ER._isGear(ER.selectedBooking)) {
      var s = prevT.call(this, g, p);
      if (s !== g) return s;
    }
    return prevT.apply(this, arguments);
  };

  // ---- Chybové kódy serveru pro výbavu ----
  var GEAR_ERR = {
    out_of_stock: 'editRez.gearbk.errStock', branch_closed: 'editRez.gearbk.errClosed',
    bad_size: 'editRez.gearbk.errSize', last_item: 'editRez.gearbk.errLastItem',
    term_started: 'editRez.gearbk.errStarted', gear_no_moto: 'editRez.err.wrongStatus',
    too_long: 'editRez.gearbk.errTooLong', bad_item: 'editRez.err.generic'
  };
  ER._gearErrKey = function(code) { return code && GEAR_ERR[code] ? GEAR_ERR[code] : null; };
  var coreErr = ER._showError;
  ER._showError = function(msg) {
    var m = /^([a-z_]+)(?:\s+—.*)?$/.exec(String(msg || ''));
    if (m && GEAR_ERR[m[1]]) return coreErr.call(this, MG.t(GEAR_ERR[m[1]]));
    return coreErr.apply(this, arguments);
  };

  // ---- Náhled pro CMS (Velín → Texty webu): jedna ukázková výpůjčka výbavy ----
  var coreMock = ER._enterMockMode;
  ER._enterMockMode = function() {
    var r = coreMock.apply(this, arguments);
    try {
      if (!(ER.bookings || []).some(ER._isGear)) {
        var d = new Date(); d.setDate(d.getDate() + 12);
        var s = ER._toIsoDate(d); d.setDate(d.getDate() + 2);
        ER.bookings.push(fromRpc({
          id: 'cms-preview-gear-0001', status: 'reserved', payment_status: 'paid',
          start_date: s, end_date: ER._toIsoDate(d), pickup_time: '10:00:00', total: 1470, per_day: 490,
          created_at: new Date().toISOString(),
          lines: [{ key: 'set_rider', kind: 'set', label: 'Komplet bez bot', includes: ['helmet', 'jacket', 'pants', 'gloves'],
            sizes: { helmet: 'M', jacket: 'L', pants: 'L', gloves: 'L' }, price_per_day: 490, total: 1470 }],
          branch: { id: 'preview-branch', name: 'MotoGo24 Velké Němčice', address: 'Velké Němčice', city: 'Velké Němčice', type: 'samoobslužná' },
          docs: { required: true, ok: false, missing: ['identity'] }
        }));
      }
    } catch (e) { /* noop */ }
    return r;
  };
})();
