/* MotoGo24 — Landing v2 informační stránky (viz landing-info.php): zkrácení
   dlouhých textů s „Číst dál“ (text zůstává v DOM celý) a tlačítka AI asistenta
   (otevřou bublinu chatu; bez bubliny se skryjí). Bez závislostí. */
(function () {
  var d = document;
  function each(sel, fn) { Array.prototype.forEach.call(d.querySelectorAll(sel), fn); }

  // 1) Zkrácení (hero intro na mobilu, dlouhý text v CTA kartě)
  var n = 0;
  each('[data-lpi-clamp]', function (el) {
    el.classList.add('is-clamped');
    if (el.scrollHeight <= el.clientHeight + 4) { el.classList.remove('is-clamped'); return; }
    if (!el.id) el.id = 'lpi-clamp-' + (++n);
    var btn = d.createElement('button');
    btn.type = 'button';
    btn.className = 'lpi-clamp-btn';
    btn.setAttribute('aria-controls', el.id);
    btn.setAttribute('aria-expanded', 'false');
    btn.textContent = el.getAttribute('data-more') || '…';
    btn.addEventListener('click', function () {
      var open = el.classList.toggle('is-clamped') === false;
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
      btn.textContent = el.getAttribute(open ? 'data-less' : 'data-more') || '…';
    });
    el.parentNode.insertBefore(btn, el.nextSibling);
  });

  // 2) AI asistent — tlačítka otevřou bublinu chatu; bez (povolené) bubliny se výzvy skryjí
  function bubble() {
    var b = d.getElementById('motogo-ai-bubble');
    return b && b.style.display !== 'none' ? b : null;
  }
  each('[data-lpi-ai]', function (el) {
    el.addEventListener('click', function () {
      var b = bubble();
      if (b && b.getAttribute('aria-expanded') !== 'true') b.click();
    });
  });
  function check() {
    if (bubble()) return;
    each('[data-lpi-ai-box], button[data-lpi-ai].lpi-ccard', function (el) { el.hidden = true; });
  }
  function later() { setTimeout(check, 1500); }
  if (d.readyState === 'complete') later(); else window.addEventListener('load', later);
})();
