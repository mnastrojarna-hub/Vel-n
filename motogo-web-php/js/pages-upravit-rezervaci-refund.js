/* ===== MotoGo24 — Upravit rezervaci: jednotné pravidlo vratky (storno i zkrácení) =====
 * Rozhodnutí majitele 2026-10-22 (§1.11, platí pro VŠECHNY rezervace, web = server = AI = appka):
 * pásmo vratky se počítá od TEĎ do AKTUÁLNÍHO začátku rezervace (před změnou) v den a čas
 * vyzvednutí podle Prahy — ≥ 168 h → 100 %, ≥ 48 h → 50 %, jinak 0 % (u zkrácení z ceny
 * odebraných dní, u storna z celé ceny). Strop po posunu začátku (_storno_cap_after_move)
 * zůstává. Dřív web počítal zkrácení konce k NOVÉMU KONCI a půlnoc UTC (rozpor s VOP i appkou).
 * Jádro je minifikované a NEUPRAVUJE se — přetěžujeme zvenčí:
 *   _refundPercentFor(b)  — druhý parametr (nový konec/začátek) se ignoruje,
 *   _refundNet(b, gross)  — zrcadlo _apply_discount_variant_b (sleva se vrací poměrně),
 *   _refundZeroText(b)    — důvod nulové vratky (méně než 48 h / rezervace běží / strop po posunu),
 *   _stornoBoxHtml        — + věta, k čemu se lhůty počítají a že platí i pro zkrácení,
 *   záložky Zkrátit a Storno — pravidlo a upozornění na strop po posunu (jen když platí).
 * Načítá se PŘED guard.js (pages/upravit-rezervaci.php) — guard volá tyto helpery dynamicky.
 */
