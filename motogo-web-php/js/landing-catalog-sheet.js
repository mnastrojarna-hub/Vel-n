/* MotoGo24 — katalog v2: otevírání panelů (bottom sheet na mobilu, rozbalovací panel / popover
   na desktopu). Esc a klik mimo zavře, na mobilu modální (focus trap, zámek scrollu), fokus se
   vrací na tlačítko. Používá js/landing-catalog.js (filtry) a js/landing-catalog-dates.js (termín).
   F.initExtras: kalkulačka pod mřížkou (na mobilu sbalená, tlačítko na kartách), úvod na 2 řádky,
   stín přilepené lišty. */
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
    // Desktop (nemodální): klik mimo zavře přes průhledný scrim, odchod fokusu z panelu taky
    d.addEventListener('focusin', function (e) {
      if (cur && F.isDesk() && !cur.contains(e.target) && e.target !== opener) F.closeSheet(true);
    });
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
    if (t) setTimeout(function () { if (cur === el && !el.contains(d.activeElement)) try { t.focus({ preventScroll: true }); } catch (e) { t.focus(); } }, F.rm ? 0 : 60);
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
  // --- Drobné UI katalogu; vrací calc(id) = otevřít kalkulačku (motorka z karty, termín z filtru) ---
  F.initExtras = function (o) {
    var K = w.MGKC || {}, T = o.T, kcRoot = d.querySelector('[data-kc]'), tg = null, q = function (s) { return o.root.querySelector(s); };
    function calc(id) {
      if (!kcRoot) return;
      var DT = o.dt();
      kcRoot.classList.remove('kf-closed');
      if (tg) tg.hidden = true;
      if (K.calcSet && (id || (DT && DT.active()))) K.calcSet({ moto: id || '', start: DT && DT.start(), end: DT && DT.end() });
      kcRoot.scrollIntoView({ behavior: F.rm ? 'auto' : 'smooth', block: 'start' });
    }
    if (kcRoot && o.kc && K.ico) {
      q('[data-kf-calc]').hidden = false;
      var un = {}, ico = q('[data-kf-calc] .lp-ico').outerHTML;
      o.kc.motos.forEach(function (m) { if (m.un) un[m.id] = 1; });
      Object.keys(o.cards).forEach(function (id) {
        var li = o.cards[id], act = li.querySelector('.kf-act'), h = li.querySelector('h3');
        if (!act || un[id]) return;
        var b = d.createElement('button');
        b.type = 'button'; b.className = 'kf-calc-btn'; b.setAttribute('data-id', id);
        b.setAttribute('aria-label', T.f_calc + (h ? ': ' + h.textContent : ''));
        b.title = T.f_calc;
        b.innerHTML = ico;
        act.appendChild(b);
      });
      var head = kcRoot.querySelector('.kc-head'), body = kcRoot.querySelector('.kc-grid');
      if (head && body && !F.isDesk() && w.location.hash !== '#kalkulacka') {
        body.id = body.id || 'kc-body';
        kcRoot.classList.add('kf-closed');
        tg = d.createElement('button');
        tg.type = 'button'; tg.className = 'lp-btn lp-btn-primary kf-calc-tg';
        tg.setAttribute('aria-expanded', 'false'); tg.setAttribute('aria-controls', body.id);
        tg.innerHTML = K.ico('cal') + '<span>' + K.esc(T.f_calc_open) + '</span>';
        head.appendChild(tg);
        tg.addEventListener('click', function () {
          kcRoot.classList.remove('kf-closed'); tg.setAttribute('aria-expanded', 'true'); tg.hidden = true;
          var s = kcRoot.querySelector('#kc-moto'); if (s) s.focus({ preventScroll: true });
        });
      }
    }
    // Úvodní text na mobilu sbalený na 2 řádky (text zůstává v DOM)
    var intro = d.querySelector('.kf-intro');
    if (intro && w.innerWidth <= 768) {
      intro.classList.add('is-clamp');
      if (intro.scrollHeight > intro.clientHeight + 4) {
        var mb = d.createElement('button');
        mb.type = 'button'; mb.className = 'kf-more'; mb.setAttribute('aria-expanded', 'false'); mb.textContent = T.more_open;
        intro.parentNode.insertBefore(mb, intro.nextSibling);
        mb.addEventListener('click', function () {
          var c = intro.classList.toggle('is-clamp');
          mb.textContent = c ? T.more_open : T.more_close; mb.setAttribute('aria-expanded', c ? 'false' : 'true');
        });
      } else intro.classList.remove('is-clamp');
    }
    // Stín lišty, když je přilepená
    if ('IntersectionObserver' in w) {
      var sen = d.createElement('div');
      sen.setAttribute('aria-hidden', 'true');
      o.bar.parentNode.insertBefore(sen, o.bar);
      new IntersectionObserver(function (es) { o.bar.classList.toggle('is-stuck', !es[0].isIntersecting); }).observe(sen);
    }
    return calc;
  };
})(window);
