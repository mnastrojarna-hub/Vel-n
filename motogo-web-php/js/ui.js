// MotoGo24 — site-wide UI: hash redirect, scroll-top, mobile menu, switchers
(function () {
  if (window.location.hash && window.location.hash.indexOf('#/') === 0) {
    window.location.replace(window.location.hash.substring(1));
  }
  var btn = document.getElementById('Up');
  if (btn) {
    window.addEventListener('scroll', function () {
      btn.classList.toggle('visible', window.scrollY > 400);
    }, { passive: true });
  }
  var menu = document.getElementById('mobile-menu');
  var toggleBtn = document.querySelector('.nav-toggle');
  function setMenu(open) {
    if (!menu) return;
    menu.classList.toggle('open', open);
    document.body.classList.toggle('menu-open', open);
    if (toggleBtn) toggleBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
  }
  if (toggleBtn) {
    toggleBtn.setAttribute('aria-expanded', 'false');
    toggleBtn.setAttribute('aria-controls', 'mobile-menu');
  }
  if (menu) {
    menu.addEventListener('click', function (e) { if (e.target === menu) setMenu(false); });
    menu.querySelectorAll('a').forEach(function (a) {
      if (a.closest('.has-sub')) return;
      a.addEventListener('click', function () { setMenu(false); });
    });
  }
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && menu && menu.classList.contains('open')) setMenu(false);
  });
  window.addEventListener('resize', function () {
    if (window.innerWidth > 768 && menu && menu.classList.contains('open')) setMenu(false);
  }, { passive: true });

  function bindSwitcher(sw, toggleSel, dropSel) {
    var toggle = sw.querySelector(toggleSel);
    var dropdown = sw.querySelector(dropSel);
    if (!toggle || !dropdown) return;
    toggle.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = sw.classList.toggle('open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    document.addEventListener('click', function (e) {
      if (!sw.contains(e.target)) {
        sw.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && sw.classList.contains('open')) {
        sw.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });
  }
  document.querySelectorAll('[data-lang-switcher]').forEach(function (sw) {
    bindSwitcher(sw, '.lang-toggle', '.lang-dropdown');
  });
  document.querySelectorAll('[data-cur-switcher]').forEach(function (sw) {
    bindSwitcher(sw, '.cur-toggle', '.cur-dropdown');
  });

  document.querySelectorAll('.has-sub > a').forEach(function (a) {
    a.addEventListener('click', function (e) {
      if (window.innerWidth <= 768) {
        var li = a.parentElement;
        var wasOpen = li.classList.contains('show');
        document.querySelectorAll('.has-sub').forEach(function (el) { el.classList.remove('show'); });
        if (!wasOpen) { e.preventDefault(); li.classList.add('show'); }
      }
    });
  });
})();
