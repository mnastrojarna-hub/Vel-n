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
    // Když je galerie na mobilu nahrazena sliderem, originální .moto-photo
    // a .moto-thumbs-wrap dostanou .moto-mobile-hide a jejich anchory bychom
    // dvakrát namixovali do lightboxu — odfiltrovat.
    var arr = Array.prototype.slice.call(nodes).filter(function(a){
      return !a.closest('.moto-mobile-hide');
    });
    // Deduplikace podle data-index — zachová jediný anchor pro každý index
    // (ten první v DOM pořadí). Pojistka pro případ, že by se na mobile
    // zachovaly originály i slider naráz.
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

  // ===== Mobile gallery slider (jedna velká fotka + tečky pod) =====
  // Na mobilu (≤768 px) je původní layout (velká fotka nad pásem miniatur)
  // matoucí — fotky vypadají naskládané pod sebou bez oddělení. Místo toho
  // sestavíme jeden full-width swipe slider se scroll-snap a tečkami pod.
  // Klepnutí na slide otevře lightbox (přes existující data-gallery delegaci).
  var MOBILE_GALLERY_BREAKPOINT = 768;

  function setupMobileGallery(gal){
    if (!gal || gal.dataset.mgMobileSetup === '1') return;
    var anchors = Array.prototype.slice.call(gal.querySelectorAll('a[data-gallery]'));
    if (!anchors.length) return;
    gal.dataset.mgMobileSetup = '1';

    var slider = document.createElement('div');
    slider.className = 'moto-mobile-slider';

    var track = document.createElement('div');
    track.className = 'moto-mobile-track';

    anchors.forEach(function(a, i){
      var srcImg = a.querySelector('img');
      if (!srcImg) return;
      var slide = document.createElement('a');
      slide.className = 'moto-mobile-slide';
      slide.href = a.getAttribute('href') || srcImg.src;
      slide.setAttribute('data-gallery', a.getAttribute('data-gallery') || 'moto');
      slide.setAttribute('data-index', String(i));
      var lbl = a.getAttribute('aria-label');
      if (lbl) slide.setAttribute('aria-label', lbl);
      var img = document.createElement('img');
      img.src = srcImg.getAttribute('src') || srcImg.src;
      img.alt = srcImg.getAttribute('alt') || '';
      img.loading = i === 0 ? 'eager' : 'lazy';
      img.decoding = 'async';
      slide.appendChild(img);
      track.appendChild(slide);
    });

    slider.appendChild(track);

    if (anchors.length > 1) {
      var dots = document.createElement('div');
      dots.className = 'moto-mobile-dots';
      dots.setAttribute('aria-hidden', 'true');
      for (var j = 0; j < anchors.length; j++) {
        var d = document.createElement('span');
        d.className = 'moto-mobile-dot' + (j === 0 ? ' active' : '');
        dots.appendChild(d);
      }
      slider.appendChild(dots);

      var rafId = 0;
      track.addEventListener('scroll', function(){
        if (rafId) return;
        rafId = requestAnimationFrame(function(){
          rafId = 0;
          var w = track.clientWidth;
          if (!w) return;
          var idx = Math.round(track.scrollLeft / w);
          var ds = slider.querySelectorAll('.moto-mobile-dot');
          for (var k = 0; k < ds.length; k++) {
            ds[k].classList.toggle('active', k === idx);
          }
        });
      }, {passive:true});
    }

    // Schováme původní velkou fotku i pás miniatur — slider je nahrazuje.
    var photo = gal.querySelector('.moto-photo');
    if (photo) photo.classList.add('moto-mobile-hide');
    var thumbsWrap = gal.querySelector('.moto-thumbs-wrap');
    if (thumbsWrap) thumbsWrap.classList.add('moto-mobile-hide');

    gal.insertBefore(slider, gal.firstChild);
  }

  function teardownMobileGallery(gal){
    if (!gal || gal.dataset.mgMobileSetup !== '1') return;
    var slider = gal.querySelector('.moto-mobile-slider');
    if (slider) slider.remove();
    var hidden = gal.querySelectorAll('.moto-mobile-hide');
    hidden.forEach(function(h){ h.classList.remove('moto-mobile-hide'); });
    delete gal.dataset.mgMobileSetup;
  }

  function refreshMobileGalleries(){
    var isMobile = window.matchMedia('(max-width:' + MOBILE_GALLERY_BREAKPOINT + 'px)').matches;
    document.querySelectorAll('.moto-gallery').forEach(function(gal){
      if (isMobile) setupMobileGallery(gal);
      else teardownMobileGallery(gal);
    });
  }

  refreshMobileGalleries();
  var resizeTimer = 0;
  window.addEventListener('resize', function(){
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(refreshMobileGalleries, 150);
  });
})();
