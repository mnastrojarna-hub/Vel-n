// ===== MotoGo24 — Samoobslužná pobočka: přistavení na adresu / odvoz z adresy =====
// Rozhodnutí majitele 2026-09-28: motorky ze SAMOOBSLUŽNÉ pobočky
// (branches.type = 'samoobslužná') nelze rezervovat s přistavením na adresu ani
// s odvozem/vyzvednutím z adresy — v rezervačním formuláři (/rezervace) ani při
// úpravě rezervace (/upravit-rezervaci). Volby zůstávají VIDĚT, ale jsou
// odškrtnuté a zablokované a pod nimi je sbalený řádek s vysvětlením
// („ⓘ … — na samoobslužné pobočce zatím není k dispozici" → po kliku text).
//
// Feature flag `feature_flags.self_service_delivery` (Velín → CMS → Feature
// flags) to v budoucnu zapne; výchozí false a false i při chybě čtení. Řádek
// flagu vzniká SQL migrací; anon ho čte stejně jako `reservation_upsell`.
// Stejné pravidlo hlídá i DB trigger — tohle je jen srozumitelná vrstva pro
// zákazníka, aby nenarazil až na chybu při uložení.
//
// Jádra obou stránek (js/pages-rezervace.js, js/pages-upravit-rezervaci.js)
// jsou MINIFIKOVANÁ a NEUPRAVUJÍ se — tento soubor je obaluje zvenčí
// (stejná technika jako pages-upravit-rezervaci-*.js):
//   /rezervace            wrap MG._rezApplySelfServiceTimes (volá se po každé
//                         změně motorky i po změně voleb místa) + MutationObserver
//                         na #rezervace-app + change listenery jako pojistka.
//                         Prvky: #rez-delivery (.rez-loc-card[data-loc="delivery"]),
//                         #rez-return-other (.rez-loc-card[data-loc="return-other"]),
//                         #rez-return-same-as-delivery, panely #rez-delivery-panel,
//                         #rez-return-panel. Motorka: MG._rez.motoId || selectedMotoId
//                         v MG._rez.motos[] (branches.type).
//   /upravit-rezervaci    wrap MG._editRez._renderTabLocation (radia name=pickup /
//                         name=returnM, value=delivery, v #edit-rez-loc-form) a
//                         MG._editRez._renderTabMoto (karty .erez-moto-card[data-branch]
//                         — u rezervace s přistavením/odvozem se motorky ze
//                         samoobsluhy nenabízí) + MutationObserver na #edit-rez-app
//                         (pokryje i záložku „Výměna motorky", #erez-swap-motos).
//                         Motorka rezervace: MG._editRez.selectedBooking.motorcycles
//                         .branches.type; samoobslužné pobočky pro karty: tabulka
//                         branches (veřejné čtení).
// Načítá se v pages/rezervace.php a pages/upravit-rezervaci.php za jádrem.
(function () {
  var MG = window.MG;
  if (!MG) return;

  var FLAG_KEY = 'self_service_delivery';
  var SS_TYPE = 'samoobslužná';
  var NOTE_ATTR = 'data-mg-ss-note';

  // Výchozí české texty — když klíč v MG_I18N chybí, MG.t vrací samotný klíč.
  var DEF_TITLE = 'Na samoobslužné pobočce zatím není k dispozici';
  var DEF_TEXT = 'Motorky ze samoobslužné pobočky se přebírají i vracejí pouze na pobočce — nonstop (24/7) pomocí kódu, který dostanete po zaplacení. Přistavení na adresu ani odvoz z adresy u nich zatím nenabízíme; v budoucnu tuto službu zapneme.';

  var flag = { loaded: false, loading: false, enabled: false };
  var ssBranchIds = null; // { <branch_id>: 1 } — jen pro karty motorek na /upravit-rezervaci
  var applying = false;
  var scheduled = false;

  function txt(key, def) {
    var v = (typeof MG.t === 'function') ? MG.t(key) : null;
    return (typeof v === 'string' && v && v !== key) ? v : def;
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function fire(el, bubbles) {
    if (el) el.dispatchEvent(new Event('change', { bubbles: !!bubbles }));
  }
  function ruleOff() { return flag.enabled; } // flag zapnutý = pravidlo se neuplatní

  // ---------- feature flag ----------
  MG._selfServiceDeliveryEnabled = false;
  MG._loadSelfServiceDeliveryFlag = async function () {
    if (flag.loaded) return flag.enabled;
    if (!window.sb) return false;
    try {
      var r = await window.sb.from('feature_flags').select('enabled').eq('key', FLAG_KEY).maybeSingle();
      flag.enabled = !!(r && r.data && r.data.enabled);
    } catch (e) {
      flag.enabled = false;
    }
    flag.loaded = true;
    MG._selfServiceDeliveryEnabled = flag.enabled;
    return flag.enabled;
  };
  function loadFlag() {
    if (flag.loaded || flag.loading) return;
    if (!window.sb) { setTimeout(loadFlag, 150); return; }
    flag.loading = true;
    MG._loadSelfServiceDeliveryFlag().then(function () { flag.loading = false; applyAll(); },
      function () { flag.loading = false; flag.loaded = true; applyAll(); });
  }

  // ---------- společné UI: zámek karty + sbalená poznámka ----------
  function injectStyles() {
    if (document.getElementById('mg-ss-styles')) return;
    var st = document.createElement('style');
    st.id = 'mg-ss-styles';
    st.textContent =
      '.mg-ss-locked{opacity:.55;cursor:not-allowed!important;pointer-events:none;filter:grayscale(.25)}' +
      '.mg-ss-note{margin:.15rem 0 .8rem;border:1.5px dashed #b8e6b8;border-radius:12px;background:#f9fefa;font-size:.85rem;color:#1a2e22}' +
      '.mg-ss-note-head{display:flex;align-items:center;gap:.5rem;width:100%;background:none;border:0;padding:.6rem .85rem;font:inherit;font-weight:600;color:#1a2e22;text-align:left;cursor:pointer;line-height:1.3}' +
      '.mg-ss-note-ico{color:#0d6e0d;font-size:1rem;flex-shrink:0}' +
      '.mg-ss-note-title{flex:1;min-width:0}' +
      '.mg-ss-note-chev{color:#4a6b5a;transition:transform .2s;flex-shrink:0}' +
      '.mg-ss-note[data-open="1"] .mg-ss-note-chev{transform:rotate(180deg)}' +
      '.mg-ss-note-body{padding:0 .85rem .7rem 2.4rem;color:#4a6b5a;line-height:1.45}' +
      '.mg-ss-note-body[hidden]{display:none}' +
      '.erez-moto-card .mg-ss-note{margin:.4rem 0;font-size:.8rem}' +
      '.erez-moto-card .mg-ss-note-head{padding:.45rem .65rem}' +
      '.erez-moto-card .mg-ss-note-body{padding:0 .65rem .55rem 2.1rem}';
    document.head.appendChild(st);
  }
  function noteHtml(id, title) {
    var status = txt('rez.pickup.selfServiceNoDelivery', DEF_TITLE);
    var head = title ? esc(title) + ' — ' + esc(status) : esc(status);
    return '<div class="mg-ss-note" ' + NOTE_ATTR + '="' + esc(id) + '">' +
      '<button type="button" class="mg-ss-note-head" aria-expanded="false">' +
      '<span class="mg-ss-note-ico" aria-hidden="true">&#9432;</span>' +
      '<span class="mg-ss-note-title">' + head + '</span>' +
      '<span class="mg-ss-note-chev" aria-hidden="true">&#9662;</span></button>' +
      '<div class="mg-ss-note-body" hidden>' + txt('rez.pickup.selfServiceNoDeliveryText', DEF_TEXT) + '</div></div>';
  }
  function findNote(scope, id) {
    return (scope || document).querySelector('.mg-ss-note[' + NOTE_ATTR + '="' + id + '"]');
  }
  // Rozbalení / sbalení vysvětlení kliknutím na řádek.
  function bindNote(n) {
    var btn = n && n.querySelector('.mg-ss-note-head');
    if (!btn) return;
    btn.addEventListener('click', function () {
      var body = n.querySelector('.mg-ss-note-body'), open = n.getAttribute('data-open') === '1';
      n.setAttribute('data-open', open ? '0' : '1');
      btn.setAttribute('aria-expanded', open ? 'false' : 'true');
      if (body) body.hidden = open;
    });
  }
  // Vloží poznámku za `anchor` (afterend), pokud tam ještě není.
  function ensureNote(scope, id, anchor, title) {
    if (!anchor || findNote(scope, id)) return;
    anchor.insertAdjacentHTML('afterend', noteHtml(id, title));
    bindNote(findNote(scope, id));
  }
  function removeNote(scope, id) {
    var n = findNote(scope, id);
    if (n && n.parentNode) n.parentNode.removeChild(n);
  }
  // Text titulku karty bez tooltipu (.ctooltip) — poznámka pak zní
  // „Přistavení motorky jinam — na samoobslužné pobočce zatím není k dispozici".
  function cardTitle(card, sel, fallback) {
    var t = card && card.querySelector(sel);
    if (!t) return fallback;
    var c = t.cloneNode(true);
    Array.prototype.forEach.call(c.querySelectorAll('.ctooltip'), function (x) { x.parentNode.removeChild(x); });
    var s = (c.textContent || '').replace(/\s+/g, ' ').trim();
    return s || fallback;
  }

  // ---------- /rezervace — rezervační formulář ----------
  function rezSelectedMoto() {
    var r = MG._rez || {}, id = r.motoId || r.selectedMotoId;
    if (!id) return null;
    var list = r.motos || [];
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === id) return list[i];
    return null;
  }
  function rezIsSelfService() {
    var m = rezSelectedMoto();
    return !!(m && m.branches && m.branches.type === SS_TYPE);
  }
  function lockCheckbox(cb, card, lock) {
    if (!cb) return;
    if (lock) {
      // Nejdřív odškrtnout a poslat change (jádro schová panel, přepočte cenu,
      // časy i souhrn), TEPRVE potom zablokovat.
      if (cb.checked) { cb.checked = false; fire(cb); }
      cb.disabled = true;
    } else {
      cb.disabled = false;
    }
    if (card) card.classList.toggle('mg-ss-locked', !!lock);
  }
  function applyRez() {
    var del = document.getElementById('rez-delivery');
    if (!del) return; // formulář není vykreslený (krok 2 / resume)
    var app = document.getElementById('rezervace-app') || document;
    var lock = rezIsSelfService() && !ruleOff();
    var ret = document.getElementById('rez-return-other');
    var same = document.getElementById('rez-return-same-as-delivery');
    var delCard = del.closest('.rez-loc-card') || app.querySelector('.rez-loc-card[data-loc="delivery"]');
    var retCard = ret ? (ret.closest('.rez-loc-card') || app.querySelector('.rez-loc-card[data-loc="return-other"]')) : null;

    lockCheckbox(del, delCard, lock);
    lockCheckbox(ret, retCard, lock);
    if (same) same.disabled = lock;
    if (lock) {
      var dp = document.getElementById('rez-delivery-panel'), rp = document.getElementById('rez-return-panel');
      if (dp) dp.style.display = 'none';
      if (rp) rp.style.display = 'none';
      // Poznámka pod mřížkou s dotčenou kartou (karta „na pobočce" zůstává vybraná).
      ensureNote(app, 'delivery', delCard && delCard.parentElement, cardTitle(delCard, '.rez-loc-title', txt('rez.pickup.delivery', 'Přistavení motorky jinam')));
      ensureNote(app, 'return', retCard && retCard.parentElement, cardTitle(retCard, '.rez-loc-title', txt('rez.pickup.returnOther', 'Vrácení motorky jinde')));
    } else {
      removeNote(app, 'delivery');
      removeNote(app, 'return');
    }
    bindRezFallbacks();
  }
  // Pojistka: i kdyby jádro někdy _rezApplySelfServiceTimes nezavolalo.
  function bindRezFallbacks() {
    ['rez-moto-dropdown', 'rez-avail-dropdown', 'rez-delivery', 'rez-return-other'].forEach(function (id) {
      var el = document.getElementById(id);
      if (!el || el.getAttribute('data-mg-ss-bound')) return;
      el.setAttribute('data-mg-ss-bound', '1');
      el.addEventListener('change', function () { schedule(); });
    });
  }
  function observe(app) {
    if (!app || app.getAttribute('data-mg-ss-observed')) return;
    app.setAttribute('data-mg-ss-observed', '1');
    new MutationObserver(function () { schedule(); }).observe(app, { childList: true, subtree: true });
  }
  function hookRez() {
    if (typeof MG._rezApplySelfServiceTimes !== 'function') return false;
    if (!MG._rezApplySelfServiceTimes._mgSsHooked) {
      var orig = MG._rezApplySelfServiceTimes;
      MG._rezApplySelfServiceTimes = function () {
        var r = orig.apply(this, arguments);
        applyAll();
        return r;
      };
      MG._rezApplySelfServiceTimes._mgSsHooked = true;
    }
    observe(document.getElementById('rezervace-app'));
    return true;
  }

  // ---------- /upravit-rezervaci — záložka Místo ----------
  function editBooking() {
    return (MG._editRez && MG._editRez.selectedBooking) || null;
  }
  function editIsSelfService() {
    var b = editBooking(), m = b && b.motorcycles;
    return !!(m && m.branches && m.branches.type === SS_TYPE);
  }
  // Rezervace už přistavení / odvoz MÁ (vznikla dřív) → ponechat: nové pravidlo
  // (a DB trigger) brání jen NOVÉ volbě, ne zachování stávající.
  function hasAddr(method, addr) {
    return method === 'delivery' || !!String(addr || '').trim();
  }
  function applyEditLoc() {
    var form = document.getElementById('edit-rez-loc-form');
    if (!form) return;
    var b = editBooking() || {};
    var lockAll = editIsSelfService() && !ruleOff();
    [['pickup', 'editRez.loc.deliveryTitle', 'Přistavení na adresu', hasAddr(b.pickup_method, b.pickup_address)],
     ['returnM', 'editRez.loc.deliveryReturnTitle', 'Vyzvedneme od vás', hasAddr(b.return_method, b.return_address)]].forEach(function (c) {
      var name = c[0];
      var lock = lockAll && !c[3];
      var delRadio = form.querySelector('input[type="radio"][name="' + name + '"][value="delivery"]');
      if (!delRadio) return; // aktivní rezervace: převzetí je zamčené, radia nejsou
      var branchRadio = form.querySelector('input[type="radio"][name="' + name + '"][value="pickup"]');
      var card = delRadio.closest('.erez-loc-card');
      if (lock) {
        if (delRadio.checked && branchRadio) {
          branchRadio.checked = true;
          fire(branchRadio); // jádro (g): panely, active třídy, časy, souhrn ceny
        }
        delRadio.disabled = true;
        if (card) card.classList.add('mg-ss-locked');
        ensureNote(form, name, card && card.parentElement, cardTitle(card, '.erez-loc-title', txt(c[1], c[2])));
      } else {
        delRadio.disabled = false;
        if (card) card.classList.remove('mg-ss-locked');
        removeNote(form, name);
      }
    });
  }

  // ---------- /upravit-rezervaci — karty motorek (Změna motorky, Výměna motorky) ----------
  // Rezervace s přistavením / odvozem z adresy nesmí přejít na motorku ze
  // samoobsluhy — karta se zablokuje jako u „Nedostupné" + sbalené vysvětlení.
  function loadSsBranches() {
    if (ssBranchIds) return;
    if (!window.sb) { setTimeout(loadSsBranches, 150); return; }
    ssBranchIds = {};
    try {
      window.sb.from('branches').select('id').eq('type', SS_TYPE).then(function (r) {
        (r && r.data || []).forEach(function (b) { if (b && b.id) ssBranchIds[b.id] = 1; });
        applyAll();
      }, function () { /* chyba čtení → nic nezamykáme, hlídá DB trigger */ });
    } catch (e) { /* viz výše */ }
  }
  function applyEditMotoCards() {
    var wrap = document.getElementById('edit-rez-tab-content');
    var b = editBooking();
    if (!wrap || !b || !ssBranchIds) return;
    var pickDel = b.pickup_method === 'delivery', retDel = b.return_method === 'delivery';
    if (ruleOff() || (!pickDel && !retDel)) {
      // Flag se zapnul až po vykreslení zamčených karet → click listener jádra
      // se vrátit nedá, záložku vykreslíme znovu (jen tu, která karty vlastní).
      var ER = MG._editRez;
      if (wrap.querySelector('.mg-ss-moto-locked') && ER) {
        if (ER.tab === 'moto' && typeof ER._renderTabMoto === 'function') ER._renderTabMoto();
        else if (ER.tab === 'swap' && typeof ER._renderTabSwap === 'function') ER._renderTabSwap();
      }
      return;
    }
    var title = (pickDel ? txt('editRez.loc.deliveryTitle', 'Přistavení na adresu') : '') +
      (pickDel && retDel ? ' / ' : '') + (retDel ? txt('editRez.loc.deliveryReturnTitle', 'Vyzvedneme od vás') : '');
    Array.prototype.forEach.call(wrap.querySelectorAll('.erez-moto-card[data-branch]'), function (card) {
      if (card.classList.contains('mg-ss-moto-locked')) return;
      if (!ssBranchIds[card.getAttribute('data-branch')]) return;
      // Výměna motorky uprostřed pronájmu: převzetí už proběhlo, vadí jen odvoz z adresy.
      if (card.closest('#erez-swap-motos') && !retDel) return;
      card.classList.add('mg-ss-moto-locked', 'is-disabled');
      var cta = card.querySelector('.erez-moto-cta');
      if (cta) {
        var d = document.createElement('button');
        d.type = 'button'; d.className = 'erez-moto-cta disabled'; d.disabled = true;
        d.textContent = txt('editRez.moto.unavailable', 'Nedostupné');
        cta.parentNode.replaceChild(d, cta); // nový uzel = bez click listeneru jádra
        d.insertAdjacentHTML('beforebegin', noteHtml('moto-' + (card.getAttribute('data-branch') || ''), title));
        bindNote(d.previousElementSibling);
      }
    });
  }
  function hookEdit() {
    var ER = MG._editRez;
    if (!ER) return false;
    if (typeof ER._renderTabLocation === 'function' && !ER._renderTabLocation._mgSsHooked) {
      var origLoc = ER._renderTabLocation;
      ER._renderTabLocation = function () {
        var r = origLoc.apply(this, arguments);
        applyAll();
        return r;
      };
      ER._renderTabLocation._mgSsHooked = true;
    }
    if (typeof ER._renderTabMoto === 'function' && !ER._renderTabMoto._mgSsHooked) {
      var origMoto = ER._renderTabMoto;
      ER._renderTabMoto = function () {
        var p = origMoto.apply(this, arguments);
        return Promise.resolve(p).then(function (v) { applyAll(); return v; });
      };
      ER._renderTabMoto._mgSsHooked = true;
    }
    observe(document.getElementById('edit-rez-app'));
    loadSsBranches();
    return true;
  }

  // ---------- řízení ----------
  function applyAll() {
    if (applying) return;
    applying = true;
    try {
      injectStyles();
      applyRez();
      applyEditLoc();
      applyEditMotoCards();
    } catch (e) {
      console.warn('[REZ] self-service delivery rule failed:', e);
    } finally {
      applying = false;
    }
  }
  // Sloučí dávku mutací / eventů do jednoho průchodu (až po handlerech jádra).
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(function () { scheduled = false; applyAll(); }, 0);
  }
  function tryHook() {
    var isRez = !!document.getElementById('rezervace-app');
    var isEdit = !!document.getElementById('edit-rez-app');
    var ok = false;
    if (isRez) ok = hookRez();
    if (isEdit) ok = hookEdit();
    if (!ok && (isRez || isEdit)) { setTimeout(tryHook, 100); return; }
    applyAll();
  }

  loadFlag();
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', tryHook);
  else tryHook();
})();
