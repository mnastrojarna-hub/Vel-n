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
    var arr = Array.prototype.slice.call(nodes);
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
    root.style.position = 'fixed';
    root.style.top = '0';
    root.style.left = '0';
    root.style.right = '0';
    root.style.bottom = '0';
    root.style.width = '100vw';
    root.style.height = '100vh';
    root.style.zIndex = '99999';
    root.style.display = 'flex';
    document.body.classList.add('mg-lb-open');
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
    imgEl.src = '';
    items = [];
  }

  function next(){ current++; render(); }
  function prev(){ current--; render(); }

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

  // Touch swipe
  var tx = 0, ty = 0, tracking = false;
  root.addEventListener('touchstart', function(e){
    if (e.touches.length !== 1) { tracking = false; return; }
    tracking = true;
    tx = e.touches[0].clientX;
    ty = e.touches[0].clientY;
  }, {passive:true});
  root.addEventListener('touchend', function(e){
    if (!tracking) return;
    tracking = false;
    var t = e.changedTouches[0];
    var dx = t.clientX - tx;
    var dy = t.clientY - ty;
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) {
      if (dx < 0) next(); else prev();
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
})();
