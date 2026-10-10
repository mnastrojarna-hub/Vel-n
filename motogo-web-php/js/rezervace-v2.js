/* ===== MotoGo24 — Rezervace v2: JEN prezentace (krokový ukazatel, souhrn ceny, animace) =====
   Načítá ho pages/rezervace.php jen při landingV2Enabled() (body.rez-v2). Logiku js/pages-rezervace*.js
   nemění: DOM a stav (MG._rez) jen čte, prvkům formuláře nanejvýš přidá třídy (rz-*); vlastní prvky
   (.rz-side) leží MIMO #rezervace-app. Tlačítko souhrnu jen posune na skutečné CTA (nic neodesílá).
   Smazání souboru = původní chování. Vzhled: css/rezervace-v2.css. */
(function () {
  'use strict';
  var d = document, w = window, app = d.getElementById('rezervace-app');
  if (!app || !d.body.classList.contains('rez-v2') || !app.parentNode) return;
  var host = app.parentNode, AP = Array.prototype;
  var RM = !!(w.matchMedia && w.matchMedia('(prefers-reduced-motion: reduce)').matches);
  function T(k) { var v = (w.MG_I18N || {})[k]; return typeof v === 'string' ? v.replace(/<[^>]*>/g, '') : ''; }
  function tx(e) { return e ? (e.textContent || '').replace(/\s+/g, ' ').trim() : ''; }
  function own(e) { var s = ''; if (e) for (var n = e.firstChild; n; n = n.nextSibling) if (n.nodeType === 3) s += n.nodeValue; return s.replace(/\s+/g, ' ').trim(); }
  function vis(e) { return !!(e && e.getClientRects().length); }
  function mk(tag, cls) { var e = d.createElement(tag); if (cls) e.className = cls; return e; }
  function tog(e, c, on) { if (e.classList.contains(c) !== !!on) e.classList.toggle(c, !!on); }

  // --- vlastní prvky (před #rezervace-app, na mobilu display:contents → lišta nahoře + dole) ---
  var side = mk('div', 'rz-side'), inn = mk('div', 'rz-side-in'), steps = mk('div', 'rz-steps'), list = mk('ol');
  var sum = mk('div', 'rz-sum'), rows = mk('dl', 'rz-sum-rows'), tot = mk('div', 'rz-sum-tot');
  var totL = mk('span', 'rz-sum-tl'), totV = mk('strong', 'rz-sum-tv'), totX = mk('span', 'rz-sum-tx'), go = mk('button', 'rz-sum-go');
  go.type = 'button'; steps.hidden = sum.hidden = true;
  steps.appendChild(list); tot.appendChild(totL); tot.appendChild(totV); tot.appendChild(totX);
  sum.appendChild(rows); sum.appendChild(tot); sum.appendChild(go);
  inn.appendChild(steps); inn.appendChild(sum); side.appendChild(inn); host.insertBefore(side, app);

  var secs = [], sig = '', cur = -1, seen = typeof WeakSet === 'function' ? new WeakSet() : null, ctaEl = null, near = null;
  var rv = !RM && 'IntersectionObserver' in w ? new IntersectionObserver(function (es) {
    es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('rz-rv-in'); rv.unobserve(e.target); } });
  }, { rootMargin: '0px 0px -6% 0px' }) : null;

  function sections() {
    return AP.filter.call(app.querySelectorAll('.rez-section'), function (s) { return vis(s) && s.querySelector('.rez-section-head h2'); });
  }
  function head(s) { return [tx(s.querySelector('.rez-step-num')), tx(s.querySelector('.rez-section-head h2'))]; }
  function buildSteps(ss) {
    var g = ss.map(function (s) { return head(s).join('|'); }).join('#');
    if (g === sig) return; sig = g; cur = -1; list.textContent = '';
    ss.forEach(function (s, i) {
      var h = head(s), li = mk('li'), b = mk('button', 'rz-step'), n = mk('span', 'rz-step-n'), t = mk('span', 'rz-step-t');
      b.type = 'button'; n.textContent = h[0] || String(i + 1); t.textContent = h[1];
      n.setAttribute('aria-hidden', 'true'); b.appendChild(n); b.appendChild(t); li.appendChild(b); list.appendChild(li);
      b.addEventListener('click', function () { s.scrollIntoView({ behavior: RM ? 'auto' : 'smooth', block: 'start' }); });
    });
    steps.hidden = !ss.length;
  }
  // nové karty (start, krok 2, zpět): viditelné naskočí postupně, níže se odhalí při scrollu
  function animateNew(ss) {
    if (RM || !seen) return;
    var k = 0, vh = w.innerHeight || 800;
    ss.forEach(function (s) {
      if (seen.has(s)) return; seen.add(s);
      if (s.getBoundingClientRect().top < vh) s.classList.add('rz-enter', 'rz-d' + Math.min(k++, 5));
      else if (rv) { s.classList.add('rz-rv'); rv.observe(s); }
    });
  }

  function fmtD(v) { try { return w.MG && w.MG.formatDate ? w.MG.formatDate(v) : v; } catch (e) { return v; } }
  function selTx(id) { var s = d.getElementById(id); return s && s.selectedIndex >= 0 && s.options[s.selectedIndex] ? tx(s.options[s.selectedIndex]) : ''; }
  function val(id, card) { var i = d.getElementById(id); return i && i.value && vis(d.getElementById(card)) ? i.value : ''; }
  function totLabel() { var t = T('rez.totalPrice'), i = t.indexOf('{price}'); return i < 0 ? '' : t.slice(0, i).replace(/[\s:：]+$/, ''); }
  function totValue(s) {
    var t = T('rez.totalPrice'), i = t.indexOf('{price}'), pre = i < 0 ? '' : t.slice(0, i), post = i < 0 ? '' : t.slice(i + 7);
    if (pre && s.indexOf(pre) === 0) s = s.slice(pre.length);
    if (post && s.slice(-post.length) === post) s = s.slice(0, -post.length);
    return s.trim();
  }
  // souhrn: co je vybráno (jen čtení DOM / MG._rez) — motorka, termín, časy, výbava a služby
  function rowsData() {
    var R = (w.MG && w.MG._rez) || {}, id = R.motoId || R.selectedMotoId, m = null, out = [], ex = [], lc = [];
    (R.motos || []).forEach(function (x) { if (x && x.id === id) m = x; });
    var br = (m && m.branches && (m.branches.name || m.branches.city)) || (d.getElementById('rez-branch-dropdown') || {}).value && selTx('rez-branch-dropdown');
    var dt = R.startDate ? fmtD(R.startDate) + ' – ' + (R.endDate ? fmtD(R.endDate) : '…') : '';
    out.push([T('rez.steps.metaMotoTerm'), [(m && m.model) || selTx('rez-moto-dropdown'), br, dt]]);
    out.push([T('rez.pickup.title'), [val('rez-pickup-time', 'rez-pickup-time-card')]]);
    out.push([T('rez.return.expectedTitle'), [val('rez-return-time', 'rez-return-time-card')]]);
    AP.forEach.call(app.querySelectorAll('.rez-loc-card'), function (c) { var i = c.querySelector('input'); if (i && i.checked && vis(c)) lc.push(own(c.querySelector('.rez-loc-title'))); });
    if (!lc.length) lc.push(own(app.querySelector('.rez-loc-card-info .rez-loc-title')));
    out.push([T('rez.step.location'), lc]);
    AP.forEach.call(app.querySelectorAll('.gear-card'), function (c) { var i = c.querySelector('.gear-head input'); if (i && i.checked && vis(c) && !c.classList.contains('disabled')) ex.push(own(c.querySelector('.gear-title'))); });
    if (ex.length) out.push([T('rez.step.gear'), ex]);
    return out.filter(function (r) { r[1] = r[1].filter(Boolean); return r[0] && r[1].length; });
  }
  function priceInfo() {
    var pv = d.getElementById('rez-price-preview');
    if (pv && vis(pv.parentNode)) {
      var b = pv.firstElementChild;
      return { form: 1, main: b ? totValue(own(b)) : '', extra: b ? AP.map.call(b.children, tx).filter(Boolean).join(' · ') : '', cta: d.querySelector('#rez-form .rez-cta') };
    }
    var a = app.querySelector('.rez-step2-amount');
    if (a && vis(a)) return { main: tx(a), extra: '', cta: a.parentNode.querySelector('.btn') };
    return null;
  }
  var lastP = '', lastR = '';
  function updateSum() {
    var p = priceInfo();
    sum.hidden = !p; if (!p) { ctaEl = null; return; }
    ctaEl = p.cta;
    var r = p.form ? rowsData() : [], rs = JSON.stringify(r);
    if (rs !== lastR) {
      lastR = rs; rows.textContent = '';
      r.forEach(function (x) { var t = mk('dt'), v = mk('dd'); t.textContent = x[0]; v.textContent = x[1].join(' · '); rows.appendChild(t); rows.appendChild(v); });
    }
    totL.textContent = totLabel();
    if (p.main !== lastP) {
      totV.textContent = p.main || '—';
      if (lastP && p.main && !RM) { totV.classList.remove('rz-bump'); void totV.offsetWidth; totV.classList.add('rz-bump'); }
      lastP = p.main;
    }
    totX.textContent = p.extra;
    go.textContent = tx(p.cta); go.hidden = !p.main || !p.cta;
    tog(sum, 'is-empty', !p.main);
  }
  go.addEventListener('click', function () {
    var c = ctaEl; if (!c) return;
    c.scrollIntoView({ behavior: RM ? 'auto' : 'smooth', block: 'center' });
    setTimeout(function () { try { c.focus({ preventScroll: true }); } catch (e) {} if (!RM) { c.classList.add('rz-hl'); setTimeout(function () { c.classList.remove('rz-hl'); }, 1900); } }, RM ? 0 : 450);
  });

  // aktuální krok podle scrollu + skrytí spodní lišty u skutečného CTA, při psaní a u cookie lišty
  function track() {
    var vh = w.innerHeight || 800, i, idx = 0;
    if (secs.length) {
      for (i = 0; i < secs.length; i++) if (secs[i].getBoundingClientRect().top <= vh * 0.38) idx = i;
      if (idx !== cur) {
        cur = idx;
        AP.forEach.call(list.children, function (li, j) {
          var b = li.firstChild; tog(li, 'is-cur', j === idx); tog(b, 'is-cur', j === idx); tog(b, 'is-past', j < idx);
          if (j === idx) b.setAttribute('aria-current', 'step'); else b.removeAttribute('aria-current');
        });
        secs.forEach(function (s, j) { tog(s, 'rz-cur', j === idx); });
        steps.style.setProperty('--rz-p', secs.length > 1 ? String(idx / (secs.length - 1)) : '1');
      }
    }
    var n = false, box = ctaEl && (ctaEl.closest('.rez-step2-actions') || ctaEl.parentNode);
    if (box) { var r = box.getBoundingClientRect(), pv = d.getElementById('rez-price-preview'), q = pv && pv.getBoundingClientRect(); n = (r.top < vh && r.bottom > 0) || !!(q && q.height && q.top < vh && q.bottom > 0); }
    if (n !== near) { near = n; tog(side, 'rz-near', n); }
    var ck = d.querySelector('.mg-consent'); tog(side, 'rz-cookie', !!(ck && !ck.hidden && vis(ck)));
  }
  function sync() {
    var ss = sections();
    buildSteps(ss); secs = ss; animateNew(ss); updateSum();
    tog(host, 'rz-grid', !steps.hidden || !sum.hidden);
    track();
  }
  var tm = 0, raf = 0;
  function later() { if (!tm) tm = setTimeout(function () { tm = 0; sync(); }, 90); }
  function onScroll() { if (!raf) raf = (w.requestAnimationFrame || setTimeout)(function () { raf = 0; track(); }); }
  if ('MutationObserver' in w) new MutationObserver(later).observe(app, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class'] });
  ['change', 'input', 'click'].forEach(function (e) { app.addEventListener(e, later); });
  w.addEventListener('scroll', onScroll, { passive: true });
  w.addEventListener('resize', onScroll, { passive: true });
  d.addEventListener('focusin', function (e) { var t = e.target; tog(side, 'rz-kb', !!(t && app.contains(t) && /^(INPUT|SELECT|TEXTAREA)$/.test(t.tagName) && !/^(checkbox|radio|button|submit)$/.test(t.type))); });
  d.addEventListener('focusout', function () { setTimeout(function () { var t = d.activeElement; if (!t || !app.contains(t) || !/^(INPUT|SELECT|TEXTAREA)$/.test(t.tagName)) tog(side, 'rz-kb', false); }, 0); });
  d.addEventListener('click', function (e) { if (e.target && e.target.closest && e.target.closest('.mg-consent')) setTimeout(track, 50); });
  sync();
})();
