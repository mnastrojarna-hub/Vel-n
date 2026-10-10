/* MotoGo24 — Landing v2 (viz landing.php): reveal animace, karusely (motorky,
   recenze s autoposunem), rozbalení výhod, sticky CTA lišta na mobilu, sbalitelný
   SEO text. Bez závislostí. */
(function () {
  var d = document, b = d.body;
  d.documentElement.classList.add('lp-js');
  var rm = !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
  var IO = 'IntersectionObserver' in window;
  function each(sel, fn, root) { Array.prototype.forEach.call((root || d).querySelectorAll(sel), fn); }

  // 1) Reveal on scroll
  if (IO && !rm) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -8% 0px' });
    each('.lp-reveal', function (el) { io.observe(el); });
  } else {
    each('.lp-reveal', function (el) { el.classList.add('is-in'); });
  }

  // 2) Karusel motorek — progress, šipky (jen myš), jednorázový „swipe“ náznak
  each('[data-lp-track]', function (tr) {
    var wrap = tr.parentNode, sec = wrap.parentNode;
    var bar = sec.querySelector('.lp-progress i');
    var prev = wrap.querySelector('.lp-nav-prev'), next = wrap.querySelector('.lp-nav-next');
    function upd() {
      var max = tr.scrollWidth - tr.clientWidth;
      var vis = tr.scrollWidth ? tr.clientWidth / tr.scrollWidth : 1;
      var pos = max > 0 ? tr.scrollLeft / max : 0;
      if (bar) {
        var w = Math.max(8, Math.min(100, vis * 100));
        bar.style.width = w + '%';
        bar.style.transform = 'translateX(' + (pos * (100 - w) / w * 100) + '%)';
      }
      if (prev) prev.disabled = tr.scrollLeft < 8;
      if (next) next.disabled = tr.scrollLeft > max - 8;
    }
    function step(dir) {
      var card = tr.firstElementChild;
      var dx = card ? card.getBoundingClientRect().width + 16 : tr.clientWidth * 0.8;
      tr.scrollBy({ left: dir * dx * (window.innerWidth >= 1100 ? 3 : 2), behavior: rm ? 'auto' : 'smooth' });
    }
    if (prev && next && window.matchMedia && matchMedia('(hover: hover) and (pointer: fine)').matches) {
      prev.hidden = false; next.hidden = false;
      prev.addEventListener('click', function () { step(-1); });
      next.addEventListener('click', function () { step(1); });
    }
    var raf = 0;
    tr.addEventListener('scroll', function () { if (!raf) raf = requestAnimationFrame(function () { raf = 0; upd(); }); }, { passive: true });
    window.addEventListener('resize', upd);
    upd();
    if (IO && !rm && tr.scrollWidth > tr.clientWidth + 8) {
      var ho = new IntersectionObserver(function (es) {
        if (!es[0].isIntersecting) return;
        ho.disconnect();
        setTimeout(function () { if (tr.scrollLeft < 4) tr.classList.add('lp-nudge'); }, 400);
      }, { threshold: 0.6 });
      ho.observe(tr);
      tr.addEventListener('pointerdown', function () { tr.classList.remove('lp-nudge'); }, { passive: true });
    }
    // Recenze: pomalý automatický posun, jen když je karusel vidět a uživatel se ho nedotkl
    if (tr.hasAttribute('data-lp-autoplay') && IO && !rm) {
      var stop = false, vis = false, tm = 0;
      var tick = function () {
        if (stop || !vis || d.hidden) return;
        var max = tr.scrollWidth - tr.clientWidth;
        var card = tr.firstElementChild;
        var dx = card ? card.getBoundingClientRect().width + 12 : tr.clientWidth * 0.8;
        tr.scrollTo({ left: tr.scrollLeft >= max - 8 ? 0 : tr.scrollLeft + dx, behavior: 'smooth' });
      };
      new IntersectionObserver(function (es) {
        vis = es[0].isIntersecting;
        clearInterval(tm);
        if (vis && !stop) tm = setInterval(tick, 5000);
      }, { threshold: 0.5 }).observe(tr);
      ['pointerdown', 'wheel', 'touchstart', 'focusin', 'keydown'].forEach(function (ev) {
        tr.addEventListener(ev, function () { stop = true; clearInterval(tm); }, { passive: true });
      });
      each('.lp-nav', function (n) { n.addEventListener('click', function () { stop = true; clearInterval(tm); }); }, wrap);
    }
  });

  // 2b) Důvody „Proč jezdit s námi“ — dalších N výhod po rozbalení (bez JS vidět vše)
  each('[data-lp-reasons]', function (btn) {
    var sec = btn.closest('.lp-reasons');
    if (!sec) return;
    btn.hidden = false;
    btn.addEventListener('click', function () {
      var open = !sec.classList.contains('is-open');
      sec.classList.toggle('is-open', open);
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
      btn.textContent = btn.getAttribute(open ? 'data-close' : 'data-open');
      if (open) {
        var first = sec.querySelector('.lp-reason--extra');
        each('.lp-reason--extra', function (el) { el.classList.add('is-in'); }, sec);
        if (first) { first.setAttribute('tabindex', '-1'); first.focus({ preventScroll: true }); }
      } else if (sec.getBoundingClientRect().top < 0) {
        sec.scrollIntoView({ behavior: rm ? 'auto' : 'smooth' });
      }
    });
  });

  // 3) Sticky CTA lišta — po odscrollování tlačítek akčního panelu; skrytá, když je
  //    vidět závěrečná výzva (.lp-cta) nebo patička (tam jsou tlačítka/kontakty)
  //    a dokud je otevřená cookie lišta (ta má přednost)
  var st = d.querySelector('[data-lp-sticky]'), sen = d.querySelector('[data-lp-sentinel]'), cs = d.getElementById('mg-consent');
  if (st && sen && IO) {
    var past = false, foot = false, on = null, seen = [];
    var apply = function () {
      var v = past && !foot && !(cs && !cs.hidden);
      if (v === on) return;
      on = v;
      b.classList.toggle('lp-sticky-on', v);
      st.setAttribute('aria-hidden', v ? 'false' : 'true');
      each('a', function (a) { if (v) a.removeAttribute('tabindex'); else a.setAttribute('tabindex', '-1'); }, st);
      // prvek s focusem (Tab) nesmí skončit pod lištou
      d.documentElement.style.scrollPaddingBottom = v ? (st.offsetHeight + 12) + 'px' : '';
    };
    if (cs && 'MutationObserver' in window) new MutationObserver(apply).observe(cs, { attributes: true, attributeFilter: ['hidden'] });
    new IntersectionObserver(function (es) {
      var e = es[0];
      past = !e.isIntersecting && e.boundingClientRect.top < 0;
      b.classList.toggle('lp-cta-visible', e.isIntersecting);
      apply();
    }).observe(sen);
    var eo = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        var k = seen.indexOf(e.target);
        if (e.isIntersecting && k < 0) seen.push(e.target);
        if (!e.isIntersecting && k >= 0) seen.splice(k, 1);
      });
      foot = seen.length > 0;
      apply();
    });
    each('.lp-cta, footer', function (el) { eo.observe(el); });
  }

  // 4) Sbalitelný SEO text — v DOM zůstává celý (indexace), jen se vizuálně zkrátí
  each('[data-lp-more]', function (s) {
    var btn = s.querySelector('.lp-more-btn'), body = s.querySelector('.lp-more-body');
    if (!btn || !body || body.scrollHeight < 260) return;
    var set = function (collapsed) {
      s.classList.toggle('is-collapsed', collapsed);
      btn.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
      btn.textContent = btn.getAttribute(collapsed ? 'data-open' : 'data-close');
    };
    set(true);
    btn.hidden = false;
    btn.addEventListener('click', function () { set(!s.classList.contains('is-collapsed')); });
  });
})();
