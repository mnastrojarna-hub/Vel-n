/* ===== MotoGo24 — CMS admin overlay =====
 * Načítá se jen pro adminy (cookie `mg_cms_admin=1` nastavila PHP po ověření tokenu).
 * - Zvýrazní všechny prvky s `data-cms-key`.
 * - Pokud je v URL `?cms_highlight=<klíč>`, najde odpovídající prvek, scrollne k němu
 *   a obarví ho výrazně (oranžový pulzující rámeček).
 * - Vpravo dole vyrenderuje toolbar s informací a tlačítkem pro vypnutí admin režimu.
 */
(function () {
  'use strict';

  if (!document.cookie.split('; ').some(c => c.startsWith('mg_cms_admin=1'))) return;

  var cfg = window.MG_CMS_ADMIN || {};
  var highlightKey = (cfg.highlight || '').trim();

  function $(sel, root) { return (root || document).querySelector(sel); }
  function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  function focusTarget() {
    if (!highlightKey) return;
    // CSS.escape pro klíče s tečkami (validní v atributu, neproblém pro selektor,
    // ale escape je bezpečné).
    var safe = window.CSS && CSS.escape ? CSS.escape(highlightKey) : highlightKey.replace(/"/g, '\\"');
    var el = document.querySelector('[data-cms-key="' + safe + '"]');
    if (!el) return;
    el.classList.add('mg-cms-target');
    try {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    } catch (e) {
      el.scrollIntoView();
    }
    // Po 8 vteřinách puls vypneme, ať to neblbne navždy.
    setTimeout(function () { el.classList.remove('mg-cms-target'); }, 8000);
  }

  function renderToolbar() {
    var bar = document.createElement('div');
    bar.className = 'mg-cms-toolbar';
    bar.setAttribute('role', 'region');
    bar.setAttribute('aria-label', 'Velín CMS admin režim');

    var count = $all('[data-cms-key]').length;
    var html = ''
      + '<div class="mg-cms-title">⚡ Velín CMS</div>'
      + '<div class="mg-cms-info">Admin režim aktivní · ' + count + ' editovatelných prvků</div>';
    if (highlightKey) {
      html += '<div class="mg-cms-info" title="Aktuálně zvýrazněno">🎯 ' + escapeHtml(highlightKey) + '</div>';
    }
    html += '<button type="button" class="mg-cms-secondary" data-act="back">↩ Zpět do Velínu</button>';
    html += '<button type="button" data-act="logout">Vypnout admin</button>';
    bar.innerHTML = html;

    bar.addEventListener('click', function (ev) {
      var t = ev.target;
      if (!t || !t.dataset) return;
      if (t.dataset.act === 'logout') {
        var url = new URL(window.location.href);
        url.searchParams.set('cms_admin_logout', '1');
        url.searchParams.delete('cms_highlight');
        window.location.href = url.toString();
      } else if (t.dataset.act === 'back') {
        // Zpět tam, odkud admin přišel — nebo prostě window.close (neotevřeno z jiného tabu = no-op).
        if (history.length > 1) history.back();
        else window.close();
      }
    });

    document.body.appendChild(bar);
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function init() {
    renderToolbar();
    focusTarget();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
