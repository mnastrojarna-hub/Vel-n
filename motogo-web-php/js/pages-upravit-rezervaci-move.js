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
      // Po posunu drž AKTUÁLNÍ stav rezervace — ostatní záložky (prodloužit,
      // čas vyzvednutí, motorka) berou datumy/cenu ze selectedBooking a bez
      // obnovení by naceňovaly změnu proti starému termínu.
      try {
        await ER._loadBookings();
        var fresh = (ER.bookings || []).filter(function (x) { return x && x.id === b.id; })[0];
        if (fresh) { ER.selectedBooking = fresh; ER.selectedMoto = fresh.motorcycles || ER.selectedMoto; }
      } catch (e) { /* best-effort */ }
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

  // ---- Záložka „Posunout termín" i v DEN vyzvednutí (2026-09-20) ----
  // Jádro (minifikované) ukazuje tab jen při _displayStatus(b)==='upcoming', což se
  // počítá z DATUMŮ — v den začátku termínu tedy záložka zmizela, přestože motorka
  // ještě nebyla převzatá a server (reschedule_booking_free) posun normálně pustí.
  // Rozhoduje PŘEVZETÍ (status zůstává 'reserved', dokud zákazník nezadá kód do boxu
  // / obsluha nepodepíše protokol), ne kalendář. Doplňujeme tab zvenčí stejnou
  // technikou jako swap — bez zásahu do jádra.
  var TAB = 'move';

  function todayIso() {
    var d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }

  function shouldInject() {
    var b = ER.selectedBooking;
    if (!b || b.status !== 'reserved' || b.payment_status !== 'paid') return false;
    var start = ER._normIso(b.start_date);
    // Posun zdarma jen dokud termín nezačal (den začátku včetně) — po něm se
    // nevyzvednutá rezervace řeší stornem dle podmínek (parita se serverem).
    if (start < todayIso()) return false;
    // Jádro tab vykresluje samo u termínů začínajících v budoucnu — pak neduplikuj.
    return start === todayIso();
  }

  function injectTab() {
    if (!shouldInject()) return;
    var nav = document.querySelector('#edit-rez-app .edit-rez-tabs');
    if (!nav) return;
    if (nav.querySelector('.edit-rez-tab[data-tab="' + TAB + '"]')) return;

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'edit-rez-tab' + (ER.tab === TAB ? ' active' : '');
    btn.setAttribute('data-tab', TAB);
    btn.textContent = MG.t('editRez.tab.move');

    var detailBtn = nav.querySelector('.edit-rez-tab[data-tab="detail"]');
    if (detailBtn) nav.insertBefore(btn, detailBtn.nextSibling);
    else nav.insertBefore(btn, nav.firstChild);

    btn.addEventListener('click', function () {
      ER.tab = TAB;
      nav.querySelectorAll('.edit-rez-tab').forEach(function (t) { t.classList.remove('active'); });
      btn.classList.add('active');
      ER._renderTabMove();
    });
  }

  function startObserver() {
    var app = document.getElementById('edit-rez-app');
    if (!app) { setTimeout(startObserver, 200); return; }
    new MutationObserver(function () { injectTab(); }).observe(app, { childList: true, subtree: true });
    injectTab();
  }

  startObserver();
})();
