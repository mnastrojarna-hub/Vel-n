/* MotoGo24 — kalkulačka ceny: krok „Přistavení“ (vzhled + události). Stav a pravidla: landing-calc-delivery.js,
   CSS css/landing-calc-delivery.css, kontejner [data-kc-dv] z pages/katalog-calc.php. Kreslí se po částech
   (kostra jen při změně režimu), aby psaní adresy nepřišlo o fokus při překreslení kalkulačky.
   Režimy: need = není vybraná motorka (jen nápověda) · lock = motorka, u které formulář přistavení zamyká
   (volby vidět, zamčené, rozbalovací vysvětlení jako ve formuláři) · ok = volby + adresa s našeptávačem.
   Adresa = jen pole s našeptávačem (GPS a mapa zůstávají ve formuláři). Texty voleb, trasy a zámku jsou
   texty rezervačního formuláře (kcDvFormTexts v pages/katalog-calc-delivery.php). */
(function (w) {
  var K = w.MGKC = w.MGKC || {}, d = document, D = K.dv, el = d.querySelector('[data-kc] [data-kc-dv]');
  if (!D || !el) return;
  var X = null, rerender = function () {}, mode = '', sug = { key: '', list: [], i: -1, t: 0 };
  var esc = function (s) { return K.esc(s); };
  function q(s) { return el.querySelector(s); }
  function mg() { return w.MG || {}; }
  function setHtml(n, h) { if (n && n._h !== h) { n.innerHTML = h; n._h = h; } }

  function opt(key, title, sub, locked) {
    return '<label class="kc-dv-opt' + (locked ? ' is-locked' : '') + '"><input type="checkbox"' + (locked ? ' disabled' : ' data-dv="' + key + '"') + '>' +
      '<span class="kc-dv-in"><span class="kc-dv-box" aria-hidden="true">' + K.ico('check') + '</span><span class="kc-dv-tx"><span class="kc-dv-t">' + esc(title) + '</span>' +
      '<span class="kc-dv-s">' + esc(sub) + '</span></span></span></label>';
  }
  function addr(key, ph) {
    return '<input type="text" class="kc-dv-addr" data-dv-addr="' + key + '" placeholder="' + esc(ph) + '" aria-label="' + esc(ph) + '" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="kc-dv-list-' + key + '" autocomplete="off" spellcheck="false" enterkeyhint="search" maxlength="200">' +
      '<ul class="kc-dv-list" id="kc-dv-list-' + key + '" data-dv-list="' + key + '" role="listbox" hidden></ul><p class="kc-dv-route" data-dv-route="' + key + '" aria-live="polite" hidden></p>';
  }
  function build(m) {
    mode = m; sug.list = []; sug.key = '';
    el.hidden = m === 'off';
    if (m === 'off') { el.innerHTML = ''; return; }
    var T = X.T, r = K.dvRate(), sub = K.tpl(T.dv_sub, { base: X.money(r.base), perKm: X.money(r.perKm) });
    var h = '<p class="kc-label"><span class="kc-n">' + esc(el.getAttribute('data-n') || '') + '</span>' + esc(T.step_delivery) + '</p>';
    if (m === 'need') h += '<p class="kc-dv-hint">' + esc(T.dv_need_moto) + '</p>';
    else if (m === 'lock') {
      h += opt('', T.dv_on, sub, true) + opt('', T.dv_ro, sub, true) +
        '<div class="kc-dv-lock"><button type="button" class="kc-dv-lock-h" data-dv-lock aria-expanded="' + (D.cut ? 'true' : 'false') + '"><span class="kc-dv-lock-i" aria-hidden="true">&#9432;</span>' +
        '<span class="kc-dv-lock-t">' + esc(T.dv_lock) + '</span>' + K.ico('chev') + '</button><p class="kc-dv-lock-b"' + (D.cut ? '' : ' hidden') + '>' + esc(T.dv_lock_text) + '</p></div>';
    } else {
      h += opt('on', T.dv_on, sub) + '<div class="kc-dv-panel" data-dv-panel="d" hidden>' + addr('d', T.dv_addr) +
        '<label class="kc-dv-chk"><input type="checkbox" data-dv="same"><span>' + esc(T.dv_same) + '</span></label>' +
        '<p class="kc-dv-info">' + esc(T.dv_lead) + '</p><p class="kc-dv-warn" data-dv-warn role="status" hidden></p></div>' +
        opt('ro', T.dv_ro, sub) + '<div class="kc-dv-panel" data-dv-panel="r" hidden>' + addr('r', T.dv_raddr) + '</div>';
    }
    el.innerHTML = h;
  }
  // Řádek trasy: stejné údaje (a stejné texty) jako rámeček trasy ve formuláři — MG._renderRouteInfo
  function routeHtml(key) {
    var s = D[key], T = X.T, r = K.dvRate(), br = mg()._BRANCH_FROM_ADDRESS || '', p = { base: X.money(r.base), perKm: X.money(r.perKm) };
    if (s.st === 'wait') return '<span class="kc-spin" aria-hidden="true"></span><span>' + esc(K.tpl(T.dv_wait, { branch: br })) + '</span>';
    if (s.st === 'err') { p.kind = key === 'd' ? T.dv_kind_d : T.dv_kind_r; return '<span>' + esc(K.tpl(T.dv_err, p)) + '</span>'; }
    if (s.st !== 'ok') return '';
    var km = K.dvKm(s.km);
    p.km = km; p.total = X.money(mg()._calcDeliveryFee(s.km));
    return '<b>' + esc(K.tpl(T.dv_fast, { branch: br, km: km, drive: s.min ? ' ' + K.tpl(T.dv_drive, { min: s.min }) : '' })) + '</b><span>' + esc(K.tpl(T.dv_calc, p)) + '</span>';
  }
  function update() {
    var st = d.querySelector('[data-kc] [data-kc-dvstep]');
    if (st) st.classList.toggle('is-done', K.dvQuery(X).length > 0);
    if (mode !== 'ok') return;
    [['on', D.on], ['same', D.same], ['ro', D.ro]].forEach(function (c) { var i = q('[data-dv="' + c[0] + '"]'); if (i) i.checked = c[1]; });
    [['d', D.on], ['r', D.ro]].forEach(function (c) {
      var key = c[0], s = D[key], p = q('[data-dv-panel="' + key + '"]'), i = q('[data-dv-addr="' + key + '"]'), rt = q('[data-dv-route="' + key + '"]'), h = routeHtml(key);
      p.hidden = !c[1];
      if (i && d.activeElement !== i && i.value !== s.a) i.value = s.a;
      setHtml(rt, h); rt.hidden = !h; rt.className = 'kc-dv-route' + (s.st ? ' is-' + s.st : '');
    });
    var wn = q('[data-dv-warn]'), ld = K.dvLead(X), wt = ld === 'late' ? X.T.dv_today : (ld === 'soon' ? X.T.dv_soon : '');
    setHtml(wn, esc(wt)); wn.hidden = !wt;
  }
  K.dvRender = function (ctx, render) {
    X = ctx; rerender = render;
    var m = !K.dvReady() ? 'off' : (!X.S.moto ? 'need' : (K.dvBlocked(X) ? 'lock' : 'ok'));
    if (m !== mode) build(m);
    update();
    K.dvSave(X);
  };

  // --- našeptávač adres (MG._mapySuggest, 220 ms po dopsání; ↑ ↓ Enter Esc jako ve formuláři) ---
  function listEl(key) { return q('[data-dv-list="' + key + '"]'); }
  function drawList() {
    var l = listEl(sug.key);
    if (!l) return;
    l.innerHTML = sug.list.map(function (x, i) {
      return '<li role="option" data-i="' + i + '"' + (i === sug.i ? ' class="is-on" aria-selected="true"' : '') + '><b>' + esc(x.label) + '</b>' + (x.description ? '<small>' + esc(x.description) + '</small>' : '') + '</li>';
    }).join('');
    l.hidden = !sug.list.length;
    var inp = q('[data-dv-addr="' + sug.key + '"]');
    if (inp) inp.setAttribute('aria-expanded', sug.list.length ? 'true' : 'false');
  }
  function closeList() { clearTimeout(sug.t); sug.list = []; sug.i = -1; drawList(); }
  function pick(inp, hit) {
    var key = sug.key, v = hit.full || hit.label || '';
    closeList();
    inp.value = v;
    K.dvAddr(key, v, hit, rerender);
    inp.blur();
  }
  el.addEventListener('input', function (ev) {
    var inp = ev.target, key = inp.getAttribute && inp.getAttribute('data-dv-addr');
    if (!key) return;
    if (sug.key !== key) closeList();
    sug.key = key; clearTimeout(sug.t);
    var v = inp.value;
    if (!v || v.trim().length < 2) { closeList(); return; }
    sug.t = setTimeout(function () {
      mg()._mapySuggest(v, 8).then(function (l) { if (inp.value === v && d.activeElement === inp) { sug.list = l || []; sug.i = -1; drawList(); } });
    }, 220);
  });
  el.addEventListener('change', function (ev) {
    var t = ev.target, k = t.getAttribute && t.getAttribute('data-dv'), key = t.getAttribute && t.getAttribute('data-dv-addr');
    if (key) { if (t.value.trim() !== D[key].a) K.dvAddr(key, t.value, null, rerender); return; }
    if (!k) return;
    // stejné vazby jako ve formuláři: „vrácení jinde“ ruší „na stejné adrese“ a naopak
    if (k === 'on') D.on = t.checked;
    else if (k === 'ro') { D.ro = t.checked; if (D.ro) D.same = false; }
    else if (k === 'same') { D.same = t.checked; if (D.same) D.ro = false; }
    rerender();
  });
  el.addEventListener('keydown', function (ev) {
    var inp = ev.target, key = inp.getAttribute && inp.getAttribute('data-dv-addr');
    if (!key) return;
    var n = sug.key === key ? sug.list.length : 0;
    if (ev.key === 'Escape') { closeList(); return; }
    if (ev.key === 'Enter') { ev.preventDefault(); if (n && sug.i >= 0) pick(inp, sug.list[sug.i]); else { closeList(); inp.blur(); } return; }
    if (!n || (ev.key !== 'ArrowDown' && ev.key !== 'ArrowUp')) return;
    ev.preventDefault();
    sug.i = ev.key === 'ArrowDown' ? Math.min(n - 1, sug.i + 1) : Math.max(0, sug.i - 1);
    drawList();
  });
  // mousedown (ne click): pole zůstane ve fokusu, výběr proběhne dřív než blur → change
  el.addEventListener('mousedown', function (ev) {
    var li = ev.target.closest && ev.target.closest('.kc-dv-list li');
    if (!li) return;
    ev.preventDefault();
    var inp = q('[data-dv-addr="' + sug.key + '"]'), hit = sug.list[+li.getAttribute('data-i')];
    if (inp && hit) pick(inp, hit);
  });
  el.addEventListener('click', function (ev) {
    var b = ev.target.closest && ev.target.closest('[data-dv-lock]');
    if (!b) return;
    var body = b.parentNode.querySelector('.kc-dv-lock-b'), open = b.getAttribute('aria-expanded') === 'true';
    b.setAttribute('aria-expanded', open ? 'false' : 'true');
    if (body) body.hidden = open;
  });
  el.addEventListener('focusout', function (ev) { if (ev.target.getAttribute && ev.target.getAttribute('data-dv-addr')) closeList(); });
  d.addEventListener('mousedown', function (ev) { if (sug.list.length && !(ev.target.closest && ev.target.closest('.kc-dv-list,.kc-dv-addr'))) closeList(); });
})(window);
