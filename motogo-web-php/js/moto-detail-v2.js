/* MotoGo24 — Detail motorky v2 (pages/katalog-detail.php při landingV2Enabled(), css/moto-detail-v2.css):
   1) ikony parametrů a výbavy, 2) swipe galerie — počítadlo, šipky (myš), náhledy (desktop);
   klik na fotku dál otevírá lightbox.js, 3) mobilní sticky lišta „Rezervovat“ (ustoupí liště
   kalkulačky .kc-sticky, patičce a cookie liště). Bez závislostí; bez JS je vše vidět a funkční. */
(function () {
  var d = document, b = d.body, W = window;
  var rm = !!(W.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
  function each(sel, fn, root) { Array.prototype.forEach.call((root || d).querySelectorAll(sel), fn); }
  var ICO = {
    year: 'M4 5h16v15H4zM16 3v4M8 3v4M4 10h16',
    color: 'M12 3a9 9 0 0 0 0 18c1.2 0 1.6-.9 1.6-1.6 0-1.5 1-2.1 2.3-2.1H18a3 3 0 0 0 3-3C21 7 17 3 12 3zM7.5 11.5h.01M9.5 7.5h.01M14.5 7.5h.01',
    engine: 'M3 10h2V8h3V6h6v2h2l2 2.5h3v5h-3L16 18H8l-3-3H3z',
    power: 'M13 2 4.5 13.5H11L10 22l8.5-11.5H13z',
    torque: 'M20.5 12a8.5 8.5 0 1 1-2.5-6M20.5 3.5V8H16',
    gear: 'M6 5v14M12 5v14M18 5v7H6',
    chain: 'M9 15l6-6M10.5 6.5l1.2-1.2a4 4 0 0 1 5.7 5.7l-1.2 1.2M13.5 17.5l-1.2 1.2a4 4 0 0 1-5.7-5.7l1.2-1.2',
    speed: 'M4 17.5a8.5 8.5 0 1 1 16 0M12 16.5l4-5',
    fuel: 'M5 21V5a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v16M3.5 21h12M5 10h9M14 8h2a2 2 0 0 1 2 2v6.5a1.5 1.5 0 0 0 3 0V9l-3-3',
    tank: 'M12 3s6 6.4 6 11a6 6 0 0 1-12 0c0-4.6 6-11 6-11z',
    brake: 'M12 3a9 9 0 1 0 .01 0zM12 9a3 3 0 1 0 .01 0zM12 5.5v1M18.5 12h-1M12 18.5v-1M5.5 12h1',
    shield: 'M12 3l7.5 3v5.5c0 4.7-3.2 8.2-7.5 9.5-4.3-1.3-7.5-4.8-7.5-9.5V6zM9 12l2 2 4-4',
    weight: 'M5 9h14l1.5 12h-17zM9 9a3 3 0 1 1 6 0',
    height: 'M12 3v18M8.5 6.5 12 3l3.5 3.5M8.5 17.5 12 21l3.5-3.5',
    seats: 'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM3 20a6 6 0 0 1 12 0M16 4.3a3.5 3.5 0 0 1 0 6.4M21 20a6 6 0 0 0-3.5-5.5',
    lic: 'M3 6h18v12H3zM7 11a2 2 0 1 0 4 0 2 2 0 0 0-4 0M6.5 15.5a3 3 0 0 1 5 0M14.5 10h3.5M14.5 14h3.5',
    time: 'M12 3a9 9 0 1 0 .01 0zM12 7.5V12l3 2',
    dot: 'M12 8a4 4 0 1 0 .01 0z',
    helmet: 'M4 18v-3.5A8.5 8.5 0 0 1 20.5 12v6zM11 12.5h9.5M15 18v-3',
    jacket: 'M9 3 12 6l3-3 4 2.5L18 11h-2v10H8V11H6L5 5.5zM12 6v15',
    pants: 'M6.5 3h11l1.5 18h-5L12 10l-2 11H5z',
    gloves: 'M8 21v-5.5L4.5 12l1.5-1.5L8.5 13V5.5a1.4 1.4 0 0 1 2.8 0V11V4.2a1.4 1.4 0 0 1 2.8 0V11V5.5a1.4 1.4 0 0 1 2.8 0V15c0 3.3-2 6-5 6z',
    arrow: 'M5 12h14M13 6l6 6-6 6'
  };
  function svg(name, cls) {
    var NS = 'http://www.w3.org/2000/svg', s = d.createElementNS(NS, 'svg'), p = d.createElementNS(NS, 'path');
    var at = { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', 'stroke-width': '2', 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true', focusable: 'false' };
    for (var k in at) s.setAttribute(k, at[k]);
    if (cls) s.setAttribute('class', cls);
    p.setAttribute('d', ICO[name] || ICO.dot);
    s.appendChild(p);
    return s;
  }

  // 1) Ikony parametrů (data-ico) a výbavy v ceně (.g-<název>)
  each('.md-spec[data-ico]', function (li) { li.insertBefore(svg(li.getAttribute('data-ico'), 'md-spec-i'), li.firstChild); });
  each('.md-gear-ico i', function (i) { var m = /g-(\w+)/.exec(i.className); if (m && ICO[m[1]]) i.appendChild(svg(m[1])); });

  // 2) Galerie: snímky = video + hlavní fotka + ostatní fotky (všechny přes celou šířku .md-track)
  each('.md-gallery', function (g) {
    var tr = g.querySelector('.md-track');
    var sl = tr ? tr.querySelectorAll('.moto-video,.moto-photo,.moto-thumbs>div') : [];
    var n = sl.length, cur = -1, raf = 0, tb = [];
    if (n < 2) return;
    var lb = d.getElementById('mg-lightbox');
    var tpl = (lb && lb.getAttribute('data-counter-tpl')) || '{current} / {total}';
    function num(i) { return tpl.replace('{current}', String(i + 1)).replace('{total}', String(n)); }
    function go(i) { i = (i % n + n) % n; tr.scrollTo({ left: i * tr.clientWidth, behavior: rm ? 'auto' : 'smooth' }); }
    var cnt = d.createElement('span');
    cnt.className = 'md-count';
    cnt.setAttribute('aria-hidden', 'true');
    g.appendChild(cnt);
    var fine = !!(W.matchMedia && matchMedia('(hover: hover) and (pointer: fine)').matches);
    [-1, 1].forEach(function (dir) {
      var src = (lb || g).querySelector(dir < 0 ? '.mg-lb-prev' : '.mg-lb-next'), a = d.createElement('button');
      a.type = 'button';
      a.className = 'md-arr md-arr--' + (dir < 0 ? 'prev' : 'next');
      a.setAttribute('aria-label', (src && src.getAttribute('aria-label')) || '');
      a.hidden = !fine;
      a.appendChild(svg('arrow'));
      a.addEventListener('click', function () { go(cur + dir); });
      g.appendChild(a);
    });
    var th = d.createElement('div');
    th.className = 'md-thumbs';
    Array.prototype.forEach.call(sl, function (s, i) {
      var im = s.querySelector('img'), v = s.querySelector('video'), u = im ? im.getAttribute('src') : (v && v.getAttribute('poster'));
      var bt = d.createElement('button');
      bt.type = 'button';
      if (v) bt.className = 'is-video';
      bt.setAttribute('aria-label', num(i));
      if (u) { var t = d.createElement('img'); t.src = u; t.alt = ''; t.loading = 'lazy'; t.decoding = 'async'; bt.appendChild(t); }
      bt.addEventListener('click', function () { go(i); });
      th.appendChild(bt);
      tb.push(bt);
    });
    g.appendChild(th);
    // Video mimo zobrazený snímek pozastavíme (šetří data); po návratu ho pustíme jen když jsme ho zastavili my
    var vid = tr.querySelector('video'), vi = vid ? Array.prototype.indexOf.call(sl, vid.closest('.moto-video')) : -1, ours = false;
    function upd() {
      raf = 0;
      var i = Math.max(0, Math.min(n - 1, Math.round(tr.scrollLeft / (tr.clientWidth || 1))));
      if (i === cur) return;
      cur = i;
      cnt.textContent = num(i);
      tb.forEach(function (x, k) { x.setAttribute('aria-current', k === i ? 'true' : 'false'); });
      if (th.scrollWidth > th.clientWidth) th.scrollTo({ left: tb[i].offsetLeft - (th.clientWidth - tb[i].offsetWidth) / 2, behavior: rm ? 'auto' : 'smooth' });
      if (vid && i !== vi && !vid.paused) { vid.pause(); ours = true; }
      else if (vid && i === vi && ours) { ours = false; var p = vid.play(); if (p && p.catch) p.catch(function () {}); }
    }
    tr.addEventListener('scroll', function () { if (!raf) raf = requestAnimationFrame(upd); }, { passive: true });
    tr.addEventListener('keydown', function (e) {
      if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
      e.preventDefault();
      go(cur + (e.key === 'ArrowRight' ? 1 : -1));
    });
    var rt = 0;
    W.addEventListener('resize', function () {
      clearTimeout(rt);
      rt = setTimeout(function () { var c = Math.max(cur, 0); tr.scrollLeft = c * tr.clientWidth; cur = -1; upd(); }, 120);
    });
    upd();
  });

  // 3) Sticky lišta — po odscrollování CTA panelu; skrytá u kalkulačky, patičky, cookie lišty a když je
  //    vidět lišta kalkulačky. Polohu čteme při scrollu (IntersectionObserver nehlásí skok nahoru přes celou stránku).
  var st = d.querySelector('[data-md-sticky]'), sen = d.querySelector('[data-md-sentinel]');
  if (!st || !sen) return;
  var on = null, cta = null, rq = 0, kc = d.querySelector('.kc-sticky'), cs = d.getElementById('mg-consent');
  var zones = [d.getElementById('kalkulacka'), d.querySelector('footer')].filter(Boolean);
  function inView(el) { var r = el.getBoundingClientRect(); return r.bottom > 0 && r.top < W.innerHeight; }
  function apply() {
    rq = 0;
    var r = sen.getBoundingClientRect(), vis = r.bottom > 0 && r.top < W.innerHeight;
    if (vis !== cta) { cta = vis; b.classList.toggle('lp-cta-visible', vis); }
    var v = r.bottom < 0 && !zones.some(inView) && !(kc && kc.classList.contains('is-on')) && !(cs && !cs.hidden) && W.innerWidth < 769;
    if (v === on) return;
    on = v;
    st.classList.toggle('is-on', v);
    b.classList.toggle('md-sticky-on', v);
    st.setAttribute('aria-hidden', v ? 'false' : 'true');
    each('a', function (a) { if (v) a.removeAttribute('tabindex'); else a.setAttribute('tabindex', '-1'); }, st);
    d.documentElement.style.scrollPaddingBottom = v ? (st.offsetHeight + 12) + 'px' : '';
  }
  function req() { if (!rq) rq = requestAnimationFrame(apply); }
  W.addEventListener('scroll', req, { passive: true });
  W.addEventListener('resize', req);
  if ('MutationObserver' in W) {
    var mo = new MutationObserver(req);
    if (kc) mo.observe(kc, { attributes: true, attributeFilter: ['class'] });
    if (cs) mo.observe(cs, { attributes: true, attributeFilter: ['hidden'] });
  }
  apply();
})();
