/* ===== MotoGo24 — Upravit rezervaci: výpůjčka výbavy — záložky Velikosti a Odebrat kus =====
 * Velikosti (zdarma): RPC customer_update_gear_sizes(p_booking_id, p_sizes {key: velikost}) —
 *   stejné kusy, velikosti z ceníku (u samoobslužné pobočky v rozsahu samoobsluhy, gear-ss-cap.js),
 *   při kontrole skladu (get_gear_rental_availability) nejsou vyprodané velikosti k výběru.
 * Odebrat kus: RPC customer_remove_gear_item(p_booking_id, p_key) — vratka rozdílu ceny podle
 *   jednotného pravidla (refund.js: čas do začátku výpůjčky, sleva poměrně); náhled přecení zbylé
 *   kusy jako server (_gearQuote), konečnou částku vrací server. Poslední kus odebrat nejde (Storno).
 * Přidání kusu k zaplacené výpůjčce není samoobslužné (v1) — text s kontaktem.
 */
(function() {
  var MG = window.MG;
  var ER = (MG && MG._editRez) ? MG._editRez : null;
  if (!ER || !ER._isGear) return;

  function esc(v) { return ER._esc ? ER._esc(v) : String(v == null ? '' : v); }
  function days(b) { return ER._daysInclusive(ER._normIso(b.start_date), ER._normIso(b.end_date)); }
  function tabEl() { return document.getElementById('edit-rez-tab-content'); }
  function still(b, tab) { return ER.selectedBooking === b && ER.tab === tab && !!tabEl(); }
  var ERR = { not_found: 'editRez.err.notFound', wrong_status: 'editRez.err.wrongStatus', not_paid: 'editRez.err.notPaid',
    unauthenticated: 'editRez.login.error', no_change: 'editRez.extend.noChange', started: 'editRez.gearbk.errStarted' };
  function errText(code) {
    var k = (ER._gearErrKey && ER._gearErrKey(code)) || ERR[code];
    return MG.t(k || 'editRez.err.generic');
  }
  function manual(b, amount) {
    return amount > 0 && !b.stripe_payment_intent_id ? '<br><span class="muted">' + MG.t('editRez.refund.manualNote') + '</span>' : '';
  }
  function done(html) {
    var el = tabEl();
    if (!el) return;
    el.innerHTML = '<div class="edit-rez-success-box"><h3>✓</h3><p>' + html + '</p><button type="button" class="btn btngreen-small" id="edit-rez-back-list">' +
      MG.t('editRez.list.title') + '</button></div>';
    document.getElementById('edit-rez-back-list').addEventListener('click', async function() {
      ER.selectedBooking = null;
      await ER._loadBookings();
      ER._goto('list');
    });
  }
  function rpc(name, args) {
    return Promise.resolve(window.sb.rpc(name, args)).then(function(r) {
      var d = r && r.data;
      if (r && r.error) return { error: r.error.message || r.error.code || 'error' };
      return d || { error: 'error' };
    });
  }

  // ---- Velikosti ----
  async function loadAvail(b) {
    if (!window.sb || ER._isMockMode || !b.branch_id) return null;
    try {
      var r = await window.sb.rpc('get_gear_rental_availability', { p_branch_id: b.branch_id,
        p_start: ER._normIso(b.start_date), p_end: ER._normIso(b.end_date) });
      return r && r.data && r.data.enabled && r.data.sizes ? r.data.sizes : null;
    } catch (e) { return null; }
  }

  ER._renderGearSizesTab = async function() {
    var b = ER.selectedBooking, el = tabEl();
    if (!b || !el) return;
    el.innerHTML = '<h3>' + MG.t('editRez.gearbk.sizesTitle') + '</h3><p class="muted">' + MG.t('editRez.loading') + '</p>';
    var res = await Promise.all([ER._gearPricesLoad(), loadAvail(b)]);
    if (!still(b, 'gsizes')) return;
    var avail = res[1], ss = ER._gearIsSS(b);
    var items = ER._gearItems(b).filter(function(i) { return i.size; });
    var orig = {}, sel = {};
    items.forEach(function(i) { orig[i.key] = sel[i.key] = i.size; });
    function chips(it) {
      var row = ER._gearRow(it.key), list = (row && row.sizes && row.sizes.length) ? row.sizes.slice() : [it.size];
      if (MG._ssCapGearSizes) list = MG._ssCapGearSizes(it.key, list, ss, false);
      if (list.indexOf(orig[it.key]) < 0) list.unshift(orig[it.key]);
      return list.map(function(s) {
        var out = avail && avail[it.key] && avail[it.key][s] === 0 && s !== orig[it.key];
        return '<button type="button" class="size-chip erez-gsz' + (sel[it.key] === s ? ' active' : '') + '" data-k="' + esc(it.key) + '" data-s="' + esc(s) + '"' +
          (out ? ' disabled title="' + esc(MG.t('editRez.gearbk.soldOut')) + '"' : '') + '>' + esc(s) + '</button>';
      }).join('');
    }
    function changed() { return items.filter(function(i) { return sel[i.key] !== orig[i.key]; }); }
    function draw() {
      var ch = changed();
      el.innerHTML = '<h3>' + MG.t('editRez.gearbk.sizesTitle') + '</h3><p>' + MG.t('editRez.gearbk.sizesIntro') + '</p>' +
        (ss ? '<p class="muted erez-gear-ss">ⓘ ' + MG.t('editRez.gearbk.ssLimits') + '</p>' : '') +
        items.map(function(it) {
          return '<div class="erez-gsz-row"><div class="erez-gsz-label">' + esc(ER._gearLabel(it.key)) + '</div><div class="erez-gsz-chips">' + chips(it) + '</div></div>';
        }).join('') +
        '<div class="edit-rez-price-summary" aria-live="polite">' + (ch.length ? ch.map(function(i) {
          return esc(ER._gearLabel(i.key)) + ': <s>' + esc(orig[i.key]) + '</s> → <strong>' + esc(sel[i.key]) + '</strong>';
        }).join('<br>') + '<div class="muted">' + MG.t('editRez.gearbk.sizesFree') + '</div>' : '<span class="muted">' + MG.t('editRez.gearbk.sizesPick') + '</span>') + '</div>' +
        '<button type="button" class="btn btngreen" id="erez-gsz-save"' + (ch.length ? '' : ' disabled') + '>' + MG.t('editRez.gearbk.sizesSave') + '</button>' +
        '<p class="erez-gear-note">' + MG.t('editRez.gearbk.addItemNote') + '</p>';
      el.querySelectorAll('.erez-gsz').forEach(function(btn) {
        btn.addEventListener('click', function() {
          if (btn.disabled) return;
          sel[btn.getAttribute('data-k')] = btn.getAttribute('data-s');
          draw();
        });
      });
      var save = document.getElementById('erez-gsz-save');
      save.addEventListener('click', function() { if (changed().length && !ER.busy) submit(save); });
    }
    async function submit(btn) {
      ER._setBusy(true);
      btn.disabled = true;
      try {
        var d = await rpc('customer_update_gear_sizes', { p_booking_id: b.id, p_sizes: Object.assign({}, sel) });
        if (!d || d.error || d.success === false) {
          console.error('[editRez] gear sizes failed', d);
          ER._showError(errText(d && d.error));
          btn.disabled = false;
          return;
        }
        done(MG.t('editRez.gearbk.sizesSaved'));
      } catch (e) {
        console.error('[editRez] gear sizes exception', e);
        ER._showError(MG.t('editRez.err.generic'));
        btn.disabled = false;
      } finally { ER._setBusy(false); }
    }
    draw();
  };

  // ---- Odebrat kus ----
  ER._gearRemovePreview = function(b, key) {
    var keys = ER._gearItems(b).map(function(i) { return i.key; }).filter(function(k) { return k !== key; });
    var q = ER._gearQuote(keys);
    if (!q) return null;
    var perDay = Number(b.gear_per_day || 0), diff = Math.max(0, perDay - q.per_day) * days(b);
    var pct = ER._refundPercentFor(b), gross = Math.round(diff * pct / 100);
    // Bez kusu může vyjít dráž (komplet je levnější než jednotlivé kusy) — cena se nezvyšuje, vratka 0.
    return { perDay: Math.min(perDay, q.per_day), noSaving: q.per_day >= perDay, diff: diff, pct: pct, refund: ER._refundNet(b, gross) };
  };

  ER._renderGearRemoveTab = async function() {
    var b = ER.selectedBooking, el = tabEl();
    if (!b || !el) return;
    el.innerHTML = '<h3>' + MG.t('editRez.gearbk.removeTitle') + '</h3><p class="muted">' + MG.t('editRez.loading') + '</p>';
    await ER._gearPricesLoad();
    if (!still(b, 'gremove')) return;
    var items = ER._gearItems(b), pick = null;
    function draw() {
      var p = pick ? ER._gearRemovePreview(b, pick) : null, sum = '';
      if (pick && p) {
        sum = '<div class="erez-loc-calc-row"><span>' + MG.t('editRez.gearbk.newPerDay') + '</span><strong>' + MG.formatPrice(p.perDay) + '</strong></div>' +
          '<div class="line ' + (p.noSaving ? 'refund-none' : p.pct === 100 ? 'refund-full' : p.pct === 50 ? 'refund-half' : 'refund-none') + '">' +
          (p.noSaving ? MG.t('editRez.gearbk.removeNoSaving') : p.pct === 0 ? MG.formatPrice(0) + ' — ' + ER._refundZeroReason(b) :
          MG.t('editRez.shorten.refund', { amount: MG.formatPrice(p.refund), percent: p.pct })) + '</div>';
      } else if (pick) {
        sum = '<span class="muted">' + MG.t('editRez.gearbk.removeServerCalc') + '</span>';
      } else {
        sum = '<span class="muted">' + MG.t('editRez.gearbk.removePick') + '</span>';
      }
      el.innerHTML = '<h3>' + MG.t('editRez.gearbk.removeTitle') + '</h3><p>' + MG.t('editRez.gearbk.removeIntro') + '</p>' +
        ER._refundRuleHtml(b) +
        '<div class="erez-gear-remove-list">' + items.map(function(i) {
          return '<button type="button" class="erez-gear-remove-item' + (pick === i.key ? ' active' : '') + '" data-k="' + esc(i.key) + '" aria-pressed="' + (pick === i.key) + '">' +
            esc(ER._gearLabel(i.key)) + (i.size ? ' <span class="muted">' + esc(i.size) + '</span>' : '') + '</button>';
        }).join('') + '</div><div class="edit-rez-price-summary" aria-live="polite">' + sum + '</div>' +
        '<button type="button" class="btn btnred" id="erez-gear-remove-cta"' + (pick ? '' : ' disabled') + '>' + MG.t('editRez.gearbk.removeCta') + '</button>' +
        '<p class="erez-gear-note">' + MG.t('editRez.gearbk.removeLastNote') + '</p>' + ER._stornoBoxHtml();
      el.querySelectorAll('.erez-gear-remove-item').forEach(function(btn) {
        btn.addEventListener('click', function() { var k = btn.getAttribute('data-k'); pick = pick === k ? null : k; draw(); });
      });
      document.getElementById('erez-gear-remove-cta').addEventListener('click', function() {
        if (!pick || ER.busy) return;
        var key = pick;
        ER._confirmDialog(MG.t('editRez.gearbk.removeConfirm', { item: esc(ER._gearLabel(key)) }), function() { submit(key); },
          { yesLabel: MG.t('editRez.gearbk.removeYes'), noLabel: MG.t('editRez.cancel.confirmNo'), danger: true });
      });
    }
    async function submit(key) {
      ER._setBusy(true);
      try {
        var d = await rpc('customer_remove_gear_item', { p_booking_id: b.id, p_key: key });
        if (!d || d.error || d.success === false) {
          console.error('[editRez] gear remove failed', d);
          ER._showError(errText(d && d.error));
          return;
        }
        var amt = Number(d.refund_amount || 0), pct = d.refund_percent != null ? d.refund_percent : 0, item = esc(ER._gearLabel(key));
        done((amt > 0 ? MG.t('editRez.gearbk.removeSuccess', { item: item, amount: MG.formatPrice(amt), percent: pct })
          : MG.t('editRez.gearbk.removeSuccessNoRefund', { item: item })) + manual(b, amt));
      } catch (e) {
        console.error('[editRez] gear remove exception', e);
        ER._showError(MG.t('editRez.err.generic'));
      } finally { ER._setBusy(false); }
    }
    draw();
  };
})();
