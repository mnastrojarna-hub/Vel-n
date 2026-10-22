/* ===== MotoGo24 — Rezervace: pobočka podle motorky + výběr motorky s fotkou (2026-10-22) =====
   Jádro js/pages-rezervace*.js je minifikované — tento soubor ho jen doplňuje zvenčí (čte MG._rez,
   nastavuje hodnoty <select> a posílá jim 'change', na který reagují původní handlery):
   1) Vybraná motorka (z ?moto=, konceptu, seznamu i ze seznamu volných pod kalendářem) = vybraná
      i její pobočka (#rez-branch-dropdown) — motorka stojí na konkrétní pobočce.
   2) Změna pobočky při vybrané motorce z jiné pobočky → potvrzení, že se výběr motorky (a termínu)
      zruší; „Zrušit“ vrátí původní pobočku a původní handler vůbec neproběhne.
   3) #rez-moto-dropdown a #rez-avail-dropdown dostanou vlastní rozbalovací seznam s miniaturou
      hlavní fotky, cenou od/den a pobočkou. Nativní <select> zůstává (zdroj pravdy, handlery);
      jen se vizuálně skryje. Vzhled css/rezervace-ux.css. */
(function () {
  'use strict';
  var d = document, w = window, MG = w.MG || {};
  var LG = ((w.MOTOGO_CONFIG || {}).LANG || d.documentElement.lang || 'cs').slice(0, 2);
  var TX = {
    cs: { conf: 'Motorka {moto} stojí na pobočce {branch}. Když pobočku změníš, výběr motorky (i termínu) se zruší. Pokračovat?', from: 'od {p}/den', pick: 'Vybrat motorku', close: 'Zavřít', one: 'Máš vybraný 1 den: {d}', more: 'Chceš jet déle? Klepni v kalendáři na den vrácení.' },
    en: { conf: 'The {moto} is based at {branch}. Changing the branch will clear the bike (and dates). Continue?', from: 'from {p}/day', pick: 'Choose a bike', close: 'Close', one: 'You have 1 day selected: {d}', more: 'Want to ride longer? Tap your return day in the calendar.' },
    de: { conf: 'Die {moto} steht in der Filiale {branch}. Wenn du die Filiale änderst, wird die Auswahl des Motorrads (und des Termins) aufgehoben. Fortfahren?', from: 'ab {p}/Tag', pick: 'Motorrad wählen', close: 'Schließen', one: 'Du hast 1 Tag gewählt: {d}', more: 'Länger fahren? Tippe im Kalender auf den Rückgabetag.' },
    es: { conf: 'La {moto} está en la sucursal {branch}. Si cambias de sucursal, se borrará la moto elegida (y las fechas). ¿Continuar?', from: 'desde {p}/día', pick: 'Elegir moto', close: 'Cerrar', one: 'Tienes 1 día elegido: {d}', more: '¿Quieres más días? Toca en el calendario el día de devolución.' },
    fr: { conf: 'La {moto} se trouve à l’agence {branch}. Si tu changes d’agence, le choix de la moto (et des dates) sera annulé. Continuer ?', from: 'dès {p}/jour', pick: 'Choisir une moto', close: 'Fermer', one: 'Tu as choisi 1 jour : {d}', more: 'Envie de rouler plus longtemps ? Touche le jour de retour dans le calendrier.' },
    nl: { conf: 'De {moto} staat bij vestiging {branch}. Als je de vestiging wijzigt, vervalt de gekozen motor (en de data). Doorgaan?', from: 'vanaf {p}/dag', pick: 'Motor kiezen', close: 'Sluiten', one: 'Je hebt 1 dag gekozen: {d}', more: 'Langer rijden? Tik in de kalender op de inleverdag.' },
    pl: { conf: 'Motocykl {moto} stoi w oddziale {branch}. Zmiana oddziału anuluje wybór motocykla (i terminu). Kontynuować?', from: 'od {p}/dzień', pick: 'Wybierz motocykl', close: 'Zamknij', one: 'Wybrany 1 dzień: {d}', more: 'Chcesz jechać dłużej? Kliknij w kalendarzu dzień zwrotu.' },
    uk: { conf: 'Мотоцикл {moto} стоїть у філії {branch}. Якщо зміниш філію, вибір мотоцикла (і дат) скасується. Продовжити?', from: 'від {p}/день', pick: 'Обрати мотоцикл', close: 'Закрити', one: 'Обрано 1 день: {d}', more: 'Хочеш довше? Торкнись у календарі дня повернення.' }
  }[LG] || null;
  TX = TX || { conf: 'Motorka {moto} stojí na pobočce {branch}. Když pobočku změníš, výběr motorky (i termínu) se zruší. Pokračovat?', from: 'od {p}/den', pick: 'Vybrat motorku', close: 'Zavřít', one: 'Máš vybraný 1 den: {d}', more: 'Chceš jet déle? Klepni v kalendáři na den vrácení.' };
  var SB = ((w.MOTOGO_CONFIG || {}).SUPABASE_URL || '').replace(/\/$/, '');

  function R() { return MG._rez || {}; }
  function moto(id) { var l = R().motos || []; for (var i = 0; i < l.length; i++) if (l[i] && l[i].id === id) return l[i]; return null; }
  function brName(m) { var b = m && m.branches; return b ? String(b.name || b.city || '').replace(/^MotoGo24\s*/i, '') : ''; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function fire(el) { el.dispatchEvent(new Event('change', { bubbles: true })); }
  function selectedMoto() { var r = R(); return moto(r.motoId) || moto(r.selectedMotoId); }

  // Miniatura přes transformační endpoint Supabase (jako PHP imgUrlSized)
  function thumb(m) {
    var src = m && (m.image_url || (Array.isArray(m.images) && m.images[0])) || '';
    if (!src || /^data:/.test(src)) return src;
    var mk = ['/storage/v1/object/public/media/', '/storage/v1/render/image/public/media/'], path = src;
    if (/^https?:\/\//.test(src)) {
      var i = -1, k = 0;
      for (; k < mk.length && i < 0; k++) { i = src.indexOf(mk[k]); if (i >= 0) path = src.slice(i + mk[k].length).split('?')[0]; }
      if (i < 0) return src;
    }
    return SB ? SB + '/storage/v1/render/image/public/media/' + path + '?width=160&quality=60&resize=contain' : src;
  }
  function fromPrice(m) {
    var min = 0;
    ['price_mon', 'price_tue', 'price_wed', 'price_thu', 'price_fri', 'price_sat', 'price_sun', 'price_weekday'].forEach(function (k) {
      var v = Number(m && m[k]) || 0; if (v > 0 && (!min || v < min)) min = v;
    });
    return min ? TX.from.replace('{p}', MG.formatPrice ? MG.formatPrice(min) : min + ' Kč') : '';
  }

  // ---- 1) pobočka podle motorky ----
  function syncBranch() {
    var bd = d.getElementById('rez-branch-dropdown'), md = d.getElementById('rez-moto-dropdown'), m = selectedMoto();
    if (!bd || !m || !m.branch_id || bd.value === m.branch_id) return;
    if (!Array.prototype.some.call(bd.options, function (o) { return o.value === m.branch_id; })) return;
    bd.value = m.branch_id; bd.setAttribute('data-ux-prev', m.branch_id);
    R().branchId = m.branch_id;
    if (md && typeof MG._rezFillMotoOptions === 'function') MG._rezFillMotoOptions(md, m.branch_id, R().motoId || '');
    if (typeof MG._rezRenderCal === 'function' && d.getElementById('rez-calendar') && R().calYear != null) MG._rezRenderCal();
    refresh();
  }

  // ---- 2) potvrzení změny pobočky (capture na dokumentu = před původním handlerem) ----
  d.addEventListener('focusin', function (ev) { var t = ev.target; if (t && t.id === 'rez-branch-dropdown') t.setAttribute('data-ux-prev', t.value); }, true);
  d.addEventListener('change', function (ev) {
    var bd = ev.target;
    if (!bd || bd.id !== 'rez-branch-dropdown') return;
    var m = selectedMoto(), prev = bd.getAttribute('data-ux-prev');
    if (m && m.branch_id && bd.value !== m.branch_id) {
      if (!w.confirm(TX.conf.replace('{moto}', m.model || '').replace('{branch}', brName(m)))) {
        ev.stopImmediatePropagation();
        bd.value = prev != null ? prev : m.branch_id;
        return;
      }
      // „Všechny pobočky“: původní handler motorku nechá (je i ve „všech“) → zrušit ji po něm
      if (!bd.value) setTimeout(function () {
        var md = d.getElementById('rez-moto-dropdown');
        if (md && md.value) { md.value = ''; fire(md); }
        if (R().selectedMotoId) R().selectedMotoId = '';
        refresh();
      }, 0);
    }
    bd.setAttribute('data-ux-prev', bd.value);
    setTimeout(refresh, 0);
  }, true);
  // výběr motorky (hlavní seznam i seznam volných) → po původním handleru dorovnat pobočku
  d.addEventListener('change', function (ev) {
    var id = ev.target && ev.target.id;
    if (id === 'rez-moto-dropdown' || id === 'rez-avail-dropdown') setTimeout(syncBranch, 0);
  });

  // ---- 3) vlastní výběr motorky s miniaturou ----
  var open = null;
  function optHtml(o, sel) {
    var m = o.value ? moto(o.value) : null, img = m ? thumb(m) : '', sub = m ? [brName(m), fromPrice(m)].filter(Boolean).join(' · ') : '';
    return (img ? '<img class="ux-pk-img" src="' + esc(img) + '" alt="" loading="lazy" decoding="async" width="72" height="48">'
      : '<span class="ux-pk-img ux-pk-any" aria-hidden="true">' + (o.value ? '' : '★') + '</span>') +
      '<span class="ux-pk-tx"><span class="ux-pk-n">' + esc(o.textContent) + '</span>' + (sub ? '<span class="ux-pk-s">' + esc(sub) + '</span>' : '') + '</span>' +
      (sel ? '<span class="ux-pk-ok" aria-hidden="true">✓</span>' : '');
  }
  function sync(sel) {
    var b = sel._uxBtn; if (!b) return;
    var o = sel.options[sel.selectedIndex] || sel.options[0];
    var h = o ? optHtml(o, false) + '<span class="ux-pk-chev" aria-hidden="true"></span>' : '';
    if (b._h !== h) { b._h = h; b.innerHTML = h; } // beze změny nesahat do DOM (MutationObserver níže)
  }
  function closeList() {
    if (!open) return;
    var o = open; open = null;
    o.list.remove(); o.ov.remove(); o.btn.setAttribute('aria-expanded', 'false');
    d.documentElement.classList.remove('ux-pk-lock');
  }
  function openList(sel) {
    closeList();
    var btn = sel._uxBtn, ov = d.createElement('div'), list = d.createElement('div');
    ov.className = 'ux-pk-ov'; list.className = 'ux-pk-list'; list.setAttribute('role', 'listbox');
    list.setAttribute('aria-label', TX.pick);
    var h = '<div class="ux-pk-head"><span>' + esc(TX.pick) + '</span><button type="button" class="ux-pk-x" data-x aria-label="' + esc(TX.close) + '">×</button></div><div class="ux-pk-scroll">';
    Array.prototype.forEach.call(sel.options, function (o, i) {
      if (o.disabled && !o.value) return;
      var on = i === sel.selectedIndex;
      h += '<button type="button" class="ux-pk-opt' + (on ? ' is-on' : '') + '" role="option" aria-selected="' + on + '" data-i="' + i + '"' + (o.disabled ? ' disabled' : '') + '>' + optHtml(o, on) + '</button>';
    });
    list.innerHTML = h + '</div>';
    d.body.appendChild(ov); d.body.appendChild(list);
    var r = btn.getBoundingClientRect(), mob = w.innerWidth < 640;
    if (!mob) {
      list.style.top = (r.bottom + w.scrollY + 6) + 'px';
      list.style.left = (r.left + w.scrollX) + 'px';
      list.style.width = r.width + 'px';
    } else d.documentElement.classList.add('ux-pk-lock');
    list.classList.add(mob ? 'is-sheet' : 'is-drop');
    btn.setAttribute('aria-expanded', 'true');
    open = { sel: sel, btn: btn, list: list, ov: ov };
    var cur = list.querySelector('.is-on') || list.querySelector('.ux-pk-opt');
    if (cur) { cur.focus({ preventScroll: !mob }); if (!mob && cur.scrollIntoView) cur.scrollIntoView({ block: 'nearest' }); }
    ov.addEventListener('click', closeList);
    list.addEventListener('click', function (ev) {
      if (ev.target.closest('[data-x]')) { closeList(); btn.focus(); return; }
      var b = ev.target.closest('[data-i]'); if (!b || b.disabled) return;
      var i = +b.getAttribute('data-i');
      closeList(); btn.focus();
      if (i !== sel.selectedIndex) { sel.selectedIndex = i; fire(sel); }
      sync(sel);
    });
    list.addEventListener('keydown', function (ev) {
      if (ev.key === 'Escape') { closeList(); btn.focus(); return; }
      if (ev.key !== 'ArrowDown' && ev.key !== 'ArrowUp') return;
      var all = Array.prototype.slice.call(list.querySelectorAll('.ux-pk-opt:not([disabled])')), k = all.indexOf(d.activeElement);
      ev.preventDefault();
      var n = all[Math.max(0, Math.min(all.length - 1, k + (ev.key === 'ArrowDown' ? 1 : -1)))]; if (n) n.focus();
    });
  }
  function enhance(sel) {
    if (!sel || sel._uxBtn) return;
    var btn = d.createElement('button');
    btn.type = 'button'; btn.className = 'ux-pk-btn'; btn.setAttribute('aria-haspopup', 'listbox'); btn.setAttribute('aria-expanded', 'false');
    var lab = sel.id && d.querySelector('label[for="' + sel.id + '"]');
    if (lab) { lab.id = lab.id || sel.id + '-lbl'; btn.setAttribute('aria-labelledby', lab.id); }
    sel._uxBtn = btn;
    sel.classList.add('ux-pk-native'); sel.setAttribute('tabindex', '-1'); sel.setAttribute('aria-hidden', 'true');
    sel.parentNode.insertBefore(btn, sel);
    sel.parentNode.classList.add('ux-pk-wrap');
    if (lab) lab.addEventListener('click', function (ev) { ev.preventDefault(); btn.focus(); });
    btn.addEventListener('click', function () { if (open && open.sel === sel) closeList(); else openList(sel); });
    sel.addEventListener('change', function () { sync(sel); });
    // programové sel.value = … (původní kód) i přestavění <option> → přepsat tlačítko
    var P = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value'), PI = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'selectedIndex');
    try {
      Object.defineProperty(sel, 'value', { configurable: true, get: function () { return P.get.call(this); }, set: function (v) { P.set.call(this, v); sync(sel); } });
      Object.defineProperty(sel, 'selectedIndex', { configurable: true, get: function () { return PI.get.call(this); }, set: function (v) { PI.set.call(this, v); sync(sel); } });
    } catch (e) { /* starý prohlížeč: tlačítko se srovná při dalším change */ }
    if (w.MutationObserver) new MutationObserver(function () { sync(sel); }).observe(sel, { childList: true, subtree: true });
    sync(sel);
  }
  function refresh() {
    ['rez-moto-dropdown', 'rez-avail-dropdown'].forEach(function (id) { var s = d.getElementById(id); if (s) { enhance(s); sync(s); } });
  }
  w.addEventListener('resize', closeList);

  // ---- 4) jednodenní termín v liště nad kalendářem (1. klik = 1 den, viz pages-rezervace-calendar.js) ----
  if (typeof MG._rezUpdateBanner === 'function' && !MG._rezUpdateBanner._ux) {
    var ub = MG._rezUpdateBanner;
    MG._rezUpdateBanner = function () {
      ub.apply(this, arguments);
      var r = R(), b = d.getElementById('rez-date-banner'), sp = b && b.querySelector('span');
      if (!sp || !r.startDate || r.startDate !== r.endDate) return;
      sp.textContent = TX.one.replace('{d}', MG.formatDate ? MG.formatDate(r.startDate) : r.startDate);
      if (r._rangeOpen) { var h = d.createElement('small'); h.className = 'ux-one-hint'; h.textContent = TX.more; sp.appendChild(d.createElement('br')); sp.appendChild(h); }
    };
    MG._rezUpdateBanner._ux = 1;
  }

  // Formulář staví _rezInit asynchronně (motorky z DB) a seznam volných se překresluje → hlídat DOM
  var app = d.getElementById('rezervace-app'), tries = 0;
  if (app && w.MutationObserver) new MutationObserver(function () { refresh(); }).observe(app, { childList: true, subtree: true });
  (function wait() {
    var md = d.getElementById('rez-moto-dropdown');
    if (md && (R().motos || []).length) { refresh(); syncBranch(); return; }
    if (++tries < 150) setTimeout(wait, 100);
  })();
})();
