/* ===== MotoGo24 — CMS admin overlay =====
 * Načítá se jen pro adminy (cookie `mg_cms_admin=1` nastavila PHP po ověření tokenu).
 * - Zvýrazní všechny prvky s `data-cms-key`.
 * - Pokud je v URL `?cms_highlight=<klíč>`, najde odpovídající prvek, scrollne k němu
 *   a obarví ho výrazně (oranžový pulzující rámeček).
 * - Inline edit: klik na editovatelný prvek ho udělá `contenteditable`. Enter (bez
 *   shiftu) uloží přes edge funkci `cms-save` (token + auto-překlad), Esc zruší.
 *   Po uložení toast „✓ Uloženo · 🌍 překlady na cestě".
 * - Vpravo dole toolbar s informací a tlačítkem „Vypnout admin".
 */
(function () {
  'use strict';

  if (!document.cookie.split('; ').some(c => c.startsWith('mg_cms_admin=1'))) return;

  var cfg = window.MG_CMS_ADMIN || {};
  var highlightKey = (cfg.highlight || '').trim();
  var token = cfg.token || '';
  var apiUrl = cfg.apiUrl || '';
  var canSave = !!(token && apiUrl);

  function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // ---- Toast ----
  function toast(message, type) {
    var t = document.createElement('div');
    t.className = 'mg-cms-toast' + (type === 'error' ? ' mg-cms-toast-error' : '');
    t.textContent = message;
    document.body.appendChild(t);
    requestAnimationFrame(function () { t.classList.add('mg-cms-toast-show'); });
    setTimeout(function () {
      t.classList.remove('mg-cms-toast-show');
      setTimeout(function () { t.remove(); }, 250);
    }, 2400);
  }

  // ---- Save přes edge funkci cms-save ----
  function saveValue(key, value) {
    if (!canSave) {
      toast('⚠ Token chybí — ulož v Velíně', 'error');
      return Promise.reject(new Error('no_token'));
    }
    return fetch(apiUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: token, key: key, value: value }),
    }).then(function (r) {
      return r.json().then(function (data) { return { ok: r.ok, status: r.status, data: data }; });
    }).then(function (res) {
      if (!res.ok || !res.data || !res.data.success) {
        var d = res.data || {};
        var msg = d.error ? String(d.error) : ('HTTP ' + res.status);
        if (d.detail) msg += ': ' + d.detail;
        if (d.code) msg += ' [' + d.code + ']';
        throw new Error(msg);
      }
      return res.data;
    }).catch(function (err) {
      // Fetch failure (network / CORS) má jiný error tvar — zlepšíme info pro adminu.
      if (err && err.name === 'TypeError') {
        throw new Error('CORS/síťová chyba — edge funkce cms-save není správně nasazená. Spusť: supabase functions deploy cms-save --no-verify-jwt');
      }
      throw err;
    });
  }

  // ---- Inline edit ----
  // Pro každý [data-cms-key]: na click → contenteditable, Enter uloží, Esc zruší.
  // U <a> tagů blokujeme navigaci v edit režimu.
  function setupInlineEdit() {
    document.addEventListener('click', function (ev) {
      var el = ev.target.closest('[data-cms-key]');
      if (!el) return;
      // Pokud je už edit, neblokujeme
      if (el.getAttribute('contenteditable') === 'true') return;
      // U odkazů blokuj navigaci, ale jen jednou (umožni druhý click pro skutečnou navigaci pomocí cmd/ctrl).
      if (el.tagName === 'A' && !ev.metaKey && !ev.ctrlKey) {
        ev.preventDefault();
      }
      startEdit(el);
    }, true);
  }

  function startEdit(el) {
    var key = el.getAttribute('data-cms-key');
    if (!key) return;
    var original = el.innerHTML;
    el.setAttribute('contenteditable', 'true');
    el.dataset.cmsOriginal = original;
    el.classList.add('mg-cms-editing');
    el.focus();
    // Select all on first focus pro pohodlí
    try {
      var range = document.createRange();
      range.selectNodeContents(el);
      var sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    } catch (_) { /* noop */ }

    var saving = false;

    function commit() {
      if (saving) return;
      var newVal = el.innerHTML;
      // <br> → \n pro stringovou hodnotu, ale nech HTML jak je (web ho jako HTML i čte).
      // Plain text strip pokud původní hodnota byla jednoduchý text bez tagů — heuristika.
      // Bezpečnější: posíláme HTML jak je, web už HTML rendruje.
      if (newVal === el.dataset.cmsOriginal) {
        cleanup();
        return;
      }
      saving = true;
      el.classList.add('mg-cms-saving');
      saveValue(key, newVal).then(function (resp) {
        toast('✓ Uloženo' + (resp.translation === 'queued' ? ' · 🌍 překlady na cestě' : ''));
        delete el.dataset.cmsOriginal;
        cleanup();
      }).catch(function (err) {
        toast('✗ Chyba: ' + (err.message || 'nelze uložit'), 'error');
        // Vrať původní obsah
        el.innerHTML = el.dataset.cmsOriginal || '';
        delete el.dataset.cmsOriginal;
        cleanup();
      });
    }

    function cancel() {
      el.innerHTML = el.dataset.cmsOriginal || el.innerHTML;
      delete el.dataset.cmsOriginal;
      cleanup();
    }

    function cleanup() {
      el.removeAttribute('contenteditable');
      el.classList.remove('mg-cms-editing');
      el.classList.remove('mg-cms-saving');
      el.removeEventListener('keydown', onKey);
      el.removeEventListener('blur', onBlur);
    }

    function onKey(ev) {
      if (ev.key === 'Enter' && !ev.shiftKey) {
        ev.preventDefault();
        commit();
      } else if (ev.key === 'Escape') {
        ev.preventDefault();
        cancel();
      }
    }
    function onBlur() {
      // Lehké zpoždění, ať klik na toast nezavře edit dřív než commit.
      setTimeout(commit, 80);
    }
    el.addEventListener('keydown', onKey);
    el.addEventListener('blur', onBlur);
  }

  // ---- Highlight cílového klíče ----
  function focusTarget() {
    if (!highlightKey) return;
    var safe = window.CSS && CSS.escape ? CSS.escape(highlightKey) : highlightKey.replace(/"/g, '\\"');
    var el = document.querySelector('[data-cms-key="' + safe + '"]');
    if (!el) return;
    el.classList.add('mg-cms-target');
    try {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    } catch (e) {
      el.scrollIntoView();
    }
    setTimeout(function () { el.classList.remove('mg-cms-target'); }, 8000);
  }

  // ---- Floating toolbar ----
  function renderToolbar() {
    var bar = document.createElement('div');
    bar.className = 'mg-cms-toolbar';
    bar.setAttribute('role', 'region');
    bar.setAttribute('aria-label', 'Velín CMS admin režim');

    var count = $all('[data-cms-key]').length;
    var html = ''
      + '<div class="mg-cms-title">⚡ Velín CMS</div>'
      + '<div class="mg-cms-info">Inline edit aktivní · ' + count + ' prvků</div>'
      + '<div class="mg-cms-info" style="font-weight:400;font-size:10px">'
      + '  <strong>Klik</strong> na text · <strong>Enter</strong> uložit · <strong>Esc</strong> zrušit'
      + '</div>';
    if (!canSave) {
      html += '<div class="mg-cms-info" style="color:#fca5a5">⚠ Token nedostupný — edit nelze uložit. Otevři Velín a zkontroluj <code>cms_admin_token</code> v <code>app_settings</code>.</div>';
    }
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
        if (history.length > 1) history.back();
        else window.close();
      }
    });

    document.body.appendChild(bar);
  }

  function init() {
    renderToolbar();
    focusTarget();
    setupInlineEdit();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
