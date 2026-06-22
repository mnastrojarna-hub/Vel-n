// ===== MotoGo24 — Header app-download popover =====
// Lehký script (~0.5 KB) pro přepínání bublinky se stažením appky (QR + Google
// Play + info o testování a věrnostním programu) v horní hlavičce.
(function () {
  function init() {
    var wrap = document.querySelector('[data-mg-app]');
    if (!wrap) return;
    var btn = wrap.querySelector('[data-mg-app-toggle]');
    var pop = wrap.querySelector('[data-mg-app-pop]');
    var closeBtn = wrap.querySelector('[data-mg-app-close]');
    if (!btn || !pop) return;
    function setOpen(open) {
      pop.hidden = !open;
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    }
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      setOpen(pop.hidden);
    });
    if (closeBtn) closeBtn.addEventListener('click', function () { setOpen(false); });
    document.addEventListener('click', function (e) {
      if (!wrap.contains(e.target)) setOpen(false);
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' || e.key === 'Esc') setOpen(false);
    });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
