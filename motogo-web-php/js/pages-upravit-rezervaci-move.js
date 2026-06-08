// ===== MotoGo24 — Upravit rezervaci: záložka "Posun termínu" (zdarma) =====
// Přidává MG._editRez._renderTabMove + _submitMove.
// Posun = přesun CELÉ rezervace na jiný termín se ZACHOVÁNÍM počtu dní i CENY.
// Zdarma pro všechny nadcházející (reserved + zaplacené) rezervace, kamkoliv,
// kde je motorka volná a nepřekrývá se to s jinou rezervací zákazníka/motorky.
// Backend: RPC reschedule_booking_free → existující trigger trg_send_booking_modified_email
// pošle web_booking_modified / booking_modified mail + aktualizovanou smlouvu.
// UI: reusneme EXISTUJÍCÍ kalendář MG._editRez._renderRangeCalendar (mode 'move'),
// takže je 1:1 stejný jako u Prodloužit/Zkrátit (vč. CSS, obsazených dnů, zámku minulosti).
(function () {
  var ER = (window.MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  ER._renderTabMove = async function () {
    var b = ER.selectedBooking;
    var content = document.getElementById('edit-rez-tab-content');
    if (!b || !content) return;

    var origStart = ER._normIso(b.start_date);
    var origEnd = ER._normIso(b.end_date);
    var lenDays = ER._daysInclusive(origStart, origEnd);
    var dayLbl = (typeof MG._dayLabel === 'function') ? MG._dayLabel(lenDays) : lenDays;

    // MG.tc() = CMS-inline-editable (Velín → Texty webu → Úprava rezervace).
    content.innerHTML =
      '<h3>' + MG.tc('editRez.move.title') + '</h3>' +
      '<p>' + MG.tc('editRez.move.help', { days: dayLbl, start: MG.formatDate(origStart), end: MG.formatDate(origEnd) }) + '</p>' +
      '<div id="edit-rez-move-banner" class="erez-range-banner" style="display:none"></div>' +
      '<div id="edit-rez-move-cal"></div>' +
      '<button type="button" class="btn btngreen" id="edit-rez-move-cta" disabled>' + MG.t('editRez.move.cta') + '</button>';

    var occupied = (await ER._loadOccupied()).map(function (o) {
      return { start_date: ER._normIso(o.start_date), end_date: ER._normIso(o.end_date), status: o.status };
    });

    var banner = document.getElementById('edit-rez-move-banner');
    var cta = document.getElementById('edit-rez-move-cta');
    var cur = { start: origStart, end: origEnd };

    function updateBanner(s, e) {
      banner.className = 'erez-range-banner';
      if (!s || !e || (s === origStart && e === origEnd)) {
        banner.style.display = 'none'; banner.innerHTML = ''; cta.disabled = true; return;
      }
      banner.style.display = 'flex';
      banner.innerHTML =
        '<span>' + MG.formatDate(origStart) + ' – ' + MG.formatDate(origEnd) + '</span>' +
        '<span class="erez-range-arrow">→</span>' +
        '<span>' + MG.formatDate(s) + ' – ' + MG.formatDate(e) + '</span>';
      cta.disabled = false;
    }

    ER._renderRangeCalendar({
      container: document.getElementById('edit-rez-move-cal'),
      mode: 'move',
      isActive: false,
      origStart: origStart,
      origEnd: origEnd,
      newStart: origStart,
      newEnd: origEnd,
      occupied: occupied,
      onChange: function (s, e) { cur.start = s; cur.end = e; updateBanner(s, e); },
      onError: function (msg) {
        banner.className = 'erez-range-banner error';
        banner.style.display = 'flex';
        banner.innerHTML = '<span>⚠️ ' + msg + '</span>';
      }
    });

    cta.addEventListener('click', function () {
      if (!cur.start || !cur.end || (cur.start === origStart && cur.end === origEnd)) return;
      ER._submitMove(cur.start, cur.end);
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
        var code = (res.data && res.data.error) || (res.error && (res.error.message || res.error.code)) || '';
        // Diagnostika do F12 — ať je vidět přesná příčina (RPC error / výjimka).
        console.error('[editRez] move failed', { sent: { p_booking_id: b.id, p_new_start: newStart, p_new_end: newEnd }, code: code, error: res.error, data: res.data });
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
        var key = map[code];
        // Když chybu neznáme, ukaž radši surovou serverovou hlášku (vč. detailu) než „něco se pokazilo".
        var detail = (res.data && res.data.detail) || (res.error && res.error.details) || '';
        ER._showError(key ? MG.t(key) : ((code || MG.t('editRez.err.generic')) + (detail ? ' — ' + detail : '')));
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
