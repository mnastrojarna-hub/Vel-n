/* MotoGo24 — katalog v2: otevírání panelů (bottom sheet na mobilu, rozbalovací panel / popover
   na desktopu). Esc a klik mimo zavře, na mobilu modální (focus trap, zámek scrollu), fokus se
   vrací na tlačítko. Používá js/landing-catalog.js (filtry) a js/landing-catalog-dates.js (termín). */
(function (w) {
  var d = document, F = w.MGKF = w.MGKF || {};
  var mq = w.matchMedia ? w.matchMedia('(min-width: 900px)') : null;
  var cur = null, opener = null, scrim = null, bar = null;
  F.rm = !!(w.matchMedia && w.matchMedia('(prefers-reduced-motion: reduce)').matches);
  F.isDesk = function () { return !!(mq && mq.matches); };

  function focusables(el) {
    return Array.prototype.filter.call(el.querySelectorAll('a[href],button:not([disabled]),input:not([disabled]):not([type=hidden]),select,textarea,[tabindex]:not([tabindex="-1"])'), function (x) {
      return x.offsetWidth > 0 || x.offsetHeight > 0 || x === d.activeElement;
    });
  }
  F.initSheets = function (barEl) {
    bar = barEl;
    scrim = d.createElement('div');
    scrim.className = 'kf-scrim';
    scrim.setAttribute('aria-hidden', 'true');
    bar.appendChild(scrim);
    scrim.addEventListener('click', function () { F.closeSheet(); });
    d.addEventListener('keydown', function (e) {
      if (!cur) return;
      if (e.key === 'Escape') { e.preventDefault(); F.closeSheet(); return; }
      if (e.key !== 'Tab' || F.isDesk()) return;
      var f = focusables(cur);
      if (!f.length) return;
      var a = f[0], z = f[f.length - 1];
      if (e.shiftKey && (d.activeElement === a || !cur.contains(d.activeElement))) { e.preventDefault(); z.focus(); }
      else if (!e.shiftKey && (d.activeElement === z || !cur.contains(d.activeElement))) { e.preventDefault(); a.focus(); }
    });
    // Desktop: klik mimo panel i lištu zavře (scrim je průhledný)
    if (mq && mq.addEventListener) mq.addEventListener('change', function () { if (cur) F.closeSheet(true); });
  };
  F.openSheet = function (el, btn) {
    if (cur === el) return;
    if (cur) F.closeSheet(true);
    cur = el; opener = btn || null;
    el.hidden = false;
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', F.isDesk() ? 'false' : 'true');
    void el.offsetWidth; // start přechodu po zrušení hidden
    el.classList.add('is-open');
    if (opener) opener.setAttribute('aria-expanded', 'true');
    bar.classList.add('is-raised');
    scrim.classList.add('is-on');
    d.documentElement.classList.add('kf-sheet-open');
    if (!F.isDesk()) d.documentElement.classList.add('kf-lock');
    var t = el.querySelector('[data-kf-focus]') || focusables(el)[0];
    if (t) setTimeout(function () { try { t.focus({ preventScroll: true }); } catch (e) { t.focus(); } }, F.rm ? 0 : 60);
    if (F.onSheet) F.onSheet(el, true);
  };
  F.closeSheet = function (quiet) {
    if (!cur) return;
    var el = cur, op = opener;
    cur = opener = null;
    el.classList.remove('is-open');
    el.removeAttribute('aria-modal');
    if (op) op.setAttribute('aria-expanded', 'false');
    scrim.classList.remove('is-on');
    d.documentElement.classList.remove('kf-sheet-open', 'kf-lock');
    setTimeout(function () { if (!cur) bar.classList.remove('is-raised'); }, F.rm ? 0 : 320);
    if (op && !quiet) { try { op.focus({ preventScroll: true }); } catch (e) { op.focus(); } }
    if (F.onSheet) F.onSheet(el, false);
  };
  F.openEl = function () { return cur; };
})(window);
