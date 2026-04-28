// ===== MotoGo24 — Lightbox =====
// Vanilla JS, žádné závislosti. Najde všechny <a data-gallery="X" data-index="N">,
// při kliknutí otevře full-screen náhled s navigací prev/next/close + klávesy a swipe.
(function(){
  'use strict';
  var root = document.getElementById('mg-lightbox');
  if (!root) return;

  var imgEl     = root.querySelector('.mg-lb-img');
  var counterEl = root.querySelector('.mg-lb-counter');
  var btnPrev   = root.querySelector('.mg-lb-prev');
  var btnNext   = root.querySelector('.mg-lb-next');
  var btnClose  = root.querySelector('.mg-lb-close');
  var counterTpl = (root.getAttribute('data-counter-tpl') || '{current} / {total}');

  var current = 0;
  var items = [];

  function collect(group){
    var nodes = document.querySelectorAll('a[data-gallery="' + cssEscape(group) + '"]');
    // Filtrovat: skryté originály (mobile rebuild) a klony pásu miniatur.
    var arr = Array.prototype.slice.call(nodes).filter(function(a){
      if (a.closest('.mg-mob-orig-hidden')) return false;
      if (a.getAttribute('data-mg-clone') === '1') return false;
      return true;
    });
    // Deduplikace podle data-index — zachová jediný anchor pro každý index
    // (např. hlavní fotka je v .mg-mob-main i v .mg-mob-strip jako index 0).
    var seen = {};
    arr = arr.filter(function(a){
      var k = a.getAttribute('data-index') || '0';
      if (seen[k]) return false;
      seen[k] = 1; return true;
    });
    arr.sort(function(a,b){
      var ia = parseInt(a.getAttribute('data-index') || '0', 10);
      var ib = parseInt(b.getAttribute('data-index') || '0', 10);
      return ia - ib;
    });
    return arr.map(function(a){
      var img = a.querySelector('img');
      return {
        href: a.getAttribute('href'),
        alt: (img && img.getAttribute('alt')) || ''
      };
    });
  }

  function cssEscape(s){
    return String(s).replace(/["\\]/g,'\\$&');
  }

  function render(){
    if (!items.length) return;
    if (current < 0) current = items.length - 1;
    if (current >= items.length) current = 0;
    var it = items[current];
    imgEl.src = it.href;
    imgEl.alt = it.alt;
    counterEl.textContent = counterTpl
      .replace('{current}', String(current + 1))
      .replace('{total}', String(items.length));
    var multi = items.length > 1;
    btnPrev.style.display = multi ? '' : 'none';
    btnNext.style.display = multi ? '' : 'none';
    counterEl.style.display = multi ? '' : 'none';
  }

  function open(group, index){
    items = collect(group);
    if (!items.length) return;
    current = Math.max(0, Math.min(items.length - 1, index|0));
    // Únik z případného ancestor containing-blocku (transform/filter na předkovi
    // umí rozbít position:fixed a způsobit, že overlay vykreslí pod patou webu).
    if (root.parentElement !== document.body) document.body.appendChild(root);
    root.removeAttribute('hidden');
    // Inline pojistka na případy, kdy by CSS bylo přepsáno jiným pravidlem.
    // dvh místo vh kvůli iOS Safari (URL bar mu jinak ukousne spodek a × se
    // nedostane na obrazovku).
    root.style.position = 'fixed';
    root.style.top = '0';
    root.style.left = '0';
    root.style.right = '0';
    root.style.bottom = '0';
    root.style.width = '100vw';
    root.style.height = '100vh';
    root.style.height = '100dvh';
    root.style.zIndex = '99999';
    root.style.display = 'flex';
    document.body.classList.add('mg-lb-open');
    resetZoom();
    render();
    btnClose.focus();
  }

  function close(){
    root.setAttribute('hidden','');
    root.style.display = '';
    root.style.position = '';
    root.style.top = '';
    root.style.left = '';
    root.style.right = '';
    root.style.bottom = '';
    root.style.width = '';
    root.style.height = '';
    root.style.zIndex = '';
    document.body.classList.remove('mg-lb-open');
    resetZoom();
    imgEl.src = '';
    items = [];
  }

  function next(){ resetZoom(); current++; render(); }
  function prev(){ resetZoom(); current--; render(); }

  // Click handlers — delegovat z document, aby fungovalo i na pozdě injektovaný obsah.
  document.addEventListener('click', function(e){
    var a = e.target.closest && e.target.closest('a[data-gallery]');
    if (!a) return;
    var group = a.getAttribute('data-gallery');
    var idx = parseInt(a.getAttribute('data-index') || '0', 10);
    if (!group) return;
    e.preventDefault();
    open(group, idx);
  });

  btnPrev.addEventListener('click', function(e){ e.stopPropagation(); prev(); });
  btnNext.addEventListener('click', function(e){ e.stopPropagation(); next(); });
  btnClose.addEventListener('click', function(e){ e.stopPropagation(); close(); });

  // Klik mimo obrázek (na overlay) zavře.
  root.addEventListener('click', function(e){
    if (e.target === root || e.target.classList.contains('mg-lb-stage')) close();
  });

  // Klávesy
  document.addEventListener('keydown', function(e){
    if (root.hasAttribute('hidden')) return;
    if (e.key === 'Escape') { e.preventDefault(); close(); }
    else if (e.key === 'ArrowRight') { e.preventDefault(); next(); }
    else if (e.key === 'ArrowLeft')  { e.preventDefault(); prev(); }
  });

  // ===== Touch: swipe + pinch zoom + double-tap zoom + pan when zoomed =====
  // Single touch:
  //   - když je zoom = 1, swipe vlevo/vpravo přepíná fotky (>50 px horizontálně)
  //   - když je zoom > 1, single-touch posouvá obrázek (pan)
  // Two touches:
  //   - pinch zoom kolem středu mezi prsty
  // Double-tap:
  //   - na 1× → zoom 2× (vystředěno na klepnutí)
  //   - na 2× → reset
  var zoom = 1, panX = 0, panY = 0;
  var tx = 0, ty = 0, tracking = false;
  var pinchStartDist = 0, pinchStartZoom = 1;
  var panStartX = 0, panStartY = 0;
  var lastTap = 0;

  function applyTransform(){
    imgEl.style.transform = 'translate3d(' + panX + 'px,' + panY + 'px,0) scale(' + zoom + ')';
    imgEl.style.transition = 'transform .15s ease';
  }
  function resetZoom(){
    zoom = 1; panX = 0; panY = 0;
    if (imgEl) {
      imgEl.style.transform = '';
      imgEl.style.transition = '';
    }
  }
  function distance(t1, t2){
    var dx = t1.clientX - t2.clientX, dy = t1.clientY - t2.clientY;
    return Math.sqrt(dx*dx + dy*dy);
  }

  // Necháváme touchmove ne-passive jen když potřebujeme blokovat scroll (pan zoomed / pinch).
  root.addEventListener('touchstart', function(e){
    if (e.touches.length === 2) {
      tracking = false;
      pinchStartDist = distance(e.touches[0], e.touches[1]);
      pinchStartZoom = zoom;
      imgEl.style.transition = 'none';
    } else if (e.touches.length === 1) {
      tracking = true;
      tx = e.touches[0].clientX;
      ty = e.touches[0].clientY;
      panStartX = panX;
      panStartY = panY;
      imgEl.style.transition = 'none';
    }
  }, {passive:true});

  root.addEventListener('touchmove', function(e){
    if (e.touches.length === 2 && pinchStartDist > 0) {
      e.preventDefault();
      var d = distance(e.touches[0], e.touches[1]);
      var newZoom = Math.max(1, Math.min(4, pinchStartZoom * (d / pinchStartDist)));
      zoom = newZoom;
      if (zoom === 1) { panX = 0; panY = 0; }
      imgEl.style.transform = 'translate3d(' + panX + 'px,' + panY + 'px,0) scale(' + zoom + ')';
    } else if (e.touches.length === 1 && tracking && zoom > 1) {
      e.preventDefault();
      var dx = e.touches[0].clientX - tx;
      var dy = e.touches[0].clientY - ty;
      panX = panStartX + dx;
      panY = panStartY + dy;
      imgEl.style.transform = 'translate3d(' + panX + 'px,' + panY + 'px,0) scale(' + zoom + ')';
    }
  }, {passive:false});

  root.addEventListener('touchend', function(e){
    if (e.touches.length === 0) {
      pinchStartDist = 0;
      imgEl.style.transition = 'transform .15s ease';
      // Single-touch swipe — jen když není zoom
      if (tracking && zoom === 1 && e.changedTouches.length === 1) {
        var t = e.changedTouches[0];
        var dx = t.clientX - tx;
        var dy = t.clientY - ty;
        if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) {
          if (dx < 0) next(); else prev();
        } else if (Math.abs(dx) < 10 && Math.abs(dy) < 10) {
          // Double-tap detect
          var now = Date.now();
          if (now - lastTap < 300) {
            if (zoom === 1) {
              zoom = 2;
              // Vystředíme zoom na místo klepnutí
              var rect = imgEl.getBoundingClientRect();
              var cx = rect.left + rect.width / 2;
              var cy = rect.top + rect.height / 2;
              panX = (cx - t.clientX);
              panY = (cy - t.clientY);
              applyTransform();
            } else {
              resetZoom();
            }
            lastTap = 0;
          } else {
            lastTap = now;
          }
        }
      }
      tracking = false;
    }
  }, {passive:true});

  // ===== Thumb strip nav (šipky pod hlavní fotkou) =====
  function thumbsForBtn(btn){
    var wrap = btn.closest('.moto-thumbs-wrap');
    return wrap ? wrap.querySelector('.moto-thumbs') : null;
  }
  function updateThumbBtns(strip){
    var wrap = strip.closest('.moto-thumbs-wrap');
    if (!wrap) return;
    var prevBtn = wrap.querySelector('.moto-thumbs-prev');
    var nextBtn = wrap.querySelector('.moto-thumbs-next');
    // Infinite mode — žádné okraje, šipky vždy aktivní.
    if (strip.dataset.mgInfinite === '1') {
      if (prevBtn) prevBtn.disabled = false;
      if (nextBtn) nextBtn.disabled = false;
      return;
    }
    var max = strip.scrollWidth - strip.clientWidth - 1;
    if (prevBtn) prevBtn.disabled = strip.scrollLeft <= 0;
    if (nextBtn) nextBtn.disabled = strip.scrollLeft >= max;
  }
  document.addEventListener('click', function(e){
    var btn = e.target.closest && e.target.closest('.moto-thumbs-prev, .moto-thumbs-next');
    if (!btn) return;
    e.preventDefault();
    var strip = thumbsForBtn(btn);
    if (!strip) return;
    var first = strip.querySelector('div');
    var step = first ? (first.getBoundingClientRect().width + 8) : Math.max(120, strip.clientWidth * 0.5);
    var dir = btn.classList.contains('moto-thumbs-next') ? 1 : -1;
    strip.scrollBy({ left: dir * step * 2, behavior: 'smooth' });
  });
  document.querySelectorAll('.moto-thumbs').forEach(function(strip){
    updateThumbBtns(strip);
    strip.addEventListener('scroll', function(){ updateThumbBtns(strip); }, {passive:true});
    window.addEventListener('resize', function(){ updateThumbBtns(strip); });
  });

  // ===== Mobile gallery rebuild =====
  // Na mobilu (≤768 px) přebudujeme galerii do vlastní izolované struktury
  // (.mg-mob-*) — původní DOM (.moto-photo, .moto-thumbs-wrap) schováme přes
  // display:none. Tím obejdeme jakékoli kolize s globálním CSS pro .gr3 / .gr4
  // / column-reverse a podobně, protože nové třídy nikdo jiný nestyluje.
  //
  // Layout:
  //   [   velká hlavní fotka   ]   ← .mg-mob-main (klik = lightbox)
  //   [ A ][ B ][ C ][ D ][ E ]    ← .mg-mob-strip (4-5 viditelných, scroll-x)
  //                                  klony 1× před + 1× za = nekonečný loop
  var MGM_BREAK = 768;

  function buildMobileGallery(gal){
    if (!gal || gal.dataset.mgmDone === '1') return;
    var anchors = Array.prototype.slice.call(gal.querySelectorAll('a[data-gallery]'));
    if (!anchors.length) return;
    var group = anchors[0].getAttribute('data-gallery') || 'moto';
    gal.dataset.mgmDone = '1';

    function makeAnchor(srcAnchor, indexOverride, isClone){
      var srcImg = srcAnchor.querySelector('img');
      var a = document.createElement('a');
      a.setAttribute('data-gallery', group);
      a.setAttribute('data-index', String(indexOverride));
      a.href = srcAnchor.getAttribute('href') || (srcImg && srcImg.src) || '#';
      var lbl = srcAnchor.getAttribute('aria-label');
      if (lbl) a.setAttribute('aria-label', lbl);
      if (isClone) a.setAttribute('data-mg-clone', '1');
      var img = document.createElement('img');
      img.src = (srcImg && (srcImg.getAttribute('src') || srcImg.src)) || '';
      img.alt = (srcImg && srcImg.getAttribute('alt')) || '';
      img.loading = 'lazy';
      img.decoding = 'async';
      a.appendChild(img);
      return a;
    }

    var wrap = document.createElement('div');
    wrap.className = 'mg-mob';

    // Hlavní fotka
    var main = makeAnchor(anchors[0], 0, false);
    main.className = 'mg-mob-main';
    wrap.appendChild(main);

    // Pás miniatur (jen pokud je víc než 1 fotka)
    if (anchors.length > 1) {
      var strip = document.createElement('div');
      strip.className = 'mg-mob-strip';

      // Originály index 1..N-1 (index 0 je hlavní; do pásu přidáme i index 0,
      // ať se uživatel může vrátit k hlavní fotce přes pás)
      var thumbs = [];
      for (var i = 0; i < anchors.length; i++) {
        thumbs.push(makeAnchor(anchors[i], i, false));
      }

      // Infinite loop — duplikujeme set 2× (1× před, 1× za), originály jdou
      // do středu. Klony mají data-mg-clone="1", aby je lightbox při collect()
      // zfiltroval (deduplikace podle data-index ale i tak zachytí).
      var beforeClones = anchors.map(function(a, i){ return makeAnchor(a, i, true); });
      var afterClones  = anchors.map(function(a, i){ return makeAnchor(a, i, true); });

      // Vložit before-clones v původním pořadí (insertBefore zachová pořadí
      // jen když se odkazujeme na fixní referenci, ne na firstChild)
      var anchorRef = null;
      beforeClones.forEach(function(c){ strip.appendChild(c); });
      thumbs.forEach(function(c){ strip.appendChild(c); });
      afterClones.forEach(function(c){ strip.appendChild(c); });

      wrap.appendChild(strip);

      // Vystředit scroll na originály (= 1/3 celkové šířky)
      function centerStrip(){
        var setW = strip.scrollWidth / 3;
        strip.style.scrollBehavior = 'auto';
        strip.scrollLeft = setW;
      }
      // Vícekrát kvůli lazy načítání obrázků (šířka roste)
      requestAnimationFrame(centerStrip);
      setTimeout(centerStrip, 100);
      setTimeout(centerStrip, 400);
      setTimeout(centerStrip, 1000);

      // Edge-jump pro nekonečný dojem
      var jumping = false;
      strip.addEventListener('scroll', function(){
        if (jumping) return;
        var setW = strip.scrollWidth / 3;
        if (setW < 10) return; // ještě se nenačetlo
        var sl = strip.scrollLeft;
        if (sl < setW * 0.4) {
          jumping = true;
          strip.style.scrollBehavior = 'auto';
          strip.scrollLeft = sl + setW;
          requestAnimationFrame(function(){ jumping = false; });
        } else if (sl > setW * 1.6) {
          jumping = true;
          strip.style.scrollBehavior = 'auto';
          strip.scrollLeft = sl - setW;
          requestAnimationFrame(function(){ jumping = false; });
        }
      }, {passive:true});

      // Resize → re-center
      var resizeT = 0;
      window.addEventListener('resize', function(){
        clearTimeout(resizeT);
        resizeT = setTimeout(centerStrip, 150);
      });
    }

    // Schovat původní gallery děti — necháme je v DOM, ale neviditelné
    Array.prototype.forEach.call(gal.children, function(c){
      c.classList.add('mg-mob-orig-hidden');
    });

    // Vložit naši strukturu jako první potomek galerie
    gal.insertBefore(wrap, gal.firstChild);
  }

  function teardownMobileGallery(gal){
    if (!gal || gal.dataset.mgmDone !== '1') return;
    var wrap = gal.querySelector('.mg-mob');
    if (wrap) wrap.remove();
    Array.prototype.forEach.call(gal.querySelectorAll('.mg-mob-orig-hidden'), function(c){
      c.classList.remove('mg-mob-orig-hidden');
    });
    delete gal.dataset.mgmDone;
  }

  function refreshMobileGalleries(){
    var isMobile = window.matchMedia('(max-width:' + MGM_BREAK + 'px)').matches;
    document.querySelectorAll('.moto-gallery').forEach(function(gal){
      if (isMobile) buildMobileGallery(gal);
      else teardownMobileGallery(gal);
    });
  }

  refreshMobileGalleries();
  var mgmResizeT = 0;
  window.addEventListener('resize', function(){
    clearTimeout(mgmResizeT);
    mgmResizeT = setTimeout(refreshMobileGalleries, 200);
  });
})();
