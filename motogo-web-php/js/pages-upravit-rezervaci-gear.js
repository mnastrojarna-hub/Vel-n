// ===== MotoGo24 — Upravit rezervaci: záložka „Výbava" (změna velikostí) =====
// Záložka „gear" byla v dispatchi (_renderDetail) i překladech (editRez.gear.*)
// odjakživa, ale render funkce chyběla → klik na záložku skončil TypeError a
// zákazník na webu nemohl velikosti výbavy vůbec změnit. Backend existuje celý:
// RPC update_booking_gear (velikosti + placené booking_extras + přepočet ceny,
// dry-run vrací net_diff), webhook-receiver umí `change:{_gear:{sizes}}` →
// apply_paid_gear_change po Stripe platbě. Tenhle soubor doplňuje frontend:
//  - změna velikosti už vybrané výbavy = zdarma (uloží se hned),
//  - přidání placené výbavy (boty řidiče, výbava/boty spolujezdce) = doplatek
//    přes process-payment (type=extension) — stejný pending flow jako prodloužení,
//  - odebrání placené výbavy = uložení s p_settle_refund:true; vratku
//    dispatchne RPC server-side až PO úspěšném commitu.
// Záznam do historie úprav zajistí DB trigger track_booking_content_changes
// (gear_changes {pole:{from,to}}) — Velín, appka i web ho zobrazí.
(function () {
  var ER = (window.MG && MG._editRez) ? MG._editRez : null;
  if (!ER) return;

  var TYPES = ['helmet', 'jacket', 'pants', 'boots', 'gloves'];
  // Fallback velikosti, když se accessory_types nepodaří načíst
  var FALLBACK_SIZES = {
    helmet: ['XS', 'S', 'M', 'L', 'XL', '2XL'],
    jacket: ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL'],
    pants: ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL'],
    boots: ['36', '37', '38', '39', '40', '41', '42', '43', '44', '45', '46', '47'],
    gloves: ['XS', 'S', 'M', 'L', 'XL', '2XL'],
  };
  var _sizeCatalog = null; // {helmet:[...], ...} z accessory_types (cache)

  function loadSizeCatalog() {
    if (_sizeCatalog) return Promise.resolve(_sizeCatalog);
    if (!window.sb || ER._isMockMode) { _sizeCatalog = FALLBACK_SIZES; return Promise.resolve(_sizeCatalog); }
    return window.sb.from('accessory_types').select('key,sizes,is_active')
      .in('key', TYPES).then(function (res) {
        var out = {};
        (res.data || []).forEach(function (row) {
          if (row.is_active === false) return;
          if (Array.isArray(row.sizes) && row.sizes.length) out[row.key] = row.sizes.map(String);
        });
        TYPES.forEach(function (tp) { if (!out[tp]) out[tp] = FALLBACK_SIZES[tp]; });
        _sizeCatalog = out;
        return out;
      }).catch(function () {
        _sizeCatalog = FALLBACK_SIZES;
        return _sizeCatalog;
      });
  }

  // Aktuální výběr velikostí (10 klíčů dle p_sizes v update_booking_gear)
  function sizesFromBooking(b) {
    var s = {};
    TYPES.forEach(function (tp) {
      s[tp] = b[tp + '_size'] || '';
      s['passenger_' + tp] = b['passenger_' + tp + '_size'] || '';
    });
    return s;
  }

  function chipRow(field, label, sizes, current, allowNone) {
    var chips = '';
    if (allowNone) {
      chips += '<button type="button" class="size-chip' + (current ? '' : ' active') +
        '" data-gear-field="' + field + '" data-gear-size="">' + MG.t('editRez.gear.none') + '</button>';
    }
    sizes.forEach(function (sz) {
      chips += '<button type="button" class="size-chip' + (String(sz) === String(current) ? ' active' : '') +
        '" data-gear-field="' + field + '" data-gear-size="' + sz + '">' + sz + '</button>';
    });
    return '<div class="edit-rez-gear-row" style="margin:.5rem 0">' +
      '<div style="font-weight:700;font-size:.9rem;margin-bottom:.25rem">' + label + '</div>' +
      '<div style="display:flex;flex-wrap:wrap;gap:.35rem">' + chips + '</div></div>';
  }

  ER._renderTabGear = function () {
    var el = document.getElementById('edit-rez-tab-content');
    var b = ER.selectedBooking;
    if (!el || !b) return;

    // Rozpracovaný stav po návratu ze Stripe „Zpět" (resume), jinak stav rezervace
    var sizes;
    if (ER._resumeUiTab === 'gear' && ER._resumeUi && ER._resumeUi.sizes) {
      sizes = ER._resumeUi.sizes;
      ER._resumeUiTab = null; ER._resumeUi = null;
    } else {
      sizes = sizesFromBooking(b);
    }
    ER._gearSizes = sizes;

    el.innerHTML = '<h3>' + MG.t('editRez.gear.title') + '</h3>' +
      '<p class="muted" style="font-size:.9rem">' + MG.t('editRez.gear.intro') + '</p>' +
      '<div id="edit-rez-gear-body"><div class="muted">…</div></div>';

    loadSizeCatalog().then(function (catalog) {
      var body = document.getElementById('edit-rez-gear-body');
      if (!body || ER.tab !== 'gear') return;
      var labels = ER._GEAR_LABELS || {};
      var html = '<div class="edit-rez-gear-block"><h5>' + MG.t('rez.gear.rider') + '</h5>';
      TYPES.forEach(function (tp) {
        html += chipRow(tp, labels[tp] || tp, catalog[tp], sizes[tp], true);
      });
      html += '</div><div class="edit-rez-gear-block" style="margin-top:1rem"><h5>' + MG.t('rez.gear.passenger') + '</h5>';
      TYPES.forEach(function (tp) {
        html += chipRow('passenger_' + tp, labels[tp] || tp, catalog[tp], sizes['passenger_' + tp], true);
      });
      html += '</div>' +
        '<div id="edit-rez-gear-msg" class="muted" style="margin:.75rem 0;font-size:.9rem"></div>' +
        '<button type="button" class="btn btngreen-small" id="edit-rez-gear-save">' + MG.t('editRez.gear.save') + '</button>';
      body.innerHTML = html;

      body.querySelectorAll('[data-gear-field]').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var field = btn.getAttribute('data-gear-field');
          ER._gearSizes[field] = btn.getAttribute('data-gear-size') || '';
          body.querySelectorAll('[data-gear-field="' + field + '"]').forEach(function (o) {
            o.classList.toggle('active', o === btn);
          });
          ER._gearPreview();
        });
      });
      var saveBtn = document.getElementById('edit-rez-gear-save');
      if (saveBtn) saveBtn.addEventListener('click', function () { ER._submitGear(); });
      ER._gearPreview();
    });
  };

  // Živý náhled dopadu na cenu (dry-run) — doplatek / vratka / zdarma
  var _previewT = null;
  ER._gearPreview = function () {
    if (_previewT) clearTimeout(_previewT);
    _previewT = setTimeout(async function () {
      var b = ER.selectedBooking;
      var msg = document.getElementById('edit-rez-gear-msg');
      if (!b || !msg) return;
      try {
        var res = await window.sb.rpc('update_booking_gear', {
          p_booking_id: b.id, p_sizes: ER._gearSizes, p_dry_run: true,
        });
        if (!msg.isConnected) return;
        if (res.error || !res.data || res.data.success === false) { msg.textContent = ''; return; }
        var net = Number(res.data.net_diff || 0);
        msg.textContent = net > 0 ? MG.t('editRez.gear.surcharge', { amount: MG.formatPrice(net) })
          : net < 0 ? MG.t('editRez.gear.refund', { amount: MG.formatPrice(-net) })
          : MG.t('editRez.gear.noCharge');
      } catch (e) { /* náhled je best-effort */ }
    }, 250);
  };

  ER._submitGear = async function () {
    if (ER.busy) return;
    var b = ER.selectedBooking;
    if (!b) return;
    ER._setBusy(true);
    try {
      var sizes = ER._gearSizes || sizesFromBooking(b);
      var dry = await window.sb.rpc('update_booking_gear', {
        p_booking_id: b.id, p_sizes: sizes, p_dry_run: true,
      });
      if (dry.error || !dry.data || dry.data.success === false) {
        var code = dry.data && dry.data.error;
        var map = { wrong_status: 'editRez.err.wrongStatus', not_paid: 'editRez.err.notPaid', not_found: 'editRez.err.notFound', not_owner: 'editRez.err.notFound' }[code];
        console.error('[editRez] gear dry-run failed', { code: code, error: dry.error, data: dry.data });
        return void ER._showError(MG.t(map || 'editRez.err.generic'));
      }
      var net = Number(dry.data.net_diff || 0);

      if (net > 0) {
        // Doplatek — stejný pending flow jako prodloužení: process-payment
        // (type=extension) s change:{_gear:{sizes}} → webhook aplikuje přes
        // apply_paid_gear_change; klientský fallback řeší _applyPendingAfterPayment.
        try { localStorage.setItem('editRez_pending_' + b.id, JSON.stringify({ payload: { _gear_sizes: sizes }, ts: Date.now() })); } catch (e) {}
        if (ER._saveResume) ER._saveResume('gear', { sizes: sizes });
        var sess = await window.sb.auth.getSession();
        var token = sess && sess.data && sess.data.session && sess.data.session.access_token;
        if (!token) throw new Error('no-auth');
        var resp = await fetch(window.MOTOGO_CONFIG.SUPABASE_URL + '/functions/v1/process-payment', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token, apikey: window.MOTOGO_CONFIG.SUPABASE_ANON_KEY },
          body: JSON.stringify({
            type: 'extension', mode: 'checkout', booking_id: b.id, amount: net,
            change: { _gear: { sizes: sizes }, new_total: dry.data.new_total },
            success_url: window.location.origin + '/upravit-rezervaci?paid_booking=' + b.id,
            cancel_url: window.location.origin + '/upravit-rezervaci?edit_booking=' + b.id + '&edit_tab=gear',
          }),
        });
        var pay = await resp.json().catch(function () { return null; });
        var url = pay && (pay.checkout_url || pay.url);
        if (!resp.ok || !url) {
          console.error('[editRez] gear payment err', resp.status, pay);
          try { localStorage.removeItem('editRez_pending_' + b.id); } catch (e) {}
          return void ER._showError(pay && pay.error ? pay.error : MG.t('editRez.err.generic'));
        }
        window.location.href = url;
        return;
      }

      // net<=0 → rovnou COMMIT. Vratku dispatchne RPC server-side AŽ PO
      // úspěšném uložení (p_settle_refund) — klientský refund před commitem
      // nechával při selhaném uložení „osiřelou" vratku a vedl k duplicitním
      // dobropisům (incident DB-2026-0008/-0009, 21.8.2026).
      var commit = await window.sb.rpc('update_booking_gear', {
        p_booking_id: b.id, p_sizes: sizes, p_dry_run: false, p_settle_refund: true,
      });
      if (commit.error || !commit.data || commit.data.success === false) {
        console.error('[editRez] gear commit failed', commit.error, commit.data);
        return void ER._showError(MG.t('editRez.err.generic'));
      }
      // refund_manual = bez Stripe platby → vratka převodem na účet do 14 dnů.
      var manualRefund = net < 0 && commit.data.refund_manual === true;

      // Propsat lokální stav (velikosti + cenu), ať detail sedí bez reloadu
      TYPES.forEach(function (tp) {
        b[tp + '_size'] = sizes[tp] || null;
        b['passenger_' + tp + '_size'] = sizes['passenger_' + tp] || null;
      });
      if (commit.data.new_total != null) b.total_price = commit.data.new_total;

      var okMsg = net < 0
        ? MG.t('editRez.change.successWithRefund', { amount: MG.formatPrice(-net) })
        : MG.t('editRez.gear.saved');
      if (manualRefund) {
        okMsg += '<br><span class="muted" style="font-size:.9em">' + MG.t('editRez.refund.manualNote') + '</span>';
      }
      var el = document.getElementById('edit-rez-tab-content');
      if (el) {
        el.innerHTML = '<div class="edit-rez-success-box"><h3>✓</h3><p>' + okMsg +
          '</p><button type="button" class="btn btngreen-small" id="edit-rez-gear-back">' + MG.t('editRez.tab.detail') + '</button></div>';
        var back = document.getElementById('edit-rez-gear-back');
        if (back) back.addEventListener('click', function () { ER.tab = 'detail'; ER._renderDetail(); });
      }
    } catch (e) {
      console.error('[editRez] submitGear err', e);
      ER._showError(MG.t('editRez.err.generic'));
    } finally {
      ER._setBusy(false);
    }
  };

  // Klientský fallback aplikace po Stripe platbě: pending s _gear_sizes se
  // aplikuje přes update_booking_gear (webhook to zpravidla stihne dřív přes
  // apply_paid_gear_change — RPC je idempotentní, druhý běh má net_diff 0).
  var _origApply = ER._applyPendingAfterPayment;
  ER._applyPendingAfterPayment = async function (id) {
    var raw = null;
    try { raw = localStorage.getItem('editRez_pending_' + id); } catch (e) {}
    var pending = null;
    try { pending = raw && JSON.parse(raw); } catch (e) {}
    if (!(pending && pending.payload && pending.payload._gear_sizes)) {
      return _origApply.apply(this, arguments);
    }
    var paid = false;
    for (var n = 0; n < 15; n++) {
      var st = await window.sb.from('bookings').select('payment_status').eq('id', id).single();
      if (st.data && st.data.payment_status === 'paid') { paid = true; break; }
      await new Promise(function (r) { setTimeout(r, 2000); });
    }
    if (!paid) { console.warn('[editRez] gear post-stripe: payment not confirmed in time'); return false; }
    var res = await window.sb.rpc('update_booking_gear', {
      p_booking_id: id, p_sizes: pending.payload._gear_sizes, p_dry_run: false,
    });
    try { localStorage.removeItem('editRez_pending_' + id); } catch (e) {}
    if (res.error || !res.data || res.data.success === false) {
      console.error('[editRez] gear post-stripe apply err', res.error, res.data);
      return false;
    }
    return true;
  };
})();
