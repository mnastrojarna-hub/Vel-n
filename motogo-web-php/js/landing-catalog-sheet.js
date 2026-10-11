/* MotoGo24 — katalog v2: otevírání panelů (bottom sheet na mobilu, rozbalovací panel / popover
   na desktopu). Esc a klik mimo zavře, na mobilu modální (focus trap, zámek scrollu), fokus se
   vrací na tlačítko. Používá js/landing-catalog.js (filtry) a js/landing-catalog-dates.js (termín).
   F.initMode: přepínač karty .km [Najít motorku | Spočítat cenu] (kalkulačka je v kartě),
   F.initExtras: tlačítko kalkulačky na kartách, úvod na 2 řádky, přilepená lišta (is-float). */
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
    // Desktop: panel pod ohybem (karta níž než dřív) → posun tak, aby byl celý vidět
    if (F.isDesk() && !bar.classList.contains('is-float')) w.requestAnimationFrame(function () {
      if (cur !== el) return;
      var r = el.getBoundingClientRect(), row = bar.parentNode;
      if (r.bottom > w.innerHeight && row) w.scrollBy({ top: Math.min(r.bottom - w.innerHeight + 16, row.getBoundingClientRect().top - 12), behavior: F.rm ? 'auto' : 'smooth' });
    });
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
  // --- Přepínač režimu karty .km: role tablist/tab/tabpanel (bez JS je přepínač skrytý a oba režimy
  //     vidět), šipky + Home/End s roving tabindexem, automatická aktivace. Vrací setMode(m). ---
  F.initMode = function (onUserCalc) {
    var km = d.querySelector('[data-km]'), tabs = km ? Array.prototype.slice.call(km.querySelectorAll('[data-km-tab]')) : [];
    if (!tabs.length) return function () {};
    tabs[0].parentNode.setAttribute('role', 'tablist');
    function set(m, focus, user) {
      var changed = km.getAttribute('data-mode') !== m;
      if (changed) F.closeSheet(true);
      km.setAttribute('data-mode', m);
      if (user && m !== 'calc' && w.location.hash === '#kalkulacka') try { history.replaceState(history.state, '', w.location.pathname + w.location.search); } catch (e) {}
      if (changed && F.onMode) F.onMode(m);
      if (changed && user && m === 'calc' && onUserCalc) onUserCalc();
      tabs.forEach(function (t) {
        var on = t.getAttribute('data-km-tab') === m;
        t.setAttribute('aria-selected', on ? 'true' : 'false');
        t.tabIndex = on ? 0 : -1;
        if (on && focus) t.focus();
      });
    }
    tabs.forEach(function (t, i) {
      var p = d.getElementById(t.getAttribute('aria-controls'));
      t.setAttribute('role', 'tab');
      if (p) { p.setAttribute('role', 'tabpanel'); p.setAttribute('aria-labelledby', t.id); }
      t.addEventListener('click', function () { set(t.getAttribute('data-km-tab'), false, true); });
      t.addEventListener('keydown', function (e) {
        var k = e.key, n = tabs.length, j = k === 'ArrowRight' ? i + 1 : k === 'ArrowLeft' ? i - 1 : k === 'Home' ? 0 : k === 'End' ? n - 1 : null;
        if (j === null) return;
        e.preventDefault();
        set(tabs[(j + n) % n].getAttribute('data-km-tab'), true, true);
      });
    });
    set('find');
    km.setAttribute('data-km-ready', ''); // CSS skrývá neaktivní režim až po inicializaci (jinak no-JS vzhled)
    return set;
  };
  // --- Drobné UI katalogu; vrací calc(id) = režim kalkulačky (motorka z karty, termín z filtru) ---
  F.initExtras = function (o) {
    var K = w.MGKC || {}, T = o.T, kcRoot = d.querySelector('[data-kc]'), km = d.querySelector('[data-km]'), q = function (s) { return o.root.querySelector(s); };
    // Přepnutí na kalkulačku záložkou převezme termín z filtru (motorku nechá)
    var setMode = F.initMode(function () {
      var DT = o.dt();
      if (kcRoot && K.calcSet && DT && DT.active()) K.calcSet({ keepMoto: true, start: DT.start(), end: DT.end() });
    });
    function calc(id, now) {
      if (!kcRoot) return;
      var DT = o.dt();
      setMode('calc');
      // Kotva #kalkulacka (i nativní skok prohlížeče) skončí na horní hraně karty, ne pod přepínačem
      if (km) kcRoot.style.scrollMarginTop = Math.round(kcRoot.getBoundingClientRect().top - km.getBoundingClientRect().top + 12) + 'px';
      if (K.calcSet && (id || (DT && DT.active()))) K.calcSet({ moto: id || '', start: DT && DT.start(), end: DT && DT.end() });
      (km || kcRoot).scrollIntoView({ behavior: F.rm || now ? 'auto' : 'smooth', block: 'start' });
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
    // Lišta Termín/Filtry/🧮 se přilepí nahoru, jen když řádek s poli odjel NAD viewport (ne pod ohyb)
    // + jen dokud je na obrazovce mřížka motorek (ne přes SEO text / FAQ / patičku pod katalogem)
    var row = o.bar.parentNode, grid = d.getElementById('katalog-grid');
    if ('IntersectionObserver' in w && row && row.classList.contains('km-row--bar')) {
      var gone = false, inGrid = true;
      var upd = function () {
        var f = gone && inGrid && (!km || km.getAttribute('data-mode') !== 'calc');
        if (f && !o.bar.classList.contains('is-float')) row.style.minHeight = o.bar.offsetHeight + 'px';
        o.bar.classList.toggle('is-float', f);
      };
      new IntersectionObserver(function (es) { var e = es[0]; gone = !e.isIntersecting && e.boundingClientRect.top < 0; upd(); }, { rootMargin: '-24px 0px 0px 0px' }).observe(row);
      if (grid) new IntersectionObserver(function (es) { inGrid = es[0].isIntersecting; upd(); }, { rootMargin: '-80px 0px 0px 0px' }).observe(grid);
      F.onMode = function () { upd(); };
    }
    // Odkaz /katalog#kalkulacka (i během návštěvy) otevře režim kalkulačky (po sbalení úvodu)
    var hash = function (e) { if (w.location.hash === '#kalkulacka') calc('', !e); };
    setTimeout(hash, 0); // až po F.initDates (termín z URL se tak předá i kalkulačce)
    w.addEventListener('hashchange', hash);
    return calc;
  };
})(window);
