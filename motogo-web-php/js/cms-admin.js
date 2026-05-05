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
      return r.text().then(function (text) {
        var data = null;
        try { data = JSON.parse(text); } catch (_) { data = { raw: text }; }
        // Vždy logni kompletní odpověď do konzole — uživateli stačí F12
        // Console a vidí přesnou PG chybu (detail + code).
        console.log('[cms-save] response', { status: r.status, ok: r.ok, body: data, raw: text });
        return { ok: r.ok, status: r.status, data: data };
      });
    }).then(function (res) {
      if (!res.ok || !res.data || !res.data.success) {
        var d = res.data || {};
        var msg = d.error ? String(d.error) : ('HTTP ' + res.status);
        if (d.detail) msg += ': ' + d.detail;
        if (d.code) msg += ' [' + d.code + ']';
        if (d.raw && !d.error) msg += ': ' + String(d.raw).slice(0, 200);
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
  // U <a> tagů (a libovolného předka, který je odkaz) blokujeme navigaci v edit
  // režimu — typický případ: signpost karta `<a class="gbox" href="/katalog">`
  // s vnořeným `<h3 data-cms-key>` / `<p data-cms-key>` / `<div data-cms-key>`.
  // Bez tohoto by klik na nadpis karty rovnou redirectnul na /katalog
  // a editace by se neuložila. Cmd/Ctrl klik zachová možnost normální navigace.
  function setupInlineEdit() {
    document.addEventListener('click', function (ev) {
      var el = ev.target.closest('[data-cms-key]');
      if (!el) return;
      // Pokud je už edit, neblokujeme
      if (el.getAttribute('contenteditable') === 'true') return;
      // Najdi nejbližší předka <a href> (včetně el samotného) — pokud existuje
      // a uživatel nedrží cmd/ctrl (chce reálně navigovat), zablokuj redirect.
      var anchor = (el.tagName === 'A' && el.hasAttribute('href'))
        ? el
        : el.closest('a[href]');
      if (anchor && !ev.metaKey && !ev.ctrlKey) {
        ev.preventDefault();
        ev.stopPropagation();
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

    var formatBar = renderFormatBar(el, {
      onSave: function () { commit(); },
      onCancel: function () { cancel(); },
    });

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
      if (formatBar) {
        formatBar.destroy();
        formatBar = null;
      }
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
      // Lehké zpoždění, ať klik na toast/lištu nezavře edit dřív než commit.
      setTimeout(function () {
        // Pokud focus přešel do format-baru (color picker, select, button),
        // editaci nezavírej a NEVRACEJ focus zpět — vrácení focusu by zavřelo
        // native <select> dropdown a uživatel by neviděl možnosti velikosti písma.
        // Nechť format bar drží focus dokud uživatel neklikne mimo; potom zase
        // padne onBlur a zavoláme commit().
        var ae = document.activeElement;
        if (formatBar && formatBar.el && ae && (formatBar.el === ae || formatBar.el.contains(ae))) {
          return;
        }
        commit();
      }, 120);
    }
    el.addEventListener('keydown', onKey);
    el.addEventListener('blur', onBlur);
  }

  // ---- Format bar (Word-like toolbar nad editovaným prvkem) ----
  // Plovoucí lišta nad aktuálně editovaným [data-cms-key]: B/I/U/S, barva,
  // zvýraznění, velikost písma, odkaz, vyčistit, Uložit/Zrušit.
  // Příkazy přes document.execCommand → ukládá se HTML přímo do `value` sloupce.
  function renderFormatBar(targetEl, handlers) {
    var bar = document.createElement('div');
    bar.className = 'mg-cms-formatbar';
    bar.setAttribute('contenteditable', 'false');

    // Klik na lištu nesmí ukrást focus (jinak by spadl onBlur a commit).
    // Color input a select potřebují native focus, na ně preventDefault NE.
    bar.addEventListener('mousedown', function (ev) {
      var t = ev.target;
      var isNativeFocus = (t && (t.tagName === 'INPUT' || t.tagName === 'SELECT'));
      if (!isNativeFocus) ev.preventDefault();
    });

    function exec(cmd, val) {
      try {
        targetEl.focus();
        document.execCommand(cmd, false, val == null ? null : val);
      } catch (_) { /* noop */ }
    }

    function makeBtn(label, title, onClick, opts) {
      opts = opts || {};
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'mg-cms-fb-btn'
        + (opts.primary ? ' mg-cms-fb-primary' : '')
        + (opts.danger ? ' mg-cms-fb-danger' : '');
      b.title = title || '';
      b.innerHTML = label;
      b.addEventListener('click', function (ev) {
        ev.preventDefault();
        onClick();
      });
      return b;
    }

    function makeColorPicker(title, defaultColor, onPick) {
      var wrap = document.createElement('label');
      wrap.className = 'mg-cms-fb-color';
      wrap.title = title;
      var icon = document.createElement('span');
      icon.textContent = title.indexOf('Zvýraz') === 0 ? '◼' : 'A';
      icon.style.borderBottom = '3px solid ' + defaultColor;
      var input = document.createElement('input');
      input.type = 'color';
      input.value = defaultColor;
      input.addEventListener('input', function () {
        icon.style.borderBottomColor = input.value;
        onPick(input.value);
      });
      wrap.appendChild(icon);
      wrap.appendChild(input);
      return wrap;
    }

    function makeSelect(title, options, onChange) {
      var sel = document.createElement('select');
      sel.className = 'mg-cms-fb-select';
      sel.title = title;
      options.forEach(function (opt) {
        var o = document.createElement('option');
        o.value = opt[0];
        o.textContent = opt[1];
        sel.appendChild(o);
      });
      sel.addEventListener('change', function () {
        if (sel.value) {
          onChange(sel.value);
          sel.value = '';
          // Vrať focus zpět do editovaného elementu, ať blur nespadne.
          setTimeout(function () { targetEl.focus(); }, 0);
        }
      });
      return sel;
    }

    function sep() {
      var s = document.createElement('span');
      s.className = 'mg-cms-fb-sep';
      return s;
    }

    // Velikost písma
    bar.appendChild(makeSelect('Velikost', [
      ['', 'Velikost'],
      ['1', 'XS'], ['2', 'S'], ['3', 'M'],
      ['4', 'L'], ['5', 'XL'], ['6', 'XXL'], ['7', 'XXXL'],
    ], function (v) { exec('fontSize', v); }));

    bar.appendChild(sep());

    bar.appendChild(makeBtn('<b>B</b>', 'Tučně (Ctrl+B)', function () { exec('bold'); }));
    bar.appendChild(makeBtn('<i>I</i>', 'Kurzíva (Ctrl+I)', function () { exec('italic'); }));
    bar.appendChild(makeBtn('<span style="text-decoration:underline">U</span>', 'Podtržení (Ctrl+U)', function () { exec('underline'); }));
    bar.appendChild(makeBtn('<span style="text-decoration:line-through">S</span>', 'Přeškrtnout', function () { exec('strikeThrough'); }));

    bar.appendChild(sep());

    bar.appendChild(makeColorPicker('Barva textu', '#1a2e22', function (c) { exec('foreColor', c); }));
    bar.appendChild(makeColorPicker('Zvýraznění', '#fef08a', function (c) { exec('hiliteColor', c); }));

    bar.appendChild(sep());

    bar.appendChild(makeBtn('🔗', 'Vložit odkaz', function () {
      var url = window.prompt('URL odkazu (např. https://...)');
      if (url) exec('createLink', url);
    }));
    bar.appendChild(makeBtn('⛓̸', 'Odstranit odkaz', function () { exec('unlink'); }));
    bar.appendChild(makeBtn('⌫', 'Vyčistit formátování', function () { exec('removeFormat'); }));

    bar.appendChild(sep());

    bar.appendChild(makeBtn('Zrušit', 'Esc', function () { handlers.onCancel(); }, { danger: true }));
    bar.appendChild(makeBtn('✓ Uložit', 'Enter', function () { handlers.onSave(); }, { primary: true }));

    document.body.appendChild(bar);

    function reposition() {
      // position: fixed → souřadnice jsou vůči viewportu (nepotřeba scrollY).
      var rect = targetEl.getBoundingClientRect();
      var barH = bar.offsetHeight || 44;
      var barW = bar.offsetWidth || 320;
      var vw = document.documentElement.clientWidth;
      var vh = document.documentElement.clientHeight;

      var top = rect.top - barH - 12;
      if (top < 8) {
        // Nahoře není místo — pod prvek.
        top = rect.bottom + 12;
      }
      // Pokud i pod prvkem mimo viewport, přilep nahoru viewportu.
      if (top + barH > vh - 8) top = Math.max(8, vh - barH - 8);
      if (top < 8) top = 8;

      var left = Math.max(8, rect.left);
      if (left + barW > vw - 8) left = Math.max(8, vw - barW - 8);

      bar.style.top = top + 'px';
      bar.style.left = left + 'px';
    }
    reposition();
    // Repozicuj po prvním renderu (offsetHeight/Width už známe).
    requestAnimationFrame(reposition);
    window.addEventListener('scroll', reposition, true);
    window.addEventListener('resize', reposition);

    return {
      el: bar,
      destroy: function () {
        window.removeEventListener('scroll', reposition, true);
        window.removeEventListener('resize', reposition);
        bar.remove();
      },
    };
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
