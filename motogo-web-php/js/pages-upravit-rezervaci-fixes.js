/* ===== MotoGo24 — Upravit rezervaci: opravy z auditu 2026-10-22 (moto rezervace) =====
 * Jádro je minifikované a NEUPRAVUJE se — opravy zvenčí (stejná technika jako guard/status):
 *  B1  probíhající (převzatou) rezervaci nelze stornovat — záložka Storno se u status 'active'
 *      nenabízí (storno běžící výpůjčky rušilo kódy kiosku a vrácení by nešlo dokončit),
 *  B2  po první vratce (payment_status partial_refund / refund_pending) nezmizí úpravy —
 *      server (zkrácení, změny, storno) tyto stavy bere; jen bezplatný posun chce 'paid',
 *  B5  štítek stavu v detailu stejně jako seznam: „Nadcházející“ až do převzetí,
 *  B6  rezervace vydaná předem (DB 'active', začátek zítra) se v Prodloužit/Zkrátit chová jako
 *      probíhající (dřív nabídla změnu začátku, kterou server odmítne: active_start_locked),
 *  B8  kolize s cizí rezervací v den začátku — porovnání datumů jako YYYY-MM-DD,
 *  B12 náhled pro CMS: ukázková data měla neplatný stav 'confirmed' → bez záložek úprav.
 * Výpůjčku výbavy řeší gearbk-view.js (vlastní záložky). Načítá se PŘED status.js.
 */
(function() {
  var MG = window.MG;
  var ER = (MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  var isGear = function(b) { return !!(ER._isGear && ER._isGear(b)); };
  var PART = { partial_refund: 1, refund_pending: 1 };

  // B6 (natrvalo — status.js si tuto verzi bere jako „jádro“ a po seznamu ji vrací)
  var coreDisp = ER._displayStatus;
  ER._displayStatus = function(b) {
    var s = coreDisp.apply(this, arguments);
    return (s === 'upcoming' && b && b.status === 'active') ? 'active' : s;
  };

  // B8
  var coreOv = ER._rangeOverlapsOccupied;
  ER._rangeOverlapsOccupied = function(s, e, occ) {
    var n = function(v) { return ER._normIso(v) || v; };
    return coreOv.call(this, n(s), n(e), (occ || []).map(function(o) {
      return { start_date: n(o.start_date), end_date: n(o.end_date), status: o.status };
    }));
  };

  function listKey(b) {
    if (b.status === 'cancelled' || b.status === 'completed' || b.status === 'active' || b.status === 'pending') return b.status;
    return ER._normIso(b.end_date) < ER._toIsoDate(new Date()) ? 'completed' : 'upcoming';
  }

  var coreDetail = ER._renderDetail;
  ER._renderDetail = function() {
    var b = ER.selectedBooking;
    if (!b || isGear(b)) return coreDetail.apply(this, arguments);
    var realPay = b.payment_status, mapped = !!PART[realPay];
    if (b.status === 'active' && ER.tab === 'cancel') ER.tab = 'detail';
    if (mapped && ER.tab === 'move') ER.tab = 'detail';
    // B2: tab bar a dispatch jádra čtou payment_status synchronně — po dobu vykreslení 'paid'
    if (mapped) b.payment_status = 'paid';
    var r;
    try {
      r = coreDetail.apply(this, arguments);
    } finally {
      if (mapped) b.payment_status = realPay;
    }
    try {
      var nav = document.querySelector('#edit-rez-app .edit-rez-tabs');
      var drop = function(key) {
        var t = nav && nav.querySelector('.edit-rez-tab[data-tab="' + key + '"]');
        if (t) t.remove();
      };
      if (b.status === 'active') drop('cancel'); // B1
      if (mapped) drop('move'); // reschedule_booking_free chce 'paid'
      var chip = document.querySelector('#edit-rez-app .edit-rez-detail-meta .edit-rez-booking-status');
      if (chip && !ER._isMockMode) { // B5
        var k = ER._isPendingUnpaid(b) ? 'pending' : listKey(b);
        chip.className = 'edit-rez-booking-status status-' + k;
        chip.textContent = MG.t('editRez.status.' + k);
      }
    } catch (e) { /* noop */ }
    return r;
  };

  // B12
  var coreMock = ER._enterMockMode;
  ER._enterMockMode = function() {
    var r = coreMock.apply(this, arguments);
    try {
      (ER.bookings || []).forEach(function(b) {
        if (b && b.status === 'confirmed') b.status = /ACTIVE/.test(String(b.id)) ? 'active' : 'reserved';
      });
    } catch (e) { /* noop */ }
    return r;
  };
})();
