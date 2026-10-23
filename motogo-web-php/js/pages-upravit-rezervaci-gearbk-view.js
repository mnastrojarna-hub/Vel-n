/* ===== MotoGo24 — Upravit rezervaci: výpůjčka výbavy — seznam, detail, doklady =====
 * Řádek seznamu, hlavička detailu a záložky gear rezervace (data: gearbk.js). Záložky výbavy:
 * Detail, Posunout termín, Prodloužit, Zkrátit (jádro + guard, cena/den = gear_per_day),
 * Velikosti a Odebrat kus (gearbk-tabs.js), Doklady (jen doklad totožnosti), Storno.
 * Motorka, výměna, čas a místo ani výbava k motorce se u výbavy nenabízí. Storno jen před
 * převzetím (probíhající výpůjčku nelze stornovat). Moto rezervace jdou beze změny do jádra.
 */
(function() {
  var MG = window.MG;
  var ER = (MG && MG._editRez) ? MG._editRez : null;
  if (!ER || !ER._isGear) return;

  var ICO = { helmet: '⛑️', jacket: '🧥', pants: '👖', gloves: '🧤', boots: '🥾' };
  function esc(v) { return ER._esc ? ER._esc(v) : String(v == null ? '' : v); }
  function iso(v) { return ER._normIso(v); }
  function today() { return ER._toIsoDate(new Date()); }
  function days(b) { return ER._daysInclusive(iso(b.start_date), iso(b.end_date)); }
  function num(b) { return b.booking_number || (b.id || '').slice(-8).toUpperCase(); }
  function hm(v) { var s = v ? String(v).slice(0, 5) : ''; return s === '00:01' ? '' : s; }

  // Stav pro zákazníka: „Nadcházející“ až do převzetí (stejně jako status.js / Velín / appka).
  ER._gearStatusKey = function(b) {
    if (ER._isPendingUnpaid(b)) return 'unpaid';
    if (b.status === 'cancelled' || b.status === 'completed' || b.status === 'active' || b.status === 'pending') return b.status;
    return iso(b.end_date) < today() ? 'completed' : 'upcoming';
  };

  function sizesText(l) {
    var s = l.sizes || {};
    return Object.keys(s).filter(function(k) { return s[k]; }).map(function(k) {
      return ((l.includes || []).length > 1 ? ER._gearLabel(k) + ' ' : '') + s[k];
    }).join(', ');
  }

  // ---- Seznam ----
  var coreRow = ER._renderBookingRow;
  ER._renderBookingRow = function(b) {
    if (!ER._isGear(b)) return coreRow.apply(this, arguments);
    var unpaid = ER._isPendingUnpaid(b), st = ER._displayStatus(b);
    var items = ER._gearItems(b).map(function(i) { return ER._gearLabel(i.key); }).join(', ');
    var br = b.branch && b.branch.name ? String(b.branch.name).replace(/^MotoGo24\s*/, '') : '';
    var pay = unpaid ? '<button type="button" class="edit-rez-row-pay" data-pay-id="' + esc(b.id) + '" aria-label="' +
      MG.t('editRez.list.payAria') + '">' + MG.t('editRez.list.payCta') + '</button>' : '';
    return '<div class="edit-rez-booking-wrap"><button type="button" class="edit-rez-booking erez-row erez-row-gear' + (unpaid ? ' pending' : '') +
      '" data-id="' + esc(b.id) + '"><div class="erez-row-img"><div class="erez-row-img-ph">🧥</div></div><div class="erez-row-body">' +
      '<div class="erez-row-num">#' + esc(num(b)) + '</div><div class="erez-row-title">' + MG.t('editRez.gearbk.title') + '</div>' +
      '<div class="erez-row-meta">📅 ' + MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date) + ' <span class="muted">· ' + MG._dayLabel(days(b)) + '</span></div>' +
      ((items || br) ? '<div class="erez-row-meta erez-row-sub">' + esc([items, br].filter(Boolean).join(' · ')) + '</div>' : '') +
      '<div class="edit-rez-booking-status status-' + (unpaid ? 'pending-unpaid' : st) + '">' + MG.t('editRez.status.' + (unpaid ? 'unpaid' : st)) + '</div>' +
      '</div><div class="erez-row-price">' + MG.formatPrice(Number(b.total_price || 0)) + '</div></button>' + pay + '</div>';
  };

  // ---- Detail: hlavička + záložky ----
  ER._gearTabs = function(b) {
    var paid = ER._gearPaid(b), res = b.status === 'reserved', live = (res || b.status === 'active') && paid;
    var upcoming = iso(b.start_date) >= today();
    var sized = ER._gearItems(b).some(function(i) { return i.size; });
    return [
      ['detail', MG.t('editRez.tab.detail'), true],
      ['move', MG.t('editRez.tab.move'), res && b.payment_status === 'paid' && upcoming],
      ['extend', MG.t('editRez.tab.extend'), live],
      ['shorten', MG.t('editRez.tab.shorten'), live],
      ['gsizes', MG.t('editRez.gearbk.tabSizes'), res && paid && upcoming && sized],
      ['gremove', MG.t('editRez.gearbk.tabRemove'), res && paid && ER._gearItems(b).length >= 2],
      ['docs', MG.t('editRez.tab.docs'), b.status !== 'cancelled'],
      ['cancel', MG.t('editRez.tab.cancel'), res && paid]
    ].filter(function(t) { return t[2]; });
  };

  function renderGearDetail() {
    ER._renderShell();
    var c = document.getElementById('edit-rez-content'), b = ER.selectedBooking;
    var tabs = ER._gearTabs(b);
    if (!tabs.some(function(t) { return t[0] === ER.tab; })) ER.tab = 'detail';
    var sk = ER._gearStatusKey(b), unpaid = ER._isPendingUnpaid(b);
    var banner = unpaid ? '<section class="edit-rez-card edit-rez-pending-banner"><div class="edit-rez-pending-icon">⏳</div><div class="edit-rez-pending-body"><h3>' +
      MG.t('editRez.pending.title') + '</h3><p>' + MG.t('editRez.pending.text') + '</p></div><div class="edit-rez-pending-actions"><button type="button" class="btn btngreen" id="edit-rez-resume-pay">' +
      MG.t('editRez.pending.payNow') + '</button><button type="button" class="btn btn-secondary" id="edit-rez-cancel-pending">' + MG.t('editRez.pending.cancelNow') + '</button></div></section>' : '';
    c.innerHTML = '<section class="edit-rez-card edit-rez-detail-head"><button type="button" class="btn-link" id="edit-rez-back">← ' + MG.t('editRez.list.title') +
      '</button><h2>' + MG.t('editRez.gearbk.title') + '</h2><div class="edit-rez-detail-meta">' + MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date) +
      ' · <span class="edit-rez-booking-status status-' + (unpaid ? 'pending' : sk) + '">' + MG.t('editRez.status.' + (unpaid ? 'pending' : sk)) + '</span></div></section>' + banner +
      '<nav class="edit-rez-tabs" role="tablist">' + tabs.map(function(t) {
        return '<button type="button" class="edit-rez-tab' + (ER.tab === t[0] ? ' active' : '') + '" data-tab="' + t[0] + '">' + t[1] + '</button>';
      }).join('') + '</nav><section class="edit-rez-card" id="edit-rez-tab-content"></section>';
    document.getElementById('edit-rez-back').addEventListener('click', function() { ER.selectedBooking = null; ER._goto('list'); });
    c.querySelectorAll('.edit-rez-tab').forEach(function(el) {
      el.addEventListener('click', function() { ER.tab = el.getAttribute('data-tab'); ER._renderDetail(); });
    });
    var pay = document.getElementById('edit-rez-resume-pay');
    pay && pay.addEventListener('click', function() { ER._resumePending(b.id); });
    var cp = document.getElementById('edit-rez-cancel-pending');
    cp && cp.addEventListener('click', function() {
      ER._confirmDialog(MG.t('editRez.pending.confirmCancel'), function() { ER._cancelPending(b.id); },
        { yesLabel: MG.t('editRez.pending.confirmYes'), noLabel: MG.t('editRez.pending.confirmNo'), danger: true });
    });
    var map = { detail: '_renderGearDetailTab', move: '_renderTabMove', extend: '_renderTabExtend', shorten: '_renderTabShorten',
      gsizes: '_renderGearSizesTab', gremove: '_renderGearRemoveTab', docs: '_renderTabDocs', cancel: '_renderTabCancel' };
    var fn = ER[map[ER.tab]] || ER._renderGearDetailTab;
    return fn.call(ER);
  }

  var coreDetail = ER._renderDetail;
  ER._renderDetail = function() {
    var b = ER.selectedBooking;
    if (!ER._isGear(b)) return coreDetail.apply(this, arguments);
    ER.selectedMoto = {};
    return renderGearDetail();
  };

  // ---- Záložka Detail ----
  function info(ico, lbl, val, cls) {
    return '<div class="edit-rez-info-item' + (cls ? ' ' + cls : '') + '"><div class="ico">' + ico + '</div><div><div class="lbl">' + lbl + '</div><div class="val">' + val + '</div></div></div>';
  }

  ER._gearLinesHtml = function(b) {
    var n = days(b);
    return '<div class="edit-rez-price-card erez-gear-lines">' + (b.gear_lines || []).map(function(l) {
      var sz = sizesText(l), ppd = Number(l.price_per_day || 0);
      return '<div class="edit-rez-price-row"><span>' + esc(ER._gearLabel(l.key, l.label)) + (sz ? ' <span class="muted">(' + esc(sz) + ')</span>' : '') +
        '<br><small class="muted">' + MG.formatPrice(ppd) + ' × ' + MG._dayLabel(n) + '</small></span><span>' + MG.formatPrice(ppd * n) + '</span></div>';
    }).join('') + (Number(b.discount_amount) > 0 ? '<div class="edit-rez-price-row"><span>🎁 ' + MG.t('editRez.detail.priceDiscount') + '</span><span>−' +
      MG.formatPrice(Number(b.discount_amount)) + '</span></div>' : '') + '<div class="edit-rez-price-row total"><span>' + MG.t('editRez.detail.priceTotal') +
      '</span><span>' + MG.formatPrice(Number(b.total_price || 0)) + '</span></div></div>';
  };

  ER._gearDocsVal = function(b) {
    var d = b.docs;
    if (!d || !d.required) return '';
    if (d.ok) return '✓ ' + MG.t('editRez.gearbk.docsOk');
    return MG.t('editRez.gearbk.docsMissing') + '<br><a class="btn btngreen-small erez-gear-docs-cta" href="/pujceni-obleceni?resume=' +
      encodeURIComponent(b.id) + '&docs=1">' + MG.t('editRez.gearbk.docsCta') + '</a>';
  };

  ER._renderGearDetailTab = function() {
    var b = ER.selectedBooking, el = document.getElementById('edit-rez-tab-content');
    if (!b || !el) return;
    var br = b.branch || {}, ss = ER._gearIsSS(b), n = days(b);
    var place = br.name ? ER._pickupDetail(br, b) : '—';
    var items = ER._gearItems(b).map(function(i) {
      return '<li><span class="gear-key">' + (ICO[i.key] || '•') + ' ' + esc(ER._gearLabel(i.key)) + '</span><span class="gear-val">' + esc(i.size || '—') + '</span></li>';
    }).join('');
    var docs = ER._gearDocsVal(b);
    // brána: branch.has_gate z get_my_gear_bookings; neznámá (starší data) → dotaz níže
    var gate = br.has_gate === true || br.has_gate === false ? br.has_gate : null;
    var how = !ss ? MG.t('editRez.gearbk.howStaffed') : gate === false ? MG.t('editRez.gearbk.howSelfNoGate')
      : MG.t('editRez.gearbk.howSelf') + (gate ? '<br>' + MG.t('editRez.gearbk.gateNotice') : '');
    el.innerHTML = '<div class="edit-rez-detail-grid erez-gear-detail"><div class="edit-rez-detail-gallery"><div class="erez-gear-hero" aria-hidden="true">🧥</div>' +
      '<div class="edit-rez-detail-headline"><h3>' + MG.t('editRez.gearbk.title') + '</h3><span class="edit-rez-chip">' + MG.t('editRez.gearbk.chip') + '</span>' +
      '<div class="edit-rez-detail-id">' + MG.t('editRez.detail.bookingNum') + ' <code>' + esc(num(b)) + '</code></div></div>' +
      '<ul class="edit-rez-gear-list erez-gear-items">' + items + '</ul></div><aside class="edit-rez-detail-side">' +
      info('📅', MG.t('editRez.detail.dateLabel'), MG.formatDate(b.start_date) + ' – ' + MG.formatDate(b.end_date) + ' <span class="muted">(' + MG._dayLabel(n) + ')</span>') +
      info('🕐', MG.t('editRez.detail.timeLabel'), (hm(b.pickup_time) || '—') + ' / ' + (hm(b.return_time) || '—')) +
      info('📍', MG.t('editRez.gearbk.placeLabel'), place) +
      (docs ? info('🪪', MG.t('editRez.gearbk.docsLabel'), docs) : '') +
      info(ss ? '🔑' : 'ℹ️', MG.t('editRez.gearbk.howLabel'), how, 'erez-gear-how') +
      '</aside></div><div class="edit-rez-detail-extras"><h4 class="edit-rez-section-h">💰 ' + MG.t('editRez.detail.priceBreakdown') + '</h4>' +
      ER._gearLinesHtml(b) + '<p class="erez-gear-note">' + MG.t('editRez.gearbk.addItemNote') + '</p>' +
      '<h4 class="edit-rez-section-h">🕘 ' + MG.t('editRez.detail.historyTitle') + '</h4>' + ER._historyHtml(b) + '</div>';
    if (ss && gate === null && b.branch_id && window.sb && !ER._isMockMode) {
      Promise.resolve(window.sb.rpc('branch_has_gate', { p_branch_id: b.branch_id })).then(function(r) {
        var v = el.querySelector('.erez-gear-how .val');
        if (!r || typeof r.data !== 'boolean' || !v || ER.selectedBooking !== b) return;
        if (b.branch) b.branch.has_gate = r.data;
        if (r.data) v.insertAdjacentHTML('beforeend', '<br>' + MG.t('editRez.gearbk.gateNotice'));
        else v.innerHTML = MG.t('editRez.gearbk.howSelfNoGate');
      }).catch(function() {});
    }
  };

  // ---- Doklady: jádro (nahrání OP/pasu, doklady ke stažení) bez řidičáku a moto smlouvy ----
  var coreLic = ER._licSectionHtml;
  ER._licSectionHtml = function() {
    if (ER._isGear(ER.selectedBooking)) { ER._licState = null; return ''; }
    return coreLic ? coreLic.apply(this, arguments) : '';
  };
  var coreSaveLic = ER._saveLic;
  ER._saveLic = async function(force, bk) {
    if (ER._isGear(bk || ER.selectedBooking)) return;
    return coreSaveLic ? coreSaveLic.apply(this, arguments) : undefined;
  };
  var coreGateMsg = ER._gateMsg;
  ER._gateMsg = async function(bk) {
    if (!ER._isGear(bk)) return coreGateMsg.apply(this, arguments);
    try {
      var g = await window.sb.rpc('get_docs_gate_checklist', { p_booking_id: bk.id }), c = g && !g.error && g.data;
      if (!c || c.error || c.ok) return null;
      var m = [];
      if (!c.identity_ok) m.push(MG.t('editRez.doc.gateIdentity'));
      if (!c.date_of_birth) m.push(MG.t('editRez.doc.gateDob'));
      else if (!c.age_ok) m.push(MG.t('editRez.doc.gateAge'));
      return m.length ? MG.t('editRez.doc.gateIntro') + ' ' + m.join(' ') : null;
    } catch (e) { return null; }
  };
  var coreDocs = ER._renderTabDocs;
  ER._renderTabDocs = async function() {
    var b = ER.selectedBooking;
    var r = await coreDocs.apply(this, arguments);
    if (!ER._isGear(b) || ER.selectedBooking !== b) return r;
    var el = document.getElementById('edit-rez-tab-content');
    if (!el) return r;
    var cards = el.querySelectorAll('.edit-rez-upload-card');
    if (cards[1]) cards[1].remove();
    (ER._docRows || []).forEach(function(row, i) {
      if (row && (row.templateType === 'rental_contract' || row.templateType === 'contract') && !row.path && !row.signedHtml) {
        var btn = el.querySelector('[data-row="' + i + '"]');
        var li = btn && btn.closest('li');
        if (li) li.remove();
      }
    });
    return r;
  };
})();
