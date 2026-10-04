// ===== MotoGo24 — Upravit rezervaci: pobočka s vjezdovou bránou (Velké Němčice) =====
// Jádro js/pages-upravit-rezervaci.js je MINIFIKOVANÉ a NEUPRAVUJE se — tento soubor
// obaluje zvenčí (stejná technika jako guard/swap/gear):
//   - MG._editRez._appendPickup — blok „K vyzvednutí“ po změně motorky (_submitChange),
//     po výměně (swap.js) i po návratu ze zaplacené úpravy (_paidPickup),
//   - MG._editRez._renderTabDetail — záložka Detail (místo vyzvednutí / vrácení).
// Má-li pobočka motorky bránu se schránkou na klíč (veřejný příznak RPC
// branch_has_gate), doplní krátký postup příjezdu (editRez.pickup.gateNoticeTitle /
// editRez.pickup.gateNotice). Pobočka se bere z motorky (motorcycles.branch_id) —
// jádro si branch id nenačítá, proto jeden lehký dotaz navíc (cache na stránku).
// BEZPEČNOST: kód schránky se tu NIKDY nezobrazuje — chodí jen osobními kanály
// (zprávy v appce, SMS/WhatsApp, e-mail s kódy). Pobočky bez brány = beze změny.
// Načítá se po pages-upravit-rezervaci-guard.js (pages/upravit-rezervaci.php).
(function () {
  var MG = window.MG;
  var ER = (MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  var gateByBranch = {};  // branch_id → Promise<boolean>
  var branchByMoto = {};  // moto_id → Promise<branch_id|null>
  var BOX_STYLE = 'border:1.5px dashed #b8e6b8;border-radius:12px;background:#f9fefa;padding:.6rem .75rem';

  function esc(v) {
    if (typeof ER._esc === 'function') return ER._esc(v);
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  // Chybějící překlad → '' (MG.t vrací syrový klíč — ten se nesmí vypsat).
  function txt(k) { var v = MG.t(k); return (typeof v === 'string' && v !== k) ? v : ''; }
  function offline() { return !window.sb || ER._isMockMode; }

  function hasGate(branchId) {
    if (!branchId || offline()) return Promise.resolve(false);
    if (!gateByBranch[branchId]) {
      gateByBranch[branchId] = Promise.resolve(window.sb.rpc('branch_has_gate', { p_branch_id: branchId }))
        .then(function (r) {
          if (!r || r.error) { delete gateByBranch[branchId]; return false; }
          return r.data === true;
        })
        .catch(function () { delete gateByBranch[branchId]; return false; });
    }
    return gateByBranch[branchId];
  }

  function motoBranch(motoId) {
    if (!motoId || offline()) return Promise.resolve(null);
    if (!branchByMoto[motoId]) {
      branchByMoto[motoId] = Promise.resolve(window.sb.from('motorcycles').select('branch_id').eq('id', motoId).maybeSingle())
        .then(function (r) {
          if (!r || r.error) { delete branchByMoto[motoId]; return null; }
          return (r.data && r.data.branch_id) || null;
        })
        .catch(function () { delete branchByMoto[motoId]; return null; });
    }
    return branchByMoto[motoId];
  }

  // Aktuální motorka rezervace (po změně je jiná než v selectedBooking) → pobočka.
  async function bookingBranch(bid) {
    if (!bid || offline()) return null;
    try {
      var r = await window.sb.from('bookings').select('motorcycles!moto_id(branch_id)').eq('id', bid).maybeSingle();
      var m = r && !r.error && r.data && r.data.motorcycles;
      return (m && m.branch_id) || null;
    } catch (e) { return null; }
  }

  // Do boxu „K vyzvednutí“ (.edit-rez-pickup).
  ER._gateNoticeHtml = function () {
    var title = txt('editRez.pickup.gateNoticeTitle'), body = txt('editRez.pickup.gateNotice');
    if (!body) return '';
    return '<div class="erez-gate-notice" style="margin-top:.6rem;font-size:.9rem;line-height:1.45;' + BOX_STYLE + '">' +
      (title ? '<strong>🔑 ' + esc(title) + '</strong><br>' : '') + esc(body) + '</div>';
  };

  // Záložka Detail — položka ve stylu ostatních (.edit-rez-info-item, jako _lateGateNote).
  ER._gateDetailItemHtml = function () {
    var title = txt('editRez.pickup.gateNoticeTitle'), body = txt('editRez.pickup.gateNotice');
    if (!body) return '';
    return '<div class="edit-rez-info-item erez-gate-notice" style="' + BOX_STYLE + '"><div class="ico">🔑</div><div>' +
      (title ? '<div class="lbl">' + esc(title) + '</div>' : '') +
      '<div class="val" style="font-size:.9rem;line-height:1.45">' + esc(body) + '</div></div></div>';
  };

  function addToPickupBox(el) {
    var boxes = el.querySelectorAll('.edit-rez-pickup');
    var box = boxes.length ? boxes[boxes.length - 1] : null;
    if (!box || box.querySelector('.erez-gate-notice')) return false;
    var h = ER._gateNoticeHtml();
    if (!h) return false;
    box.insertAdjacentHTML('beforeend', h);
    return true;
  }

  // ---- 1) Blok „K vyzvednutí“ po úpravě / výměně / zaplacení ----
  var coreAppend = ER._appendPickup;
  if (typeof coreAppend === 'function') {
    ER._appendPickup = async function (bid, el, motoId) {
      // dotaz na bránu běží souběžně s jádrem; chyba = bez upozornění
      var gateP = (motoId ? motoBranch(motoId) : bookingBranch(bid))
        .then(hasGate).catch(function () { return false; });
      var ok = await coreAppend.apply(this, arguments);
      if (!ok || !el) return ok;
      try { if (await gateP) addToPickupBox(el); } catch (e) { /* noop */ }
      return ok;
    };
  }

  // ---- 2) Záložka Detail ----
  function atBranch(method, addr) { return method !== 'delivery' && !String(addr || '').trim(); }

  ER._decorateDetailGate = function () {
    var b = ER.selectedBooking, m = ER.selectedMoto || {};
    if (!b || b.status === 'completed' || b.status === 'cancelled') return null;
    // před převzetím: k místu vyzvednutí; probíhající (nebo přistavení): k místu vrácení
    var pick = b.status !== 'active' && atBranch(b.pickup_method, b.pickup_address);
    var ret = atBranch(b.return_method, b.return_address);
    if (!pick && !ret) return null;
    var root = document.getElementById('edit-rez-tab-content');
    var side = root && root.querySelector('.edit-rez-detail-side');
    if (!side) return null;
    return motoBranch(b.moto_id || m.id).then(hasGate).then(function (yes) {
      if (!yes || ER.selectedBooking !== b || !document.body.contains(side) || side.querySelector('.erez-gate-notice')) return false;
      var h = ER._gateDetailItemHtml();
      if (!h) return false;
      var want = pick ? '📍' : '🏁', anchor = null, items = side.querySelectorAll('.edit-rez-info-item');
      for (var i = 0; i < items.length; i++) {
        var ico = items[i].querySelector('.ico');
        if (ico && String(ico.textContent || '').trim() === want) anchor = items[i];
      }
      if (anchor) anchor.insertAdjacentHTML('afterend', h);
      else side.insertAdjacentHTML('beforeend', h);
      return true;
    }).catch(function () { return false; });
  };

  var coreDetail = ER._renderTabDetail;
  if (typeof coreDetail === 'function') {
    ER._renderTabDetail = function () {
      var res = coreDetail.apply(this, arguments);
      try { ER._decorateDetailGate(); } catch (e) { /* noop */ }
      return res;
    };
  }
})();