(function() {
  var MG = window.MG;
  var ER = (MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  function hm(b) {
    // stejně jako server: COALESCE(LEAST(refund_pickup_time, pickup_time), '09:00') — pásmo k nejdřívějšímu
    // času vyzvednutí pro daný den začátku (pozdější posun času vratku nezvýší, 20261023e)
    var p = (b && b.pickup_time) ? String(b.pickup_time).slice(0, 5) : '';
    var r = (b && b.refund_pickup_time) ? String(b.refund_pickup_time).slice(0, 5) : '';
    var t = p && r ? (r < p ? r : p) : (p || r);
    return t || '09:00';
  }

  var fmt = null;
  try {
    fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Europe/Prague', hourCycle: 'h23', year: 'numeric', month: '2-digit',
      day: '2-digit', hour: '2-digit', minute: '2-digit'
    });
  } catch (e) { fmt = null; }

  // posun Prahy proti UTC (min) v okamžiku ts
  function pragueOffset(ts) {
    if (!fmt) return -new Date(ts).getTimezoneOffset();
    var q = {};
    fmt.formatToParts(new Date(ts)).forEach(function(x) { q[x.type] = x.value; });
    var asUtc = Date.UTC(+q.year, +q.month - 1, +q.day, (+q.hour) % 24, +q.minute);
    return Math.round((asUtc - ts) / 60000);
  }

  // Pražský den + čas → epoch ms
  ER._pragueTs = function(iso, time) {
    var p = String(iso || '').split('-'), t = String(time || '00:00').split(':');
    if (p.length !== 3) return NaN;
    var guess = Date.UTC(+p[0], +p[1] - 1, +p[2], +t[0] || 0, +t[1] || 0);
    var ts = guess - pragueOffset(guess) * 60000;
    var off2 = pragueOffset(ts);
    return guess - off2 * 60000;
  };

  ER._refundRefTs = function(b) {
    return ER._pragueTs(ER._normIso(b && b.start_date), hm(b));
  };

  ER._refundTier = function(b) {
    var h = (ER._refundRefTs(b) - Date.now()) / 36e5;
    if (!isFinite(h)) return 0;
    return h >= 168 ? 100 : h >= 48 ? 50 : 0;
  };

  ER._refundPercentFor = function(b) {
    return Math.min(ER._refundTier(b), ER._stornoCapAfterMove(b));
  };

  // Vratka po slevě (varianta B): nová sleva = nová hrubá × stará sleva / stará hrubá.
  ER._refundNet = function(b, gross) {
    var g = Math.max(0, Math.round(Number(gross) || 0));
    var total = Number(b && b.total_price || 0), disc = Math.max(0, Number(b && b.discount_amount || 0));
    if (!g || !(disc > 0)) return g;
    var og = total + disc, ng = Math.max(0, og - g);
    var nd = og > 0 ? Math.round(ng * disc / og) : 0;
    return Math.max(0, Math.round(total - Math.max(0, ng - nd)));
  };

  // Důvod nulové vratky (věta bez částky) — u zkrácení i storna.
  ER._refundZeroReason = function(b) {
    if (ER._refundTier(b) > 0 && ER._stornoCapAfterMove(b) === 0) return MG.t('editRez.refund.whyCap');
    if (ER._refundRefTs(b) <= Date.now()) return MG.t('editRez.refund.whyStarted');
    return MG.t('editRez.refund.whyLate');
  };

  ER._refundZeroText = function(b) {
    return MG.formatPrice(0) + ' — ' + ER._refundZeroReason(b) + ' ' + MG.t('editRez.refund.shortenAnyway');
  };

  function whenText(b) {
    var iso = ER._normIso(b.start_date), t = hm(b);
    return MG.formatDate(iso) + (t === '00:01' ? '' : ' ' + t);
  }

  ER._refundCapHtml = function(b) {
    var cap = ER._stornoCapAfterMove(b);
    if (cap >= 100) return '';
    return '<p class="erez-refund-note erez-refund-cap">' + MG.t(cap === 0 ? 'editRez.refund.capNote0' : 'editRez.refund.capNote50') + '</p>';
  };

  ER._refundRuleHtml = function(b) {
    var started = ER._refundRefTs(b) <= Date.now() || 'active' === ER._displayStatus(b);
    var rule = started ? MG.t('editRez.refund.ruleActive') : MG.t('editRez.refund.ruleUpcoming', { when: whenText(b) });
    return '<p class="erez-refund-note">' + rule + '</p>' + (started ? '' : ER._refundCapHtml(b));
  };

  // Nulová vratka v jádře (první vykreslení náhledu) hned se správným důvodem.
  var coreT = MG.t;
  MG.t = function(k, p) {
    if (k === 'editRez.shorten.refundZero' && ER.selectedBooking) return ER._refundZeroText(ER.selectedBooking);
    var s = coreT.apply(this, arguments);
    // CMS hodnoty „{amount} Kč" + MG.formatPrice (už s měnou) = „1 500 Kč Kč"
    if (typeof s === 'string' && /^editRez\.(cancel|shorten)\.success$|^editRez\.change\.successWithRefund$/.test(k)) {
      s = s.replace(/(Kč|€|EUR|CZK)\s+Kč/g, '$1');
    }
    return s;
  };

  var coreBox = ER._stornoBoxHtml;
  ER._stornoBoxHtml = function() {
    var h = coreBox.apply(this, arguments);
    var note = '<p class="edit-rez-storno-note erez-refund-boxnote">' + MG.t('editRez.refund.boxNote') + '</p>';
    return h.replace('</aside>', note + '</aside>');
  };

  var coreShorten = ER._renderTabShorten;
  ER._renderTabShorten = function() {
    var r = coreShorten.apply(this, arguments);
    try {
      var b = ER.selectedBooking, c = document.getElementById('edit-rez-tab-content');
      var help = c && c.querySelector('h3 + p');
      if (b && help && !c.querySelector('.erez-refund-note')) help.insertAdjacentHTML('afterend', ER._refundRuleHtml(b));
    } catch (e) { /* noop */ }
    return r;
  };

  var coreCancel = ER._renderTabCancel;
  ER._renderTabCancel = function() {
    var r = coreCancel.apply(this, arguments);
    try {
      var b = ER.selectedBooking, c = document.getElementById('edit-rez-tab-content');
      var line = c && c.querySelector('.edit-rez-refund-line');
      if (b && line) {
        var extra = ER._refundPercentFor(b) === 0 ? '<p class="erez-refund-note">' + ER._refundZeroReason(b) + '</p>' : ER._refundCapHtml(b);
        if (extra) line.insertAdjacentHTML('afterend', extra);
      }
    } catch (e) { /* noop */ }
    return r;
  };
})();
