// ===== MotoGo24 — Upravit rezervaci: záložka "Posun termínu" (zdarma) =====
// Samostatný modul přidávající MG._editRez._renderTabMove + _submitMove.
// Posun = přesun CELÉ rezervace na jiný termín se ZACHOVÁNÍM počtu dní a CENY.
// Zdarma pro všechny nadcházející (reserved + zaplacené) rezervace, kamkoliv,
// kde je motorka volná a nepřekrývá se to s jinou rezervací zákazníka/motorky.
// Backend: RPC reschedule_booking_free → existující trigger trg_send_booking_modified_email
// pošle web_booking_modified / booking_modified mail + aktualizovanou smlouvu.
// UI sdílí stejné CSS třídy (.erez-cal-*) jako kalendář prodloužení/zkrácení.
(function () {
  var ER = (window.MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  function iso(y, m, d) {
    return y + '-' + String(m + 1).padStart(2, '0') + '-' + String(d).padStart(2, '0');
  }
  function todayIso() {
    var n = new Date();
    return iso(n.getFullYear(), n.getMonth(), n.getDate());
  }
  // posuň ISO datum o N dní (kladně i záporně)
  function shiftIso(isoStr, days) {
    var p = isoStr.split('-');
    var dt = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
    dt.setDate(dt.getDate() + days);
    return iso(dt.getFullYear(), dt.getMonth(), dt.getDate());
  }
  function csDate(isoStr) {
    if (!isoStr) return '';
    var p = isoStr.split('-');
    return parseInt(p[2], 10) + '.' + parseInt(p[1], 10) + '.' + p[0];
  }

  ER._renderTabMove = async function () {
    var b = ER.selectedBooking;
    var content = document.getElementById('edit-rez-tab-content');
    if (!b || !content) return;

    var origStart = ER._normIso(b.start_date);
    var origEnd = ER._normIso(b.end_date);
    var lenDays = ER._daysInclusive(origStart, origEnd); // počet dní (inclusive)

    // MG.tc() = CMS-inline-editable (Velín → Texty webu → Úprava rezervace).
    content.innerHTML =
      '<h3>' + MG.tc('editRez.move.title') + '</h3>' +
      '<p>' + MG.tc('editRez.move.help', { days: ER._dayLabel(lenDays), start: MG.formatDate(origStart), end: MG.formatDate(origEnd) }) + '</p>' +
      '<div id="edit-rez-move-banner" class="erez-range-banner" style="display:none"></div>' +
      '<div id="edit-rez-move-cal"></div>' +
      '<div id="edit-rez-move-summary" class="edit-rez-price-summary" aria-live="polite"></div>' +
      '<button type="button" class="btn btngreen" id="edit-rez-move-cta" disabled>' + MG.t('editRez.move.cta') + '</button>';

    var occupied = (await ER._loadOccupied()).map(function (o) {
      return { start_date: ER._normIso(o.start_date), end_date: ER._normIso(o.end_date), status: o.status };
    });

    var state = { newStart: null, newEnd: null };
    var calBox = document.getElementById('edit-rez-move-cal');
    var banner = document.getElementById('edit-rez-move-banner');
    var cta = document.getElementById('edit-rez-move-cta');
    var pivot = { y: 0, m: 0 };
    (function () { var p = origStart.split('-'); pivot.y = Number(p[0]); pivot.m = Number(p[1]) - 1; })();

    var months = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map(function (n) { return MG.t('editRez.cal.month.' + n); });
    var dows = [1, 2, 3, 4, 5, 6, 7].map(function (n) { return MG.t('editRez.cal.dow.' + n); });

    function inOrig(ds) { return ds >= origStart && ds <= origEnd; }
    function inNew(ds) { return state.newStart && state.newEnd && ds >= state.newStart && ds <= state.newEnd; }
    function isOcc(ds) { return occupied.some(function (o) { return ds >= o.start_date && ds <= o.end_date; }); }
    function isPast(ds) { return ds < todayIso(); }
    // celý rozsah volný (occupied už neobsahuje vlastní rezervaci)
    function rangeFree(from, to) {
      var d = from;
      while (d <= to) {
        if (isOcc(d)) return false;
        d = shiftIso(d, 1);
      }
      return true;
    }

    function dayClasses(ds) {
      var c = ['erez-cal-day'];
      if (isPast(ds)) { c.push('past'); return c; }
      if (isOcc(ds) && !inOrig(ds)) { c.push('occ'); return c; }
      if (inNew(ds)) {
        c.push('extension');
        if (ds === state.newStart) c.push('extension-start');
        if (ds === state.newEnd) c.push('extension-end');
        return c;
      }
      if (inOrig(ds)) { c.push('orig'); return c; }
      c.push('free');
      return c;
    }

    function updateBanner() {
      banner.className = 'erez-range-banner';
      if (!state.newStart || !state.newEnd || (state.newStart === origStart && state.newEnd === origEnd)) {
        banner.style.display = 'none'; banner.innerHTML = '';
        cta.disabled = true;
        return;
      }
      banner.style.display = 'flex';
      banner.innerHTML =
        '<span class="erez-range-old">' + MG.formatDate(origStart) + ' – ' + MG.formatDate(origEnd) + '</span>' +
        '<span class="erez-range-arrow">→</span>' +
        '<span class="erez-range-new">' + MG.formatDate(state.newStart) + ' – ' + MG.formatDate(state.newEnd) + '</span>';
      cta.disabled = false;
    }

    function onDayTap(ds) {
      if (isPast(ds)) { ER._showError(MG.t('editRez.validate.pastDate')); return; }
      if (isOcc(ds) && !inOrig(ds)) { ER._showError(MG.t('editRez.validate.dayOccupied')); return; }
      // klik na nový začátek znovu → reset
      if (state.newStart && ds === state.newStart) { state.newStart = null; state.newEnd = null; render(); return; }
      var ns = ds;
      var ne = shiftIso(ns, lenDays - 1);
      if (!rangeFree(ns, ne)) { ER._showError(MG.t('editRez.move.occupiedRange')); return; }
      state.newStart = ns; state.newEnd = ne;
      render();
    }

    function render() {
      var y = pivot.y, m = pivot.m;
      var first = new Date(y, m, 1);
      var last = new Date(y, m + 1, 0);
      var offset = (first.getDay() + 6) % 7;
      var tIso = todayIso();
      var html = '<div class="erez-cal-wrap"><div class="erez-cal-nav">' +
        '<button type="button" class="erez-cal-navbtn" data-prev aria-label="' + MG.t('editRez.cal.prev') + '">‹</button>' +
        '<span class="erez-cal-navtitle">' + months[m] + ' ' + y + '</span>' +
        '<button type="button" class="erez-cal-navbtn" data-next aria-label="' + MG.t('editRez.cal.next') + '">›</button></div>' +
        '<div class="erez-cal-single"><div class="erez-cal-month"><div class="erez-cal-mhead">' + months[m] + ' ' + y + '</div><div class="erez-cal-grid">';
      dows.forEach(function (dn) { html += '<div class="erez-cal-dn">' + dn + '</div>'; });
      for (var e = 0; e < offset; e++) html += '<div class="erez-cal-empty"></div>';
      for (var dd = 1; dd <= last.getDate(); dd++) {
        var ds = iso(y, m, dd);
        var cls = dayClasses(ds);
        if (ds === tIso) cls.push('today');
        html += '<div class="' + cls.join(' ') + '" data-ds="' + ds + '"><span>' + dd + '</span></div>';
      }
      html += '</div></div></div>' +
        '<div class="erez-cal-legend">' +
        '<span><i class="dot dot-free"></i> ' + MG.t('editRez.cal.legend.free') + '</span>' +
        '<span><i class="dot dot-orig"></i> ' + MG.t('editRez.cal.legend.thisBooking') + '</span>' +
        '<span><i class="dot dot-extension"></i> ' + MG.tc('editRez.move.legendNew') + '</span>' +
        '<span><i class="dot dot-occ"></i> ' + MG.t('editRez.cal.legend.occupied') + '</span></div></div>';
      calBox.innerHTML = html;
      calBox.querySelector('[data-prev]').addEventListener('click', function () {
        pivot.m--; if (pivot.m < 0) { pivot.m = 11; pivot.y--; } render();
      });
      calBox.querySelector('[data-next]').addEventListener('click', function () {
        pivot.m++; if (pivot.m > 11) { pivot.m = 0; pivot.y++; } render();
      });
      calBox.querySelectorAll('.erez-cal-day').forEach(function (el) {
        el.addEventListener('click', function () { onDayTap(el.getAttribute('data-ds')); });
      });
      updateBanner();
    }

    render();

    cta.addEventListener('click', function () {
      if (!state.newStart || !state.newEnd) return;
      if (state.newStart === origStart && state.newEnd === origEnd) return;
      ER._submitMove(state.newStart, state.newEnd);
    });
  };

  ER._submitMove = async function (newStart, newEnd) {
    if (ER.busy) return;
    var b = ER.selectedBooking;
    var cta = document.getElementById('edit-rez-move-cta');
    var orig = cta ? cta.textContent : '';
    if (cta) { cta.disabled = true; cta.textContent = MG.t('editRez.move.confirming'); }
    ER._setBusy(true);
    try {
      var res = await window.sb.rpc('reschedule_booking_free', {
        p_booking_id: b.id,
        p_new_start: newStart,
        p_new_end: newEnd,
        p_source: 'web_customer'
      });
      if (res.error || !res.data || res.data.success === false) {
        var code = (res.data && res.data.error) || (res.error && res.error.message) || '';
        var map = {
          not_found: 'editRez.err.notFound',
          unauthenticated: 'editRez.login.error',
          wrong_status: 'editRez.err.wrongStatus',
          not_paid: 'editRez.err.notPaid',
          length_mismatch: 'editRez.move.errLength',
          past_date: 'editRez.validate.pastDate',
          no_change: 'editRez.move.errNoChange',
          moto_overlap: 'editRez.move.occupiedRange',
          customer_overlap: 'editRez.move.errCustomerOverlap'
        };
        ER._showError(MG.t(map[code] || 'editRez.err.generic'));
        return;
      }
      var msg = MG.t('editRez.move.success', { start: MG.formatDate(newStart), end: MG.formatDate(newEnd) });
      var content = document.getElementById('edit-rez-tab-content');
      if (content) {
        content.innerHTML = '<div class="edit-rez-success-box"><h3>✓</h3><p>' + msg + '</p>' +
          '<button type="button" class="btn btngreen-small" id="edit-rez-move-back">' + MG.t('editRez.list.title') + '</button></div>';
        var back = document.getElementById('edit-rez-move-back');
        if (back) back.addEventListener('click', async function () {
          ER.selectedBooking = null;
          await ER._loadBookings();
          ER._goto('list');
        });
      }
    } catch (e) {
      console.error('[editRez] move exception', e);
      ER._showError(MG.t('editRez.err.generic'));
    } finally {
      ER._setBusy(false);
      if (cta) { cta.disabled = false; cta.textContent = orig; }
    }
  };
})();
