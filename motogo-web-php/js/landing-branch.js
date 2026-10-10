/* MotoGo24 — Landing v2: pobočky (viz pages/pobocky-v2-lib.php). Průvodce „Jak to probíhá“:
   na mobilu (< 900 px) krokování — jeden krok, „Krok X z N“, tečky, Předchozí/Další, swipe;
   na desktopu a bez JS časová osa se všemi kroky. Počítadla čísel ve statistikách.
   Reveal, karusely a sticky lištu obsluhuje js/landing.js. Bez závislostí. */
(function () {
  var d = document;
  var rm = !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
  function each(sel, fn, root) { Array.prototype.forEach.call((root || d).querySelectorAll(sel), fn); }

  // 1) Průvodce — krokování na mobilu
  each('[data-pb-guide]', function (g) {
    var steps = g.querySelectorAll('.pb-gstep'), n = steps.length;
    var bar = g.querySelector('.pb-guide-bar'), cnt = g.querySelector('.pb-guide-count');
    var fill = g.querySelector('.pb-guide-prog i'), dots = g.querySelectorAll('.pb-guide-dots button');
    var prev = g.querySelector('.pb-guide-btn[data-dir="-1"]'), next = g.querySelector('.pb-guide-btn[data-dir="1"]');
    var list = g.querySelector('.pb-guide-list');
    if (n < 2 || !bar || !cnt || !prev || !next || !list || !window.matchMedia) return;
    var mq = matchMedia('(max-width: 899px)'), cur = 0, on = false;
    var tpl = cnt.getAttribute('data-tpl') || '{n} / {total}';

    function show(i, scroll) {
      i = Math.max(0, Math.min(n - 1, i));
      var back = i < cur;
      cur = i;
      Array.prototype.forEach.call(steps, function (s, k) {
        s.classList.toggle('is-cur', k === i);
        s.classList.toggle('is-back', k === i && back);
      });
      Array.prototype.forEach.call(dots, function (b, k) {
        b.classList.toggle('is-done', k < i);
        if (k === i) b.setAttribute('aria-current', 'step'); else b.removeAttribute('aria-current');
      });
      cnt.textContent = tpl.replace('{n}', i + 1).replace('{total}', n);
      if (fill) fill.style.width = ((i + 1) / n * 100) + '%';
      prev.disabled = i === 0;
      g.classList.toggle('is-last', i === n - 1);
      // po „Další“ dole pod dlouhým krokem: zpět na začátek kroku (pod sticky hlavičku)
      if (scroll) {
        var hd = d.querySelector('header'), off = hd ? Math.max(0, hd.getBoundingClientRect().bottom) : 0;
        var top = bar.getBoundingClientRect().top - off - 12;
        if (top < 0) window.scrollBy({ top: top, behavior: rm ? 'auto' : 'smooth' });
      }
    }

    function mode() {
      var m = mq.matches;
      if (m === on) return;
      on = m;
      g.classList.toggle('is-stepper', on);
      bar.hidden = !on;
      prev.hidden = !on;
      next.hidden = !on;
      if (on) {
        each('.pb-gstep', function (s) { s.classList.add('is-in'); }, g);
        show(cur, false);
      } else {
        g.classList.remove('is-last');
        each('.pb-gstep', function (s) { s.classList.remove('is-cur', 'is-back'); }, g);
      }
    }

    prev.addEventListener('click', function () { show(cur - 1, true); });
    next.addEventListener('click', function () { show(cur + 1, true); });
    Array.prototype.forEach.call(dots, function (b) {
      b.addEventListener('click', function () { show(parseInt(b.getAttribute('data-step'), 10) || 0, false); });
    });
    // swipe vlevo/vpravo
    var x0 = null, y0 = 0;
    list.addEventListener('touchstart', function (e) {
      if (!on || e.touches.length !== 1) return;
      x0 = e.touches[0].clientX; y0 = e.touches[0].clientY;
    }, { passive: true });
    list.addEventListener('touchend', function (e) {
      if (!on || x0 === null) return;
      var t = e.changedTouches[0], dx = t.clientX - x0, dy = t.clientY - y0;
      x0 = null;
      if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) show(cur + (dx < 0 ? 1 : -1), false);
    }, { passive: true });
    if (mq.addEventListener) mq.addEventListener('change', mode); else if (mq.addListener) mq.addListener(mode);
    mode();
    // přímý odkaz na krok (#krok-3)
    var h = /^#krok-(\d+)$/.exec(location.hash);
    if (h && on) show(parseInt(h[1], 10) - 1, false);
  });

  // 2) Počítadla čísel ve statistikách (hodnota je v HTML, JS ji jen „napočítá“)
  if ('IntersectionObserver' in window && !rm) {
    var co = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (!e.isIntersecting) return;
        co.unobserve(e.target);
        var el = e.target, to = parseInt(el.getAttribute('data-pb-count'), 10), t0 = null;
        if (!(to > 1)) return;
        var f = function (t) {
          if (t0 === null) t0 = t;
          var p = Math.min(1, (t - t0) / 900);
          el.textContent = String(Math.round(to * (1 - Math.pow(1 - p, 3))));
          if (p < 1) requestAnimationFrame(f);
        };
        el.textContent = '0';
        requestAnimationFrame(f);
      });
    }, { threshold: 0.6 });
    each('[data-pb-count]', function (el) { co.observe(el); });
  }
})();
